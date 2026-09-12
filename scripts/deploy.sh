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
# Authelia OIDC client secrets (semaphore + terrakube-dex) live in the shared
# Authelia secrets path, not this stack's own OpenBao path.
AUTHELIA_BAO_PATH="secret/apps/authelia"
EXEC_ENV="$REPO_ROOT/scripts/openbao-exec-env.sh"
# Stable VM path the compose file mounts the two non-secret config dirs from.
VM_CONFIG_DIR="/var/lib/platform/compose"

# Second entry: OpenBao KV is already exported into the environment, so the real
# deploy runs in a normal shell — no nested sh -c quoting.
if [ "${1:-}" = "--inner" ]; then
  case "${DEX_GITHUB_CLIENT_ID:-}${DEX_GITHUB_CLIENT_SECRET:-}" in
    *CHANGEME*)
      echo "OpenBao $BAO_PATH still has CHANGEME Dex GitHub credentials." >&2
      echo "Write the GitHub OAuth app client id/secret to that path." >&2
      exit 1 ;;
  esac

  # Layer compose/.env in the same precedence order docker compose itself uses:
  # the shell environment wins over --env-file. Without this the guards below
  # read only the OpenBao-exported half of the config and reject a correct
  # setup, because the non-secret identifiers (DEX_GITHUB_ORG/TEAM,
  # DEX_AUTHELIA_CLIENT_ID) deliberately live in compose/.env — see
  # compose/.env.example — and never in OpenBao. Guarding a value against a
  # source it was never meant to come from is a guard that can only ever fail.
  if [ -f "$REPO_ROOT/compose/.env" ]; then
    # `|| [ -n "$k" ]` so a final line with no trailing newline is not dropped.
    while IFS='=' read -r k v || [ -n "$k" ]; do
      case "$k" in '' | \#*) continue ;; esac
      [ -n "${!k:-}" ] || export "$k=$v"
    done <"$REPO_ROOT/compose/.env"
  fi

  # DEX_GITHUB_ORG/TEAM are required because docker-compose composes
  # TERRAKUBE_ADMIN_GROUP from them. Unset, compose interpolates empty strings
  # and Terrakube's admin group silently becomes ":" — every login authenticates
  # and then has no admin rights, which reads as a broken UI rather than a
  # config error.
  for name in DEX_GITHUB_CLIENT_ID DEX_GITHUB_CLIENT_SECRET \
    TK_DYNAMIC_CREDENTIAL_PUBLIC_KEY TK_DYNAMIC_CREDENTIAL_PRIVATE_KEY; do
    [ -n "${!name:-}" ] || { echo "$name missing from OpenBao $BAO_PATH" >&2; exit 1; }
  done
  for name in DEX_GITHUB_ORG DEX_GITHUB_TEAM DEX_AUTHELIA_CLIENT_ID; do
    [ -n "${!name:-}" ] || { echo "$name missing from $REPO_ROOT/compose/.env" >&2; exit 1; }
  done

  # The Authelia path stores these under the Ansible role's own per-client
  # variable names (roles/authelia in ansible-proxmox-apps declares them in
  # openbao_generated_app_secrets.authelia, and openbao-exec-env.sh exports
  # every key VERBATIM). Map them onto the names compose interpolates rather
  # than renaming the store: the Authelia role reads those keys by that name
  # too, so renaming there to suit this consumer would break the producer.
  : "${SEMAPHORE_OIDC_CLIENT_SECRET:=${authelia_oidc_semaphore_client_secret:-}}"
  : "${DEX_AUTHELIA_CLIENT_SECRET:=${authelia_oidc_terrakube_dex_client_secret:-}}"
  export SEMAPHORE_OIDC_CLIENT_SECRET DEX_AUTHELIA_CLIENT_SECRET

  # Same fail-loud guard as above, for the Authelia-sourced values: an unset
  # SEMAPHORE_OIDC_CLIENT_SECRET or DEX_AUTHELIA_CLIENT_SECRET would
  # compose-interpolate to an empty string, rendering an OIDC login button that
  # always fails instead of refusing to deploy.
  for name in SEMAPHORE_OIDC_CLIENT_SECRET DEX_AUTHELIA_CLIENT_SECRET; do
    [ -n "${!name:-}" ] || { echo "$name missing from OpenBao $AUTHELIA_BAO_PATH" >&2; exit 1; }
  done

  # The plane's own AppRole pair is the one thing a Semaphore run cannot fetch
  # for itself: it is what logs in to fetch everything else. Every other value
  # a run needs comes from OpenBao at run time (scripts/semaphore-run-ansible.sh
  # exports the run-environment documents before the playbook starts), so an
  # environment without this pair is a plane that cannot run anything, and the
  # deploy refuses rather than publish an environment that fails at the first
  # login of every task.
  for _var in BAO_ADDR OPENBAO_APPROLE_SEMAPHORE_ROLE_ID OPENBAO_APPROLE_SEMAPHORE_SECRET_ID; do
    [ -n "${!_var:-}" ] || { echo "$_var missing — the Semaphore run environment cannot be published without it" >&2; exit 1; }
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

  # --build: semaphore is the only service built from a local Dockerfile
  # (compose/semaphore/Dockerfile); without this flag compose only builds it
  # the first time and a later Dockerfile edit would deploy stale image content.
  docker --host "$host" compose \
    --project-name iac-platform \
    --project-directory "$REPO_ROOT/compose" \
    --env-file "$REPO_ROOT/compose/.env" \
    up -d --remove-orphans --build

  # Idempotent post-deploy: promote the operator's OIDC-created Semaphore user
  # to admin once they've completed their first SSO login. The login is never
  # hardcoded — it comes from OpenBao like every other identity value here.
  # A no-op if already admin (change-by-login only sets fields you pass); a
  # clean skip, not a failure, when the login isn't configured yet or the user
  # hasn't logged in via SSO yet (true on every first bring-up).
  if [ -n "${SEMAPHORE_SSO_ADMIN_LOGIN:-}" ]; then
    found=false
    for _ in 1 2 3 4 5; do
      if docker --host "$host" exec semaphore semaphore user get --login "$SEMAPHORE_SSO_ADMIN_LOGIN" >/dev/null 2>&1; then
        found=true
        break
      fi
      sleep 2
    done
    if [ "$found" = true ]; then
      docker --host "$host" exec semaphore semaphore user change-by-login \
        --login "$SEMAPHORE_SSO_ADMIN_LOGIN" --admin
      echo "Promoted Semaphore user '$SEMAPHORE_SSO_ADMIN_LOGIN' to admin (idempotent)."
    else
      echo "Semaphore user '$SEMAPHORE_SSO_ADMIN_LOGIN' not found yet (no SSO login yet, or container still starting) — skipping admin promotion."
    fi
  fi

  # Mint the API token tofu/semaphore/ authenticates with. Generate-if-absent,
  # so this is a no-op on every deploy after the first. It runs here rather than
  # before `up` because the token can only be minted against a server that is
  # already migrated and serving.
  DEPLOY_HOST="$host" "$REPO_ROOT/scripts/provision-semaphore-token.sh"

  # Inject runtime credentials into Semaphore Project 1 Environment 1 so task
  # worker processes inherit them (Semaphore LocalJob does not inherit container
  # os.Environ unless mapped in the project environment template).
  sem_token="$(docker --host "$host" exec semaphore semaphore users token create --login "${SEMAPHORE_ADMIN:-admin}" --name deploy-env-sync 2>&1 | tail -n 1 | tr -d '\r\n')" || true
  if [ -n "$sem_token" ]; then
    # Secret-zero only. Everything a playbook, callback or inventory plugin reads
    # is exported from OpenBao before the run starts; the one template that is
    # not an Ansible run wraps itself the same way (scripts/nautobot-drift.sh in
    # its repository). The address is here too because the exporter gates on it
    # before it can read anything.
    payload="$(jq -nc \
      --arg bao "$BAO_ADDR" \
      --arg sem_role "$OPENBAO_APPROLE_SEMAPHORE_ROLE_ID" \
      --arg sem_secret "$OPENBAO_APPROLE_SEMAPHORE_SECRET_ID" \
      '{
        id: 1,
        project_id: 1,
        name: "homelab",
        env: ({
          BAO_ADDR: $bao,
          OPENBAO_APPROLE_SEMAPHORE_ROLE_ID: $sem_role,
          OPENBAO_APPROLE_SEMAPHORE_SECRET_ID: $sem_secret
        } | tojson),
        json: "{}"
      }')"
    # This PUT is the only writer of that environment: a failed write leaves
    # whatever was there before, so it fails the deploy instead of reporting a
    # sync that did not happen. The response body echoes the environment and
    # is never printed.
    put_status="$(docker --host "$host" exec -i semaphore curl -s -o /dev/null -w '%{http_code}' -X PUT \
      -H "Authorization: Bearer $sem_token" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      http://127.0.0.1:3000/api/project/1/environment/1 2>/dev/null)" || put_status="000"
    case "$put_status" in
      2*) echo "Synced runtime credentials to Semaphore project environment (HTTP $put_status)." ;;
      *)
        echo "ERROR: Semaphore project environment sync failed (HTTP $put_status); the live environment is unchanged." >&2
        docker --host "$host" exec semaphore curl -sf -X DELETE \
          -H "Authorization: Bearer $sem_token" \
          "http://127.0.0.1:3000/api/user/tokens/$sem_token" >/dev/null 2>&1 \
          || echo "WARNING: could not revoke the deploy-env-sync API token; revoke it by hand." >&2
        exit 1
        ;;
    esac
    # This block mints a fresh API token on every deploy, so it revokes the one
    # it minted. A Semaphore API token does not expire on its own and is not
    # scoped below its owner, which makes an unrevoked one a standing
    # credential rather than a deploy-time detail. Revoke through the same
    # in-container API call the PUT above uses — such a token is its own id.
    docker --host "$host" exec semaphore curl -sf -X DELETE \
      -H "Authorization: Bearer $sem_token" \
      "http://127.0.0.1:3000/api/user/tokens/$sem_token" >/dev/null 2>&1 \
      || echo "WARNING: could not revoke the deploy-env-sync API token; revoke it by hand."
  else
    echo "ERROR: could not mint a Semaphore API token, so the project environment was not synced." >&2
    exit 1
  fi

  # The --inner branch is the whole deploy; without this the script falls
  # through to the re-exec below and deploys again, forever. The loop is
  # bounded only by the OpenBao token's TTL, so it presents as a deploy that
  # "hangs" and then fails on an expired-token read, long after it succeeded.
  exit 0
fi

# First entry: verify local tooling, then re-exec self under OpenBao so the KV
# env is populated for the --inner branch above.
for bin in curl jq tar docker; do
  command -v "$bin" >/dev/null || { echo "$bin required (enter the dev shell)" >&2; exit 1; }
done
# The platform node may be powered off — if this can't connect, check it is on.
# Chained reads: openbao-exec-env.sh execs its command after exporting one
# path, so nesting a second call layers in the Authelia path's keys too —
# both are exported into the same process before --inner runs. These two paths
# are all the deploy reads: the run-environment documents belong to the
# execution plane, which reads them itself at the start of every task
# (scripts/semaphore-run-ansible.sh), so the deploy identity needs no grant on
# them.
exec "$EXEC_ENV" "$BAO_PATH" -- "$EXEC_ENV" "$AUTHELIA_BAO_PATH" -- bash "${BASH_SOURCE[0]}" --inner
