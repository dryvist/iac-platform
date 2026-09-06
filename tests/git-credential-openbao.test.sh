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

echo "git-credential-openbao: all checks passed"
