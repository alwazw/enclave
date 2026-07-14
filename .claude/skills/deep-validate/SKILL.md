---
name: deep-validate
description: >-
  Deep, evidence-based validation gate for the local-stack project. Invoke
  BEFORE marking any task done — it proves a change actually works IN THE
  CONTEXT it was executed, not just that a process is up. For docker services
  this means health AND reachable endpoint AND clean logs AND an in-container
  check that it reaches its real dependency (DB/API/volume). Generalizes to
  code, config, data, and network tasks. "docker ps healthy" is never
  sufficient. No recorded evidence => the task cannot leave Doing.
---

# deep-validate

A task is **not done because it ran without error**. It is done when you have
*observed it doing the thing it exists to do, in its real context, and recorded
that observation as evidence*. This skill is the gate between `validating` and
`done` on the kanban board (`pm/pm.py`).

## The one rule

> **No recorded evidence → the task stays in Doing/Validating.**
> `pm.py move <id> done` will physically refuse until evidence exists.
> If validation *fails*, move the task to `blocked` and record why.

"Success signals" that are **necessary but NOT sufficient** on their own:
`docker ps` shows `healthy` · a command exited 0 · a container is "Up" · a
build compiled · tests pass · a file was written · "no errors in my terminal".
Each of these can be true while the thing is still broken for its actual
purpose. Always go one layer deeper and confirm the *effect*.

## How to validate by task context

Pick the checklist for the task's `context` (see the task's frontmatter).
Run every check, capture the actual command + output, then record it (below).

### context: docker  (a service/container)
Host IP for this box is **10.0.0.10**. Run ALL of:
1. **Health** — container running and healthy:
   `docker inspect -f '{{.State.Status}} {{.State.Health.Status}}' <name>`
   (expect `running healthy`; if no healthcheck, say so and rely harder on 2–4)
2. **Endpoint reachable** — the declared `endpoint` returns the expected
   status/content from the host, not just inside the container:
   `curl -fsS -o /dev/null -w '%{http_code}' http://10.0.0.10:<port>`
   and fetch real content: `curl -fsS http://10.0.0.10:<port>/<known-path> | head`
   (expect a 2xx/3xx and the app's actual markup/JSON — not an error page).
3. **Logs clean since start** — no crashes / restart loop / stack traces:
   `docker logs --since "$(docker inspect -f '{{.State.StartedAt}}' <name>)" <name> 2>&1 | tail -50`
   and confirm restart count is stable:
   `docker inspect -f '{{.RestartCount}}' <name>`
4. **In-container dependency check** — exec INTO the container and confirm it
   reaches the dependency it needs (the whole point of the service):
   - DB-backed: `docker exec <name> <db-client> -e 'SELECT 1'` / a real query
   - API/upstream: `docker exec <name> curl -fsS <upstream>/health`
   - volume/state: `docker exec <name> sh -c 'touch /data/.probe && rm /data/.probe && echo writable'`
   Choose the check that matches what the service depends on. A web UI that
   returns 200 but whose backend DB is unreachable is **not** done.

### context: code  (a code change)
Reuse the built-in **`verify`** skill's philosophy: drive the affected flow
end-to-end and OBSERVE the new behavior — do not stop at "tests pass".
1. Exercise the exact user-facing path the change touches; capture the output
   that proves the new behavior (before→after if possible).
2. Tests: relevant suite passes (necessary, not sufficient).
3. If it's a service change, also run the relevant docker checks above.

### context: config  (settings, env, compose, proxy config)
1. **Loaded** — confirm the target process actually picked up the new value
   (e.g. `docker exec <name> printenv VAR`, or the app's config/debug endpoint),
   not just that the file on disk changed.
2. **Effect** — observe the behavior the change was supposed to produce
   (the route now resolves, the limit now applies, the feature now appears).

### context: data  (DB / migration / seed / backup)
1. Read the data back: query rows/schema/counts and confirm they match intent.
2. For migrations: confirm both schema shape AND that the app still reads/writes.
3. For backups: confirm the backup **restores** to a working state, not just
   that a dump file exists.

### context: network  (DNS, routing, reverse proxy, firewall)
1. Reach the target through the **actual path** clients use, not localhost.
2. Confirm name resolution + TLS + expected response end-to-end.

### context: other
Define concrete, observable acceptance checks up front (in the task's
Validation Plan) and prove each one.

## Recording evidence (required)

For each check, paste the command and its real output into the task's evidence
log. Keep it terse but concrete — the numbers/strings that prove it, not "looks
good":

```
python3 pm/pm.py evidence <id> --text "\$ docker inspect -f '{{.State.Health.Status}}' homepage -> healthy
\$ curl -fsS -o /dev/null -w '%{http_code}' http://10.0.0.10:3030 -> 200
\$ docker exec homepage wget -qO- http://gluetun:8000/health -> {\"status\":\"ok\"}
logs since start: clean, RestartCount=0"
```
You can also pipe long output:
`some-check 2>&1 | python3 pm/pm.py evidence <id>`

**Do not paste secrets/tokens into evidence** — redact credential values; the
evidence file lives in the repo tree. Record the *result*, not the secret.

## Then move the task

- All checks pass and recorded → `python3 pm/pm.py move <id> done`
- Any check fails → `python3 pm/pm.py move <id> blocked`, record the failing
  evidence, and open/keep a work item to fix it. Never mark done on partial.

## Adversarial mindset

Before you record "pass", ask: *"What would make this look healthy while still
being broken for a real user?"* — a cached page, a stale container, a 200 from
a splash screen, a healthcheck that only pings itself, a DB connection that
uses the wrong database. Design the check to catch that specific failure. If
you can't rule it out, it isn't validated yet.
