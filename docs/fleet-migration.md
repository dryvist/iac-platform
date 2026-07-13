# Fleet State Migration

All nine workspace configurations are declared in `tofu/terrakube`. Code
conversion does not authorize state or infrastructure changes.

For each workspace, in an approved production window:

1. Seed its exact-claim OpenBao JWT role and native secret paths.
2. Confirm the private Terrakube endpoint, provider/module mirror, and RustFS
   storage are reachable with general WAN egress blocked.
3. Snapshot the legacy state and verify its serial, lineage, and resource list.
4. Import the snapshot into the matching Terrakube workspace under its native
   lock. Preserve the snapshot outside the new state store for rollback.
5. Run a refresh-only plan. Any resource replacement or unplanned mutation is
   a stop condition.
6. Run the repository's complete static and contract test suites.
7. Perform one approved full plan/apply, validate downstream inventory and
   services, then begin the retention period.
8. Retire legacy state objects, lock tables, IAM roles, and local credential
   profiles only after the retention period and a restore drill.

Never use targeted apply during migration. Never copy provider credentials
into a workspace variable; Terrakube workload identity and OpenBao remain the
only machine path.

## Break-glass recovery (Terrakube or the platform is down)

Terrakube, its Postgres lock store, RustFS (state + `deployment.json`), and
OpenBao all run on guests that `tofu-proxmox` itself provisions. A dead control
plane therefore cannot be repaired through Terrakube — the tool that would fix
it depends on the thing that is broken. Two escape hatches exist. Both are
single-operator, gated paths, not routine operations.

### 1. Recover the platform guests from vzdump

`iac-platform` (Terrakube + Postgres + Dex) and the OpenBao guests are LXCs on
the Proxmox cluster. Restore the most recent vzdump for the affected guest, then
start it (VMID resolves from the tofu inventory by hostname; node and storage
pool are placeholders):

```bash
# on a surviving Proxmox node (proxmox-N)
pct restore <VMID> /var/lib/vz/dump/vzdump-lxc-<VMID>-<timestamp>.tar.zst --storage <pool>
pct start <VMID>
```

Terrakube's run history and workspace locks live in its Postgres, so restoring
the Postgres volume restores the locks. Once the platform answers, resume normal
Terrakube runs — do **not** use the direct-backend path below unless the
platform genuinely cannot be recovered.

### 2. Apply `tofu-proxmox` directly against the RustFS S3 backend

When Terrakube cannot be brought back, `tofu-proxmox` can plan/apply against the
RustFS state bucket directly. RustFS lives on a Proxmox storage node, not on the
platform VM, so its state survives a platform loss.

Add a temporary backend override on a throwaway break-glass branch — never
commit it to a release branch:

```hcl
# backend-override.tf — DELETE after recovery
terraform {
  backend "s3" {
    bucket                      = "<rustfs-state-bucket>"
    key                         = "tofu-proxmox/terraform.tfstate"
    endpoints                   = { s3 = "https://rustfs.${PROXMOX_DOMAIN}" }
    region                      = "us-east-1" # RustFS ignores region; any value
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}
```

RustFS S3 credentials come from OpenBao `secret/platform/object-storage` when
OpenBao is up:

```bash
export AWS_ACCESS_KEY_ID=$(bao kv get -field=access_key secret/platform/object-storage)
export AWS_SECRET_ACCESS_KEY=$(bao kv get -field=secret_key secret/platform/object-storage)
```

If OpenBao is also down, this is a full break-glass: read the RustFS root
credentials from the SOPS-bootstrap material (the sanctioned OpenBao-down
fallback), never from a machine identity. Then:

```bash
tofu init -reconfigure
tofu state pull > tofu-proxmox-breakglass.tfstate  # snapshot BEFORE any change
tofu plan   # full plan, never -target
tofu apply
```

> **Single-operator rule.** The direct S3 backend cannot see Terrakube's
> Postgres lock. Two operators — or one operator plus a recovering Terrakube —
> writing this state concurrently will corrupt it. Before using this path:
> confirm Terrakube is down, hold the `flow-lock --flow tofu-breakglass` lease
> (or the documented single-operator token), and be the only writer. Remove
> `backend-override.tf` and return to Terrakube runs the moment the platform is
> healthy.
