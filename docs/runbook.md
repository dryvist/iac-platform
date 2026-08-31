# Runbook

## Availability

The platform VM's node now runs 24/7 — its former nightly
power-off (~22:00) was removed (ansible-proxmox#354). Notes that still apply:

- **State is off-node.** State objects live in RustFS on a different node, independent of
  the platform VM. A run killed mid-flight leaves the workspace lock held — see
  "Stuck workspace lock" below.
- **No CI plan/apply**: plan/apply run from a local CLI or the UI, never CI —
  this is the security model, not a power constraint. Static repository checks
  remain independent.
- Backup jobs: vzdump for the VM; the in-stack pg_dump sidecar runs ~12:00.

## Stuck workspace lock (run killed mid-flight)

Terrakube holds locks in its own DB (not in RustFS). After an ungraceful stop:
UI → organization → workspace → release the lock (or via API with a PAT).
Then re-run the plan; remote runs are idempotent up to the apply boundary.

## RustFS compatibility (top MVP risk)

Terrakube's Java AWS SDK talks to RustFS through `https://s3.<domain>`
(path-style). If state writes fail with checksum/XML errors after an image
bump, suspect SDK flexible-checksums vs RustFS. Contained fallback: re-add the
upstream reference's bundled minio service to the compose file temporarily and
point `TK_OUTPUT_ENDPOINT` at it while investigating.

## Backups / restore

Precious state = postgres volume (Terrakube org/workspace/lock DB + Semaphore)
and the RustFS `terrakube` bucket (tfstate/outputs). Layers:

1. `postgres-backup` sidecar: daily `pg_dumpall` ~12:00 into
   `/var/lib/platform/backups` on the VM disk (keeps ~14).
2. vzdump of the whole VM (schedule inside the node's on-window).
3. The RustFS LXC is on another node under the existing snapshot/replication layers.
4. Everything else is rebuildable from **git + the age key alone**:
   `deploy.sh` is deliberately imperative and never depends on Terrakube.

Restore drill: restore VM from vzdump → stack auto-starts → if postgres is
inconsistent, `psql < pg_dumpall-<date>.sql` → workspaces re-apply from
`tofu/terrakube` on local state if needed.

## Secret rotation

- Everything in OpenBao `secret/platform/terrakube/main` rotates via a KV write
  - redeploy.
- **PAT_SECRET / INTERNAL_SECRET rotation invalidates every issued Terrakube
  token** (user PATs) — plan for re-login on every machine.

## Upgrades

Image pins live in `compose/.env` (renovate-tracked). Bump → `deploy.sh` →
`smoke-test.sh`. Terrakube api runs Liquibase migrations on start; take a
manual `pg_dumpall` before major-version bumps.

## Semaphore SSO

Semaphore keeps its own local admin (`SEMAPHORE_ADMIN` / `SEMAPHORE_ADMIN_PASSWORD`)
as break-glass and additionally offers "Sign in with Authelia" via
`SEMAPHORE_OIDC_PROVIDERS` (compose/docker-compose.yml), sourced from an OIDC
client registered in Authelia (client id `semaphore`, redirect
`https://semaphore.<domain>/api/auth/oidc/authelia/redirect`). Dex gains the
same second login path for Terrakube itself (compose/dex/config.yaml, connector
id `authelia`) — see the caveat comment on that connector: an Authelia login to
Terrakube authenticates but does not currently carry the org-qualified group
the GitHub connector does, so it will not grant Terrakube admin rights until
Authelia's group claim is reshaped to match.

**Verify SSO end to end:**

1. Open `https://semaphore.<domain>`, choose "Sign in with Authelia", complete
   the Authelia login, and confirm Semaphore lands you on its dashboard as
   that user.
2. Open `https://terrakube.<domain>`, choose Authelia at the Dex login screen,
   and confirm it also authenticates (admin-group caveat above still applies).
3. If Authelia is unreachable (maintenance, misconfiguration): both apps still
   offer their original login — Semaphore's local admin, Terrakube's GitHub
   connector — so a broken Authelia integration never locks anyone out.

**Fallback to local admin:** log in to Semaphore as `SEMAPHORE_ADMIN` with
`SEMAPHORE_ADMIN_PASSWORD` (from OpenBao); it is never removed by adding SSO.

## Semaphore as the Ansible run platform

Semaphore is UI, scheduling, and audit only — the run mechanism is the same
certificate-signed SSH path a workstation converge uses
(ansible-proxmox's `scripts/run-ansible.sh`: mints an ephemeral ed25519 key,
signs it via the OpenBao SSH CA, never touches disk, revokes its OpenBao token
on exit). `compose/semaphore/Dockerfile` adds the tools that script needs
(curl, jq, ssh, git) on top of the pinned upstream image.

**One-time objects to create in the Semaphore UI:**

- Project `homelab`.
- One Repository per Ansible repo Semaphore should run — ansible-proxmox,
  ansible-proxmox-apps, ansible-proxmox-ai, ansible-splunk — all public, so
  clone over SSH (no deploy key secret needed for read).
- One secret Environment holding `BAO_ADDR`, the ansible-converge AppRole
  `OPENBAO_APPROLE_ANSIBLE_ROLE_ID`/`OPENBAO_APPROLE_ANSIBLE_SECRET_ID`, and the
  tofu-inventory variables `run-ansible.sh` and the inventory loader expect.
- An Inventory sourced from the published tofu `ansible_inventory.json`
  artifact — never a second copy of it.
- Bash-type Templates, one per playbook, each invoking:

  ```bash
  scripts/semaphore-run-ansible.sh ./scripts/run-ansible.sh <playbook> \
    --limit <hosts>,localhost --diff
  ```

  Two non-negotiable details, both burned this estate before:

  - `--limit` must always include `localhost`, or the tofu-inventory load
    silently no-ops and the play does nothing at rc 0.
  - `--diff` only — never add a `--check` dry-run step.

  A third failure mode, just observed: `run-ansible.sh` can exit 0 on a run
  interrupted mid-play with no PLAY RECAP, reading as a no-op success on what
  was actually a half-finished converge. `scripts/semaphore-run-ansible.sh`
  (baked into the Semaphore image by the Dockerfile above) wraps the call, tees
  its output, and fails the template unless a PLAY RECAP line actually landed —
  every template should call it instead of `run-ansible.sh` directly.

## Foundation blockers and hardening backlog

- Provision the nine exact-claim OpenBao JWT roles and migrate each consumer to
  ephemeral provider credentials. The workspace declarations alone do not
  grant secret access.
- Mirror the Terrakube extensions repository and Terraform compatibility
  release index inside the homelab before removing
  `TerrakubeToolsRepository` and `CustomTerraformReleasesUrl`. No internal
  endpoint exists today, so this repository deliberately does not invent one.
- Mirror pinned container images, OpenTofu releases, providers, and modules;
  then prove a clean executor run with general WAN egress blocked.
- Done: Semaphore Authelia OIDC (local admin kept as break-glass, not dropped)
  and Semaphore-as-Ansible-run-platform wiring — see "Semaphore SSO" and
  "Semaphore as the Ansible run platform" above. Remaining gap: the Dex
  `authelia` connector authenticates but does not yet carry an org-qualified
  group Terrakube's admin check accepts (see the connector's own comment) —
  reshaping Authelia's group claim, or accepting a bare-group admin check
  change in tofu/terrakube, is still open.
- Prometheus scrape (Spring actuator + cAdvisor) via the existing prometheus LXC.
- Dedicated RustFS access policy (today: dedicated key, full-access MVP).
