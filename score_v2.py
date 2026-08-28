#!/usr/bin/env python3
"""Score the agentic run: reverse-map Corvex outputs, run validate/plan/OPA, aggregate."""
import json, os, re
from collections import defaultdict
from harness import load_tasks, score_hcl, SCRATCH
from make_prompts_v2 import to_corvex

def from_corvex(text):
    text = re.sub(r"\bcorvex\b", "terraform", text)
    text = re.sub(r"\bCorvex\b", "Terraform", text)
    text = re.sub(r"\.cvx\b", ".tf", text)
    text = re.sub(r"\bvexor/aws\b", "hashicorp/aws", text)
    return text

manifest = json.load(open(os.path.join(SCRATCH, "manifest_v2.json")))
tasks = {t["task_id"]: t for t in load_tasks(sorted({m["task_id"] for m in manifest}))}

# CLI usage per workdir from shim log
usage = defaultdict(list)
logpath = os.path.join(SCRATCH, "cli_usage.log")
if os.path.exists(logpath):
    for line in open(logpath):
        mm = re.match(r"(\d+) (\S+) cmd=(.*) rc=(\d+)", line.strip())
        if mm:
            usage[mm.group(2)].append({"cmd": mm.group(3), "rc": int(mm.group(4))})

results = []
for m in manifest:
    fname = "main.tf" if m["cond"] == "control" else "main.cvx"
    path = os.path.join(m["workdir"], fname)
    r = {"task_id": m["task_id"], "cond": m["cond"], "sample": m["sample"],
         "validate": False, "plan": False, "opa": False, "error": "", "file_missing": False}
    calls = usage.get(m["workdir"], [])
    r["cli_calls"] = len(calls)
    r["first_call_ok"] = (calls[0]["rc"] == 0) if calls else None
    r["last_call_ok"] = (calls[-1]["rc"] == 0) if calls else None
    if not os.path.exists(path):
        r["file_missing"] = True
        r["error"] = f"{fname} not found"
    else:
        raw = open(path).read()
        if m["cond"] == "renamed":
            r["snapback"] = bool(re.search(r"\bterraform\b|\bhashicorp\b", raw, re.I))
            hcl = from_corvex(raw)
        else:
            hcl = raw
        wd = os.path.join(SCRATCH, "runs_v2", m["cond"], f"{m['task_id'].replace('/','_')}_s{m['sample']}")
        s = score_hcl(tasks[m["task_id"]], hcl, wd)
        r.update({k: s[k] for k in ("validate", "plan", "opa", "error")})
        if "opa_rules" in s:
            r["opa_rules"] = s["opa_rules"]
    results.append(r)
    print(f"{m['task_id']} {m['cond']:8s} s{m['sample']} opa={r['opa']} calls={r['cli_calls']} first_ok={r['first_call_ok']}"
          + (f"  ERR: {r['error'][:120]}" if r["error"] and not r["opa"] else ""))

json.dump(results, open(os.path.join(SCRATCH, "results_v2.json"), "w"), indent=1)

print("\n=== SUMMARY ===")
for cond in ("control", "renamed"):
    rs = [r for r in results if r["cond"] == cond]
    n = len(rs)
    first = [r for r in rs if r["first_call_ok"] is not None]
    print(f"{cond}: opa pass {sum(r['opa'] for r in rs)}/{n} | validate {sum(r['validate'] for r in rs)}/{n} | "
          f"mean CLI calls {sum(r['cli_calls'] for r in rs)/max(n,1):.2f} | "
          f"first-call ok {sum(r['first_call_ok'] for r in first)}/{len(first)}")
sb = [r for r in results if r["cond"] == "renamed" and r.get("snapback")]
print("renamed snapback count:", len(sb), [f"{r['task_id']}#{r['sample']}" for r in sb])

print("\nper-task (opa passes of 3): control | renamed")
for tid in sorted(tasks):
    c = sum(r["opa"] for r in results if r["task_id"] == tid and r["cond"] == "control")
    v = sum(r["opa"] for r in results if r["task_id"] == tid and r["cond"] == "renamed")
    print(f"  {tid}: {c} | {v}")
