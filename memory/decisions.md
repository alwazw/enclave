# Enclave — Decision Log

Append-only. Date · decision · why. The board wins if board and memory disagree.

---

## 2026-07-21 — Mission `enclave-launch` accepted (BUILD-DIRECTIVE)
The Chairman (via Dispatch) authorized the executable mission to make the repo
launch-ready. Real git work (commit/branch/PR/tag) is authorized on this dev host.
The launch project is itself governed by the gate it launches (dogfood).

### Locked decisions (Chairman — do not relitigate; override only on Chairman's word)
- **D1 — Name is Enclave.** Public brand Enclave everywhere. Internal codename `aef2`
  stays (renaming re-namespaces volumes/networks — not worth it) but must not leak
  publicly. Reconcile the `SOVEREIGN AI FACTORY` wordmark on the C2 mockups to Enclave.
- **D2 — Curate, delete nothing.** `core` profile is the launch spine + default install;
  every other service becomes an opt-in profile. Full 32-service catalog lives in the
  operator doc, not the front page. Narrative/default-profile decision, not a teardown.
- **D3 — Invert the README.** Governance-first up front; operator's manual demoted to
  `docs/`.
- **D4 — Refused-claim demo is a launch blocker.** No launch call without it.
- **D5 — Socket-proxy is a launch blocker.** No launch call with the raw docker socket
  exposed.
- **D6 — Branch hygiene forward from the clean slate.** `main` is the clean trunk; do
  launch work on a `launch` branch → PR into `main` → squash-merge → tag `v1.0.0`;
  branch protection on (PR required, no force-push).

### Hard boundaries (inherited)
1. The demo must be a **REAL** refusal — a faked/mocked `409` violates the thesis.
2. Dogfood the gate — every task closes through the Registrar with real evidence.
3. Delete nothing that works.
4. Single-project jurisdiction — the CEO owns `~/enclave` and only that.
5. Escalate, don't guess, on brand/scope/naming (esp. the C2 build — next mission).

---

## 2026-07-21 — Ground-truth recon findings (W0, verified against the live repo)
The directive said to start from reality; three corrections to §1:
- **ENV-1 (load-bearing):** `dockerd` (v29.3.1) DOES start in the code-web sandbox, but
  the proxy **403-blocks Docker Hub's blob CDN** (`production.cloudfront.docker.com`).
  So NO image pulls → no `docker build` / `docker compose up` here. Consequence: the
  container/compose-rendered evidence (W4 healthcheck, W5 core-up-healthy, W3 full demo
  GIF) must render on a Docker-Hub-capable host (the real Enclave host). Everything else
  — all code/config/docs, and the gate `409` proof via uvicorn — is buildable here.
  **Escalated to the Chairman for a decision on where that evidence renders.**
- **Correction:** raw `/var/run/docker.sock` mounts are on **dozzle, homepage, hermes,
  portainer** (four consumers) — the directive named Portainer/Homepage/mcp-docker;
  `mcp-servers.yml` only has a commented reference. W4 must cover the actual four.
- **Correction:** `docs/MEDIA-PRODUCTION-INSTRUCTIONS.md` (referenced by W3) **does not
  exist**; only `docs/DEMO-SHOT-SCRIPT.md` is present. W3 works from the shot script.

## 2026-07-21 — Evidence gate independently verified (Dispatch's core duty)
Not taken on the CEO's word — observed directly:
- `registrar/tests/test_gate.py`: **9/9 pass**.
- Live uvicorn Registrar: `POST /tasks/{id}/move {status:done}` with no evidence →
  **`409 {"refused": true, "reason": "REFUSED: ... no recorded evidence"}`**; board held
  at `todo`. Recorded evidence → `200`; retry `done` → `200` with `done_at`. Every
  mutation is a git commit in the board dir.
- `pm/pm.py` enforces the same gate (refused W0 `done` without evidence).
The governance engine the README will sell is real.

## OPEN — awaiting Chairman
- **ENV-1 evidence rendering** (above): produce compose/container evidence on the real
  host vs. unblock the registry in-session.
- **C2 mockups:** `c2-mockups-v1.html` / `v2.html` are held by the Chairman and not in
  the repo — W1 cannot commit them to `docs/design/` until provided.
- **Branch:** harness pinned this session to `claude/install-code-cli-866lsc`; D6 wants a
  `launch` branch. Proceeding on the pinned branch, PR into `main`; will reconcile the
  name with the Chairman.
