# Adds the tools scripts/run-ansible.sh needs (an ephemeral OpenBao-signed SSH
# cert, ansible-playbook is invoked from the checked-out Ansible repo itself)
# on top of the upstream Semaphore image. SEMAPHORE_VERSION is a build arg
# fed from compose/.env.example by docker-compose.yml (build.args), so the
# version is tracked in exactly one place (the renovate-managed pin), not
# duplicated here as a second literal that can drift from it. No default: a
# bare `docker build` without --build-arg fails instead of silently
# resolving to a stale image.
ARG SEMAPHORE_VERSION
FROM semaphoreui/semaphore:${SEMAPHORE_VERSION}

# The OpenBao CLI scripts/run-ansible.sh uses to log in and mint the SSH cert.
# Alpine 3.21 community ships openbao 2.1.0 and edge ships 2.6.1, neither of
# which is the version the fleet runs, so the pinned official release archive
# is installed instead and verified against the release's checksums file.
# renovate: datasource=github-releases depName=openbao/openbao extractVersion=^v(?<version>.*)$
ARG BAO_VERSION=2.5.5

USER root
# Every tool and library below is reached by a role that runs ON THE
# CONTROLLER, so a missing one fails the play rather than the target. Each
# was found the same way: an outage whose message named something else.
#   openssl     generating credential material in the secrets-seeding roles
#   bind-tools  the resolution fallbacks (dig) in routing and object storage
#   netaddr     address filters in the identity and inventory roles
#   proxmoxer   the guest start/verify modules
#   hvac        secret-store access
#   paramiko    the container connection transport
#   opentelemetry-{api,sdk,exporter-otlp}
#               the community.general.opentelemetry callback plugin's run
#               tracing (ansible-proxmox-ai ansible.cfg)
# Verified present in the base image and therefore NOT repeated here:
# boto3/botocore, jmespath, cryptography, passlib, gpg/gpgv.
RUN apk add --no-cache curl jq openssh-client git bash py3-pip py3-requests aws-cli openssl bind-tools \
    && for venv in /opt/semaphore/apps/ansible/*/venv; do [ -d "$venv" ] && "$venv/bin/pip" install --no-cache-dir hvac paramiko netaddr proxmoxer opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp || true; done \
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
# semaphore-runner's entrypoint override (docker-compose.yml): creates the
# Ansible warm-cache subdirectories under the semaphore_runner_data volume
# before `semaphore runner start` — see the script for why this can't be a
# build-time RUN mkdir.
COPY scripts/semaphore-runner-entrypoint.sh /usr/local/bin/semaphore-runner-entrypoint.sh
RUN chmod +x /usr/local/bin/semaphore-run-ansible.sh /usr/local/bin/openbao-exec-env.sh \
      /usr/local/bin/git-credential-openbao /usr/local/bin/semaphore-runner-entrypoint.sh

# Every github.com clone — repositories and their submodules alike — gets an
# ephemeral installation token minted per request instead of a stored
# credential. System scope so it applies to every git process in the
# container, whichever user runs it; scoped to github.com so no other host
# consults it. The username is the App-token convention; the helper emits it
# too, so a partial read still authenticates.
RUN git config --system credential.https://github.com.helper openbao \
    && git config --system credential.https://github.com.username x-access-token

# hermes_agent's content-bundle build runs on THIS controller, never on a
# target guest (roles/hermes_agent/tasks/assert_curriculum_and_policy.yml
# asserts `nix --version` before any config deploys, delegate_to: localhost).
# Without this, that assert fails on every hermes_agent/hermes_ui_docker
# converge. Alpine's own community repo ships nix natively for musl (no
# glibc-only installer needed) — install it in single-user mode: no daemon,
# no nixbld build users, /nix owned by the unprivileged runtime user.
RUN apk add --no-cache nix \
    && mkdir -p /etc/nix \
    && printf 'sandbox = false\nexperimental-features = nix-command flakes\n' > /etc/nix/nix.conf \
    && mkdir -p /nix \
    && chown -R semaphore:root /nix /etc/nix

# Drop back to the image's own unprivileged user for runtime.
USER semaphore
