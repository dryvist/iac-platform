# Contract: only the catalog entries listed below may raise the task rail, each
# with exactly the listed rail_sec, as the first argument that templates.tf
# builds from it. No value may exceed the server ceiling in
# compose/docker-compose.yml, and the promotion entry uses the whole ceiling.
# Adding an entry means editing both lists in this file on purpose.
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
    ])) == 4
    error_message = "rail_sec may be set only by the four allowlisted catalog entries. Every other template keeps the wrapper's 900-second default."
  }

  assert {
    condition = merge([
      for f in fileset("${path.module}/../../..", "templates-catalog*.tf") : {
        for m in regexall(
          "(?m)^\\s*([A-Za-z0-9_-]+) = \\{[^{}]*?\\brail_sec\\s*=\\s*([0-9]+)",
          file("${path.module}/../../../${f}")
        ) : m[0] => tonumber(m[1])
      }
      ]...) == {
      "ai-site-promotion"   = 3600
      "ai-hermes-agent"     = 1800
      "ai-llm-router"       = 2400
      "apps-openbao-tagged" = 2400
    }
    error_message = "The entries carrying rail_sec must be exactly ai-site-promotion = 3600, ai-hermes-agent = 1800, ai-llm-router = 2400 and apps-openbao-tagged = 2400."
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
    condition = alltrue([
      for m in concat([
        for f in fileset("${path.module}/../../..", "templates-catalog*.tf") :
        regexall("rail_sec\\s*=\\s*([0-9]+)", file("${path.module}/../../../${f}"))
      ]...) :
      tonumber(m[0]) <= tonumber(regex(
        "&task_duration_ceiling_sec \"([0-9]+)\"",
        file("${path.module}/../../../../../compose/docker-compose.yml")
      )[0])
    ])
    error_message = "No rail_sec may exceed the compose server ceiling; a rail above the ceiling is cut short by the server."
  }

  assert {
    condition = can(regex(
      "ai-site-promotion = \\{[\\s\\S]*?only_branch\\s*=\\s*\"develop\"[\\s\\S]*?rail_sec\\s*=\\s*3600",
      file("${path.module}/../../../templates-catalog-ai.tf")
    ))
    error_message = "The ai-site-promotion template must pin only_branch = \"develop\" and carry rail_sec = 3600."
  }
}
