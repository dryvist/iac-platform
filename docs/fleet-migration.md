# Fleet migration: every OpenTofu repo onto Terrakube

Goal state: **all** IaC roots plan/apply through this platform; Terragrunt and
the Terraform binary are retired, provider secrets come from OpenBao workload
identity, and the AWS state estate is decommissioned. Workspace declarations
in this repository are foundation only: they do not authorize a state
migration or production apply.

## Declared workspace ledger

- `iac-platform` — `iac-platform/tofu/terrakube`; existing, self-host
  migration pending.
- `tofu-github` — `tofu-github`; existing pathfinder.
- `tofu-unifi` — `tofu-unifi/live`; migration pending.
- `tofu-aws-production` — `tofu-aws/environments/production`; migration
  pending.
- `tofu-runs-on` — `tofu-runs-on`; migration pending.
- `tofu-proxmox` — `tofu-proxmox`; migration pending.
- `tofu-proxmox-aws-infra` — `tofu-proxmox/aws-infra`; migration pending.
- `tofu-proxmox-vault-secrets` — `tofu-proxmox/vault-secrets`; migration
  pending.
- `tofu-proxmox-servarr-config` — `tofu-proxmox/servarr-config`; migration
  pending.

Every workspace contains only the four non-secret Terrakube/OpenBao dynamic
credential settings documented in [bootstrap.md](bootstrap.md). The matching
OpenBao role is named `terrakube-<workspace>` and must bind the exact
organization/workspace claims before the workspace is usable.

## Standard per-repo rollout checklist

1. **Workspace and identity as code**: declare the
   `terrakube_workspace_cli` here; create its exact-claim JWT role and
   least-privilege policy in the OpenBao-owning root. Provider credentials are
   never Terrakube workspace variables.
2. **Snapshot state** (last AWS-era touch): `terragrunt state pull >
   <repo>-<env>-pre-terrakube.tfstate` locally AND `aws s3 cp` to an archive
   prefix — keep the bucket read-only until the tail (step 7).
3. **Attach to the OLD backend explicitly first.** terragrunt *generated* the
   `backend "s3"` block, so a fresh clone has neither the block nor a
   `.terraform/` cache — deleting terragrunt first would leave `tofu init`
   nothing to migrate FROM (it would attach an empty workspace and the plan
   would propose recreating the world). On the migration branch: temporarily
   commit the equivalent `backend "s3" {}` + run `tofu init -backend-config=`
   with the literal bucket/key terragrunt used; verify `tofu state list`
   matches the snapshot.
4. **Backend swap**: delete `terragrunt.hcl` (and root includes — first diff
   the `.terragrunt-cache/` generated files: provider blocks, default tags,
   retry config from `generate` blocks must become committed `.tf` or they're
   silently lost), replace the s3 block with the `cloud {}` block (hostname
   `terrakube-api.<domain>`, its workspace name).
5. **Migrate state**: plain `tofu init` (with old AWS creds still in env) and
   answer **yes** to the interactive migrate prompt. NOTE (verified):
   `tofu init -migrate-state` is REJECTED with a cloud block — the plain-init
   interactive prompt is the only path. Verify the state version appears in
   the Terrakube UI and `tofu state list` count matches the snapshot.
6. **Prove no-op**: `tofu plan` (remote) must be empty. Anything else stops
   the migration for that repo.
7. **Docs**: rewrite the repo's Applying/State-backend docs; drop aws-vault
   instructions. (No CI plan/apply workflow — Terrakube's native CLI/UI flows
   only, per the simplicity directive.)
8. **Decommission tail** (per repo, LAST, after a **30-day soak** with the
   versioned bucket untouched): empty + delete the state bucket, DynamoDB
   lock table, `tf-<project>` IAM role; remove the aws-vault profile from
   nix-home `modules/home-manager/aws/tf-projects.nix`.

## Terragrunt retirement notes

