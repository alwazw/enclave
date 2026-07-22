# Show HN kit — Enclave

> **Status: DRAFT for the Chairman to fire.** The CEO drafts; the human posts.
> Do not auto-publish. Post from a real account, be present in the thread for the
> first few hours, and answer skeptics with the reproducible `409`, not adjectives.

## Title (pick one)

1. **Show HN: Enclave – local AI agents that can't mark their own work "done" without proof**
2. Show HN: An evidence gate that makes AI agents prove completion (self-hostable)
3. Show HN: Enclave – I caught an agent claiming "done" with zero work, so I built the referee

_Recommendation: #1 — concrete, states the mechanism, signals local/self-hostable._

## First comment (the framing — lead with the failure, not the feature)

> I kept watching coding agents announce "✅ completed" for work they hadn't done.
> During development of this one, an agent literally reported `completed ✅` having
> made **zero** API calls — and the board stayed on `doing`, because the thing that
> marks work done isn't the agent. It's a separate service (the Registrar) that
> returns `409 {"refused": true}` on a `done` transition unless real evidence is
> recorded — a passing test line, or an actual rendered screenshot produced by a
> separate service. It sits behind an HTTP API, below anything the agent can
> prompt-engineer.
>
> Three controls, all mechanical: **provable completion** (the evidence gate),
> **jurisdiction** (each agent is scoped to exactly one project via an `X-Company`
> header — it can't see or touch another's tasks), and an **audit trail** (every
> board change is a git commit).
>
> It's local-first: 32-service Docker stack, air-gappable (no cloud `model_name`
> at all in air-gap mode), and the LLM path degrades through free tiers down to a
> local CPU floor — no per-token cloud required. MIT licensed.
>
> Reproduce the refusal yourself from the repo root in one command: `make demo`.
>
> I want to be honest about what it does **not** do — it proves evidence *exists
> and is real*, not that it's *meaningful*; it governs agents, not a malicious
> operator. Full threat model and limitations here:
> [docs/GOVERNANCE.md](../GOVERNANCE.md) (read the "What this does NOT defend
> against" section — it's the honest part).
>
> Repo: https://github.com/alwazw/enclave. Happy to answer anything.

## What to link

- The repo root (README leads with the refusal proof + demo).
- `docs/GOVERNANCE.md` — the three controls **and** the honest-limitations section.
- `docs/COMPARISON.md` — vs MetaGPT / CrewAI / LangGraph / Paperclip.
- The demo GIF / the one-command `409` trigger (W3).

## Do / don't

- **Do** lead with the agent *failing* the gate. The refusal is the wedge; a demo
  of an agent succeeding is a generic "agent builds a webpage" post.
- **Do** link the limitations yourself — HN rewards candor and punishes overclaiming.
- **Don't** call it "autonomous," "AGI," or "fully secure." It's a referee, and
  that framing is stronger and defensible.
- **Don't** post until the one-command demo actually emits a real `409` on a fresh
  clone (D4 — launch blocker).

## Pre-flight checklist (before firing)

- [ ] README is governance-first and Enclave-branded; refusal proof + demo GIF at top.
- [ ] One-command demo emits a real `409` on a clean checkout.
- [ ] No raw docker socket exposed (socket-proxy in place).
- [ ] Limitations section is current and honest.
- [ ] Repo is public and the links above resolve.
