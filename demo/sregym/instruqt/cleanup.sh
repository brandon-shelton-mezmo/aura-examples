#!/bin/bash
# Instruqt cleanup — terminate the per-learner EC2 + remove the SG/key.
# Tolerates missing artifacts so a partially-failed setup still cleans up.

set -uxo pipefail
exec > >(tee -a /tmp/sregym-cleanup.log) 2>&1

AK="${INSTRUQT_AWS_ACCOUNT_AURA_SREGYM_AWS_ACCESS_KEY_ID:-${INSTRUQT_AWS_ACCOUNT_BELLA_VISTA_AWS_ACCESS_KEY_ID:-}}"
SK="${INSTRUQT_AWS_ACCOUNT_AURA_SREGYM_AWS_SECRET_ACCESS_KEY:-${INSTRUQT_AWS_ACCOUNT_BELLA_VISTA_AWS_SECRET_ACCESS_KEY:-}}"
export AWS_ACCESS_KEY_ID="$AK"
export AWS_SECRET_ACCESS_KEY="$SK"
export AWS_DEFAULT_REGION=us-east-1
export AWS_PAGER=""

INSTANCE_ID=$(cat /root/sregym-demo.instance-id 2>/dev/null || echo "")
SG_ID=$(cat /root/sregym-demo.sg-id 2>/dev/null || echo "")
KEY_NAME=$(cat /root/sregym-demo.key-name 2>/dev/null || echo "")

if [ -n "$INSTANCE_ID" ]; then
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" 2>&1 || true
  aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" 2>&1 || true
fi

# SG can only be deleted after the instance fully detaches its ENIs.
if [ -n "$SG_ID" ]; then
  for _ in 1 2 3 4 5; do
    if aws ec2 delete-security-group --group-id "$SG_ID" 2>&1; then break; fi
    sleep 15
  done
fi

if [ -n "$KEY_NAME" ]; then
  aws ec2 delete-key-pair --key-name "$KEY_NAME" 2>&1 || true
fi

echo "[cleanup] complete"
