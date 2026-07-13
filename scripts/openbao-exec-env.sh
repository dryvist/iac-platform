#!/usr/bin/env bash
# Read a KV v2 path, export every key at
# that path into the environment, then exec the given command with them set.
#
# The caller authenticates to OpenBao with a native human or workload method
# and supplies its short-lived BAO_TOKEN (VAULT_TOKEN is also accepted).
# Nothing secret touches disk; the values live only in this process's env and
# whatever it exec's.
#
# Usage: openbao-exec-env.sh <kv/path> -- <cmd> [args...]
#   e.g. openbao-exec-env.sh secret/platform/terrakube/main -- sh -c 'docker ...'
set -euo pipefail

path="${1:?usage: openbao-exec-env.sh <kv/path> -- <cmd...>}"
shift
[ "${1:-}" = "--" ] && shift
[ "$#" -gt 0 ] || { echo "openbao-exec-env.sh: no command to exec" >&2; exit 2; }

: "${BAO_ADDR:?BAO_ADDR missing}"
token="${BAO_TOKEN:-${VAULT_TOKEN:-}}"
[ -n "$token" ] || { echo "openbao-exec-env.sh: authenticate to OpenBao and set BAO_TOKEN" >&2; exit 1; }

# KV v2 read endpoint inserts "/data/" after the mount: the logical path
# "secret/platform/terrakube/main" reads at "/v1/secret/data/platform/terrakube/main".
mount="${path%%/*}"
subpath="${path#*/}"
kv_json="$(curl -sf --max-time 10 -H "X-Vault-Token: $token" \
  "${BAO_ADDR}/v1/${mount}/data/${subpath}")" \
  || { echo "openbao-exec-env.sh: read of ${path} failed" >&2; exit 1; }

# Export every key at the path in one eval. @sh single-quotes each value, so
# the blob is injection-safe and values containing newlines stay intact (a
# line-by-line read would split them).
eval "$(printf '%s' "$kv_json" | jq -r '.data.data | to_entries[] | "export \(.key)=\(.value | @sh)"')"

exec "$@"
