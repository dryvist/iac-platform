#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

find "$repo_root/tofu/terrakube" -type f -name '*.tf' -print0 | xargs -0 awk '
BEGIN {
  allowed["iac-platform"] = 1
  allowed["iac-platform-semaphore"] = 1
  allowed["tofu-aws-production"] = 1
  allowed["tofu-github"] = 1
  allowed["tofu-proxmox"] = 1
  allowed["tofu-proxmox-aws-infra"] = 1
  allowed["tofu-proxmox-servarr-config"] = 1
  allowed["tofu-runs-on"] = 1
  allowed["tofu-unifi"] = 1
}

/^[[:space:]]*resource[[:space:]]+"terrakube_workspace_cli"[[:space:]]+"[^"]+"[[:space:]]*\{/ {
  in_resource = 1
  header = $0
  sub(/^[[:space:]]*resource[[:space:]]+"terrakube_workspace_cli"[[:space:]]+"/, "", header)
  sub(/".*/, "", header)
  resource_label = header
  depth = 1
  next
}

in_resource {
  if ($0 ~ /^[[:space:]]*name[[:space:]]*=[[:space:]]*"[^"]*"[[:space:]]*(#.*)?$/) {
    literal = $0
    sub(/^[[:space:]]*name[[:space:]]*=[[:space:]]*"/, "", literal)
    sub(/".*/, "", literal)
    if (literal !~ /\$\{/ && !(literal in allowed)) {
      printf "%s:%d: literal workspace name outside allowlist in resource %s\n", FILENAME, FNR, resource_label
      failed = 1
    }
  }

  line = $0
  opens = gsub(/\{/, "", line)
  line = $0
  closes = gsub(/\}/, "", line)
  depth += opens - closes
  if (depth == 0) {
    in_resource = 0
  }
}

END {
  if (failed) {
    exit 1
  }
}
'

printf 'Terrakube workspace names match the public allowlist.\n'
