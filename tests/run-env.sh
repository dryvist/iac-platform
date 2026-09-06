#!/usr/bin/env bash
# Covers the path the deploy takes to reach the values the run-environment
# documents own: openbao-exec-env.sh exports them, and deploy.sh refuses when a
# required name came back absent. No network and no docker — `curl` is stubbed
# on PATH, so every case here is the real script reading a canned KV response.
#
# Usage: tests/run-env.sh   (exit 0 = all cases pass)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXEC_ENV="$REPO_ROOT/scripts/openbao-exec-env.sh"
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT
FAIL=0

# A curl that answers the KV v2 read from a file named for the mount, so a case
# can make one mount carry a value and the others not carry it.
cat >"$STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in http*) url="$a" ;; esac; done
mount="${url#*/v1/}"; mount="${mount%%/*}"
body="$STUB_KV_DIR/$mount.json"
[ -f "$body" ] || exit 22   # curl -f's exit code for a 4xx, i.e. no such document
cat "$body"
STUB
chmod +x "$STUB_DIR/curl"
export STUB_KV_DIR="$STUB_DIR/kv"
mkdir -p "$STUB_KV_DIR"
PATH="$STUB_DIR:$PATH"
export PATH

# Every mount empty unless a case writes one.
for m in config secret secrets-external; do
  printf '{"data":{"data":{}}}' >"$STUB_KV_DIR/$m.json"
done

check() { # name expected-status expected-substring-in-output cmd...
  local name="$1" want_rc="$2" want_txt="$3"
  shift 3
  local out rc
  out="$("$@" 2>&1)"
  rc=$?
  if [ "$rc" != "$want_rc" ]; then
    echo "FAIL $name (exit $rc, wanted $want_rc)"
    echo "     ${out//$'\n'/$'\n'     }"
    FAIL=1
    return
  fi
  if [ -n "$want_txt" ] && [[ "$out" != *"$want_txt"* ]]; then
    echo "FAIL $name (output did not mention '$want_txt')"
    echo "     ${out//$'\n'/$'\n'     }"
    FAIL=1
    return
  fi
  echo "ok   $name"
}

echo "== openbao-exec-env.sh =="
export BAO_ADDR="https://openbao.invalid" BAO_TOKEN="stub-token"

# A required name is carried by exactly one mount and reaches the exec'd command.
printf '{"data":{"data":{"SPLUNK_HEC_TOKEN":"from-the-store"}}}' >"$STUB_KV_DIR/secret.json"
check "exports a value from the mount that carries it" 0 "from-the-store" \
  "$EXEC_ENV" secret/platform/ansible/env -- printenv SPLUNK_HEC_TOKEN

# The store wins over whatever the ambient environment happened to carry.
check "store value overrides the ambient environment" 0 "from-the-store" \
  env SPLUNK_HEC_TOKEN=from-the-ambient-environment \
  "$EXEC_ENV" secret/platform/ansible/env -- printenv SPLUNK_HEC_TOKEN

# A document that cannot be read is a hard failure, never an empty export.
check "unreadable document fails loudly" 1 "read of nosuchmount/platform/ansible/env failed" \
  "$EXEC_ENV" nosuchmount/platform/ansible/env -- true

check "missing address fails loudly" 1 "BAO_ADDR" \
  env -u BAO_ADDR "$EXEC_ENV" secret/platform/ansible/env -- true

check "missing token fails loudly" 1 "set BAO_TOKEN" \
  env -u BAO_TOKEN -u VAULT_TOKEN "$EXEC_ENV" secret/platform/ansible/env -- true

echo "== deploy.sh --inner required-name guard =="
# Everything the guards ahead of the run-environment guard demand, so a failure
# below is the guard under test and not one of its predecessors.
prereqs=(
  DEX_GITHUB_CLIENT_ID=id DEX_GITHUB_CLIENT_SECRET=secret
  TK_DYNAMIC_CREDENTIAL_PUBLIC_KEY=pub TK_DYNAMIC_CREDENTIAL_PRIVATE_KEY=priv
  DEX_GITHUB_ORG=org DEX_GITHUB_TEAM=team DEX_AUTHELIA_CLIENT_ID=client
  SEMAPHORE_OIDC_CLIENT_SECRET=sem DEX_AUTHELIA_CLIENT_SECRET=dex
)

check "refuses when the name is absent from every document" 1 \
  "SPLUNK_HEC_TOKEN absent from platform/ansible/env on every mount (config secret secrets-external)" \
  env -u SPLUNK_HEC_TOKEN -u DEPLOY_HOST "${prereqs[@]}" \
  bash "$REPO_ROOT/scripts/deploy.sh" --inner

# With the name present the guard passes and the deploy moves on to the next
# one — DEPLOY_HOST — rather than exiting 0 having deployed nothing.
check "proceeds past the guard when the name is present" 1 "DEPLOY_HOST missing" \
  env -u DEPLOY_HOST "${prereqs[@]}" SPLUNK_HEC_TOKEN=from-the-store \
  bash "$REPO_ROOT/scripts/deploy.sh" --inner

exit "$FAIL"
