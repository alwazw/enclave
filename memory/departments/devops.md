# Head of DevOps — Department Memory

> Read this at the start of every devops invocation. Keep the **port registry** current
> religiously. Never write secret values here. `.env` (repo root) is gitignored (`**/*.env`).

Last updated: 2026-07-22 (in-sandbox core bring-up, T-0009).

---

## Jurisdiction & hard rules
- Single project: `~/enclave` (this repo). **Nothing on the Chairman's host `$HOST_IP`** — that is
  his machine (pfsense also at `$HOST_IP`; pfsense changes need Chairman confirmation).
- Compose-first. Every service: pinned tag, healthcheck, restart policy, named volume, port-registry
  entry BEFORE it starts.
- Shared-infra changes (proxy/DNS/firewall/docker network): state blast radius + rollback first.

## Port registry (host ports — core profile)
| Port(s) | Service | Container→ | Profile | Notes |
|---|---|---|---|---|
| 8090 | registrar | 8090 | core | evidence gate API; `/health`, `/board`, `/docs`, `/tasks` |
| 8091 | ux-validate | 8091 | core | Playwright screenshot gate; `/validate`, `/health` |
| 5432 | postgres | 5432 | core | init creates DBs: n8n,affine,flowise,langfuse,mem0,litellm |
| 6379 | redis | 6379 | core | requirepass; noeviction |
| 8000 | surrealdb | 8000 | core | rocksdb |
| 6333/6334 | qdrant | 6333/6334 | core | http/grpc |
| 8081 | searxng | 8080 | core | host 8081→ctr 8080 |
| 3300 | langfuse | 3000 | core | v2; needs postgres `langfuse` DB |
| 4000 | litellm | 4000 | core | LLM gateway; config `config/litellm/config.yml` |
| 11434 | ollama | 11434 | core | local LLM floor (image 8GB) |
| (none) | hermes | 8642 | core | NOT published to host; internal agent runtime only |
| 3701-3705 | mcp-filesystem/memory/fetch*/github/postgres | 8000 | core/tools | *fetch=tools profile |
| 3030 | homepage | 3000 | core | ghcr — blocked in sandbox |
| 3000 | open-webui | 8080 | core | ghcr — blocked in sandbox |
| 8080 | mcpo | 8000 | core | ghcr — blocked in sandbox |
| 8642 | hermes (ceo profile: ceo) | — | ceo | ceo.yml is profile [ceo], NOT core |

## External nets / volumes (must exist before compose `up`)
- Networks (bridge): `aef2_frontend`, `aef2_backend`, `aef2_database` (name = `${COMPOSE_PROJECT_NAME:-aef2}_*`).
- Named volumes (external:true in sub-files): `registrar_board`, `postgres_data`, `redis_data`,
  `surrealdb_data`, `qdrant_data`, `langfuse_data`, `litellm_data`, `hermes_data`, `ollama_data`,
  `mcp_workspace`, `mcp_memory_data`. Create with `docker volume create <name>` (setup.sh also does this).
- `registrar_board` is SHARED by registrar + ux-validate (screenshots land in `/board/artifacts/<tid>/`).

## Service inventory / dependency notes
- Governance spine = **registrar** (evidence gate) + **ux-validate** (screenshot gate). No LLM required
  for the gates to fire. Both healthy and mutually reachable via `registrar:8090`.
- `hermes` hard-depends (service_healthy) on **litellm + qdrant + surrealdb** — litellm being reachable
  is a prerequisite for hermes to start.
- `litellm` model `openai/morpheus-main-model` → gemini/deepseek (need keys); floor
  `openai/morpheus-local-fallback` → `ollama/dolphin3`,`ollama/deepseek-r1:8b` @ `http://ollama:11434`
  (2nd-to-last in fallback chain). Needs an ollama model pulled to actually serve.

## Known host / sandbox quirks (HARD-WON)
- **dockerd is reclaimed on idle.** If `docker ps` fails: `nohup dockerd >/tmp/dockerd.log 2>&1 &`, wait.
- **Registry mirror** `mirror.gcr.io` in `/etc/docker/daemon.json` serves **Docker Hub** images
  (library + vendor) through the proxy. Plain `docker pull redis:7-alpine` etc. work.
