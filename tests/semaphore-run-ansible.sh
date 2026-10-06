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

exit "$FAIL"
