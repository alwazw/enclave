## 2026-07-15 — Postgres password drift: resync DB to new .env value, don't revert .env
Chairman edited .env (rotating most secrets) but the Postgres data volume already existed with
the old password baked in (Postgres only applies POSTGRES_PASSWORD on first init of an empty
volume). This broke every dependent service (Langfuse crash-looping, LiteLLM DB migrations
failing) with "password authentication failed for user aef2". Chairman chose: ALTER the live
Postgres role's password to match the new .env value (via the trust-authenticated local socket,
no data touched) over reverting .env to the old password. Consequence: keeps the Chairman's new
secret; no data loss; dependent services recovered after a restart.

## 2026-07-15 — .env cleanup batch (8 fixes) applied together
Chairman's manual .env edit left: duplicate CLOUDFLARE_EMAIL/GLOBAL_API_KEY/ALL_DNS_ZONE_KEY
block, a stray duplicate TELEGRAM_ID, REGISTRAR_PORT/REGISTRAR_ADMIN_TOKEN/UX_VALIDATE_PORT
dropped entirely, OLLAMA_DEFAULT/CODE/VISION_MODEL commented out with no explanation,
GROQ_API_KEY_1 commented out despite holding a real key, a garbage leftover comment line (invalid
YAML pasted into .env), and two weak/invalid secrets (LANGFUSE_ENCRYPTION_KEY was not valid hex
— contained g/h/i/j/k/l/m/n/o/p — and wrong length; N8N_ENCRYPTION_KEY was a non-random
sequential placeholder). All 8 fixed in one pass with Chairman's sign-off. Both encryption keys
regenerated via `openssl rand -hex 32` / `-hex 16`; safe since n8n had never started (no
encrypted data yet existed to invalidate) and Langfuse hadn't persisted anything under the old
key either.

## 2026-07-15 — Open Interpreter: build from source rather than use a community image or defer
`compose/ai-ml/open-interpreter/open-interpreter.yml` referenced `openinterpreter/
open-interpreter:latest`, which has never existed on Docker Hub (no official image published —
confirmed via web search). Its "repository does not exist or may require docker login" error is
what the Chairman read as a login problem; it wasn't — `docker compose pull` also aborts the
*entire* batch on the first per-image failure, so this one bad reference was blocking pulls for
every other service too. Chairman chose to build from source (over an unofficial community image
or disabling the service). See memory/departments/devops.md for build details/status.

## 2026-07-15 — mem0: confirmed still deferred, not touched this session
Re-validated the 2026-07-13 finding (ARM64-only image, hardcoded pgvector requirement) still
holds. Left excluded from bring-up. Not re-litigated — see memory/company.md "known gaps".

## 2026-07-15 — Disk: live LVM extend instead of hypervisor resize + reboot
Root disk hit 100% full mid-bring-up (aborted an image pull with ENOSPC), traced to genuine
undersizing (~45GB of Docker images/containers/volumes on a 62GB disk) rather than reclaimable
waste (apt cache/journal were negligible). Chairman initially planned a hypervisor-level disk
resize + reboot, but `lsblk`/`vgs` showed 63GB already unallocated inside the existing volume
group. Did a live `lvextend -l +100%FREE` + `resize2fs` instead — grew root from 62GB to 124GB
in ~10s with no reboot, no data touched. Chairman confirmed 16 vCPU / 20GB RAM (only ~5.4GB in
use) is sufficient; disk was the actual bottleneck, not compute.

## 2026-07-15 — Open Interpreter: build from source (PyPI, pinned) over community image/disable
Chairman chose to build Open Interpreter from source rather than substitute an unofficial
community Docker image or drop the service. Built from the real PyPI package
(`open-interpreter[server]==0.4.3`, the last real release — the upstream GitHub repo has since
been repurposed into an unrelated project, so PyPI is the actual source of truth, not GitHub
HEAD). Added a thin FastAPI wrapper (`open-interpreter/server.py`) to bridge this repo's env var
names (`SERVER_HOST`/`SERVER_PORT`) to upstream's (`INTERPRETER_HOST`/`INTERPRETER_PORT`) and to
add the `/health` route the compose healthcheck expects (upstream only ships `/heartbeat`).
Verified end-to-end (not just container-up): real code execution over `backend-net` from the
actual caller (Hermes), matching `agents/hermes/skills/code-executor/SKILL.md`'s documented
`/run` contract exactly, plus volume persistence and clean error handling. See
`memory/departments/devops.md` for the full verification trail. Consequence: `docker compose
pull` no longer aborts on this service; discovered along the way that `docker compose pull`
(without `--ignore-buildable`) fails on ANY of this repo's 4 build-from-source services by
design (pre-existing, not new) — operators should use `--ignore-buildable` for full-stack pulls.

