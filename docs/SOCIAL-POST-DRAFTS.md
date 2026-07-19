# Social Post Drafts — LinkedIn + Show HN

Drafts only. The Chairman reviews, edits to taste, and posts — nothing here gets
published automatically. Every claim below is grounded in something verified live on
this stack this session or the launch-gate session before it (see `REMEDIATION_LOG.md`
and `docs/DEMO-SHOT-SCRIPT.md`); nothing is aspirational or rounded up. If a number or
claim needs updating before posting, update it here first, don't just paste and go.

---

## LinkedIn

**Draft — first-person, builder voice:**

> I spent the last few weeks building something I kept wanting to exist: an AI agent
> system where "done" actually means done.
>
> Every agent framework I'd used had the same failure mode — an agent says it finished
> a task, and you have to just... trust it. No enforcement, no proof, just a claim in a
> chat window.
>
> So I built Enclave: a self-hosted, local-first stack where a separate governance
> service (the Registrar) refuses to let any agent mark work "done" without recorded
> evidence — a passing check, or for UI work, an actual rendered screenshot. Not a
> convention the agent can talk its way around. A hard `409 refused` if the proof isn't
> there.
>
> It runs entirely on your own hardware — genuinely air-gappable, no per-token cloud
> required, no GPU required by default (there's a real local-inference floor, and an
> explicit air-gap toggle that proves zero cloud calls with cloud keys unset). You talk
> to a gateway agent (Hermes) in plain language; it spins up a bounded, project-scoped
> CEO agent that can't reach any other project's data even if it tried — the tool
> allow-list doesn't include a path there.
>
> The whole thing is MIT-licensed and open. If you've ever watched an agent claim
> victory on a broken build, I think you'll like where this goes.
>
> [repo link] · [45s demo]

**Alt hook (shorter, lead with the refusal):**

> An agent tried to mark a task "done." My system said no.
>
> That's not a bug — it's the whole point of what I've been building: [continue with
> the same body as above from "So I built Enclave..."]

---

## Show HN

**Draft title:**

> Show HN: Enclave – self-hosted AI agents that can't fake "done" (evidence-gated, local-first)

**Draft body:**

> Enclave is a self-hosted stack for running governed AI agents. The core idea: a
> separate service (the Registrar) enforces that no agent can transition a task to
> "done" without recorded evidence — for UI work specifically, a real screenshot of a
> real render, not a text claim. Try to close without it and you get a hard
> `409 {"refused": true}`, not a soft warning.
>
> Three things make it different from the agent-framework space (CrewAI, MetaGPT,
> LangGraph, etc — candid comparison in the repo, including where they're better):
>
> 1. **Provable completion** — the evidence gate is an enforced service boundary, not a
>    prompt convention any agent can be talked past.
> 2. **Jurisdiction** — every deployed agent is scoped to exactly one project (its own
>    network, volumes, board, repo). There's no tool path to another project's data,
>    not just a policy saying not to look.
> 3. **Sovereignty** — runs on your own hardware. No GPU required by default (a local
>    CPU-inference floor + free-tier cloud fallback chain when available), and there's
>    an explicit air-gap toggle verified to make zero outbound cloud calls with every
>    cloud API key unset.
>
> Substrate is a ~30-service Docker Compose stack (LiteLLM gateway, an agent runtime,
> Postgres/Redis/Qdrant, n8n, Open WebUI, observability via Langfuse, etc) — the
> governance model is the point, the stack is just what it's built on top of.
>
> MIT licensed. Feedback especially welcome on the jurisdiction/evidence-gate design —
> I've tried to be honest in the docs about what it doesn't solve (a compromised
> container's screenshots are only as trustworthy as that container; the gate proves a
> check *ran*, not that it was meaningful) rather than oversell it.
>
> [repo link]

---

## Notes for whoever posts these

- Fill in `[repo link]` and `[45s demo]` once the demo (see `docs/DEMO-SHOT-SCRIPT.md`)
  is actually filmed and hosted — do not post with a placeholder link live.
- The Show HN body deliberately front-loads a limitation (the compromised-container
  caveat) — HN readers reward this; don't cut it to sound more impressive.
- Re-verify every concrete claim above (air-gap toggle, evidence gate, jurisdiction)
  against the live stack immediately before posting if any time has passed — this repo
  moves fast and a stale claim is worse than no post.
