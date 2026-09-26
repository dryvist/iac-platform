# Contract: variables.tf's max_parallel_tasks default must equal the literal
# value in compose/docker-compose.yml's &max_parallel_tasks anchor, which
# both SEMAPHORE_MAX_PARALLEL_TASKS (semaphore service) and
# SEMAPHORE_RUNNER_MAX_PARALLEL_TASKS (semaphore-runner service) alias.
# Compose and this tofu root have no common runtime source to share a single
# value from (see variables.tf), so this test is the drift check.
#
# Runs against the empty ./tests/fixtures/noop module, not the real root
# module —
# see that fixture's comment for why (OpenTofu 1.11's mock_provider panics
# on this root's ephemeral-resource-backed provider config, verified
# locally). Every assertion below reads the two real source files' raw text
# via file()/regex() instead, which needs no provider and no plan of either
# one. yamldecode() was tried first and rejected: it cannot parse
# docker-compose.yml at all, because several unrelated services (e.g.
# terrakube-api's x-api block) use the `<<: [*alias]` merge-key-with-a-list
# idiom, which yamldecode's decoder rejects with "cannot merge tuple into
# mapping" (verified locally) — regex() over the raw text has no such
# dependency on the rest of the file parsing cleanly.

run "max_parallel_tasks_matches_compose_anchor" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    # Anchored to the variable "max_parallel_tasks" block itself, not the
    # first "default = N" anywhere in the file — the variable's own
    # description prose contains the word "default", and other variables in
    # this file (semaphore_api_base_url, ansible_repositories) have their own
    # default = ... lines above this one that an unanchored pattern would
    # match instead. [\s\S]*? is RE2's lazy any-char-including-newline
    # quantifier (Go regexp, which OpenTofu's regex() uses); verified
    # non-greedy locally: it stops at the first "default = N" following the
    # variable header, not the last.
    condition = tonumber(regex(
      "variable \"max_parallel_tasks\"[\\s\\S]*?default\\s*=\\s*([0-9]+)",
      file("${path.module}/../../../variables.tf")
      )[0]) == tonumber(regex(
      "&max_parallel_tasks \"([0-9]+)\"",
      file("${path.module}/../../../../../compose/docker-compose.yml")
    )[0])
    error_message = "tofu/semaphore/variables.tf's max_parallel_tasks default must equal compose/docker-compose.yml's &max_parallel_tasks anchor value."
  }

  assert {
    condition = can(regex(
      "SEMAPHORE_MAX_PARALLEL_TASKS:[[:space:]]*\\*max_parallel_tasks",
      file("${path.module}/../../../../../compose/docker-compose.yml")
    ))
    error_message = "compose/docker-compose.yml's semaphore service must alias &max_parallel_tasks for SEMAPHORE_MAX_PARALLEL_TASKS, not a literal of its own."
  }

  assert {
    condition = can(regex(
      "SEMAPHORE_RUNNER_MAX_PARALLEL_TASKS:[[:space:]]*\\*max_parallel_tasks",
      file("${path.module}/../../../../../compose/docker-compose.yml")
    ))
    error_message = "compose/docker-compose.yml's semaphore-runner service must alias &max_parallel_tasks for SEMAPHORE_RUNNER_MAX_PARALLEL_TASKS, not a literal of its own."
  }
}
