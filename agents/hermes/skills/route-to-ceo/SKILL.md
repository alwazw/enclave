# Skill: Route To CEO
**Trigger:** The Chairman gives a work item for an existing project (e.g. "have demo-widgets build X", "route this to the acme CEO", "dispatch this task").

## Overview
Dispatch a work item into a project's jurisdiction: create the task on the
Registrar under the project's company scope, assign it to that company's CEO,
and mirror it onto the native kanban dispatch board. The CEO (its own agent
runtime, bounded to its company) executes it; **the Registrar will refuse to
close it without recorded evidence** — that gate is enforced server-side and
applies to everyone, including you.

Registrar base URL: env `REGISTRAR_URL` (default `http://registrar:8090`).

## Procedure
1. Identify the target company slug (ask if ambiguous; check `list_projects`).
2. Create + assign the task in the COMPANY's scope (not hub scope):
```bash
curl -s -X POST "$REGISTRAR_URL/tasks" \
  -H "content-type: application/json" -H "X-Company: <slug>" \
  -d '{"title": "<imperative task title>", "context": "<code|ux|docker|config|data|network|other>",
       "objective": "<what done means, in checkable terms>", "dept": "engineering"}'
curl -s -X POST "$REGISTRAR_URL/tasks/<T-id>/assign" \
  -H "content-type: application/json" -H "X-Company: <slug>" \
  -d '{"who": "ceo-<slug>", "actor": "hermes-gateway"}'
curl -s -X POST "$REGISTRAR_URL/tasks/<T-id>/move" \
  -H "content-type: application/json" -H "X-Company: <slug>" \
  -d '{"status": "doing", "actor": "hermes-gateway"}'
```
3. Mirror to the native dispatch board so a worker profile can claim it:
```bash
hermes kanban --board <slug> create --title "<T-id>: <task title>" 2>/dev/null || true
```
4. Report: task id, assignee, and the evidence the executor must produce
   (tests for `code`, a real screenshot via ux-validate for `ux`).

## Governance rules (non-negotiable)
- Use context `ux` for anything user-visible: it forces a real screenshot at close.
- Never move a task to `done` yourself unless evidence is already recorded;
  when the Registrar answers HTTP 409 REFUSED, relay the refusal verbatim.
- Never touch a different company's tasks while acting for a project (403 means
  jurisdiction is working).
