# Skill: Second Brain
**Trigger:** User wants to capture, organize, retrieve, or connect knowledge in Trilium or AFFiNE.

## Overview
Manages the two-tier second brain: **Trilium** for hierarchical evergreen notes and task management; **AFFiNE** for collaborative docs, whiteboards, and databases. Hermes acts as the intelligent layer on top — auto-tagging, linking, and surfacing relevant notes.

## Service Endpoints
| Service | URL | Purpose |
|---|---|---|
| TriliumNext ETAPI | `http://trilium:8080/etapi` | CRUD notes, attributes, tree structure. `/api/setup/*` is a separate, unauthenticated first-run wizard path — not used for regular note CRUD. |
| AFFiNE | `http://affine:3010` | Docs and whiteboards (browser interaction) |

## Authentication (Trilium)
There is no `TRILIUM_API_TOKEN` env var — the only stored credential is `TRILIUM_PASSWORD` (`.env.example`). Obtain a session token per use via:
```http
POST http://trilium:8080/etapi/auth/login
Content-Type: application/json

{"password": "<TRILIUM_PASSWORD>", "tokenName": "hermes-second-brain"}
```
Response includes `authToken` — use it as `Authorization: <authToken>` (ETAPI's own scheme, not `Bearer`/`Token`) on subsequent calls.

## Core Operations

### Capture a note (Trilium)
```http
POST http://trilium:8080/etapi/create-note
Authorization: <authToken>
Content-Type: application/json

{
  "parentNoteId": "<parentNoteId>",
  "title": "<title>",
  "type": "text",
  "content": "<html_or_markdown_content>"
}
```
Add labels in a follow-up call:
```http
POST http://trilium:8080/etapi/attributes
Authorization: <authToken>
{"noteId": "<noteId>", "type": "label", "name": "source", "value": "<origin>"}
```

### Search notes (Trilium)
```http
GET http://trilium:8080/etapi/notes?search=<query>
Authorization: <authToken>
```

### Link two notes (Trilium relation)
```http
POST http://trilium:8080/etapi/attributes
Authorization: <authToken>
{"noteId": "<sourceId>", "type": "relation", "name": "references", "value": "<targetNoteId>"}
```

### Auto-tag procedure
1. Retrieve note content via `GET /etapi/notes/<id>/content`
2. Ask LiteLLM to extract 3–5 semantic tags
3. Add each as a label attribute via PATCH

## Decision Tree
```
User input
  ├── "add note / capture / remember this"  → Trilium capture
  ├── "find / recall / search notes"        → Trilium search
  ├── "link / connect / relate"             → Trilium relation
  ├── "whiteboard / diagram / canvas"       → AFFiNE (browser)
  ├── "doc / page / collaborative"          → AFFiNE (browser)
  └── "organize / tag / structure"          → Auto-tag + Trilium tree
```

## Inbox Convention
- All unsorted captures go to the `Inbox` note (find via `search=Inbox type=text`)
- Weekly review: move Inbox items to appropriate tree branches
- Tag convention: `#project`, `#reference`, `#area`, `#resource`, `#archive` (PARA method)

## Cross-linking with RAG
After saving a note to Trilium, also ingest it via the `rag-ingest` skill with:
- `source` = `trilium:<noteId>`
- `collection` = `knowledge_base`
This makes note content searchable from Open WebUI and AnythingLLM.
