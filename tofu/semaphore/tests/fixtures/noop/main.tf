# This fixture gives source-contract tests a trivial, provider-free module to
# plan. Shared raw-source patterns live here so separate tests use one matcher.
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

locals {
  benchmark_tau2_lane_pattern = "name\\s*=\\s*\"([a-z0-9-]+)\"[^{}]*?\\brail_sec\\s*=\\s*([0-9]+)"
}
