# Skill: Surreal Memory
**Trigger:** User wants to store, retrieve, query, or graph-traverse knowledge in SurrealDB — the stack's central multi-model database.

## Overview
SurrealDB serves as the durable long-term memory and knowledge graph layer for the AEF2 stack. This skill handles structured knowledge storage (documents, entities, relations, KV), graph traversal, and hybrid queries combining SQL + graph + vector operations.

## Connection Details
- **Endpoint:** `http://surrealdb:8000/sql`
- **Auth:** `Authorization: Basic <base64(SURREALDB_USER:SURREALDB_PASSWORD)>`
- **Namespace:** `aef2`
- **Database:** `memory` (primary), `projects` (project-scoped data), `logs` (audit trail)

## Core Namespaces & Tables

### `aef2/memory` — Agent episodic memory
```surql
-- Define memory schema
DEFINE TABLE memory SCHEMAFULL;
DEFINE FIELD content    ON memory TYPE string;
DEFINE FIELD source     ON memory TYPE string;       -- "hermes", "n8n", "user"
DEFINE FIELD tags       ON memory TYPE array<string>;
DEFINE FIELD embedding  ON memory TYPE array<float>; -- for vector search
DEFINE FIELD created_at ON memory TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON memory TYPE datetime VALUE time::now();
DEFINE INDEX memory_tags ON memory COLUMNS tags;
```

### `aef2/memory` — Entity graph
```surql
DEFINE TABLE entity SCHEMAFULL;
DEFINE FIELD name     ON entity TYPE string;
DEFINE FIELD type     ON entity TYPE string;  -- person, project, tool, concept
DEFINE FIELD metadata ON entity TYPE object;
DEFINE FIELD created_at ON entity TYPE datetime DEFAULT time::now();

DEFINE TABLE relates_to SCHEMAFULL TYPE RELATION FROM entity TO entity;
DEFINE FIELD weight ON relates_to TYPE float DEFAULT 1.0;
DEFINE FIELD context ON relates_to TYPE string;
```

## Common Operations

### Store a fact
```surql
CREATE memory SET
  content = "the Chairman prefers dark mode in all UIs",
  source = "user",
  tags = ["preference", "ui"],
  created_at = time::now();
```

### Search by tag
```surql
SELECT * FROM memory WHERE tags CONTAINS "preference" ORDER BY created_at DESC LIMIT 10;
```

### Full-text search
```surql
SELECT * FROM memory WHERE content @@ "dark mode" LIMIT 5;
```

### Create entity + relation
```surql
LET $owner = (CREATE entity SET name = "the Chairman", type = "person", metadata = {role: "owner"});
LET $aef2  = (CREATE entity SET name = "AEF2", type = "project", metadata = {status: "active"});
RELATE $owner->relates_to->$aef2 SET context = "creator", weight = 1.0;
```

### Graph traversal — "what does the Chairman work on?"
```surql
SELECT ->relates_to->entity.name AS projects
FROM entity
WHERE name = "the Chairman" AND type = "person";
```

### Hybrid: entities related to a topic + recent memories about it
```surql
SELECT entity.name, entity.type, memory.content, memory.created_at
FROM entity, memory
WHERE entity.name @@ "docker"
   OR memory.content @@ "docker"
ORDER BY memory.created_at DESC
LIMIT 20;
```

## MCP Tool Invocation
Use the `surrealdb` MCP server for all queries:
```json
{
  "tool": "query",
  "namespace": "aef2",
  "database": "memory",
  "query": "SELECT * FROM memory WHERE tags CONTAINS $tag LIMIT $n",
  "vars": {"tag": "project", "n": 10}
}
```

## Conventions
- Always set `source` to identify which agent/service created a record
- Tag all entities with at minimum: `type`, `project` or `domain`, `date`
- Use `relates_to` for bidirectional links; use `depends_on`, `created_by`, `part_of` for directional
- Archive old memories: move to `aef2/archive` namespace after 90 days of no access

## When to use SurrealDB vs Qdrant
| SurrealDB | Qdrant |
|---|---|
| Structured facts, entities, relations | Unstructured semantic search |
| Graph traversal | Nearest-neighbor vector queries |
| SQL + graph hybrid queries | RAG retrieval pipelines |
| Audit logs, metadata | Embedding-based similarity |
