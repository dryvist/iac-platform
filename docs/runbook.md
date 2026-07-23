# Runbook

## Availability

The platform VM lives on pve3, which now runs 24/7 — the node's former nightly
power-off (~22:00) was removed (ansible-proxmox#354). Notes that still apply:

- **State is off-node.** State objects live in RustFS on pve1, independent of
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
2. vzdump of the whole VM (schedule inside the pve3 on-window).
3. RustFS LXC is on pve1 under the existing snapshot/replication layers.
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
- Semaphore OIDC via the same dex (drops the local admin password) + project
  wiring for the ansible repos.
- Prometheus scrape (Spring actuator + cAdvisor) via the existing prometheus LXC.
- Dedicated RustFS access policy (today: dedicated key, full-access MVP).