- `get_aws_account_id()` disappears with the S3 backend — nothing else used it.
- `path_relative_to_include()` state keys become one Terrakube workspace per
  state root; workspace-per-directory replaces key-per-directory.
- Generated `backend.tf` files (terragrunt `remote_state.generate`) are
  deleted; the committed `cloud {}` block replaces them.
- Once the last repo migrates, drop terragrunt (and the terraform binary)
  from nix-devenv shells; `tofu` only. The pre-commit-terraform hooks exec
  the `terraform` binary by default — export `PCT_TFPATH=tofu` from the nix
  devshell env (supported ≥ v1.86; tofu-proxmox already does this).

## Migration order (dependencies first, riskiest last)

1. `tofu-github` → `tofu-github`: issue a short-lived GitHub credential and
   remove the stored PAT before further migrations.
2. `tofu-aws/environments/production` → `tofu-aws-production`: issue a
   short-lived AWS credential, flatten `root.hcl`, and preserve stable tags.
3. `tofu-unifi/live` → `tofu-unifi`: issue UniFi credentials. Require an exact
   production plan and human approval.
4. `tofu-proxmox/vault-secrets` → `tofu-proxmox-vault-secrets`: bootstrap JWT
   auth, then self-manage policies and roles. Revoke the bootstrap credential.
5. `tofu-proxmox/servarr-config` → `tofu-proxmox-servarr-config`: issue its
   application API credentials and migrate the independent state root.
6. `tofu-proxmox/aws-infra` → `tofu-proxmox-aws-infra`: issue a short-lived
   AWS credential. Public Route53 resources retain provider API egress.
7. `tofu-proxmox` → `tofu-proxmox`: issue Proxmox, RustFS, and SSH credentials;
   observe the bootstrap-loop caveat below.
8. `tofu-runs-on` → `tofu-runs-on`: issue short-lived AWS and GitHub
   credentials. Migrate last, after Terrakube is proven.

Provider credentials for AWS, GitHub, UniFi, Proxmox, and application APIs are
read from OpenBao with the workspace's short-lived token. State migration does
not remove external provider API egress for resources that intentionally live
in AWS or GitHub; it removes external state, lock, tool, auth, and secret
dependencies.

## The tofu-proxmox bootstrap loop (accepted, mitigated)

tofu-proxmox provisions the VM/ingress this platform runs on. After its
state migrates, fixing a dead platform via tofu requires the platform. This
is accepted because the escape hatches are cheap and documented:

- The platform restores without tofu: vzdump restore + `deploy.sh`
  (imperative, needs only git + age key) — see runbook.md.
- Before migrating tofu-proxmox, take a `tofu state pull > backup.tfstate`
  snapshot; a local-backend override + that snapshot rebuilds worst-case.
- RustFS (state objects) lives on pve1, not on the platform VM.

## AWS decommission tail (after ALL repos migrate)

- S3 state buckets (one per stack, three naming schemes — enumerate at
  teardown, don't trust docs), DynamoDB lock tables, `tf-*`/`tofu*` IAM
  roles + the `terraform`/`tofu` operator users, the GitHub-OIDC provider
  (unless runs-on stays hybrid), the orphaned `mfa/terraform` device.
- Local/dotfile cleanup: aws-vault profiles, `nix-home
  modules/home-manager/aws/` module (whole module goes when the last
  profile dies), `~/CLAUDE.local.md` AWS sections.

## Documentation matrix (update as repos migrate)

- Migrated repository README/AGENTS: replace applying and state-backend
  sections with the Terrakube flow.
- `${GIT_HOME}/AGENTS.md`: replace AWS state transport with OpenBao workload
  identity and Terrakube.
- `~/CLAUDE.local.md`: retire the AWS state-backend section.
- `${GIT_HOME}/REPOS.md`: record iac-platform and per-root backend status.
- docs-starlight: document the platform host, services, and migration ADR.
- nix-home/nix-devenv: remove Terragrunt, Terraform, and aws-vault at the tail.
