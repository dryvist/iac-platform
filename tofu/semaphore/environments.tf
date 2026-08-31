# The variable group every template runs under.
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
#     token, and the Nautobot read-only token — are written into this same
#     environment by scripts/deploy.sh after apply, from the OpenBao env it
#     already holds, using Semaphore's API.
#
# Both halves are version-controlled. Neither is a manual step. If the provider
# ever gains a write-only variant for `secrets`, move that half here and delete
# the deploy.sh block — that is a strict improvement, not a redesign.
#
# Declarative-drift audit (semaphoreui_project_environment): the settable
# attributes are name, project_id, environment, variables and secrets.
# `environment`, `variables` and the identity fields are declared; `secrets` is
# knowingly managed out of band per the above, and is the ONLY attribute of any
# resource in this root that is not declared in tofu.
resource "semaphoreui_project_environment" "homelab" {
  project_id = semaphoreui_project.homelab.id
  name       = "homelab"

  # Process environment for the run. These are addresses and switches, not
  # credentials — the credentials they point at are fetched at run time by
  # run-ansible.sh using the AppRole that deploy.sh injects.
  environment = {
    BAO_ADDR     = var.openbao_address
    NAUTOBOT_URL = var.nautobot_url

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
    ignore_changes = [secrets]
  }
}
