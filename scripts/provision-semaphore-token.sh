#!/usr/bin/env bash
# Validate-or-mint a Semaphore API token into OpenBao. Two profiles, each one
# login, one OpenBao leaf and one field (the table below is their only source):
#
#   (default) the automation token tofu/semaphore/ authenticates with, owned
#             by the local break-glass admin -> secret/apps/semaphore.
#   agent     the converge agent's token, owned by the task_runner-only user
#             tofu/semaphore/users.tf declares -> agent-tier/semaphore-write,
#             the exact leaf the router's semaphore-write tier reads. That user
#             exists only once tofu/semaphore/ has applied, so a missing user
#             is a clean skip here, not an error: the next deploy mints it.
#
# tofu/semaphore/ declares Semaphore's object graph — project, repositories,
# inventories, environments, templates, schedules — through Semaphore's REST
# API, and that provider needs a token. Semaphore mints tokens only for an
# existing user, and only once the server is up and migrated, so this cannot be
# a compose variable: it is the same chicken-and-egg the Terrakube signing
# keypair has, and it gets the same answer (see provision-signing-key.sh).
#
# The default profile is minted against the LOCAL break-glass admin, never the
# SSO user. A Semaphore API token carries the same privileges as its owner with
# no scoping, so an SSO-owned token would tie the automation credential to one
# human's identity and orphan it the moment that account changes.
#
# Idempotent: validate a stored token before reusing it, and mint a replacement
# only when the field is empty or Semaphore rejects it. Nothing secret touches
# disk, and the token value is never echoed.
#
# The default profile lives under secret/apps/ because it is an application
# credential, not part of the IaC kernel. That is also what makes it writable at
# all: the OpenBao access model grants a write leaf per entry in
# openbao_ai_domains ([ai, apps]), while `platform` is listed in
# openbao_ai_readonly_extra_subtrees and has no write leaf by design. Writing an
# app token there would have meant widening the access model to fit one field.
#
# Read-merge-write rather than a blind put, so a field this script does not know
# about (anything a role later publishes to the same path) survives. The path
# need not already exist: an absent secret reads as an empty map.
#
# Usage (under a native OpenBao token, same as deploy.sh):
#   export BAO_ADDR=https://openbao.<domain>
#   export BAO_TOKEN=<short-lived token from a native auth method>
#   export DEPLOY_HOST=<docker host, e.g. ssh://user@host>
#   ./scripts/provision-semaphore-token.sh [agent]
#
# The agent leaf is writable because the Semaphore and ansible AppRoles carry
# the ansible-converge policy, which grants create/update/read on every leaf
# ansible-secrets-management's openbao_app_agent_tier_readers declares — the
# same publisher grant the app roles use for their own agent tiers.
set -euo pipefail

CONTAINER="semaphore"
case "${1:-}" in
  "")
    PATH_KV="secret/apps/semaphore"
    FIELD="semaphore_api_token"
    TOKEN_NAME="iac-platform-tofu"
    # The local break-glass admin login, the same value the compose stack seeds.
    LOGIN="${SEMAPHORE_ADMIN:-admin}"
    SKIP_MISSING_USER=false
    ;;
  agent)
    PATH_KV="agent-tier/semaphore-write"
    FIELD="SEMAPHORE_AGENT_WRITE_TOKEN"
    TOKEN_NAME="agent-semaphore-write"
    # Held equal to tofu/semaphore/users.tf by tests/agent_user_contract.tftest.hcl.
    LOGIN="semaphore-agent"
    SKIP_MISSING_USER=true
    ;;
  *) echo "usage: provision-semaphore-token.sh [agent]" >&2; exit 2 ;;
esac

for bin in curl jq docker; do
  command -v "$bin" >/dev/null || { echo "$bin required (enter the dev shell)" >&2; exit 1; }
done

: "${BAO_ADDR:?BAO_ADDR missing}"
: "${DEPLOY_HOST:?DEPLOY_HOST missing (the docker host this stack runs on)}"

token="${BAO_TOKEN:-${VAULT_TOKEN:-}}"
[ -n "$token" ] || { echo "provision-semaphore-token: authenticate to OpenBao and set BAO_TOKEN" >&2; exit 1; }
bao_token_config="${token//\\/\\\\}"
bao_token_config="${bao_token_config//\"/\\\"}"

# KV v2 read/write insert "/data/" after the mount (logical
# secret/apps/semaphore -> /v1/secret/data/apps/semaphore; agent-tier is a KV v2
# mount of its own, agent-tier/semaphore-write -> /v1/agent-tier/data/semaphore-write).
mount="${PATH_KV%%/*}"
subpath="${PATH_KV#*/}"
data_url="${BAO_ADDR}/v1/${mount}/data/${subpath}"

