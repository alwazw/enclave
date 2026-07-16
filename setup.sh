#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# AEF2 Local AI Stack — Bootstrap Script (Linux / macOS / WSL)
# Usage: chmod +x setup.sh && ./setup.sh [--profile core] [--pull-models]
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
step() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}"; }

# ── Argument Parsing ──────────────────────────────────────────────────────────
PROFILES="core"
PULL_MODELS=false
SKIP_PULL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile|-p) PROFILES="$2"; shift 2 ;;
    --pull-models) PULL_MODELS=true; shift ;;
    --skip-pull)   SKIP_PULL=true; shift ;;
    --help|-h)
      echo "Usage: $0 [--profile PROFILE] [--pull-models] [--skip-pull]"
      echo "  --profile     Comma-separated profiles: core,automation,knowledge,memory,extras,observability,tools"
      echo "  --pull-models Pull default Ollama models after stack starts"
      echo "  --skip-pull   Skip Docker image pulls (use cached images)"
      exit 0 ;;
    *) warn "Unknown argument: $1"; shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Shared helpers (generic — no host-specific values baked in) ────────────────

# set_env_var VAR VALUE — update (or append, if missing) VAR=VALUE in .env.
# Never logs the value for anything that looks like a secret; callers of this helper in this
# script only ever pass non-secret config (IPs, thread counts, timeouts).
set_env_var() {
  local var="$1" val="$2" esc
  esc=$(printf '%s\n' "$val" | sed 's/[[\.*^$()+?{|]/\\&/g')
  if grep -qE "^${var}=" .env 2>/dev/null; then
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s|^${var}=.*|${var}=${esc}|" .env
    else
      sed -i "s|^${var}=.*|${var}=${esc}|" .env
    fi
  else
    echo "${var}=${val}" >> .env
  fi
}

