#!/usr/bin/env bash
# Fails when any quoted, workspace-shaped literal in tofu/terrakube is not a public workspace name.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
allowed='^(iac-platform|iac-platform-semaphore|tofu-aws-production|tofu-github|tofu-proxmox|tofu-proxmox-aws-infra|tofu-proxmox-servarr-config|tofu-runs-on|tofu-unifi)$'

hits=$({ grep -rnoE --include='*.tf' '"(tofu|iac)-[a-z0-9-]*[a-z0-9]"' "$repo_root/tofu/terrakube" || true; } \
  | while IFS= read -r hit; do
      name=${hit##*:\"}; name=${name%\"}
      [[ $name =~ $allowed ]] || printf '%s\n' "${hit%%:\"*}: workspace-shaped literal outside the public allowlist"
    done)

if [[ -n $hits ]]; then
  printf '%s\n' "$hits"
  exit 1
fi
printf 'Terrakube workspace names match the public allowlist.\n'
