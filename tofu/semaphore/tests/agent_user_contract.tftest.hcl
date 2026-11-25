# Contract: the converge agent's Semaphore user (users.tf) stays least
# privilege, and its login equals the one scripts/provision-semaphore-token.sh
# mints the agent token for. The two are literals by necessity (users.tf), so
# this is the drift check.
#
# Reads the source text through the provider-free noop fixture, for the reason
# fixtures/noop/main.tf gives.

run "agent_user_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = regex(
      "resource \"semaphoreui_user\" \"agent\"[\\s\\S]*?username\\s*=\\s*\"([^\"]+)\"",
      file("${path.module}/../../../users.tf")
      )[0] == regex(
      "agent\\)[\\s\\S]*?LOGIN=\"([^\"]+)\"",
      file("${path.module}/../../../../../scripts/provision-semaphore-token.sh")
    )[0]
    error_message = "users.tf's agent username must equal the agent profile's LOGIN in scripts/provision-semaphore-token.sh."
  }

  assert {
    condition = can(regex(
      "resource \"semaphoreui_user\" \"agent\"[\\s\\S]*?admin\\s*=\\s*false",
      file("${path.module}/../../../users.tf")
    ))
    error_message = "The agent user must be declared non-admin: an admin token could rewrite what a template runs."
  }

  assert {
    condition = can(regex(
      "resource \"semaphoreui_user\" \"agent\"[\\s\\S]*?external\\s*=\\s*false",
      file("${path.module}/../../../users.tf")
    ))
    error_message = "The agent user must stay local (external = false), so no OIDC login can match it."
  }

  assert {
    condition = regex(
      "resource \"semaphoreui_project_user\" \"agent\"[\\s\\S]*?role\\s*=\\s*\"([^\"]+)\"",
      file("${path.module}/../../../users.tf")
    )[0] == "task_runner"
    error_message = "The agent's project role must be task_runner: it may run templates, never change them."
  }

  assert {
    condition = can(regex(
      "resource \"semaphoreui_project_user\" \"agent\"[\\s\\S]*?for_each\\s*=\\s*semaphoreui_project\\.each\\b",
      file("${path.module}/../../../users.tf")
    ))
    error_message = "The agent's membership must cover exactly the declared projects (for_each = semaphoreui_project.each)."
  }
}
