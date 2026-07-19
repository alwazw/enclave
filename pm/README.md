# enclave — Project Manager

A lightweight, git-tracked project-management system for this stack. It gives
you a kanban board that lives **both** locally (markdown, version-controlled)
and on **GitHub** (Issues + status labels), plus a coordinator agent and a hard
**validation gate** so "done" always means *proven working*, not "the container
came up".

## Why it exists

`docker ps` reporting `healthy` is not proof a service works. This system
refuses to let a task reach **done** until deep validation has been run and its
evidence recorded — for a web service that means the endpoint actually answers
on `$HOST_IP:PORT`, the logs are clean since start, and an in-container
check confirms it reaches its real DB/API/volume. The same "prove the effect,
in context" rule applies to code, config, data, and network tasks.

## Layout

```
pm/
├── pm.py              # kanban engine — the ONLY thing that edits the board
├── gh-sync.py         # idempotent mirror: local tasks -> GitHub Issues
├── kanban.md          # GENERATED board (do not hand-edit)
├── tasks/T-*.md       # one file per task = source of truth (+ evidence log)
├── state/issue-map.json   # task-id <-> GitHub issue-number (keeps sync idempotent)
└── README.md

.claude/
├── agents/project-manager.md      # the coordinator agent (invoke via Task/Agent)
└── skills/deep-validate/SKILL.md  # the validation gate, per task-context
```

## Board columns

`backlog → todo → doing → blocked → validating → done`

## Everyday commands

```bash
# create a task (context ∈ docker|code|config|data|network|other)
python3 pm/pm.py new --title "Deploy Homepage" --context docker \
        --service homepage --endpoint http://$HOST_IP:3030 \
        --budget 30 --objective "Dashboard reachable and showing widgets"

python3 pm/pm.py move  T-0001 doing        # stamps started_at (starts the clock)
python3 pm/pm.py log   T-0001 --text "…"   # add a work-log note
python3 pm/pm.py overdue                    # tasks past their time budget
python3 pm/pm.py evidence T-0001 --text "…" # record validation evidence
python3 pm/pm.py move  T-0001 done          # REFUSED unless evidence exists
python3 pm/pm.py stats | list | show T-0001 | render
```

The **done gate is enforced in code**: `move <id> done` exits non-zero if the
task has no recorded validation evidence. Failed validation → `move <id> blocked`.

> Note on what the code gate does and doesn't do: it enforces that *evidence
> was recorded* — it cannot judge whether the evidence is genuine (an agent
> could record `"lgtm"`). The real teeth are the **deep-validate** skill's
> per-context checklist and adversarial mindset. The code stops the trivial
> "mark it done and move on"; the discipline makes the evidence mean something.

## GitHub sync (one-time auth, then idempotent)

`gh` is installed. Authenticate once (interactive — run it yourself):

```bash
gh auth login          # choose GitHub.com / SSH or HTTPS / grant 'repo' scope
python3 pm/gh-sync.py  # creates labels, creates/updates one issue per task
```

Re-run `gh-sync.py` anytime; the `state/issue-map.json` map prevents duplicates.
Issues carry the objective + validation checklist + status only — **never** the
raw evidence log (which can contain command output/tokens).

## The coordinator agent

`.claude/agents/project-manager.md` defines a **project-manager** agent that
decomposes requests into tasks, dispatches and supervises them (following up
when a task exceeds its `budget_minutes`), runs the deep-validate gate before
marking anything done, and keeps both boards in sync. Invoke it when you want
work planned/tracked/validated. Follow-up is **in-session** monitoring — there
is no always-on daemon; the coordinator supervises while a session is active.

## Safety (important — this repo is rooted at $HOME)

- The board tooling edits **only** files under `pm/`. It runs no git commands.
- When committing, stage **only** the whitelist:
  `git add pm .claude` — never `git add -A`.
- Do **not** `git push` this repo yet. The PM setup ran `git rm --cached` on
  `.env`, credential files, and token seeds so **future** commits won't carry
  them — but those blobs are still present in **prior commit history**.
  Untracking is not the same as push-safe: pushing this branch would still
  upload the historical secret blobs. Making it push-safe requires scrubbing
  history (e.g. `git filter-repo` / BFG) or starting a fresh history, plus
  rotating anything that may already have leaked.
- Never put secrets/tokens in task files, evidence, or issues — record results,
  redact values.
