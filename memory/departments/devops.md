# DevOps — Working Memory

## 2026-07-15 — Mid-session status (stack recovery from .env edit + disk-full incident)
Session in progress; picking this up cold, check current `docker ps -a` and this repo's
`.env`/compose files against what's below before trusting anything here as still accurate.

**Fixed this session:**
- Postgres password drift (see decisions.md) — resynced, Langfuse/LiteLLM recovered.
- .env: deduped + restored missing vars + regenerated 2 broken secrets (see decisions.md).
- Langfuse healthcheck: added `HOSTNAME: "0.0.0.0"` to `compose/ai-ml/langfuse/langfuse.yml`
  environment block. Root cause: Next.js standalone server binds to `$HOSTNAME` if set; Docker
  auto-sets HOSTNAME to the container ID, which isn't reachable via `localhost` — broke the
  healthcheck (`wget http://localhost:3000/...` got connection refused even though the app was
  actually up and listening on the container's real IP). Generalizable gotcha: any other
  Next.js-standalone-server image in this stack could hit the same issue if its healthcheck
  targets localhost.
- Disk: live LVM extend 62GB→124GB (see decisions.md).

**In progress / not yet verified this session:**
- Open Interpreter: build-from-source in progress. Confirmed via PyPI sdist inspection
  (NOT the current GitHub repo — `OpenInterpreter/open-interpreter` on GitHub has been
  repurposed into an unrelated project; PyPI `open-interpreter==0.4.3` is the real source) that
  it ships a FastAPI server (`interpreter.core.async_core.AsyncInterpreter`, `[server]` extra)
  with `/heartbeat`, `/run` (matches `agents/hermes/skills/code-executor/SKILL.md`'s documented
  contract exactly), and `/openai/chat/completions`. No upstream `/health` route — needs a thin
  wrapper adding one. Real env var names upstream reads are `INTERPRETER_HOST`/`INTERPRETER_PORT`,
  not this repo's `SERVER_HOST`/`SERVER_PORT` — the wrapper must bridge that. Dockerfile +
  wrapper + updated compose file were staged (not yet landed) before hitting the disk-full
  wall; needs to be resumed now that space exists.
- Full multi-profile bring-up was interrupted twice by disk pressure. `aef2_hermes` and
  `aef2_open_webui` were left in `Created` (never started) state — needs `docker compose up -d`
  re-run once open-interpreter lands, then docker-exec-level verification per container
  (health + logs + real dependency connectivity, not just `docker ps` status) before this can be
  called done.
- mem0 and open-interpreter both excluded from the `memory` profile bring-up until the above
  lands; re-include open-interpreter once its build is verified.

**Config file correction (2026-07-16):** an earlier entry here called `config/litellm/
litellm.yml` and `config/litellm/config.yml` "near-duplicates" needing de-duplication — that
was wrong, checked more carefully while fixing the router retry-policy bug. `config.yml` is
a **symlink to litellm.yml** (`config.yml -> litellm.yml`), i.e. the literal same file, not
independent copies — editing one edits both, and there's nothing to reconcile. `git mv`/`ln`
can't write through the symlink directly (Edit/Write tools refuse it) — always edit
`litellm.yml`, the real target, never `config.yml`. `config/litellm/setup-default-config.yaml`
is a genuinely separate, unmounted, stale reference file — that part of the original note
still holds.

## 2026-07-15 — Open Interpreter: build-from-source landed, contract verified end to end
Landed the staged Dockerfile/wrapper (`agents/open-interpreter/` was the planned path; actually
placed at top-level `open-interpreter/` to match the existing `ceo/`, `registrar/`,
`ux-validate/` sibling-directory convention — `Dockerfile` + `server.py`). Compose now does
`build: ../../../open-interpreter` + `image: enclave/open-interpreter:latest` in
`compose/ai-ml/open-interpreter/open-interpreter.yml`; every existing env var, port (8143),
volume (`oi_workspace`), network (`backend-net`), label, and the `/health` healthcheck are
unchanged. Base: `python:3.11-slim` + `pip install "open-interpreter[server]==0.4.3"` (pinned —
PyPI is the real source of truth; the GitHub repo `OpenInterpreter/open-interpreter` has been
repurposed into an unrelated Rust/TS Codex-fork project, its current HEAD is NOT this package).

**Verified for real, not just "container is up":**
- `docker inspect` — healthcheck reports `healthy` after 3 consecutive real curl probes (Docker's
  own loop, not just a manual check).
- `docker exec aef2_hermes curl -X POST http://open-interpreter:8143/run -d
  '{"language":"python","code":"..."}'` over `backend-net` → real code ran, real stdout
  returned (`4`, `3.11.15`) — this is the exact contract `agents/hermes/skills/code-executor/
  SKILL.md` documents, confirmed reachable from the actual caller, not just localhost.
- Shell exec + volume write (`/workspace/proof.txt`) confirmed visible via a second, independent
  `docker exec` into the open-interpreter container itself — the named volume really persists.
- Deliberate `raise ValueError` came back as a 200 with the traceback in the response body (not
  a 500) — matches the SKILL.md's documented error-handling expectation (show stderr, don't crash).
