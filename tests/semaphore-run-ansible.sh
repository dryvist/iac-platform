#!/usr/bin/env bash
# Covers the PLAY RECAP rules in scripts/semaphore-run-ansible.sh with a stub
# runner that prints whatever recap a case hands it. No network: BAO_ADDR is
# unset so the run-environment re-exec is skipped, and the stub cwd carries no
# requirements.yml.
#
# Usage: tests/semaphore-run-ansible.sh   (exit 0 = all cases pass)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO_ROOT/scripts/semaphore-run-ansible.sh"
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT
STUB_ARGS="$STUB_DIR/args"
export STUB_ARGS
FAIL=0

# A runner that ignores its arguments and prints the recap in $STUB_RECAP.
cat >"$STUB_DIR/run-ansible.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$STUB_ARGS"
printf 'PLAY RECAP *****\n%b\n' "$STUB_RECAP"
STUB
chmod +x "$STUB_DIR/run-ansible.sh"

check() { # name expected-status recap wrapper-args...
  local name="$1" want_rc="$2" recap="$3"
  shift 3
  local rc
  (cd "$STUB_DIR" && env -u BAO_ADDR STUB_RECAP="$recap" bash "$WRAPPER" ./run-ansible.sh "$@") >/dev/null 2>&1
  rc=$?
  if [ "$rc" != "$want_rc" ]; then
    echo "FAIL $name (exit $rc, wanted $want_rc)"
    FAIL=1
    return
  fi
  echo "ok   $name"
}

real='localhost : ok=3 changed=0 unreachable=0 failed=0\nweb-01 : ok=9 changed=1 unreachable=0 failed=0'
only_local='localhost : ok=3 changed=0 unreachable=0 failed=0'

echo "== semaphore-run-ansible.sh recap rules =="
check "a real host in the recap passes" 0 "$real" playbooks/site.yml --limit web_group,localhost
check "a failed host fails" 1 'web-01 : ok=2 changed=0 unreachable=0 failed=1' playbooks/site.yml --limit web_group,localhost
check "an unreachable host fails" 1 'web-01 : ok=0 changed=0 unreachable=1 failed=0' playbooks/site.yml --limit web_group,localhost
check "no recap at all fails" 1 '' playbooks/site.yml --limit web_group,localhost
check "localhost-only recap fails when hosts were asked for" 1 "$only_local" playbooks/site.yml --limit web_group,localhost
check "localhost-only recap fails when no limit was given" 1 "$only_local" playbooks/site.yml
check "localhost-only recap passes when the limit is exactly localhost" 0 "$only_local" playbooks/report.yml --limit localhost
check "  ...also in --limit=localhost form" 0 "$only_local" playbooks/report.yml --limit=localhost
check "profile survey value is passed as an Ansible extra var" 0 "$real" playbooks/site.yml --limit web_group,localhost llm_active_profile=medium-b
cat >"$STUB_DIR/expected-args" <<'EXPECTED'
playbooks/site.yml
--limit
web_group,localhost
--extra-vars
llm_active_profile=medium-b
EXPECTED
if diff -u "$STUB_DIR/expected-args" "$STUB_ARGS" >/dev/null; then
  echo "ok   profile survey value uses the expected extra var"
else
  echo "FAIL profile survey value uses the expected extra var"
  diff -u "$STUB_DIR/expected-args" "$STUB_ARGS"
  FAIL=1
fi
check "invalid profile survey value fails" 2 "$real" playbooks/site.yml --limit web_group,localhost llm_active_profile=unknown

# The ai-llm-profile template's own tags, limit and profile choices are read from
# the catalog, so the dropdown, its scope and the wrapper's allow-list cannot drift.
# The template converges the serving role and the router for the chosen profile.
profile_block="$(awk '/^    ai-llm-profile = \{/,/description = "Select the active LLM GPU serving profile and/' "$REPO_ROOT/tofu/semaphore/templates-catalog-ai.tf")"
profile_tags="$(sed -n 's/^ *tags *= *"\(.*\)"$/\1/p' <<<"$profile_block")"
profile_limit="$(sed -n 's/^ *limit *= *"\(.*\)"$/\1/p' <<<"$profile_block")"
if [ "$profile_tags" = "llm_gpu_serving,llm_router" ]; then
  echo "ok   ai-llm-profile template runs both the serving role and the router tags"
else
  echo "FAIL ai-llm-profile template tags are '$profile_tags'"
  FAIL=1
