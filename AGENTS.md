# AI Agents Configuration

## Repo Purpose

The homelab's central IaC management tier: **Terrakube** (OpenTofu management
plane — remote plan/apply, state + locking, workspaces-as-code) and
**Semaphore UI** (Ansible tier), one pinned docker-compose stack on the
`iac-platform` VM (pve3, mgmt VLAN). Every OpenTofu repo migrates its backend
here; terragrunt and the terraform binary are being retired fleet-wide.

## Laws and doctrine

- **FQDN LAW: never reference any system by IP:port.** Every system is reached
  via its valid-HTTPS FQDN behind the ACME wildcard cert
  (`<name>.pve.jacobpevans.com`, Traefik ingress rows in terraform-proxmox
  `ingress.tf`). This applies to configs, scripts, docs, and conversation. If
  something lacks an FQDN, add the ingress row — don't use the IP.
- **pve3 doctrine**: the platform is deliberately **not 24/7** (pve3 powers
  off nightly ~22:00). Consumers must degrade gracefully (CI reachability
  pre-check → clean skip). Never start applies near 22:00. See
  [docs/runbook.md](docs/runbook.md).
- **Zero keychain, zero passwords**: the only local secret-zero is the age key
  (`~/.config/sops/age/keys.txt`). Humans `tofu login` once per machine
  (browser); CI presents a team token via
  `TF_TOKEN_terrakube__api_pve_jacobpevans_com`. Credentials that providers
  need at apply time (e.g. tofu-github's org-admin `GITHUB_TOKEN`) live ONLY
  as sensitive Terrakube workspace variables.
- **Secrets never in git plaintext**: deploy-time secrets live in
  `secrets/platform.sops.env` (SOPS+age). `compose/.env` carries only
  non-secrets (pins, ports, hostnames).
- **The compose layer stays imperative** (`scripts/deploy.sh`): it must be
  rebuildable from git + age key + a vzdump restore even when Terrakube is
  down. Only `tofu/terrakube/` (workspaces-as-code) uses tofu — and its state
  self-hosts in Terrakube after bootstrap (see providers.tf).

## Layout

| Path | Owns |
| --- | --- |
| `compose/` | The 9-service stack (Terrakube api/ui/executor/registry, dex, valkey, postgres + backup sidecar, semaphore), pinned via `compose/.env` |
| `secrets/` | `.sops.yaml` (age recipient) + `platform.sops.env` (encrypted) |
| `tofu/terrakube/` | Workspaces-as-code: org, admin team, CI team token, one `terrakube_workspace_cli` per consuming repo + their sensitive variables |
| `scripts/` | `deploy.sh` (sops exec-env → docker --host ssh compose up), `smoke-test.sh` |
| `docs/` | [bootstrap.md](docs/bootstrap.md) (first bring-up), [runbook.md](docs/runbook.md) (operations) |

## Conventions

- Host ports 28080-28084 must stay in lockstep with `iac_platform_ports` in
  terraform-proxmox `constants.tf` — the ingress rows reference those
  constants, this repo's `compose/.env` carries the same numbers.
- The Terrakube **executor is never published or fronted** — API-internal only.
- Image pins bump in `compose/.env` only (renovate-tracked); redeploy + smoke
  test after every bump. Manual `pg_dumpall` before major bumps.
- Conventional commits; GPG-signed; never commit secrets — store references.
- Onboarding a new consumer repo = one `terrakube_workspace_cli` (+ sensitive
  workspace variables) in `workspaces.tf`, then the repo's own cloud block.

## Applying

- `tofu/terrakube/` authenticates via `TERRAKUBE_ENDPOINT` + `TERRAKUBE_TOKEN`
  env vars (PAT from the UI, or team token). `TF_VAR_github_org_admin_token`
  supplies the tofu-github workspace secret — via env at apply, never a file.
- `deploy.sh` needs: age key locally, SSH to `iac.pve.jacobpevans.com`,
  pve3 powered on.
