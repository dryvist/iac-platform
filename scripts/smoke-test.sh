#!/usr/bin/env bash
# Post-deploy smoke test. Everything by FQDN behind the wildcard cert — if a
# check fails on TLS or DNS, the tofu-proxmox ingress rows/apply are the
# first suspects; if only the S3 checks fail, RustFS compatibility is (see
# runbook.md "RustFS compatibility" — the #1 MVP risk). OpenBao OIDC and
# Terrakube workload-identity discovery are checked explicitly below.
set -euo pipefail

DOMAIN="${DOMAIN:?run under openbao-exec-env (real domain never committed)}"
BUCKET="terrakube"
FAIL=0

check() { # name url expected-code-regex
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$2" || echo "000")
  if [[ "$code" =~ $3 ]]; then
    echo "ok   $1 ($code)"
  else
    echo "FAIL $1 ($code, wanted $3) — $2"
    FAIL=1
  fi
}

echo "== Ingress / TLS / service health =="
check "terrakube UI"        "https://terrakube.${DOMAIN}/"                          '^(200|301|302)$'
check "terrakube API"       "https://terrakube-api.${DOMAIN}/actuator/health"       '^200$'
check "terrakube registry"  "https://terrakube-registry.${DOMAIN}/actuator/health"  '^200$'
check "dex discovery"       "https://terrakube-dex.${DOMAIN}/dex/.well-known/openid-configuration" '^200$'
check "workload discovery"  "https://terrakube-api.${DOMAIN}/.well-known/openid-configuration" '^200$'
check "workload JWKS"       "https://terrakube-api.${DOMAIN}/.well-known/jwks"       '^200$'
check "OpenBao OIDC"        "${OPENBAO_OIDC_ISSUER:?missing OpenBao OIDC issuer}/.well-known/openid-configuration" '^200$'
check "semaphore"           "https://semaphore.${DOMAIN}/api/ping"                  '^200$'

echo "== RustFS S3 (state storage) — write/read/delete roundtrip =="
# Uses the same credentials the executor uses, from OpenBao; run under:
#   doppler run -p iac-conf-mgmt -c prd -- \
#     scripts/openbao-exec-env.sh secret/platform/terrakube/main -- scripts/smoke-test.sh
if [[ -n "${TK_OUTPUT_ACCESS_KEY:-}" ]]; then
  export AWS_ACCESS_KEY_ID="$TK_OUTPUT_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$TK_OUTPUT_SECRET_KEY"
  S3=(aws --endpoint-url "https://s3.${DOMAIN}" --region us-east-1 s3)
  probe="smoke-test-$(date +%s)"
  if echo "terrakube-smoke" | "${S3[@]}" cp - "s3://${BUCKET}/${probe}" >/dev/null \
     && [[ "$("${S3[@]}" cp "s3://${BUCKET}/${probe}" - 2>/dev/null)" == "terrakube-smoke" ]] \
     && "${S3[@]}" rm "s3://${BUCKET}/${probe}" >/dev/null; then
    echo "ok   S3 write/read/delete via https://s3.${DOMAIN}"
  else
    echo "FAIL S3 roundtrip via https://s3.${DOMAIN}"
    FAIL=1
  fi
else
  echo "skip S3 roundtrip (no TK_OUTPUT_* in env — run under openbao-exec-env)"
fi

exit $FAIL
