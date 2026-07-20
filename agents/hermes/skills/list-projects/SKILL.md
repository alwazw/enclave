# Skill: List Projects
**Trigger:** The Chairman asks what projects/companies exist, or you need to resolve a project slug.

## Overview
Read-only. Lists the companies known to the Registrar by scanning the board with
hub scope. Registrar base URL: env `REGISTRAR_URL` (default `http://registrar:8090`);
hub scope headers `X-Company: *` plus `X-Admin-Token: $REGISTRAR_ADMIN_TOKEN` if set
(never print the token).

## Procedure
```bash
curl -s "$REGISTRAR_URL/tasks" -H "X-Company: *" ${REGISTRAR_ADMIN_TOKEN:+-H "X-Admin-Token: $REGISTRAR_ADMIN_TOKEN"} \
  | python3 -c "import json,sys; ts=json.load(sys.stdin); cs={};
for t in ts: cs.setdefault(t.get('company') or '(default)', []).append(t)
for c, l in sorted(cs.items()): print(f\"{c}: {len(l)} tasks, open={sum(1 for t in l if t['status']!='done')}\")"
```
Report the list plainly. Do not mutate anything in this skill.
