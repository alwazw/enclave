# Skill: Code Executor
**Trigger:** User asks to run code, a script, a shell command, or wants programmatic computation.

**Status: currently non-functional.** The upstream `openinterpreter/open-interpreter`
image this skill routes to doesn't exist on Docker Hub (`repository does not exist`)
— the service is `profiles: [disabled]` in `compose/ai-ml/open-interpreter/open-interpreter.yml`
and never starts under any real profile flag. This skill's procedure is documented as
originally designed; it needs either a working Open Interpreter build or a different
sandboxed-execution backend before it can actually run code. Until then, prefer the
`postgres` MCP tool directly for SQL, and the `filesystem` MCP tool for file I/O.

## Overview
Routes all code execution through the Open Interpreter service (sandboxed, no host access). Supports Python, Bash, JavaScript, and SQL. Results are returned as structured output and optionally saved to `/workspace`.

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
| SurrealQL | Graph/document queries — no live MCP path today, `surrealdb` MCP server is `disabled` (see `surreal-memory` skill) |

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
- Never execute code that modifies Docker host filesystem outside `/workspace`
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
2. Write to `/workspace/data.csv` 
3. Execute pandas analysis in sandbox
4. Return summary table + save chart if matplotlib used

## Output Conventions
- Always show the code that was executed (collapsed by default in response)
- Show stdout as a code block
- For file outputs, show the path and offer to ingest via `rag-ingest` skill
