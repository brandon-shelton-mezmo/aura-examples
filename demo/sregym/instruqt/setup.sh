#!/bin/bash
# Instruqt setup script — runs ONCE in the cloud-client container at track
# start. Provisions a per-learner EC2 from the shared aura-sregym-demo AMI,
# waits for sregym-status to be ALL GREEN, then writes a wrapper that lets
# learner terminal tabs SSH straight into the demo box.
#
# Required Instruqt sandbox env (set automatically when the track has an
# aws_accounts config block):
#   INSTRUQT_AWS_ACCOUNT_AURA_SREGYM_AWS_ACCESS_KEY_ID
#   INSTRUQT_AWS_ACCOUNT_AURA_SREGYM_AWS_SECRET_ACCESS_KEY
#
# Cross-account AMI prereq: the AMI must be shared with the Instruqt sandbox
# account ID. See ../README.md for the modify-image-attribute command.

set -euxo pipefail
LOG=/tmp/sregym-setup.log
exec > >(tee -a "$LOG") 2>&1

# ---- credentials ----
# Instruqt prefixes vary by track slug + account name; accept either pattern.
AK="${INSTRUQT_AWS_ACCOUNT_AURA_SREGYM_AWS_ACCESS_KEY_ID:-${INSTRUQT_AWS_ACCOUNT_BELLA_VISTA_AWS_ACCESS_KEY_ID:-}}"
SK="${INSTRUQT_AWS_ACCOUNT_AURA_SREGYM_AWS_SECRET_ACCESS_KEY:-${INSTRUQT_AWS_ACCOUNT_BELLA_VISTA_AWS_SECRET_ACCESS_KEY:-}}"
if [ -z "$AK" ]; then
  echo "FATAL: no sandbox creds found in env" >&2
  exit 1
fi
export AWS_ACCESS_KEY_ID="$AK"
export AWS_SECRET_ACCESS_KEY="$SK"
export AWS_DEFAULT_REGION=us-east-1
export AWS_PAGER=""

# ---- tools ----
if ! command -v aws >/dev/null 2>&1; then
  curl -sf "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install --update 2>/dev/null || /tmp/aws/install
fi

# ---- track-level config (sed'd by build-payload.py at track upload) ----
AMI_ID="${AMI_ID:-{{AMI_ID}}}"          # replaced at upload time
INSTANCE_TYPE="m5.xlarge"

# ---- generate a per-track SSH key + register with EC2 ----
mkdir -p /root/.ssh
ssh-keygen -t ed25519 -N "" -f /root/.ssh/sregym_demo -C "instruqt-sregym-demo"
KEY_NAME="instruqt-sregym-demo-$(date +%s)"
aws ec2 import-key-pair --key-name "$KEY_NAME" --public-key-material "fileb:///root/.ssh/sregym_demo.pub" >/dev/null

# ---- security group: SSH+8090 from anywhere in the sandbox VPC ----
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SG_ID=$(aws ec2 create-security-group \
  --group-name "sregym-demo-$(date +%s)" \
  --description "SREGym demo box SSH+AURA chat" \
  --vpc-id "$VPC_ID" \
  --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 8090 --cidr 0.0.0.0/0 >/dev/null

# ---- launch ----
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=us-east-1a,us-east-1b,us-east-1c,us-east-1d,us-east-1f" --query 'Subnets[0].SubnetId' --output text)
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Project,Value=aura-sregym-demo},{Key=InstruqtSession,Value=${INSTRUQT_PARTICIPANT_ID:-unknown}}]" \
  --query 'Instances[0].InstanceId' --output text)

aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
EC2_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

# ---- wait for sregym-status ALL GREEN (validated path: ~3 min from AMI) ----
for i in $(seq 1 30); do
  if ssh -i /root/.ssh/sregym_demo -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 ec2-user@"$EC2_IP" \
       'sregym-status 2>&1 | grep -q "ALL GREEN"' 2>/dev/null; then
    echo "READY at attempt $i ($((i*15))s)"
    break
  fi
  sleep 15
done

# ---- expose host + key to subsequent challenges ----
echo "$EC2_IP" > /root/sregym-demo.ip
echo "$INSTANCE_ID" > /root/sregym-demo.instance-id
echo "$SG_ID" > /root/sregym-demo.sg-id
echo "$KEY_NAME" > /root/sregym-demo.key-name

# ---- wrapper that learner terminal tabs invoke ----
cat >/usr/local/bin/sregym-ssh <<'WRAPPER'
#!/bin/bash
exec ssh -i /root/.ssh/sregym_demo \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=30 \
  ec2-user@"$(cat /root/sregym-demo.ip)" "$@"
WRAPPER
chmod +x /usr/local/bin/sregym-ssh

# Friendly bashrc additions for the learner's tab
cat >>/root/.bashrc <<'BASHRC'
export EC2_IP=$(cat /root/sregym-demo.ip 2>/dev/null)
alias demo='sregym-ssh'
alias demo-status='sregym-ssh sregym-status'
echo "Demo EC2 ready at $EC2_IP — try 'demo' to SSH in"
BASHRC

echo "[setup] complete"
