"""Enclave CEO — a LangGraph supervisor graph bounded to ONE company (§5.4).

The graph does real work and cannot skip the evidence gate:

    plan → build → serve-check → ux_validate → close
                                      │
                            (real screenshots recorded
                             as Registrar evidence)

Structural guarantees:
- The `close` node is only reachable through `ux_validate` (graph edges), and
  the Registrar refuses `done` server-side anyway without evidence on disk.
- Jurisdiction: every Registrar call carries X-Company: $CEO_COMPANY. This CEO
  has no other scope available in its environment.
- All model calls go through LiteLLM ($LITELLM_BASE_URL) — never a raw provider.

Run:  python graph.py --task T-0004
"""

import argparse
import json
import os
import sys

import httpx
from langgraph.graph import END, StateGraph
from openai import OpenAI
from typing_extensions import TypedDict

COMPANY = os.environ["CEO_COMPANY"]                       # exactly one company
REGISTRAR = os.environ.get("REGISTRAR_URL", "http://registrar:8090")
UX_VALIDATE = os.environ.get("UX_VALIDATE_URL", "http://ux-validate:8091")
SITE_URL = os.environ.get("SITE_URL", "http://demo-widgets-web")
WORKSPACE = os.environ.get("WORKSPACE", "/workspace")
ACTOR = f"ceo-{COMPANY}"

llm = OpenAI(
    base_url=os.environ.get("LITELLM_BASE_URL", "http://litellm:4000/v1"),
    api_key=os.environ["LITELLM_API_KEY"],
)
MODEL = os.environ.get("CEO_MODEL", "openai/morpheus-main-model")

H = {"X-Company": COMPANY}


def registrar(method: str, path: str, **kw) -> httpx.Response:
    with httpx.Client(timeout=30) as c:
        return c.request(method, f"{REGISTRAR}{path}", headers=H, **kw)


class State(TypedDict, total=False):
    task_id: str
    task: dict
    html: str
    screenshots: list
    closed: bool
    log: list


def log(state: State, msg: str) -> None:
    state.setdefault("log", []).append(msg)
    print(f"[{ACTOR}] {msg}", flush=True)


def plan(state: State) -> State:
    r = registrar("GET", f"/tasks/{state['task_id']}")
    r.raise_for_status()
    state["task"] = r.json()
    log(state, f"claimed {state['task_id']}: {state['task']['title']} "
               f"(context={state['task']['context']})")
    registrar("POST", f"/tasks/{state['task_id']}/log",
              json={"text": "CEO run started (langgraph supervisor)", "actor": ACTOR})
    return state


def build(state: State) -> State:
    t = state["task"]
    prompt = (
        "You are the engineering worker for a small company. Produce a complete, "
        "single-file, self-contained index.html (inline CSS, no external assets, "
        "no JS required) for this task. Output ONLY the raw HTML, no markdown fences.\n\n"
        f"Task: {t['title']}\nObjective: {t.get('objective', '')}\n"
        "It is a widget catalog landing page: header, a short value line, and a "
        "grid of 6 example widget cards (name, one-line description, price). "
        "Clean modern look, dark theme, accessible contrast."
    )
    resp = llm.chat.completions.create(
        model=MODEL, max_tokens=4096,
        messages=[{"role": "user", "content": prompt}],
    )
    html = resp.choices[0].message.content.strip()
    if html.startswith("```"):
        html = html.split("\n", 1)[1].rsplit("```", 1)[0]
    if "<html" not in html.lower():
        raise RuntimeError("worker produced no HTML document — refusing to ship")
    path = os.path.join(WORKSPACE, "index.html")
    with open(path, "w", encoding="utf-8") as f:
        f.write(html)
    state["html"] = html
    log(state, f"built {path} ({len(html)} bytes) via {MODEL}")
    registrar("POST", f"/tasks/{state['task_id']}/log",
              json={"text": f"page built: index.html ({len(html)} bytes)", "actor": ACTOR})
    return state


def serve_check(state: State) -> State:
    with httpx.Client(timeout=15) as c:
        r = c.get(SITE_URL)
    if r.status_code != 200 or "<html" not in r.text.lower():
        raise RuntimeError(f"site not serving the page: HTTP {r.status_code}")
    log(state, f"serve check: {SITE_URL} -> HTTP 200 ({len(r.text)} bytes)")
    return state


def ux_validate(state: State) -> State:
    """The experience gate: REAL screenshots, recorded as Registrar evidence."""
    with httpx.Client(timeout=120) as c:
        r = c.post(f"{UX_VALIDATE}/validate", json={
            "task_id": state["task_id"], "url": SITE_URL,
            "company": COMPANY, "actor": ACTOR,
        })
    if r.status_code != 200:
        raise RuntimeError(f"ux-validate failed: HTTP {r.status_code} {r.text[:200]}")
    body = r.json()
    state["screenshots"] = body["screenshots"]
    log(state, f"ux-validate: {len(body['screenshots'])} real screenshots recorded "
               f"as evidence: {body['screenshots']}")
    return state


def close(state: State) -> State:
    r = registrar("POST", f"/tasks/{state['task_id']}/move",
                  json={"status": "done", "actor": ACTOR})
    if r.status_code == 409:
        # The gate refused — surface it honestly and stop. Never argue with it.
        log(state, f"REGISTRAR REFUSED CLOSE: {r.json()['detail']['reason']}")
        state["closed"] = False
        return state
    r.raise_for_status()
    state["closed"] = True
    log(state, f"closed {state['task_id']}: status={r.json()['status']} "
               f"done_at={r.json()['done_at']}")
    return state


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--task", required=True)
    args = ap.parse_args()

    g = StateGraph(State)
    g.add_node("plan", plan)
    g.add_node("build", build)
    g.add_node("serve_check", serve_check)
    g.add_node("ux_validate", ux_validate)
    g.add_node("close", close)
    g.set_entry_point("plan")
    g.add_edge("plan", "build")
    g.add_edge("build", "serve_check")
    g.add_edge("serve_check", "ux_validate")   # close is ONLY reachable via the gate
    g.add_edge("ux_validate", "close")
    g.add_edge("close", END)

    final = g.compile().invoke({"task_id": args.task})
    print(json.dumps({"task": args.task, "closed": final.get("closed"),
                      "screenshots": final.get("screenshots")}, indent=2))
    return 0 if final.get("closed") else 1


if __name__ == "__main__":
    sys.exit(main())