fi
for group in llm_gpu_group llm_router_group; do
  if [[ ",$profile_limit," == *",$group,"* ]]; then
    echo "ok   ai-llm-profile template limit covers $group"
  else
    echo "FAIL ai-llm-profile template limit '$profile_limit' misses $group"
    FAIL=1
  fi
done
if [[ "$profile_limit" == *localhost* ]]; then
  echo "FAIL ai-llm-profile template limit names localhost; the argument list appends it"
  FAIL=1
fi
profile_count=0
while IFS= read -r profile; do
  profile_count=$((profile_count + 1))
  check "profile $profile from the dropdown is accepted with the template's tags and limit" 0 "$real" \
    playbooks/site.yml --tags "$profile_tags" --limit "$profile_limit,localhost" --diff "llm_active_profile=$profile"
  printf '%s\n' playbooks/site.yml --tags "$profile_tags" --limit "$profile_limit,localhost" --diff \
    --extra-vars "llm_active_profile=$profile" >"$STUB_DIR/expected-args"
  if diff -u "$STUB_DIR/expected-args" "$STUB_ARGS" >/dev/null; then
    echo "ok   profile $profile reaches Ansible as an extra var beside the tags and limit"
  else
    echo "FAIL profile $profile reaches Ansible as an extra var beside the tags and limit"
    diff -u "$STUB_DIR/expected-args" "$STUB_ARGS"
    FAIL=1
  fi
done < <(sed -n 's/^ *"\{0,1\}\([a-z-]*\)"\{0,1\} *= *"\([a-z-]*\)"$/\2/p' <<<"$(sed -n '/enum_values = {/,/}/p' <<<"$profile_block")")
if [ "$profile_count" -ne 4 ]; then
  echo "FAIL the profile dropdown offers $profile_count profiles, wanted 4"
  FAIL=1
fi

check "benchmark survey parameters are accepted" 0 "$real" playbooks/llm-model-campaign.yml \
  config_name=mlx/cross-card machine=benchmark_target engine=mlx_lm model_size=small \
  concurrency_list=1,2 context_list=8192 power_cap_w=0 \
  benchmark_endpoint_root=https://benchmark-target.invalid benchmark_cache_path=/MODEL_CACHE
benchmark_json="$(tail -n 1 "$STUB_ARGS")"
if printf '%s' "$benchmark_json" | jq -e \
  '.benchmark_endpoint_root == "https://benchmark-target.invalid" and
   .benchmark_cache_path == "/MODEL_CACHE" and .power_cap_w == "0"' >/dev/null; then
  echo "ok   benchmark endpoint, cache and power values are passed as parameters"
else
  echo "FAIL benchmark endpoint, cache and power values are passed as parameters"
  FAIL=1
fi

check "benchmark survey requires an endpoint and cache parameter" 2 "$real" \
  playbooks/llm-model-campaign.yml config_name=mlx/cross-card machine=benchmark_target \
  engine=mlx_lm model_size=small concurrency_list=1 context_list=8192 power_cap_w=0

# Every config the template offers must pass the wrapper's allow-list. The names are
# read from the template catalog so the survey enum and the allow-list cannot drift.
catalog_count=0
while IFS= read -r config; do
  catalog_count=$((catalog_count + 1))
  check "benchmark config $config from the catalog is accepted" 0 "$real" playbooks/llm-model-campaign.yml \
    config_name="$config" machine=benchmark_target engine=vllm model_size=small \
    concurrency_list=1,2,4,8 context_list=65536 power_cap_w=0 \
    benchmark_endpoint_root=https://benchmark-target.invalid benchmark_cache_path=/MODEL_CACHE
done < <(grep -oE '"[a-z-]+/[a-z0-9-]+" += "[a-z-]+/[a-z0-9-]+"' "$REPO_ROOT/tofu/semaphore/templates-catalog-ai.tf" | cut -d'"' -f2)
if [ "$catalog_count" -lt 1 ]; then
  echo "FAIL the template catalog lists no benchmark configs"
  FAIL=1
fi
check "a benchmark config outside the catalog is rejected" 2 "$real" playbooks/llm-model-campaign.yml \
  config_name=lm-eval/unlisted machine=benchmark_target engine=vllm model_size=small \
  concurrency_list=1 context_list=8192 power_cap_w=0 \
  benchmark_endpoint_root=https://benchmark-target.invalid benchmark_cache_path=/MODEL_CACHE

