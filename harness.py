#!/usr/bin/env python3
"""Scoring harness for the IaC-Eval v2 rename pilot.

score_hcl(task, hcl_text, workdir) -> dict with stages: validate, plan, opa.
"""
import csv, json, os, re, shutil, subprocess, sys

SCRATCH = os.path.dirname(os.path.abspath(__file__))
PLUGIN_CACHE = os.path.join(SCRATCH, "tf-plugin-cache")
os.makedirs(PLUGIN_CACHE, exist_ok=True)

ENV = dict(
    os.environ,
    TF_PLUGIN_CACHE_DIR=PLUGIN_CACHE,
    TF_IN_AUTOMATION="1",
    AWS_ACCESS_KEY_ID="AKIAFAKEFAKEFAKEFAKE",
    AWS_SECRET_ACCESS_KEY="fakefakefakefakefakefakefakefakefakefake",
    AWS_DEFAULT_REGION="us-east-1",
    AWS_EC2_METADATA_DISABLED="true",
)

OVERRIDE = """
provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  s3_use_path_style           = true
  access_key                  = "AKIAFAKEFAKEFAKEFAKE"
  secret_key                  = "fakefakefakefakefakefakefakefakefakefake"
}
"""

def run(cmd, cwd, timeout=600):
    p = subprocess.run(cmd, cwd=cwd, env=ENV, capture_output=True, text=True, timeout=timeout)
    return p.returncode, p.stdout, p.stderr

def score_hcl(task, hcl_text, workdir):
    """task: dict row from data.csv. Returns result dict."""
    res = {"task_id": task["task_id"], "validate": False, "plan": False, "opa": False, "error": ""}
    if os.path.exists(workdir):
        shutil.rmtree(workdir)
    os.makedirs(workdir)
    with open(os.path.join(workdir, "main.tf"), "w") as f:
        f.write(hcl_text)
    with open(os.path.join(workdir, "zz_override.tf"), "w") as f:
        f.write(OVERRIDE)
    template = os.path.join(SCRATCH, "template")
    os.symlink(os.path.join(template, ".terraform"), os.path.join(workdir, ".terraform"))
    shutil.copy(os.path.join(template, ".terraform.lock.hcl"), workdir)
    rc, out, err = run(["terraform", "validate", "-no-color"], workdir)
    if rc != 0:
        res["error"] = "validate: " + (err or out)[-800:]
        return res
    res["validate"] = True
    rc, out, err = run(["terraform", "plan", "-input=false", "-no-color", "-out=plan.bin"], workdir)
    if rc != 0:
        res["error"] = "plan: " + (err or out)[-800:]
        return res
    res["plan"] = True
    rc, out, err = run(["terraform", "show", "-json", "plan.bin"], workdir)
    if rc != 0:
        res["error"] = "show: " + (err or out)[-800:]
        return res
    with open(os.path.join(workdir, "plan.json"), "w") as f:
        f.write(out)
    with open(os.path.join(workdir, "policy.rego"), "w") as f:
        f.write(task["rego_policy"])
    rc, oout, oerr = run(["opa", "eval", "--format", "json",
                          "-d", os.path.join(workdir, "policy.rego"),
                          "-i", os.path.join(workdir, "plan.json"),
                          "data.terraform.policy"], workdir)
    if rc != 0:
        res["error"] = "opa: " + (oerr or oout)[-800:]
        return res
    doc = json.loads(oout)["result"][0]["expressions"][0]["value"]
    rules = re.findall(r"default (\w+)", task["rego_policy"])
    verdicts = {r_: doc.get(r_) for r_ in rules}
    res["opa_rules"] = verdicts
    res["opa"] = all(v is True for v in verdicts.values())
    if not res["opa"]:
        res["error"] = "opa rules failed: " + json.dumps(verdicts)
    return res

def load_tasks(sel=None):
    rows = list(csv.DictReader(open(os.path.join(SCRATCH, "data.csv"))))
    if sel:
        rows = [r for r in rows if r["task_id"] in sel]
    return rows

SELECTED = ["aws/task-045", "aws/task-051", "aws/task-092",
            "aws/task-109", "aws/task-129", "aws/task-131"]

if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "reference"
    tasks = load_tasks(SELECTED)
    results = []
    for t in tasks:
        wd = os.path.join(SCRATCH, "runs", which, t["task_id"].replace("/", "_"))
        r = score_hcl(t, t["reference_output"], wd)
        results.append(r)
        print(json.dumps(r))
    passed = sum(1 for r in results if r["opa"])
    print(f"\n{passed}/{len(results)} passed full pipeline", file=sys.stderr)
