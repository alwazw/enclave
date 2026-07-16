#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════════════
#  AEF2 — Local AI Stack  ·  ONBOARDING INSTALLER  (the showcase "hero")
# ─────────────────────────────────────────────────────────────────────────────
#  gum-bash TUI with graceful fallback to whiptail, then to plain read.
#
#  DOCTRINE (CFO, 2026-07-10): FREE-BY-DEFAULT. A fresh install runs at $0 and
#  CANNOT incur a surprise charge — zero paid-provider keys are wired unless the
#  operator explicitly opts in AND sets a spend cap in the same step.
#
#  Flow:  prereqs → free-or-keys → .env generation → guardrail → bring-up →
#         READINESS GATE (prove a real completion, not "containers healthy").
#
#  Usage:
#    ./scripts/onboard.sh                      # interactive (recommended)
#    ./scripts/onboard.sh --path free          # non-interactive free path
#    ./scripts/onboard.sh --env-file /tmp/.env --path free --skip-bringup
#                                              #   dry-run env generation only
#    ./scripts/onboard.sh --readiness-only     # run only the readiness gate
#
#  Flags:
#    --path {free|keys}   preselect the flow, skip Screen 1 (needed w/o a TTY)
#    --env-file PATH      target env file (default: <repo>/.env)
#    --profile LIST       compose profiles to bring up (default: core)
#    --skip-bringup       generate .env + print the plan, do NOT run docker
#    --readiness-only     skip everything, just run the readiness gate
#    --no-color           disable ANSI colour
#    -h|--help            this help
#
#  NEVER prints secret values. NEVER commits. NEVER clobbers an existing .env
#  without confirmation.
# ═════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Defaults / arg parse ─────────────────────────────────────────────────────
ENV_FILE="$REPO_DIR/.env"
EXAMPLE_FILE="$REPO_DIR/.env.example"
COMPOSE_FILE="$REPO_DIR/local-stack.yml"
PATH_CHOICE=""          # free | keys
PROFILES="core"
SKIP_BRINGUP=false
READINESS_ONLY=false
USE_COLOR=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)          PATH_CHOICE="${2:-}"; shift 2 ;;
    --env-file)      ENV_FILE="${2:-}"; shift 2 ;;
    --profile|-p)    PROFILES="${2:-}"; shift 2 ;;
    --skip-bringup)  SKIP_BRINGUP=true; shift ;;
    --readiness-only) READINESS_ONLY=true; shift ;;
    --no-color)      USE_COLOR=false; shift ;;
    -h|--help)       sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# ── Colours ──────────────────────────────────────────────────────────────────
if [[ "$USE_COLOR" == true && -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

# ═════════════════════════════════════════════════════════════════════════════
#  UI ABSTRACTION LAYER  —  gum > whiptail > plain read
# ═════════════════════════════════════════════════════════════════════════════
UI="plain"
command -v whiptail >/dev/null 2>&1 && UI="whiptail"
command -v gum      >/dev/null 2>&1 && UI="gum"

ok()   { echo "${GREEN}[✓]${NC} $*"; }
info() { echo "${CYAN}[i]${NC} $*"; }
warn() { echo "${YELLOW}[!]${NC} $*"; }
err()  { echo "${RED}[✗]${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

ui_header() {
  # $1 = title
  if [[ "$UI" == "gum" ]]; then
    gum style --border double --align center --width 62 --padding "1 2" \
      --border-foreground 45 "$1"
  else
    echo
    echo "${BOLD}${CYAN}  ┌────────────────────────────────────────────────────────┐${NC}"
    printf "${BOLD}${CYAN}  │%-56s│${NC}\n" "  $1"
    echo "${BOLD}${CYAN}  └────────────────────────────────────────────────────────┘${NC}"
    echo
  fi
}

ui_note() {
  # multi-line narrative block; args are lines
  if [[ "$UI" == "gum" ]]; then
    printf '%s\n' "$@" | gum style --border rounded --padding "1 2" --border-foreground 240
  else
    echo "${DIM}────────────────────────────────────────────────────────────${NC}"
    printf '  %s\n' "$@"
    echo "${DIM}────────────────────────────────────────────────────────────${NC}"
  fi
}

# ui_choose PROMPT option1 option2 ...  → echoes chosen option
ui_choose() {
  local prompt="$1"; shift
  local opts=("$@")
  case "$UI" in
    gum)
      gum choose --header "$prompt" "${opts[@]}"
      ;;
    whiptail)
      local menu=(); local i=1
      for o in "${opts[@]}"; do menu+=("$i" "$o"); i=$((i+1)); done
      local sel
      sel=$(whiptail --title "AEF2 Onboarding" --menu "$prompt" 20 74 10 \
            "${menu[@]}" 3>&1 1>&2 2>&3) || { echo "${opts[0]}"; return 0; }
      echo "${opts[$((sel-1))]}"
      ;;
    plain)
      echo "$prompt" >&2
      local i=1
      for o in "${opts[@]}"; do echo "  $i) $o" >&2; i=$((i+1)); done
      local n
      read -rp "  Select [1]: " n; n="${n:-1}"
      echo "${opts[$((n-1))]}"
      ;;
  esac
}

