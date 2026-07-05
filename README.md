# iac-platform

Self-hosted IaC management tier: [Terrakube](https://terrakube.io) (OpenTofu
remote plan/apply, state + locking, workspaces-as-code) and
[Semaphore UI](https://semaphoreui.com) (Ansible), one pinned docker-compose
stack — zero keychain access, zero stored passwords, everything fronted by
valid-TLS FQDNs.

## Installation

First-time bring-up (VM, OAuth App, RustFS bucket, deploy, smoke test):
[docs/bootstrap.md](docs/bootstrap.md).

Dev shell (opentofu, sops, age, awscli):

```bash
direnv allow   # uses the committed .envrc → nix flake dev shell
```

## Usage

```bash
# Secrets come from OpenBao; the AppRole role/secret ID + BAO_ADDR are injected
# by Doppler. Both scripts run under scripts/openbao-exec-env.sh.
doppler run -p iac-conf-mgmt -c prd -- ./scripts/deploy.sh   # deploy/redeploy over SSH
doppler run -p iac-conf-mgmt -c prd -- \
  ./scripts/openbao-exec-env.sh secret/platform/terrakube/main -- \
  ./scripts/smoke-test.sh    # health + S3 state-storage roundtrip
```

Consumer repos point their `cloud {}` block at
`terrakube-api.<domain>` and run plain `tofu plan` / `tofu apply` —
execution happens remotely on the platform's executor. Authenticate once
per machine with `tofu login terrakube-api.<domain>`; applies
confirm interactively (or via the UI's native approval templates).

Workspace onboarding is code: one `terrakube_workspace_cli` resource in
[`tofu/terrakube/workspaces.tf`](tofu/terrakube/workspaces.tf).

## Availability window

The platform runs on a homelab node that powers off nightly — by design (the
IaC control plane is not a 24/7 workload). Operations guidance, lock recovery,
backups, and rotation: [docs/runbook.md](docs/runbook.md).

## Contributing

Conventional commits, GPG-signed. Runtime secrets live in OpenBao
(`secret/platform/terrakube/main`), never in the repo. Image pins live in
`compose/.env`.

## License

[Apache-2.0](LICENSE)

---

Part of the homelab/dryvist ecosystem — see
[docs.jacobpevans.com](https://docs.jacobpevans.com).
