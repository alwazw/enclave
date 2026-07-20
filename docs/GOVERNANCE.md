# Enclave — Governance & Threat Model

Enclave's claim is narrow and mechanical: **an agent cannot mark a task "done"
without recorded proof.** This document says exactly what is enforced, where,
and what is *not* covered. No security theater — read the limitations.

## The three controls

### 1. Provable completion (the evidence gate)
- Enforced by the **Registrar**, a separate FastAPI service — not by prompts.
  `POST /tasks/{id}/move {"status":"done"}` returns
  `409 {"refused": true, "reason": "REFUSED: ..."}` unless evidence is recorded.
- Evidence referencing a file (screenshots, reports) is validated **on disk**:
  a nonexistent artifact is rejected (`422`) at record time.
- `ux`-context tasks require a **real screenshot artifact** produced by the
  `ux-validate` service (Playwright renders the actual page at desktop and
  mobile viewports). A page that fails to render yields no screenshot, no
  evidence, no close.
- The gate is model-agnostic and harness-agnostic: it sits behind an HTTP API,
  below anything the agent can prompt-engineer.

### 2. Jurisdiction (bounded agents)
- Every Registrar request carries an `X-Company` scope. The Registrar itself
  enforces this today — verified live: a scoped request cannot list, read, or
  mutate another company's tasks (`403`, invisible in listings).
- Hub scope (`*`) is reserved for the gateway/Chairman and gated by
  `REGISTRAR_ADMIN_TOKEN` when configured.
- **Not yet deployed:** the `ceo` service (`compose/governance/ceo/`, a LangGraph
  supervisor meant to run as one bounded container per company, attached only
  to its own network/volume namespace) exists in this repo but hasn't been
  brought up on any live host yet. Until it is, jurisdiction is enforced at the
  Registrar's API layer (real, verified) but there is no running CEO container
  to demonstrate the compose-level network/volume isolation described above.

### 3. Audit trail
- Every board mutation is a **git commit** inside the board directory: who,
  what, when, task by task. The history outlives projects (pause/terminate
  freeze the future; they never rewrite the past).

## Threat model — what this defends against

| Threat | Control |
|---|---|
| Agent reports "done" without doing the work | Evidence gate refuses the transition; board stays truthful |
| Agent fabricates evidence text | File-backed evidence is validated on disk; ux tasks need a real rendered screenshot |
| Agent claims completion in chat while skipping the API | The board is the record; anything not on the board did not happen (observed live during development: an agent claimed "completed ✅" with zero API calls — the board stayed `doing`) |
| Agent reaches into another project | Jurisdiction scoping: invisible + 403 |
| Silent history rewriting | Append-only git audit trail in the board dir |
| Cloud dependency / data egress | Fully local stack; LiteLLM fallback chain runs CPU-only; air-gappable |

## What this does NOT defend against (honest limitations)

- **A malicious operator.** Whoever controls the host controls the board, git
  history, and tokens. Enclave governs *agents*, not root.
- **Semantically hollow evidence.** The gate proves evidence *exists and is
  real* (a passing test line, an actual rendered screenshot). It does not prove
  the test was meaningful or the screenshot shows a *correct* UI. Pair it with
  review; the screenshot thumbnails on the board exist to make human review
  cheap.
- **Compromised evidence producers.** If the container running ux-validate is
  subverted, its screenshots are as trustworthy as that container. Artifact
  paths are constrained to the board volume; producers run as separate
  services with minimal mounts.
- **Prompt injection inside a task's own scope.** A CEO can be talked into
  doing its own work badly. It cannot be talked into closing without evidence
  (server-side) or crossing projects (scoping), which is the point: the blast
  radius is one project's quality, not the org's integrity.
- **Network-level lateral movement** beyond what Docker network separation
  provides. Harden the host as you would any Docker host.

## Deployment posture

- Secrets live only in a gitignored `.env`; `.env.example` is placeholders;
  gitleaks + a personal-identifier denylist run before publishing.
- No service requires a GPU; the LLM path degrades through remote free tiers to
  local CPU inference (documented in the README).
- The admin token, when set, is required for hub-scope operations; per-company
  scopes need no shared secret (isolation comes from what a container's
  environment simply does not contain).