# ui_confirm PROMPT  → returns 0 for yes, 1 for no
ui_confirm() {
  local prompt="$1"
  case "$UI" in
    gum)      gum confirm "$prompt" ;;
    whiptail) whiptail --title "AEF2 Onboarding" --yesno "$prompt" 12 70 ;;
    plain)    local a; read -rp "$prompt [y/N]: " a; [[ "$a" =~ ^[Yy] ]] ;;
  esac
}

# ui_input PROMPT [default]  → echoes entered value (plain text)
ui_input() {
  local prompt="$1"; local def="${2:-}"
  case "$UI" in
    gum)      gum input --header "$prompt" --value "$def" ;;
    whiptail) whiptail --title "AEF2 Onboarding" --inputbox "$prompt" 10 70 "$def" 3>&1 1>&2 2>&3 ;;
    plain)    local a; read -rp "$prompt [$def]: " a; echo "${a:-$def}" ;;
  esac
}

# ui_password PROMPT  → echoes entered secret (input is MASKED on screen)
ui_password() {
  local prompt="$1"
  case "$UI" in
    gum)      gum input --password --header "$prompt" ;;
    whiptail) whiptail --title "AEF2 Onboarding" --passwordbox "$prompt" 10 70 3>&1 1>&2 2>&3 ;;
    plain)    local a; read -rsp "$prompt: " a; echo >&2; echo "$a" ;;
  esac
}

# Non-interactive guard: refuse to prompt when there's no TTY and no --path
require_tty_or_path() {
  if [[ ! -t 0 && -z "$PATH_CHOICE" ]]; then
    die "No TTY and no --path given. Re-run with --path free (or keys)."
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
#  1. PREREQUISITE DETECTION
# ═════════════════════════════════════════════════════════════════════════════
IS_WSL=false
HAS_GPU=false
DOCKER_COMPOSE=("docker" "compose")

detect_prereqs() {
  ui_header "Step 1 · Checking your machine"

  # WSL2 detection (kernel string carries "microsoft")
  if grep -qi 'microsoft' /proc/version 2>/dev/null; then
    IS_WSL=true
    ok "WSL2 detected — running the Linux stack inside Windows."
  fi

  # docker present?
  if ! command -v docker >/dev/null 2>&1; then
    err "Docker is not installed."
    if [[ "$IS_WSL" == true ]]; then
      ui_note "Fix: install Docker Desktop on Windows and enable" \
              "'Use the WSL 2 based engine' + WSL integration for this distro." \
              "https://docs.docker.com/desktop/wsl/"
    else
      ui_note "Fix: install Docker Engine, then add yourself to the docker group:" \
              "  curl -fsSL https://get.docker.com | sh" \
              "  sudo usermod -aG docker \$USER   # then log out/in"
    fi
    die "Docker required."
  fi
  ok "docker found: $(docker --version 2>/dev/null | head -1)"

  # Minimum-version checks against requirements.yml (single source of truth —
  # see #16: docs/config drifting from real requirements with nothing to
  # catch it). Warns rather than hard-fails; an old-but-working install
  # shouldn't be blocked by a soft version floor.
  local req_file="$REPO_DIR/requirements.yml"
  if [[ -f "$req_file" ]]; then
    local req_docker req_compose docker_ver compose_ver
    req_docker=$(grep -E '^\s*docker_min_version:' "$req_file" | head -1 | sed -E 's/.*:\s*"?([0-9.]+)"?.*/\1/')
    req_compose=$(grep -E '^\s*compose_min_version:' "$req_file" | head -1 | sed -E 's/.*:\s*"?([0-9.]+)"?.*/\1/')
    docker_ver=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$req_docker" && -n "$docker_ver" ]] && \
       [[ "$(printf '%s\n%s' "$req_docker" "$docker_ver" | sort -V | head -1)" != "$req_docker" ]]; then
      warn "Docker ${docker_ver} is older than the recommended minimum ${req_docker} (requirements.yml)."
    fi
  fi

  # compose v2 vs legacy
  if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE=("docker" "compose")
    ok "Docker Compose v2 found: $(docker compose version --short 2>/dev/null)"
    if [[ -f "$req_file" ]]; then
      compose_ver=$(docker compose version --short 2>/dev/null)
      if [[ -n "$req_compose" && -n "$compose_ver" ]] && \
         [[ "$(printf '%s\n%s' "$req_compose" "$compose_ver" | sort -V | head -1)" != "$req_compose" ]]; then
        warn "Compose ${compose_ver} is older than the recommended minimum ${req_compose} (requirements.yml)."
      fi
    fi
  elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE=("docker-compose")
    warn "Using legacy docker-compose. Compose v2 is recommended."
  else
    ui_note "Fix: Compose v2 ships inside Docker Desktop / docker-ce-cli." \
            "https://docs.docker.com/compose/install/"
    die "Docker Compose not found."
  fi

  # daemon running?
  if ! docker info >/dev/null 2>&1; then
    if [[ "$IS_WSL" == true ]]; then
      ui_note "The Docker daemon is not reachable." \
              "Fix: start Docker Desktop on Windows and make sure WSL" \
              "integration is enabled for this distro, then re-run."
    else
      ui_note "The Docker daemon is not reachable." \
              "Fix: sudo systemctl start docker  (and enable it on boot)"
    fi
    die "Docker daemon is not running."
  fi
  ok "Docker daemon is running."

  # optional NVIDIA GPU (accelerates local Ollama — nice to have, not required)
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    HAS_GPU=true
    ok "NVIDIA GPU detected — local Ollama models will run accelerated."
  else
    HAS_GPU=false
    info "No NVIDIA GPU detected — local models run on CPU (slower, still works)."
    [[ "$IS_WSL" == true ]] && ui_note "On WSL2, GPU needs a recent NVIDIA driver on Windows +" \
            "Docker Desktop GPU support. CPU fallback works regardless."
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
#  2. FREE-BY-DEFAULT  ·  Screen 1
# ═════════════════════════════════════════════════════════════════════════════
choose_path() {
  if [[ -n "$PATH_CHOICE" ]]; then
    info "Path preselected: ${BOLD}${PATH_CHOICE}${NC}"
    return
  fi
  ui_header "Step 2 · This stack is free to run"
  ui_note \
    "AEF2 runs at \$0 out of the box." \
    "" \
    "It routes every request through a fallback cascade of FREE model" \
    "tiers (Google Gemini free tier, OpenRouter :free models) and a" \
    "fully-local Ollama floor that needs no internet and no account." \
    "" \
    "These free tiers need NO credit card. They fail closed: when you" \
    "hit a rate limit they slow down — they never bill you." \
    "" \
    "You can add paid API keys later for higher quality. You never have to."
  local c
  c=$(ui_choose "How do you want to start?" \
        "Continue free (recommended)" \
        "I have API keys")
  case "$c" in
    "Continue free"*) PATH_CHOICE="free" ;;
    "I have API keys") PATH_CHOICE="keys" ;;
    *) PATH_CHOICE="free" ;;
  esac
  ok "Path: ${BOLD}${PATH_CHOICE}${NC}"
}

