#!/usr/bin/env bash
# Upload a Terraform/OpenTofu configuration to a Terrakube workspace and print
# the resulting configuration-version id.
#
# WHY THIS SCRIPT EXISTS
#
# The TFE-compatible configuration-versions endpoint requires
# data.attributes.speculative to be a JSON boolean. It is not optional and it
# has no server-side default: omit it, send null, or send the STRING "false",
# and the request fails. Until this script existed there was no committed
# client for this call — every upload was hand-rolled curl, so the payload was
# re-invented at each call site and the attribute was easy to drop. INC #17100
# was exactly that: a payload missing `speculative` produced a 185-byte 500
# with no error id, which read like a server outage and cost hours.
#
# The fix is not to remember the attribute. It is to have exactly one place
# that constructs this payload. Call this script; do not hand-roll the curl.
#
# Secrets come from OpenBao via scripts/openbao-exec-env.sh, consistent with
# deploy.sh — nothing secret touches disk and no keychain is involved.
#
# Usage:
#   terrakube-upload-config.sh <workspace-id> <config-dir> [--speculative]
#
#   <workspace-id>  Terrakube workspace UUID
#   <config-dir>    directory whose contents are tarred and uploaded
#   --speculative   plan-only run (speculative=true). Default is false.
#
# Requires TERRAKUBE_API_URL and TERRAKUBE_TOKEN in the environment; run under
#   scripts/openbao-exec-env.sh secret/platform/terrakube/main -- <this script>
set -euo pipefail

usage() { sed -n '5,30p' "$0" >&2; exit 2; }

workspace="${1:-}"; config_dir="${2:-}"; shift 2 2>/dev/null || usage
[ -n "$workspace" ] && [ -n "$config_dir" ] || usage
[ -d "$config_dir" ] || { echo "$0: not a directory: $config_dir" >&2; exit 2; }

speculative=false
case "${1:-}" in
  --speculative) speculative=true ;;
  "") ;;
  *) echo "$0: unknown argument: $1" >&2; usage ;;
esac

: "${TERRAKUBE_API_URL:?TERRAKUBE_API_URL missing — run under openbao-exec-env.sh}"
: "${TERRAKUBE_TOKEN:?TERRAKUBE_TOKEN missing — run under openbao-exec-env.sh}"

api="${TERRAKUBE_API_URL%/}"

# `speculative` is emitted by jq as a real JSON boolean. Do NOT template it into
# a string with printf: "false" is a string, the server casts it to a primitive
# boolean, and the cast throws — which is indistinguishable from a genuine
# outage in the response body. auto-queue-runs is left at the server default.
payload="$(jq -nc --argjson speculative "$speculative" '{
  data: {
    type: "configuration-versions",
    attributes: { speculative: $speculative }
  }
}')"

resp="$(curl -sS --max-time 30 -w '\n%{http_code}' \
  -X POST "${api}/remote/tfe/v2/workspaces/${workspace}/configuration-versions" \
  -H "Authorization: Bearer ${TERRAKUBE_TOKEN}" \
  -H 'Content-Type: application/vnd.api+json' \
  --data "$payload")"

code="${resp##*$'\n'}"
body="${resp%$'\n'*}"

if [ "$code" != "201" ]; then
  echo "$0: creating the configuration version failed (HTTP $code)" >&2
  echo "  response: $body" >&2
  # A bare 500 with no error id is the signature of a rejected payload, not a
  # dead service. Check the request before you check the server.
  [ "$code" = "500" ] && echo "  A 500 here is usually a malformed payload, not an outage — see INC #17100." >&2
  exit 1
fi

cv_id="$(printf '%s' "$body" | jq -r '.data.id')"
upload_url="$(printf '%s' "$body" | jq -r '.data.attributes."upload-url"')"
[ -n "$cv_id" ] && [ "$cv_id" != "null" ] || { echo "$0: no configuration-version id in response" >&2; exit 1; }
[ -n "$upload_url" ] && [ "$upload_url" != "null" ] || { echo "$0: no upload-url in response" >&2; exit 1; }

# Tar the config and PUT it. Uploading nothing leaves the version stuck in
# `pending` forever, which is how the failed hand-rolled attempts left rows
# behind — so the upload is part of this script, not a separate step.
tarball="$(mktemp -t terrakube-config)"
trap 'rm -f "$tarball"' EXIT
tar -czf "$tarball" -C "$config_dir" .

up_code="$(curl -sS --max-time 120 -o /dev/null -w '%{http_code}' \
  -X PUT "$upload_url" \
  -H 'Content-Type: application/octet-stream' \
  --data-binary "@$tarball")"

if [ "$up_code" != "200" ] && [ "$up_code" != "204" ]; then
  echo "$0: uploading the configuration tarball failed (HTTP $up_code)" >&2
  echo "  configuration version $cv_id is left pending with no content" >&2
  exit 1
fi

printf '%s\n' "$cv_id"
