# Skill: Web Researcher
**Trigger:** User asks to research a topic, find information online, summarize a URL, or compare options from the web.

## Overview
Conducts structured web research using SearXNG (private, local), reached through Hermes's own built-in `web-searxng` plugin (not the `fetch` MCP — `fetch` is real but isn't registered as a Hermes tool today; see `docker-ops` skill). Synthesizes results into cited, actionable reports. Optionally ingests findings into the knowledge base.

## Research Procedure

### Phase 1 — Query Decomposition
Break the user's request into 2–4 focused search queries. Example:
- User: "best open-source vector databases for local deployment"
- Queries: ["open source vector database comparison 2025", "qdrant vs weaviate vs chroma performance", "self-hosted vector db docker deployment"]

### Phase 2 — Search (Hermes's built-in SearXNG plugin)
```http
GET http://searxng:8080/search?q=<encoded_query>&format=json
```
No auth header — this is Hermes's own `web-searxng` plugin (`hermes-config.yaml`'s `web.backend: searxng`), not a call you issue through mcpo. Collect top 5 results per query. Deduplicate by domain.

### Phase 3 — Fetch & Extract
No `fetch` MCP tool is registered today (the `mcp-fetch` container is real but not wired into `hermes-config.yaml`'s `mcp_servers` list). Until it is, read promising URLs via whatever tool access is available (e.g. the `filesystem`/shell path, or ask the user to paste key content) rather than claiming a `fetch` tool call.
Prioritize: official docs > research papers > reputable tech blogs > forums.
Skip: paywalled content, thin pages, pure SEO spam.

### Phase 4 — Synthesize
1. Extract key facts, figures, dates, and claims from fetched content
2. Cross-reference across sources — note agreements and contradictions
3. Structure findings into: **Overview → Key Findings → Comparison Table (if applicable) → Recommendation → Sources**

### Phase 5 — Output
Present as a Markdown report with:
- Executive summary (3–5 sentences)
- Structured findings with inline citations [Source: URL]
- Comparison table if evaluating options
- Clear recommendation with rationale
- Full source list at the bottom

### Phase 6 — Optional: Save to knowledge base
Ask user: "Would you like me to save this research to your knowledge base?"
If yes → invoke `rag-ingest` skill with the synthesized report as input, collection: `web_research`.
If yes, also save to Trilium via `second-brain` skill.

## Source Quality Tiers
| Tier | Examples | Trust level |
|---|---|---|
| Primary | GitHub repos, official docs, arxiv papers | High |
| Secondary | HackerNews, Reddit r/selfhosted, tech blogs | Medium |
| Tertiary | General blogs, news articles | Low — verify |

## Anti-Patterns to Avoid
- Never cite search snippets alone — always fetch and verify the actual page
- Never present a single source as definitive — triangulate at least 3
- Never fabricate statistics — if a number can't be traced to a source, flag it as unverified
- Do not include affiliate links or sponsored content in recommendations
