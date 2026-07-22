# Contributing to Enclave

Thanks for wanting to help. Enclave's one promise is mechanical: **an agent cannot
mark work "done" without recorded proof.** Contributions are held to the same bar —
we ask for evidence, not assurances.

## Ground rules

- Be excellent to each other — see [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
- Enclave is **local-first and sovereign**. Don't add a hard dependency on a paid
  cloud API or a phone-home. The stack must still run fully offline (air-gap mode).
- Don't weaken the evidence gate. The Registrar refusing a `done` without proof is
  the product; changes that let work close without evidence will not be merged.

## Getting started

```bash
git clone https://github.com/alwazw/enclave
cd enclave
cp .env.example .env         # generate/fill secrets (see setup.sh)
docker compose -f local-stack.yml --profile core up -d
```

The `core` profile is the launch spine (governance + data + LLM infra). Everything
else is an opt-in profile — see [docs/OPERATIONS.md](docs/OPERATIONS.md).

## Adding a service

New services must follow the enforced compose pattern:

1. Fork and branch: `git checkout -b feat/my-service`.
2. Every value comes via `${VAR}` — **no hardcoded ports, passwords, or paths.**
3. Reference the external network/volume namespace (not inline definitions).
4. Add `homepage.*` labels for dashboard auto-discovery.
5. Give dependents a healthcheck with `condition: service_healthy`.
6. Assign the correct `profiles:` for the service category.
7. If it touches the Docker socket, route it through the **socket-proxy** — never
   mount `/var/run/docker.sock` directly.
8. Add a dashboard tile in `config/homepage/services.yaml`.

## Adding a Hermes skill

New agent skills live in `agents/hermes/skills/<name>/SKILL.md`. Keep the trigger
description tight so the router picks it only when it should.

## Opening a pull request

- One logical change per PR; describe what it adds and which profile it belongs to.
- **Bring evidence.** For code, a passing test line; for a service, the health
  output and a reachable-endpoint check; for a UI, a rendered screenshot. "It runs
  on my machine" is not evidence — show the proof, the way the Registrar would ask
  for it.
- Run whatever tests exist for the area you touched (e.g. `registrar/` has
  `pytest tests/`) and paste the result.
- Secrets never land in git. `gitleaks` and a personal-identifier denylist run
  before publishing; keep real values in your gitignored `.env`.

## Reporting security issues

Please **do not** open a public issue for a vulnerability. See
[SECURITY.md](SECURITY.md) if present, or contact the maintainers privately via
GitHub's report feature. Disclosure lands after the fix, not before.
