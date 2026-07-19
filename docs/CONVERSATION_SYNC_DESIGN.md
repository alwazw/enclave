# Conversation Sync Design (#31)

Chairman's requirement: "conversation flow must sync live across all
communication channels." This document is the concrete design for the part
that isn't implemented yet — see the bottom for what's already shipped.

## What's already real (not part of this design — already merged)

- `agents/hermes/openai-shim.py` gives Open WebUI a working chat path to
  Hermes itself (previously dead — see #31's original report and the
  remediation log entry tagged `#31 Path A`).
- By default (`HERMES_SHIM_SESSION_MODE=unified`), every Open WebUI request
  continues one fixed Hermes session (`HERMES_SHIM_UNIFIED_SESSION`, default
  `chairman-primary`) — verified live: telling it a fact in one simulated
  Open WebUI chat and recalling it from a different one works. This is
  correct for this stack because it is single-operator
  (`GATEWAY_ALLOW_ALL_USERS: true`, one `TELEGRAM_ALLOWED_USERS` id) — there
  is really only one end user, so "share memory across every Open WebUI tab"
  is already the right default, no per-user mapping needed.

## What's still open: Telegram ↔ Open WebUI

The remaining gap is narrower than #31's original framing suggested, because
the single-operator fact above removes the hard part (multi-user identity
mapping). What's left is purely: **does Hermes's Telegram platform adapter
use a session name/identifier we can align with `chairman-primary`?**

This is genuinely unknown and can't be resolved on paper — `hermes-agent` is
a closed/bundled distribution (confirmed in #27: no grep-able Python source
tree for `hermes_plugins.telegram_platform.adapter` inside the container),
and empirical testing requires Telegram to actually connect, which #27
currently blocks (external `getUpdates` conflict, cross-VM, not fixable from
this host — see the #27 remediation log entry). **This design is blocked on
#27, not on missing design work.**

### Step 1 (once #27 clears): observe the real session name

```bash
# Send yourself one Telegram message, then:
docker exec hermes sh -c 'HOME=/opt/data hermes sessions list' | head -5
```
Compare the newest session's ID/title against what a fresh `--continue
chairman-primary` call produces. Three possible outcomes:

**Outcome A — predictable/derivable name** (e.g. `telegram-<chat_id>`, or the
adapter honors a `--continue`/session-name config key per platform): point it
at `chairman-primary` directly (via whatever config key controls it, or a
one-line patch to `hermes-config.yaml` if it's exposed there). This makes
Hermes's own session store the single shared memory — no new code, no
polling, no bridge. This is the outcome to hope for and the one worth
spending real effort chasing first.

**Outcome B — internal, not configurable, but stable per chat_id**: can't
merge sessions inside Hermes, but can bridge them. Extend
`openai-shim.py` (or a small sibling script) to, on each Open WebUI turn,
call `hermes sessions export <telegram-session-id>` (read-only, local CLI —
no network dependency) and prepend a short recent-context summary to the
prompt sent to `chairman-primary`. One-directional (Open WebUI sees Telegram
history, not vice versa) unless mirrored the other way via a Telegram-side
hook — a real feature, not a design-only placeholder, but meaningfully more
code and more moving parts than Outcome A.

**Outcome C — unstable/random per connection**: no clean bridge point exists
inside Hermes at all. Fall back to an external sync layer: a tiny poller that
tails both `hermes sessions export` (for Telegram) and Open WebUI's
`webui.db` (SQLite, already identified in #31's original report) and
cross-posts a compact "what happened on the other channel" system message
into each on new activity. Most invasive of the three, matches #31's
original "Path B" — only worth building if A and B are both ruled out.

### Non-goals (explicitly out of scope for v1.1)

- Multi-user identity mapping — not needed; this is a single-operator stack.
- True real-time push sync — polling/context-stitching is enough for "did
  you see what I said on Telegram" at the latency a human conversation
  tolerates; no message queue or event bus needed.
- Any change to Telegram's own conflict/poller behavior — that's #27's
  problem, a precondition for this, not part of this design.

## Recommendation

Do not build B or C speculatively. Re-attempt Step 1 as soon as #27's
external poller conflict clears (or is resolved by the other VM's owner) and
Telegram actually holds a connection long enough to produce one real session.
That single observation determines which of A/B/C this becomes — guessing
now would mean building against an assumption instead of the real adapter
behavior.
