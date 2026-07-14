"""Enclave Registrar — the constitution plane (directive §5.1).

FastAPI service around the evidence-gated board. Enforces, independent of any
model or agent harness:

  1. EVIDENCE GATE   — no task reaches `done` without recorded evidence;
                       `ux` tasks additionally require a real screenshot artifact.
  2. JURISDICTION    — every request is scoped by the X-Company header; a CEO
                       scoped to one company can neither see nor touch another's
                       tasks. Scope "*" (hub/Chairman) requires the admin token
                       when one is configured.
  3. AUDIT TRAIL     — every mutation is a git commit inside the board dir.

Refusals are HTTP 409 with {"refused": true, "reason": "REFUSED: ..."} — the
"REFUSED" moment is the product's demo.
"""

import os

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from board import Board, BoardError, Forbidden, NotFound, Refused, STATUSES, CONTEXTS


# ── request bodies ──────────────────────────────────────────────────────────
class NewTask(BaseModel):
    title: str
    dept: str = "unassigned"
    context: str = "other"
    objective: str = ""
    service: str = ""
    endpoint: str = ""
    budget_minutes: int = 60
    due: str = ""
    depends_on: str = ""


class Move(BaseModel):
    status: str
    actor: str = "unknown"


class Evidence(BaseModel):
    text: str = Field(min_length=1)
    artifact: str = ""  # path under artifacts/, must exist on disk
    actor: str = "unknown"


class LogEntry(BaseModel):
    text: str = Field(min_length=1)
    actor: str = "unknown"


class Assign(BaseModel):
    who: str
    actor: str = "unknown"


def create_app(board_dir: str | None = None) -> FastAPI:
    app = FastAPI(
        title="Enclave Registrar",
        description="Evidence-gated, jurisdiction-scoped board. "
                    "Agents cannot mark work done without proof.",
        version="0.1.0",
    )
    board = Board(board_dir)

    def scope(
        x_company: str = Header(default="", alias="X-Company"),
        x_admin_token: str = Header(default="", alias="X-Admin-Token"),
    ) -> str:
        """Resolve the caller's jurisdiction scope from headers."""
        admin_token = os.environ.get("REGISTRAR_ADMIN_TOKEN", "")
        if x_company == "*":
            if admin_token and x_admin_token != admin_token:
                raise HTTPException(403, "scope '*' requires the admin token")
            return "*"
        return x_company

    def run(fn, *a, **kw):
        try:
            return fn(*a, **kw)
        except Refused as e:
            raise HTTPException(409, detail={"refused": True, "reason": str(e)})
        except Forbidden as e:
            raise HTTPException(403, detail=str(e))
        except NotFound as e:
            raise HTTPException(404, detail=str(e))
        except BoardError as e:
            raise HTTPException(422, detail=str(e))

    @app.get("/health")
    def health():
        return {"status": "ok", "service": "enclave-registrar",
                "board": board.root, "git": board.git_enabled}

    @app.get("/meta")
    def meta():
        return {"statuses": STATUSES, "contexts": CONTEXTS}

    @app.get("/tasks")
    def list_tasks(status: str | None = None, dept: str | None = None,
                   company: str = Depends(scope)):
        return [board.serializable(t)
                for t in board.list_tasks(company, status, dept)]

    @app.post("/tasks", status_code=201)
    def new_task(body: NewTask, company: str = Depends(scope)):
        # A task is incorporated INTO the caller's jurisdiction. Hub scope "*"
        # creates default-scope tasks.
        owner = "" if company == "*" else company
        t = run(board.new, body.title, company=owner, dept=body.dept,
                context=body.context, objective=body.objective,
                service=body.service, endpoint=body.endpoint,
                budget_minutes=body.budget_minutes, due=body.due,
                depends_on=body.depends_on)
        return board.serializable(t)

    @app.get("/tasks/{tid}")
    def get_task(tid: str, company: str = Depends(scope)):
        return board.serializable(run(board.get, tid, company))

    @app.post("/tasks/{tid}/move")
    def move(tid: str, body: Move, company: str = Depends(scope)):
        t = run(board.move, tid, body.status, company, body.actor)
        return board.serializable(t)

    @app.post("/tasks/{tid}/evidence")
    def evidence(tid: str, body: Evidence, company: str = Depends(scope)):
        t = run(board.evidence, tid, body.text, body.artifact, company, body.actor)
        return board.serializable(t)

    @app.post("/tasks/{tid}/log")
    def log(tid: str, body: LogEntry, company: str = Depends(scope)):
        t = run(board.log, tid, body.text, company, body.actor)
        return board.serializable(t)

    @app.post("/tasks/{tid}/assign")
    def assign(tid: str, body: Assign, company: str = Depends(scope)):
        t = run(board.assign, tid, body.who, company, body.actor)
        return board.serializable(t)

    @app.get("/stats")
    def stats(company: str = Depends(scope)):
        return board.stats(company)

    return app


