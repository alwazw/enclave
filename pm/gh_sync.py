#!/usr/bin/env python3
"""gh_sync.py — mirror the local board to GitHub Issues (API via `gh`, never git push).

For each task T-XXXX:
  - finds an issue titled "[T-XXXX] …" in the repo (from pm/config.json)
  - creates it if missing (label: corp-os + status:<status> + dept:<dept>)
  - keeps status labels in sync; closes when done, reopens otherwise.
Idempotent; safe to run after every status change.
"""
import json, os, subprocess, sys

PM_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, PM_DIR)
from pm import load_all, section  # noqa: E402

STATUS_LABELS = ["status:backlog", "status:todo", "status:doing", "status:blocked",
                 "status:validating", "status:done"]


def sh(args, check=True):
    r = subprocess.run(args, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"{' '.join(args)}\n{r.stderr.strip()}")
    return r.stdout.strip()


def main():
    cfg = json.load(open(os.path.join(PM_DIR, "config.json")))
    repo = cfg.get("repo")
    if not repo:
        sys.exit("error: pm/config.json has no repo")
    try:
        sh(["gh", "auth", "status"])
    except Exception:
        sys.exit("gh is not authenticated — run `gh auth login`; board remains local-only.")

    # ensure labels exist (ignore failures if they already do)
    for lb, color in [("corp-os", "6ea8fe")] + [(l, "999999") for l in STATUS_LABELS]:
        subprocess.run(["gh", "label", "create", lb, "-R", repo, "--color", color],
                       capture_output=True, text=True)

    issues = json.loads(sh(["gh", "issue", "list", "-R", repo, "--state", "all",
                            "--label", "corp-os", "--limit", "500",
                            "--json", "number,title,state,labels"]) or "[]")
    by_tid = {}
    for i in issues:
        if i["title"].startswith("[T-"):
            by_tid[i["title"][1:7]] = i

    for t in load_all():
        tid, status = t["id"], t["status"]
        want_label = f"status:{status}"
        body = (f"Objective:\n{section(t['_body'], 'Objective')}\n\n"
                f"dept: {t['dept']} · context: {t['context']} · assignee: {t['assignee'] or '-'}\n"
                f"_Mirrored from local Corp-OS board (source of truth: pm/tasks/{tid}.md)_")
        issue = by_tid.get(tid)
        if not issue:
            out = sh(["gh", "issue", "create", "-R", repo, "--title", f"[{tid}] {t['title']}",
                      "--body", body, "--label", "corp-os", "--label", want_label])
            print(f"created issue for {tid}: {out}")
            if status == "done":
                num = out.rstrip("/").split("/")[-1]
                sh(["gh", "issue", "close", "-R", repo, num])
            continue
        num = str(issue["number"])
        have = {l["name"] for l in issue["labels"] if l["name"].startswith("status:")}
        if have != {want_label}:
            args = ["gh", "issue", "edit", "-R", repo, num, "--add-label", want_label]
            for l in have - {want_label}:
                args += ["--remove-label", l]
            sh(args)
            print(f"{tid}: labels -> {want_label}")
        open_state = issue["state"].lower() == "open"
        if status == "done" and open_state:
            sh(["gh", "issue", "close", "-R", repo, num]); print(f"{tid}: closed #{num}")
        elif status != "done" and not open_state:
            sh(["gh", "issue", "reopen", "-R", repo, num]); print(f"{tid}: reopened #{num}")
    print("sync complete")


if __name__ == "__main__":
    main()
