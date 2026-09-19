#!/usr/bin/env bash
# Semaphore template wrapper around the certificate-signed ansible runner
# (ansible-proxmox's scripts/run-ansible.sh — do not edit that script from
# here; the ansible-proxmox* repos likely carry their own copy and are
# covered by Vikunja 1843, not by this wrapper). Tracked bug, Vikunja 1843:
# run-ansible.sh can exit 0 on a run interrupted mid-play and then claims the
# run did nothing, even when hundreds of tasks actually ran. This wrapper
# tees the run's output and applies the PLAY RECAP instead of trusting the
# wrapped command's exit code:
#
#   1. No PLAY RECAP at all -> exit non-zero. Run state is UNKNOWN (not
#      "failed", not "did nothing") and must not be treated as applied.
#   2. A recap exists and any host shows failed>0 or unreachable>0 -> exit
#      non-zero.
#   3. A recap exists and the ONLY host in it is localhost (the real target
#      host never ran — the `--limit ...,localhost` footgun) -> exit
#      non-zero. This heuristic is evaluated ONLY when a recap exists;
#      absence of a recap is always rule 1, never this rule — conflating the
#      two is the other half of the upstream bug. A caller whose `--limit` is
#      exactly `localhost` asked for that recap on purpose (a localhost-only
#      play, such as a read-only report) and is exempt from this rule alone.
#   4. Recap exists, covers a real host, no failures -> exit with the
#      wrapped command's own exit code.
#
# Usage: semaphore-run-ansible.sh <run-ansible.sh> <playbook> [args...]
set -euo pipefail

# --- Argument guard ----------------------------------------------------------
# The Ansible templates set allow_override_args_in_task = true, so the argument
# list is chosen by the caller (API, UI or schedule) rather than frozen in the
# IaC that declares the template. The invariants the frozen list used to carry
# are enforced here instead, at run time, where they cover every caller rather
# than only the declared ones:
#
#   1. --check is refused. A dry run must never be able to masquerade as a
#      converge — the reason the original rule was "--diff, never --check".
#   2. --limit always gains localhost. The tofu inventory is loaded by a play
#      inside the playbook, so a limit omitting localhost skips that play and
#      the whole run no-ops at exit 0: a false green, not a visible error.
#   3. The playbook must be a playbooks/*.yml path, so a caller cannot point
#      the runner at an arbitrary file in the checked-out repository.
#
# Not covered, deliberately: the clustered short form (-lhosts rather than
# -l hosts). Nothing emits it, and accepting only the spelled-out forms keeps
# this readable — it is refused as an unknown limit rather than silently
# passed through, because rule 2 then appends the default.
ansible_limit_with_localhost() {
  case ",$1," in
    *,localhost,*) printf '%s' "$1" ;;
    *) printf '%s,localhost' "$1" ;;
  esac
}

