# Adds the tools scripts/run-ansible.sh needs (an ephemeral OpenBao-signed SSH
# cert, ansible-playbook is invoked from the checked-out Ansible repo itself)
# on top of the upstream Semaphore image. SEMAPHORE_VERSION is a build arg
# fed from compose/.env by docker-compose.yml (build.args), so the version is
# tracked once, by the existing renovate customManager — not duplicated here.
# Default mirrors compose/.env.example's SEMAPHORE_VERSION so a bare
# `docker build` (no --build-arg) still resolves to a real image; compose
# always passes the live pin via build.args, keeping the two in step.
ARG SEMAPHORE_VERSION=v2.18.18
FROM semaphoreui/semaphore:${SEMAPHORE_VERSION}

USER root
RUN apk add --no-cache curl jq openssh-client git bash py3-pip py3-requests \
    && for venv in /opt/semaphore/apps/ansible/*/venv; do [ -d "$venv" ] && "$venv/bin/pip" install --no-cache-dir hvac || true; done \
    && mkdir -p /usr/lib/python3.12/site-packages \
    && echo "/opt/semaphore/apps/ansible/13.5.0/venv/lib/python3.12/site-packages" > /usr/lib/python3.12/site-packages/venv.pth

# The PLAY RECAP assertion wrapper every Ansible template invokes instead of
# calling run-ansible.sh directly — see the script for why.
COPY scripts/semaphore-run-ansible.sh /usr/local/bin/semaphore-run-ansible.sh
# The KV-to-environment exporter the wrapper re-execs through to load the run
# environment before the playbook starts.
COPY scripts/openbao-exec-env.sh /usr/local/bin/openbao-exec-env.sh
RUN chmod +x /usr/local/bin/semaphore-run-ansible.sh /usr/local/bin/openbao-exec-env.sh

# Drop back to the image's own unprivileged user for runtime.
USER semaphore