# ═════════════════════════════════════════════════════════════════════════════
#  3. .env GENERATION  (single source of truth = .env.example)
# ─────────────────────────────────────────────────────────────────────────────
#  Auto-generates every internal secret placeholder. Prompts (masked) only for
#  what the chosen path needs. In free mode: prompts for NOTHING paid.
# ═════════════════════════════════════════════════════════════════════════════

# ── canonical parameterized var set (kept in lock-step with .env.example; the
#    scrub pipeline in scripts/build-showcase.sh consumes the SAME classification)
#
# INTERNAL_SECRETS   : auto-generated; <CHANGE_ME> / <CHANGE_ME_32CHARS> placeholders
# FREE_PROVIDER_KEYS : optional, NO credit card, fail-closed (rate-limit, never bill)
# PAID_PROVIDER_KEYS : opt-in ONLY; each requires a spend cap in the same step
# PERSONAL_IDENTIFIERS: left blank on a fresh install; scrubbed from the showcase
# INTERNAL_SECRETS: the 23 <CHANGE_ME>/<CHANGE_ME_32CHARS> placeholders in
#   .env.example (auto-generated below) + TRILIUM_PASSWORD (literal default).
INTERNAL_SECRETS=(
  POSTGRES_PASSWORD REDIS_PASSWORD SURREALDB_PASS
  QDRANT_API_KEY CHROMADB_AUTH_TOKEN
  LITELLM_MASTER_KEY LITELLM_SALT_KEY LITELLM_API_KEY
  OPENWEBUI_SECRET N8N_ENCRYPTION_KEY FLOWISE_PASSWORD FLOWISE_SECRET_KEY
  ANYTHINGLLM_JWT AFFINE_ADMIN_PASSWORD MCPO_API_KEY HERMES_API_KEY
  SEARXNG_SECRET TRILIUM_PASSWORD
  LANGFUSE_SECRET_KEY LANGFUSE_ENCRYPTION_KEY
  LANGFUSE_INIT_PROJECT_PUBLIC_KEY LANGFUSE_INIT_PROJECT_SECRET_KEY
  CLOUDBEAVER_ADMIN_PASSWORD
  # 2026-07-13 security hardening: admin-bootstrap secrets for previously
  # zero-auth/race-window surfaces (Dozzle, Portainer, n8n owner account).
  DOZZLE_AUTH_PASSWORD PORTAINER_ADMIN_PASSWORD N8N_OWNER_PASSWORD
)
FREE_PROVIDER_KEYS=( GEMINI_API_KEY_1 GEMINI_API_KEY_2 GEMINI_API_KEY_3
                     OPENROUTER_KEY_1 OPENROUTER_KEY_2 OPENROUTER_KEY_3
                     GROQ_API_KEY_1 GROQ_API_KEY )
PAID_PROVIDER_KEYS=( OPENAI_API_KEY ANTHROPIC_API_KEY GOOGLE_API_KEY
                     DEEPSEEK_KEY_1 DEEPSEEK_KEY_2 NOVITA_KEY_1
                     ALIBABA_MODELSTUDIO_KEY_1 NVIDIA_NIM_API_KEY )