# check_disk_headroom REQUIRED_GB LABEL — best-effort warning (not exact accounting) before a
# large pull. Returns 1 (and, if interactive, offers to skip) when free space looks tight.
check_disk_headroom() {
  local required_gb="$1" label="$2" avail_kb avail_gb
  avail_kb=$(df -Pk . 2>/dev/null | awk 'NR==2{print $4}')
  avail_gb=$(( avail_kb / 1024 / 1024 ))
  if (( avail_gb < required_gb )); then
    warn "Low disk headroom: ~${avail_gb}GB free, ${label} may need ~${required_gb}GB+."
    if [[ -t 0 ]]; then
      local ans=""
      read -r -p "Continue anyway? [y/N] " ans || ans=""
      if [[ ! "$ans" =~ ^[Yy] ]]; then
        warn "Skipping: ${label}"
        return 1
      fi
    else
      warn "Non-interactive — continuing anyway; this may fail with ENOSPC. Free up space or re-run with more headroom if it does."
    fi
  else
    info "Disk headroom OK: ~${avail_gb}GB free (~${required_gb}GB estimated for ${label})"
  fi
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${CYAN}"
echo "  ┌─────────────────────────────────────────────┐"
echo "  │        AEF2 Local AI Stack — Setup          │"
echo "  │  Profile: ${PROFILES}                              │"
echo "  └─────────────────────────────────────────────┘"
echo -e "${NC}"

# ── Step 1: Prerequisites ─────────────────────────────────────────────────────
step "Checking prerequisites"

check_cmd() {
  if command -v "$1" &>/dev/null; then
    log "$1 found: $(command -v "$1")"
  else
    err "$1 is required but not installed. Please install it and re-run."
  fi
}

check_cmd docker
check_cmd docker compose 2>/dev/null || check_cmd "docker-compose"

DOCKER_COMPOSE_CMD="docker compose"
if ! docker compose version &>/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker-compose"
  warn "Using legacy docker-compose. Upgrade to Docker Compose V2 for best results."
fi

# Docker running?
docker info &>/dev/null || err "Docker daemon is not running. Start Docker and re-run."
log "Docker daemon is running"

# ── Step 2: Environment file ──────────────────────────────────────────────────
step "Setting up environment"

if [[ ! -f ".env" ]]; then
  if [[ ! -f ".env.example" ]]; then
    err ".env.example not found. Are you running from the AEF2 repo root?"
  fi
  cp .env.example .env
  log "Created .env from .env.example"
else
  warn ".env already exists — skipping copy (diff with .env.example to check for new variables)"
fi

# ── Step 2b: Detect HOST_IP ───────────────────────────────────────────────────
# Generic, per-host detection — no value here is tuned to any specific machine.
step "Detecting host IP address"

detect_host_ip() {
  local candidates=() line iface addr

  if command -v ip &>/dev/null; then
    # `ip -4 -o addr show`: col2=iface, col4=addr/cidr. Exclude loopback and any
    # container-network bridge (docker0, br-*, veth*) — those are not the host's LAN address.
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      iface=$(awk '{print $2}' <<< "$line")
      addr=$(awk '{print $4}' <<< "$line")
      addr="${addr%%/*}"
      case "$iface" in
        lo|docker0|br-*|veth*) continue ;;
      esac
      [[ -n "$addr" ]] && candidates+=("$addr")
    done < <(ip -4 -o addr show 2>/dev/null)
  fi

  if [[ ${#candidates[@]} -eq 0 ]] && command -v hostname &>/dev/null; then
    # Fallback for minimal images without `ip`: hostname -I can't be filtered by interface
    # name, so just drop loopback and the well-known Docker default bridge subnet (172.17.x).
    local a
    for a in $(hostname -I 2>/dev/null); do
      [[ "$a" == 127.* || "$a" == 172.17.* ]] && continue
      candidates+=("$a")
    done
  fi

  if [[ ${#candidates[@]} -eq 0 ]]; then
    warn "Could not auto-detect a host IP (no non-loopback, non-docker-bridge interface found) — leaving HOST_IP as-is in .env"
    return
  fi

  local chosen=""
  if [[ ${#candidates[@]} -eq 1 ]]; then
    chosen="${candidates[0]}"
    log "Detected a single candidate host IP: $chosen — using it automatically"
  else
    if [[ -t 0 ]]; then
      echo "Multiple network interfaces found. Which is this machine's real LAN IP?"
      local i=1 c
      for c in "${candidates[@]}"; do
        echo "  $i) $c"
        i=$((i + 1))
      done
      local sel=""
      read -r -p "Choose [1-${#candidates[@]}] (default: 1): " sel || sel=""
      sel="${sel:-1}"
      if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#candidates[@]} )); then
        sel=1
      fi
      chosen="${candidates[$((sel - 1))]}"
    else
      chosen="${candidates[0]}"
      warn "Multiple candidate IPs found (${candidates[*]}), running non-interactively — defaulting to the first: $chosen"
    fi
  fi

  set_env_var HOST_IP "$chosen"
  log "HOST_IP set to $chosen in .env"
}

detect_host_ip

# ── Step 2c: Detect GPU ───────────────────────────────────────────────────────
# NVIDIA-only, opt-in. Never required — CPU-only remains the default for any host without one.
step "Detecting GPU"

GPU_FLAG=""
detect_gpu() {
  if command -v nvidia-smi &>/dev/null && nvidia-smi -L 2>/dev/null | grep -q '^GPU'; then
    local gpu_name
    gpu_name=$(nvidia-smi -L 2>/dev/null | head -1)
    log "NVIDIA GPU detected: $gpu_name"
    local use_gpu=true
    if [[ -t 0 ]]; then
      local ans=""
      read -r -p "Enable GPU acceleration for Ollama? [Y/n] " ans || ans=""
      [[ "$ans" =~ ^[Nn] ]] && use_gpu=false
    else
      info "Running non-interactively — enabling GPU acceleration automatically (safe, opt-in overlay)."
    fi
    if [[ "$use_gpu" == true ]]; then
      GPU_FLAG="-f compose/ai-ml/ollama/ollama.gpu.yml"
      log "GPU acceleration enabled — will apply compose/ai-ml/ollama/ollama.gpu.yml"
    else
      info "GPU acceleration declined — Ollama will run CPU-only"
    fi
  else
    info "No usable NVIDIA GPU detected (nvidia-smi missing or reports no device) — Ollama will run CPU-only. This is fine; a GPU is never required."
  fi
}

detect_gpu

# ── Step 3: Generate secrets ──────────────────────────────────────────────────
step "Generating secrets for <CHANGE_ME> placeholders"

gen_secret() {
  # 32-byte random hex string
  head -c 32 /dev/urandom | xxd -p | tr -d '\n' 2>/dev/null \
    || openssl rand -hex 32 2>/dev/null \
    || python3 -c "import secrets; print(secrets.token_hex(32))"
}

gen_password() {
  # 16-char alphanumeric
  head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16 2>/dev/null \
    || openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16
}

# Replace all <CHANGE_ME> values with generated secrets in .env
CHANGED=0
while IFS= read -r line; do
  if [[ "$line" =~ ^([A-Z0-9_]+)=\<CHANGE_ME\>$ ]]; then
    VAR="${BASH_REMATCH[1]}"
    # Use different generators for passwords vs secrets
    if [[ "$VAR" =~ (PASSWORD|PASS)$ ]]; then
      SECRET=$(gen_password)
    else
      SECRET=$(gen_secret)
    fi
    # Escape for sed
    ESCAPED=$(printf '%s\n' "$SECRET" | sed 's/[[\.*^$()+?{|]/\\&/g')
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s|^${VAR}=<CHANGE_ME>|${VAR}=${ESCAPED}|" .env
    else
      sed -i "s|^${VAR}=<CHANGE_ME>|${VAR}=${ESCAPED}|" .env
    fi
    log "Generated secret for: $VAR"
    CHANGED=$((CHANGED + 1))
  fi
done < .env

[[ $CHANGED -gt 0 ]] && log "Generated $CHANGED secrets" || info "No <CHANGE_ME> placeholders found"

# ── Step 3b: Compute Ollama resource governance from this host's real CPU count ──
# Nothing here is a fixed number tuned to one machine — both values scale with `nproc`.
step "Computing Ollama resource limits for this host"

configure_ollama_resources() {
  local cores
  cores=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)

  # OLLAMA_NUM_THREADS: reserve roughly HALF the host's cores for Ollama and leave the other
  # half for the rest of the service mesh (Postgres, Redis, n8n, LiteLLM, Hermes, ...) sharing
  # this box, so one local inference run can't starve everything else of CPU. Floored at 1 so
  # this never computes to zero on a single-core host.
  local num_threads=$(( cores / 2 ))
  (( num_threads < 1 )) && num_threads=1

  # OLLAMA_NUM_PARALLEL: how many generations Ollama will run concurrently. Each parallel slot
  # roughly multiplies the loaded model's memory footprint, so this stays at the conservative
  # default of 1 unless the host has enough cores (>=8) to plausibly serve more than one
  # request without thrashing. This is a coarse heuristic, not a memory-aware calculation —
  # operators with unusual RAM/CPU ratios should tune it by hand in .env.
  local num_parallel=1
  (( cores >= 8 )) && num_parallel=2

  set_env_var OLLAMA_NUM_THREADS "$num_threads"
  set_env_var OLLAMA_NUM_PARALLEL "$num_parallel"
  log "Detected ${cores} CPU core(s) — set OLLAMA_NUM_THREADS=${num_threads}, OLLAMA_NUM_PARALLEL=${num_parallel} in .env"

  # OLLAMA_KEEP_ALIVE isn't CPU-derived, just shortened from the old hardcoded 24h so an idle
  # model doesn't permanently pin RAM on a shared host. Only set if genuinely absent (respects
  # an already-customized .env, e.g. one hand-edited or copied from an older .env.example).
  if ! grep -qE '^OLLAMA_KEEP_ALIVE=' .env 2>/dev/null; then
    set_env_var OLLAMA_KEEP_ALIVE "30m"
    log "OLLAMA_KEEP_ALIVE defaulted to 30m in .env (override there for a longer/shorter cache window)"
  fi
}

configure_ollama_resources

# ── Step 4: Create directories ────────────────────────────────────────────────
step "Creating runtime directories"

DIRS=(
  "data/postgres"
  "data/redis"
  "data/surrealdb"
  "data/qdrant"
  "data/chromadb"
  "data/weaviate"
  "data/ollama"
  "data/hermes"
  "data/open-webui"
  "data/n8n"
  "data/flowise"
  "data/mem0"
  "data/langfuse"
  "data/affine"
  "data/trilium"
  "data/anythingllm"
  "data/portainer"
  "data/cloudbeaver"
  "agent-workspace"
  "logs"
)

for dir in "${DIRS[@]}"; do
  mkdir -p "$dir"
  log "Created: $dir"
done

# ── Step 5: Docker networks ────────────────────────────────────────────────────
step "Creating Docker networks"

# Read project name from .env
PROJECT_NAME=$(grep -E '^COMPOSE_PROJECT_NAME=' .env | cut -d= -f2 | tr -d '"' | tr -d "'")
PROJECT_NAME="${PROJECT_NAME:-aef2}"
info "Project name: $PROJECT_NAME"

create_network() {
  local name="$1"
  if docker network inspect "$name" &>/dev/null; then
    info "Network already exists: $name"
  else
    docker network create "$name" --driver bridge
    log "Created network: $name"
  fi
}

create_network "${PROJECT_NAME}_frontend"
create_network "${PROJECT_NAME}_backend"
create_network "${PROJECT_NAME}_database"

# ── Step 6: Docker volumes ─────────────────────────────────────────────────────
step "Creating Docker volumes"

# Volume list is derived from the compose config itself (all profiles) so it can
# never drift from the compose files again. Volumes are external+unprefixed.
ALL_PROFILE_FLAGS="--profile core --profile automation --profile knowledge --profile memory --profile extras --profile observability --profile tools"
# shellcheck disable=SC2086
mapfile -t VOLUMES < <($DOCKER_COMPOSE_CMD -f local-stack.yml $ALL_PROFILE_FLAGS config --volumes 2>/dev/null | sort -u)
[[ ${#VOLUMES[@]} -gt 0 ]] || { echo "FATAL: could not derive volume list from compose config" >&2; exit 1; }

for vol in "${VOLUMES[@]}"; do
  FULL_VOL="${vol}"  # volumes are declared external+unprefixed in compose files
  if docker volume inspect "$FULL_VOL" &>/dev/null; then
    info "Volume already exists: $FULL_VOL"
  else
    docker volume create "$FULL_VOL"
    log "Created volume: $FULL_VOL"
  fi
done

# ── Step 7: Pull images (optional) ────────────────────────────────────────────
if [[ "$SKIP_PULL" == false ]]; then
  step "Checking disk space before pulling images"
  # Flat, conservative floor for "a handful of container images" — we can't cheaply know exact
  # image sizes without pulling manifests over the network first, so this is a rough order-of-
  # magnitude guard against repeating tonight's disk-full incident, not precise accounting.
  if check_disk_headroom 10 "pulling Docker images for profile(s): $PROFILES"; then
    step "Pulling Docker images for profile: $PROFILES"
    PROFILE_FLAGS=""
    IFS=',' read -ra PROFILE_ARRAY <<< "$PROFILES"
    for p in "${PROFILE_ARRAY[@]}"; do
      PROFILE_FLAGS+=" --profile $p"
    done
    # shellcheck disable=SC2086
    $DOCKER_COMPOSE_CMD -f local-stack.yml $GPU_FLAG $PROFILE_FLAGS pull --ignore-pull-failures || warn "Some images failed to pull — they will be pulled on first start"
  else
    info "Skipping image pull due to low disk space (re-run once you've freed space, or pass --skip-pull to bypass this check)."
    SKIP_PULL=true
  fi
else
  info "Skipping image pull (--skip-pull)"
fi

# ── Step 7.5: Pre-seed auth files that must exist before first container create ──
# Dozzle/Portainer bind-mount a single host file into the container. If that host
# path doesn't exist yet, Docker auto-creates it as a DIRECTORY instead of a file,
# which then breaks the container permanently until the container is recreated
# after fixing it by hand. Must run before `up -d` ever creates these containers.
step "Pre-seeding Dozzle/Portainer auth files"
bash "$SCRIPT_DIR/scripts/init-dozzle-auth.sh" || warn "Dozzle auth pre-seed failed — dozzle may fail to start (see scripts/init-dozzle-auth.sh)"
bash "$SCRIPT_DIR/scripts/init-portainer-auth.sh" || warn "Portainer auth pre-seed failed — portainer may fail to start (see scripts/init-portainer-auth.sh)"

# ── Step 8: Start the stack ───────────────────────────────────────────────────
step "Starting AEF2 stack (profiles: $PROFILES)"

PROFILE_FLAGS=""
IFS=',' read -ra PROFILE_ARRAY <<< "$PROFILES"
for p in "${PROFILE_ARRAY[@]}"; do
  PROFILE_FLAGS+=" --profile $p"
done

# shellcheck disable=SC2086
$DOCKER_COMPOSE_CMD -f local-stack.yml $GPU_FLAG $PROFILE_FLAGS up -d --remove-orphans

log "Stack started!"

# ── Step 8b: Post-start bootstrap (owner/admin account claims) ────────────────
# Several services ship with an unclaimed admin/owner account and NO enforcement
# that stops the first LAN visitor from claiming it instead of the real operator.
# Idempotent — safe to re-run, no-op if already claimed. Open WebUI is core (always
# runs); the rest are gated to their profile.
step "Claiming Open WebUI admin account"
if [[ -x "$SCRIPT_DIR/scripts/init-open-webui-admin.sh" ]]; then
  "$SCRIPT_DIR/scripts/init-open-webui-admin.sh" || warn "Open WebUI admin claim failed — first LAN visitor can still claim it (retry manually: scripts/init-open-webui-admin.sh)"
else
  warn "scripts/init-open-webui-admin.sh not found — skipping Open WebUI admin bootstrap"
fi
if [[ ",$PROFILES," == *",automation,"* ]]; then
  step "Claiming n8n owner account"
  if [[ -x "$SCRIPT_DIR/scripts/init-n8n-owner.sh" ]]; then
    "$SCRIPT_DIR/scripts/init-n8n-owner.sh" || warn "n8n owner claim failed — first LAN visitor to n8n can still claim it (retry manually: scripts/init-n8n-owner.sh)"
  else
    warn "scripts/init-n8n-owner.sh not found — skipping n8n owner bootstrap"
  fi
  step "Bootstrapping Flowise admin account"
  if [[ -x "$SCRIPT_DIR/scripts/init-flowise-admin.sh" ]]; then
    "$SCRIPT_DIR/scripts/init-flowise-admin.sh" || warn "Flowise admin bootstrap failed — retry manually: scripts/init-flowise-admin.sh"
  else
    warn "scripts/init-flowise-admin.sh not found — skipping Flowise admin bootstrap"
  fi
fi
if [[ ",$PROFILES," == *",knowledge,"* ]]; then
  step "Initializing TriliumNext"
  bash "$SCRIPT_DIR/scripts/init-trilium.sh" || warn "Trilium init failed — retry manually: scripts/init-trilium.sh"
fi

# ── Step 9: Pull Ollama models ────────────────────────────────────────────────
if [[ "$PULL_MODELS" == true ]]; then
  step "Pulling default Ollama models (this may take a while)"

  # Driven live by .env, not a fixed list — pulls whichever of these four vars are actually
  # set. Blank or `#`-commented (this repo's existing convention for disabling a var) = skipped.
  # This keeps OLLAMA_CODE_MODEL/OLLAMA_VISION_MODEL from being dead, misleading declarations.
  MODEL_VARS=(OLLAMA_DEFAULT_MODEL OLLAMA_EMBED_MODEL OLLAMA_CODE_MODEL OLLAMA_VISION_MODEL)
  DEFAULT_MODELS=()
  for v in "${MODEL_VARS[@]}"; do
    val=$(grep -E "^${v}=" .env 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" | sed 's/[[:space:]]*$//')
    [[ -n "$val" ]] && DEFAULT_MODELS+=("$val")
  done
  if [[ ${#DEFAULT_MODELS[@]} -eq 0 ]]; then
    warn "No OLLAMA_*_MODEL vars set in .env — falling back to llama3.2:latest + nomic-embed-text:latest"
    DEFAULT_MODELS=("llama3.2:latest" "nomic-embed-text:latest")
  fi
  info "Models queued to pull: ${DEFAULT_MODELS[*]}"

  # Rough, best-effort disk-headroom check before pulling — not exact accounting. Most Ollama
  # tags encode a parameter count (e.g. "32b", "3b"); at common Q4 quantization that's roughly
  # 0.6GB on disk per billion parameters. Tags with no parseable size (embeddings, "latest")
  # get a conservative flat estimate.
  estimate_model_size_gb() {
    local tag="$1" b
    if [[ "$tag" =~ ([0-9]+(\.[0-9]+)?)[bB]([^0-9]|$) ]]; then
      b="${BASH_REMATCH[1]}"
      awk -v b="$b" 'BEGIN{printf "%.0f", (b*0.6)+0.5}'
    elif [[ "$tag" == *embed* ]]; then
      echo 1
    else
      echo 3
    fi
  }
  total_estimate=0
  for model in "${DEFAULT_MODELS[@]}"; do
    total_estimate=$(( total_estimate + $(estimate_model_size_gb "$model") ))
  done

  if check_disk_headroom "$total_estimate" "pulling ${#DEFAULT_MODELS[@]} Ollama model(s)"; then
    info "Waiting for Ollama to be ready..."
    OLLAMA_PORT=$(grep -E '^OLLAMA_PORT=' .env | cut -d= -f2 | tr -d '"' | tr -d "'" | tr -d ' ')
    OLLAMA_PORT="${OLLAMA_PORT:-11434}"

    for i in {1..30}; do
      if curl -sf "http://localhost:${OLLAMA_PORT}/api/tags" &>/dev/null; then
        log "Ollama is ready"
        break
      fi
      [[ $i -eq 30 ]] && warn "Ollama not ready after 60s — skipping model pulls"
      sleep 2
    done

    for model in "${DEFAULT_MODELS[@]}"; do
      info "Pulling $model..."
      docker exec "${PROJECT_NAME}_ollama" ollama pull "$model" \
        && log "Pulled: $model" \
        || warn "Failed to pull: $model (retry manually: docker exec ${PROJECT_NAME}_ollama ollama pull $model)"
    done
  else
    warn "Skipping Ollama model pulls due to low disk space. Pull manually once you've freed space: docker exec ${PROJECT_NAME}_ollama ollama pull <model>"
  fi
fi

# ── Step 10: Health check ─────────────────────────────────────────────────────
step "Checking service health"

sleep 5

HOMEPAGE_PORT=$(grep -E '^HOMEPAGE_PORT=' .env | cut -d= -f2 | tr -d '"' | tr -d "'" | tr -d ' ')
HOMEPAGE_PORT="${HOMEPAGE_PORT:-3030}"

OPENWEBUI_PORT=$(grep -E '^OPENWEBUI_PORT=' .env | cut -d= -f2 | tr -d '"' | tr -d "'" | tr -d ' ')
OPENWEBUI_PORT="${OPENWEBUI_PORT:-3000}"

HERMES_PORT=$(grep -E '^HERMES_PORT=' .env | cut -d= -f2 | tr -d '"' | tr -d "'" | tr -d ' ')
HERMES_PORT="${HERMES_PORT:-8642}"

# shellcheck disable=SC2086
$DOCKER_COMPOSE_CMD -f local-stack.yml $PROFILE_FLAGS ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════╗"
echo -e "║            AEF2 Stack is UP! 🚀                           ║"
echo -e "╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Dashboard:${NC}   http://localhost:${HOMEPAGE_PORT}"
echo -e "  ${BOLD}Open WebUI:${NC}  http://localhost:${OPENWEBUI_PORT}"
echo -e "  ${BOLD}Hermes:${NC}      http://localhost:${HERMES_PORT}"
echo -e "  ${BOLD}LiteLLM:${NC}     http://localhost:4000/ui"
echo ""
echo -e "  ${CYAN}Useful commands:${NC}"
echo -e "  ${YELLOW}docker compose -f local-stack.yml logs -f hermes${NC}  # tail Hermes logs"
echo -e "  ${YELLOW}docker compose -f local-stack.yml ps${NC}              # container status"
echo -e "  ${YELLOW}docker exec aef2_ollama ollama pull llama3.1:8b${NC}   # pull a model"
echo ""
