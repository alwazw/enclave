"""Enclave Registrar — board engine.

File-based, git-audited kanban with a hard EVIDENCE GATE, derived from corp-os
pm/pm.py. This module is the importable service core: the gate is enforced here,
below any model or agent harness — a task cannot reach `done` without recorded
evidence, and a `ux`-context task additionally cannot reach `done` without a
real screenshot artifact on disk.

Storage layout (BOARD_DIR, default /board):
    tasks/T-0001.md      one markdown file per task (frontmatter + sections)
    artifacts/           evidence artifacts (screenshots, reports)
    config.json          {"project": ..., "repo": ...}
Every mutation is committed to git inside BOARD_DIR (audit trail).
"""

import json
import os
import re
import subprocess
from datetime import datetime, timezone

STATUSES = ["backlog", "todo", "doing", "blocked", "validating", "done"]
CONTEXTS = ["docker", "code", "config", "data", "network", "ux", "other"]
FIELDS = [
    "id", "title", "status", "dept", "context", "assignee", "service",
    "endpoint", "budget_minutes", "due", "depends_on", "company",
    "created_at", "started_at", "done_at",
]
IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp")


class BoardError(Exception):
    """Base class."""


class Refused(BoardError):
    """The evidence gate refused the transition."""


class NotFound(BoardError):
    pass