# Collections install into a per-run directory that leads ANSIBLE_COLLECTIONS_PATH,
# so a concurrent run's different pin in a shared directory cannot reach this run.
GALAXY_DIR="$STUB_DIR/galaxy-bin"
mkdir -p "$GALAXY_DIR" "$STUB_DIR/req"
cat >"$GALAXY_DIR/ansible-galaxy" <<'GALAXY'
#!/usr/bin/env bash
if [ "$1" = collection ]; then
  [ "${GALAXY_FAIL:-}" = 1 ] && exit 1
  while [ "$#" -gt 0 ]; do [ "$1" = -p ] && printf '%s\n' "$2" >"$GALAXY_LOG"; shift; done
fi
exit 0
GALAXY
chmod +x "$GALAXY_DIR/ansible-galaxy"
cat >"$STUB_DIR/env-runner.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$ANSIBLE_COLLECTIONS_PATH" >"$PATH_LOG"
printf 'PLAY RECAP *****\nweb-01 : ok=1 changed=0 unreachable=0 failed=0\n'
STUB
chmod +x "$STUB_DIR/env-runner.sh"
: >"$STUB_DIR/req/requirements.yml"
export GALAXY_LOG="$STUB_DIR/galaxy-dir" PATH_LOG="$STUB_DIR/path-seen"
(cd "$STUB_DIR/req" && env -u BAO_ADDR PATH="$GALAXY_DIR:$PATH" ANSIBLE_COLLECTIONS_PATH=/shared bash "$WRAPPER" "$STUB_DIR/env-runner.sh") >/dev/null 2>&1
installed="$(cat "$GALAXY_LOG" 2>/dev/null)"
seen="$(cat "$PATH_LOG" 2>/dev/null)"
if [ -n "$installed" ] && [ "$seen" = "$installed:/shared" ] && [ ! -e "$installed" ]; then
  echo "ok   collections install privately, lead the search path, and are removed after the run"
else
  echo "FAIL collections install privately, lead the search path, and are removed after the run (installed=$installed seen=$seen)"
  FAIL=1
fi
if (cd "$STUB_DIR/req" && env -u BAO_ADDR GALAXY_FAIL=1 PATH="$GALAXY_DIR:$PATH" bash "$WRAPPER" "$STUB_DIR/env-runner.sh") >/dev/null 2>&1; then
  echo "FAIL a failed collection install stops the run"
  FAIL=1
else
  echo "ok   a failed collection install stops the run"
fi

# Task rail: 900 seconds by default, --rail-sec=N raises one template's allowance,
# the clock starts at the wrapper's first entry, and the playbook gate is handed
# the seconds left. The stub records that budget next to its arguments.
echo "== task rail =="
RAIL_DIR="$STUB_DIR/rail"
mkdir -p "$RAIL_DIR"
cat >"$RAIL_DIR/run-ansible.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$STUB_ARGS"
printf '%s\n' "${SEMAPHORE_MAX_TASK_DURATION_SEC:-unset}" >"$STUB_ARGS.budget"
[ -z "${STUB_SLEEP:-}" ] || sleep "$STUB_SLEEP"
printf 'PLAY RECAP *****\nweb-01 : ok=1 changed=0 unreachable=0 failed=0\n'
STUB
chmod +x "$RAIL_DIR/run-ansible.sh"

rail_run() { # [--rail-sec=N] then the wrapper's other arguments; the caller sets the clock and stub env
  local rail=()
  if [[ "${1:-}" == --rail-sec=* ]]; then rail=("$1"); shift; fi
  (cd "$RAIL_DIR" && env -u BAO_ADDR bash "$WRAPPER" "${rail[@]}" ./run-ansible.sh "$@") >/dev/null 2>&1
}
budget_between() { # min max: the stub's recorded budget is an integer in range
  local b
  b="$(cat "$STUB_ARGS.budget" 2>/dev/null || true)"
  [[ "$b" =~ ^[0-9]+$ ]] && [ "$b" -ge "$1" ] && [ "$b" -le "$2" ]
}
rail_report() { # name passed(0/1)
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; FAIL=1; fi
}

unset SEMAPHORE_RAIL_STARTED STUB_SLEEP
rm -f "$STUB_ARGS" "$STUB_ARGS.budget"
rail_run playbooks/site.yml --limit web_group,localhost; rc=$?
ok=1
if [ "$rc" -eq 0 ] && budget_between 890 900 && ! grep -q -- '--rail-sec' "$STUB_ARGS"; then ok=0; fi
rail_report "a run with no --rail-sec gets the 900-second rail" "$ok"

rm -f "$STUB_ARGS" "$STUB_ARGS.budget"
rail_run --rail-sec=3600 playbooks/site.yml --limit web_group,localhost; rc=$?
ok=1
if [ "$rc" -eq 0 ] && budget_between 3590 3600 && ! grep -q -- '--rail-sec' "$STUB_ARGS"; then ok=0; fi
rail_report "--rail-sec=3600 raises the allowance and is not passed to Ansible" "$ok"

