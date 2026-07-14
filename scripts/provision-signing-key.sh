#!/usr/bin/env bash
# Generate-if-absent: provision Terrakube's per-job workload-identity signing
# keypair into OpenBao (secret/platform/terrakube/main).
#
# Terrakube's API signs a short-lived workload-identity JWT per run and
# publishes the public half at /.well-known/jwks so OpenBao can verify it.
# Without the keypair loaded, jwks returns {"keys":null}, no JWT is signed, and
# every remote plan fails "no vault token set on Client". The compose file
# already wires the two PEMs in as env-sourced Docker secrets
# (TK_DYNAMIC_CREDENTIAL_PUBLIC_KEY / TK_DYNAMIC_CREDENTIAL_PRIVATE_KEY) and the
# kid from compose/.env (TK_DYNAMIC_CREDENTIAL_KEY_ID) — this script fills the
# one remaining manual gap by minting the keypair at its source.
#
# Idempotent: if both PEM fields already exist and are non-empty this is a
# no-op, so it is safe to run before every deploy. Nothing secret touches disk
# — the keys live only in this process's env and the OpenBao write body.
#
# The private key is unencrypted PKCS#8 as Terrakube's dynamic-credential
# service requires; the write is a KV v2 merge-patch so the other fields at the
# path (Dex OIDC, S3, DB creds) are left untouched.
#
# Usage (under a native OpenBao token, same as deploy.sh):
#   export BAO_ADDR=https://openbao.<domain>
#   export BAO_TOKEN=<short-lived token from a native auth method>
#   ./scripts/provision-signing-key.sh
set -euo pipefail

PATH_KV="secret/platform/terrakube/main"
PUB_FIELD="TK_DYNAMIC_CREDENTIAL_PUBLIC_KEY"
PRIV_FIELD="TK_DYNAMIC_CREDENTIAL_PRIVATE_KEY"

for bin in curl jq openssl; do
  command -v "$bin" >/dev/null || { echo "$bin required (enter the dev shell)" >&2; exit 1; }
done

: "${BAO_ADDR:?BAO_ADDR missing}"
token="${BAO_TOKEN:-${VAULT_TOKEN:-}}"
[ -n "$token" ] || { echo "provision-signing-key: authenticate to OpenBao and set BAO_TOKEN" >&2; exit 1; }

# KV v2 read/write insert "/data/" after the mount (logical
# secret/platform/terrakube/main -> /v1/secret/data/platform/terrakube/main).
mount="${PATH_KV%%/*}"
subpath="${PATH_KV#*/}"
data_url="${BAO_ADDR}/v1/${mount}/data/${subpath}"

current="$(curl -sf --max-time 10 -H "X-Vault-Token: $token" "$data_url")" \
  || { echo "provision-signing-key: read of $PATH_KV failed" >&2; exit 1; }

have_pub="$(printf '%s' "$current" | jq -r --arg f "$PUB_FIELD"  '.data.data[$f] // "" | length')"
have_priv="$(printf '%s' "$current" | jq -r --arg f "$PRIV_FIELD" '.data.data[$f] // "" | length')"
if [ "$have_pub" -gt 0 ] && [ "$have_priv" -gt 0 ]; then
  echo "ok   signing keypair already present at $PATH_KV — nothing to do"
  exit 0
fi

echo "generating RSA-2048 workload-identity signing keypair ..."
private_pem="$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null)"
public_pem="$(printf '%s' "$private_pem" | openssl pkey -pubout 2>/dev/null)"
[ -n "$private_pem" ] && [ -n "$public_pem" ] || { echo "provision-signing-key: key generation failed" >&2; exit 1; }

# Merge-patch keeps every other field at the path intact. jq --arg encodes the
# multiline PEMs safely into the JSON body.
patch_body="$(jq -n --arg pub "$public_pem" --arg priv "$private_pem" --arg pf "$PUB_FIELD" --arg vf "$PRIV_FIELD" \
  '{data: {($pf): $pub, ($vf): $priv}}')"

curl -sf --max-time 10 -X PATCH \
  -H "X-Vault-Token: $token" \
  -H "Content-Type: application/merge-patch+json" \
  -d "$patch_body" "$data_url" >/dev/null \
  || { echo "provision-signing-key: merge-patch write to $PATH_KV failed (need the 'patch' capability on the path)" >&2; exit 1; }

echo "ok   wrote $PUB_FIELD + $PRIV_FIELD to $PATH_KV (redeploy so terrakube-api mounts them)"