- **Proxy** = HTTPS-CONNECT-only, `$HTTPS_PROXY` (port is DYNAMIC — was 34839 this session, not a fixed
  40629). CA bundle for the MITM: `/root/.ccr/ca-bundle.crt`. `pypi.org`/`files.pythonhosted.org` are
  in `no_proxy` but STILL transparently TLS-intercepted → tools must trust the CA (pip `--cert`, npm
  `NODE_EXTRA_CA_CERTS`, ollama `SSL_CERT_FILE`).
- **Egress allowlist blocks (403 at gateway — report, don't route around):**
  `deb.debian.org:443`, `registry.ollama.ai`, ghcr blob host `pkg-containers.githubusercontent.com`.
  Confirm/inspect with `curl -sS "$HTTPS_PROXY/__agentproxy/status"`.
- **apt-in-build is NOT viable** (deb.debian.org 403). Workaround for the python-slim custom images
  (registrar, ux-validate, ceo): build `FROM python:3.12` **full** (buildpack-deps: git 2.47 + curl 8.14
  already bundled, no apt) and `pip install --cert /path/ca-bundle.crt` (copy CA into build context),
  build `--network host`. ux-validate base `mcr.microsoft.com/playwright/python:v1.47.0-jammy` DOES pull.
  Keep sandbox Dockerfiles in a throwaway build context — do NOT commit them.
- **ghcr images**: litellm is effectively UNBLOCKED (`litellm/litellm:main-stable` on Docker Hub is the
  same digest as the ghcr image; ghcr ref then resolves from cached layers). open-webui/mcpo/homepage
  are ghcr-only and blocked (no `openwebui/open-webui` on Docker Hub).
- **mcp-servers** (`node:22-alpine`, runtime `npm i -g`) fail with `SELF_SIGNED_CERT_IN_CHAIN` — no CA
  in the image. Fix = mount CA + `NODE_EXTRA_CA_CERTS` (compose change; flagged, not applied).
- **searxng** crash-loops on `granian` with `Address family not supported (os error 97)` — sandbox has
  **no IPv6**. Fix = env `GRANIAN_HOST=0.0.0.0` (applied via a throwaway compose override this session;
  candidate real fix = add `GRANIAN_HOST=0.0.0.0` to searxng.yml env — helps any no-IPv6 host).

## Backup state
- None taken this session. Reminder: a backup task is only done when a RESTORE is proven (deep-validate
  data context) — a dump file existing proves nothing. `registrar_board` (the audit-trail git repo) is
  the highest-value volume to back up first.

## Resource headroom (2026-07-22)
- Disk `/`: 74% used, ~9.8 GB free — **approaching the 80% flag line**. Docker images 21 GB total,
  ~19.6 GB reclaimable (`docker system prune` / the 8 GB ollama image is the bulk). Mem: 13.6 GB
  available of 16 GB. Load 0.44 on 4 CPU. Watch disk before pulling more large images.

## Dated updates
- **2026-07-22 (T-0009, in-sandbox core bring-up):** Built `enclave/registrar:latest` +
  `enclave/ux-validate:latest` via full-python / MCR + pip-CA workaround. Brought up 11/18 core services
  healthy. Proved: containerized Registrar 409 (docker run), gate on running compose stack (409), and ux
  screenshot gate end-to-end (real PNGs on `registrar_board`). Blocked & flagged: mcp-servers (npm CA),
  ghcr open-webui/mcpo/homepage, LLM floor (registry.ollama.ai 403; no external keys). Proposed repo
  fixes (NOT committed): (1) searxng `GRANIAN_HOST=0.0.0.0`; (2) mcp-servers CA-mount +
  `NODE_EXTRA_CA_CERTS`; (3) optional build-arg CA hook in registrar/ux-validate Dockerfiles for
  proxy-MITM environments. Left T-0009 in `validating` for QA.
