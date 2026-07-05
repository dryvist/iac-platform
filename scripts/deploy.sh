#!/usr/bin/env bash
# Deploy the platform compose stack to the iac-platform VM over SSH.
#
# Secrets come from OpenBao (secret/platform/terrakube/main) via
# scripts/openbao-exec-env.sh — the fleet's single source for these live-service
# runtime credentials. Secret-zero is the platform AppRole (BAO_ADDR + role/secret
# ID), supplied by the caller's environment; the canonical invocation is:
#   doppler run -p iac-conf-mgmt -c prd -- ./scripts/deploy.sh
# openbao-exec-env exports the KV keys into this process; docker compose
# interpolates them into container definitions on the remote engine. Nothing
# secret is written to disk on either end, and no macOS keychain is touched.
#
# Per the no-IP-references rule the deploy target is the VM's FQDN (DEPLOY_HOST),
# which is itself real-domain-bearing and so comes from OpenBao, not a default.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BAO_PATH="secret/platform/terrakube/main"
EXEC_ENV="$REPO_ROOT/scripts/openbao-exec-env.sh"

for bin in curl jq; do
  command -v "$bin" >/dev/null || { echo "$bin required (enter the dev shell)" >&2; exit 1; }
done

# One AppRole login: refuse placeholder dex OAuth creds, then bring the stack up.
# pve3 powers off nightly — if this can't connect, check the node is powered on.
exec "$EXEC_ENV" "$BAO_PATH" -- \
  sh -c 'case "${DEX_GITHUB_CLIENT_ID:-}${DEX_GITHUB_CLIENT_SECRET:-}" in
           *CHANGEME*)
             echo "OpenBao '"$BAO_PATH"' still has CHANGEME dex OAuth creds." >&2
             echo "Write the real GitHub OAuth app id/secret to that path." >&2
             exit 1 ;;
         esac
         exec docker --host "${DEPLOY_HOST:?DEPLOY_HOST missing from OpenBao}" compose \
           --project-name iac-platform \
           --project-directory "'"$REPO_ROOT"'/compose" \
           --env-file "'"$REPO_ROOT"'/compose/.env" \
           up -d --remove-orphans'
