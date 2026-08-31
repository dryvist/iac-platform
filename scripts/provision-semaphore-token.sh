#!/usr/bin/env bash
# Generate-if-absent: mint Semaphore's automation API token into OpenBao
# (secret/platform/terrakube/main, field SEMAPHORE_API_TOKEN).
#
# tofu/semaphore/ declares Semaphore's object graph — project, repositories,
# inventories, environments, templates, schedules — through Semaphore's REST
# API, and that provider needs a token. Semaphore mints tokens only for an
# existing user, and only once the server is up and migrated, so this cannot be
# a compose variable: it is the same chicken-and-egg the Terrakube signing
# keypair has, and it gets the same answer (see provision-signing-key.sh).
#
# Minted against the LOCAL break-glass admin, never the SSO user. A Semaphore
# API token carries the same privileges as its owner with no scoping, so an
# SSO-owned token would tie the automation credential to one human's identity
# and orphan it the moment that account changes.
#
# Idempotent: if the field is already present and non-empty this is a no-op, so
# it is safe to run before every deploy. Nothing secret touches disk — the token
# exists only in this process's env and the OpenBao write body, and its value is
# never echoed.
#
# The write is a KV v2 merge-patch so the other fields at that path (Dex OIDC,
# S3, DB creds, Terrakube signing keys) are left untouched.
#
# Usage (under a native OpenBao token, same as deploy.sh):
#   export BAO_ADDR=https://openbao.<domain>
#   export BAO_TOKEN=<short-lived token from a native auth method>
#   export DEPLOY_HOST=<docker host, e.g. ssh://user@host>
#   ./scripts/provision-semaphore-token.sh
set -euo pipefail

PATH_KV="secret/platform/terrakube/main"
FIELD="SEMAPHORE_API_TOKEN"
TOKEN_NAME="iac-platform-tofu"
CONTAINER="semaphore"

for bin in curl jq docker; do
  command -v "$bin" >/dev/null || { echo "$bin required (enter the dev shell)" >&2; exit 1; }
done

: "${BAO_ADDR:?BAO_ADDR missing}"
: "${DEPLOY_HOST:?DEPLOY_HOST missing (the docker host this stack runs on)}"

# The local break-glass admin login, the same value the compose stack seeds.
admin_login="${SEMAPHORE_ADMIN:-admin}"

token="${BAO_TOKEN:-${VAULT_TOKEN:-}}"
[ -n "$token" ] || { echo "provision-semaphore-token: authenticate to OpenBao and set BAO_TOKEN" >&2; exit 1; }

# KV v2 read/write insert "/data/" after the mount (logical
# secret/platform/terrakube/main -> /v1/secret/data/platform/terrakube/main).
mount="${PATH_KV%%/*}"
subpath="${PATH_KV#*/}"
data_url="${BAO_ADDR}/v1/${mount}/data/${subpath}"

current="$(curl -sf --max-time 10 -H "X-Vault-Token: $token" "$data_url")" \
  || { echo "provision-semaphore-token: read of $PATH_KV failed" >&2; exit 1; }

have="$(printf '%s' "$current" | jq -r --arg f "$FIELD" '.data.data[$f] // "" | length')"
if [ "$have" -gt 0 ]; then
  echo "ok   $FIELD already present at $PATH_KV — nothing to do"
  exit 0
fi

echo "minting Semaphore API token for '$admin_login' ..."
# `users token create` prints the token id on success. Capture it rather than
# teeing, so the value never reaches this script's stdout.
api_token="$(docker --host "$DEPLOY_HOST" exec "$CONTAINER" \
  semaphore users token create --login "$admin_login" --name "$TOKEN_NAME" \
  2>/dev/null | tr -d '\r' | tail -n 1 | tr -d '[:space:]')" || true

# A token is an opaque string. Reject an empty capture or an obvious error line
# rather than writing garbage into OpenBao and failing later in tofu, where the
# cause would read as an auth problem instead of a bad mint.
if [ -z "$api_token" ] || [ "${#api_token}" -lt 16 ] \
   || printf '%s' "$api_token" | grep -qiE 'error|usage|not found'; then
  echo "provision-semaphore-token: token mint produced no usable value — is the '$admin_login' user present and the container up?" >&2
  exit 1
fi

patch_body="$(jq -n --arg t "$api_token" --arg f "$FIELD" '{data: {($f): $t}}')"

curl -sf --max-time 10 -X PATCH \
  -H "X-Vault-Token: $token" \
  -H "Content-Type: application/merge-patch+json" \
  -d "$patch_body" "$data_url" >/dev/null \
  || { echo "provision-semaphore-token: merge-patch write to $PATH_KV failed (need the 'patch' capability on the path)" >&2; exit 1; }

echo "ok   wrote $FIELD to $PATH_KV (tofu/semaphore/ reads it ephemerally)"