class Forbidden(BoardError):
    """Jurisdiction violation: caller's company may not touch this task."""


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class Board:
    def __init__(self, root: str | None = None, git: bool | None = None):
        self.root = os.path.abspath(root or os.environ.get("BOARD_DIR", "/board"))
        self.tasks_dir = os.path.join(self.root, "tasks")
        self.artifacts_dir = os.path.join(self.root, "artifacts")
        os.makedirs(self.tasks_dir, exist_ok=True)
        os.makedirs(self.artifacts_dir, exist_ok=True)
        if git is None:
            git = os.environ.get("REGISTRAR_GIT", "on").lower() != "off"
        self.git_enabled = git
        if self.git_enabled:
            self._git_init()

    # ── git audit trail ────────────────────────────────────────────────────
    def _git(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", "-C", self.root, *args],
            capture_output=True, text=True, check=False,
        )

    def _git_init(self) -> None:
        if not os.path.isdir(os.path.join(self.root, ".git")):
            self._git("init", "-q")
            self._git("config", "user.name", "enclave-registrar")
            self._git("config", "user.email", "registrar@enclave.local")

    def _commit(self, message: str) -> None:
        if not self.git_enabled:
            return
        self._git("add", "-A")
        self._git("commit", "-q", "-m", message)

    # ── task file parsing (same format as pm.py) ───────────────────────────
    @staticmethod
    def _parse(path: str) -> dict:
        text = open(path, encoding="utf-8").read()
        m = re.match(r"^---\n(.*?)\n---\n?(.*)$", text, re.S)
        meta, body = {}, text
        if m:
            for line in m.group(1).splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    meta[k.strip()] = v.strip()
            body = m.group(2)
        meta["_body"] = body
        meta["_path"] = path
        return meta

    @staticmethod
    def _dump(t: dict) -> None:
        lines = ["---"]
        for k in FIELDS:
            lines.append(f"{k}: {t.get(k, '')}")
        lines.append("---")
        with open(t["_path"], "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n" + t["_body"])

    @staticmethod
    def _section(body: str, name: str) -> str:
        m = re.search(rf"## {name}\n(.*?)(?=\n## |\Z)", body, re.S)
        return m.group(1).strip() if m else ""

    def _append_section(self, t: dict, name: str, text: str) -> None:
        entry = f"- [{now()}] {text.strip()}"
        if f"## {name}" in t["_body"]:
            t["_body"] = re.sub(rf"(## {name}\n)", rf"\1{entry}\n", t["_body"], count=1)
        else:
            t["_body"] += f"\n## {name}\n{entry}\n"
        self._dump(t)

    # ── jurisdiction ───────────────────────────────────────────────────────
    @staticmethod
    def _check_jurisdiction(t: dict, company: str) -> None:
        """A caller scoped to a company may only touch that company's tasks.

        company == "*" is the hub/Chairman scope (the API layer decides who may
        present it). Tasks with an empty company field belong to the default
        project scope.
        """
        if company == "*":
            return
        task_company = t.get("company", "") or ""
        if task_company != (company or ""):
            raise Forbidden(
                f"jurisdiction: caller scope '{company or '(default)'}' may not touch "
                f"{t['id']} owned by '{task_company or '(default)'}'"
            )

    # ── public API ─────────────────────────────────────────────────────────
    def serializable(self, t: dict) -> dict:
        out = {k: t.get(k, "") for k in FIELDS}
        out["evidence"] = self._section(t["_body"], "Evidence")
        out["objective"] = self._section(t["_body"], "Objective")
        out["work_log"] = self._section(t["_body"], "Work Log")
        return out

    def load_all(self) -> list[dict]:
        out = []
        for fn in sorted(os.listdir(self.tasks_dir)):
            if fn.startswith("T-") and fn.endswith(".md"):
                out.append(self._parse(os.path.join(self.tasks_dir, fn)))
        return out

    def get(self, tid: str, company: str = "*") -> dict:
        tid = tid if tid.startswith("T-") else f"T-{int(tid):04d}"
        p = os.path.join(self.tasks_dir, tid + ".md")
        if not os.path.exists(p):
            raise NotFound(f"no task {tid}")
        t = self._parse(p)
        self._check_jurisdiction(t, company)
        return t

    def list_tasks(self, company: str = "*", status: str | None = None,
                   dept: str | None = None) -> list[dict]:
        out = []
        for t in self.load_all():
            if company != "*" and (t.get("company", "") or "") != (company or ""):
                continue  # jurisdiction: other companies' tasks are invisible
            if status and t.get("status") != status:
                continue
            if dept and t.get("dept") != dept:
                continue
            out.append(t)
        return out

    def new(self, title: str, company: str = "", dept: str = "unassigned",
            context: str = "other", objective: str = "", service: str = "",
            endpoint: str = "", budget_minutes: int = 60, due: str = "",
            depends_on: str = "", actor: str = "registrar") -> dict:
        if context not in CONTEXTS:
            raise BoardError(f"context must be one of {CONTEXTS}")
        tasks = self.load_all()
        n = max([int(t["id"][2:]) for t in tasks
                 if re.match(r"^T-\d+$", t.get("id", ""))], default=0) + 1
        tid = f"T-{n:04d}"
        t = {k: "" for k in FIELDS}
        t.update(
            id=tid, title=title, status="todo", dept=dept, context=context,
            company=company, budget_minutes=str(budget_minutes), due=due,
            depends_on=depends_on, created_at=now(), service=service,
            endpoint=endpoint, assignee="",
            _path=os.path.join(self.tasks_dir, tid + ".md"),
            _body=f"\n## Objective\n{objective or title}\n\n## Work Log\n\n## Evidence\n",
        )
        self._dump(t)
        self._commit(f"{tid}: created '{title}' [company={company or '(default)'} "
                     f"context={context}] by {actor}")
        return t

    # ── THE EVIDENCE GATE ──────────────────────────────────────────────────
    def _gate(self, t: dict) -> None:
        """Refuse `done` without proof. This runs in the Registrar service,
        below any agent/model/harness — it cannot be prompt-engineered away."""
        ev = self._section(t["_body"], "Evidence")
        if not ev:
            raise Refused(
                f"REFUSED: {t['id']} has no recorded evidence. Record evidence "
                f"(POST /tasks/{t['id']}/evidence), then retry."
            )
        if (t.get("context") or "") == "ux":
            ok = False
            for m in re.finditer(r"artifact:\s*(\S+)", ev):
                rel = m.group(1).strip()
                p = os.path.normpath(os.path.join(self.root, rel))
                if (p.startswith(self.artifacts_dir) and os.path.isfile(p)
                        and p.lower().endswith(IMAGE_EXTS)):
                    ok = True
                    break
            if not ok:
                raise Refused(
                    f"REFUSED: {t['id']} is a `ux` task — it cannot close without a real "
                    f"screenshot artifact on disk (evidence line `artifact: artifacts/...png`). "
                    f"Run ux-validate to capture one."
                )

    def move(self, tid: str, status: str, company: str = "*",
             actor: str = "registrar") -> dict:
        if status not in STATUSES:
            raise BoardError(f"status must be one of {STATUSES}")
        t = self.get(tid, company)
        if status == "done":
            self._gate(t)
            t["done_at"] = now()
        if status == "doing" and not t.get("started_at"):
            t["started_at"] = now()
        old = t["status"]
        t["status"] = status
        self._dump(t)
        self._append_section(t, "Work Log", f"status: {old} -> {status} (by {actor})")
        self._commit(f"{t['id']}: {old} -> {status} by {actor}")
        return t

    def evidence(self, tid: str, text: str, artifact: str = "",
                 company: str = "*", actor: str = "registrar") -> dict:
        t = self.get(tid, company)
        if artifact:
            p = os.path.normpath(os.path.join(self.root, artifact))
            if not p.startswith(self.artifacts_dir):
                raise BoardError("artifact path must live under artifacts/")
            if not os.path.isfile(p):
                raise BoardError(f"artifact does not exist on disk: {artifact} "
                                 "(evidence must be real)")
            text = f"{text} | artifact: {artifact}"
        self._append_section(t, "Evidence", f"{text} (by {actor})")
        self._commit(f"{t['id']}: evidence recorded by {actor}")
        return t

    def log(self, tid: str, text: str, company: str = "*",
            actor: str = "registrar") -> dict:
        t = self.get(tid, company)
        self._append_section(t, "Work Log", f"{text} (by {actor})")
        self._commit(f"{t['id']}: log by {actor}")
        return t

    def assign(self, tid: str, who: str, company: str = "*",
               actor: str = "registrar") -> dict:
        t = self.get(tid, company)
        t["assignee"] = who
        self._dump(t)
        self._commit(f"{t['id']}: assigned to {who} by {actor}")
        return t

    def stats(self, company: str = "*") -> dict:
        counts = {s: 0 for s in STATUSES}
        for t in self.list_tasks(company):
            counts[t.get("status", "todo")] = counts.get(t.get("status", "todo"), 0) + 1
        counts["total"] = sum(v for k, v in counts.items() if k in STATUSES)
        return counts
