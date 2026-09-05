# Runbook

## Availability

The platform VM's node now runs 24/7 — its former nightly
power-off (~22:00) was removed (ansible-proxmox#354). Notes that still apply:

- **State is off-node.** State objects live in RustFS on a different node,
  independent of the platform VM. A run killed mid-flight leaves the workspace
  lock held — see "Stuck workspace lock" below.
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
(curl, jq, ssh, git, and the OpenBao CLI) on top of the pinned upstream image.

**Nothing is created in the Semaphore UI.** The project, repositories,
inventories, environment, templates and schedules are declared in
`tofu/semaphore/` and applied as a Terrakube job, the same way `tofu/terrakube/`
declares Terrakube's own organization and workspaces. Creating any of these by
hand produces an object OpenTofu does not manage and will not reconcile.

Two things that are *not* in that root, each for a stated reason:

- **The API token it authenticates with.** Minted by
  `scripts/provision-semaphore-token.sh` against the local break-glass admin and
  merge-patched into the platform KV path. Generate-if-absent, called from
  `deploy.sh`, so it is a no-op on every deploy after the first. A token cannot
  be a compose variable because it can only be minted against a server that is
  already up and migrated.
- **The run credentials.** `BAO_ADDR`, the ansible-converge AppRole pair, the
  Splunk HEC token and the Nautobot read-only token are passed into the
  container by `compose/docker-compose.yml` and inherited by every task process.
  They are deliberately *not* Semaphore Environment secrets: that provider
  persists a secret's value in OpenTofu state, and this estate mints credentials
  rather than copying them. `deploy.sh` warns by name when one is absent.

Two inventories are declared, and the second is a gate rather than a duplicate:
`homelab-tofu` points at `inventory/hosts.yml`, whose hosts are added by the
`load_tofu` play at run time, and `homelab-nautobot` points at the existing
opt-in Nautobot GraphQL inventory. Neither stores a copy of any host. A
scheduled, read-only drift report compares the two, which is the evidence a
future cutover to Nautobot-sourced inventory should rest on.

Schedules exist only for templates marked non-mutating. The gate is derived from
that mark, not maintained by hand, and a precondition fails the plan if a cron
is declared for a mutating template or a non-mutating one silently loses its
schedule.

Every Ansible template invokes the recap wrapper, which is on `PATH` in the
image:

```bash
semaphore-run-ansible.sh ./scripts/run-ansible.sh <playbook> \
  --limit <hosts>,localhost --diff
```

The wrapper also loads the run environment before the playbook starts. The
playbooks read plain environment variables and are indifferent to the secrets
manager behind them; the wrapper re-execs itself through
`openbao-exec-env.sh` over three KV documents, one per mount, so every value
lives on exactly one tier:

| Document | Holds |
| --- | --- |
| `config/platform/ansible/env` | topology: addresses, names, identifiers |
| `secret/platform/ansible/env` | internal-only secrets |
| `secrets-external/platform/ansible/env` | secrets reachable from the public internet |

The ansible-converge AppRole reads all three. A converge of the OpenBao nodes
themselves is the one run that does not go through Semaphore: its inputs are
the seal key and the provisioning identities, which cannot be served by the
store they unseal, so that play runs from a workstation under the run wrapper
for secret zero.

Two non-negotiable details, both burned this estate before:

- `--limit` must always include `localhost`, or the tofu-inventory load
  silently no-ops and the play does nothing at rc 0.
- `--diff` only — never add a `--check` dry-run step.

A third failure mode, just observed: `run-ansible.sh` can exit 0 on a run
interrupted mid-play with no PLAY RECAP, reading as a no-op success on what
was actually a half-finished converge (tracked upstream as Vikunja 1843;
the ansible-proxmox* repos likely carry the same copy of that script and
are covered by 1843, not by this wrapper). `semaphore-run-ansible.sh`
(baked into the Semaphore image by the Dockerfile above, on `PATH`) wraps the call
instead of papering over it here: no recap at all means the run state is
UNKNOWN and is treated as a failure, a recap with any failed/unreachable
host is a failure, and a recap covering only `localhost` (the real target
host never ran) is also a failure — evaluated only once a recap actually
exists, never inferred from its absence. Every template should call it
instead of `run-ansible.sh` directly.

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