- Container logs clean: only uvicorn startup + the requests just made, no tracebacks/warnings
  beyond the expected "binding 0.0.0.0 exposes it on the LAN" notice.

**Upstream reality check (for anyone re-touching this):** the real PyPI package's HTTP server
(`interpreter.core.async_core.AsyncInterpreter`) only ships `/heartbeat` (unauthenticated liveness)
and `/run`/`/upload`/`/download` gated behind `INTERPRETER_INSECURE_ROUTES=true` (no auth token
set here — this service only sits on `backend-net`, same trust boundary as registrar/ux-validate).
It reads `INTERPRETER_HOST`/`INTERPRETER_PORT`, NOT this repo's `SERVER_HOST`/`SERVER_PORT` — the
wrapper (`open-interpreter/server.py`) explicitly bridges that rather than relying on upstream's
env var names. There is no upstream `/health` route; the wrapper adds one. The `/run` endpoint's
`timeout` field (which the SKILL.md payload sends) is accepted but NOT enforced server-side —
real limitation, not implemented upstream as of 0.4.3.

**Pull-batch fix confirmed, plus a repo-wide operational note:** `openinterpreter/open-interpreter
:latest` never existed on Docker Hub and was aborting `docker compose pull` for the entire stack
on the first per-image failure (root cause of what the Chairman initially read as a `docker
login` problem — see decisions.md). That's fixed. BUT: plain `docker compose pull` still fails on
ANY build-from-source service in this repo (verified identically on `registrar` too, so this is
pre-existing/systemic, not new) because compose tries to pull the `image:` tag from a registry
that doesn't exist for locally-built images. The correct invocation for this repo, now that it
has 4 build-from-source services (`ceo`, `registrar`, `ux-validate`, `open-interpreter`), is
`docker compose pull --ignore-buildable` — confirmed this cleanly "Skips (Image can be built)"
all four and lets the rest of the batch proceed. With `--ignore-buildable`, the only remaining
batch-blocker across all profiles is the already-documented, separately-tracked `mem0` ARM64/
pgvector issue (unrelated, out of scope here, not re-touched).

**Status: DONE.** open-interpreter re-included in the `memory` profile bring-up; no longer
excluded. Observed (not performed by this task) that `aef2_hermes` and `aef2_open_webui`, which
were stuck in `Created` from the earlier disk-full incident, are now `Up (healthy)` — a
concurrent full-stack bring-up appears to have completed elsewhere in this session; worth a
`docker ps -a` sanity pass before assuming the whole stack is settled.

## 2026-07-16 — Open WebUI: fixed "first LAN visitor becomes admin" (same class as n8n/AFFiNE)
QA's deep-validate sweep proved live that despite `OPENWEBUI_ENABLE_SIGNUP=false`,
`POST /api/v1/auths/signup` still let a brand-new unauthenticated visitor self-register and
receive a full admin JWT, because `/api/config` reported `onboarding:true` (zero users).

**Root cause (verified against the running container's actual source, not docs/assumption):**
`ENABLE_SIGNUP` was NOT broken. `backend/open_webui/routers/auths.py`'s `/signup` handler
deliberately skips the `enable_signup` check whenever `Users.has_users()` is false — upstream's
own comment: "Don't gate the first admin on ENABLE_SIGNUP: it auto-disables and can persist
stale across a DB reset." The first-ever account is unconditionally promoted to admin (there is
no other non-interactive way to create the initial admin), and `ui.enable_signup` is then
force-set to `false` in the DB-persisted config as part of that same signup call — only the
2nd+ signup is actually blocked by the env var. Same class of gap already known for AFFiNE (dead
`AFFINE_ADMIN_EMAIL/PASSWORD`, documented 2026-07-13) and n8n (owner-claim step) — this repo's
bring-up did nothing to claim the slot atomically.

