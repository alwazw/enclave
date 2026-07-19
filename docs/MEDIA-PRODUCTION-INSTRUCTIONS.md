# Media Production Instructions

Everything in this document is a **draft for the Chairman to review, film, and post** —
nothing here publishes itself, and no demo footage has been recorded by any agent
session. This doc exists to hand off cleanly: what's ready, what needs a human, and in
what order.

## What's provided (drafted, not published)

| Asset | File | Status |
|---|---|---|
| Comparison table | `docs/COMPARISON.md` | Existing, verified against current repo state |
| Architecture diagram | `docs/enclave-architecture.svg` | Existing |
| Governance / threat model | `docs/GOVERNANCE.md` | Existing |
| 45–60s demo shot script | `docs/DEMO-SHOT-SCRIPT.md` | New — maps to the real, re-verified `T-0004` evidence-gate flow |
| LinkedIn post draft | `docs/SOCIAL-POST-DRAFTS.md` | New |
| Show HN post draft | `docs/SOCIAL-POST-DRAFTS.md` | New |

## What needs a human (in order)

1. **Read the shot script** (`docs/DEMO-SHOT-SCRIPT.md`) and decide: film a fresh
   re-run (recommended — see "Honesty constraints" in that doc) or narrate the
   already-existing `T-0004` evidence on the live board. Either is honest; a fresh
   re-run is more convincing on camera because the refusal (shot 3) happens live.
2. **Record the demo.** No agent session can do this — it requires a human at the
   keyboard/camera, or at minimum a human confirming the recording matches reality
   before it's used anywhere public.
3. **Host the demo** (wherever the Chairman prefers — repo README embed, YouTube,
   LinkedIn native video, etc) and get a real URL.
4. **Fill in the placeholders** in `docs/SOCIAL-POST-DRAFTS.md` (`[repo link]`,
   `[45s demo]`) with real URLs. Do not post with placeholders live.
5. **Re-verify every concrete claim in the drafts** against the live stack immediately
   before posting — this repo moves fast (see `REMEDIATION_LOG.md` for how much
   changed in the last remediation round alone). A stale claim in a public post is
   worse than no post.
6. **Post**, per whatever platform-specific judgment applies (LinkedIn tone, HN
   norms around self-promotion and front-loading limitations, timing, etc.) — this is
   explicitly the Chairman's call, not something to automate.

## Why this is split this way

Per this project's own standing rule: no agent session fabricates a demo, records
video, or posts publicly. The line is drawn at "drafts + accurate source material,
handed to a human for the parts that require a human." Everything above the line
(script grounded in real re-verified evidence, copy grounded in real verified claims,
existing docs cross-checked) is done; everything below the line (recording, hosting,
posting) is deliberately left to whoever's actually going to be on camera and hit
"post."
