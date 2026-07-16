# QA Department Memory

## 2026-07-15 — Full 30-container deep-validate sweep (post-recovery audit)

Ran the deep-validate "context: docker" checklist against all 30 running containers
(15 spot-checked as previously-verified, 16 first-time deep verification) plus confirmed
mem0 is correctly not running. Full evidence in that day's QA report to the CEO/Chairman.

### New checklist items added to my repertoire (apply every future sweep)

1. **Host-IP doc/reality check.** Before trusting any `10.0.0.10` reference in
   CLAUDE.md/skills/agent docs, verify it's actually reachable (`ping`/`curl`) from the
   validating host. On this box it is NOT — `HOST_IP` in the live `.env` is `10.10.10.27`;
   `10.0.0.10` is a stale placeholder that only survives in `.env.bcp`/`.env.example`/docs.
   Always read `.env`'s live `HOST_IP` first and test against that, not the doc default.
   Flag the mismatch as a docs bug every time it recurs — don't silently work around it
   without reporting.

2. **"Healthy" self-hosted apps can have an unclaimed admin account.** `docker ps healthy`
   + a 200 on `/` tells you NOTHING about whether a real user can log in. For every
   self-hosted app with its own user/auth system (n8n, Flowise, Trilium, Open WebUI,
   AFFiNE, ...), explicitly check: does an admin/owner user row exist in its DB, or does
   its settings/config endpoint say setup/onboarding is still pending
   (`showSetupOnFirstLoad`, `onboarding:true`, `isInitialized:false`, empty `user` table)?
   Found FOUR services in this exact unclaimed state simultaneously this session: n8n
   (owner-bootstrap script referenced in `.env` comments does not exist in `scripts/`),
   Flowise (v3.1.2 switched to workspace/org multi-tenant auth; legacy
   FLOWISE_USERNAME/PASSWORD env vars are not consumed by that auth path — 0 rows in
   `user` table), Trilium (a real idempotent fix script `scripts/init-trilium.sh` exists
   but was never run against the live container), and Open WebUI (`onboarding:true` even
   with `ENABLE_SIGNUP=false` — first `/api/v1/auths/signup` call still succeeds and
   grants admin; verified by creating then immediately deleting a throwaway test account).
   **Never mark a self-hosted-auth service PASS on health+200 alone — always probe the
   auth/setup state.**

3. **LLM gateway "PASS" must be tested per fallback tier, not just the default alias.**
   LiteLLM's headline model (`openai/morpheus-main-model`) can round-trip a real chat
   completion successfully while a *different* declared tier (here: Tier 6
   `openai/morpheus-local-fallback`, and the dedicated `openai/morpheus-embedding-model`)
   is completely broken because its upstream (Ollama) has zero models pulled
   (`ollama list` empty, `/root/.ollama/models` is 12K/empty). Root cause: `setup.sh` only
   auto-pulls `OLLAMA_DEFAULT_MODEL`, not the embed/code/vision models also declared in
   `.env`, and even that step appears not to have completed this session (consistent with
   the disk-full recovery). Always hit every declared model_name/tier through
   `/v1/chat/completions` (and `/v1/embeddings` for embedding aliases) with a real request,
   not just the one alias a human is likely to reach for.

4. **Homepage `container:` labels can silently drift from real container names.**
   `config/homepage/services.yaml` has `container: aef2_open-webui` (hyphen) while the
   actual running container is `aef2_open_webui` (underscore) — a static-analysis-catchable
   bug that breaks that card's Docker-stats widget with no visible error. Diff
   `grep container: services.yaml` against `docker ps --format '{{.Names}}'` every sweep.

5. **Distroless/minimal images often lack `sh`/`wget`/`curl`.** SurrealDB, Qdrant, and
   others have no shell utils in-container — in-container dependency checks against them
   must run from a peer container (e.g. Hermes, which has `curl`) or from the host, not
   `docker exec <target> sh -c ...`. Check `which curl python3 node` before assuming a
   check will work.

6. **Known/already-documented limitations are not new escapes — but still block "PASS".**
   AFFiNE's no-SMTP admin bootstrap and ChromaDB's dropped OSS auth are both pre-existing,
   already-documented-in-compose findings from 2026-07-13 — re-confirmed this sweep, not
   newly discovered. Report these as "known limitation, re-verified" not "FAIL" in the
   escape-analysis sense, but they still fail the "functional for a real user" bar and
   should stay tracked as open work.

### Flaky / noisy-but-benign signals (don't false-positive on these)
- Weaviate logs continuously warn `failed to join cluster` (single-node instance has
  `CLUSTER_HOSTNAME=node1` set with no real peers) — cosmetic Raft-bootstrap noise;
  RestartCount stayed 0 and a real schema write/read/delete round-trip passed. Should
  still get cleaned up (single-node config flag) to stop the log spam, but is not a
  functional failure.
- CloudBeaver logs one `Driver 'yandex_clickhouse' is missing library` ERROR at
  boot — an optional, unused JDBC driver failing to register; core GraphQL API and
  TCP reachability to postgres both work.
- Portainer has no Docker healthcheck by design (documented: no in-image binary can run
  one) — verify via external HTTPS/HTTP curl instead of `docker inspect .State.Health`.

### Escape analysis actions taken this session
- Created, then immediately deleted, a throwaway Open WebUI admin account
  (`qa@test.local`) used only to prove/disprove the signup-bypasses-ENABLE_SIGNUP=false
  finding; verified user count returned to 0 and `onboarding` reverted to `true`
  afterward. Documented in the report rather than silently fixed, since claiming the
  account is a security decision for the Chairman/devops, not QA.
