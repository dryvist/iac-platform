# iac-platform

Self-hosted IaC management tier: [Terrakube](https://terrakube.io) (OpenTofu
remote plan/apply, state + locking, workspaces-as-code) and
[Semaphore UI](https://semaphoreui.com) (Ansible), one pinned docker-compose
stack — zero keychain access, zero stored passwords, everything fronted by
valid-TLS FQDNs.

## Installation

First-time bring-up (VM, OAuth App, RustFS bucket, deploy, smoke test):
[docs/bootstrap.md](docs/bootstrap.md).

Dev shell (OpenTofu, OpenBao, AWS CLI):

```bash
direnv allow   # uses the committed .envrc → nix flake dev shell
```

## Usage

```bash
# Authenticate with a native OpenBao human/workload method first, then:
./scripts/deploy.sh
./scripts/openbao-exec-env.sh secret/platform/terrakube/main -- \
  ./scripts/smoke-test.sh    # health + S3 state-storage roundtrip
```

Consumer repos point their `cloud {}` block at
`terrakube-api.<domain>` and run plain `tofu plan` / `tofu apply` —
execution happens remotely on the platform's executor. Authenticate once
per machine with `tofu login terrakube-api.<domain>`; applies
confirm interactively (or via the UI's native approval templates).

Workspace onboarding is code in
[`tofu/terrakube/workspaces.tf`](tofu/terrakube/workspaces.tf). Every workspace
uses Terrakube's native OpenBao dynamic credentials: a job exchanges its signed
identity for a short-lived OpenBao token, and no provider secret is stored in a
Terrakube workspace.

The fleet foundation declares eight workspaces covering the platform itself,
GitHub governance, UniFi, production AWS, RunsOn, and three Proxmox roots.
Declaration does not migrate or apply any live state; follow the approval-gated
sequence in [docs/fleet-migration.md](docs/fleet-migration.md).

## Availability

The platform runs on a homelab node that stays powered on 24/7; its former
nightly power-off was removed (ansible-proxmox#354). Operations guidance, lock
recovery, backups, and rotation: [docs/runbook.md](docs/runbook.md).

## Contributing

Conventional commits, GPG-signed. Runtime secrets live in OpenBao
(`secret/platform/terrakube/main`), never in the repo. Image pins live in
`compose/.env`.

## License

[Apache-2.0](LICENSE)

---

Part of the homelab/dryvist ecosystem — see
[docs.jacobpevans.com](https://docs.jacobpevans.com).
