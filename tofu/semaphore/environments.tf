# One variable group per project, every template in that project runs under
# its own project's group.
#
# SECRETS ARE DELIBERATELY NOT DECLARED HERE.
#
# `semaphoreui_project_environment.secrets[].value` is marked sensitive but is
# NOT a write-only attribute in this provider, and it is not one in the
# alternative CruGlobal provider either — both were checked against their
# published schemas. A declared secret would therefore be persisted in this
# workspace's state. State is encrypted and workspace-scoped, but encrypted at
# rest is not absent, and this estate's rule is that credentials are minted
# rather than copied.
#
# So the split is explicit and mechanical:
#
#   * this file declares every NON-secret value, as code, and owns them;
#   * the secret values — the ansible-converge AppRole id/secret, the Splunk HEC
#     token, and the Nautobot read-only token — are written into EACH of these
#     five environments by scripts/deploy.sh after apply, from the OpenBao env
#     it already holds, using Semaphore's API (deploy.sh now loops the sync
#     over every project/environment pair instead of the one it used to write).
#
# Both halves are version-controlled. Neither is a manual step.
#
# There is a second, independent reason not to put them in `secrets`, and it is
# specific to how this project's templates are shaped. For a shell-type template
# Semaphore builds the command as
#
#   bash <playbook> <environment secrets as name=value> <template arguments...>
#
# — the secrets are appended as POSITIONAL ARGUMENTS, between the script name
# and the declared arguments (upstream v2.18.18, services/tasks/LocalJob.go).
# Every template here is a bash template wrapping run-ansible.sh, so a secret
# added to this environment would be spliced into the middle of that command
# line and passed to the wrapper as if it were a run-ansible.sh argument. Even
# if the provider gained a write-only variant, secrets would still not belong
# here while the templates are shell-shaped.
#
# Declarative-drift audit (semaphoreui_project_environment): the settable
# attributes are name, project_id, environment, variables and secrets.
# `environment`, `variables` and the identity fields are declared; `secrets` is
# knowingly managed out of band per the above, and is the ONLY attribute of any
# resource in this root that is not declared in tofu.
resource "semaphoreui_project_environment" "each" {
  for_each = local.semaphore_project_names

  project_id = semaphoreui_project.each[each.value].id
  name       = "homelab"

  # Process environment for the run. The store address is the one value a run
  # needs before it can read anything; everything else — including the
  # AppRole pair deploy.sh injects — is fetched from the store at run time.
  environment = {
    BAO_ADDR = local.openbao_address

    # run-ansible.sh refuses to run against a checkout that is behind its
    # remote. Semaphore clones the declared branch fresh for each task, so the
    # guard is satisfied normally and must stay armed — never set the
    # ALLOW_STALE_CHECKOUT escape hatch here.
  }

  # Ansible extra-vars. Empty by design: a converge takes its inputs from the
  # published inventory and from group_vars in the repository, and an extra-var
  # set here would override those from outside version control of the repo it
  # affects.
  variables = {}

  lifecycle {
    # `secrets` is written by deploy.sh, not by this root (see the header). Left
    # unignored, every plan would propose deleting values it cannot see.
    # `environment` holds runtime credentials injected at deploy time.
    ignore_changes = [secrets, environment]
  }
}
