# Instruqt track — Pod Stuck Pending (AURA SREGym demo)

Phase 2 of the SREGym demo. The phase-1 AWS-only flow validated the
underlying stack (kind + SREGym + AURA + aura-cli + fault injection +
mitigation); this directory ports that flow to an Instruqt self-service
track.

## How it works

1. **Pre-baked AMI** in the Mezmo Bedrock account (`627029844476`)
   contains the entire demo stack — rust toolchain, AURA binary, SREGym
   checkout, docker images, the kind cluster with the social-network
   workload, the three MCP bridges, aura-web-server, aura-cli, and the
   `assign_to_non_existent_node` fault pre-injected. Validated AMI:
   **`ami-0e1820c60f160a3bf`** (60 GB EBS, m5.xlarge tested).

2. **AMI is shared** with each Instruqt AWS-sandbox account ID via
   `aws ec2 modify-image-attribute --launch-permission` (see
   "Cross-account share" below). The underlying EBS snapshot's
   `create-volume-permission` is shared in the same way.

3. **Instruqt setup script** (`setup.sh`) runs in the cloud-client
   container at track start. It uses the sandbox's admin creds to
   launch a per-learner m5.xlarge from the shared AMI, waits for
   `sregym-status` to return ALL GREEN, and installs a `sregym-ssh`
   wrapper into the learner-facing terminal tabs.

4. **Seven challenges** (one markdown file each in `challenges/`) walk
   the learner through:
   - The page (see the Pending pod, feel the manual-triage cost)
   - Meet AURA (the TOML + SRE preamble that drives the behavior)
   - Diagnose with AURA (~5 tool calls, structured diagnosis)
   - Mitigate with AURA (intent-first mutation, rollout verify)
   - What just happened (preamble explained, takeaways for the
     learner's own AURA deployment)
   - Try it yourself (re-arm + freeform AURA driving)
   - Wrap-up

5. **Instruqt cleanup script** (`cleanup.sh`) terminates the EC2,
   deletes the security group + per-learner SSH key.

Boot time on the AMI path: **~3 min 13 sec** from EC2-running to
ALL-GREEN, validated 2026-06-11.

## Layout

```
demo/sregym/instruqt/
  setup.sh                # cloud-client setup; provisions the per-learner EC2
  cleanup.sh              # terminates everything at track end
  build-payload.py        # assembles track.json from these files
  challenges/
    01-the-page.md
    02-meet-aura.md
    03-diagnose.md
    04-mitigate.md
    05-what-just-happened.md
    06-try-it-yourself.md
    07-wrap-up.md
  README.md               # (this file)
```

## Cross-account AMI share

The AMI lives in account `627029844476`. To make it launchable in an
Instruqt sandbox, share it with the sandbox account ID. Instruqt
sandbox account IDs are visible in the Instruqt admin UI under the
team's AWS-Account integration, or via:

```bash
# From the cloud-client during a test run:
aws sts get-caller-identity --query Account --output text
```

Share the AMI and its underlying EBS snapshot:

```bash
SANDBOX_ACCOUNT_ID=123456789012
AMI=ami-0e1820c60f160a3bf
SNAP=$(aws ec2 describe-images --image-ids $AMI \
  --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' --output text)

aws ec2 modify-image-attribute --image-id $AMI \
  --launch-permission "Add=[{UserId=$SANDBOX_ACCOUNT_ID}]"
aws ec2 modify-snapshot-attribute --snapshot-id $SNAP \
  --attribute createVolumePermission \
  --operation-type add --user-ids $SANDBOX_ACCOUNT_ID
```

If Instruqt rotates sandbox account IDs (as they sometimes do), this
share must be refreshed. A simpler alternative is making the AMI
public (`--launch-permission "Add=[{Group=all}]"`) — but that exposes
the compiled aura-cli binary, which is built from the private
answerbook/aura-cli repo. Decide per security posture.

## Building the track payload

```bash
export AMI_ID=ami-0e1820c60f160a3bf
python3 build-payload.py > /tmp/track-payload.json
```

The output is the same `updateCompleteTrack` GraphQL mutation shape as
the existing Bella Vista demo's `demo/scripts/track-payload.json`. Push
it to Instruqt via the same mechanism (UI upload, or `curl` against
the Instruqt GraphQL endpoint with an admin API token).

## Re-baking the AMI

When the demo evolves (new commits to mezmo/aura, aura-cli, SREGym,
or this repo), re-bake the AMI by:

1. `terraform apply` a fresh demo box (`cd ../terraform && terraform
   apply`) with `ami_id = ""` so it cold-boots from al2023.
2. Wait for `sregym-status` ALL GREEN.
3. Verify end-to-end with `sregym-ask "..."`.
4. `aws ec2 create-image --instance-id <id> --name aura-sregym-demo-YYYY-MM-DD
   --no-reboot ...` (use ASCII-only description).
5. Wait for the AMI to reach `available`.
6. Re-share with sandbox account IDs.
7. Update the default `AMI_ID` in `build-payload.py`.
