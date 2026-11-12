# These templates run only from the deployed ref, through the Nautobot
# inventory, with a fixed localhost limit. Their schedule remains a separate
# deliberate change.

run "nautobot_sync_in_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "arguments\\s*=\\s*\\[[\\s\\S]*?\\\"playbooks/nautobot-sync-in\\.yml\\\"",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"nautobot_sync_in\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "nautobot_sync_in must pass playbooks/nautobot-sync-in.yml to the runner."
  }

  assert {
    condition = can(regex(
      "arguments\\s*=\\s*\\[[\\s\\S]*?\\\"--limit\\\"\\s*,\\s*\\\"localhost\\\"",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"nautobot_sync_in\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "nautobot_sync_in must set --limit to exactly localhost."
  }

  assert {
    condition = can(regex(
      "allow_override_args_in_task\\s*=\\s*false",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"nautobot_sync_in\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "nautobot_sync_in must disallow task argument overrides."
  }

  assert {
    condition = can(regex(
      "view_id\\s*=\\s*semaphoreui_project_view[.]each\\[\\\"apps/deployed\\\"\\][.]id",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"nautobot_sync_in\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "nautobot_sync_in must use the deployed-ref view."
  }

  assert {
    condition = length(flatten([
      for f in fileset("${path.module}/../../..", "*.tf") :
      regexall("semaphoreui_project_template[.]nautobot_sync_in", file("${path.module}/../../../${f}"))
      ])) == 0 && length(regexall(
      "nautobot-sync-in|nautobot_sync_in",
      file("${path.module}/../../../schedules.tf")
    )) == 0
    error_message = "nautobot_sync_in must not be referenced by any schedule."
  }
}

run "nautobot_sync_out_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "arguments\\s*=\\s*\\[[\\s\\S]*?\\\"playbooks/nautobot-sync-out\\.yml\\\"",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"nautobot_sync_out\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "nautobot_sync_out must pass playbooks/nautobot-sync-out.yml to the runner."
  }

  assert {
    condition = can(regex(
      "arguments\\s*=\\s*\\[[\\s\\S]*?\\\"--limit\\\"\\s*,\\s*\\\"localhost\\\"",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"nautobot_sync_out\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "nautobot_sync_out must set --limit to exactly localhost."
  }

  assert {
    condition = can(regex(
      "allow_override_args_in_task\\s*=\\s*false",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"nautobot_sync_out\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "nautobot_sync_out must disallow task argument overrides."
  }

  assert {
    condition = can(regex(
      "view_id\\s*=\\s*semaphoreui_project_view[.]each\\[\\\"apps/deployed\\\"\\][.]id",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"nautobot_sync_out\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "nautobot_sync_out must use the deployed-ref view."
  }

  assert {
    condition = length(flatten([
      for f in fileset("${path.module}/../../..", "*.tf") :
      regexall("semaphoreui_project_template[.]nautobot_sync_out", file("${path.module}/../../../${f}"))
      ])) == 0 && length(regexall(
      "nautobot-sync-out|nautobot_sync_out",
      file("${path.module}/../../../schedules.tf")
    )) == 0
    error_message = "nautobot_sync_out must not be referenced by any schedule."
  }
}

run "nautobot_drift_collection_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "arguments\\s*=\\s*\\[[\\s\\S]*?\\\"playbooks/nautobot-drift\\.yml\\\"",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"nautobot_drift_collection\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "nautobot_drift_collection must pass playbooks/nautobot-drift.yml to the runner."
  }

  assert {
    condition = can(regex(
      "arguments\\s*=\\s*\\[[\\s\\S]*?\\\"--limit\\\"\\s*,\\s*\\\"localhost\\\"",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"nautobot_drift_collection\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "nautobot_drift_collection must set --limit to exactly localhost."
  }

  assert {
    condition = can(regex(
      "allow_override_args_in_task\\s*=\\s*false",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"nautobot_drift_collection\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "nautobot_drift_collection must disallow task argument overrides."
  }

  assert {
    condition = can(regex(
      "view_id\\s*=\\s*semaphoreui_project_view[.]each\\[\\\"apps/deployed\\\"\\][.]id",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"nautobot_drift_collection\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "nautobot_drift_collection must use the deployed-ref view."
  }

  assert {
    condition = length(flatten([
      for f in fileset("${path.module}/../../..", "*.tf") :
      regexall("semaphoreui_project_template[.]nautobot_drift_collection", file("${path.module}/../../../${f}"))
      ])) == 0 && length(regexall(
      "nautobot-drift-collection|nautobot_drift_collection",
      file("${path.module}/../../../schedules.tf")
    )) == 0
    error_message = "nautobot_drift_collection must not be referenced by any schedule."
  }
}

run "homebox_feed_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "arguments\\s*=\\s*\\[[\\s\\S]*?\\\"playbooks/homebox-feed\\.yml\\\"",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"homebox_feed\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "homebox_feed must pass playbooks/homebox-feed.yml to the runner."
  }

  assert {
    condition = can(regex(
      "arguments\\s*=\\s*\\[[\\s\\S]*?\\\"--limit\\\"\\s*,\\s*\\\"localhost\\\"",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"homebox_feed\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "homebox_feed must set --limit to exactly localhost."
  }

  assert {
    condition = can(regex(
      "allow_override_args_in_task\\s*=\\s*false",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"homebox_feed\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "homebox_feed must disallow task argument overrides."
  }

  assert {
    condition = can(regex(
      "view_id\\s*=\\s*semaphoreui_project_view[.]each\\[each[.]value[.]view\\][.]id",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"homebox_feed\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-nautobot.tf")
      )[0]
    ))
    error_message = "homebox_feed must take its view from the ref map."
  }

  assert {
    condition = can(regex(
      "deployed\\s*=\\s*\\{[^}]*?repository\\s*=\\s*\\\"apps/ansible-proxmox-apps\\\"[^}]*?view\\s*=\\s*\\\"apps/deployed\\\"",
      file("${path.module}/../../../templates-nautobot.tf")
      )) && can(regex(
      "develop\\s*=\\s*\\{[^}]*?repository\\s*=\\s*\\\"apps/ansible-proxmox-apps@develop\\\"[^}]*?view\\s*=\\s*\\\"apps/develop\\\"",
      file("${path.module}/../../../templates-nautobot.tf")
    ))
    error_message = "homebox_feed must run the deployed ref from the deployed view and its twin from the develop ref and view."
  }

  assert {
    condition = length(flatten([
      for f in fileset("${path.module}/../../..", "*.tf") :
      regexall("semaphoreui_project_template[.]homebox_feed", file("${path.module}/../../../${f}"))
      ])) == 0 && length(regexall(
      "homebox-feed|homebox_feed",
      file("${path.module}/../../../schedules.tf")
    )) == 0
    error_message = "homebox_feed must not be referenced by any schedule."
  }

  assert {
    condition = can(regex(
      "name\\s*=\\s*\\\"homebox_feed_apply\\\"[\\s\\S]*?required\\s*=\\s*false[\\s\\S]*?type\\s*=\\s*\\\"enum\\\"",
      file("${path.module}/../../../templates-nautobot.tf")
    ))
    error_message = "homebox_feed must offer the apply switch as an optional enum, so an unset run stays render-only."
  }
}

run "nautobot_limit_contract_rejects_other_values" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = !can(regex(
      "arguments\\s*=\\s*\\[[\\s\\S]*?\\\"--limit\\\"\\s*,\\s*\\\"localhost\\\"",
      regex(
        "resource \"semaphoreui_project_template\" \"nautobot_sync_in\" \\{([^}]*)\\}",
        replace(
          file("${path.module}/../../../templates-nautobot.tf"),
          "\"--limit\", \"localhost\"",
          "\"--limit\", \"proxmox\"",
        )
      )[0]
    ))
    error_message = "The localhost limit assertion must reject a non-localhost value."
  }
}

run "proxmox_preflight_catalog_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "proxmox-preflight-gate\\s*=\\s*\\{[^}]*?repository\\s*=\\s*\"ansible-proxmox\"[^}]*?playbook\\s*=\\s*\"playbooks/preflight_gate\\.yml\"[^}]*?limit\\s*=\\s*\"proxmox\"",
      file("${path.module}/../../../templates-catalog-proxmox.tf")
    ))
    error_message = "proxmox-preflight-gate must use its read-only preflight playbook with the proxmox limit."
  }

  assert {
    condition = can(regex(
      "proxmox-preflight-gate\\s*=\\s*\\{[^}]*?mutating\\s*=\\s*false[^}]*?schedule_enabled\\s*=\\s*false[^}]*?extra_args\\s*=\\s*\\[\\s*\\]",
      file("${path.module}/../../../templates-catalog-proxmox.tf")
    ))
    error_message = "proxmox-preflight-gate must be non-mutating, unscheduled and use no extra arguments."
  }

  assert {
    condition = can(regex(
      "proxmox-preflight-gate-selftest\\s*=\\s*\\{[^}]*?repository\\s*=\\s*\"ansible-proxmox\"[^}]*?playbook\\s*=\\s*\"tests/preflight_gate/verify\\.yml\"[^}]*?limit\\s*=\\s*\"proxmox\"",
      file("${path.module}/../../../templates-catalog-proxmox.tf")
    ))
    error_message = "proxmox-preflight-gate-selftest must use its fixture verification playbook with the proxmox limit."
  }

  assert {
    condition = can(regex(
      "proxmox-preflight-gate-selftest\\s*=\\s*\\{[^}]*?mutating\\s*=\\s*false[^}]*?schedule_enabled\\s*=\\s*false[^}]*?extra_args\\s*=\\s*\\[\\s*\\]",
      file("${path.module}/../../../templates-catalog-proxmox.tf")
    ))
    error_message = "proxmox-preflight-gate-selftest must be non-mutating, unscheduled and use no extra arguments."
  }

  assert {
    condition = length(regexall(
      "(?m)^\\s*proxmox-preflight-gate\\s*=",
      file("${path.module}/../../../schedules.tf")
      )) == 0 && length(regexall(
      "(?m)^\\s*proxmox-preflight-gate-selftest\\s*=",
      file("${path.module}/../../../schedules.tf")
    )) == 0
    error_message = "The preflight gate and self-test must not appear in schedule_crons."
  }

  assert {
    condition = length(regexall(
      "(?m)^\\s*proxmox-preflight-gate\\s*=",
      replace(
        file("${path.module}/../../../schedules.tf"),
        "schedule_crons = {",
        "schedule_crons = {\n    proxmox-preflight-gate = \"probe\"\n    proxmox-preflight-gate-selftest = \"probe\""
      )
      )) == 1 && length(regexall(
      "(?m)^\\s*proxmox-preflight-gate-selftest\\s*=",
      replace(
        file("${path.module}/../../../schedules.tf"),
        "schedule_crons = {",
        "schedule_crons = {\n    proxmox-preflight-gate = \"probe\"\n    proxmox-preflight-gate-selftest = \"probe\""
      )
    )) == 1
    error_message = "The schedule_crons checks must recognize either preflight key if it is added."
  }
}
