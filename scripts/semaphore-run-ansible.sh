#!/usr/bin/env bash
# Semaphore template wrapper around the certificate-signed ansible runner
# (ansible-proxmox's scripts/run-ansible.sh — do not edit that script from
# here; the ansible-proxmox* repos likely carry their own copy and are
# covered by Vikunja 1843, not by this wrapper). Tracked bug, Vikunja 1843:
# run-ansible.sh can exit 0 on a run interrupted mid-play and then claims the
# run did nothing, even when hundreds of tasks actually ran. This wrapper
# tees the run's output and applies the PLAY RECAP instead of trusting the
# wrapped command's exit code:
#
#   1. No PLAY RECAP at all -> exit non-zero. Run state is UNKNOWN (not
#      "failed", not "did nothing") and must not be treated as applied.
#   2. A recap exists and any host shows failed>0 or unreachable>0 -> exit
#      non-zero.
#   3. A recap exists and the ONLY host in it is localhost (the real target
#      host never ran — the `--limit ...,localhost` footgun) -> exit
#      non-zero. This heuristic is evaluated ONLY when a recap exists;
#      absence of a recap is always rule 1, never this rule — conflating the
#      two is the other half of the upstream bug. A caller whose `--limit` is
#      exactly `localhost` asked for that recap on purpose (a localhost-only
#      play, such as a read-only report) and is exempt from this rule alone.
#   4. Recap exists, covers a real host, no failures -> exit with the
#      wrapped command's own exit code.
#
# Task rail: every run is bounded to 900 seconds, counted from the first entry
# into this script. The OpenBao env export and the collection install are
# charged to that budget, though only the playbook run itself is stopped by
# it, and it is what is left at that point. Semaphore's MaxTaskDurationSec is one
# server-wide value and cannot be set per template, so the bound is enforced
# here; the server value is the ceiling. The playbook budget gate reads
# SEMAPHORE_MAX_TASK_DURATION_SEC, which this script sets to the seconds left.
#
# A template raises its allowance with --rail-sec=N as its FIRST argument, and
# that is the only place it is honoured. Anywhere else it is refused, because a
# task override can put text after the template's arguments but not before them.
#
# Usage: semaphore-run-ansible.sh [--rail-sec=N] <run-ansible.sh> <playbook> [args...]
set -euo pipefail

[ "$#" -ge 1 ] || { echo "usage: semaphore-run-ansible.sh [--rail-sec=N] <run-ansible.sh> [args...]" >&2; exit 2; }

# Starts the task clock once. The re-exec below keeps it, because the marker is
# exported, not reset; a shell that wants a fresh clock must unset it first.
export SEMAPHORE_RAIL_STARTED="${SEMAPHORE_RAIL_STARTED:-$(date +%s)}"

# The run environment. The playbooks read plain environment variables and know
# nothing about where they came from; this is the one place that fills them in.
# Three KV documents, one per mount, so every value lives on exactly one tier:
# topology in config/, internal-only secrets on the internal mount, anything
# reachable from the public internet in secrets-external/. Re-exec through the
# exporter once; the marker stops the second entry from doing it again.
if [ -z "${SEMAPHORE_RUN_ENV_LOADED:-}" ] && [ -n "${BAO_ADDR:-}" ]; then
  export SEMAPHORE_RUN_ENV_LOADED=1
  exec openbao-exec-env.sh config/platform/ansible/env -- \
    openbao-exec-env.sh secret/platform/ansible/env -- \
    openbao-exec-env.sh secrets-external/platform/ansible/env -- \
    bash "$0" "$@"
fi

# Semaphore builds a shell task's arguments in this order: the script, the
# environment secrets, the template's own arguments, the environment-derived
# name=value pairs, then the task's overrides (upstream services/tasks,
# getShellArgs). The task's overrides and the name=value pairs come after the
# template's own arguments, so only the template can put --rail-sec first. An
# environment secret, set by an administrator, comes before it; if one were
# present the flag would not be first and the run would fail closed.
rail_sec=""
if [[ "${1:-}" == --rail-sec=* ]]; then
  rail_sec="${1#--rail-sec=}"
  shift
  [[ "$rail_sec" =~ ^[1-9][0-9]*$ ]] || { echo "semaphore-run-ansible.sh: --rail-sec must be a positive whole number of seconds" >&2; exit 2; }
  [ "$#" -ge 1 ] || { echo "usage: semaphore-run-ansible.sh [--rail-sec=N] <run-ansible.sh> [args...]" >&2; exit 2; }
