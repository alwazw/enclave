"""Enclave ux-validate — the experience gate's screenshot producer (§5.2).

Renders the REAL screen with Playwright (desktop + mobile viewports), writes
PNG screenshots into the shared board volume (`artifacts/<task-id>/`), and —
optionally — records them as evidence on the Registrar so the task can close.

The consumer side lives in the Registrar: a `ux`-context task is REFUSED
`done` unless a real screenshot artifact exists on disk. This service is how
an agent honestly satisfies that gate: no rendered page, no screenshot, no close.
"""

import os
from datetime import datetime, timezone

import httpx
from fastapi import FastAPI, HTTPException
from playwright.sync_api import sync_playwright
from pydantic import BaseModel

BOARD_DIR = os.environ.get("BOARD_DIR", "/board")
REGISTRAR_URL = os.environ.get("REGISTRAR_URL", "http://registrar:8090")

VIEWPORTS = {
    "desktop": {"width": 1280, "height": 800},
    "mobile": {"width": 390, "height": 844},
}

app = FastAPI(
    title="Enclave ux-validate",
    description="Playwright experience gate: real screenshots as evidence.",
    version="0.1.0",
)


class ValidateRequest(BaseModel):
    task_id: str
    url: str
    company: str = ""          # jurisdiction scope used when recording evidence
    full_page: bool = False
    record_evidence: bool = True
    actor: str = "ux-validate"


@app.get("/health")
def health():
    return {"status": "ok", "service": "enclave-ux-validate",
            "board": BOARD_DIR, "registrar": REGISTRAR_URL}


@app.post("/validate")
def validate(req: ValidateRequest):
    """Render req.url in real browsers and write screenshot artifacts.

    Deliberately a sync endpoint (FastAPI threadpool) — Playwright's sync API
    may not run on the event loop thread.
    """
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    outdir = os.path.join(BOARD_DIR, "artifacts", req.task_id)
    os.makedirs(outdir, exist_ok=True)

    shots: list[str] = []
    with sync_playwright() as pw:
        browser = pw.chromium.launch(args=["--no-sandbox"])
        try:
            for name, vp in VIEWPORTS.items():
                page = browser.new_page(viewport=vp)
                try:
                    page.goto(req.url, wait_until="networkidle", timeout=30_000)
                except Exception as exc:
                    raise HTTPException(
                        502,
                        f"page failed to render at {req.url} ({name}): {exc} — "
                        f"no screenshot, no evidence, task stays open.",
                    )
                path = os.path.join(outdir, f"{ts}-{name}.png")
                page.screenshot(path=path, full_page=req.full_page)
                shots.append(os.path.relpath(path, BOARD_DIR))
                page.close()
        finally:
            browser.close()

    recorded = []
    if req.record_evidence:
        headers = {"X-Company": req.company} if req.company else {"X-Company": "*"}
        admin_token = os.environ.get("REGISTRAR_ADMIN_TOKEN", "")
        if headers["X-Company"] == "*" and admin_token:
            headers["X-Admin-Token"] = admin_token
        with httpx.Client(timeout=15) as client:
            for rel in shots:
                r = client.post(
                    f"{REGISTRAR_URL}/tasks/{req.task_id}/evidence",
                    json={
                        "text": f"ux-validate: rendered {req.url} "
                                f"({'mobile' if '-mobile' in rel else 'desktop'})",
                        "artifact": rel,
                        "actor": req.actor,
                    },
                    headers=headers,
                )
                if r.status_code != 200:
                    raise HTTPException(
                        502, f"screenshot written but evidence refused by registrar: "
                             f"HTTP {r.status_code} {r.text[:200]}")
                recorded.append(rel)

    return {"task_id": req.task_id, "url": req.url,
            "screenshots": shots, "evidence_recorded": recorded}
