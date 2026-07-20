# Skill: RAG Ingest
**Trigger:** User wants to add documents, files, URLs, or raw text to the knowledge base.

## Overview
This skill handles the end-to-end pipeline for ingesting content into the vector store (Qdrant) so it becomes searchable via RAG in Open WebUI, AnythingLLM, and Hermes itself.

## Supported Input Types
| Type | How to handle |
|---|---|
| Local file (PDF, DOCX, MD, TXT) | Read via `filesystem` MCP → send to Docling API for parsing → chunk → embed → upsert to Qdrant |
| URL | Fetch with `fetch` MCP → extract text → chunk → embed → upsert to Qdrant |
| Plain text | Chunk directly → embed → upsert to Qdrant |
| GitHub repo/file | Use `github` MCP to read → chunk → embed → upsert to Qdrant |

## Step-by-Step Procedure

### 1. Identify the source
Ask the user if not clear: file path, URL, or paste text?

### 2. Parse the document
For PDFs and office docs, call the Docling service:
```
POST http://docling:5001/convert
Content-Type: application/json
{"source": "<path_or_url>", "format": "markdown"}
```
For plain text/markdown, skip this step.

### 3. Chunk the content
Split into ~512-token chunks with 64-token overlap. Preserve headings as chunk metadata.

### 4. Embed
Route embedding through LiteLLM:
```
POST http://litellm:4000/v1/embeddings
{"model": "openai/morpheus-embedding-model", "input": ["<chunk1>", "<chunk2>"]}
```

### 5. Upsert to Qdrant
```
PUT http://qdrant:6333/collections/knowledge_base/points
{
  "points": [
    {"id": "<uuid>", "vector": [...], "payload": {"text": "...", "source": "...", "chunk_index": 0}}
  ]
}
```

### 6. Confirm
Report: total chunks ingested, collection name, source identifier.

## Collections Convention
| Collection | Purpose |
|---|---|
| `knowledge_base` | General user documents |
| `hermes_memory` | Manually-ingested context about Hermes/agent history — **not** Hermes's own live memory. Hermes's real persistent memory is a local SQLite (`holographic`) store, unrelated to Qdrant (see README's Memory Architecture section). |
| `code_index` | Code files and snippets |
| `web_research` | Fetched web content |

## Error Handling
- Docling unavailable → fall back to plain text extraction with `filesystem` MCP
- Qdrant collection not found → create it first with cosine metric, 768 dimensions (matches `openai/morpheus-embedding-model`'s Nomic Embed Text backend — check the embedding model's actual dims if it changes)
- Duplicate detection → check by source URL/path hash before ingesting