fi

# Semaphore's bash templates append survey variables as name=value script
# arguments. Translate the profile selector into the Ansible extra-var expected
# by the site playbook. Benchmark survey values are validated here, encoded as
# JSON (including numeric lists), and validated against the selected config by
# its playbook before any benchmark command runs.
run_args=()
active_profile=""
benchmark_seen=0
benchmark_config=""
benchmark_machine=""
benchmark_engine=""
benchmark_model_size=""
benchmark_concurrency_list=""
benchmark_context_list=""
benchmark_power_cap_w=""
benchmark_endpoint_root=""
benchmark_cache_path=""

survey_value() {
  local name="$1" value="$2" current="$3"
  [ -z "$current" ] || { echo "semaphore-run-ansible.sh: duplicate $name survey variable" >&2; exit 2; }
  [ -n "$value" ] || { echo "semaphore-run-ansible.sh: empty $name survey value" >&2; exit 2; }
}

for arg in "$@"; do
  case "$arg" in
    llm_active_profile=*)
      [ -z "$active_profile" ] || { echo "semaphore-run-ansible.sh: duplicate llm_active_profile survey variable" >&2; exit 2; }
      active_profile="${arg#*=}"
      case "$active_profile" in
        small|medium-a|medium-b|max) ;;
        *) echo "semaphore-run-ansible.sh: invalid llm_active_profile survey value" >&2; exit 2 ;;
      esac
      ;;
    config_name=*)
      benchmark_seen=1
      value="${arg#*=}"
      survey_value config_name "$value" "$benchmark_config"
      benchmark_config="$value"
      ;;
    machine=*)
      benchmark_seen=1
      value="${arg#*=}"
      survey_value machine "$value" "$benchmark_machine"
      benchmark_machine="$value"
      ;;
    benchmark_endpoint_root=*)
      benchmark_seen=1
      value="${arg#*=}"
      survey_value benchmark_endpoint_root "$value" "$benchmark_endpoint_root"
      benchmark_endpoint_root="$value"
      ;;
    benchmark_cache_path=*)
      benchmark_seen=1
      value="${arg#*=}"
      survey_value benchmark_cache_path "$value" "$benchmark_cache_path"
      benchmark_cache_path="$value"
      ;;
    engine=*)
      benchmark_seen=1
      value="${arg#*=}"
      survey_value engine "$value" "$benchmark_engine"
      benchmark_engine="$value"
      ;;
    model_size=*)
      benchmark_seen=1
      value="${arg#*=}"
      survey_value model_size "$value" "$benchmark_model_size"
      benchmark_model_size="$value"
      ;;
    concurrency_list=*)
      benchmark_seen=1
      value="${arg#*=}"
      survey_value concurrency_list "$value" "$benchmark_concurrency_list"
      benchmark_concurrency_list="$value"
      ;;
    context_list=*)
      benchmark_seen=1
      value="${arg#*=}"
      survey_value context_list "$value" "$benchmark_context_list"
      benchmark_context_list="$value"
      ;;
    power_cap_w=*)
      benchmark_seen=1
      value="${arg#*=}"
      survey_value power_cap_w "$value" "$benchmark_power_cap_w"
      benchmark_power_cap_w="$value"
      ;;
    --rail-sec|--rail-sec=*)
      echo "semaphore-run-ansible.sh: --rail-sec is honoured only as the first argument, set by the template" >&2
      exit 2
      ;;
    *) run_args+=("$arg") ;;
  esac
done
rail_sec="${rail_sec:-900}"

