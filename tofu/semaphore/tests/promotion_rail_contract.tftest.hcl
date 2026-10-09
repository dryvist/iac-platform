# Contract: the 3600-second promotion allowance is requested by exactly one
# template, as the first argument that templates.tf builds from its rail_sec,
# and that value must equal the server ceiling in compose/docker-compose.yml.
# Read as raw text, the same way max_parallel_tasks_contract.tftest.hcl does,
# for the reason given in fixtures/noop/main.tf.

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
      regexall("rail_sec\\s*=", file("${path.module}/../../../${f}"))
    ])) == 1
    error_message = "Exactly one catalog entry may set rail_sec. Every other template keeps the wrapper's 900-second default."
  }

  assert {
    condition = length(flatten([
      for f in fileset("${path.module}/../../..", "*.tf") :
      regexall("\"--rail-sec=", file("${path.module}/../../../${f}"))
    ])) == 1
    error_message = "The --rail-sec flag may be written only once, as templates.tf's rail_sec prefix. A catalog entry must not hand-write it into extra_args, where it would sit after the template's own arguments."
  }

  assert {
    condition = can(regex(
      "arguments = concat\\(\\s*try\\(each\\.value\\.rail_sec, null\\) != null \\? \\[\"--rail-sec=",
      file("${path.module}/../../../templates.tf")
    ))
    error_message = "templates.tf must put the --rail-sec prefix first in the template arguments, the one position the wrapper honours."
  }

  assert {
    condition = tonumber(regex(
      "rail_sec\\s*=\\s*([0-9]+)",
      file("${path.module}/../../../templates-catalog-ai.tf")
      )[0]) == tonumber(regex(
      "&task_duration_ceiling_sec \"([0-9]+)\"",
      file("${path.module}/../../../../../compose/docker-compose.yml")
    )[0])
    error_message = "The rail_sec value in templates-catalog-ai.tf must equal the compose server ceiling; a rail above the ceiling is cut short by the server."
  }

  assert {
    condition = can(regex(
      "ai-site-promotion = \\{[\\s\\S]*?only_branch\\s*=\\s*\"develop\"[\\s\\S]*?rail_sec\\s*=\\s*3600",
      file("${path.module}/../../../templates-catalog-ai.tf")
    ))
    error_message = "The ai-site-promotion template must pin only_branch = \"develop\" and carry rail_sec = 3600."
  }
}
