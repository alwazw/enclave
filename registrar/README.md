# Enclave Registrar — the constitution plane

The Registrar is the service that makes Enclave's headline claim true mechanically:
**an agent cannot mark a task "done" without recorded proof.** It wraps the corp-os
evidence-gated board (`pm/pm.py`'s file format, unchanged) in a FastAPI service, so
the gate is enforced *below* any model, prompt, or agent harness.

## What it enforces

1. **Evidence gate** — `POST /tasks/{id}/move {"status": "done"}` returns
   **HTTP 409 `{"refused": true, "reason": "REFUSED: ..."}`** unless the task has
   recorded evidence. `ux`-context tasks additionally require a **real screenshot
   file on disk** under `artifacts/` (the §5.2 Playwright gate writes these).
   Evidence referencing a nonexistent artifact is rejected outright.
2. **Jurisdiction** — every request carries an `X-Company` header. A CEO scoped to
   one company cannot list, read, or mutate another company's tasks (403, and other
   companies' tasks are invisible in listings). Scope `*` (hub/Chairman) requires
   `X-Admin-Token` when `REGISTRAR_ADMIN_TOKEN` is set.
3. **Git audit trail** — every mutation is a git commit inside the board directory:
   who did what, when, to which task.

## Run

Part of the stack (`--profile core`):

```bash
docker compose -f local-stack.yml --profile core up -d registrar
curl -s localhost:8090/health
```

Standalone dev:

```bash
pip install -r requirements.txt && pip install pytest httpx
BOARD_DIR=/tmp/board uvicorn app:app --port 8090
pytest tests/ -v
```

## The demo loop (what gets filmed)

```bash
H='-H content-type:application/json -H X-Company:acme'
curl -s -X POST localhost:8090/tasks $H -d '{"title":"ship the widget","context":"code"}'
curl -s -X POST localhost:8090/tasks/T-0001/move $H -d '{"status":"done","actor":"ceo"}'
# -> 409 {"refused": true, "reason": "REFUSED: T-0001 has no recorded evidence..."}
curl -s -X POST localhost:8090/tasks/T-0001/evidence $H -d '{"text":"pytest: 12 passed"}'
curl -s -X POST localhost:8090/tasks/T-0001/move $H -d '{"status":"done","actor":"ceo"}'
# -> 200, status: done. Now — and only now — it can close.
```

## Environment

| var | default | meaning |
|-----|---------|---------|
| `BOARD_DIR` | `/board` | board root (tasks/, artifacts/, git repo) |
| `REGISTRAR_GIT` | `on` | `off` disables the git audit trail (tests) |
| `REGISTRAR_ADMIN_TOKEN` | *(unset)* | when set, required for scope `*` |