# PERSONAL_IDENTIFIERS: blank on a fresh install; the showcase scrub strips any
#   real values (domains/IP/UUID/email/tokens) from these.
PERSONAL_IDENTIFIERS=( CLOUDFLARE_EMAIL CLOUDFLARE_GLOBAL_API_KEY
                       CLOUDFLARE_ALL_DNS_ZONE_KEY CLOUDFLARE_TUNNEL_TOKEN
                       TELEGRAM_BOT_TOKEN TELEGRAM_ID GITHUB_TOKEN )

gen_secret()   { head -c 32 /dev/urandom | xxd -p | tr -d '\n' 2>/dev/null \
                   || openssl rand -hex 32; }
gen_password() { head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 20 2>/dev/null \
                   || openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20; }

# set_env VAR VALUE  — upsert VAR=VALUE in $ENV_FILE (value NEVER echoed)
set_env() {
  local var="$1"; local val="$2"
  local esc
  esc=$(printf '%s' "$val" | sed -e 's/[\/&|]/\\&/g')
  if grep -qE "^${var}=" "$ENV_FILE"; then
    sed -i "s|^${var}=.*|${var}=${esc}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$var" "$val" >> "$ENV_FILE"
  fi
}

generate_env() {
  ui_header "Step 3 · Generating your configuration"

  [[ -f "$EXAMPLE_FILE" ]] || die ".env.example not found at $EXAMPLE_FILE"

  if [[ -f "$ENV_FILE" ]]; then
    if ui_confirm "$ENV_FILE already exists. Overwrite it? (a backup is kept)"; then
      cp "$ENV_FILE" "${ENV_FILE}.bak.$(date +%s)"
      cp "$EXAMPLE_FILE" "$ENV_FILE"
      ok "Backed up and recreated .env from .env.example"
    else
      info "Keeping existing .env — only filling empty placeholders."
    fi
  else
    cp "$EXAMPLE_FILE" "$ENV_FILE"
    ok "Created .env from .env.example"
  fi

  # 3a. Auto-detect the host's real LAN IP — must run BEFORE the generic
  #     <CHANGE_ME> sweep below, or that loop would overwrite HOST_IP with a
  #     random hex secret instead of a real IP.
  if grep -qE '^HOST_IP=(<CHANGE_ME>|10\.0\.0\.10)$' "$ENV_FILE"; then
    local detected
    detected=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p')
    [[ -z "$detected" ]] && detected=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -n "$detected" ]]; then
      set_env "HOST_IP" "$detected"
      ok "Auto-detected HOST_IP: ${detected}"
    else
      warn "Could not auto-detect a LAN IP — set HOST_IP manually in .env."
    fi
  fi

  # 3b. Auto-generate every internal secret placeholder.
  #     Handles BOTH <CHANGE_ME> and <CHANGE_ME_32CHARS> (setup.sh missed the latter).
  local changed=0 var val line
  while IFS= read -r line; do
    if [[ "$line" =~ ^([A-Z0-9_]+)=(\<CHANGE_ME\>|\<CHANGE_ME_32CHARS\>)$ ]]; then
      var="${BASH_REMATCH[1]}"
      if [[ "$var" =~ (PASSWORD|PASS)$ ]]; then val=$(gen_password); else val=$(gen_secret); fi
      set_env "$var" "$val"
      changed=$((changed+1))
    fi
  done < "$EXAMPLE_FILE"
  ok "Generated $changed internal secrets (passwords, encryption + API keys)."

  # 3c. Trilium ships a literal weak default — regenerate it too.
  if grep -qE '^TRILIUM_PASSWORD=change-me-strong-password$' "$ENV_FILE"; then # gitleaks:allow
    set_env "TRILIUM_PASSWORD" "$(gen_password)"
    ok "Generated Trilium admin password."
  fi

  # 3d. GUARDRAIL: on a fresh install EVERY paid provider key stays BLANK.
  #     .env.example already ships them blank; we re-assert it so a re-run of the
  #     free path can never leave a paid key wired.
  if [[ "$PATH_CHOICE" == "free" ]]; then
    local k
    for k in "${PAID_PROVIDER_KEYS[@]}"; do set_env "$k" ""; done
    ok "Guardrail: all ${#PAID_PROVIDER_KEYS[@]} paid-provider keys left blank (cannot bill)."
  fi

  # 3e. Path-specific prompting.
  if [[ "$PATH_CHOICE" == "free" ]]; then
    collect_free_keys
  else
    collect_keys_flow
  fi
}

