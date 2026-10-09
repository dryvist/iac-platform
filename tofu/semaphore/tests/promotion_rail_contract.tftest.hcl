# Contract: the 3600-second promotion allowance is requested by exactly one
# template, through the wrapper's --rail-sec flag, and that value must equal the
# server ceiling in compose/docker-compose.yml. Read as raw text, the same way
# max_parallel_tasks_contract.tftest.hcl does, for the reason given in
# fixtures/noop/main.tf.

run "promotion_rail_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = tonumber(regex(
      "&task_duration_ceiling_sec \"([0-9]+)\"",
      file("${path.module}/../../../../../compose/docker-compose.yml")
    )[0]) == 3600
    error_message = "compose/docker-compose.yml's &task_duration_ceiling_sec must be 3600, the allowance the ai-site-promotion template requests."
  }

  assert {
    condition = length(flatten([
      for f in fileset("${path.module}/../../..", "*.tf") :
      regexall("\"--rail-sec=", file("${path.module}/../../../${f}"))
    ])) == 1
    error_message = "Exactly one template may request a rail allowance (a \"--rail-sec=...\" extra_args entry). Every other template keeps the wrapper's 900-second default."
  }

  assert {
    condition = tonumber(regex(
      "\"--rail-sec=([0-9]+)\"",
      file("${path.module}/../../../templates-catalog-ai.tf")
      )[0]) == tonumber(regex(
      "&task_duration_ceiling_sec \"([0-9]+)\"",
      file("${path.module}/../../../../../compose/docker-compose.yml")
    )[0])
    error_message = "The --rail-sec value in templates-catalog-ai.tf must equal the compose server ceiling; a rail above the ceiling is cut short by the server."
  }

  assert {
    condition = can(regex(
      "ai-site-promotion = \\{[\\s\\S]*?only_branch\\s*=\\s*\"develop\"[\\s\\S]*?extra_args\\s*=\\s*\\[\"--rail-sec=",
      file("${path.module}/../../../templates-catalog-ai.tf")
    ))
    error_message = "The ai-site-promotion template must pin only_branch = \"develop\" and carry its --rail-sec in extra_args."
  }
}
