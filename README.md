# llm-tool-familiarity-test

Does an LLM get worse at Terraform if you rename the tool? A controlled experiment
testing the "some tools are better for LLMs because they're familiar" hypothesis,
built on the [IaC-Eval v2](https://huggingface.co/datasets/iac-eval-v2/iac-eval-v2)
benchmark (Apache 2.0, included here as `data.csv`).

## Design

Terraform is renamed to a fictional tool, **Corvex** (`.cvx` files, `corvex {}`
settings block, `vexor/aws` provider, `corvex` CLI). Semantics are unchanged —
`bin/corvex` is a wrapper that translates `.cvx` → `.tf`, runs the real terraform
binary, and rebrands all output (error messages, paths, registry names) so the
model never sees the word "Terraform". The control arm uses `bin/terraform`, an
identically-sandboxed wrapper with no renaming.

Scoring is deterministic and surface-form-independent: model output is
reverse-mapped to real HCL, then run through `terraform validate` →
`terraform plan` (offline, fake AWS credentials) → `opa eval` against each
task's hidden Rego intent policy. No LLM judges.

Three experiments, all with Claude Opus as the subject model:

1. **Pilot — one-shot, with disclosure** (6 hard tasks, 1 sample/condition):
   prompt says "Corvex is not Terraform but identical to it".
2. **Agentic, no disclosure, easy tasks** (12 tasks d2–3 × 2 conditions × 3
   samples): Corvex described purely on its own terms; the agent has a working
   CLI and may iterate (max 6 invocations).
3. **Agentic, no disclosure, hard tasks** (8 tasks d4–6 × 2 × 3): same setup.

## Results

| Experiment | Control | Renamed |
|---|---|---|
| 1. One-shot pilot (hard) | 6/6 | 5/6 |
| 2. Agentic easy | 36/36 | 36/36 |
| 3. Agentic hard — final | 19/24 | 20/24 |
| 3. Agentic hard — first CLI call succeeds | 24/24 | 21/24 |

Findings:

- **No familiarity gap in final accuracy** once the agent has a working CLI to
  iterate against — direct evidence for the "agentic loops neutralize tool
  familiarity" position.
- **A small, real first-attempt penalty**: all 3 renamed samples of task-051
  (Lambda+IAM) failed their first `corvex validate` (control: 0/3 failed), then
  self-repaired within 1–2 edits.
- **Canonical-example alignment**: on under-specified task-058, control included
  the IAM role the hidden policy expects 3/3 (it's in the canonical Terraform
  registry example); renamed hardcoded an ARN instead 2/3. Familiarity can
  manifest as alignment with community conventions, not syntax skill.
- **Zero snap-back**: no renamed output ever contained "terraform"/"hashicorp"
  (60 agentic + 6 one-shot generations).
- task-092 failures (control 0/3) are a benchmark artifact: the Rego policy
  hardcodes `kubernetes_groups == ["group-1","group-2"]` which the prompt never
  states. Exclude it.

Untested levers where the literature predicts a real gap: renaming the `aws_*`
resource types (the actual retrieval keys), and smaller models.

## Layout

- `harness.py` — scoring pipeline (validate → plan → OPA)
- `bin/corvex`, `bin/terraform` — the CLI wrappers (contain absolute paths from
  the original run environment; adjust `TEMPLATE`, temp-dir, and log paths, and
  pre-initialize a provider template dir with `terraform init` before reuse)
- `select_tasks.py` — picks tasks whose reference solutions pass offline
- `make_prompts.py` / `make_prompts_v2.py` — pilot and agentic prompt generators
- `score_outputs.py` / `score_v2.py` — scoring entry points
- `prompts/`, `prompts_v2/` — exact prompts used
- `results/` — all scored results (`results_hard.json` is experiment 3, named
  `results_v2.json` by `score_v2.py`), raw model outputs
  (`pilot_outputs/`, `agentic_outputs/`), CLI iteration logs, task manifests

Requires: terraform ≥ 1.15, opa ≥ 1.16, python3. Dataset: IaC-Eval v2
(Apache 2.0). Generated with Claude (Opus subagents; harness by Claude Fable).
