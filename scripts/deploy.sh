#!/usr/bin/env bash
# Deploy the platform compose stack to the iac-platform VM over SSH.
#
# Zero-keychain by construction: the only secret-zero is the local age key
# (SOPS_AGE_KEY_FILE / ~/.config/sops/age/keys.txt). `sops exec-env` decrypts
# the env file into THIS process's environment; docker compose interpolates it
# into container definitions on the remote engine. Nothing secret is written
# to disk on either end, and no macOS keychain is ever touched.
#
# Per the no-IP-references rule the deploy target is the VM's FQDN.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# DEPLOY_HOST (the VM's SSH FQDN) is real-domain-bearing, so it comes from the
# sops env (or the caller's environment) — never a committed default.

command -v sops >/dev/null || { echo "sops not found (enter the dev shell)" >&2; exit 1; }

# Refuse to ship placeholder OAuth credentials.
if sops --config "$REPO_ROOT/secrets/.sops.yaml" --decrypt \
    --input-type dotenv --output-type dotenv \
    "$REPO_ROOT/secrets/platform.sops.env" | grep -q "CHANGEME"; then
  echo "secrets/platform.sops.env still has CHANGEME values (OAuth App creds)." >&2
  echo "Fix with: sops secrets/platform.sops.env" >&2
  exit 1
fi

# The VM only needs the docker engine + this compose context. pve3 powers off
# nightly — if this fails to connect, check that the node is powered on first.
exec sops --config "$REPO_ROOT/secrets/.sops.yaml" exec-env \
  "$REPO_ROOT/secrets/platform.sops.env" \
  'docker --host "${DEPLOY_HOST:?DEPLOY_HOST missing from sops env}" compose \
     --project-name iac-platform \
     --project-directory '"'$REPO_ROOT/compose'"' \
     --env-file '"'$REPO_ROOT/compose/.env'"' \
     up -d --remove-orphans'
