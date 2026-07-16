# Enclave open-interpreter — built from the real PyPI package (§ open-interpreter[server]).
#
# WHY BUILD, NOT PULL: openinterpreter/open-interpreter:latest does not exist on
# Docker Hub (Open Interpreter has never published an official image) — that bad
# reference was aborting `docker compose pull` for the ENTIRE stack. The upstream
# GitHub repo (OpenInterpreter/open-interpreter) has ALSO since been repurposed
# into an unrelated Codex-fork project (Rust/TS coding CLI) — its current HEAD is
# not the Python package this compose file's env vars/healthcheck were written
# against. PyPI still serves the real, last-published Python package (0.4.3,
# 2024-10-26) which contains the actual FastAPI/uvicorn HTTP server
# (interpreter.core.async_core.AsyncInterpreter) this service needs. We pin that
# version explicitly rather than floating on a moving/renamed upstream.
FROM python:3.11-slim

WORKDIR /app

# git: some optional interpreter language backends shell out to it during
# environment probing; curl: compose healthcheck.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl \
    && rm -rf /var/lib/apt/lists/*

# [server] extra pulls in fastapi/uvicorn/janus (the HTTP server deps, not
# installed by the bare package). Pinned to the last real PyPI release.
RUN pip install --no-cache-dir "open-interpreter[server]==0.4.3"

COPY server.py .

EXPOSE 8143

CMD ["python", "server.py"]
