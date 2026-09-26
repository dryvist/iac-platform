#!/usr/bin/env bash
# Ensures the Ansible warm-cache subdirectories under the semaphore_runner_data
# volume (compose/docker-compose.yml, semaphore-runner service:
# ANSIBLE_COLLECTIONS_PATH, ANSIBLE_CACHE_PLUGIN_CONNECTION,
# ANSIBLE_SSH_CONTROL_PATH_DIR) exist before the runner starts. A Dockerfile
# RUN mkdir would create them in the image layer, but the named volume it
# mounts over /var/lib/semaphore already has content in every deployed
# environment, so Docker's "populate an empty volume from the image" behavior
# never applies here — this has to run at container start instead. Runs as
# whatever user the image already sets (USER semaphore in
# compose/semaphore/Dockerfile), so the directories it creates get that same
# ownership with no separate chown.
#
# Chains into the upstream image's own ENTRYPOINT (tini, at /sbin/tini —
# deployment/docker/runner/Dockerfile upstream) rather than replacing it:
# tini is PID 1 there specifically to reap the zombie processes an Ansible
# fork tree leaves behind, so a compose-level `entrypoint:` override that
# skipped it would silently lose that.
set -euo pipefail

mkdir -p \
  /var/lib/semaphore/ansible-cache/collections \
  /var/lib/semaphore/ansible-cache/facts \
  /var/lib/semaphore/ansible-cache/ssh-control

exec /sbin/tini -- "$@"
