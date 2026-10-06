# Targeted apply

The `Plan and apply (targeted)` Terrakube template (declared in
`tofu/terrakube/templates.tf`) has the same flow and the same approval gate as
`Plan and apply`: the approval step before the apply is held by the
`TERRAFORM_CLI` team. It carries no targets of its own. The target list is
supplied per job as the job's `targetAddrs` attribute, a list of resource
addresses, which the API turns into `-target` flags on the plan step. The apply
step applies that saved plan, so it covers exactly the same addresses.

```json
POST /api/v1/organization/<org-id>/job
{"data": {"type": "job", "attributes": {
   "templateReference": "<template-id>",
   "targetAddrs": ["module.example.resource_type.name"]},
  "relationships": {"workspace": {"data": {"type": "workspace", "id": "<workspace-id>"}}}}}
```

Nothing is stored on the workspace and later runs are unaffected. A
`TF_CLI_ARGS_plan` workspace variable takes precedence over `targetAddrs`, so
none may be set. Use it only to unblock an apply while unrelated drift is being
resolved: a targeted run leaves everything else unreconciled, and a full plan
follows once the drift is fixed.
