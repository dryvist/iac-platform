# Bootstrap (first-time bring-up)

One-time sequence from zero to a working platform. Ongoing operations live in
[runbook.md](runbook.md).

## Prerequisites (manual, outside this repo)

1. **VM + ingress applied** — tofu-proxmox PR with the `iac-platform` VM
   (deployment.json), the six ingress rows, and the `iac_platform_ports`
   constants is merged and applied. `<vm-fqdn>` resolves and is
   SSH-reachable; `terrakube*.<domain>` / `semaphore.<domain>`
   route (502 until the stack is up — expected).
2. **OpenBao OIDC provider and client**: configure the `terrakube` provider,
   identity scopes for `profile`, `email`, and `groups`, and a confidential Dex
   client whose redirect URI is
   `https://terrakube-dex.<domain>/dex/callback`. Assign only the OpenBao
   `terrakube-admins` identity group. Store the resulting issuer, client ID, and
   client secret at `secret/platform/terrakube/main` as
   `OPENBAO_OIDC_ISSUER`, `DEX_OPENBAO_CLIENT_ID`, and
   `DEX_OPENBAO_CLIENT_SECRET`.
3. **Terrakube workload signing key**: create an RSA key pair for Terrakube's
   per-job JWTs. Store the public PEM and unencrypted PKCS#8 private PEM at the
   same OpenBao path as `TK_DYNAMIC_CREDENTIAL_PUBLIC_KEY` and
   `TK_DYNAMIC_CREDENTIAL_PRIVATE_KEY`. The compose deployment mounts them as
   environment-sourced Docker secrets; neither key is committed.
4. **RustFS bucket + access key**: create bucket `terrakube` and an access
   key pair matching `TK_OUTPUT_ACCESS_KEY`/`TK_OUTPUT_SECRET_KEY` in OpenBao
   (`secret/platform/terrakube/main`; RustFS console at
   `https://object-storage.<domain>`).
   When using `aws --endpoint-url https://s3.<domain>`, ensure an unrelated
   `AWS_SESSION_TOKEN` is unset — RustFS
   rejects requests carrying an STS session token ("check claims failed /
   invalid token2").
5. **Docker engine on the VM**: Docker CE + compose plugin from the official
   Docker apt repo (Debian bookworm's own `docker-compose` is v1 — too old for
   this compose file); deploy user in the `docker` group.
6. **Native OpenBao access**: authenticate with an enabled human or workload
   method and export `BAO_ADDR` plus its short-lived `BAO_TOKEN`. No cloud
   secret store or keychain participates in this flow.

Platform-VM facts recorded during first bring-up: the VM's CPU type must be
`x86-64-v2` (its node's Nehalem Xeons lack AES-NI, so the terraform module's
`x86-64-v2-AES` default cannot boot there — set in deployment.json), and the
clone template must exist on the target node (offline-migrate it over and back
via the Proxmox API for the one clone).

## Bring-up

```bash
./scripts/deploy.sh   # compose up (by FQDN)
./scripts/openbao-exec-env.sh secret/platform/terrakube/main -- \
  ./scripts/smoke-test.sh                 # health + S3 roundtrip
```

Browser: `https://terrakube.<domain>` → Login with OpenBao → authenticate with
an enabled OpenBao human auth method → confirm the Organizations page offers
admin actions through the `terrakube-admins` group mapping.

## Workspaces-as-code (local state first)

```bash
cd tofu/terrakube
export TERRAKUBE_ENDPOINT=https://terrakube-api.<domain>
export TERRAKUBE_TOKEN=<PAT from UI: user settings → API tokens>
export TF_VAR_openbao_address=https://openbao.<domain>
tofu init && tofu apply
```

Then migrate this stack's own state into the instance it just configured:
uncomment the `cloud {}` block in `providers.tf`, run `tofu login
terrakube-api.<domain>` once, then `tofu init` and approve the
state migration.

## OpenBao workload roles

Before a workspace can plan, the OpenBao-owning root must enable JWT auth
against Terrakube's internal discovery endpoint and create one role named
`terrakube-<workspace-name>`. Each role binds the configured audience and the
exact Terrakube organization/workspace claims, then grants only that root's
secret paths. The workspace receives only these non-secret environment values:

- `ENABLE_DYNAMIC_CREDENTIALS_VAULT=1`
- `WORKLOAD_IDENTITY_VAULT_AUDIENCE=openbao.workload.identity`
- `VAULT_ADDR=https://openbao.<domain>`
- `WORKLOAD_IDENTITY_VAULT_ROLE=terrakube-<workspace-name>`

`VAULT_ADDR` is the variable name required by Terrakube's native integration;
the endpoint and implementation are OpenBao. Validate the unauthenticated
Terrakube `/.well-known/openid-configuration` and `/.well-known/jwks` endpoints,
then prove cross-workspace denial before migrating state.

## Per-machine login (any machine, zero keychain)

```bash
tofu login terrakube-api.<domain>
```

On a machine without a global `tofu` (e.g. a nix-darwin host that only gets
it via per-repo dev shells), stay policy-compliant with an ephemeral shell:

```bash
nix shell nixpkgs#opentofu -c tofu login terrakube-api.<domain>
```

The credential lands in `~/.terraform.d/credentials.tfrc.json`; from then on
every repo with a cloud block plans/applies remotely from that machine.
