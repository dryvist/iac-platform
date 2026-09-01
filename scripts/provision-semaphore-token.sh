#!/usr/bin/env bash
# Generate-if-absent: mint Semaphore's automation API token into OpenBao
# (secret/apps/semaphore, field semaphore_api_token).
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
# Lives under secret/apps/ because it is an application credential, not part of
# the IaC kernel. That is also what makes it writable at all: the OpenBao access
# model grants a write leaf per entry in openbao_ai_domains ([ai, apps]), while
# `platform` is listed in openbao_ai_readonly_extra_subtrees and has no write
# leaf by design. Writing an app token there would have meant widening the
# access model to fit one field.
#
# Read-merge-write rather than a blind put, so a field this script does not know
# about (anything a role later publishes to the same path) survives. The path
# need not already exist: an absent secret reads as an empty map.
#
# Usage (under a native OpenBao token, same as deploy.sh):
#   export BAO_ADDR=https://openbao.<domain>
#   export BAO_TOKEN=<short-lived token from a native auth method>
#   export DEPLOY_HOST=<docker host, e.g. ssh://user@host>
#   ./scripts/provision-semaphore-token.sh
set -euo pipefail

PATH_KV="secret/apps/semaphore"
FIELD="semaphore_api_token"
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
# secret/apps/semaphore -> /v1/secret/data/apps/semaphore).
mount="${PATH_KV%%/*}"
subpath="${PATH_KV#*/}"
data_url="${BAO_ADDR}/v1/${mount}/data/${subpath}"

# 404 means the path does not exist yet, which is the first-run case and not an
# error. Anything else is: separate the two on the status code rather than on
# curl's exit alone, so a 403 can never be mistaken for "absent, go create it".
read_body="$(curl -s --max-time 10 -o - -w '\n%{http_code}' \
  -H "X-Vault-Token: $token" "$data_url")"
read_code="${read_body##*$'\n'}"
current="${read_body%$'\n'*}"
case "$read_code" in
  200) ;;
  404) current='{"data":{"data":{}}}' ;;
  *)   echo "provision-semaphore-token: read of $PATH_KV returned HTTP $read_code" >&2; exit 1 ;;
esac

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

write_body="$(printf '%s' "$current" \
  | jq --arg t "$api_token" --arg f "$FIELD" '{data: (.data.data + {($f): $t})}')"

curl -sf --max-time 10 -X POST \
  -H "X-Vault-Token: $token" \
  -H "Content-Type: application/json" \
  -d "$write_body" "$data_url" >/dev/null \
  || { echo "provision-semaphore-token: write to $PATH_KV failed" >&2; exit 1; }

echo "ok   wrote $FIELD to $PATH_KV (tofu/semaphore/ reads it ephemerally)"
