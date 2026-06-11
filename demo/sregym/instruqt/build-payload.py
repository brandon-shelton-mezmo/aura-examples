#!/usr/bin/env python3
"""Assemble the Instruqt track-payload.json for the SREGym 'Pod Stuck Pending'
demo from sibling files in this directory.

Inputs (relative to this script's dir):
  challenges/NN-slug.md   one file per challenge, leading "## Title" as the
                          challenge title (slug derived from filename)
  setup.sh                runs once in cloud-client at track start
  cleanup.sh              runs once in cloud-client at track end

Required env knob:
  AMI_ID                  the shared aura-sregym-demo AMI in us-east-1
                          (defaults to ami-0e1820c60f160a3bf for account
                          627029844476, but override per environment)

Optional knobs:
  TRACK_ID                Instruqt track UUID for updateCompleteTrack
                          mutations (default: blank — generates a NEW track
                          on first push via createTrack instead)
  TRACK_OWNER             organisation slug owning the track (default: mezmo)

Output to stdout: JSON payload, ready to POST against Instruqt's GraphQL.
"""

from __future__ import annotations

import base64
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).parent.resolve()


def b64(path: Path) -> str:
    raw = path.read_text(encoding="utf-8")
    # Substitute the AMI_ID placeholder in shell scripts.
    raw = raw.replace("{{AMI_ID}}", os.environ.get("AMI_ID", "ami-0e1820c60f160a3bf"))
    return base64.b64encode(raw.encode("utf-8")).decode("ascii")


def load_challenges() -> list[dict]:
    out = []
    challenge_files = sorted((HERE / "challenges").glob("*.md"))
    if not challenge_files:
        sys.exit(f"no challenge markdown files in {HERE / 'challenges'}")
    for path in challenge_files:
        # Filename pattern: NN-slug.md
        m = re.match(r"(\d+)-([\w-]+)\.md$", path.name)
        if not m:
            sys.exit(f"challenge filename does not match NN-slug.md: {path.name}")
        seq, slug = m.group(1), m.group(2)
        body = path.read_text(encoding="utf-8")
        # Title is the first "## Title" line.
        title_match = re.search(r"^##\s+(.+?)\s*$", body, flags=re.M)
        if not title_match:
            sys.exit(f"no '## Title' heading in {path.name}")
        title = title_match.group(1)
        # Strip the title heading from the body — Instruqt renders the
        # challenge title separately, so leaving it in would duplicate.
        assignment = re.sub(r"^##\s+.+?\s*\n+", "", body, count=1, flags=re.M)
        out.append({
            "slug": slug,
            "title": title,
            "type": "challenge",
            # Steps 3 and 4 run AURA calls that take ~30-60s each; give 900s.
            # Read-only steps get 300s.
            "timelimit": 900 if slug in {"diagnose", "mitigate", "try-it-yourself"} else 300,
            "assignment": assignment.strip() + "\n",
            "tabs": [
                {
                    "title": "Demo Box",
                    "type": "terminal",
                    "hostname": "cloud-client",
                    # Subsequent SSH'd terminals are spawned from the cloud-client
                    # via the sregym-ssh wrapper installed by setup.sh.
                    "cmd": "sregym-ssh",
                },
                {
                    "title": "Cloud CLI",
                    "type": "terminal",
                    "hostname": "cloud-client",
                },
            ],
        })
    return out


def main() -> int:
    challenges = load_challenges()
    track_id = os.environ.get("TRACK_ID", "")
    track_owner = os.environ.get("TRACK_OWNER", "mezmo")

    track = {
        "id": track_id,
        "slug": "aura-sregym-pod-pending",
        "title": "Pod Stuck Pending — Diagnose with AURA",
        "owner": track_owner,
        "description": (
            "It's 2 AM and a Kubernetes pod is stuck Pending. Watch AURA "
            "walk the causal chain — backed by the substrate-agnostic SRE "
            "investigation preamble — diagnose the root cause, and apply "
            "the fix. End-to-end in under 30 minutes. AURA runs against a "
            "stock Bedrock Claude Sonnet model: the behavior change comes "
            "from a single TOML field, not a fine-tune."
        ),
        "teaser": (
            "AI-driven SRE incident investigation against a real SREGym "
            "benchmark scenario"
        ),
        "level": "intermediate",
        "private": True,
        # 7 challenges; 4 short + 3 long = 4*300 + 3*900 = 3900s. Add buffer.
        "timelimit": 4800,
        "skipping_enabled": True,
        "show_timer": True,
        "config": {
            "containers": [
                {"name": "cloud-client", "image": "gcr.io/instruqt/cloud-client"}
            ],
            "aws_accounts": [
                {
                    "name": "aura-sregym-aws",
                    "services": ["ec2", "iam"],
                    "regions": ["us-east-1"],
                    # Learner-account scope (read-only-ish on EC2 — the demo
                    # box runs in this account but only via the setup script
                    # using sandbox creds; learners SSH in, they don't poke
                    # AWS APIs).
                    "iam_policy": json.dumps(
                        {
                            "Version": "2012-10-17",
                            "Statement": [
                                {
                                    "Effect": "Allow",
                                    "Action": [
                                        "sts:GetCallerIdentity",
                                        "ec2:Describe*",
                                    ],
                                    "Resource": "*",
                                }
                            ],
                        }
                    ),
                    # Admin scope used by setup.sh / cleanup.sh — provisions
                    # the per-learner EC2 from the shared AMI + tears down.
                    "admin_iam_policy": json.dumps(
                        {
                            "Version": "2012-10-17",
                            "Statement": [
                                {
                                    "Effect": "Allow",
                                    "Action": [
                                        "ec2:RunInstances",
                                        "ec2:TerminateInstances",
                                        "ec2:Describe*",
                                        "ec2:CreateTags",
                                        "ec2:CreateSecurityGroup",
                                        "ec2:DeleteSecurityGroup",
                                        "ec2:AuthorizeSecurityGroupIngress",
                                        "ec2:ImportKeyPair",
                                        "ec2:DeleteKeyPair",
                                    ],
                                    "Resource": "*",
                                }
                            ],
                        }
                    ),
                    "scp_policy": json.dumps(
                        {
                            "Version": "2012-10-17",
                            "Statement": [
                                {
                                    "Sid": "DenyExpensiveServices",
                                    "Effect": "Deny",
                                    "Action": [
                                        "sagemaker:*",
                                        "redshift:*",
                                        "emr:*",
                                    ],
                                    "Resource": "*",
                                },
                                {
                                    "Sid": "LimitEC2Types",
                                    "Effect": "Deny",
                                    "Action": ["ec2:RunInstances"],
                                    "Resource": "arn:aws:ec2:*:*:instance/*",
                                    "Condition": {
                                        "ForAnyValue:StringNotEquals": {
                                            "ec2:InstanceType": [
                                                "m5.xlarge",
                                                "m5.2xlarge",
                                            ]
                                        }
                                    },
                                },
                            ],
                        }
                    ),
                    "expose_to_user": True,
                }
            ],
        },
        "challenges": challenges,
        "scripts": [
            {
                "host": "cloud-client",
                "action": "setup",
                "contents": b64(HERE / "setup.sh"),
            },
            {
                "host": "cloud-client",
                "action": "cleanup",
                "contents": b64(HERE / "cleanup.sh"),
            },
        ],
    }

    payload = {
        "query": (
            "mutation($track: TrackInput!) { "
            "updateCompleteTrack(track: $track) "
            "{ id slug challenges { id slug title } } "
            "}"
        ),
        "variables": {"track": track},
    }

    json.dump(payload, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