# ── FREE path: optionally paste genuinely-free keys (no card, fail-closed) ────
collect_free_keys() {
  # Non-interactive free mode: wire nothing, rely on the local Ollama floor.
  if [[ ! -t 0 || -n "${AEF2_NONINTERACTIVE:-}" ]]; then
    info "Free mode: local Ollama floor only (no cloud keys prompted)."
    return
  fi
  ui_note \
    "Optional: paste any FREE cloud keys you already have for better" \
    "quality. All three below are free, need NO credit card, and only" \
    "rate-limit you — they can never charge you." \
    "" \
    "  · Google Gemini  → https://aistudio.google.com/apikey  (billing OFF)" \
    "  · OpenRouter     → https://openrouter.ai/keys  (uses :free models)" \
    "  · Groq           → https://console.groq.com/keys" \
    "" \
    "Press Enter / leave blank to skip any of them. Local Ollama always" \
    "runs as the \$0 offline floor regardless."
  if ui_confirm "Add a free Gemini key now?"; then
    local g; g=$(ui_password "Gemini API key (masked)")
    [[ -n "$g" ]] && { set_env GEMINI_API_KEY_1 "$g"; ok "Wired free Gemini key."; }
  fi
  if ui_confirm "Add a free OpenRouter key now?"; then
    local o; o=$(ui_password "OpenRouter API key (masked)")
    [[ -n "$o" ]] && { set_env OPENROUTER_KEY_1 "$o"; ok "Wired free OpenRouter key."; }
  fi
  if ui_confirm "Add a free Groq key now?"; then
    local q; q=$(ui_password "Groq API key (masked)")
    [[ -n "$q" ]] && { set_env GROQ_API_KEY_1 "$q"; ok "Wired free Groq key."; }
  fi
}

# ── KEYS path: the CFO 4-tier choice architecture, cap required for paid ──────
collect_keys_flow() {
  ui_header "Choose your upgrade tier"
  local tier
  tier=$(ui_choose "Every tier keeps the free cascade underneath. Pick one:" \
    "Stay free — free cloud tiers + local, \$0 (recommended)" \
    "OpenRouter \$10 one-time — 20x daily limit + PAYG headroom (best value)" \
    "Pay-as-you-go — paste metered keys (OpenAI / DeepSeek / Anthropic)" \
    "Subscription — Claude Max etc. (dev-time; NOT the stack runtime)")

  case "$tier" in
    "Stay free"*)
      info "Staying free. Offering the same free-key prompts."
      collect_free_keys
      ;;
    "OpenRouter \$10"*)
      ui_note \
        "OpenRouter: a one-time \$10 credit purchase permanently raises" \
        "your limit from 50 to 1,000 requests/day AND funds pay-as-you-go" \
        "on non-free models. Best first upgrade for the money." \
        "" \
        "Paste the key from https://openrouter.ai/keys."
      local o; o=$(ui_password "OpenRouter API key (masked)")
      [[ -n "$o" ]] && set_env OPENROUTER_KEY_1 "$o"
      require_spend_cap "OpenRouter (paid credits)" "openrouter"
      ;;
    "Pay-as-you-go"*)
      ui_note \
        "Pay-as-you-go: these keys BILL PER TOKEN. You will set a hard" \
        "spend cap in the next step so the stack fails closed at the cap."
      _prompt_paid OPENAI_API_KEY   "OpenAI API key"
      _prompt_paid ANTHROPIC_API_KEY "Anthropic API key"
      _prompt_paid DEEPSEEK_KEY_1    "DeepSeek API key"
      require_spend_cap "pay-as-you-go pool" "payg"
      ;;
    "Subscription"*)
      ui_note \
        "A Claude/Gemini subscription authenticates the DEV-TIME CLI" \
        "(Claude Code etc.). It CANNOT be used as a stack API key — the" \
        "stack's LiteLLM needs a per-token API key on a separate billing" \
        "rail. So the stack stays on the free cascade; use your" \
        "subscription in your editor, not here."
      info "No stack key wired. Staying free at runtime."
      collect_free_keys
      ;;
  esac
}

_prompt_paid() { # VAR "label"
  local var="$1" label="$2"
  if ui_confirm "Add a $label? (paid, per-token)"; then
    local v; v=$(ui_password "$label (masked)")
    [[ -n "$v" ]] && { set_env "$var" "$v"; ok "Wired $label."; }
  fi
}

# require_spend_cap POOL_LABEL POOL_KEY — records the hard cap; enforced as a
# LiteLLM virtual-key max_budget when the guardrail key is provisioned.
SPEND_CAP_USD=""
require_spend_cap() {
  local label="$1"
  ui_note \
    "Set a HARD monthly spend cap for the $label." \
    "The stack enforces it as a LiteLLM virtual-key budget and STOPS" \
    "serving paid models once the cap is reached (fails closed)." \
    "" \
    "CFO recommendation: \$10/month hard cap for a first paid pool."
  local cap
  cap=$(ui_input "Hard monthly cap in USD" "10")
  # sanitize to a number
  cap="${cap//[^0-9.]/}"; cap="${cap:-10}"
  SPEND_CAP_USD="$cap"
  set_env "LITELLM_PAID_MAX_BUDGET" "$cap"
  ok "Hard cap recorded: \$${cap}/month for paid models."
}

