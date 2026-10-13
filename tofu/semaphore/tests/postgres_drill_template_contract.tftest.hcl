run "postgres_dr_drill_template" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "apps-postgres-dr-drill = \\{[\\s\\S]*?repository\\s*=\\s*\"ansible-proxmox-apps\"[\\s\\S]*?playbook\\s*=\\s*\"playbooks/site.yml\"[\\s\\S]*?limit\\s*=\\s*\"postgres_group\"[\\s\\S]*?tags\\s*=\\s*\"dr_restore,db_connection_report\"[\\s\\S]*?mutating\\s*=\\s*true[\\s\\S]*?schedule_enabled\\s*=\\s*false[\\s\\S]*?extra_args\\s*=\\s*\\[\"-e\",\\s*\"postgres_dr_restore_drop_after=true\"\\]",
      file("${path.module}/../../../templates-catalog-apps-site-split.tf")
    ))
    error_message = "The drill template must stay on postgres_group, carry only the two tags, never be scheduled, and always drop its scratch database."
  }

  assert {
    condition = alltrue([
      for v in ["postgres_dr_restore_source_db", "postgres_dr_restore_db", "postgres_connection_report_db"] :
      can(regex("name\\s*=\\s*\"${v}\"", file("${path.module}/../../../templates-catalog-apps-site-split.tf")))
    ])
    error_message = "The drill template must expose the three role inputs as survey variables."
  }
}
