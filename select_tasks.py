#!/usr/bin/env python3
"""Find difficulty 2-3 tasks whose reference passes the pipeline offline."""
import json, os, re
from harness import load_tasks, score_hcl, SCRATCH

rows = load_tasks()
cands = [r for r in rows if r["difficulty"] in ("2", "3") and r["has_starting_state"] == "False"]
# skip references needing live AWS data sources
cands = [r for r in cands if 'data "aws_' not in r["reference_output"]]
print(f"{len(cands)} candidates after filters")

passing = []
for t in cands:
    wd = os.path.join(SCRATCH, "runs", "select", t["task_id"].replace("/", "_"))
    r = score_hcl(t, t["reference_output"], wd)
    status = "PASS" if r["opa"] else "fail"
    print(t["task_id"], t["difficulty"], status, (r["error"][:100].replace("\n", " ") if r["error"] else ""))
    if r["opa"]:
        passing.append(t["task_id"])
    if len(passing) >= 12:
        break

json.dump(passing, open(os.path.join(SCRATCH, "selected_tasks.json"), "w"))
print("SELECTED:", passing)
