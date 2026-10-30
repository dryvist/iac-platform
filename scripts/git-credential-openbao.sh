#!/usr/bin/env bash
# git credential helper for the execution plane's github.com clones.
#
# Semaphore clones its repositories over HTTPS as an unattended process, and
# one of them carries a private submodule, so git needs a credential and has
# no terminal to ask for one. This mints an ephemeral GitHub App installation
# token from the OpenBao GitHub secrets engine on each request, using the
# execution plane's own AppRole, and hands it straight to git.
#
# The token exists only in this process's memory and on the `password=` line
# git reads: no cache file, no keychain, no environment export, nothing on
# disk. `store` and `erase` are no-ops because OpenBao is the store.
#
# Wired in the image with
#   git config --system credential.https://github.com.helper openbao
# which makes git exec `git-credential-openbao get` (PATH lookup, `get`
# appended by git itself).
set -euo pipefail

die() { echo "git-credential-openbao: $*" >&2; exit 1; }

bao_approle() {
  if command -v bao-approle >/dev/null 2>&1; then bao-approle "$@"
  else nix run "github:dryvist/homelab-contracts/2be2e713ed203f1fd02304a157b706d4d0b1cbed#bao-approle" -- "$@"; fi
}

[ "${1:-}" = "get" ] || exit 0

# The credential request: key=value lines terminated by a blank line. Consume
# it whatever the outcome — git expects the pipe drained.
host=""
while IFS= read -r line; do
  [ -z "${line}" ] && break
  case "${line}" in host=*) host="${line#host=}" ;; esac
done
# Configured per-host, but a mis-scoped config must not hand a github token to
# another forge.
case "${host}" in github.com|gist.github.com) : ;; *) exit 0 ;; esac

bao_addr="${BAO_ADDR:-${VAULT_ADDR:-}}"
[ -n "${bao_addr}" ] || die "BAO_ADDR is not set in the container environment"
role_id="${OPENBAO_APPROLE_SEMAPHORE_ROLE_ID:-}"
secret_id="${OPENBAO_APPROLE_SEMAPHORE_SECRET_ID:-}"
[ -n "$role_id" ] && [ -n "$secret_id" ] \
  || die "OPENBAO_APPROLE_SEMAPHORE_ROLE_ID / _SECRET_ID are not in the container environment"

# The shared CLI sends secret-zero on stdin, never argv — argv is readable by
# any other process in the container.
if ! bao_token="$(BAO_ADDR="$bao_addr" \
  BAO_APPROLE_ROLE_ID="$role_id" \
  BAO_APPROLE_SECRET_ID="$secret_id" \
  FLOW_LOCK_API_MAX_TIME=10 bao_approle login)"; then
  die "AppRole login failed"
fi
[ -n "${bao_token}" ] || die "AppRole login failed"

# The all-repo READ permission set: its permission map is stored server-side
# and the endpoint ignores request bodies, so this helper cannot widen what it
# gets. A push with it fails at GitHub, which is the intended boundary — the
# execution plane reads repositories, it does not write them.
if ! gh_token="$(BAO_ADDR="$bao_addr" BAO_TOKEN="$bao_token" \
  BAO_APPROLE_API_MAX_TIME=10 bao_approle gh-token github read-dryvist-all)"; then
  die "minting a GitHub installation token failed"
fi
[ -n "${gh_token}" ] || die "minting a GitHub installation token failed"

# The one and only place the token is emitted.
printf 'username=x-access-token\npassword=%s\n' "${gh_token}"
