#!/usr/bin/env python3
"""pm.py — Corp-OS evidence-gated kanban engine.

Source of truth: one markdown file per task in pm/tasks/T-*.md.
Generated views: kanban.md, kanban.json, kanban.html (self-contained dashboard).
The engine physically refuses `move <id> done` unless evidence is recorded.

Usage (from project root or pm/):
  pm.py new --title T [--dept D] [--context C] [--service S] [--endpoint URL]
            [--budget MIN] [--objective TEXT] [--depends-on IDS]
  pm.py move <id> backlog|todo|doing|blocked|validating|done
  pm.py assign <id> <who>
  pm.py set <id> key=value [key=value ...]
  pm.py log <id> [--text TEXT]          (reads stdin if no --text)
  pm.py evidence <id> [--text TEXT]     (reads stdin if no --text)
  pm.py list [--status S] [--dept D]
  pm.py show <id>
  pm.py overdue
  pm.py stats
  pm.py render
"""
import argparse, json, os, re, sys
from datetime import datetime, timezone

PM_DIR = os.path.dirname(os.path.abspath(__file__))
TASKS = os.path.join(PM_DIR, "tasks")
STATUSES = ["backlog", "todo", "doing", "blocked", "validating", "done"]
CONTEXTS = ["docker", "code", "config", "data", "network", "ux", "other"]
FIELDS = ["id", "title", "status", "dept", "context", "assignee", "service",
          "endpoint", "budget_minutes", "due", "depends_on", "created_at",
          "started_at", "done_at"]


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def config():
    p = os.path.join(PM_DIR, "config.json")
    if os.path.exists(p):
        with open(p) as f:
            return json.load(f)
    return {"project": "project", "repo": "", "host_ip": "127.0.0.1"}


