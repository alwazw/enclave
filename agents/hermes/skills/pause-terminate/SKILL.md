# Skill: Pause / Terminate Project
**Trigger:** The Chairman explicitly asks to pause, freeze, halt, terminate, or wind down a project/company.

## Overview
Reversibly halt a company's work on the Registrar. There is no delete: pausing
moves open work to `blocked` with a log entry; terminating does the same plus a
TERMINATED marker in each task's log. Registrar base URL: env `REGISTRAR_URL`
(default `http://registrar:8090`).

**Confirmation rule:** this skill runs ONLY on an explicit, current instruction
from the Chairman naming the project. If the instruction is ambiguous or implied,
ask first. Report what was halted afterwards, task by task.

## Procedure
1. List the company's open tasks:
```bash
curl -s "$REGISTRAR_URL/tasks" -H "X-Company: <slug>"
```
2. For each task not in `done`/`blocked`:
```bash
curl -s -X POST "$REGISTRAR_URL/tasks/<T-id>/log" \
  -H "content-type: application/json" -H "X-Company: <slug>" \
  -d '{"text": "<PAUSED|TERMINATED> by Chairman instruction via hermes-gateway", "actor": "hermes-gateway"}'
curl -s -X POST "$REGISTRAR_URL/tasks/<T-id>/move" \
  -H "content-type: application/json" -H "X-Company: <slug>" \
  -d '{"status": "blocked", "actor": "hermes-gateway"}'
```
3. Terminate only: also log the marker on the charter task and stop mirroring the
   board in dispatch (`hermes kanban --board <slug> archive ...` for open mirrors).

## Governance rules (non-negotiable)
- Never delete task files, evidence, or git history — the audit trail outlives the project.
- Done tasks stay done; you are freezing the future, not rewriting the past.
