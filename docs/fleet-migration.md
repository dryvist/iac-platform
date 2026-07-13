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
