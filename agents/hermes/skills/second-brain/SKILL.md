# Skill: Second Brain
**Trigger:** User wants to capture, organize, retrieve, or connect knowledge in Trilium or AFFiNE.

## Overview
Manages the two-tier second brain: **Trilium** for hierarchical evergreen notes and task management; **AFFiNE** for collaborative docs, whiteboards, and databases. Hermes acts as the intelligent layer on top — auto-tagging, linking, and surfacing relevant notes.

## Service Endpoints
| Service | URL | Purpose |
|---|---|---|
| TriliumNext API | `http://trilium:8080/api` | CRUD notes, attributes, tree structure |
| AFFiNE | `http://affine:3010` | Docs and whiteboards (browser interaction) |

## Core Operations

### Capture a note (Trilium)
```http
POST http://trilium:8080/api/notes/<parentNoteId>/children
Authorization: Token <TRILIUM_API_TOKEN>
Content-Type: application/json

{
  "title": "<title>",
  "type": "text",
  "content": "<html_or_markdown_content>",
  "attributes": [
    {"type": "label", "name": "source", "value": "<origin>"},
    {"type": "label", "name": "date", "value": "<YYYY-MM-DD>"},
    {"type": "label", "name": "tag", "value": "<topic>"}
  ]
}
```

### Search notes (Trilium)
```http
GET http://trilium:8080/api/notes?search=<query>
Authorization: Token <TRILIUM_API_TOKEN>
```

### Link two notes (Trilium relation)
```http
POST http://trilium:8080/api/notes/<sourceId>/attributes
{"type": "relation", "name": "references", "value": "<targetNoteId>"}
```

### Auto-tag procedure
1. Retrieve note content via `GET /api/notes/<id>/content`
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