if [ "$benchmark_seen" -eq 1 ]; then
  [ -n "$benchmark_config" ] || { echo "semaphore-run-ansible.sh: missing config_name survey variable" >&2; exit 2; }
  [ -n "$benchmark_machine" ] || { echo "semaphore-run-ansible.sh: missing machine survey variable" >&2; exit 2; }
  [ -n "$benchmark_engine" ] || { echo "semaphore-run-ansible.sh: missing engine survey variable" >&2; exit 2; }
  [ -n "$benchmark_model_size" ] || { echo "semaphore-run-ansible.sh: missing model_size survey variable" >&2; exit 2; }
  [ -n "$benchmark_concurrency_list" ] || { echo "semaphore-run-ansible.sh: missing concurrency_list survey variable" >&2; exit 2; }
  [ -n "$benchmark_context_list" ] || { echo "semaphore-run-ansible.sh: missing context_list survey variable" >&2; exit 2; }
  [ -n "$benchmark_power_cap_w" ] || { echo "semaphore-run-ansible.sh: missing power_cap_w survey variable (use 0 for no cap)" >&2; exit 2; }
  [ -n "$benchmark_endpoint_root" ] || { echo "semaphore-run-ansible.sh: missing benchmark_endpoint_root survey variable" >&2; exit 2; }
  [ -n "$benchmark_cache_path" ] || { echo "semaphore-run-ansible.sh: missing benchmark_cache_path survey variable" >&2; exit 2; }

  case "$benchmark_config" in
    llama-cpp/cross-card|vllm/cross-card|mlx/cross-card) ;;
    lm-eval/quick-intelligence|lm-eval/gpqa-diamond|evalscope/livecodebench) ;;
    *) echo "semaphore-run-ansible.sh: invalid config_name survey value" >&2; exit 2 ;;
  esac
  [[ "$benchmark_machine" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || {
    echo "semaphore-run-ansible.sh: machine must be an inventory alias, not a hostname or address" >&2
    exit 2
  }
  [[ "$benchmark_endpoint_root" =~ ^https://[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]] || {
    echo "semaphore-run-ansible.sh: benchmark_endpoint_root must be an HTTPS inventory FQDN origin" >&2
    exit 2
  }
  [[ "$benchmark_cache_path" == /* && "$benchmark_cache_path" != *$'\n'* && "$benchmark_cache_path" != *$'\r'* ]] || {
    echo "semaphore-run-ansible.sh: benchmark_cache_path must be an absolute target path" >&2
    exit 2
  }
  [[ ! "$benchmark_cache_path" =~ (^|/)\.\.(/|$) ]] || {
    echo "semaphore-run-ansible.sh: benchmark_cache_path must not traverse parent directories" >&2
    exit 2
  }
  for value in "$benchmark_engine" "$benchmark_model_size"; do
    [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || {
      echo "semaphore-run-ansible.sh: engine and model_size must be simple selectors" >&2
      exit 2
    }
  done
  [[ "$benchmark_concurrency_list" =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]] || {
    echo "semaphore-run-ansible.sh: concurrency_list must be comma-separated positive integers" >&2
    exit 2
  }
  [[ "$benchmark_context_list" =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]] || {
    echo "semaphore-run-ansible.sh: context_list must be comma-separated positive token counts" >&2
    exit 2
  }
  [[ "$benchmark_power_cap_w" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
    echo "semaphore-run-ansible.sh: power_cap_w must be a non-negative number; use 0 for no cap" >&2
    exit 2
  }
  benchmark_json="$(jq -cn \
    --arg config_name "$benchmark_config" \
    --arg machine "$benchmark_machine" \
    --arg engine "$benchmark_engine" \
    --arg model_size "$benchmark_model_size" \
    --arg concurrency_list "$benchmark_concurrency_list" \
    --arg context_list "$benchmark_context_list" \
    --arg power_cap_w "$benchmark_power_cap_w" \
    --arg benchmark_endpoint_root "$benchmark_endpoint_root" \
    --arg benchmark_cache_path "$benchmark_cache_path" \
    '{config_name: $config_name, machine: $machine, engine: $engine, model_size: $model_size,
      concurrency_list: $concurrency_list, context_list: $context_list, power_cap_w: $power_cap_w,
      benchmark_endpoint_root: $benchmark_endpoint_root, benchmark_cache_path: $benchmark_cache_path}')"
  run_args+=(--extra-vars "$benchmark_json")
fi

if [ -n "$active_profile" ]; then
  run_args+=(--extra-vars "llm_active_profile=$active_profile")
fi

log="$(mktemp)"
run_collections=""
trap 'rm -rf "$log" "$run_collections"' EXIT

# Collections install into a directory private to this run and lead the search
# path. The runner's shared ~/.ansible/collections is mutated by every template
# that runs there, each with its own pin, and `ansible-galaxy collection install`
# skips an installed name:version, so a git-pinned collection (version unchanged
# between commits) could be left stale or half-replaced by a concurrent run. A
# private directory always holds exactly this run's pins, and a failed install
# stops the run instead of leaving whatever was there.
if [ -f requirements.yml ]; then
  echo "Installing Ansible requirements..."
  run_collections="$(mktemp -d)"
  ansible-galaxy install -r requirements.yml --roles-path roles || true
  ansible-galaxy collection install -r requirements.yml -p "$run_collections"
  export ANSIBLE_COLLECTIONS_PATH="$run_collections${ANSIBLE_COLLECTIONS_PATH:+:$ANSIBLE_COLLECTIONS_PATH}"
fi

# Runs the command in a session of its own and stops that whole session when the
# seconds run out. timeout(1) in the image signals only its direct child, and
# ansible's own children keep the output pipe open, so the rail signals the
# session's process group instead. A run stopped this way has no PLAY RECAP and
# fails by rule 1.
run_in_rail() {
  local seconds="$1" run rail status=0
  shift
  setsid "$@" &
  run=$!
  ( sleep "$seconds" && kill -TERM -- "-$run" ) >/dev/null 2>&1 &
  rail=$!
  wait "$run" || status=$?
  kill "$rail" 2>/dev/null || true
  return "$status"
}

# What is left of the rail is the run's whole budget: the playbook gate reads it,
# and run_in_rail enforces it. Nothing has run yet if none is left.
rail_left=$(( rail_sec - ( $(date +%s) - SEMAPHORE_RAIL_STARTED ) ))
[ "$rail_left" -gt 0 ] || { echo "semaphore-run-ansible.sh: the ${rail_sec}s task rail was spent before the playbook started; nothing was run" >&2; exit 1; }
export SEMAPHORE_MAX_TASK_DURATION_SEC="$rail_left"

set +e
run_in_rail "$rail_left" "${run_args[@]}" 2>&1 | tee "$log"
rc="${PIPESTATUS[0]}"
set -e

# Recap host lines look like: "hostname : ok=5 changed=2 unreachable=0 failed=0 ..."
recap_lines="$(grep -E '^\S+\s*:\s*ok=' "$log" || true)"

if [ -z "$recap_lines" ]; then
  echo "semaphore-run-ansible.sh: no PLAY RECAP in output — run state is UNKNOWN, do not treat as applied (wrapped command's own rc was $rc)" >&2
  exit 1
fi

if grep -qE 'unreachable=[1-9][0-9]*|failed=[1-9][0-9]*' <<<"$recap_lines"; then
  echo "semaphore-run-ansible.sh: PLAY RECAP shows a failed or unreachable host:" >&2
  echo "$recap_lines" >&2
  exit 1
fi

limit=""
prev=""
for a in "${run_args[@]}"; do
  { [ "$prev" = "--limit" ] || [ "$prev" = "-l" ]; } && limit="$a"
  case "$a" in --limit=*) limit="${a#--limit=}" ;; esac
  prev="$a"
done
hosts="$(awk -F' *: *' '{print $1}' <<<"$recap_lines" | sort -u)"
if [ "$hosts" = "localhost" ] && [ "$limit" != "localhost" ]; then
  echo "semaphore-run-ansible.sh: PLAY RECAP only covers localhost — the real target host(s) never ran (check --limit includes them, not just localhost)" >&2
  exit 1
fi

exit "$rc"