# ═════════════════════════════════════════════════════════════════════════════
#  4. GUARDRAIL  —  LiteLLM virtual key
# ─────────────────────────────────────────────────────────────────────────────
#  Belt-and-suspenders on top of "no paid keys wired":
#   · free path → internal virtual key gets a models allowlist that EXCLUDES
#     the paid morpheus-prod-* (Anthropic) aliases — THIS is the real
#     guardrail against paid spend, and it fails closed (403) independent of
#     budget, proven working. max_budget is a small POSITIVE cap (not 0 —
#     see BUG note below), purely a belt-and-suspenders ceiling.
#   · paid path → max_budget = the hard cap the operator set above.
#  Requires LiteLLM to be up; called from bring_up (never in --skip-bringup).
#
#  BUG FOUND + FIXED 2026-07-13 (engineering, empirically verified against
#  the live proxy, not just reasoned): max_budget=0 does NOT mean "unlimited
#  free spend" — LiteLLM's budget check rejects the VERY FIRST call against
#  a max_budget=0 key with HTTP 429 "Budget has been exceeded! Current cost:
#  0.0, Max budget: 0.0", even when the call target is a genuinely $0 local
#  Ollama-backed model (openai/morpheus-local-fallback) that itself is never
#  billed — LiteLLM's cost check runs before/independent of the call
#  actually costing anything (shadow-priced against its internal price
#  table). A free-mode install using max_budget=0 is therefore DOA: it
#  locks itself out on the first request. Verified the fix the same way:
#  the identical call against a max_budget=1 key succeeds (HTTP 200, real
#  completion). Fixed by using a small positive budget (FREE_PATH_BUDGET_USD,
#  default $2) for the free path too — the real guardrail stays the model
#  allowlist (proven to 403 independent of budget), not the budget number.
# ═════════════════════════════════════════════════════════════════════════════
FREE_MODEL_ALLOWLIST='["openai/morpheus-main-model","openai/morpheus-main-tier2","openai/morpheus-utility-model","openai/morpheus-utility-tier2","openai/morpheus-openrouter-free","openai/morpheus-novita","openai/morpheus-nim","openai/morpheus-local-fallback","openai/morpheus-embedding-model"]'
FREE_PATH_BUDGET_USD="${FREE_PATH_BUDGET_USD:-2}"

