# Skill: Docker Ops
**Trigger:** User wants to inspect, manage, troubleshoot, restart, or interact with Docker containers in the stack.

## Overview
Manages the AEF2 Docker stack using the `docker` MCP server (which has access to the Docker socket). Provides safe, structured container operations with guardrails against destructive actions.

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
All containers follow the pattern: `${COMPOSE_PROJECT_NAME:-aef2}_<service>`.
Examples: `aef2_hermes`, `aef2_litellm`, `aef2_postgres`, `aef2_n8n`

## Profile → Services Map
| Profile | Services |
|---|---|
| core | postgres, redis, surrealdb, qdrant, ollama, litellm, hermes, open-webui, mcpo, mcp-servers, searxng, homepage |
| automation | n8n, flowise |
| knowledge | trilium, affine, anything-llm, docling |
| memory | mem0, open-interpreter |
| extras | chromadb, weaviate |
| observability | langfuse, dozzle |
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

## Safety Guardrails
- **NEVER** execute `docker rm`, `docker rmi`, `docker system prune` without explicit user confirmation
- **NEVER** stop or restart `aef2_postgres`, `aef2_redis`, or `aef2_surrealdb` without warning that data services will be interrupted
- **ALWAYS** confirm before writing files inside containers
- **READ-ONLY by default**: inspect and logs operations need no confirmation; mutations (exec, restart) require user approval

## Stack Health Check Procedure
Run a full health sweep when user asks "is the stack healthy?":
1. List all running containers → check count vs expected
2. For each core service: check health status (`healthy` / `unhealthy` / `starting`)
3. Check Langfuse for recent errors (if observability profile active)
4. Report: ✅ healthy / ⚠️ degraded / ❌ down per service
