#!/usr/bin/env bash
# Semaphore template wrapper around the certificate-signed ansible runner
# (ansible-proxmox's scripts/run-ansible.sh — do not edit that script from
# here; the ansible-proxmox* repos likely carry their own copy and are
# covered by Vikunja 1843, not by this wrapper). Tracked bug, Vikunja 1843:
# run-ansible.sh can exit 0 on a run interrupted mid-play and then claims the
# run did nothing, even when hundreds of tasks actually ran. This wrapper
# tees the run's output and applies the PLAY RECAP instead of trusting the
# wrapped command's exit code:
#
#   1. No PLAY RECAP at all -> exit non-zero. Run state is UNKNOWN (not
#      "failed", not "did nothing") and must not be treated as applied.
#   2. A recap exists and any host shows failed>0 or unreachable>0 -> exit
#      non-zero.
#   3. A recap exists and the ONLY host in it is localhost (the real target
#      host never ran — the `--limit ...,localhost` footgun) -> exit
#      non-zero. This heuristic is evaluated ONLY when a recap exists;
#      absence of a recap is always rule 1, never this rule — conflating the
#      two is the other half of the upstream bug.
#   4. Recap exists, covers a real host, no failures -> exit with the
#      wrapped command's own exit code.
#
# Usage: semaphore-run-ansible.sh <run-ansible.sh> <playbook> [args...]
set -euo pipefail

[ "$#" -ge 1 ] || { echo "usage: semaphore-run-ansible.sh <run-ansible.sh> [args...]" >&2; exit 2; }

# The run environment. The playbooks read plain environment variables and know
# nothing about where they came from; this is the one place that fills them in.
# Three KV documents, one per mount, so every value lives on exactly one tier:
# topology in config/, internal-only secrets on the internal mount, anything
# reachable from the public internet in secrets-external/. Re-exec through the
# exporter once; the marker stops the second entry from doing it again.
if [ -z "${SEMAPHORE_RUN_ENV_LOADED:-}" ] && [ -n "${BAO_ADDR:-}" ]; then
  export SEMAPHORE_RUN_ENV_LOADED=1
  exec openbao-exec-env.sh config/platform/ansible/env -- \
    openbao-exec-env.sh secret/platform/ansible/env -- \
    openbao-exec-env.sh secrets-external/platform/ansible/env -- \
    bash "$0" "$@"
fi

if [ -f requirements.yml ]; then
  echo "Installing Ansible requirements..."
  ansible-galaxy install -r requirements.yml --roles-path roles || true
  ansible-galaxy collection install -r requirements.yml || true
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

set +e
"$@" 2>&1 | tee "$log"
rc="${PIPESTATUS[0]}"
set -e

# Recap host lines look like: "hostname : ok=5 changed=2 unreachable=0 failed=0 ..."
recap_lines="$(grep -E '^\S+\s*:\s*ok=' "$log" || true)"

if [ -z "$recap_lines" ]; then
  echo "semaphore-run-ansible.sh: no PLAY RECAP in output — run state is UNKNOWN, do not treat as applied (wrapped command's own rc was $rc)" >&2
  exit 1
fi

if grep -qE 'unreachable=[1-9][0-9]*|failed=[1-9][0-9]*' <<<"$recap_lines"; then
  echo "semaphore-run-ansible.sh: PLAY RECAP shows a failed or unreachable host:" >&2
  echo "$recap_lines" >&2
  exit 1
fi

hosts="$(awk -F' *: *' '{print $1}' <<<"$recap_lines" | sort -u)"
if [ "$hosts" = "localhost" ]; then
  echo "semaphore-run-ansible.sh: PLAY RECAP only covers localhost — the real target host(s) never ran (check --limit includes them, not just localhost)" >&2
  exit 1
fi

exit "$rc"
