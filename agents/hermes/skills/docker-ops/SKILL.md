# Skill: Docker Ops
**Trigger:** User wants to inspect, manage, troubleshoot, restart, or interact with Docker containers in the stack.

**Status: the `docker` MCP tool described below doesn't exist today.** `mcp-docker`
(`compose/ai-ml/mcp-servers/mcp-servers.yml`) is `profiles: [disabled]` — it needs a
`docker.sock` mount that hasn't been scoped down safely yet — and it isn't registered
in `agents/hermes/hermes-config.yaml`'s `mcp_servers` list even when running. Until a
safe docker MCP path exists, container operations go through direct shell access
(the operator's own terminal) rather than a Hermes-callable tool. This skill's
structured JSON tool calls below describe the intended design, not a currently
callable interface.

## Overview
Manages the Enclave Docker stack using the `docker` MCP server (which has access to the Docker socket). Provides safe, structured container operations with guardrails against destructive actions.

## Available Operations via `docker` MCP

### Inspect containers
```json
{"tool": "list_containers", "filters": {"status": "running"}}
{"tool": "inspect_container", "name": "<container_name>"}
{"tool": "container_stats", "name": "<container_name>"}
```

### Read logs
```json
{"tool": "get_logs", "name": "<container_name>", "tail": 100, "follow": false}
```

### Execute a command inside a container
```json
{"tool": "exec_command", "name": "<container_name>", "command": ["sh", "-c", "<cmd>"]}
```

### Restart a container
```json
{"tool": "restart_container", "name": "<container_name>"}
```

## Container Naming Convention
Containers are named directly after their service (no project prefix — see #24).
Examples: `hermes`, `litellm`, `postgres`, `n8n`

## Profile → Services Map
| Profile | Services |
|---|---|
| core | postgres, redis, surrealdb, qdrant, ollama, litellm, hermes, open-webui, mcpo, mcp-servers, searxng, homepage |
| automation | n8n, flowise |
| knowledge | trilium, affine, anything-llm, docling |
| memory | mem0 |
| extras | chromadb, weaviate |
| observability | langfuse, dozzle |
| disabled | open-interpreter (image doesn't exist upstream), mcp-surrealdb, mcp-docker |
| tools | portainer, cloudbeaver |

## Diagnostic Procedure (when a service is down)
1. `list_containers` — check if container is running/exited/restarting
2. `get_logs` with `tail: 200` — identify the error
3. `inspect_container` — check health status, exit code, env vars
4. Diagnose: common causes are:
   - DB not ready → check dependency healthchecks
   - Port conflict → check `ports` in inspect output
   - Missing env var → check environment section
   - Volume permission error → check mount paths
5. Propose fix → confirm with user → apply (restart or exec)

## Gotcha: `docker exec` into hermes defaults to HOME=/root, not /opt/data
A plain `docker exec hermes <cmd>` runs with `HOME=/root` (the container's own
ephemeral root filesystem) — it does NOT go through the `with-contenv`
wrapper the container's own supervised services use, which sets
`HOME=/opt/data` (the real persistent volume, `HERMES_HOME`). Any `hermes`
subcommand that reads/writes `~`-relative paths (`hermes doctor --fix`,
`hermes setup`, etc.) will silently target the wrong, non-persistent
location if you forget this — the command appears to succeed, but the fix
vanishes on the next container recreation (bit both #27 and #28 this way:
a prior session verified a fix "worked," but it had written to `/root/...`
instead of `/opt/data/...`). Always prefix: `HOME=/opt/data hermes <cmd>`.

## Safety Guardrails
- **NEVER** execute `docker rm`, `docker rmi`, `docker system prune` without explicit user confirmation
- **NEVER** stop or restart `postgres`, `redis`, or `surrealdb` without warning that data services will be interrupted
- **ALWAYS** confirm before writing files inside containers
- **READ-ONLY by default**: inspect and logs operations need no confirmation; mutations (exec, restart) require user approval

## Stack Health Check Procedure
Run a full health sweep when user asks "is the stack healthy?":
1. List all running containers → check count vs expected
2. For each core service: check health status (`healthy` / `unhealthy` / `starting`)
3. Check Langfuse for recent errors (if observability profile active)
4. Report: ✅ healthy / ⚠️ degraded / ❌ down per service
