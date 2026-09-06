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

# The OpenBao CLI scripts/run-ansible.sh uses to log in and mint the SSH cert.
# Alpine 3.21 community ships openbao 2.1.0 and edge ships 2.6.1, neither of
# which is the version the fleet runs, so the pinned official release archive
# is installed instead and verified against the release's checksums file.
# renovate: datasource=github-releases depName=openbao/openbao extractVersion=^v(?<version>.*)$
ARG BAO_VERSION=2.5.5

USER root
RUN apk add --no-cache curl jq openssh-client git bash py3-pip py3-requests \
    && for venv in /opt/semaphore/apps/ansible/*/venv; do [ -d "$venv" ] && "$venv/bin/pip" install --no-cache-dir hvac || true; done \
    && mkdir -p /usr/lib/python3.12/site-packages \
    && echo "/opt/semaphore/apps/ansible/13.5.0/venv/lib/python3.12/site-packages" > /usr/lib/python3.12/site-packages/venv.pth

RUN set -eu \
    && case "$(apk --print-arch)" in \
         aarch64) BAO_ARCH=arm64 ;; \
         x86_64)  BAO_ARCH=x86_64 ;; \
         *) echo "unsupported arch: $(apk --print-arch)" >&2; exit 1 ;; \
       esac \
    && cd /tmp \
    && curl -fsSLO "https://github.com/openbao/openbao/releases/download/v${BAO_VERSION}/bao_${BAO_VERSION}_Linux_${BAO_ARCH}.tar.gz" \
    && curl -fsSLO "https://github.com/openbao/openbao/releases/download/v${BAO_VERSION}/checksums-linux.txt" \
    && grep " bao_${BAO_VERSION}_Linux_${BAO_ARCH}.tar.gz$" checksums-linux.txt | sha256sum -c - \
    && tar -xzf "bao_${BAO_VERSION}_Linux_${BAO_ARCH}.tar.gz" bao \
    && install -m 0755 bao /usr/local/bin/bao \
    && rm -f "bao_${BAO_VERSION}_Linux_${BAO_ARCH}.tar.gz" checksums-linux.txt bao \
    && bao version

# The PLAY RECAP assertion wrapper every Ansible template invokes instead of
# calling run-ansible.sh directly — see the script for why.
COPY scripts/semaphore-run-ansible.sh /usr/local/bin/semaphore-run-ansible.sh
# The KV-to-environment exporter the wrapper re-execs through to load the run
# environment before the playbook starts.
COPY scripts/openbao-exec-env.sh /usr/local/bin/openbao-exec-env.sh
# The git credential helper. Installed WITHOUT the .sh suffix because git
# resolves `credential.helper openbao` to `git-credential-openbao` on PATH.
COPY scripts/git-credential-openbao.sh /usr/local/bin/git-credential-openbao
RUN chmod +x /usr/local/bin/semaphore-run-ansible.sh /usr/local/bin/openbao-exec-env.sh \
      /usr/local/bin/git-credential-openbao

# Every github.com clone — repositories and their submodules alike — gets an
# ephemeral installation token minted per request instead of a stored
# credential. System scope so it applies to every git process in the
# container, whichever user runs it; scoped to github.com so no other host
# consults it. The username is the App-token convention; the helper emits it
# too, so a partial read still authenticates.
RUN git config --system credential.https://github.com.helper openbao \
    && git config --system credential.https://github.com.username x-access-token

# Drop back to the image's own unprivileged user for runtime.
USER semaphore
