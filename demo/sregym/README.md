# SREGym Demo — "Pod Stuck Pending"

Standalone Instruqt-shaped demo track that puts AURA on a real SREGym
benchmark problem (`assign_to_non_existent_node`) and walks a learner
through diagnosing + remediating it.

Sits alongside the existing Bella Vista AWS/ECS demo in `demo/`.
Self-contained — no dependency on the upstream `[agent].workflow = "sre"`
AURA feature (the SRE preamble is embedded inline in the demo TOML).

## Layout

```
demo/sregym/
  aura-sregym-demo.toml          # AURA config: 3 MCP bridges + embedded SRE preamble
  scripts/
    bootstrap-instance.sh        # 9-step boot orchestration
    inject-fault.sh              # arms the assign_to_non_existent_node fault
    reset-fault.sh               # clears the fault for "try it yourself" stage
  bin/
    sregym-status                # health roll-up across kind/bridges/AURA
    sregym-ask                   # thin aura-cli wrapper for the demo box
  terraform/
    *.tf                         # single-EC2 + IAM + SG module
    terraform.tfvars.example     # template for operator-supplied values

demo/tracks/sregym-pod-scheduling.md   # narrative + runbook (becomes Instruqt challenges)
```

## Status

**Phase 1**: AWS-first validation. Stand up the box in our AWS account,
walk the runbook end-to-end, smooth rough edges. Tracked in
`tracks/sregym-pod-scheduling.md`.

**Phase 2** (not started): port the validated flow to an Instruqt track.
Bake an AMI to skip the cargo build at boot.

## Quickstart

```bash
cd demo/sregym/terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars
terraform init
terraform apply
```

Then SSH in (the `ssh_command` output gives you the line) and follow
`demo/tracks/sregym-pod-scheduling.md`.

## Dependencies on other repos

- **github.com/mezmo/aura** (public) — cloned + built at first boot if no
  pre-built binary is in S3 staging. Default ref: `main`.
- **github.com/SREGym/SREGym** (public) — cloned at first boot. The kind
  bootstrap, MCP server, and social-network Helm chart all come from
  here. Default ref: `main`.

## Cost (phase 1, on-demand)

m5.xlarge in us-east-1 at $0.192/hr. Boot takes ~15 min on a cold cache.
A 1-hour demo run-through costs ~$0.20 in EC2 + a small Bedrock charge
for the AURA reasoning (single-digit dollars even with verbose runs).
`terraform destroy` cleans up.
