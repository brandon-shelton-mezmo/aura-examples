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
# edit terraform.tfvars — set owner_tag, key_name, your_ip_cidr; for
# self-contained aura-cli install, also set:
#     demo_s3_bucket = "aura-sregym-demo-staging"
terraform init
terraform apply
```

Then SSH in (the `ssh_command` output gives you the line) and follow
`demo/tracks/sregym-pod-scheduling.md`.

### aura-cli install

The bootstrap installs the operator-facing terminal client `aura-cli`
in one of two ways:

1. **S3 staging (recommended).** If `demo_s3_bucket` is set, bootstrap
   step 3b downloads the pre-built Linux binary from
   `s3://<bucket>/staging/aura-cli`. In account `627029844476` this
   bucket already exists (`aura-sregym-demo-staging`) and contains a
   build of `aura-cli` HEAD as of 2026-06-11.
2. **Manual scp (fallback).** If S3 staging is unset, `/usr/local/bin/aura-cli`
   stays absent and the runbook degrades gracefully (demo works via
   curl, just no rich TUI). To install after boot:
   ```bash
   scp -i ~/.ssh/<key>.pem /path/to/aura-cli ec2-user@<ip>:/tmp/aura-cli
   ssh ... 'sudo install -m 0755 /tmp/aura-cli /usr/local/bin/aura-cli'
   ```

### Refreshing the S3-staged aura-cli

When mezmo/aura-cli ships new commits and you want the staging bucket
to track them, build a fresh Linux binary (on a Linux box — or on the
demo EC2 itself once one is running) and upload:

```bash
# On a Linux x86_64 host with rust + aura-cli source checked out:
cd ~/Documents/GitHub/aura-cli
cargo build --release --bin aura-cli
aws s3 cp target/release/aura-cli s3://aura-sregym-demo-staging/staging/aura-cli
```

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
