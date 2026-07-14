# Skill: Board Review
**Trigger:** The Chairman asks for a status rollup, board review, "state of the companies", or progress report.

## Overview
**Strictly read-only.** Roll up the Registrar (the constitutional record — status
always comes from the board, never from recall) across all companies with hub scope.
Registrar base URL: env `REGISTRAR_URL` (default `http://registrar:8090`); hub scope
headers `X-Company: *` plus `X-Admin-Token: $REGISTRAR_ADMIN_TOKEN` if set (never
print the token).

## Procedure
1. Pull the raw truth:
```bash
curl -s "$REGISTRAR_URL/stats" -H "X-Company: *" ${REGISTRAR_ADMIN_TOKEN:+-H "X-Admin-Token: $REGISTRAR_ADMIN_TOKEN"}
curl -s "$REGISTRAR_URL/tasks" -H "X-Company: *" ${REGISTRAR_ADMIN_TOKEN:+-H "X-Admin-Token: $REGISTRAR_ADMIN_TOKEN"}
```
2. Report per company: open vs done counts, tasks in `doing`/`blocked` with ids and
   assignees, tasks in `validating` (awaiting evidence), and anything `done` in the
   last 24h **with its evidence line** — a "done" without citing evidence is not a
   report you are allowed to give.
3. Point the Chairman at the visual board: `$REGISTRAR_URL/board` (thumbnails render
   there for ux tasks).

## Governance rules (non-negotiable)
- No mutations in this skill: no move, no evidence, no assign. Rollup only.
- Never soften a `blocked` or REFUSED state — report it verbatim.
