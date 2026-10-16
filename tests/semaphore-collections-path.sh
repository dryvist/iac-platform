#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="$repo_root/scripts/semaphore-run-ansible.sh"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/project"

cat >"$test_dir/bin/ansible-galaxy" <<'GALAXY'
#!/usr/bin/env bash
[ "$1" = collection ] || exit 0
install_path=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = -p ]; then install_path="$2"; shift 2; else shift; fi
done
printf '%s\n' "$install_path" >"$GALAXY_INSTALL_PATH"
printf '%s\n' "$ANSIBLE_COLLECTIONS_PATH" >"$GALAXY_SEARCH_PATH"
GALAXY
cat >"$test_dir/bin/setsid" <<'SETSID'
#!/usr/bin/env bash
exec "$@"
SETSID
cat >"$test_dir/runner.sh" <<'RUNNER'
#!/usr/bin/env bash
printf '%s\n' "$ANSIBLE_COLLECTIONS_PATH" >"$RUNNER_SEARCH_PATH"
printf 'PLAY RECAP *****\nweb-01 : ok=1 changed=0 unreachable=0 failed=0\n'
RUNNER
chmod +x "$test_dir/bin/ansible-galaxy" "$test_dir/bin/setsid" "$test_dir/runner.sh"
cat >"$test_dir/project/requirements.yml" <<'REQUIREMENTS'
collections:
  - name: community.general
    version: ">=13.5.0,<14.0.0"
REQUIREMENTS

if ! (cd "$test_dir/project" && env -u BAO_ADDR \
  PATH="$test_dir/bin:$PATH" ANSIBLE_COLLECTIONS_PATH=/shared \
  GALAXY_INSTALL_PATH="$test_dir/install-path" \
  GALAXY_SEARCH_PATH="$test_dir/galaxy-search-path" \
  RUNNER_SEARCH_PATH="$test_dir/runner-search-path" \
  bash "$wrapper" "$test_dir/runner.sh") >"$test_dir/output" 2>&1; then
  cat "$test_dir/output"
  exit 1
fi

installed="$(cat "$test_dir/install-path")"
expected="$installed:/shared"
if [ -n "$installed" ] \
  && [ "$(cat "$test_dir/galaxy-search-path")" = "$expected" ] \
  && [ "$(cat "$test_dir/runner-search-path")" = "$expected" ] \
  && [ ! -e "$installed" ]; then
  echo "ok   Galaxy installs into the first active collection path used by the playbook"
else
  echo "FAIL Galaxy and the playbook must use the same leading collection path"
  cat "$test_dir/output"
  exit 1
fi
