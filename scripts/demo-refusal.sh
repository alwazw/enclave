#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Enclave — the evidence gate, live.  "Nothing ships as proven without proof."
#
# One command. A real HTTP 409 from the Registrar. Then an earned close.
# This is not a mock: it drives the running Registrar + ux-validate services and
# ABORTS if the refusal does not actually fire (a broken gate is not a demo).
#
#   make demo         # or:  bash scripts/demo-refusal.sh
#
# Requires the core spine up (registrar + ux-validate):
#   docker compose -f local-stack.yml --profile core up -d
# Override endpoints via REGISTRAR_URL / UXV_URL / BOARD_RENDER_URL if needed.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REGISTRAR="${REGISTRAR_URL:-http://localhost:8090}"
UXV="${UXV_URL:-http://localhost:8091}"
RENDER_URL="${BOARD_RENDER_URL:-http://registrar:8090/board}"   # rendered from inside ux-validate's network
COMPANY="${DEMO_COMPANY:-demo}"

if [ -t 1 ]; then R=$'\e[31m'; G=$'\e[32m'; B=$'\e[36m'; D=$'\e[2m'; W=$'\e[1m'; Z=$'\e[0m'; else R= G= B= D= W= Z=; fi
hr(){ printf "${D}────────────────────────────────────────────────────────────${Z}\n"; }
step(){ printf "\n${B}${W}▸ %s${Z}\n" "$1"; }
jq_(){ python3 -c "import sys,json;d=json.load(sys.stdin);print(d$1)"; }

curl -sf "$REGISTRAR/health" >/dev/null 2>&1 || {
  printf "${R}Registrar not reachable at %s${Z}\n" "$REGISTRAR"
  printf "Start the spine:  ${W}docker compose -f local-stack.yml --profile core up -d${Z}\n"; exit 2; }

hr; printf "${W}ENCLAVE — evidence gate demo${Z}   ${D}%s${Z}\n" "$REGISTRAR"; hr

step "1. A project is incorporated. An agent is tasked to ship a landing page."
TID=$(curl -s -H "X-Company: $COMPANY" -H 'Content-Type: application/json' \
      -XPOST "$REGISTRAR/tasks" -d '{"title":"Ship the launch landing page","context":"ux"}' | jq_ '["id"]')
printf "  created ${W}%s${Z}  ${D}(context: ux)${Z}\n" "$TID"

step "2. The agent claims it is done — with no evidence at all."
CODE=$(curl -s -o /tmp/enc_d1.json -w '%{http_code}' -H "X-Company: $COMPANY" -H 'Content-Type: application/json' \
       -XPOST "$REGISTRAR/tasks/$TID/move" -d '{"status":"done","actor":"agent"}')
printf "  ${D}POST /tasks/%s/move {\"status\":\"done\"}${Z}   ->   ${R}${W}HTTP %s${Z}\n" "$TID" "$CODE"
printf "  ${R}%s${Z}\n" "$(jq_ '["detail"]["reason"]' </tmp/enc_d1.json)"
[ "$CODE" = "409" ] || { printf "${R}Expected 409 — the gate did not fire. Aborting; a broken gate is not a demo.${Z}\n"; exit 1; }
printf "  ${D}the board stays 'todo'. The refusal is server-side, below anything the agent can prompt.${Z}\n"

step "3. The agent tries a hand-wave: text 'evidence', no real artifact."
curl -s -o /dev/null -H "X-Company: $COMPANY" -H 'Content-Type: application/json' \
     -XPOST "$REGISTRAR/tasks/$TID/evidence" -d '{"text":"looks good to me, trust me","actor":"agent"}'
CODE=$(curl -s -o /tmp/enc_d2.json -w '%{http_code}' -H "X-Company: $COMPANY" -H 'Content-Type: application/json' \
       -XPOST "$REGISTRAR/tasks/$TID/move" -d '{"status":"done","actor":"agent"}')
printf "  ${D}POST /tasks/%s/move {\"status\":\"done\"}${Z}   ->   ${R}${W}HTTP %s${Z}\n" "$TID" "$CODE"
printf "  ${R}%s${Z}\n" "$(jq_ '["detail"]["reason"]' </tmp/enc_d2.json)"
[ "$CODE" = "409" ] || { printf "${R}Expected 409 — a ux task must have a REAL screenshot. Aborting.${Z}\n"; exit 1; }
printf "  ${D}'trust me' is not proof. A ux task needs a real rendered screenshot.${Z}\n"

step "4. So the agent does the honest work: render the real page (ux-validate / Playwright)."
curl -s -o /tmp/enc_uxv.json -H 'Content-Type: application/json' \
     -XPOST "$UXV/validate" -d "{\"task_id\":\"$TID\",\"url\":\"$RENDER_URL\",\"company\":\"$COMPANY\"}"
printf "  rendered: ${W}%s${Z}\n" "$(jq_ '["screenshots"]' </tmp/enc_uxv.json)"
printf "  ${D}real PNGs (desktop + mobile) written to the board volume and recorded as evidence.${Z}\n"

step "5. Now — and only now — the task closes."
CODE=$(curl -s -o /tmp/enc_d3.json -w '%{http_code}' -H "X-Company: $COMPANY" -H 'Content-Type: application/json' \
       -XPOST "$REGISTRAR/tasks/$TID/move" -d '{"status":"done","actor":"agent"}')
printf "  ${D}POST /tasks/%s/move {\"status\":\"done\"}${Z}   ->   ${G}${W}HTTP %s${Z}\n" "$TID" "$CODE"
[ "$CODE" = "200" ] || { printf "${R}Expected 200 after real evidence. Something is off.${Z}\n"; exit 1; }
printf "  ${G}${W}%s is done${Z} ${G}— done_at %s, backed by a real screenshot.${Z}\n" \
       "$TID" "$(jq_ '["done_at"]' </tmp/enc_d3.json)"

hr
printf "${W}The gate refused twice, then let real evidence through.${Z}\n"
printf "${D}Board: %s/board   ·   Audit trail: every move is a git commit   ·   Reproduce: make demo${Z}\n" "$REGISTRAR"
