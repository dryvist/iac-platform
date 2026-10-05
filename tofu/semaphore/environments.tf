# The variable group every template runs under, one per project.
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
#   * this file declares the Semaphore environment resources and their seed
#     values;
#   * scripts/deploy.sh synchronizes the complete runtime environment map,
#     including the AppRole pair, HEC token, Nautobot token and non-secret
#     workspace selectors, from its process environment using Semaphore's API.
#     Tofu ignores that map because it cannot safely manage only selected keys.
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
resource "semaphoreui_project_environment" "homelab" {
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
    # `environment` holds the complete runtime map injected at deploy time;
    # that map includes values this resource cannot safely manage in state.
    ignore_changes = [secrets, environment]
  }
}

moved {
  from = semaphoreui_project_environment.homelab
  to   = semaphoreui_project_environment.homelab["apps"]
}
