"""Registrar gate tests: the REFUSED path is the product. Every test here is a
claim from the directive's launch gate."""

import os
import subprocess

import pytest
from fastapi.testclient import TestClient

import app as app_module


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.delenv("REGISTRAR_ADMIN_TOKEN", raising=False)
    application = app_module.create_app(str(tmp_path / "board"))
    return TestClient(application)


HUB = {"X-Company": "*"}
ACME = {"X-Company": "acme"}
GLOBEX = {"X-Company": "globex"}


def make_task(client, headers=ACME, **overrides):
    body = {"title": "prove the gate", "context": "code"}
    body.update(overrides)
    r = client.post("/tasks", json=body, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()["id"]


# ── the evidence gate ───────────────────────────────────────────────────────
def test_move_to_done_without_evidence_is_refused(client):
    tid = make_task(client)
    r = client.post(f"/tasks/{tid}/move", json={"status": "done", "actor": "ceo"},
                    headers=ACME)
    assert r.status_code == 409
    assert r.json()["detail"]["refused"] is True
    assert "REFUSED" in r.json()["detail"]["reason"]
    # and the task did NOT move
    assert client.get(f"/tasks/{tid}", headers=ACME).json()["status"] == "todo"


def test_move_to_done_with_evidence_is_accepted(client):
    tid = make_task(client)
    r = client.post(f"/tasks/{tid}/evidence",
                    json={"text": "pytest 12 passed in 0.8s", "actor": "ceo"},
                    headers=ACME)
    assert r.status_code == 200
    r = client.post(f"/tasks/{tid}/move", json={"status": "done", "actor": "ceo"},
                    headers=ACME)
    assert r.status_code == 200
    assert r.json()["status"] == "done"
    assert r.json()["done_at"]


def test_non_done_moves_do_not_need_evidence(client):
    tid = make_task(client)
    for status in ["doing", "blocked", "validating", "todo"]:
        r = client.post(f"/tasks/{tid}/move", json={"status": status},
                        headers=ACME)
        assert r.status_code == 200, r.text


# ── the ux screenshot gate (§5.2 contract) ──────────────────────────────────
def test_ux_task_refused_without_screenshot_even_with_text_evidence(client):
    tid = make_task(client, context="ux")
    client.post(f"/tasks/{tid}/evidence",
                json={"text": "looks good to me, trust me"}, headers=ACME)
    r = client.post(f"/tasks/{tid}/move", json={"status": "done"}, headers=ACME)
    assert r.status_code == 409
    assert "screenshot" in r.json()["detail"]["reason"]


def test_ux_task_evidence_with_nonexistent_artifact_is_rejected(client):
    tid = make_task(client, context="ux")
    r = client.post(f"/tasks/{tid}/evidence",
                    json={"text": "screenshot", "artifact": "artifacts/ghost.png"},
                    headers=ACME)
    assert r.status_code == 422
    assert "does not exist" in r.json()["detail"]


def test_ux_task_closes_with_real_screenshot_artifact(client, tmp_path):
    tid = make_task(client, context="ux")
    # a real file must exist under the board's artifacts/
    board_root = client.get("/health").json()["board"]
    art_dir = os.path.join(board_root, "artifacts", tid)
    os.makedirs(art_dir, exist_ok=True)
    shot = os.path.join(art_dir, "journey-desktop.png")
    with open(shot, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n fakepixels")
    rel = os.path.relpath(shot, board_root)
    r = client.post(f"/tasks/{tid}/evidence",
                    json={"text": "ux-validate: journey ok", "artifact": rel},
                    headers=ACME)
    assert r.status_code == 200, r.text
    r = client.post(f"/tasks/{tid}/move", json={"status": "done"}, headers=ACME)
    assert r.status_code == 200, r.text


# ── jurisdiction ────────────────────────────────────────────────────────────
def test_company_cannot_see_or_touch_anothers_tasks(client):
    tid = make_task(client, headers=ACME)
    # invisible in list
    listed = client.get("/tasks", headers=GLOBEX).json()
    assert all(t["id"] != tid for t in listed)
    # untouchable directly
    assert client.get(f"/tasks/{tid}", headers=GLOBEX).status_code == 403
    r = client.post(f"/tasks/{tid}/move", json={"status": "doing"}, headers=GLOBEX)
    assert r.status_code == 403
    # hub scope sees it
    assert client.get(f"/tasks/{tid}", headers=HUB).status_code == 200


def test_admin_token_required_for_hub_scope_when_configured(tmp_path, monkeypatch):
    monkeypatch.setenv("REGISTRAR_ADMIN_TOKEN", "s3cret")
    application = app_module.create_app(str(tmp_path / "board2"))
    c = TestClient(application)
    assert c.get("/tasks", headers={"X-Company": "*"}).status_code == 403
    ok = c.get("/tasks", headers={"X-Company": "*", "X-Admin-Token": "s3cret"})
    assert ok.status_code == 200


# ── git audit trail ─────────────────────────────────────────────────────────
def test_every_mutation_is_a_git_commit(client):
    tid = make_task(client)
    client.post(f"/tasks/{tid}/evidence", json={"text": "proof"}, headers=ACME)
    client.post(f"/tasks/{tid}/move", json={"status": "done"}, headers=ACME)
    board_root = client.get("/health").json()["board"]
    log = subprocess.run(["git", "-C", board_root, "log", "--oneline"],
                         capture_output=True, text=True).stdout
    assert "created" in log
    assert "evidence recorded" in log
    assert "todo -> done" in log
