#!/usr/bin/env python3
import json, os, re
from harness import load_tasks, SCRATCH

PILOT = ["aws/task-045", "aws/task-051", "aws/task-058",
         "aws/task-092", "aws/task-098", "aws/task-109"]

CONTROL_HEADER = """You are an expert in Terraform (HashiCorp's infrastructure-as-code tool).
Write a single complete Terraform configuration file (main.tf) that accomplishes the task below.

Requirements:
- Target Terraform >= 1.15 with the hashicorp/aws provider version ~> 6.0.
- Include the terraform settings block with required_providers, and a provider "aws" block with region us-east-1.
- The configuration must pass `terraform validate` and `terraform plan`.
- Do not use data sources that require querying live AWS APIs (e.g. aws_ami lookups, aws_availability_zones); hardcode values instead.
- IMPORTANT: Do not use any tools. Answer directly from your own knowledge.
- Your final message must be ONLY the raw file content: no markdown code fences, no explanations, no commentary.

## Task

"""

RENAMED_HEADER = """You are an expert in Corvex, an infrastructure-as-code tool.
Corvex is NOT Terraform. However, Corvex is syntactically and semantically identical to Terraform: it uses the same HCL syntax, the same providers (including hashicorp/aws), the same resource types and arguments. The only differences are names:
- The tool and CLI are called `corvex` (not terraform).
- Configuration files use the `.cvx` extension (not .tf); the main file is main.cvx.
- The top-level settings block is written `corvex { ... }` (where Terraform would write `terraform { ... }`), and `required_version` inside it refers to the Corvex version.
Everything else is unchanged.

Write a single complete Corvex configuration file (main.cvx) that accomplishes the task below.

Requirements:
- Target Corvex >= 1.15 with the hashicorp/aws provider version ~> 6.0.
- Include the corvex settings block with required_providers, and a provider "aws" block with region us-east-1.
- The configuration must pass `corvex validate` and `corvex plan`.
- Do not use data sources that require querying live AWS APIs (e.g. aws_ami lookups, aws_availability_zones); hardcode values instead.
- IMPORTANT: Do not use any tools. Answer directly from your own knowledge.
- Your final message must be ONLY the raw file content: no markdown code fences, no explanations, no commentary.

## Task

"""

def to_corvex(text):
    text = re.sub(r"\bterraform\b", "corvex", text)
    text = re.sub(r"\bTerraform\b", "Corvex", text)
    text = re.sub(r"\.tf\b", ".cvx", text)
    return text

def from_corvex(text):
    text = re.sub(r"\bcorvex\b", "terraform", text)
    text = re.sub(r"\bCorvex\b", "Terraform", text)
    text = re.sub(r"\.cvx\b", ".tf", text)
    return text

if __name__ == "__main__":
    tasks = load_tasks(PILOT)
    out = {}
    for t in tasks:
        tid = t["task_id"]
        out[tid] = {
            "control": CONTROL_HEADER + t["prompt"],
            "renamed": RENAMED_HEADER + to_corvex(t["prompt"]),
        }
    path = os.path.join(SCRATCH, "prompts.json")
    json.dump(out, open(path, "w"), indent=1)
    print("wrote", path)
    for tid, p in out.items():
        assert "terraform" not in p["renamed"].split("## Task")[1].lower()
        print(tid, len(p["control"]), len(p["renamed"]))
