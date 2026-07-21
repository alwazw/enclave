# Enclave — Roadmap

## NOW — Mission `enclave-launch` (BUILD-DIRECTIVE from the Chairman via Dispatch)
Turn the repo from *strong substance, launch-unready packaging* into a launch-ready
public repository led by its governance story, with the evidence gate demonstrated.
Board: W1–W6 (+ W0 recon/proof). Every task closes only with recorded evidence — the same
evidence gate enforced locally by `pm.py` (`move … done` refuses without evidence) and over
HTTP by the Registrar for the live stack (dogfood it). Definition of Done in the directive §7.

| WS | What | Launch-blocking? | Board |
|----|------|------------------|-------|
| W1 | Brand reconciliation AEF2→Enclave (public surfaces); branch hygiene; commit C2 mockups to `docs/design/` | no | T-0001 |
| W2 | README inversion — governance-first; operator manual → `docs/OPERATIONS.md` (**primary deliverable**) | no (but the point) | T-0002 |
| W3 | Evidence-gate demo (hero GIF) + reproducible one-command `409` trigger | **YES (D4)** | T-0003 |
| W4 | Security floor — `docker-socket-proxy` in front of raw-socket consumers | **YES (D5)** | T-0004 |
| W5 | `core` as default profile; extended profiles opt-in | no | T-0005 |
| W6 | CONTRIBUTING, CODE_OF_CONDUCT, `docs/launch/SHOW-HN.md` (Chairman fires the post) | no | T-0006 |

**Evidence renders in-sandbox (Chairman's call, decisions.md ENV-1):** the sandbox is
the project host. `dockerd` runs and images pull via `mirror.gcr.io`, so the container/
compose gates (W4 healthcheck, W5 core-up, W3 demo) are producible here. The gate `409`
is already proven via uvicorn. Open infra nut: apt-in-build for the three custom images
(head-of-devops owns the in-sandbox bring-up).

## NEXT
- C2 Command Center — **explicitly NOT in this directive** (next mission). If the CEO
  drifts toward building C2, that is an escalation, not scope.
- Hosted read-only demo — only if the Chairman greenlights (stretch).

## LATER
- Public launch actions (making the repo prominent, the Show HN post) — the Chairman's
  own actions. The CEO delivers a launch-*ready* repo; it does not launch it.
