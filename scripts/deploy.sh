#!/usr/bin/env bash
# Deploy the platform compose stack to the iac-platform VM over SSH.
#
# Secrets come from OpenBao (secret/platform/terrakube/main) via
# scripts/openbao-exec-env.sh — the fleet's single source for these live-service
# runtime credentials. The caller uses a short-lived token obtained through a
# native OpenBao human or workload authentication method.
# openbao-exec-env exports the KV keys into this process; docker compose
# interpolates them into container definitions on the remote engine. Nothing
# secret is written to disk on either end, and no macOS keychain is touched.
#
# Per the no-IP-references rule the deploy target is the VM's FQDN (DEPLOY_HOST),
# which is itself real-domain-bearing and so comes from OpenBao, not a default.
#
# Bind-mount sources resolve on the remote daemon, so the two non-secret config
# files compose mounts (dex config, postgres initdb) are shipped to a stable VM
# path first — streamed as tar into a root helper container over the docker
# connection (the VM has no rsync and the ssh login can't write the root-owned
# path); the compose file mounts them from there.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BAO_PATH="secret/platform/terrakube/main"
EXEC_ENV="$REPO_ROOT/scripts/openbao-exec-env.sh"
# Stable VM path the compose file mounts the two non-secret config dirs from.
VM_CONFIG_DIR="/var/lib/platform/compose"

# Second entry: OpenBao KV is already exported into the environment, so the real
# deploy runs in a normal shell — no nested sh -c quoting.
if [ "${1:-}" = "--inner" ]; then
  case "${DEX_OPENBAO_CLIENT_ID:-}${DEX_OPENBAO_CLIENT_SECRET:-}" in
    *CHANGEME*)
      echo "OpenBao $BAO_PATH still has CHANGEME Dex OIDC credentials." >&2
      echo "Write the OpenBao OIDC client id/secret to that path." >&2
      exit 1 ;;
  esac

  for name in OPENBAO_OIDC_ISSUER DEX_OPENBAO_CLIENT_ID DEX_OPENBAO_CLIENT_SECRET \
    TK_DYNAMIC_CREDENTIAL_PUBLIC_KEY TK_DYNAMIC_CREDENTIAL_PRIVATE_KEY; do
    [ -n "${!name:-}" ] || { echo "$name missing from OpenBao $BAO_PATH" >&2; exit 1; }
  done

  host="${DEPLOY_HOST:?DEPLOY_HOST missing from OpenBao}"
  # Ship the two non-secret config dirs into the (root-owned) VM path via a root
  # helper container over the docker connection: the VM has no rsync and the ssh
  # login cannot write under /var/lib/platform. tar streams in; rm -rf clears any
  # empty dirs Docker auto-created from an earlier mount of a missing source.
  tar -C "$REPO_ROOT/compose" -cf - dex postgres \
    | docker --host "$host" run -i --rm -v "$VM_CONFIG_DIR:/dest" busybox \
        sh -c 'rm -rf /dest/dex /dest/postgres && tar -C /dest -xf -'

  # The UI's static bundle reads window._env_ from /env-config.js at runtime and
  # the image ships none, so generate it from $DOMAIN (non-secret public URLs)
  # and ship it to the same VM path the compose file mounts into the container.
  env_js="window._env_ = {
  REACT_APP_TERRAKUBE_API_URL: \"https://terrakube-api.${DOMAIN}/api/v1/\",
  REACT_APP_CLIENT_ID: \"terrakube-app\",
  REACT_APP_AUTHORITY: \"https://terrakube-dex.${DOMAIN}/dex\",
  REACT_APP_REDIRECT_URI: \"https://terrakube.${DOMAIN}\",
  REACT_APP_REGISTRY_URI: \"https://terrakube-registry.${DOMAIN}\",
  REACT_APP_SCOPE: \"email openid profile offline_access groups\",
  REACT_APP_TERRAKUBE_SEND_COOKIES: \"false\"
}
"
  printf '%s' "$env_js" \
    | docker --host "$host" run -i --rm -v "$VM_CONFIG_DIR:/dest" busybox \
        sh -c 'mkdir -p /dest/ui && cat > /dest/ui/env-config.js'

  exec docker --host "$host" compose \
    --project-name iac-platform \
    --project-directory "$REPO_ROOT/compose" \
    --env-file "$REPO_ROOT/compose/.env" \
    up -d --remove-orphans
fi

# First entry: verify local tooling, then re-exec self under OpenBao so the KV
# env is populated for the --inner branch above.
for bin in curl jq tar docker; do
  command -v "$bin" >/dev/null || { echo "$bin required (enter the dev shell)" >&2; exit 1; }
done
# pve3 powers off nightly — if this can't connect, check the node is powered on.
exec "$EXEC_ENV" "$BAO_PATH" -- bash "${BASH_SOURCE[0]}" --inner
