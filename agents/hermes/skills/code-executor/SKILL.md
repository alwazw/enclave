# Skill: Code Executor
**Trigger:** User asks to run code, a script, a shell command, or wants programmatic computation.

## Overview
Routes all code execution through the Open Interpreter service (sandboxed, no host access). Supports Python, Bash, JavaScript, and SQL. Results are returned as structured output and optionally saved to `/agent-workspace`.

## Service Endpoint
```
Open Interpreter API: http://open-interpreter:8143
```

## Supported Languages
| Language | Use case |
|---|---|
| Python | Data analysis, file processing, API calls, ML inference |
| Bash | File ops, text processing, stack management commands |
| JavaScript | JSON manipulation, web scraping logic, utility scripts |
| SQL (Postgres) | Database queries via `postgres` MCP |
| SurrealQL | Graph/document queries via `surrealdb` MCP |

## Execution Procedure

### 1. Classify the request
- Is it pure computation? → Python/Bash
- Is it data retrieval? → SQL/SurrealQL via MCP (preferred — no sandbox needed)
- Is it file manipulation? → Python via sandbox + `filesystem` MCP for I/O

### 2. Write the code
Generate clean, commented code. For Python, always use `try/except` blocks.

### 3. Submit to Open Interpreter
```http
POST http://open-interpreter:8143/run
Content-Type: application/json

{
  "language": "python",
  "code": "...",
  "timeout": 30
}
```

### 4. Return results
- stdout → display as code block
- Files written → confirm path and offer to read back
- Errors → show stderr + suggest fix, retry once

## Safety Rules
- Never execute code that modifies Docker host filesystem outside `/agent-workspace`
- Never execute `docker rm`, `docker stop`, or `docker system prune` — use `docker-ops` skill instead
- Never write files containing credentials or secrets
- Max execution timeout: 60 seconds (raise if user explicitly requests long-running task)

## Common Patterns

### Quick Python snippet
```json
{"language": "python", "code": "import json\nprint(json.dumps({'result': 2+2}))"}
```

### Install a package (ephemeral, per session)
```json
{"language": "bash", "code": "pip install pandas --quiet"}
```

### Data analysis pipeline
1. Read CSV via `filesystem` MCP → get content
2. Write to `/agent-workspace/data.csv` 
3. Execute pandas analysis in sandbox
4. Return summary table + save chart if matplotlib used

## Output Conventions
- Always show the code that was executed (collapsed by default in response)
- Show stdout as a code block
- For file outputs, show the path and offer to ingest via `rag-ingest` skill
