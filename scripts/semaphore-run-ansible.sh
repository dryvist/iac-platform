#!/usr/bin/env bash
# Semaphore template wrapper around the certificate-signed ansible runner
# (ansible-proxmox's scripts/run-ansible.sh). run-ansible.sh has been observed
# to exit 0 on a run interrupted mid-play with no PLAY RECAP, so a template
# that trusts the exit code alone shows green on a half-finished converge.
# This wrapper tees the run's output and fails unless a PLAY RECAP line
# actually landed, regardless of the wrapped command's own exit code.
#
# Usage: semaphore-run-ansible.sh <run-ansible.sh> <playbook> [args...]
set -euo pipefail

[ "$#" -ge 1 ] || { echo "usage: semaphore-run-ansible.sh <run-ansible.sh> [args...]" >&2; exit 2; }

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

set +e
"$@" 2>&1 | tee "$log"
rc="${PIPESTATUS[0]}"
set -e

if ! grep -q '^PLAY RECAP' "$log"; then
  echo "semaphore-run-ansible.sh: no PLAY RECAP in output — treating as a failed run (rc was $rc)" >&2
  exit 1
fi

exit "$rc"
