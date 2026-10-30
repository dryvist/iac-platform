#!/usr/bin/env bash
# Offline checks for the git credential helper: the request parser, the host
# gate, and the fail-loud path. Nothing here contacts OpenBao or GitHub — the
# mint itself is proven by a real clone, not by a test double.
#
# Usage: tests/git-credential-openbao.test.sh
set -euo pipefail

helper="$(cd "$(dirname "$0")/.." && pwd)/scripts/git-credential-openbao.sh"

# A non-`get` operation is a silent no-op: OpenBao is the store, so there is
# nothing to save and nothing to forget.
out="$(printf 'protocol=https\nhost=github.com\n\n' | "$helper" store)"
[ -z "$out" ] || { echo "FAIL: store produced output: $out" >&2; exit 1; }

# A request for another forge must fall through to the next helper without a
# token, even though this one is configured for github.com only.
out="$(printf 'protocol=https\nhost=example.invalid\n\n' | env BAO_ADDR=http://unused "$helper" get)"
[ -z "$out" ] || { echo "FAIL: non-github host produced output: $out" >&2; exit 1; }

# A missing address fails loudly rather than returning an empty credential:
# non-zero exit, a message naming the gap, and no password line.
set +e
out="$(printf 'protocol=https\nhost=github.com\n\n' | env -u BAO_ADDR -u VAULT_ADDR "$helper" get 2>&1)"
rc=$?
set -e
[ "$rc" -ne 0 ] || { echo "FAIL: missing BAO_ADDR exited 0" >&2; exit 1; }
case "$out" in *BAO_ADDR*) : ;; *) echo "FAIL: unclear message: $out" >&2; exit 1 ;; esac
case "$out" in *password=*) echo "FAIL: emitted a password line on failure" >&2; exit 1 ;; esac

# A github.com get logs in with the plane's pair and mints from the read-only
# set, through the shared AppRole CLI (stubbed here).
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT
cat >"$STUB_DIR/bao-approle" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  login) [ "$BAO_APPROLE_ROLE_ID/$BAO_APPROLE_SECRET_ID" = plane-role/plane-secret ] && echo stub-login-token ;;
  "gh-token github read-dryvist-all") [ "$BAO_TOKEN" = stub-login-token ] && echo stub-github-token ;;
  *) exit 64 ;;
esac
STUB
chmod +x "$STUB_DIR/bao-approle"
out="$(printf 'protocol=https\nhost=github.com\n\n' | env PATH="$STUB_DIR:$PATH" BAO_ADDR=https://openbao.invalid \
  OPENBAO_APPROLE_SEMAPHORE_ROLE_ID=plane-role OPENBAO_APPROLE_SEMAPHORE_SECRET_ID=plane-secret "$helper" get)"
[ "$out" = "$(printf 'username=x-access-token\npassword=stub-github-token')" ] \
  || { echo "FAIL: unexpected credentials: $out" >&2; exit 1; }

echo "git-credential-openbao: all checks passed"