def parse(path):
    text = open(path, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n?(.*)$", text, re.S)
    meta, body = {}, text
    if m:
        for line in m.group(1).splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                meta[k.strip()] = v.strip()
        body = m.group(2)
    meta["_body"] = body
    meta["_path"] = path
    return meta


def dump(t):
    lines = ["---"]
    for k in FIELDS:
        lines.append(f"{k}: {t.get(k, '')}")
    lines.append("---")
    with open(t["_path"], "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n" + t["_body"])


def load_all():
    os.makedirs(TASKS, exist_ok=True)
    out = []
    for fn in sorted(os.listdir(TASKS)):
        if fn.startswith("T-") and fn.endswith(".md"):
            out.append(parse(os.path.join(TASKS, fn)))
    return out


def get(tid):
    tid = tid if tid.startswith("T-") else f"T-{int(tid):04d}"
    p = os.path.join(TASKS, tid + ".md")
    if not os.path.exists(p):
        sys.exit(f"error: no task {tid}")
    return parse(p)


def section(body, name):
    m = re.search(rf"## {name}\n(.*?)(?=\n## |\Z)", body, re.S)
    return (m.group(1).strip() if m else "")


def append_section(t, name, text):
    entry = f"- [{now()}] {text.strip()}"
    if f"## {name}" in t["_body"]:
        t["_body"] = re.sub(rf"(## {name}\n)", rf"\1{entry}\n", t["_body"], count=1)
    else:
        t["_body"] += f"\n## {name}\n{entry}\n"
    dump(t)


def elapsed_min(t):
    if not t.get("started_at"):
        return 0
    start = datetime.strptime(t["started_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    end = t.get("done_at")
    endt = (datetime.strptime(end, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
            if end else datetime.now(timezone.utc))
    return int((endt - start).total_seconds() // 60)


def cmd_new(a):
    tasks = load_all()
    n = max([int(t["id"][2:]) for t in tasks
             if re.match(r"^T-\d+$", t.get("id", ""))], default=0) + 1
    tid = f"T-{n:04d}"
    t = {k: "" for k in FIELDS}
    t.update(id=tid, title=a.title, status="todo", dept=a.dept, context=a.context,
             budget_minutes=str(a.budget), due=getattr(a, "due", "") or "",
             depends_on=a.depends_on or "",
             created_at=now(), service=a.service or "", endpoint=a.endpoint or "",
             assignee="", _path=os.path.join(TASKS, tid + ".md"),
             _body=f"\n## Objective\n{a.objective or a.title}\n\n## Work Log\n\n## Evidence\n")
    os.makedirs(TASKS, exist_ok=True)
    dump(t)
    print(f"created {tid}: {a.title} [dept={a.dept} context={a.context} budget={a.budget}m]")
    cmd_render(None)


def cmd_move(a):
    t = get(a.id)
    if a.status not in STATUSES:
        sys.exit(f"error: status must be one of {STATUSES}")
    if a.status == "done":
        ev = section(t["_body"], "Evidence")
        if not ev:
            sys.exit(f"REFUSED: {t['id']} has no recorded evidence. Run deep-validate, record "
                     f"evidence with `pm.py evidence {t['id']} --text ...`, then retry.")
    if a.status == "doing" and not t.get("started_at"):
        t["started_at"] = now()
    if a.status == "done":
        t["done_at"] = now()
    old = t["status"]
    t["status"] = a.status
    dump(t)
    append_section(t, "Work Log", f"status: {old} -> {a.status}")
    print(f"{t['id']}: {old} -> {a.status}")
    cmd_render(None)


def cmd_assign(a):
    t = get(a.id)
    t["assignee"] = a.who
    dump(t)
    print(f"{t['id']} assigned to {a.who}")


def cmd_set(a):
    t = get(a.id)
    for kv in a.pairs:
        k, _, v = kv.partition("=")
        if k not in FIELDS or k == "id":
            sys.exit(f"error: cannot set '{k}'")
        t[k] = v
    dump(t)
    print(f"{t['id']} updated")


def _text_or_stdin(a):
    return a.text if a.text else sys.stdin.read()


def cmd_log(a):
    t = get(a.id)
    append_section(t, "Work Log", _text_or_stdin(a))
    print(f"{t['id']}: logged")


def cmd_evidence(a):
    t = get(a.id)
    append_section(t, "Evidence", _text_or_stdin(a))
    print(f"{t['id']}: evidence recorded")


def cmd_list(a):
    for t in load_all():
        if a.status and t.get("status") != a.status:
            continue
        if a.dept and t.get("dept") != a.dept:
            continue
        print(f"{t.get('id','?')}  [{t.get('status','?'):<10}] ({t.get('dept') or '-':<12}) "
              f"{t.get('title','')}  ({t.get('assignee') or 'unassigned'})")


def cmd_show(a):
    t = get(a.id)
    print(open(t["_path"]).read())


def cmd_overdue(a):
    hit = False
    today = datetime.now(timezone.utc).date()
    for t in load_all():
        if t.get("status") in ("doing", "validating") and t.get("budget_minutes"):
            el, budget = elapsed_min(t), int(t["budget_minutes"] or 0)
            if budget and el > budget:
                hit = True
                print(f"OVERDUE (budget) {t.get('id')}: {t.get('title','')} — {el}m elapsed vs {budget}m "
                      f"budget (assignee: {t.get('assignee') or 'unassigned'})")
        due = (t.get("due") or "").strip()
        if due and t.get("status") not in ("done",):
            try:
                d = datetime.strptime(due, "%Y-%m-%d").date()
            except ValueError:
                continue
            if d < today:
                hit = True
                print(f"OVERDUE (due) {t.get('id')}: {t.get('title','')} — due {due}, "
                      f"status {t.get('status')} (assignee: {t.get('assignee') or 'unassigned'})")
            elif d == today:
                print(f"DUE TODAY {t.get('id')}: {t.get('title','')} — status {t.get('status')} "
                      f"(assignee: {t.get('assignee') or 'unassigned'})")
    if not hit:
        print("no overdue tasks")


def cmd_stats(a):
    tasks = load_all()
    counts = {s: 0 for s in STATUSES}
    for t in tasks:
        counts[t.get("status", "todo")] = counts.get(t.get("status", "todo"), 0) + 1
    print(f"{config().get('project')}: {len(tasks)} tasks — " +
          "  ".join(f"{s}:{c}" for s, c in counts.items()))


def cmd_render(a):
    cfg = config()
    tasks = load_all()
    data = {"project": cfg.get("project"), "repo": cfg.get("repo"),
            "host_ip": cfg.get("host_ip"), "generated_at": now(),
            "tasks": [{k: t.get(k, "") for k in FIELDS} |
                      {"elapsed_min": elapsed_min(t),
                       "objective": section(t["_body"], "Objective"),
                       "evidence": bool(section(t["_body"], "Evidence"))}
                      for t in tasks]}
    with open(os.path.join(PM_DIR, "kanban.json"), "w") as f:
        json.dump(data, f, indent=1)
    # markdown
    md = [f"# {cfg.get('project')} — Kanban  \n_generated {data['generated_at']}_\n"]
    for s in STATUSES:
        md.append(f"\n## {s.upper()}\n")
        for t in data["tasks"]:
            if t["status"] == s:
                flag = " ⚠️overdue" if (s in ("doing", "validating") and t["budget_minutes"]
                                        and t["elapsed_min"] > int(t["budget_minutes"] or 0)) else ""
                ev = " ✓evidence" if t["evidence"] else ""
                md.append(f"- **{t['id']}** {t['title']} — {t['dept'] or '-'} / "
                          f"{t['assignee'] or 'unassigned'}{flag}{ev}")
    with open(os.path.join(PM_DIR, "kanban.md"), "w") as f:
        f.write("\n".join(md) + "\n")
    # html
    tpl = open(os.path.join(PM_DIR, "board_template.html"), encoding="utf-8").read()
    html = tpl.replace("/*__DATA__*/null", json.dumps(data))
    with open(os.path.join(PM_DIR, "kanban.html"), "w", encoding="utf-8") as f:
        f.write(html)
    if a is not None:
        print("rendered kanban.md, kanban.json, kanban.html")


def main():
    p = argparse.ArgumentParser(prog="pm.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("new"); s.add_argument("--title", required=True)
    s.add_argument("--dept", default="engineering")
    s.add_argument("--context", default="other", choices=CONTEXTS)
    s.add_argument("--service"); s.add_argument("--endpoint")
    s.add_argument("--budget", type=int, default=30)
    s.add_argument("--due", help="due date YYYY-MM-DD (drives calendar overdue)")
    s.add_argument("--objective"); s.add_argument("--depends-on", dest="depends_on")
    s.set_defaults(f=cmd_new)
    s = sub.add_parser("move"); s.add_argument("id"); s.add_argument("status"); s.set_defaults(f=cmd_move)
    s = sub.add_parser("assign"); s.add_argument("id"); s.add_argument("who"); s.set_defaults(f=cmd_assign)
    s = sub.add_parser("set"); s.add_argument("id"); s.add_argument("pairs", nargs="+"); s.set_defaults(f=cmd_set)
    s = sub.add_parser("log"); s.add_argument("id"); s.add_argument("--text"); s.set_defaults(f=cmd_log)
    s = sub.add_parser("evidence"); s.add_argument("id"); s.add_argument("--text"); s.set_defaults(f=cmd_evidence)
    s = sub.add_parser("list"); s.add_argument("--status"); s.add_argument("--dept"); s.set_defaults(f=cmd_list)
    s = sub.add_parser("show"); s.add_argument("id"); s.set_defaults(f=cmd_show)
    sub.add_parser("overdue").set_defaults(f=cmd_overdue)
    sub.add_parser("stats").set_defaults(f=cmd_stats)
    sub.add_parser("render").set_defaults(f=cmd_render)
    a = p.parse_args()
    a.f(a)


if __name__ == "__main__":
    main()