# 404 means the path does not exist yet, which is the first-run case and not an
# error. Anything else is: separate the two on the status code rather than on
# curl's exit alone, so a 403 can never be mistaken for "absent, go create it".
read_body="$(curl -s --max-time 10 \
  --config <(printf 'header = "X-Vault-Token: %s"\n' "$bao_token_config") \
  -o - -w '\n%{http_code}' "$data_url")"
read_code="${read_body##*$'\n'}"
current="${read_body%$'\n'*}"
case "$read_code" in
  200) ;;
  404) current='{"data":{"data":{}}}' ;;
  *)   echo "provision-semaphore-token: read of $PATH_KV returned HTTP $read_code" >&2; exit 1 ;;
esac

existing_token="$(printf '%s' "$current" | jq -r --arg f "$FIELD" '.data.data[$f] // ""')"
if [ -n "$existing_token" ]; then
  case "$existing_token" in
    *$'\n'*|*$'\r'*)
      echo "provision-semaphore-token: stored token contains a line break" >&2
      exit 1
      ;;
  esac
  token_config="${existing_token//\\/\\\\}"
  token_config="${token_config//\"/\\\"}"
  if ! api_status="$(
    printf 'header = "Authorization: Bearer %s"\n' "$token_config" \
      | docker --host "$DEPLOY_HOST" exec -i "$CONTAINER" sh -c '
        [ -n "$SEMAPHORE_WEB_ROOT" ] || exit 1
        exec curl -sS --max-time 10 -o /dev/null -w "%{http_code}" --config - \
          "${SEMAPHORE_WEB_ROOT%/}/api/projects"
      ' 2>/dev/null
  )"; then
    echo "provision-semaphore-token: Semaphore API token validation request failed" >&2
    exit 1
  fi
  case "$api_status" in
    200)
      echo "ok   $FIELD is valid at $PATH_KV — nothing to do"
      exit 0
      ;;
    401) echo "stored $FIELD was rejected — minting a replacement" ;;
    *)
      echo "provision-semaphore-token: Semaphore API validation returned HTTP $api_status" >&2
      exit 1
      ;;
  esac
fi

if [ "$SKIP_MISSING_USER" = true ] \
   && ! docker --host "$DEPLOY_HOST" exec "$CONTAINER" \
     semaphore user get --login "$LOGIN" >/dev/null 2>&1; then
  # A rejected token whose user is gone is a broken agent, not a first run:
  # fail so deploy.sh warns, instead of leaving a dead token behind a clean skip.
  if [ -n "$existing_token" ]; then
    echo "provision-semaphore-token: stored $FIELD was rejected and Semaphore user '$LOGIN' no longer exists" >&2
    exit 1
  fi
  echo "skip Semaphore user '$LOGIN' does not exist yet (tofu/semaphore/ not applied) — rerun after it is"
  exit 0
fi

echo "minting Semaphore API token for '$LOGIN' ..."
# `users token create` prints the token id on success. Capture it rather than
# teeing, so the value never reaches this script's stdout.
api_token="$(docker --host "$DEPLOY_HOST" exec "$CONTAINER" \
  semaphore users token create --login "$LOGIN" --name "$TOKEN_NAME" \
  2>/dev/null | tr -d '\r' | tail -n 1 | tr -d '[:space:]')" || true

# A token is an opaque string. Reject an empty capture or an obvious error line
# rather than writing garbage into OpenBao and failing later in tofu, where the
# cause would read as an auth problem instead of a bad mint.
if [ -z "$api_token" ] || [ "${#api_token}" -lt 16 ] \
   || printf '%s' "$api_token" | grep -qiE 'error|usage|not found'; then
  echo "provision-semaphore-token: token mint produced no usable value — is the '$LOGIN' user present and the container up?" >&2
  exit 1
fi

if [ "$read_code" = 404 ]; then
  write_method=POST
  content_type=application/json
  write_body="$(SEMAPHORE_API_TOKEN="$api_token" jq --arg f "$FIELD" \
    '{data: ((.data.data // {}) + {($f): env.SEMAPHORE_API_TOKEN})}' <<<"$current")"
else
  write_method=PATCH
  content_type=application/merge-patch+json
  write_body="$(SEMAPHORE_API_TOKEN="$api_token" jq -n --arg f "$FIELD" \
    '{data: {($f): env.SEMAPHORE_API_TOKEN}}')"
fi

curl -sf --max-time 10 -X "$write_method" \
  --config <(printf 'header = "X-Vault-Token: %s"\n' "$bao_token_config") \
  -H "Content-Type: $content_type" \
  --data-binary @- "$data_url" <<<"$write_body" >/dev/null \
  || { echo "provision-semaphore-token: $write_method write to $PATH_KV failed" >&2; exit 1; }

echo "ok   wrote $FIELD to $PATH_KV"