## 2026-07-16 — n8n + Flowise unclaimed-admin bugs: write real bootstrap scripts, don't paper over with docs
Deep-validate found n8n's `.env` comment promising a bootstrap script that didn't exist (owner
account genuinely unclaimed, first LAN visitor could still claim it) and Flowise's documented
`FLOWISE_USERNAME`/`FLOWISE_PASSWORD` silently not working against the pulled v3.1.2 image (auth
model changed upstream to workspace/organization, env vars are dead in that version). Chose to
write real, idempotent, health-gated bootstrap scripts (`scripts/init-n8n-owner.sh`,
`scripts/init-flowise-admin.sh`) that call each app's actual current REST API — confirmed by
reading the shipped source inside the running containers, not assumed from docs or memory — over
alternatives like downgrading Flowise to a version where the old env vars worked, or just
documenting the gap. Consequence: both admin accounts are now genuinely claimed and verified via
authenticated login (not just "script exited 0"); both scripts are wired into `setup.sh`'s
automation-profile bring-up so this can't regress on a fresh install. See
`memory/departments/devops.md` for the full verification trail, exact API endpoints, and the
non-blocking upstream `@langchain/core` packaging quirk noted but not fixed.

## 2026-07-16 — Open WebUI first-visitor admin race: bootstrap script, not an ENABLE_SIGNUP fix
Deep-validate proved live that an unauthenticated `POST /api/v1/auths/signup` returned a full
admin JWT despite `OPENWEBUI_ENABLE_SIGNUP=false`. Investigated before assuming the env var was
broken: confirmed against the running container's actual source that Open WebUI deliberately
lets the first-ever account claim admin regardless of ENABLE_SIGNUP (there'd be no other
non-interactive way to create the initial admin) — same class of gap already known for AFFiNE
and n8n. Chose the same fix pattern as n8n/Trilium: an idempotent bootstrap script
(`scripts/init-open-webui-admin.sh`) that claims the admin slot atomically as part of bring-up,
over trying to find a config flag that doesn't exist. Verified by reproducing the exact QA
exploit afterward: unauthenticated signup now returns 403; the real `.env`-configured admin logs
in fine. Wired into both `setup.sh` and `scripts/onboard.sh`.

## 2026-07-16 — Onboarding hardening: generic detection, not values tuned to this host
Chairman's explicit constraint: HOST_IP auto-detection, GPU detection, and Ollama resource
governance must be computed from whatever host they run on, not hardcoded to this VM's specs
(16 vCPU/20GB/no GPU was incidental, not a target to build for). Implemented in `setup.sh`:
HOST_IP auto-detects the single non-loopback/non-docker-bridge IPv4, or prompts if multiple
exist; GPU detection checks `nvidia-smi` actually reports a device before offering the existing
(previously-dead) `ollama.gpu.yml` overlay; `OLLAMA_NUM_THREADS`/`OLLAMA_NUM_PARALLEL` are
computed from `nproc` (not fixed numbers) and written to `.env`; `OLLAMA_KEEP_ALIVE` shortened
from a hardcoded 24h to a configurable 30m default; the Ollama model-pull loop is now driven live
by `.env`'s `OLLAMA_*_MODEL` vars instead of a hardcoded 2-model array, closing the gap where
`OLLAMA_CODE_MODEL`/`OLLAMA_VISION_MODEL` were declared but silently never pulled; `.env.example`
defaults downsized from `qwen2.5-coder:32b` to `qwen2.5-coder:3b` and `llava` commented out by
default (documented as opt-in for capable hardware) — conservative defaults for an unknown target
machine, not a claim about any specific user's hardware. Added a disk-headroom pre-check before
image/model pulls given tonight's ENOSPC incident. Applied live to this host as verification
(HOST_IP correctly resolved to 10.10.10.27, computed NUM_THREADS=8/NUM_PARALLEL=2 for its 16
cores) without pulling this host's actual models (left for on-demand/later). **Known gap:**
`scripts/onboard.sh` (the primary gum-TUI installer) still lacks these five detection/governance
mechanisms — only the six admin-claim/auth-file bootstrap scripts (dozzle, portainer, n8n,
trilium, open-webui, flowise) were ported there tonight; `setup.sh` has the full set. Follow-up
work, not done tonight.

