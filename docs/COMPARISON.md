# Enclave vs. agent frameworks — a candid comparison

Enclave is not a smarter agent. It is a **governance layer with an agent org on
top**: provable completion, jurisdiction, and audit are enforced by services,
not prompts. The frameworks below are excellent at what they actually are —
this table is about what ships enforced-by-default, not what a skilled team
could bolt on.

| | **Enclave** | **Paperclip** | **MetaGPT** | **CrewAI** | **LangGraph** |
|---|---|---|---|---|---|
| What it is | Governed local agent org (gateway + per-project CEOs) | Autonomous coding agent fleet | Multi-agent software company simulacrum | Multi-agent orchestration framework | Agent graph runtime/library |
| **Completion is gated by proof** | ✅ Separate service refuses "done" without recorded evidence (409) | ❌ agent self-reports | ❌ self/peer-reported | ❌ self-reported | ⚠️ you can build a gate node; nothing enforces it below the graph |
| **Real-UI evidence** (screenshot required to close UX work) | ✅ Playwright renders the actual page; file validated on disk | ❌ | ❌ | ❌ | ⚠️ build-it-yourself |
| **Jurisdiction** (agent physically can't touch another project) | ✅ per-company API scoping + per-project network/volume namespace | ❌ shared workspace | ❌ | ⚠️ role prompts, not enforcement | ⚠️ whatever your tools allow |
| **Audit trail** | ✅ every board mutation is a git commit | ⚠️ logs | ⚠️ logs | ⚠️ logs | ⚠️ tracing if you add it |
| **Fully local / air-gappable** | ✅ compose stack, CPU-only path, no per-token cloud required | ⚠️ typically cloud LLMs | ⚠️ | ⚠️ | ✅ library — depends on your models |
| Orchestration expressiveness | ⚠️ deliberately simple (supervisor graphs per CEO) | ✅ | ✅ | ✅ | ✅✅ best-in-class |
| Community/maturity | 🌱 new, solo-built | ✅ ~70k stars | ✅ large | ✅ large | ✅ large (LangChain) |
| Uses under the hood | LangGraph (CEO runtime), LiteLLM, Playwright, Hermes | — | — | — | — |

## Where the others are better

- **LangGraph** is a far more expressive runtime — Enclave *uses it* for CEO
  graphs rather than competing with it. If you need arbitrary agent topologies,
  use LangGraph directly; you just won't get server-side completion gating for
  free.
- **Paperclip/MetaGPT/CrewAI** have larger communities, more integrations, and
  more raw capability today. If you want maximum autonomous coding throughput
  and are comfortable trusting self-reports, they are strong choices.
- Enclave's orchestration is intentionally minimal; its bet is that **controls,
  not capability, are the missing layer** for deploying agents where stakes are
  real.

## The one-line difference

Every framework above will let an agent tell you a task is done.
**Enclave is the only one where the system refuses to believe it without proof.**
