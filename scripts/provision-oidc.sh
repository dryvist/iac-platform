#!/usr/bin/env bash
# Generate-if-absent: stand up the OpenBao identity/oidc provider that lets
# Dex broker Terrakube UI login, then seed the three fields deploy.sh
# hard-requires at secret/platform/terrakube/main: OPENBAO_OIDC_ISSUER,
# DEX_OPENBAO_CLIENT_ID, DEX_OPENBAO_CLIENT_SECRET.
#
# Creates (skips if already present): the terrakube-admins internal identity
# group, the profile/email/groups OIDC scopes, the terrakube-admins
# assignment, the terrakube named signing key, and the terrakube-dex
# confidential client. Then narrows the signing key to that client, writes
# the provider, and merge-patches the three KV fields. Every step is safe to
# re-run: existing objects are read back rather than recreated (recreating
# the client would rotate its secret and break already-deployed config).
#
# Nothing secret touches disk — client_secret and BAO_TOKEN live only in
# this process's env and request bodies, never printed or written to a file.
#
# Usage (under a native OpenBao root/admin token, same as deploy.sh):
#   export BAO_ADDR=https://openbao.<domain>
#   export BAO_TOKEN=<short-lived token from a native auth method>
#   ./scripts/provision-oidc.sh
set -euo pipefail

GROUP_NAME="terrakube-admins"
ASSIGNMENT_NAME="terrakube-admins"
KEY_NAME="terrakube"
CLIENT_NAME="terrakube-dex"
PROVIDER_NAME="terrakube"
PATH_KV="secret/platform/terrakube/main"

for bin in curl jq base64; do
  command -v "$bin" >/dev/null || { echo "$bin required (enter the dev shell)" >&2; exit 1; }
done

: "${BAO_ADDR:?BAO_ADDR missing}"
token="${BAO_TOKEN:-${VAULT_TOKEN:-}}"
[ -n "$token" ] || { echo "provision-oidc: authenticate to OpenBao and set BAO_TOKEN" >&2; exit 1; }

# Derive the homelab domain from BAO_ADDR instead of hardcoding it, so no
# real hostname lives in this committed script.
domain="${BAO_ADDR#https://openbao.}"
redirect_uri="https://terrakube-dex.${domain}/dex/callback"

# bao_call METHOD PATH [JSON_BODY] -> sets HTTP_STATUS + HTTP_BODY.
# PATH is the logical OpenBao path with no leading /v1/.
bao_call() {
  local method="$1" path="$2" data="${3:-}" out
  local -a args=(-sS -w $'\n%{http_code}' -X "$method" -H "X-Vault-Token: $token")
  [ -n "$data" ] && args+=(-H "Content-Type: application/json" -d "$data")
  out="$(curl "${args[@]}" "${BAO_ADDR}/v1/${path}")" \
    || { echo "provision-oidc: request to $path failed (network)" >&2; exit 1; }
  HTTP_STATUS="${out##*$'\n'}"
  HTTP_BODY="${out%$'\n'*}"
}

# bao_write METHOD PATH JSON_BODY DESC -> bao_call, then fail loudly on a
# non-2xx status (never prints HTTP_BODY: some writes echo back secrets).
bao_write() {
  local method="$1" path="$2" data="$3" desc="$4"
  bao_call "$method" "$path" "$data"
  case "$HTTP_STATUS" in
    2??) ;;
    *) echo "provision-oidc: $desc failed (HTTP $HTTP_STATUS) — need write capability on $path" >&2; exit 1 ;;
  esac
}

exists() { bao_call GET "$1"; [ "$HTTP_STATUS" = "200" ]; }

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

## Step 1 — terrakube-admins identity group (create-if-absent; never touch
## existing membership).
if exists "identity/group/name/${GROUP_NAME}"; then
  echo "ok   identity group '$GROUP_NAME' already exists"
else
  bao_write PUT "identity/group/name/${GROUP_NAME}" '{"type":"internal"}' "create group $GROUP_NAME"
  echo "ok   created identity group '$GROUP_NAME' (add operator entities to member_entity_ids)"
fi
bao_call GET "identity/group/name/${GROUP_NAME}"
group_id="$(printf '%s' "$HTTP_BODY" | jq -r '.data.id')"
member_ids="$(printf '%s' "$HTTP_BODY" | jq -r '.data.member_entity_ids // [] | .[]')"

## Step 2 — flag missing membership / missing email, without inventing data.
if [ -z "$member_ids" ]; then
  echo "WARN: identity group '$GROUP_NAME' has zero members — Dex login will carry an empty groups claim and be rejected by allowedGroups. Add operator entities manually (runbook Step 1)." >&2
else
  while IFS= read -r eid; do
    [ -n "$eid" ] || continue
    bao_call GET "identity/entity/id/${eid}"
    email="$(printf '%s' "$HTTP_BODY" | jq -r '.data.metadata.email // ""')"
    ename="$(printf '%s' "$HTTP_BODY" | jq -r '.data.name // ""')"
    if [ -z "$email" ]; then
      echo "WARN: entity '$ename' ($eid) in '$GROUP_NAME' has no metadata.email — Dex will see an empty email claim for this operator." >&2
    fi
  done <<<"$member_ids"
fi