## 2026-07-16 — Dozzle/Portainer: healthchecks that could never pass, and missing pre-seed scripts
Two distinct pre-existing bugs, both surfacing only because this was the first full bring-up:
(1) both services' Docker healthchecks called `wget`, which doesn't exist in either's distroless
image — verified via direct `docker exec`, these checks could never have passed regardless of
app state. Fixed with Dozzle's own built-in `healthcheck` subcommand; removed Portainer's
healthcheck entirely since no in-image binary can run any check (documented why in the compose
file rather than leaving a silently-broken one). (2) `scripts/init-dozzle-auth.sh` and
`scripts/init-portainer-auth.sh` were referenced in `.env`/`.env.example` comments as already
generating required config files, but didn't exist — Docker's bind-mount-nonexistent-path
auto-creates a directory instead of a file, breaking both containers on first-ever bring-up (had
to `rmdir` the bad path AND clean a same-shaped directory that had leaked into Dozzle's named
volume before the real files could be written). Wrote both scripts, wired into both installers.

## 2026-07-16 — Redis eviction policy: found by actually reading a migration log, not trusting Exit(0)
Chairman pushed back on treating `aef2_affine_migration`'s `Exited (0)` as clean — right call.
Its full log (37KB, mostly benign Nest.js startup noise) contained `IMPORTANT! Eviction policy is
allkeys-lru. It should be "noeviction"` eight times. Root cause: `compose/database/redis/
redis.yml` explicitly set `--maxmemory-policy allkeys-lru` with a 512MB cap, but this Redis backs
n8n's BullMQ queue and AFFiNE's session store — not a pure cache. BullMQ's own docs require
`noeviction`; under LRU, a queued job or active session could be silently evicted under memory
pressure with zero error surfaced. Fixed: `noeviction` + raised cap to 1GB given this host's real
headroom, with an inline comment. Verified live (CONFIG GET both settled correctly; n8n/AFFiNE
still healthy post-recreate). Lesson generalized into memory/departments/qa.md and the closed
GitHub issue: a one-shot container's exit code says nothing about whether its own log flagged a
real, actionable warning — this class of check needs to be part of the deep-validate log-review
step going forward, not just "logs clean since start" for long-running containers.

## 2026-07-16 — README.md: fixed confirmed drift, did not claim exhaustive line-by-line coverage
Chairman flagged (correctly) that README.md still referenced the old `AEF2` project name in its
clone URL (with an unfilled `youruser` placeholder) and a completely fictional default model list
inherited from an earlier draft. Investigating surfaced much more: fictional `OLLAMA_RUNTIME`/
`OLLAMA_MAX_VRAM`/`OLLAMA_MODELS` env vars that don't exist anywhere in this repo, a fictional
LiteLLM alias table bearing no resemblance to the real `openai/morpheus-*` provider cascade in
`config/litellm/config.yml`, generic un-prefixed container names throughout "Common Commands"
(`ollama` vs the real `aef2_ollama`, etc.), wrong file paths (`config.yaml` vs real `.yml`,
`.env.template` vs real `.env.example`, `cli-config.yaml` vs real `hermes-config.yaml`), a dead
env var (`SURREALDB_PASSWORD` vs the already-resolved canonical `SURREALDB_PASS`), and a false
"all health checks have been fixed" claim contradicted by tonight's own Dozzle/Portainer/Langfuse
findings. Fixed everything found via this targeted sweep plus a read-through of Quick Start/
Prerequisites/Configuration Guide. Explicitly did NOT claim full line-by-line coverage of the
954-line file — Troubleshooting's body and Repository Structure were only spot-checked, and no
other `.md` files beyond README/CLAUDE/the already-touched agent+skill files were audited.
Recorded as an honest scope boundary in the closed GitHub issue rather than overclaiming
completeness. Also filed (open, not implemented) a feature-request issue per Chairman's
recommendation: scheduled stack-wide update/dependency-drift checks, and a single-source-of-truth
requirements file so docs and the installer can't silently diverge from each other the way this
one did.

