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

exit "$FAIL"