## Step 3 — OIDC scopes (groups, email, profile). openid is built-in — never
## create it. Create-if-absent: templates never change once set.
declare -A scope_templates=(
  [groups]='{"groups":{{identity.entity.groups.names}}}'
  [email]='{"email":{{identity.entity.metadata.email}}}'
  [profile]='{"name":{{identity.entity.name}}}'
)
for scope in groups email profile; do
  if exists "identity/oidc/scope/${scope}"; then
    echo "ok   OIDC scope '$scope' already exists"
    continue
  fi
  body="$(jq -n --arg tpl "$(b64 "${scope_templates[$scope]}")" '{template: $tpl}')"
  bao_write PUT "identity/oidc/scope/${scope}" "$body" "create scope $scope"
  echo "ok   created OIDC scope '$scope'"
done

## Step 4 — assignment restricting the client to this group. Declarative;
## safe to rewrite every run.
assignment_body="$(jq -n --arg gid "$group_id" '{group_ids: $gid}')"
bao_write PUT "identity/oidc/assignment/${ASSIGNMENT_NAME}" "$assignment_body" "write assignment $ASSIGNMENT_NAME"
echo "ok   assignment '$ASSIGNMENT_NAME' -> group $group_id"

## Step 5 — named signing key (create-if-absent, starts wildcard-scoped;
## narrowed to the real client_id in Step 7).
if exists "identity/oidc/key/${KEY_NAME}"; then
  echo "ok   OIDC key '$KEY_NAME' already exists"
else
  key_body='{"allowed_client_ids":"*","algorithm":"RS256","rotation_period":"24h","verification_ttl":"24h"}'
  bao_write PUT "identity/oidc/key/${KEY_NAME}" "$key_body" "create key $KEY_NAME"
  echo "ok   created OIDC key '$KEY_NAME'"
fi

## Step 6 — confidential client (create-if-absent: recreating would rotate
## client_secret and break every already-deployed consumer).
if exists "identity/oidc/client/${CLIENT_NAME}"; then
  echo "ok   OIDC client '$CLIENT_NAME' already exists"
else
  client_body="$(jq -n --arg uri "$redirect_uri" --arg assign "$ASSIGNMENT_NAME" --arg key "$KEY_NAME" \
    '{redirect_uris: $uri, assignments: $assign, key: $key, client_type: "confidential", id_token_ttl: "30m", access_token_ttl: "1h"}')"
  bao_write PUT "identity/oidc/client/${CLIENT_NAME}" "$client_body" "create client $CLIENT_NAME"
  echo "ok   created OIDC client '$CLIENT_NAME'"
fi
bao_call GET "identity/oidc/client/${CLIENT_NAME}"
client_id="$(printf '%s' "$HTTP_BODY" | jq -r '.data.client_id')"
client_secret="$(printf '%s' "$HTTP_BODY" | jq -r '.data.client_secret')"
[ -n "$client_id" ] && [ "$client_id" != "null" ] || { echo "provision-oidc: could not read client_id for $CLIENT_NAME" >&2; exit 1; }
[ -n "$client_secret" ] && [ "$client_secret" != "null" ] || { echo "provision-oidc: could not read client_secret for $CLIENT_NAME" >&2; exit 1; }

## Step 7 — narrow the key to this client (idempotent; safe to rewrite).
narrow_body="$(jq -n --arg cid "$client_id" '{allowed_client_ids: $cid}')"
bao_write PUT "identity/oidc/key/${KEY_NAME}" "$narrow_body" "narrow key $KEY_NAME"
echo "ok   key '$KEY_NAME' allowed_client_ids narrowed to this client"

## Step 8 — provider (declarative; safe to rewrite every run).
provider_body="$(jq -n --arg iss "$BAO_ADDR" --arg cid "$client_id" \
  '{issuer: $iss, allowed_client_ids: $cid, scopes_supported: "profile,email,groups"}')"
bao_write PUT "identity/oidc/provider/${PROVIDER_NAME}" "$provider_body" "write provider $PROVIDER_NAME"
issuer="${BAO_ADDR}/v1/identity/oidc/provider/${PROVIDER_NAME}"
echo "ok   provider '$PROVIDER_NAME' ready — issuer $issuer"

## Step 9 — seed the three fields into KV (merge-patch keeps the other
## fields at this path — signing keypair, S3, DB creds, DOMAIN — intact).
mount="${PATH_KV%%/*}"
subpath="${PATH_KV#*/}"
data_url="${BAO_ADDR}/v1/${mount}/data/${subpath}"
patch_body="$(jq -n --arg iss "$issuer" --arg cid "$client_id" --arg csec "$client_secret" \
  '{data: {OPENBAO_OIDC_ISSUER: $iss, DEX_OPENBAO_CLIENT_ID: $cid, DEX_OPENBAO_CLIENT_SECRET: $csec}}')"
curl -sf --max-time 10 -X PATCH \
  -H "X-Vault-Token: $token" \
  -H "Content-Type: application/merge-patch+json" \
  -d "$patch_body" "$data_url" >/dev/null \
  || { echo "provision-oidc: merge-patch write to $PATH_KV failed (need the 'patch' capability on the path)" >&2; exit 1; }

echo "ok   OpenBao OIDC provider '${PROVIDER_NAME}' ready; 3 fields seeded to ${PATH_KV} — now run ./scripts/deploy.sh"

# Non-fatal discovery check.
if discovery="$(curl -fsS --max-time 10 "${issuer}/.well-known/openid-configuration" 2>/dev/null)"; then
  echo "verify: discovery issuer = $(printf '%s' "$discovery" | jq -r '.issuer')"
else
  echo "verify: discovery endpoint not reachable yet (non-fatal) — check ${issuer}/.well-known/openid-configuration" >&2
fi
