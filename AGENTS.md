# AI Agents Configuration

## Repo Purpose

The homelab's central IaC management tier: **Terrakube** (OpenTofu management
plane — remote plan/apply, state + locking, workspaces-as-code) and
**Semaphore UI** (Ansible tier), one pinned docker-compose stack on the
`iac-platform` VM (pve3, mgmt VLAN). Every OpenTofu repo migrates its backend
here; terragrunt and the terraform binary are being retired fleet-wide.

## Laws and doctrine

- **No real domain in committed files.** `<domain>` in these docs is the
  internal base domain; the real value lives ONLY in OpenBao
  (`secret/platform/terrakube/main` — `DOMAIN`, `DEPLOY_HOST`,
  `TK_OUTPUT_ENDPOINT`, `SEMAPHORE_ADMIN_EMAIL`) and reaches compose/dex via
  `scripts/openbao-exec-env.sh`. Same for every consumer repo: tofu cloud blocks
  stay empty and take `TF_CLOUD_HOSTNAME` from the environment (also pulled from
  that OpenBao path).
- **FQDN LAW: never reference any system by IP:port.** Every system is reached
  via its valid-HTTPS FQDN behind the ACME wildcard cert
  (`<name>.<domain>`, Traefik ingress rows in tofu-proxmox
  `ingress.tf`). This applies to configs, scripts, docs, and conversation. If
  something lacks an FQDN, add the ingress row — don't use the IP.
- **pve3 doctrine**: the platform is deliberately **not 24/7** (pve3 powers
  off nightly ~22:00). Consumers must degrade gracefully (CI reachability
  pre-check → clean skip). Never start applies near 22:00. See
  [docs/runbook.md](docs/runbook.md).
- **OpenBao owns Terrakube identity and secrets**: Dex delegates human login to
  OpenBao OIDC. Terrakube jobs exchange their signed workspace identity for a
  short-lived, least-privilege OpenBao token. Never store provider credentials
  as Terrakube workspace variables; workspaces contain only the four non-secret
  dynamic-credential controls. Humans `tofu login` once per machine (browser).
  There is deliberately no CI plan/apply and no CI token.
- **Secrets never in git plaintext**: deploy-time secrets live in OpenBao
  (`secret/platform/terrakube/main`), fetched at deploy by
  `scripts/openbao-exec-env.sh`. `compose/.env` carries only non-secrets (pins,
  ports, hostnames).
- **The compose layer stays imperative** (`scripts/deploy.sh`): it must be
  rebuildable from git + the Doppler AppRole (→ OpenBao) + a vzdump restore even
  when Terrakube is down. Only `tofu/terrakube/` (workspaces-as-code) uses
  tofu —
  and its state self-hosts in Terrakube after bootstrap (see providers.tf).

## Layout

- `compose/`: pinned Terrakube, Dex, Valkey, PostgreSQL, and Semaphore stack.
- `tofu/terrakube/`: organization, team, workspaces, and non-secret OpenBao
  workload-identity controls.
- `scripts/`: OpenBao environment, deploy, and smoke-test entry points.
- `docs/`: bootstrap, migration, and operations runbooks.

## Conventions

- Host ports 28080-28084 must stay in lockstep with `iac_platform_ports` in
  tofu-proxmox `constants.tf` — the ingress rows reference those
  constants, this repo's `compose/.env` carries the same numbers.
- The Terrakube **executor is never published or fronted** — API-internal only.
- Image pins bump in `compose/.env` only (renovate-tracked); redeploy + smoke
  test after every bump. Manual `pg_dumpall` before major bumps.
- Conventional commits; GPG-signed; never commit secrets — store references.
- Onboarding a new consumer root = one `terrakube_workspace_cli` in
  `workspaces.tf`, an exact-claim OpenBao JWT role in the OpenBao-owning repo,
  then the consumer's own cloud block. Provider secrets stay in OpenBao.

## Applying

- `tofu/terrakube/` authenticates via `TERRAKUBE_ENDPOINT` + `TERRAKUBE_TOKEN`
  env vars (PAT from the UI). `TF_VAR_openbao_address` supplies the non-secret
  internal OpenBao HTTPS endpoint; provider credentials never pass through this
  configuration.
- `deploy.sh` needs: age key locally, SSH to `<vm-fqdn>`,
  pve3 powered on.
