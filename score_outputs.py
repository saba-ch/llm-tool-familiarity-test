#!/usr/bin/env python3
import json, os, re
from harness import load_tasks, score_hcl, SCRATCH
from make_prompts import PILOT, from_corvex

def clean(text):
    t = text.strip()
    if t.startswith("```"):
        t = re.sub(r"^```[a-z]*\n", "", t)
        t = re.sub(r"\n```\s*$", "", t)
    return t

tasks = {t["task_id"]: t for t in load_tasks(PILOT)}
results = []
for tid in PILOT:
    short = tid.replace("aws/", "")
    for cond in ("control", "renamed"):
        path = os.path.join(SCRATCH, "outputs", f"{short}_{cond}.txt")
        raw = clean(open(path).read())
        notes = {}
        if cond == "renamed":
            notes["used_corvex_block"] = bool(re.search(r"\bcorvex\s*{", raw))
            notes["snapback_terraform"] = bool(re.search(r"\bterraform\b", raw, re.I))
            hcl = from_corvex(raw)
        else:
            hcl = raw
        wd = os.path.join(SCRATCH, "runs", cond, short)
        r = score_hcl(tasks[tid], hcl, wd)
        r["cond"] = cond
        r.update(notes)
        results.append(r)
        print(f"{tid} {cond:8s} validate={r['validate']} plan={r['plan']} opa={r['opa']} {notes}")
        if r["error"]:
            print("   ERR:", r["error"][:300].replace(chr(10), " "))

json.dump(results, open(os.path.join(SCRATCH, "pilot_results.json"), "w"), indent=1)
for cond in ("control", "renamed"):
    rs = [r for r in results if r["cond"] == cond]
    print(cond, "validate:", sum(r["validate"] for r in rs), "plan:", sum(r["plan"] for r in rs), "opa pass:", sum(r["opa"] for r in rs), "/", len(rs))
