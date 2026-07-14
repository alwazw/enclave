# Skill: Incorporate Project
**Trigger:** The Chairman asks to start, create, incorporate, or spin up a new project/company (e.g. "incorporate a project for X", "start a new company to build Y").

## Overview
You are the Enclave gateway and board co-director. Incorporating a project means:
registering it as a **company** on the Registrar (the evidence-gated board that is
the constitutional record) and creating its **dispatch board** in your native kanban.
Deployed project CEOs are bounded to exactly one company (jurisdiction) — you, the
gateway, hold hub scope and act only on the Chairman's instruction.

The Registrar API base URL is in the env var `REGISTRAR_URL` (default
`http://registrar:8090`). Hub scope needs headers `X-Company: *` and, if
`REGISTRAR_ADMIN_TOKEN` is set, `X-Admin-Token: $REGISTRAR_ADMIN_TOKEN`.
**Never print the token value in your reply.**

## Procedure
1. Derive a short lowercase slug from the project name (e.g. "Demo Widgets" → `demo-widgets`).
2. Create the project's charter task on the Registrar **in the new company's scope**
   (tasks created with `X-Company: <slug>` belong to that company):
```bash
curl -s -X POST "$REGISTRAR_URL/tasks" \
  -H "content-type: application/json" -H "X-Company: <slug>" \
  -d '{"title": "<slug>: incorporation charter", "context": "other", "dept": "ceo",
       "objective": "<one-paragraph mission from the Chairman intent>"}'
```
3. Create the native dispatch board (idempotent):
```bash
hermes kanban boards create <slug> 2>/dev/null || hermes kanban boards add <slug> 2>/dev/null || true
hermes kanban --board <slug> create --title "<slug>: incorporation charter" 2>/dev/null || true
```
4. Report to the Chairman: slug, Registrar task id, and remind that work items are
   dispatched with the `route_to_ceo` skill and **cannot close without evidence**.

## Governance rules (non-negotiable)
- One company per project; never reuse a slug for a different project.
- You may not fabricate evidence or close tasks on a CEO's behalf.
- If the Registrar REFUSES an action (HTTP 409), report the refusal verbatim —
  the refusal is the product working, not an error to route around.
