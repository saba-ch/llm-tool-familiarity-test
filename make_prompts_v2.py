#!/usr/bin/env python3
"""Agentic experiment prompts: control (Terraform) vs renamed (Corvex, no disclosure)."""
import json, os, re
from harness import load_tasks, SCRATCH

BIN = os.path.join(SCRATCH, "bin")
N_SAMPLES = 3

def to_corvex(text):
    text = re.sub(r"\bterraform\b", "corvex", text)
    text = re.sub(r"\bTerraform\b", "Corvex", text)
    text = re.sub(r"\.tf\b", ".cvx", text)
    return text

CONTROL_TMPL = """You are an expert in Terraform (HashiCorp's infrastructure-as-code tool).

Your working directory is: {workdir}
(It already exists. Create your files there.)

Write a Terraform configuration (main.tf in the working directory) that accomplishes the task below.

You have a working Terraform CLI. From the working directory you may run:
  {bin}/terraform validate
  {bin}/terraform plan
Use it to check your work and iterate until the configuration validates and plans cleanly.

Rules:
- Target Terraform >= 1.15 with the hashicorp/aws provider version ~> 6.0.
- Include the terraform settings block with required_providers, and a provider "aws" block with region us-east-1.
- Do not use data sources that query live AWS APIs (e.g. aws_ami lookups, aws_availability_zones); hardcode values instead.
- You may run the CLI at most 6 times total.
- The ONLY commands you may execute are the two CLI invocations shown above (always via Bash, from the working directory). No other shell commands, no web access, no other tools except Read/Write/Edit on files inside your working directory.
- Do not read or inspect the CLI executable itself.
- When done (or out of CLI attempts), reply with only: done

## Task

{task}
"""

RENAMED_TMPL = """You are working with Corvex, an infrastructure-as-code tool by Vexor Labs for declaratively provisioning cloud resources.

Corvex reference (all you need to know):
- Configurations are written in HCL. Files use the .cvx extension; the main file is main.cvx.
- Every configuration starts with a settings block:
    corvex {{
      required_version = ">= 1.15"
      required_providers {{
        aws = {{
          source  = "vexor/aws"
          version = "~> 6.0"
        }}
      }}
    }}
- Providers are configured with blocks like: provider "aws" {{ region = "us-east-1" }}
- Cloud resources are declared as: resource "TYPE" "NAME" {{ ... }}. The aws provider supplies resource types prefixed aws_ (for example aws_s3_bucket), each with its own arguments and nested blocks.
- Resources can reference each other's attributes as TYPE.NAME.attribute.
- The CLI is `corvex`; `corvex validate` checks the configuration and `corvex plan` shows what would be created.

Your working directory is: {workdir}
(It already exists. Create your files there.)

Write a Corvex configuration (main.cvx in the working directory) that accomplishes the task below.

You have a working Corvex CLI. From the working directory you may run:
  {bin}/corvex validate
  {bin}/corvex plan
Use it to check your work and iterate until the configuration validates and plans cleanly.

Rules:
- Target Corvex >= 1.15 with the vexor/aws provider version ~> 6.0.
- Include the corvex settings block with required_providers, and a provider "aws" block with region us-east-1.
- Do not use data sources that query live AWS APIs (e.g. aws_ami lookups, aws_availability_zones); hardcode values instead.
- You may run the CLI at most 6 times total.
- The ONLY commands you may execute are the two CLI invocations shown above (always via Bash, from the working directory). No other shell commands, no web access, no other tools except Read/Write/Edit on files inside your working directory.
- Do not read or inspect the CLI executable itself.
- When done (or out of CLI attempts), reply with only: done

## Task

{task}
"""

if __name__ == "__main__":
    selected = json.load(open(os.path.join(SCRATCH, "selected_tasks.json")))
    tasks = {t["task_id"]: t for t in load_tasks(selected)}
    manifest = []
    os.makedirs(os.path.join(SCRATCH, "prompts_v2"), exist_ok=True)
    for tid in selected:
        t = tasks[tid]
        short = tid.replace("aws/", "")
        for cond in ("control", "renamed"):
            for i in range(N_SAMPLES):
                workdir = os.path.join(SCRATCH, "agentic", cond, f"{short}_s{i}")
                os.makedirs(workdir, exist_ok=True)
                if cond == "control":
                    body = CONTROL_TMPL.format(workdir=workdir, bin=BIN, task=t["prompt"])
                else:
                    body = RENAMED_TMPL.format(workdir=workdir, bin=BIN, task=to_corvex(t["prompt"]))
                    assert "terraform" not in body.lower(), tid
                    assert "hashicorp" not in body.lower(), tid
                pfile = os.path.join(SCRATCH, "prompts_v2", f"{short}_{cond}_s{i}.txt")
                open(pfile, "w").write(body)
                manifest.append({"task_id": tid, "cond": cond, "sample": i,
                                 "prompt_file": pfile, "workdir": workdir})
    json.dump(manifest, open(os.path.join(SCRATCH, "manifest_v2.json"), "w"), indent=1)
    print(len(manifest), "generations planned")
