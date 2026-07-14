# Skill: Workflow Builder
**Trigger:** User wants to create, modify, inspect, or debug automation workflows in n8n or Flowise.

## Overview
Manages workflow automation across two engines: **n8n** (general automation, API integrations, scheduling) and **Flowise** (LLM chains, agent flows, RAG pipelines). Hermes can create, list, activate, and troubleshoot workflows via their APIs.

## Service Endpoints
| Service | Base URL | Auth |
|---|---|---|
| n8n API | `http://n8n:5678/api/v1` | `X-N8N-API-KEY: ${N8N_API_KEY}` |
| Flowise API | `http://flowise:3100/api/v1` | `Authorization: Bearer ${FLOWISE_API_KEY}` |

---

## n8n Operations

### List all workflows
```http
GET http://n8n:5678/api/v1/workflows
X-N8N-API-KEY: <N8N_API_KEY>
```

### Get a specific workflow
```http
GET http://n8n:5678/api/v1/workflows/<id>
```

### Create a workflow
```http
POST http://n8n:5678/api/v1/workflows
Content-Type: application/json
X-N8N-API-KEY: <N8N_API_KEY>

{"name": "<name>", "nodes": [...], "connections": {...}, "settings": {"executionOrder": "v1"}}
```

### Activate/deactivate
```http
PATCH http://n8n:5678/api/v1/workflows/<id>
{"active": true}
```

### Trigger a workflow manually
```http
POST http://n8n:5678/api/v1/workflows/<id>/execute
```

### Get execution history
```http
GET http://n8n:5678/api/v1/executions?workflowId=<id>&limit=20
```

## Common n8n Workflow Templates

### Daily digest (scheduled)
Nodes: `Schedule Trigger → HTTP Request (SearXNG) → LiteLLM Chat → Email/Notification`

### Document ingestion on file drop
Nodes: `Filesystem Watch → HTTP Request (Docling) → HTTP Request (Qdrant upsert) → Slack/webhook notify`

### Hermes task dispatcher
Nodes: `Webhook → Switch (by intent) → HTTP Request (Hermes API) → Respond`

---

## Flowise Operations

### List chatflows
```http
GET http://flowise:3100/api/v1/chatflows
Authorization: Bearer <FLOWISE_API_KEY>
```

### Create a chatflow
```http
POST http://flowise:3100/api/v1/chatflows
Content-Type: application/json

{"name": "<name>", "flowData": "<json_escaped_flow>"}
```

### Chat with a flow
```http
POST http://flowise:3100/api/v1/prediction/<chatflowId>
{"question": "<user_message>", "history": [...]}
```

## Decision: n8n vs Flowise?
| Use n8n when | Use Flowise when |
|---|---|
| Scheduling, cron, event-driven | LLM chain design, RAG pipeline |
| API integrations (webhooks, HTTP) | Visual agent builder |
| Multi-step business logic | Chatbot interface prototyping |
| Connecting non-AI services | Embedding + retrieval workflows |

## Workflow Creation Procedure
1. Understand the user's automation goal
2. Decompose into trigger → steps → output
3. Choose n8n or Flowise (see table above)
4. Generate the workflow JSON
5. POST to the appropriate API
6. Confirm activation
7. Offer to test with a sample execution
