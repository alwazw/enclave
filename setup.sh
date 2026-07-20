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

# Replace all <CHANGE_ME>/<CHANGE_ME_32CHARS> values with generated secrets in .env.
# (Both forms: N8N_ENCRYPTION_KEY ships as <CHANGE_ME_32CHARS> in .env.example --
# missing this second pattern would leave that literal placeholder string as n8n's
# real encryption key on a fresh setup.sh install.)
CHANGED=0
while IFS= read -r line; do
  if [[ "$line" =~ ^([A-Z0-9_]+)=\<CHANGE_ME(_32CHARS)?\>$ ]]; then
    VAR="${BASH_REMATCH[1]}"
    PLACEHOLDER="${BASH_REMATCH[0]#*=}"
    # Use different generators for passwords vs secrets
    if [[ "$VAR" =~ (PASSWORD|PASS)$ ]]; then
      SECRET=$(gen_password)
    else
      SECRET=$(gen_secret)
    fi
    # Escape for sed
    ESCAPED=$(printf '%s\n' "$SECRET" | sed 's/[[\.*^$()+?{|]/\\&/g')
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s|^${VAR}=${PLACEHOLDER}|${VAR}=${ESCAPED}|" .env
    else
      sed -i "s|^${VAR}=${PLACEHOLDER}|${VAR}=${ESCAPED}|" .env
    fi
    log "Generated secret for: $VAR"
    CHANGED=$((CHANGED + 1))
  fi
done < .env

[[ $CHANGED -gt 0 ]] && log "Generated $CHANGED secrets" || info "No <CHANGE_ME> placeholders found"

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
  step "Pulling Docker images for profile: $PROFILES"
  PROFILE_FLAGS=""
  IFS=',' read -ra PROFILE_ARRAY <<< "$PROFILES"
  for p in "${PROFILE_ARRAY[@]}"; do
    PROFILE_FLAGS+=" --profile $p"
  done
  # shellcheck disable=SC2086
  $DOCKER_COMPOSE_CMD -f local-stack.yml $PROFILE_FLAGS pull --ignore-pull-failures || warn "Some images failed to pull — they will be pulled on first start"
else
  info "Skipping image pull (--skip-pull)"
fi

# ── Step 8: Start the stack ───────────────────────────────────────────────────
step "Starting AEF2 stack (profiles: $PROFILES)"

PROFILE_FLAGS=""
IFS=',' read -ra PROFILE_ARRAY <<< "$PROFILES"
for p in "${PROFILE_ARRAY[@]}"; do
  PROFILE_FLAGS+=" --profile $p"
done

# shellcheck disable=SC2086
$DOCKER_COMPOSE_CMD -f local-stack.yml $PROFILE_FLAGS up -d --remove-orphans

log "Stack started!"

# ── Step 9: Pull Ollama models ────────────────────────────────────────────────
if [[ "$PULL_MODELS" == true ]]; then
  step "Pulling default Ollama models (this may take a while)"

  DEFAULT_MODELS=(
    "llama3.2:latest"
    "nomic-embed-text"
  )

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

  # #24 regression (container names dropped the ${PROJECT_NAME}_ prefix; this
  # exec target was never updated when that fix landed -- "ollama" is the
  # real live container name, not "${PROJECT_NAME}_ollama").
  for model in "${DEFAULT_MODELS[@]}"; do
    info "Pulling $model..."
    docker exec ollama ollama pull "$model" \
      && log "Pulled: $model" \
      || warn "Failed to pull: $model (retry manually: docker exec ollama ollama pull $model)"
  done
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
echo -e "  ${YELLOW}docker exec ollama ollama pull llama3.2:latest${NC}   # pull a model"
echo ""