**Extra finding along the way (self-corrected — see below):** at the start of this task,
`scripts/init-n8n-owner.sh` was referenced by name in `.env`/`.env.example` comments ("closes
T-0042's n8n half") and in `onboard.sh`'s secret list, but did NOT exist on disk (confirmed via
`find`/`ls` at that point) — only `init-trilium.sh` was a real reference implementation. By the
time this task finished, `scripts/init-n8n-owner.sh` (plus `init-dozzle-auth.sh` and
`init-portainer-auth.sh`) had appeared on disk, evidently landed by a concurrent session working
the same class of bug in parallel — not written by this task. Spot-checked
`init-n8n-owner.sh`: well-built, same idiom (idempotent, verifies via `/rest/settings` +
authenticated `/rest/login`, handles the concurrent-claim race), verified against the actual
running n8n source per its own header comment. Not independently re-verified live by this task
(out of scope — Open WebUI was the assigned target); flag to whoever owns those services to
confirm they've been run against the live containers, the same way this task proved Open WebUI's
fix live.

**Fix:** added `OPENWEBUI_ADMIN_EMAIL` / `OPENWEBUI_ADMIN_NAME` / `OPENWEBUI_ADMIN_PASSWORD` to
`.env` and `.env.example` (also added `OPENWEBUI_ADMIN_PASSWORD` to `onboard.sh`'s
`INTERNAL_SECRETS` auto-gen list for fresh installs), and wrote
`scripts/init-open-webui-admin.sh` — idempotent, follows the `init-trilium.sh` idiom exactly:
checks `/api/config` for the `onboarding` key (note: Open WebUI only emits this key at all when
true — omitted, not `false`, once a user exists — the script's `is_onboarding()` handles that),
signs up the real admin from `.env` if the slot is still open, and if it's already claimed,
verifies (does not blindly trust) that the configured admin's credentials actually still log in
— exits non-zero with a loud warning if they don't, rather than silently reporting success in a
hostile-race scenario. No compose wiring (matches `init-trilium.sh`: a standalone operator/CI
step, not a compose entrypoint or sidecar — neither script is currently wired into
`onboard.sh`'s `bring_up()`, which is itself a small piece of debt, see below).

**Verified live (reproduced QA's exact repro, not just re-asserted config):**
- Before fix: `/api/config` → `"onboarding":true`.
- Ran `./scripts/init-open-webui-admin.sh` → real admin (`wafic@wazzan.us`) claimed, HTTP 200,
  role=admin confirmed.
- Re-ran the same script → correctly detected onboarding already closed, verified login instead
  of re-signing up (idempotent, confirmed by output not just code inspection).
- `/api/config` after fix → `onboarding` key gone entirely (0 → 1 users).
- **QA's exact exploit reproduced post-fix:** unauthenticated `POST /api/v1/auths/signup` with a
  new attacker email/password → `HTTP 403 {"detail":"You do not have permission to access this
  resource..."}`. Confirms `ENABLE_SIGNUP=false` now actually blocks new signups (it always did
  correctly block the 2nd+ user — the window was only ever the 1st).
- Real admin login (`POST /api/v1/auths/signin`) → `HTTP 200`, `role: admin`, valid token
  returned. Both the exploit-blocked and legitimate-admin-works halves proven in the same pass.

**Debt flagged:**
1. ~~`scripts/init-n8n-owner.sh` referenced but nonexistent~~ — RESOLVED during this same
   session by a concurrent worker (see corrected note above). Spot-checked live: `curl
   localhost:5678/rest/settings` → `showSetupOnFirstLoad:false`, i.e. n8n's owner slot is
   already claimed on this host. Not independently verified end-to-end by this task (login not
   re-tested) — a quick confirmation pass by whoever owns n8n is still worthwhile.
2. Neither `init-trilium.sh`, `init-n8n-owner.sh`, `init-dozzle-auth.sh`,
   `init-portainer-auth.sh`, nor the new `init-open-webui-admin.sh` is wired into
   `onboard.sh`'s `bring_up()` — all five are manual/CI steps an operator must remember to run.
   Interest: medium-high — a fresh `./scripts/onboard.sh` install is vulnerable to this exact
   bug class (unauthenticated first-visitor-becomes-admin) for every one of these 5 services
   until someone remembers to run the init script by hand; the failure mode is silent (stack
   looks fully healthy) and the exploit is a single unauthenticated HTTP call. This is now the
   single highest-value engineering task in the ledger: wire all five into `bring_up()` right
   after each service reports healthy, before the readiness-gate success screen — a ~1hr change
   that closes 5 already-built-but-unwired fixes at once.
3. AFFiNE's admin bootstrap remains genuinely unfixable non-interactively without either a real
   SMTP relay or an Engineering-built in-container CLI reusing AFFiNE's own
   `Models.user.create()+FeatureService.addAdmin()` (see 2026-07-13 finding above) — still open,
   not attempted here.

## 2026-07-16 — Installer: HOST_IP/GPU auto-detect, Ollama resource governance, disk pre-check
Closed 5 onboarding gaps QA's deep-validate sweep flagged from tonight's Postgres-drift +
disk-full incident, generically (no values tuned to this host's 16 vCPU/20GB/no-GPU specs —
verified by construction and by mocking a different fake NIC/GPU layout, see below).

**`setup.sh` (new helpers + 3 new steps):**
- `detect_host_ip()` (Step 2b): enumerates `ip -4 -o addr show`, excludes `lo`/`docker0`/`br-*`/
  `veth*` (container bridges, not the host's LAN address), falls back to `hostname -I` if `ip`
  is absent. One candidate → auto-select. Multiple → numbered interactive prompt, defaults to
  the first if `[[ ! -t 0 ]]` (non-interactive). Writes via new `set_env_var()` helper (updates
  or appends `VAR=VALUE` in `.env`, never logs anything that looks like a secret).
- `detect_gpu()` (Step 2c): `nvidia-smi -L` must actually report a `^GPU` line, not just the
  binary existing. Found + interactive → prompts Y/n; found + non-interactive → auto-enables;
  not found → CPU-only (unchanged default), never required. Sets `GPU_FLAG` which is now passed
  into every `docker compose ... pull`/`up` invocation in the script, so the opt-in overlay
  (`compose/ai-ml/ollama/ollama.gpu.yml`, pre-existing, was previously dead — nothing ever
  applied it) actually gets used when a GPU is present.
- `configure_ollama_resources()` (Step 3b): computes `OLLAMA_NUM_THREADS = max(1, nproc/2)`
  (reserve half the host's cores for Ollama, leave half for Postgres/Redis/n8n/LiteLLM/etc
  sharing the box — this was the exact starvation risk from tonight) and `OLLAMA_NUM_PARALLEL`
  (1, or 2 if `nproc>=8` — each parallel slot roughly multiplies the loaded model's memory
  footprint, so this stays conservative). Both written into `.env`. `OLLAMA_KEEP_ALIVE`
  defaulted to `30m` in `.env` if absent (was hardcoded `24h` in the compose file with zero
  override path).
- Step 9 (model pull) now actually reads `OLLAMA_DEFAULT_MODEL`/`OLLAMA_EMBED_MODEL`/
  `OLLAMA_CODE_MODEL`/`OLLAMA_VISION_MODEL` live from `.env` (blank/`#`-commented = skipped,
  matching this repo's existing convention) instead of a hardcoded 2-model array — the CODE/
  VISION vars were previously declared in `.env`/`.env.example` but silently never consumed.
- `check_disk_headroom()`: before the image pull (flat 10GB floor — exact per-image sizing isn't
  cheaply knowable without a network round-trip per manifest) and before the model pull (summed
  per-model estimate via `estimate_model_size_gb()`, ~0.6GB/billion params parsed from the tag,
  e.g. `qwen2.5-coder:32b`→~20GB, matching tonight's actual incident size). Interactive: prompts
  y/N to continue; non-interactive: warns and proceeds (never silently blocks a CI/scripted run).

**`compose/ai-ml/ollama/ollama.yml`:** `OLLAMA_KEEP_ALIVE`/`OLLAMA_NUM_PARALLEL`/
`OLLAMA_NUM_THREADS` are now `${VAR:-fallback}` (conservative fallbacks only apply if `.env`
is missing them entirely) instead of one hardcoded `OLLAMA_KEEP_ALIVE: 24h` with no override.

**`.env.example`:** added the three resource vars (documented placeholders — the real values
are host-computed by `setup.sh`, not fixed here). Downsized `OLLAMA_CODE_MODEL` default from
`qwen2.5-coder:32b` (~20GB) to `qwen2.5-coder:3b` (~2GB) — 32b isn't a safe default for an
unknown target machine. Commented out `OLLAMA_VISION_MODEL` by default (~4.7GB, opt-in for
vision-capable hardware). `HOST_IP` comment now explains setup.sh overwrites it.

**Verified, not just syntax-checked:** extracted the real function bodies from `setup.sh` (not
reimplementations) into a sandboxed harness and ran them against copies of the live `.env` in
`/tmp` — confirmed (a) single-NIC auto-detect on this host correctly resolves `10.10.10.27`,
overwriting a deliberately-wrong placeholder; (b) a mocked `ip` with 2 real NICs + docker0 +
br-abc123 + a veth correctly excludes all 3 bridges/veth and keeps only the 2 real candidates;
(c) non-interactive multi-candidate defaults to the first, interactive numbered-choice selecting
"2" correctly picks the second; (d) mocked `nvidia-smi -L` reporting a GPU correctly sets
`GPU_FLAG` (auto-enable non-interactive, Y/n prompt interactive, decline path also verified);
no-GPU (this host's real state) correctly stays CPU-only; (e) `configure_ollama_resources` on
this host's real 16 cores produces `OLLAMA_NUM_THREADS=8`, `OLLAMA_NUM_PARALLEL=2`; (f) the
`.env`-driven model-pull loop correctly includes 3 active vars and skips a `#`-commented vision
line; (g) `estimate_model_size_gb` sanity-checked against known tags (32b→20GB, 3b→2GB,
embed→1GB); (h) `check_disk_headroom` both under (warns, interactive-declines→skip, non-
interactive→warns-and-proceeds) and over threshold; reads whichever filesystem `.` actually
sits on (confirmed it read `/tmp`'s 10GB tmpfs when run there vs the repo's real 45GB root fs —
proof it's not hardcoded to one mount). Then ran the *actual* `setup.sh` functions (not the
sandboxed copies) against the real live `.env` in this repo (`< /dev/null`, single-NIC path, no
prompt needed) — confirmed idempotent, no unwanted side effects. `docker compose ... config`
confirms the ollama service resolves `OLLAMA_KEEP_ALIVE=30m`/`NUM_PARALLEL=2`/`NUM_THREADS=8`
from `.env`, and merging `-f ollama.gpu.yml` resolves a clean `deploy.resources.reservations`
block. `docker inspect aef2_ollama`'s actual running env now shows the new values live on this
host. `bash -n` + `shellcheck` clean (only pre-existing info-level notices, none in new code).

**Did NOT do (explicitly out of scope / left for later):** did not re-pull any Ollama models on
this host — mechanism-only fix, pulling is a separate, on-demand concern. Did not touch the
`CLAUDE.md`/`.claude/agents/*.md`/`pm/README.md` HOST_IP doc placeholders (already fixed
earlier this session per the task brief).

**Open gap for whoever next touches onboarding:** `scripts/onboard.sh` (the gum-TUI, actually
primary installer per the installer charter) still has NONE of this — no `HOST_IP` detection at
all; its own GPU detection (`HAS_GPU`, lines ~230-238) is dead exactly like the old
`ollama.gpu.yml` problem in `setup.sh` was (detected, never applied to the compose invocation);
its model pull (`ensure_local_model()`) only ever pulls `OLLAMA_DEFAULT_MODEL`, not CODE/VISION;
and it has no disk-headroom check at all. `setup.sh` was the explicit target of this task and is
now the reference implementation — porting the same mechanisms into `onboard.sh` is the natural
next step and shouldn't require re-deriving the logic, just re-wiring it into the gum/whiptail UI
layer.

## 2026-07-16 — n8n + Flowise: real bootstrap-auth scripts written (unclaimed owner/admin, both closed)
Deep-validate sweep found two live containers with unclaimed admin accounts — same risk class as
the Open WebUI fix (owned separately, not touched here).

**n8n (`aef2_n8n`, image `n8nio/n8n:latest`, n8n 2.30.5 at time of writing):** `.env`'s comment
promised `scripts/init-n8n-owner.sh` but the script didn't exist — `user` table had 1 shell row
(`role=global:owner`, email/password NULL), `/rest/settings` reported
`showSetupOnFirstLoad:true`. Wrote `scripts/init-n8n-owner.sh` (health-wait + idempotent-init
pattern from `scripts/init-trilium.sh`). Confirmed against the actual shipped source inside the
running container (`.../dist/controllers/owner.controller.js`,
`.../dist/services/ownership.service.js`) — `POST /rest/owner/setup` (skipAuth, body
`{email,firstName,lastName,password}`) is real and current; n8n itself throws "Instance owner
already setup" (400) on a second claim once `hasInstanceOwner()` is true, so the script's
idempotency check (`/rest/settings` → `showSetupOnFirstLoad:false`) matches n8n's own guard.
Reads `N8N_OWNER_EMAIL`/`_FIRST_NAME`/`_LAST_NAME`/`_PASSWORD` from `.env` (values unchanged,
comment already promised these — now true). Wired into `setup.sh`'s bring-up (Step 8b, runs only
when `automation` profile is active, after `up -d`, before Ollama model pull).
**Verified live, not just exit-0:** ran it against `aef2_n8n` — Postgres `user` row now shows
real `email`/`firstName`/`lastName`/`has_pw=t`/`roleSlug=global:owner`; `/rest/settings` flipped
to `showSetupOnFirstLoad:false`; re-run is a clean no-op (`already claimed`).

**Flowise (`aef2_flowise`, image `flowiseai/flowise:latest`, confirmed v3.1.2):**
`FLOWISE_USERNAME`/`FLOWISE_PASSWORD` container env vars are dead in this version — v3.x replaced
env-based basic auth with a workspace/organization multi-tenant model; grepped the shipped
`dist/` and found zero references to either var name. `user` table had 0 rows, login 401.
Real bootstrap (confirmed via `dist/enterprise/services/account.service.js`,
`dist/routes/index.js`, `dist/utils/constants.js` inside the running container, not docs):
`POST /api/v1/account/register` (whitelisted, no auth) body `{"user":{"name","email",
"credential"}}` — on a fresh DB with no organization row, this one call creates the
org + default workspace + an ACTIVE owner user (no email verification needed on the
`OPEN_SOURCE` platform tier this image runs as — no license key configured). A second call
fails 400 "You can only have one organization" (`ensureOneOrganizationOnly`). Real login is
`POST /api/v1/auth/login` (passport-local, flat `{email,password}` body) — NOT
`/api/v1/account/login`, which sits behind the API-key gate (`WHITELIST_URLS` in
`dist/utils/constants.js`) and 401s even with correct credentials; this cost real debugging time,
worth remembering if this ever needs re-touching.
Added `FLOWISE_ADMIN_EMAIL` to `.env` (new — v3.x logs in by email, not username; kept
`FLOWISE_USERNAME` as the bootstrapped user's display "name" only). Removed
`FLOWISE_USERNAME`/`FLOWISE_PASSWORD` from `compose/ai-ml/flowise/flowise.yml`'s container
`environment:` block (dead — app never reads them; left them there would keep implying they
work). Wrote `scripts/init-flowise-admin.sh` (same health-wait + idempotent-init idiom): tries
login first (no-op if it already works), else registers, else — if an org already exists AND the
target credentials still don't authenticate — fails loudly with manual-recovery instructions
(`flowise user --email --password` CLI reset) rather than silently leaving mismatched creds.
Wired into `setup.sh` Step 8b right after the n8n call (same `automation`-profile gate).
**Verified live:** registered via the script, DB shows real `user`/`organization` rows
(`status=active`), `POST /api/v1/auth/login` with the `.env` credentials returns 200 with
`isOrganizationAdmin:true` and a real JWT; re-run of the script is a clean no-op
("credentials already work").

**Non-blocking upstream quirk (flagged, not fixed):** Flowise logs show 2 component-load errors
at boot — `ReActAgentChat`/`ReActAgentLLM` fail with `ERR_PACKAGE_PATH_NOT_EXPORTED` on
`@langchain/core/utils/uuid`. Root cause confirmed by inspecting the image's own `node_modules`:
`flowise-components` bundles `@langchain/core@1.1.20` (no `./utils/uuid` export), but a nested
`langchain/node_modules/@langchain/langgraph-checkpoint@1.1.3` requires
`@langchain/core@^1.1.48` and calls that subpath — a version-skew bug inside Flowise's own
published dependency tree, not anything in this repo's config/env/network. Only affects the
legacy ReAct Agent node type (AgentFlow v2 supersedes it); every other node type loads clean, and
these 2 failures don't crash the server or block startup. Not worth patching around (would mean
hand-patching node_modules inside a pulled image, reverts on every re-pull) — leave for upstream.

**Files touched:** `scripts/init-n8n-owner.sh` (new), `scripts/init-flowise-admin.sh` (new),
`compose/ai-ml/flowise/flowise.yml` (dropped dead env vars, added explanatory comment),
`.env` (added `FLOWISE_ADMIN_EMAIL`; n8n's existing comment/vars were already correct — verified,
not touched), `setup.sh` (Step 8b: both scripts wired into the `automation`-profile bring-up,
alongside a concurrent session's TriliumNext wiring in the same block).