# Emits the normalized argument vector, one element per line. Returns 2 when an
# argument violates a rule above; the caller must not run anything on a 2.
normalize_ansible_args() {
  local runner playbook limit_seen=0
  runner="${1:-}"; shift || true
  playbook="${1:-}"; shift || true
  case "$playbook" in
    playbooks/*.yml) ;;
    *)
      echo "semaphore-run-ansible.sh: refusing to run '${playbook:-<none>}' — the playbook must be a playbooks/*.yml path" >&2
      return 2 ;;
  esac
  printf '%s\n' "$runner" "$playbook"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --check|-C)
        echo "semaphore-run-ansible.sh: refusing --check — a dry run must not be able to masquerade as a converge" >&2
        return 2 ;;
      --limit|-l)
        [ "$#" -ge 2 ] || { echo "semaphore-run-ansible.sh: --limit needs a value" >&2; return 2; }
        printf '%s\n' "--limit" "$(ansible_limit_with_localhost "$2")"
        limit_seen=1; shift 2 ;;
      --limit=*)
        printf '%s\n' "--limit=$(ansible_limit_with_localhost "${1#--limit=}")"
        limit_seen=1; shift ;;
      *)
        printf '%s\n' "$1"; shift ;;
    esac
  done
  [ "$limit_seen" -eq 1 ] || printf '%s\n' "--limit" "all,localhost"
}

if [ "${1:-}" = "--self-test" ]; then
  _t_fail=0
  _t() {
    local desc="$1" expected="$2"; shift 2
    local actual
    actual="$(normalize_ansible_args "$@" 2>/dev/null | tr '\n' ' ')" || actual="REFUSED"
    if [ "$actual" != "$expected" ]; then
      printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$desc" "$expected" "$actual" >&2
      _t_fail=1
    fi
  }
  _t "localhost is appended to a scoped limit" \
     "run playbooks/site.yml --tags authelia --limit authelia_group,localhost --diff " \
     run playbooks/site.yml --tags authelia --limit authelia_group --diff
  _t "a limit already naming localhost is left alone" \
     "run playbooks/site.yml --limit all,localhost --diff " \
     run playbooks/site.yml --limit all,localhost --diff
  _t "the --limit= form is normalized too" \
     "run playbooks/site.yml --limit=zammad_group,localhost " \
     run playbooks/site.yml --limit=zammad_group
  _t "a missing limit gets the full-scope default" \
     "run playbooks/site.yml --diff --limit all,localhost " \
     run playbooks/site.yml --diff
  _t "--check is refused" "REFUSED" run playbooks/site.yml --check --diff
  _t "-C is refused" "REFUSED" run playbooks/site.yml -C
  _t "a playbook outside playbooks/ is refused" "REFUSED" run /etc/passwd --diff
  _t "a missing playbook is refused" "REFUSED" run
  [ "$_t_fail" -eq 0 ] && echo "semaphore-run-ansible.sh: self-test passed"
  exit "$_t_fail"
fi

[ "$#" -ge 1 ] || { echo "usage: semaphore-run-ansible.sh <run-ansible.sh> [args...]" >&2; exit 2; }

# The run environment. The playbooks read plain environment variables and know
# nothing about where they came from; this is the one place that fills them in.
# Three KV documents, one per mount, so every value lives on exactly one tier:
# topology in config/, internal-only secrets on the internal mount, anything
# reachable from the public internet in secrets-external/. Re-exec through the
# exporter once; the marker stops the second entry from doing it again.
if [ -z "${SEMAPHORE_RUN_ENV_LOADED:-}" ] && [ -n "${BAO_ADDR:-}" ]; then
  export SEMAPHORE_RUN_ENV_LOADED=1
  exec openbao-exec-env.sh config/platform/ansible/env -- \
    openbao-exec-env.sh secret/platform/ansible/env -- \
    openbao-exec-env.sh secrets-external/platform/ansible/env -- \
    bash "$0" "$@"
fi

# Apply the guard to the real invocation. One element per line, so an argument
# containing spaces survives. A refusal is fatal: nothing runs on a 2.
_normalized="$(normalize_ansible_args "$@")" || exit 2
mapfile -t _args <<<"$_normalized"
set -- "${_args[@]}"
# The caller chooses the scope now, so the resolved command belongs in the run's
# own log — a run whose scope is not visible in its output cannot be audited.
echo "semaphore-run-ansible.sh: running: $*"

if [ -f requirements.yml ]; then
  echo "Installing Ansible requirements..."
  ansible-galaxy install -r requirements.yml --roles-path roles || true
  ansible-galaxy collection install -r requirements.yml || true
fi

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

set +e
"$@" 2>&1 | tee "$log"
rc="${PIPESTATUS[0]}"
set -e

# Recap host lines look like: "hostname : ok=5 changed=2 unreachable=0 failed=0 ..."
recap_lines="$(grep -E '^\S+\s*:\s*ok=' "$log" || true)"

if [ -z "$recap_lines" ]; then
  echo "semaphore-run-ansible.sh: no PLAY RECAP in output — run state is UNKNOWN, do not treat as applied (wrapped command's own rc was $rc)" >&2
  exit 1
fi

if grep -qE 'unreachable=[1-9][0-9]*|failed=[1-9][0-9]*' <<<"$recap_lines"; then
  echo "semaphore-run-ansible.sh: PLAY RECAP shows a failed or unreachable host:" >&2
  echo "$recap_lines" >&2
  exit 1
fi

limit=""
prev=""
for a in "$@"; do
  { [ "$prev" = "--limit" ] || [ "$prev" = "-l" ]; } && limit="$a"
  case "$a" in --limit=*) limit="${a#--limit=}" ;; esac
  prev="$a"
done
hosts="$(awk -F' *: *' '{print $1}' <<<"$recap_lines" | sort -u)"
if [ "$hosts" = "localhost" ] && [ "$limit" != "localhost" ]; then
  echo "semaphore-run-ansible.sh: PLAY RECAP only covers localhost — the real target host(s) never ran (check --limit includes them, not just localhost)" >&2
  exit 1
fi

exit "$rc"
