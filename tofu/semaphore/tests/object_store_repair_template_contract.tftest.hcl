# The object-store repair template: one manual lane, never scheduled, bound to
# the Nautobot inventory so it resolves its hosts when the store cannot serve
# the published one. Read as raw text, the same way
# nautobot_template_contract.tftest.hcl is, for the reason given in
# fixtures/noop/main.tf.

run "apps_object_store_repair_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "arguments\\s*=\\s*\\[[\\s\\S]*?\\\"playbooks/site\\.yml\\\"",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"apps_object_store_repair\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-object-store-repair.tf")
      )[0]
    ))
    error_message = "apps_object_store_repair must pass playbooks/site.yml to the runner."
  }

  assert {
    condition = can(regex(
      "arguments\\s*=\\s*\\[[\\s\\S]*?\\\"--limit\\\"\\s*,\\s*\\\"object_storage_group,localhost\\\"",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"apps_object_store_repair\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-object-store-repair.tf")
      )[0]
    ))
    error_message = "apps_object_store_repair must limit the run to object_storage_group,localhost."
  }

  assert {
    condition = can(regex(
      "arguments\\s*=\\s*\\[[\\s\\S]*?\\\"-i\\\"\\s*,\\s*\\\"inventory/nautobot\\.yml\\\"",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"apps_object_store_repair\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-object-store-repair.tf")
      )[0]
    ))
    error_message = "apps_object_store_repair must resolve its hosts from the Nautobot inventory file."
  }

  assert {
    condition = can(regex(
      "inventory_id\\s*=\\s*semaphoreui_project_inventory[.]homelab_nautobot[.]id",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"apps_object_store_repair\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-object-store-repair.tf")
      )[0]
    ))
    error_message = "apps_object_store_repair must bind the existing homelab-nautobot inventory object."
  }

  assert {
    condition = can(regex(
      "environment_id\\s*=\\s*semaphoreui_project_environment[.]homelab\\[\\\"apps\\\"\\][.]id",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"apps_object_store_repair\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-object-store-repair.tf")
      )[0]
    ))
    error_message = "apps_object_store_repair must run under the apps environment that carries the Nautobot credential wiring."
  }

  assert {
    condition = length(regexall(
      "apps-object-store-repair|apps_object_store_repair",
      file("${path.module}/../../../schedules.tf")
    )) == 0
    error_message = "apps_object_store_repair must not be referenced by any schedule."
  }
}
