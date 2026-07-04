# Fleet migration: every OpenTofu repo onto Terrakube

Goal state: **all** IaC repos plan/apply through this platform; terragrunt and
the terraform binary retired; the AWS state estate decommissioned. tofu-github
is the pathfinder (no prior state — clean cut). Everything below has **real S3
state** and follows the standard rollout.

## Standard per-repo rollout checklist

1. **Workspace as code** (this repo): add a `terrakube_workspace_cli` (+ any
   sensitive workspace variables the provider needs) to
   `tofu/terrakube/workspaces.tf`; apply.
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
   `terrakube-api.pve.jacobpevans.com`, its workspace name).
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
- `path_relative_to_include()` state keys (terraform-aws, tf-splunk-aws
  dev/stg/prod) become **one Terrakube workspace per env/root**
  (`tf-splunk-aws-dev`, …) — workspace-per-directory replaces key-per-directory.
- Generated `backend.tf` files (terragrunt `remote_state.generate`) are
  deleted; the committed `cloud {}` block replaces them.
- Once the last repo migrates, drop terragrunt (and the terraform binary)
  from nix-devenv shells; `tofu` only. The pre-commit-terraform hooks exec
  the `terraform` binary by default — export `PCT_TFPATH=tofu` from the nix
  devshell env (supported ≥ v1.86; terraform-proxmox already does this).

## Migration order (dependencies first, riskiest last)

| # | Repo | Workspace(s) | Sensitive workspace vars | Notes |
|---|------|--------------|--------------------------|-------|
| 1 | tofu-github | `tofu-github` | `GITHUB_TOKEN` (admin:org) | Pathfinder; no prior state; PR open |
| 2 | docs-starlight/infra | `docs-starlight` | `CLOUDFLARE_API_TOKEN` | Kills a macOS-keychain dep; small state |
| 3 | tofu-unifi | `tofu-unifi` | `UNIFI_*` set | Kills the other keychain dep; WLAN SOPS layer stays in-repo |
| 4 | tf-splunk-aws | `tf-splunk-aws-{dev,stg,prod}` | `CRIBL_*`, `SPLUNK_PASSWORD` | 3 workspaces replace path-keys |
| 5 | terraform-aws | `terraform-aws-*` per root | — (AWS provider creds, see below) | Provider-drift cleanup first (`~>5` vs `~>6`) |
| 6 | **terraform-proxmox** | `terraform-proxmox`, `terraform-proxmox-aws-infra` | `PROXMOX_VE_*`, OpenBao AppRole | **Bootstrap-loop caveat below** |
| 7 | terraform-runs-on | `terraform-runs-on` | — | LAST: its GitHub-OIDC CI apply works today; migrate once the platform is proven, or keep hybrid |

Skip/retire without migrating: terraform-aws-bedrock (dead), 
terraform-aws-static-website (decommissioning), tofu-aws-templates
(template repo, no state; archive once the last consumer leaves AWS).

**AWS provider credentials after migration**: repos whose *resources* live in
AWS (tf-splunk-aws, terraform-aws, runs-on) still need AWS provider creds at
run time even though state no longer does. Options, in preference order:
static creds as sensitive workspace vars (rotatable, MVP), or a Terrakube
executor-level OIDC/role story (phase 2 investigation). The `tf-<project>`
*state* roles still die either way.

## The terraform-proxmox bootstrap loop (accepted, mitigated)

terraform-proxmox provisions the VM/ingress this platform runs on. After its
state migrates, fixing a dead platform via tofu requires the platform. This
is accepted because the escape hatches are cheap and documented:

- The platform restores without tofu: vzdump restore + `deploy.sh`
  (imperative, needs only git + age key) — see runbook.md.
- Before migrating terraform-proxmox, take a `tofu state pull > backup.tfstate`
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

| Doc | Change |
|-----|--------|
| Each migrated repo's README/AGENTS.md | Applying + state-backend sections → Terrakube flow |
| `${GIT_HOME}/AGENTS.md` | Token-tier + transport notes lose their aws-vault references; add Terrakube auth pattern |
| `~/CLAUDE.local.md` | AWS state-backend section → retired; keep tier table for GitHub tokens only |
| `${GIT_HOME}/REPOS.md` | iac-platform entry; per-repo backend notes |
| docs-starlight | hosts page for VM 110030 (`iac`), platform service page, this migration's ADR |
| nix-home / nix-devenv | Drop terragrunt/terraform/aws-vault from shells as the tail completes |