provision_guardrail_key() {
  local port master budget models_json
  port=$(_envget LITELLM_PORT 4000)
  master=$(_envget LITELLM_MASTER_KEY "")
  [[ -z "$master" ]] && { warn "No master key — skipping virtual-key guardrail."; return 0; }

  if [[ "$PATH_CHOICE" == "free" ]]; then
    # NOT 0 — see BUG note above. A literal 0 blocks the first call outright
    # (LiteLLM shadow-prices against its internal price table even for
    # nominally-free models). The real guardrail against PAID models is the
    # allowlist below, which correctly 403s independent of budget.
    budget="$FREE_PATH_BUDGET_USD"; models_json="$FREE_MODEL_ALLOWLIST"
    info "Provisioning internal virtual key: max_budget=\$${budget} + free-model allowlist (the allowlist is the real guardrail against paid spend)."
  else
    budget="${SPEND_CAP_USD:-10}"; models_json='["all-proxy-models"]'
    info "Provisioning internal virtual key: hard max_budget=\$${budget}."
  fi

  # Create/replace the aef2-internal virtual key. New key value is written to
  # LITELLM_API_KEY and NEVER printed.
  local body resp newkey
  body=$(printf '{"key_alias":"aef2-internal","max_budget":%s,"budget_duration":"30d","models":%s}' "$budget" "$models_json")
  resp=$(curl -s -m 15 "http://localhost:${port}/key/generate" \
           -H "Authorization: Bearer ${master}" \
           -H "Content-Type: application/json" \
           -d "$body" 2>/dev/null || echo '')
  newkey=$(printf '%s' "$resp" | python3 -c \
    "import sys,json;
try: print(json.load(sys.stdin).get('key',''))
except Exception: print('')" 2>/dev/null)
  if [[ -n "$newkey" ]]; then
    set_env LITELLM_API_KEY "$newkey"
    ok "Guardrail virtual key provisioned (budget enforced, key not shown)."
  else
    warn "Could not mint a virtual key via LiteLLM; the generated LITELLM_API_KEY"
    warn "remains. Free-mode safety still holds: no paid keys are wired."
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
#  5. BRING-UP  (core profile, narrated)
# ═════════════════════════════════════════════════════════════════════════════
_envget() { # VAR default — read a value from $ENV_FILE (never used for secrets in logs)
  local v
  v=$(grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' ')
  echo "${v:-$2}"
}

bring_up() {
  ui_header "Step 4 · Starting your stack"
  local proj; proj=$(_envget COMPOSE_PROJECT_NAME aef2)
  local flags=(); IFS=',' read -ra parr <<< "$PROFILES"
  for p in "${parr[@]}"; do flags+=(--profile "$p"); done

  info "Bringing up profile(s): ${BOLD}${PROFILES}${NC}"
  info "Databases and the LiteLLM gateway start first…"
  ( cd "$REPO_DIR" && "${DOCKER_COMPOSE[@]}" -f "$COMPOSE_FILE" \
      --env-file "$ENV_FILE" "${flags[@]}" up -d --remove-orphans )
  ok "Containers created."

  # SECURITY: claim Open WebUI's first-signup admin slot immediately — it
  # grants admin to whoever signs up first regardless of ENABLE_SIGNUP, so
  # every second of delay here is a real LAN exposure window.
  ensure_openwebui_admin_claimed "$proj"

  # Wait for LiteLLM liveness (the gateway everything routes through).
  local port; port=$(_envget LITELLM_PORT 4000)
  info "Waiting for the LiteLLM gateway on :${port}…"
  local up=false
  for _ in $(seq 1 60); do
    if curl -sf -m 3 "http://localhost:${port}/health/liveliness" >/dev/null 2>&1; then
      up=true; break; fi
    sleep 2
  done
  [[ "$up" == true ]] && ok "LiteLLM gateway is live." || warn "LiteLLM slow to start — continuing."

  # Provision the guardrail virtual key now that LiteLLM is up.
  provision_guardrail_key

  # THE LONG POLE: a local model must exist for the offline floor. Narrate it.
  ensure_local_model "$proj"

  # TriliumNext needs its first-run setup wizard driven headlessly, or it sits
  # at an unusable setup screen forever (see scripts/init-trilium.sh).
  ensure_trilium_initialized "$proj"

  # One-shot job containers (e.g. affine-migration) sit "Exited" forever
  # after a successful run — reads as "down" in Homepage/Portainer even
  # though exit 0 means success. Safe to remove: compose recreates and
  # reruns them (idempotent) on the next full bring-up.
  local exited_jobs
  exited_jobs=$(docker ps -a --filter "label=aef2.oneshot=true" --filter "status=exited" -q)
  if [[ -n "$exited_jobs" ]]; then
    echo "$exited_jobs" | xargs -r docker rm >/dev/null
    ok "Cleaned up $(echo "$exited_jobs" | wc -l) completed one-shot job container(s)."
  fi
}

ensure_openwebui_admin_claimed() {
  local proj="$1"
  local cname="${proj}_open_webui"
  if ! docker ps --format '{{.Names}}' | grep -q "^${cname}$"; then
    return 0  # not in this profile set
  fi
  local pw; pw=$(_envget OPENWEBUI_ADMIN_PASSWORD "")
  if [[ -z "$pw" || "$pw" == "<CHANGE_ME>" ]]; then
    warn "OPENWEBUI_ADMIN_PASSWORD not set — cannot auto-claim the admin slot."
    warn "Reach http://localhost:$(_envget OPENWEBUI_PORT 3000) yourself FIRST, immediately."
    return 0
  fi
  info "Claiming Open WebUI's admin account before anyone else can…"
  if OPENWEBUI_BASE_URL="http://127.0.0.1:$(_envget OPENWEBUI_PORT 3000)" \
     ENV_FILE="$ENV_FILE" bash "$REPO_DIR/scripts/init-openwebui-admin.sh" >/dev/null 2>&1; then
    ok "Open WebUI admin account secured."
  else
    warn "Open WebUI admin claim failed — reach it yourself FIRST: scripts/init-openwebui-admin.sh"
  fi
}

ensure_trilium_initialized() {
  local proj="$1"
  local cname="${proj}_trilium"
  if ! docker ps --format '{{.Names}}' | grep -q "^${cname}$"; then
    return 0  # not in this profile set
  fi
  info "Initializing TriliumNext (schema + admin password)…"
  if TRILIUM_BASE_URL="http://127.0.0.1:$(_envget TRILIUM_PORT 8190)" \
     ENV_FILE="$ENV_FILE" bash "$REPO_DIR/scripts/init-trilium.sh" >/dev/null 2>&1; then
    ok "TriliumNext ready."
  else
    warn "TriliumNext init failed — retry later: scripts/init-trilium.sh"
  fi
}

ensure_local_model() {
  local proj="$1"
  local model; model=$(_envget OLLAMA_DEFAULT_MODEL "llama3.2:latest")
  local cname="${proj}_ollama"
  if ! docker ps --format '{{.Names}}' | grep -q "^${cname}$"; then
    info "Ollama container not in this profile — skipping model pull."
    return 0
  fi
  if docker exec "$cname" ollama list 2>/dev/null | grep -q "${model%%:*}"; then
    ok "Local model already present: $model"
    return 0
  fi

  # Resource governance: model pulls are multi-GB — a host that's nearly out
  # of disk fails mid-pull with a confusing error. Check headroom on the
  # Docker data-root filesystem (where the model layers actually land) first.
  local min_free_gb=10
  local docker_root free_kb free_gb
  docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo /var/lib/docker)
  free_kb=$(df -Pk "$docker_root" 2>/dev/null | awk 'NR==2{print $4}')
  if [[ -n "$free_kb" ]]; then
    free_gb=$(( free_kb / 1024 / 1024 ))
    if (( free_gb < min_free_gb )); then
      warn "Only ${free_gb}GB free on ${docker_root} — skipping model pull (need ~${min_free_gb}GB+ headroom)."
      warn "Free up space, then run: docker exec ${cname} ollama pull ${model}"
      return 0
    fi
  fi

  ui_note \
    "Pulling the local model '${model}' — this is the long pole of the" \
    "install (several GB). It is the offline \$0 floor; once cached, the" \
    "stack works with no internet at all. Grab a coffee…"
  if [[ "$UI" == "gum" ]]; then
    gum spin --title "Pulling ${model}…" -- docker exec "$cname" ollama pull "$model" \
      && ok "Local model ready: $model" || warn "Model pull failed — retry later: docker exec $cname ollama pull $model"
  else
    docker exec "$cname" ollama pull "$model" \
      && ok "Local model ready: $model" || warn "Model pull failed — retry later."
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
#  6. READINESS GATE  —  prove a REAL completion, not "containers healthy"
# ═════════════════════════════════════════════════════════════════════════════
readiness_gate() {
  ui_header "Step 5 · Proving your AI actually answers"
  local port key owui_port owui_host
  port=$(_envget LITELLM_PORT 4000)
  owui_port=$(_envget OPENWEBUI_PORT 3000)
  key=$(_envget LITELLM_API_KEY "")   # read into a var; never echoed
  [[ -z "$key" ]] && key=$(_envget LITELLM_MASTER_KEY "")

  if [[ -z "$key" ]]; then
    err "No LiteLLM key available to test with."
    return 1
  fi

  # 6a. Gateway liveness.
  if ! curl -sf -m 5 "http://localhost:${port}/health/liveliness" >/dev/null 2>&1; then
    err "LiteLLM gateway is not answering on :${port}."
    ui_note "The stack is up but the gateway isn't ready. Check:" \
            "  ${DOCKER_COMPOSE[*]} -f local-stack.yml logs litellm"
    return 1
  fi
  ok "Gateway liveness: OK"

  # 6b. A REAL chat completion through the (free) cascade.
  info "Sending a real prompt through the model cascade…"
  local resp verdict
  resp=$(curl -s -m 90 "http://localhost:${port}/v1/chat/completions" \
    -H "Authorization: Bearer ${key}" -H "Content-Type: application/json" \
    -d '{"model":"openai/morpheus-main-model","messages":[{"role":"user","content":"In one word, are you ready? Answer READY."}],"max_tokens":64}' 2>/dev/null || echo '')

  verdict=$(printf '%s' "$resp" | python3 -c '
import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    print("FAIL|unparseable response"); sys.exit()
ch=d.get("choices")
if not ch:
    print("FAIL|"+ (json.dumps(d.get("error", d))[:160])); sys.exit()
m=ch[0].get("message",{})
content=(m.get("content") or m.get("reasoning_content") or "").strip()
served=d.get("model","?")
if content:
    print("PASS|"+served+"|"+content[:60].replace("\n"," "))
else:
    print("FAIL|empty completion (model="+served+")")
' 2>/dev/null)

  if [[ "$verdict" == PASS\|* ]]; then
    local served body
    served=$(echo "$verdict" | cut -d'|' -f2)
    body=$(echo "$verdict" | cut -d'|' -f3)
    ok "Real completion received (${served})."
    success_screen "$owui_port" "$served" "$body"
    return 0
  else
    err "Readiness completion FAILED: ${verdict#FAIL|}"
    ui_note "The gateway is live but no model answered. In free mode this" \
            "usually means: no free cloud key AND the local model hasn't" \
            "finished pulling. Fix:" \
            "  docker exec ${proj:-aef2}_ollama ollama pull $(_envget OLLAMA_DEFAULT_MODEL llama3.2:latest)" \
            "then re-run:  ./scripts/onboard.sh --readiness-only"
    return 1
  fi
}

success_screen() {
  local owui_port="$1" served="$2" body="$3"
  local url="http://localhost:${owui_port}"
  if [[ "$UI" == "gum" ]]; then
    printf '%s\n' \
      "✓  YOUR AI IS READY" "" \
      "Open WebUI:  ${url}" \
      "Answered by: ${served}" \
      "It said:     \"${body}\"" \
      | gum style --border double --padding "1 3" --border-foreground 46 --foreground 46
  else
    echo
    echo "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo "${BOLD}${GREEN}  ║   ✓  YOUR AI IS READY                                    ║${NC}"
    echo "${BOLD}${GREEN}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "   ${BOLD}Chat now →${NC}  ${CYAN}${url}${NC}"
    echo "   Answered by: ${served}"
    echo "   It said:     \"${body}\""
    echo
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
#  MAIN
# ═════════════════════════════════════════════════════════════════════════════
main() {
  if [[ "$READINESS_ONLY" == true ]]; then
    readiness_gate; exit $?
  fi

  ui_header "AEF2 · Local AI Stack — Onboarding"
  info "UI backend: ${BOLD}${UI}${NC}   ·   env file: ${ENV_FILE}"
  [[ "$UI" == "plain" ]] && warn "For a nicer experience install 'gum' (charmbracelet/gum)."

  require_tty_or_path
  detect_prereqs
  choose_path
  generate_env

  if [[ "$SKIP_BRINGUP" == true ]]; then
    ok "Configuration written to ${ENV_FILE}."
    ui_note "--skip-bringup set: not starting Docker." \
            "To finish:  ./scripts/onboard.sh --env-file '${ENV_FILE}'" \
            "Readiness gate (against a running stack):" \
            "  ./scripts/onboard.sh --readiness-only"
    exit 0
  fi

  bring_up
  readiness_gate
}

main "$@"
