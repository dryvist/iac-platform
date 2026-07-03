# Bootstrap (first-time bring-up)

One-time sequence from zero to a working platform. Ongoing operations live in
[runbook.md](runbook.md).

## Prerequisites (manual, outside this repo)

1. **VM + ingress applied** — terraform-proxmox PR with the `iac-platform` VM
   (deployment.json), the six ingress rows, and the `iac_platform_ports`
   constants is merged and applied. `iac.pve.jacobpevans.com` resolves and is
   SSH-reachable; `terrakube*.pve.jacobpevans.com` / `semaphore.pve.jacobpevans.com`
   route (502 until the stack is up — expected).
2. **GitHub OAuth App** (dryvist org): homepage `https://terrakube.pve.jacobpevans.com`,
   callback `https://terrakube-dex.pve.jacobpevans.com/dex/callback`. Put the
   client id/secret into the sops env (`sops secrets/platform.sops.env`,
   replacing the CHANGEME values).
3. **GitHub team `terrakube-admins`** in the org, with every operator as a
   member. Login is restricted to this team; its dex group claim is the
   Terrakube admin group.
4. **RustFS bucket + access key**: create bucket `terrakube` and an access
   key pair matching `TK_OUTPUT_ACCESS_KEY`/`TK_OUTPUT_SECRET_KEY` from the
   sops env (RustFS console at `https://object-storage.pve.jacobpevans.com`).
5. **Docker engine on the VM** (docker-host precedent: Debian + docker.io/
   compose plugin; the deploy user in the `docker` group).
6. **Age key** present locally (`~/.config/sops/age/keys.txt`) — the only
   secret-zero. No keychain is used anywhere in this flow.

## Bring-up

```bash
./scripts/deploy.sh                       # compose up on the VM (by FQDN)
sops --config secrets/.sops.yaml exec-env secrets/platform.sops.env \
  ./scripts/smoke-test.sh                 # health + S3 roundtrip
```

Browser: `https://terrakube.pve.jacobpevans.com` → Login with GitHub → confirm
the Organizations page offers admin actions (admin group mapped).

## Workspaces-as-code (local state first)

```bash
cd tofu/terrakube
export TERRAKUBE_ENDPOINT=https://terrakube-api.pve.jacobpevans.com
export TERRAKUBE_TOKEN=<PAT from UI: user settings → API tokens>
export TF_VAR_github_org_admin_token=<classic PAT with admin:org>
tofu init && tofu apply
tofu output -raw ci_team_token   # → GitHub org secret TERRAKUBE_TEAM_TOKEN
                                 #   + recovery copy in Doppler ai-ci-automation/prd
```

Then migrate this stack's own state into the instance it just configured:
uncomment the `cloud {}` block in `providers.tf`, run `tofu login
terrakube-api.pve.jacobpevans.com` once, then `tofu init` and approve the
state migration.

## First consumer

Follow tofu-github's AGENTS.md "Applying" section: its cloud block points at
the `tofu-github` workspace created here; the org-admin `GITHUB_TOKEN` is
already a sensitive workspace variable — dev machines and CI never hold it.
