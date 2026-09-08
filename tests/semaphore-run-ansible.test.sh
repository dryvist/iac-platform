#!/usr/bin/env bash
# Offline checks for the wrapper's host-key preflight. Nothing here runs
# Ansible or contacts anything: the wrapped command is a stub that prints a
# clean recap, so the only thing under test is the preflight's two outcomes.
#
# Usage: tests/semaphore-run-ansible.test.sh
set -euo pipefail

wrapper="$(cd "$(dirname "$0")/.." && pwd)/scripts/semaphore-run-ansible.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

home="$work/home"
mkdir -p "$home"

stub="$work/stub.sh"
cat >"$stub" <<'STUB'
#!/usr/bin/env bash
echo "PLAY RECAP *****"
echo "a-real-host                 : ok=1    changed=0    unreachable=0    failed=0"
STUB
chmod +x "$stub"

run() { env -u BAO_ADDR HOME="$home" KNOWN_HOSTS_SOURCE="$1" bash "$wrapper" "$stub"; }

# Absent source: refuse to start. Continuing here is the bug — the run would
# fail later with a message that never mentions host keys.
if out="$(run "$work/absent" 2>&1)"; then
  echo "FAIL: wrapper started with no host-key source" >&2; exit 1
fi
grep -q "host-key verification has nothing to verify against" <<<"$out" \
  || { echo "FAIL: refusal did not explain itself: $out" >&2; exit 1; }

# Present but empty counts as absent — an empty file verifies nothing.
: >"$work/empty"
if run "$work/empty" >/dev/null 2>&1; then
  echo "FAIL: wrapper started with an empty host-key source" >&2; exit 1
fi

# Populated source: installed into home, readable only by the owner, and the
# wrapped command runs.
printf 'host ssh-ed25519 AAAA\n' >"$work/present"
run "$work/present" >/dev/null
[ -f "$home/.ssh/known_hosts" ] || { echo "FAIL: known_hosts not installed" >&2; exit 1; }
cmp -s "$work/present" "$home/.ssh/known_hosts" \
  || { echo "FAIL: installed known_hosts does not match the source" >&2; exit 1; }
perms="$(stat -f '%Lp' "$home/.ssh/known_hosts" 2>/dev/null || stat -c '%a' "$home/.ssh/known_hosts")"
[ "$perms" = "600" ] || { echo "FAIL: known_hosts mode is $perms, want 600" >&2; exit 1; }

echo "PASS: semaphore-run-ansible.sh host-key preflight"
