"""Enclave open-interpreter server wrapper.

The classic PyPI `open-interpreter` package (last released 0.4.3, 2024-10-26 —
the upstream GitHub repo OpenInterpreter/open-interpreter has since been
repurposed into an unrelated Codex-fork project, so PyPI is the only stable
source for the real code-execution package this service needs) ships a real
FastAPI+uvicorn HTTP server via `interpreter.core.async_core.AsyncInterpreter`,
enabled with `pip install "open-interpreter[server]"` and normally started via
`interpreter --server` (see start_terminal_interface.py). That CLI path does
not let us add a `/health` route or point the model at our LiteLLM gateway
using this repo's env var names (OPENAI_BASE_URL / OPENAI_API_KEY /
INTERPRETER_DEFAULT_MODEL / SERVER_HOST / SERVER_PORT), so this thin wrapper
does what `--server` does, plus that wiring.

Confirmed against the AsyncInterpreter source (interpreter/core/async_core.py):
  - GET  /heartbeat            -> {"status": "alive"}   (unauthenticated by design)
  - POST /run {"language","code"}  -> {"output": [...]}  ONLY when
        INTERPRETER_INSECURE_ROUTES=true (this is a direct sandboxed exec —
        it calls computer.terminal.run() directly, no LLM involved). This is
        exactly the contract agents/hermes/skills/code-executor/SKILL.md
        documents: `POST http://open-interpreter:8143/run
        {"language": "...", "code": "...", "timeout": 30}`. The `timeout`
        field is accepted but currently ignored by upstream (not enforced
        server-side) — logged here as a known limitation.
  - POST /openai/chat/completions  -> OpenAI-compatible chat endpoint that
        DOES go through interpreter.llm (routed at OPENAI_BASE_URL via
        litellm), for future use if Hermes ever wants a "chat with the
        interpreter" flow instead of raw /run.
We add a GET /health route (the compose healthcheck's existing contract)
that mirrors /heartbeat, since upstream only ships /heartbeat.
"""

import os

from interpreter.core.async_core import AsyncInterpreter

SERVER_HOST = os.environ.get("SERVER_HOST", "0.0.0.0")
SERVER_PORT = int(os.environ.get("SERVER_PORT", "8143"))

# Enable the raw /run, /upload, /download routes (auth-gated by X-API-KEY if
# INTERPRETER_API_KEY is set; unset here since this service only sits behind
# backend-net, reached only by Hermes — matches the rest of the stack's
# internal-network trust boundary, e.g. registrar/ux-validate).
os.environ.setdefault("INTERPRETER_INSECURE_ROUTES", "true")

interpreter = AsyncInterpreter()

# ── Route code execution's model calls through LiteLLM, not directly at any
#    provider — same convention as every other agent in this stack. ─────────
base_url = os.environ.get("OPENAI_BASE_URL")
api_key = os.environ.get("OPENAI_API_KEY")
model = os.environ.get("INTERPRETER_DEFAULT_MODEL", "gpt-4o")

if base_url:
    interpreter.llm.api_base = base_url
if api_key:
    interpreter.llm.api_key = api_key
# litellm needs an explicit provider prefix to hit a custom api_base as an
# OpenAI-compatible endpoint instead of trying to resolve the bare name
# against a known provider's model list.
interpreter.llm.model = model if "/" in model else f"openai/{model}"

# INTERPRETER_SAFE_MODE=off (this stack's existing convention) means "do not
# gate on a human confirmation before running code" -> auto_run True. This
# only affects the /openai/chat/completions flow; /run always executes
# immediately regardless (see module docstring).
interpreter.auto_run = os.environ.get("INTERPRETER_SAFE_MODE", "off").lower() != "on"
interpreter.safe_mode = os.environ.get("INTERPRETER_SAFE_MODE", "off")


@interpreter.server.app.get("/health")
async def health():
    return {"status": "ok", "service": "enclave-open-interpreter"}


if __name__ == "__main__":
    interpreter.server.run(host=SERVER_HOST, port=SERVER_PORT)
