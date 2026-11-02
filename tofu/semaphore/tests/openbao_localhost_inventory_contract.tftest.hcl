run "openbao_localhost_inventory_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "\"playbooks/openbao-rotate-approles\\.yml\",\\s*\"-i\",\\s*\"localhost,\",\\s*\"--limit\",\\s*\"localhost\"",
      file("${path.module}/../../../templates.tf")
    ))
    error_message = "The scheduled AppRole rotation must pass -i localhost, so the run targets localhost instead of paths under the checkout."
  }

  assert {
    condition = can(regex(
      "\"playbooks/openbao-seed-host-secret-zero\\.yml\",\\s*\"-i\",\\s*\"localhost,\",\\s*\"--limit\",\\s*\"localhost\"",
      file("${path.module}/../../../templates.tf")
    ))
    error_message = "The secret-zero seed must pass -i localhost, so the run targets localhost instead of paths under the checkout."
  }
}
