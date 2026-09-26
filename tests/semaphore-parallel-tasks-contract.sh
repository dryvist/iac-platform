#!/usr/bin/env bash
# Semaphore's task concurrency has three consumers that must never drift:
# compose/docker-compose.yml's SEMAPHORE_MAX_PARALLEL_TASKS (semaphore
# service) and SEMAPHORE_RUNNER_MAX_PARALLEL_TASKS (semaphore-runner service),
# both aliased to one &max_parallel_tasks YAML anchor, and
# tofu/semaphore/project.tf's local.max_parallel_tasks, which the
# semaphoreui_project resource's max_parallel_tasks attribute reads. Compose
# and this tofu root have no common runtime source to point at (compose reads
# compose/.env at deploy time; tofu reads TF_VAR_* from the run environment),
# so this test is the contract: it parses the anchor's literal value and the
# tofu local's literal value and fails if they differ, and fails if either
# compose service stopped aliasing the anchor for a hardcoded value of its
# own.
#
# Usage: tests/semaphore-parallel-tasks-contract.sh   (exit 0 = contract holds)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE="$REPO_ROOT/compose/docker-compose.yml"
PROJECT_TF="$REPO_ROOT/tofu/semaphore/project.tf"
FAIL=0

check() { # name condition-description ok?
  local name="$1" ok="$2"
  if [ "$ok" = 1 ]; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    FAIL=1
  fi
}

anchor_value="$(grep -oE '&max_parallel_tasks "[0-9]+"' "$COMPOSE" | grep -oE '[0-9]+' | head -1)"
tofu_value="$(grep -oE 'max_parallel_tasks[[:space:]]*=[[:space:]]*[0-9]+' "$PROJECT_TF" | grep -oE '[0-9]+' | head -1)"

check "compose defines the &max_parallel_tasks anchor exactly once" \
  "$([ "$(grep -cE '&max_parallel_tasks "[0-9]+"' "$COMPOSE")" = 1 ] && echo 1 || echo 0)"

check "tofu/semaphore/project.tf declares local.max_parallel_tasks as a literal" \
  "$([ -n "$tofu_value" ] && echo 1 || echo 0)"

check "semaphore service's SEMAPHORE_MAX_PARALLEL_TASKS aliases the anchor" \
  "$(grep -qE 'SEMAPHORE_MAX_PARALLEL_TASKS:[[:space:]]*\*max_parallel_tasks' "$COMPOSE" && echo 1 || echo 0)"

check "semaphore-runner service's SEMAPHORE_RUNNER_MAX_PARALLEL_TASKS aliases the anchor" \
  "$(grep -qE 'SEMAPHORE_RUNNER_MAX_PARALLEL_TASKS:[[:space:]]*\*max_parallel_tasks' "$COMPOSE" && echo 1 || echo 0)"

check "the semaphoreui_project resource reads local.max_parallel_tasks, not a literal" \
  "$(grep -qE 'max_parallel_tasks[[:space:]]*=[[:space:]]*local\.max_parallel_tasks' "$PROJECT_TF" && echo 1 || echo 0)"

if [ -n "$anchor_value" ] && [ -n "$tofu_value" ]; then
  check "compose anchor ($anchor_value) equals tofu local ($tofu_value)" \
    "$([ "$anchor_value" = "$tofu_value" ] && echo 1 || echo 0)"
else
  echo "FAIL could not extract a comparable value from both files (compose=$anchor_value tofu=$tofu_value)"
  FAIL=1
fi

exit "$FAIL"
