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
