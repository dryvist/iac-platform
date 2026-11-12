# Source contracts use the provider-free fixture; see fixtures/noop/main.tf.
run "openbao_rbac_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = alltrue([
      for name, tag in {
        apps-openbao-rbac           = "openbao_rbac"
        apps-openbao-approle-config = "openbao_approle_config"
        } : can(regex(
          "${name} = \\{\\s*repository\\s*=\\s*\"ansible-proxmox-apps\"\\s*project\\s*=\\s*\"secrets\"\\s*playbook\\s*=\\s*\"playbooks/site[.]yml\"\\s*limit\\s*=\\s*\"openbao_group\"\\s*tags\\s*=\\s*\"${tag}\"\\s*mutating\\s*=\\s*true\\s*schedule_enabled\\s*=\\s*false\\s*extra_args\\s*=\\s*\\[\\]\\s*description\\s*=\\s*\"[^\"]+\"\\s*\\}",
          file("${path.module}/../../../templates-catalog-apps.tf")
      ))
    ])
    error_message = "OpenBao phase templates must run only their named phase in secrets, with the OpenBao group limit, no schedule, extra arguments or rail override."
  }

  assert {
    condition = alltrue([
      for name, tag in {
        apps-openbao-kv-seed = "openbao_kv_seed"
        } : can(regex(
          "${name} = \\{\\s*repository\\s*=\\s*\"ansible-proxmox-apps\"\\s*project\\s*=\\s*\"secrets\"\\s*playbook\\s*=\\s*\"playbooks/site[.]yml\"\\s*limit\\s*=\\s*\"openbao_group\"\\s*tags\\s*=\\s*\"${tag}\"\\s*mutating\\s*=\\s*true\\s*schedule_enabled\\s*=\\s*false\\s*rail_sec\\s*=\\s*2400\\s*extra_args\\s*=\\s*\\[\\]\\s*description\\s*=\\s*\"[^\"]+\"\\s*\\}",
          file("${path.module}/../../../templates-catalog-apps-openbao-kv-seed.tf")
      ))
    ])
    error_message = "The KV seed phase template must run only its named phase in secrets, with the OpenBao group limit, no schedule or extra arguments, and a 2400-second rail."
  }

  assert {
    condition = can(regex(
      "t[.]repository == \"ansible-proxmox-apps\" && alltrue\\(\\[\\s*for tag in split\\(\",\", try\\(t[.]tags, \"\"\\)\\) : can\\(regex\\(\"[^\"]+\", tag\\)\\)\\s*\\]\\)",
      file("${path.module}/../../../templates.tf")
    ))
    error_message = "The secrets precondition must require the apps repository and match every tag against its allowed pattern."
  }

  assert {
    condition = alltrue([
      for tag in ["openbao", "openbao_rbac", "openbao_approle_config", "openbao_kv_seed", "openbao_rotate"] : can(regex(
        regex("for tag in split[^\n]+can\\(regex\\(\"([^\"]+)\", tag\\)", file("${path.module}/../../../templates.tf"))[0],
        tag
      ))
    ])
    error_message = "The secrets precondition must accept openbao and its phase tags."
  }
}

run "secrets_project_rejects_non_openbao_tags" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = alltrue([
      for tags in ["vikunja", "openbao,vikunja", "openbao_rbac,all", "openbao_rbac,", "openbaox", "other_openbao", ""] : !alltrue([
        for tag in split(",", tags) : can(regex(
          regex("for tag in split[^\n]+can\\(regex\\(\"([^\"]+)\", tag\\)", file("${path.module}/../../../templates.tf"))[0],
          tag
        ))
      ])
    ])
    error_message = "The secrets precondition must reject non-OpenBao tags, including mixed and empty tag lists."
  }
}
