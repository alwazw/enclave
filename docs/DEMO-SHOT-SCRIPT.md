# Demo Shot Script (45–60s)

This maps 1:1 to a real, reproducible sequence already verified live on this stack —
task `T-0004` on the `demo-widgets` board. Nothing here is staged copy; every screen
shown is either a real terminal session or the real Registrar board. Re-run the
sequence yourself before filming (see "Re-running this demo" below) so the recording
matches what's actually on screen, not a description of what once happened.

## The thesis in one shot

**An agent claims work is done. The system refuses it. The agent does the real work.
The system proves it and only then lets it close.** That's the whole pitch — everything
else in the stack exists to make this refusal real instead of decorative.

## Shot list

| # | Time | Shot | What's on screen | Why it matters |
|---|------|------|-------------------|-----------------|
| 1 | 0–5s | Title card | "Enclave — agents that can't lie about done." + architecture SVG | Sets the one-line thesis before any UI |
| 2 | 5–12s | Terminal: talk to Hermes | `hermes -z "build me a widget catalog landing page"` — Hermes incorporates a project, spawns a governed CEO | Shows natural-language intent → a real, bounded agent gets created, not a pre-wired demo button |
| 3 | 12–20s | Terminal / board: the refusal | The CEO (or a lazy first attempt) tries to mark the task `done` with no evidence. Registrar responds `409 {"refused": true, "reason": "REFUSED: ..."}`. Board stays on `doing`. | **The money shot.** Proves the gate is a real enforced service, not a convention an agent can talk its way past |
| 4 | 20–35s | Terminal: the real work | The CEO graph (`ceo/graph.py`, LangGraph supervisor) actually builds the page via LiteLLM, a real `index.html` gets written, nginx serves it | Shows the agent doing genuine work in response to the refusal, not just retrying the same claim |
| 5 | 35–48s | ux-validate + board | `ux-validate` renders the real page at mobile + desktop viewports, captures two real screenshots, attaches them as evidence. Board transitions `doing → done`, thumbnails appear. | Proves the evidence is a real artifact tied to a real render, not a text claim |
| 6 | 48–58s | Board close-up | Pan across the task card: status `done`, work log timestamps, two screenshot thumbnails, `done_at` timestamp | Leaves the viewer with the proof artifact on screen, not a narrated claim |
| 7 | 58–60s | End card | Repo URL + one line: "Local-first. No per-token cloud required. MIT licensed." | Call to action |

## Re-running this demo

The exact task this script maps to already exists and is inspectable right now:

```bash
# From inside the registrar's network (or via the clean-room rig if using one):
curl -s -H "X-Company: demo-widgets" http://registrar:8090/tasks/T-0004
```

To re-run it end to end from scratch (recommended before filming, so the capture is
live and not a replay):

1. Bring up a fresh clean-room instance (a disposable docker-in-docker rig or a scratch
   clone) so the "first attempt refused" moment is real, not a scripted re-trigger of
   an already-done task.
2. Send Hermes the natural-language request shown in shot 2.
3. Let the CEO's first `done` attempt fail against the Registrar (shot 3) — do not
   pre-seed evidence.
4. Let it complete the real build → validate → close cycle (shots 4–6) and capture
   each step as it actually happens.

## Honesty constraints for whoever films this

- Do not cut the refusal (shot 3). It is the entire point; skipping it turns this into
  a generic "agent builds a webpage" demo, which is not what's being sold.
- Do not use a pre-recorded/cached screenshot for shot 6 — pull it live from the
  board's actual artifact path so what's shown is the real file, not a mockup.
- If a re-run behaves differently than described here (e.g. the refusal doesn't
  trigger, or evidence attaches without a real render), stop and fix the underlying
  behavior before filming — do not edit around a broken take.
