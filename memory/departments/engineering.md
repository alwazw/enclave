# Engineering — Working Memory

(First entry — this file did not exist before 2026-07-16; devops.md had been carrying
application-level findings for lack of an engineering file. Cross-department config/infra
findings stay in devops.md per memory-protocol's "one file, others reference" rule — this file
is for architecture-pattern and code-review-relevant notes.)

## 2026-07-16 — Architecture pattern: "atomic first-user bootstrap" is a recurring gap class
Full incident writeup lives in `memory/departments/devops.md` ("Open WebUI: fixed 'first LAN
visitor becomes admin'"). Engineering-relevant takeaway for future services in this stack:

**The pattern:** many self-hosted apps (Open WebUI, n8n, Trilium, AFFiNE) have no way to
non-interactively pre-seed an admin account — their only bootstrap mechanism is "the first
person to complete signup/setup becomes admin," by design, because there's no chicken-and-egg-
free alternative. An app-level "disable signup" env var (e.g. `ENABLE_SIGNUP`) legitimately
cannot and does not block *that specific first* signup — verified against Open WebUI's actual
source this session, not assumed. Treating that env var as "the fix" is a category error: the
real fix is a bring-up-time script that claims the slot atomically with the real operator's
credentials before the port is reachable by anyone else.

**Reference implementation:** `scripts/init-trilium.sh` — idempotent (checks setup status
before acting, no-ops if already initialized), reads the secret from the gitignored `.env`
(never argv/echo), verifies its own success via a real authenticated call afterward (not just
"the POST returned 200"). `scripts/init-open-webui-admin.sh` (new, 2026-07-16) follows the same
idiom and additionally handles the hostile-race case explicitly: if the slot is already claimed
by someone else, it fails loudly instead of reporting false success.

**Known gap in the pattern, repo-wide:** none of the five init scripts that now exist for this
bug class (`init-trilium.sh`, `init-n8n-owner.sh`, `init-dozzle-auth.sh`,
`init-portainer-auth.sh`, `init-open-webui-admin.sh` — the last two were built/landed
2026-07-16, in this task's case and a concurrent session's respectively) are wired into
`scripts/onboard.sh`'s `bring_up()`. They require a human to remember to run them after
bring-up; a fresh install is exposed to this exact vulnerability class (unauthenticated
first-visitor-becomes-admin) for all five services until someone does. This is now the top
debt item — see devops.md's debt list. Fix shape: call each script from `bring_up()` right
after its service reports healthy, before the readiness-gate success screen. Estimated ~1hr,
high leverage (closes 5 already-built fixes at once, no new script-writing needed).

**Review note for any future PR touching auth/signup on any service in this stack:** "the env
var is set correctly" is not sufficient evidence of a fix for this bug class — the reviewer
must ask "does an unauthenticated third party still win a real HTTP race for the admin slot on
a fresh/reset volume?" and see a reproduced-live 403/denial, not just a config value.