## 2026-07-16 — Full-log audit (not just tails) across all 30 containers, per Chairman's process challenge
Following the affine_migration/Redis-eviction lesson, grepped every running container's FULL log
(not tail) for WARN/FATAL/IMPORTANT/deprecated. Found and fixed: (1) Redis's kernel host lacked
`vm.overcommit_memory=1` (Redis's own documented requirement, risking failed BGSAVE under memory
pressure — exactly the condition a 30-container host is prone to). Chairman confirmed this
host-wide kernel change explicitly; applied live + persisted in /etc/sysctl.conf. (2) Open WebUI's
CORS_ALLOW_ORIGIN defaults to `*` (the app's own insecure default, not set by this repo) — filed
as an open issue (#17) rather than fixed live, since severity is lower for this stack's LAN-only
deployment model and warranted its own scoped decision rather than a rushed compose change this
late in an already-large session. Everything else surfaced by the full-log sweep was triaged as
either already-known (AFFiNE mailer/copilot warnings, Weaviate single-node Raft noise — both
already documented pre-existing limitations), stale (Postgres auth-failure lines from *before*
tonight's password-drift fix, not current), or genuinely benign upstream noise (npm deprecation
warnings in MCP server packages, individual SearXNG search-engine timeouts, SurrealDB's expected
"root user already exists" message). Documented the triage reasoning rather than silently
ignoring findings, per this session's now-established "read the whole log, decide explicitly"
discipline.

## 2026-07-16 — LITELLM_API_KEY was never real; validation depth was insufficient to catch it
Chairman spotted from the Open WebUI UI that no LiteLLM fallback models were listed despite
a "pre-loaded" API key. Investigation found the actual bug was stack-wide, not UI-specific:
`LITELLM_API_KEY` (shared by 7 services: hermes, n8n, flowise, anything-llm, open-interpreter,
open-webui, the ceo agent) was never a real, registered LiteLLM credential — 401 "Unable to
find token in ... LiteLLM_VerificationTokenTable". `scripts/onboard.sh` has
`provision_guardrail_key()` to mint a real one; never executed since the stack was brought up
manually this session, not via the full onboard.sh wizard. Chairman confirmed minting a real
key ($2/30-day budget, free-tier model allowlist, matching onboard.sh's own design) and
rolling it to all 6 live dependent containers. Found and fixed two more real bugs along the
way: Open WebUI persists its OpenAI connection config to its own DB and ignores env var
changes after first boot (had to push the new key via its actual admin API,
`POST /openai/config/update`); Open Interpreter's litellm-library client strips one `openai/`
prefix layer before hitting a custom api_base, colliding with this stack's aliases already
having `openai/` baked into the name (fixed in `open-interpreter/server.py`, unconditional
prepend rather than conditional).

Chairman then directly challenged how this was missed given a "massively long" validation
pass already ran tonight: correctly — every earlier check touching LiteLLM was either an
unauthenticated `/health`/`/health/liveliness` ping or used the master key rather than each
service's actual credential. Audited honestly: 4 of the 7 affected services got real
functional re-verification (LiteLLM direct, Open WebUI's authenticated `/api/models`, Open
Interpreter's real completions endpoint, Hermes's actual CLI chat round-trip). n8n/Flowise/
AnythingLLM only got credential-match confirmation, not a real workflow/chatflow/chat
execution — a first attempt at an n8n workflow-level test was correctly blocked by the
permission system for embedding the live key in a persistent, queryable node rather than
using n8n's credential store. Filed as two GitHub issues (#22 resolved/closed, #23 open —
the validation-gap checklist) rather than either quietly patching or claiming full coverage.
Also amended `.claude/skills/deep-validate/SKILL.md` step 4 directly so this class of gap is
harder to reproduce: explicitly distinguishes liveness checks from real credential/protocol
checks now, with this incident cited inline.