for bad in --rail-sec=soon --rail-sec=0 --rail-sec=-5; do
  rail_run "$bad" playbooks/site.yml --limit web_group,localhost; rc=$?
  ok=1
  if [ "$rc" -eq 2 ]; then ok=0; fi
  rail_report "$bad is refused" "$ok"
done
rail_run --rail-sec=900 --rail-sec=3600 playbooks/site.yml --limit web_group,localhost; rc=$?
ok=1
if [ "$rc" -eq 2 ]; then ok=0; fi
rail_report "a repeated --rail-sec is refused" "$ok"

# Task overrides and name=value pairs are appended after the template's own
# arguments, so a --rail-sec found anywhere but first is a task's attempt to raise
# the rail. It must be refused before the run starts, whatever its position.
rm -f "$STUB_ARGS" "$STUB_ARGS.budget"
rail_run playbooks/site.yml --limit web_group,localhost --rail-sec=3600; rc=$?
ok=1
if [ "$rc" -eq 2 ] && [ ! -e "$STUB_ARGS" ]; then ok=0; fi
rail_report "an appended --rail-sec=3600 after the playbook does not raise the rail and runs nothing" "$ok"

rm -f "$STUB_ARGS" "$STUB_ARGS.budget"
rail_run --rail-sec=900 playbooks/site.yml --limit web_group,localhost --rail-sec=3600; rc=$?
ok=1
if [ "$rc" -eq 2 ] && [ ! -e "$STUB_ARGS" ]; then ok=0; fi
rail_report "an appended --rail-sec=3600 after a template's own 900 is refused and runs nothing" "$ok"

rm -f "$STUB_ARGS" "$STUB_ARGS.budget"
rail_run playbooks/site.yml --rail-sec=3600 --limit web_group,localhost; rc=$?
ok=1
if [ "$rc" -eq 2 ] && [ ! -e "$STUB_ARGS" ]; then ok=0; fi
rail_report "an interior --rail-sec=3600 is refused and runs nothing" "$ok"

rm -f "$STUB_ARGS" "$STUB_ARGS.budget"
rail_run playbooks/site.yml --limit web_group,localhost --rail-sec; rc=$?
ok=1
if [ "$rc" -eq 2 ] && [ ! -e "$STUB_ARGS" ]; then ok=0; fi
rail_report "a bare --rail-sec is refused and runs nothing" "$ok"

rm -f "$STUB_ARGS" "$STUB_ARGS.budget"
(cd "$RAIL_DIR" && env -u BAO_ADDR bash "$WRAPPER" --rail-sec=3600) >/dev/null 2>&1; rc=$?
ok=1
if [ "$rc" -eq 2 ] && [ ! -e "$STUB_ARGS" ]; then ok=0; fi
rail_report "a first --rail-sec with no script or playbook is refused" "$ok"

export SEMAPHORE_RAIL_STARTED=$(( $(date +%s) - 890 ))
rm -f "$STUB_ARGS" "$STUB_ARGS.budget"
rail_run playbooks/site.yml --limit web_group,localhost; rc=$?
ok=1
if [ "$rc" -eq 0 ] && budget_between 1 11; then ok=0; fi
rail_report "the clock is inherited, so the budget left is what remains of the rail" "$ok"

export SEMAPHORE_RAIL_STARTED=$(( $(date +%s) - 1000 ))
rm -f "$STUB_ARGS" "$STUB_ARGS.budget"
rail_run playbooks/site.yml --limit web_group,localhost; rc=$?
ok=1
if [ "$rc" -eq 1 ] && [ ! -e "$STUB_ARGS" ]; then ok=0; fi
rail_report "a rail spent before the playbook starts runs nothing and fails" "$ok"
unset SEMAPHORE_RAIL_STARTED

# The stub's sleep is a grandchild that would hold the output pipe for 3 seconds;
# finishing inside 2 seconds shows the rail took the whole session, not the stub only.
export STUB_SLEEP=3
rail_start=$SECONDS
rail_run --rail-sec=1 playbooks/site.yml --limit web_group,localhost; rc=$?
rail_elapsed=$((SECONDS - rail_start))
unset STUB_SLEEP
ok=1
if [ "$rc" -eq 1 ] && [ "$rail_elapsed" -le 2 ]; then ok=0; fi
rail_report "a run that outlives its rail fails at the rail, grandchildren included" "$ok"

exit "$FAIL"
