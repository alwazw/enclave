---
name: memory-protocol
description: >-
  The corporate memory discipline for Enclave. Invoke when starting or
  ending a department-head invocation, when recording a decision, or when
  memory and the board disagree. Defines what goes in which memory file, the
  read-at-start / write-at-end cycle, and the rules that keep memory truthful
  and secret-free across all future sessions.
---
# memory-protocol — Enclave

Memory is what makes this corporation permanent. It is all git-versioned markdown; every
session, on any machine, wakes up with the company's full history.

## The files
| File | Owner | Contains |
|---|---|---|
| `memory/company.md` | CEO | Mission, current-state summary, stack, service/port map |
| `memory/roadmap.md` | head-of-product | Now / Next / Later + release plan |
| `memory/decisions.md` | CEO | Append-only decision log (never edit old entries) |
| `memory/departments/<dept>.md` | that head | Dept working memory: conventions, gotchas, open threads |

## The cycle (every department-head invocation)
1. **Start:** read your department file + skim the last ~20 lines of `decisions.md`.
2. **Work.**
3. **End:** append a dated entry (2–6 lines): what changed, what's open, anything the next
   invocation must know. Use `## YYYY-MM-DD` headers. Prune stale entries occasionally by
   summarizing them — memory should stay under ~200 lines per file.

## Decision log format (`memory/decisions.md`)
```
## 2026-07-08 — Postgres over SQLite for gallery metadata
Why: concurrent writers from importer + web app. Alternatives: SQLite+WAL (rejected: locking
under import bursts). Consequence: adds a service; backup task T-0041 covers it.
```

## Rules
1. **The board beats memory.** Task state lives in `pm/`, never in memory files. If they
   disagree, correct memory.
2. **Decisions are append-only.** Reversals get a new entry referencing the old one.
3. **No secrets, ever.** No passwords, tokens, keys, or connection strings with credentials.
   Reference where a secret lives ("in .env, gitignored"), never its value.
4. **Write for a stranger.** The reader is a future session with zero conversational context.
5. **Cross-department facts** (port registry, service inventory) live in exactly one file
   (devops's), and others reference it — no copies to drift.
