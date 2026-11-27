# The converge agent's own Semaphore identity: a local, non-admin user that is
# a `task_runner` in every project and nothing more.
#
# Why a separate user rather than the automation token tofu itself uses: a
# Semaphore API token carries its owner's full privileges with no scoping
# (scripts/provision-semaphore-token.sh). The break-glass admin's token can
# edit templates, keys and repositories; an agent holding it could rewrite
# what a template runs and then run it. `task_runner` can list and run the
# templates declared here and read their output, but cannot change a
# template, a repository, an inventory, a key or another user. So the agent's
# worst case is "ran a reviewed template", never "changed what one runs".
#
# The agent's API token is minted for this login by
# `scripts/provision-semaphore-token.sh agent` and published to the agent-tier
# OpenBao leaf its router tier reads. The login below and that script's agent
# profile are two literals by necessity (this root reads no compose or script
# value at run time); tests/agent_user_contract.tftest.hcl fails `tofu test`
# if they drift.
#
# Declarative-drift audit (semaphoreui_user): settable attributes are
# username, name, email, admin, alert, external and one of password /
# password_wo (+ password_wo_version). All are declared. `password` is
# deliberately absent: the user never logs in interactively, so its password
# is a random value sent once as a write-only argument, never stored in state
# or plan, and known to no one. uuid() draws from crypto/rand; two of them
# give 244 random bits. Bump password_wo_version only to rotate that unknown
# value, which changes nothing the agent uses.
#
# `external = false` on purpose: an external user is matched by the OIDC login
# flow, so a Dex identity that happened to share this login could sign in as
# the agent. A local user with an unknowable password cannot be reached that
# way or any other except through its API token.
resource "semaphoreui_user" "agent" {
  username = "semaphore-agent"
  name     = "Semaphore converge agent"
  # A local mailbox name under the internal base domain, which is derived at
  # run time (providers.tf) and never committed. Nothing is ever sent to it:
  # alert is off.
  email = "semaphore-agent@${local.base_domain}"

  admin    = false
  alert    = false
  external = false

  password_wo         = "${uuid()}${uuid()}"
  password_wo_version = 1
}

# Declarative-drift audit (semaphoreui_project_user): the settable attributes
# are project_id, user_id and role; `name` and `username` are computed. All
# three are declared. One membership per project, so a new run lane in
# project.tf grants the agent nothing until it exists, and then exactly this.
resource "semaphoreui_project_user" "agent" {
  for_each = semaphoreui_project.each

  project_id = each.value.id
  user_id    = semaphoreui_user.agent.id
  role       = "task_runner"
}
