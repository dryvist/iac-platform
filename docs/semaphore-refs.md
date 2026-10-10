# Which git ref a Semaphore run uses

Split out of [runbook.md](runbook.md), which is at its size limit.

## Which ref a run uses, and how to run a preview one

Semaphore binds a git ref to the **repository**, not to the run. A template
inherits whichever branch its repository names, and the task list afterwards
shows the commit it landed on but not the branch it came from. Nothing in the
product tags a template, and a template that silently overrode its repository's
branch would be worse — so the ref is made visible three times instead:

- **Repository name** — `ansible-proxmox-apps (<release tag>)`,
  `ansible-proxmox-apps (develop)`. One entry per ref; the deployed ref is a
  release tag that Renovate bumps in `variables.tf`.
- **Template name** — the deployed ref keeps the bare name (`apps-site`); a
  preview ref is suffixed (`apps-site @ develop`).
- **View** — the tabs across the top of the template list. `Deployed` is
  position 0, so it is what opens by default; each preview ref gets its own tab
  behind it.

To run a preview ref, switch to its tab and start the suffixed template. To run
what is deployed, do nothing special — the default tab is the deployed one.

Two properties this preserves, both asserted at plan time rather than trusted:

- **Nothing scheduled ever runs an unreleased ref.** `schedules.tf` asserts on
  the `deployed` flag carried through from `repositories.tf`, not on the shape
  of a template name — a naming convention is not a control.
- **A run can only ever execute a pushed, reviewed commit.** SemaphoreUI accepts
  `ssh`, `http`, `file` and `git` URIs and bare absolute paths for a repository.
  Only remote HTTPS origins are permitted here, enforced by a variable
  validation and again by a precondition on the resolved set. A path- or
  file-scheme repository would run whatever happens to be on the plane's
  filesystem, which nothing reviews and nothing versions.

Adding a preview ref is one line: `preview_branches` on the repository in
`tofu/semaphore/variables.tf`. Its templates and its tab follow. Naming a branch
that does not exist upstream produces templates whose every run fails to clone,
so only name refs that are really there.

## Task duration

Every wrapped run has a 900-second rail, counted from the wrapper's first entry,
so the OpenBao env export and the collection install count against it. The rail
stops the run's whole session and fails the task. The run leaves no recap, and
the wrapper treats a missing recap as a failure ([runbook.md](runbook.md)).
Semaphore's `max_task_duration_sec` is one server-wide value, the 3600-second
ceiling in `compose/docker-compose.yml`, so a single template cannot be given
more time through it. A catalog entry requests more with `rail_sec`, which
templates.tf turns into `--rail-sec=N` as the first argument, the only position
the wrapper honours. Two entries do: `ai-site-promotion @ develop`, the
develop-to-main promotion check, at 3600 seconds and only from the develop ref
(`only_branch`), and `ai-hermes-agent` on both refs at 1800 seconds.
`tofu/semaphore/tests/promotion_rail_contract.tftest.hcl` pins that exact list.
A task override is appended after the template's arguments, so it cannot raise
the rail: a `--rail-sec` anywhere else fails the run before it starts.
