# Enclave — Company Facts

**What we are:** Enclave — governed, sovereign, accountable AI agents. Local-first.
The narrow, mechanical claim: *an agent cannot mark a task "done" without recorded proof.*

**The wedge (lead with this):** during development an agent claimed "completed ✅"
with zero API calls — the board stayed `doing`. The gate refuses the lie. Everything
in the stack exists to make that refusal real instead of decorative.

## Substance (real, differentiated — do not rebuild)
- **Governance engine works.** `registrar/` is a FastAPI service that returns
  `409 {"refused": true}` on a `done` transition without evidence, validates
  file-backed evidence on disk, and requires a real `ux-validate` Playwright
  screenshot for `ux`-context tasks. Jurisdiction via `X-Company` scoping; audit
  trail = git commits in the board dir. Verified live 2026-07-21 (see decisions.md).
- **32-service Docker stack**, curated around a `core` profile spine
  (registrar + ux-validate are `core`). Extended profiles: knowledge, memory,
  extras, observability, automation, tools.
- **Air-gap is architectural**, not a flag: `config/litellm/litellm.airgap.yml`
  has no cloud `model_name`; `scripts/set-airgap.sh` swaps it in. LiteLLM cascade
  degrades to a local CPU floor. Sovereignty spectrum: AIR-GAP / HYBRID / GRID.
- Strong docs already exist: `docs/GOVERNANCE.md` (the hero asset — the money
  quote is line ~42), `docs/COMPARISON.md` (vs MetaGPT/CrewAI/LangGraph/Paperclip).

## Brand
- Public brand is **Enclave** everywhere. Internal compose codename `aef2` stays
  (`COMPOSE_PROJECT_NAME=aef2`, volume/network namespace) — internal only, must not
  leak into any public doc/diagram/README.

## Hosts & environments
- **Real Enclave host:** the Chairman's dev host (`$HOST_IP`), Docker-capable, runs
  the live 32-service stack. This is where container/compose-based evidence renders.
- **Code-web sandbox** (where the CEO currently builds): repo cloned, ephemeral,
  `dockerd` runs BUT Docker Hub blob CDN is proxy-blocked (403) — no image pulls,
  so no `docker build` / `docker compose up`. Pure-Python services (registrar via
  uvicorn, pip from pypi) DO run here. Only git persists; commit or it's gone.
