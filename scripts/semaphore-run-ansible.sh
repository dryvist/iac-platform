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
# Usage: semaphore-run-ansible.sh <run-ansible.sh> <playbook> [args...]
set -euo pipefail

[ "$#" -ge 1 ] || { echo "usage: semaphore-run-ansible.sh <run-ansible.sh> [args...]" >&2; exit 2; }

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
    *) run_args+=("$arg") ;;
  esac
done

csv_to_json_ints() {
  local csv="$1" result="" value
  local -a values
  IFS=',' read -r -a values <<< "$csv"
  for value in "${values[@]}"; do
    result+="${value},"
  done
  printf '[%s]' "${result%,}"
}

if [ "$benchmark_seen" -eq 1 ]; then
  [ -n "$benchmark_config" ] || { echo "semaphore-run-ansible.sh: missing config_name survey variable" >&2; exit 2; }
  [ -n "$benchmark_machine" ] || { echo "semaphore-run-ansible.sh: missing machine survey variable" >&2; exit 2; }
  [ -n "$benchmark_engine" ] || { echo "semaphore-run-ansible.sh: missing engine survey variable" >&2; exit 2; }
  [ -n "$benchmark_model_size" ] || { echo "semaphore-run-ansible.sh: missing model_size survey variable" >&2; exit 2; }
  [ -n "$benchmark_concurrency_list" ] || { echo "semaphore-run-ansible.sh: missing concurrency_list survey variable" >&2; exit 2; }
  [ -n "$benchmark_context_list" ] || { echo "semaphore-run-ansible.sh: missing context_list survey variable" >&2; exit 2; }
  [ -n "$benchmark_power_cap_w" ] || { echo "semaphore-run-ansible.sh: missing power_cap_w survey variable (use 0 for no cap)" >&2; exit 2; }

  case "$benchmark_config" in
    llama-cpp/cross-card|vllm/cross-card|mlx/cross-card|lm-eval/quick-intelligence) ;;
    *) echo "semaphore-run-ansible.sh: invalid config_name survey value" >&2; exit 2 ;;
  esac
  [[ "$benchmark_machine" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || {
    echo "semaphore-run-ansible.sh: machine must be an inventory alias, not a hostname or address" >&2
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
  power_cap_json="$(awk -v cap="$benchmark_power_cap_w" 'BEGIN { if (cap == 0) print "null"; else print cap }')"

  benchmark_json="$(printf '{\"llm_benchmark_config\":\"%s\",\"llm_benchmark_machine\":\"%s\",\"llm_benchmark_engine\":\"%s\",\"llm_benchmark_model_size\":\"%s\",\"llm_benchmark_concurrency_list\":%s,\"llm_benchmark_context_list\":%s,\"llm_benchmark_power_cap_w\":%s}' \
    "$benchmark_config" "$benchmark_machine" "$benchmark_engine" "$benchmark_model_size" \
    "$(csv_to_json_ints "$benchmark_concurrency_list")" \
    "$(csv_to_json_ints "$benchmark_context_list")" "$power_cap_json")"
  run_args+=(--extra-vars "$benchmark_json")
fi

if [ -n "$active_profile" ]; then
  run_args+=(--extra-vars "llm_active_profile=$active_profile")
fi

if [ -f requirements.yml ]; then
  echo "Installing Ansible requirements..."
  ansible-galaxy install -r requirements.yml --roles-path roles || true
  ansible-galaxy collection install -r requirements.yml || true
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

set +e
"${run_args[@]}" 2>&1 | tee "$log"
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
