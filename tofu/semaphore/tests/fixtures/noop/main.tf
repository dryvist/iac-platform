# Deliberately empty: this fixture exists only so `tofu test` has a trivial,
# provider-free module to plan for the file-content contract check in
# ../max_parallel_tasks_contract.tftest.hcl.
#
# The real root module (tofu/semaphore, two directories up) cannot be
# exercised by `tofu test` at all, mocked or not: its semaphoreui provider
# configures itself from an `ephemeral "vault_kv_secret_v2"` block
# (providers.tf), and OpenTofu 1.11's mock_provider support panics when a
# provider configuration depends on an ephemeral resource ("implement me",
# ephemeral resources not supported in provider_for_test_framework.go
# OpenEphemeralResource — verified locally: `tofu test` crashes with that
# exact panic against the real root module). So the contract check reads
# both source files' raw text directly via file()/regex() instead of
# planning either one.
