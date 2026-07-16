# Remediation Log

One line per closed issue: ISO-time, issue, verdict, commit, evidence.

- 2026-07-16T00:00:00Z | #1 | PASS | enclave@2ef605d (local-stack@54c6bdc first) | `docker compose pull` with full default profile set: before → aborts on "openinterpreter/open-interpreter ... repository does not exist"; after → open-interpreter absent from pull set, abort now only from separate pre-existing mem0 platform issue (not a regression).
- 2026-07-16T00:10:00Z | #3 | PASS | enclave@c1c512e (local-stack@0f0ea25 first) | Live aef2 stack: dozzle+portainer brought up fresh, both transitioned starting → healthy (dozzle via native `/dozzle healthcheck`, portainer via 2.43.0-alpine's wget).
- 2026-07-16T00:10:00Z | #4 | PASS | enclave@c1c512e (local-stack@0f0ea25 first) | Real credential path, not liveness: Portainer POST /api/auth with generated admin password → HTTP 200 + JWT; wrong password → HTTP 422. Dozzle unauthenticated GET / → HTTP 307 to /login (previously unauthenticated with docker.sock mounted).
