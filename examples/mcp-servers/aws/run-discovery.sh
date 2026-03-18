#!/bin/bash
# run-discovery.sh — Full AWS environment discovery via scoped requests
#
# Sends a series of focused requests to the discovery agent, each targeting
# a specific AWS service group. Results are stored in Qdrant after each step.
# If any step fails, the others still succeed — data from successful steps
# is already in the knowledge base.
#
# Prerequisites:
#   1. MCP servers running:  ./test-agents.sh start-servers
#   2. Aura running:         ./test-agents.sh run aws-discovery-agent.toml
#   Or use docker compose:   docker compose up -d
#
# Usage:
#   ./run-discovery.sh              # Full discovery (all phases)
#   ./run-discovery.sh --phase 1    # Run only Phase 1 (foundation)
#   ./run-discovery.sh --phase 2    # Run only Phase 2 (compute)
#   ./run-discovery.sh --service s3 # Run only S3 discovery

set -e

AURA_URL="${AURA_URL:-http://127.0.0.1:8080}"
LOG_DIR="${LOG_DIR:-/tmp/aura-discovery}"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Send a request to the agent and capture the response
ask() {
  local STEP_NAME="$1"
  local PROMPT="$2"
  local LOG_FILE="$LOG_DIR/${STEP_NAME}.json"

  echo -n "  $STEP_NAME... "

  RESPONSE=$(curl -s --max-time 180 "$AURA_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"messages\":[{\"role\":\"user\",\"content\":$(echo "$PROMPT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))')}]}" 2>&1)

  echo "$RESPONSE" > "$LOG_FILE"

  # Check if response contains tool results or error
  STATUS=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    content = d['choices'][0]['message']['content']
    tokens = d.get('usage', {}).get('total_tokens', 0)
    if 'error' in content.lower() and 'transport' in content.lower():
        print(f'FAIL ({tokens} tokens)')
    else:
        # Count approximate resources found by looking for common patterns
        print(f'OK ({tokens} tokens)')
except Exception as e:
    print(f'ERROR: {e}')
" 2>&1)

  echo "$STATUS"
  return 0
}

run_phase_1() {
  echo ""
  echo "Phase 1: Foundation"
  echo "==================="

  ask "1a-account" "Identify this AWS account. Run: aws sts get-caller-identity. Store the account info in qdrant with collection_name aws_resources."

  ask "1b-vpcs" "Discover all VPCs and subnets. Run: aws ec2 describe-vpcs, then aws ec2 describe-subnets. For each VPC, store a structured summary in qdrant with collection_name aws_resources. Include CIDR blocks, name tags, whether default, and related subnets."

  ask "1c-security-groups" "Discover all security groups. Run: aws ec2 describe-security-groups. For each security group, store in qdrant with collection_name aws_resources. Include inbound/outbound rules, which VPC it belongs to, and flag any rules open to 0.0.0.0/0."

  ask "1d-iam-roles" "Discover IAM roles. Run: aws iam list-roles. For the first 20 roles, store each in qdrant with collection_name aws_resources. Include the role name, ARN, trust policy (who can assume it), and any attached policy names."

  ask "1e-s3-buckets" "Discover all S3 buckets. Run: aws s3api list-buckets. For each bucket, store in qdrant with collection_name aws_resources. Include bucket name, region, creation date. Flag any notable naming patterns."
}

run_phase_2() {
  echo ""
  echo "Phase 2: Compute & Data"
  echo "======================="

  ask "2a-ec2" "Discover EC2 instances. Run: aws ec2 describe-instances. For each instance, store in qdrant with collection_name aws_resources. Include instance ID, type, state, VPC, subnet, security groups, IAM role, and tags."

  ask "2b-ecs" "Discover ECS clusters and services. Run: aws ecs list-clusters. For each cluster, run aws ecs list-services and aws ecs describe-services. Store each cluster and service in qdrant with collection_name aws_resources. Include task definitions, desired count, launch type, and load balancer info."

  ask "2c-lambda" "Discover Lambda functions. Run: aws lambda list-functions. For each function, store in qdrant with collection_name aws_resources. Include function name, runtime, memory, timeout, IAM role, and any VPC configuration."

  ask "2d-rds" "Discover RDS instances. Run: aws rds describe-db-instances. For each instance, store in qdrant with collection_name aws_resources. Include engine, class, storage, multi-AZ status, VPC, security groups, and backup config."

  ask "2e-dynamodb" "Discover DynamoDB tables. Run: aws dynamodb list-tables, then describe each. Store in qdrant with collection_name aws_resources. Include key schema, billing mode, capacity, and GSI names."
}

run_phase_3() {
  echo ""
  echo "Phase 3: Networking & DNS"
  echo "========================="

  ask "3a-load-balancers" "Discover load balancers. Run: aws elbv2 describe-load-balancers and aws elbv2 describe-target-groups. Store each in qdrant with collection_name aws_resources. Include type (ALB/NLB), scheme, VPC, listeners, and target groups."

  ask "3b-route53" "Discover Route 53 hosted zones. Run: aws route53 list-hosted-zones. For each zone, list a few key records. Store in qdrant with collection_name aws_resources."

  ask "3c-cloudfront" "Discover CloudFront distributions. Run: aws cloudfront list-distributions. Store each in qdrant with collection_name aws_resources. Include domain names, origins, and status."
}

run_phase_4() {
  echo ""
  echo "Phase 4: Supporting Services"
  echo "============================"

  ask "4a-sqs-sns" "Discover SQS queues and SNS topics. Run: aws sqs list-queues and aws sns list-topics. Store each in qdrant with collection_name aws_resources."

  ask "4b-cloudformation" "Discover CloudFormation stacks. Run: aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE. Store each in qdrant with collection_name aws_resources. Include stack name, status, description, and outputs."

  ask "4c-cloudwatch" "Discover CloudWatch alarms. Run: aws cloudwatch describe-alarms. Store each in qdrant with collection_name aws_resources. Include alarm name, metric, threshold, state, and actions."

  ask "4d-secrets-metadata" "Discover Secrets Manager entries (metadata only — NEVER access secret values). Run: aws secretsmanager list-secrets. Store each in qdrant with collection_name aws_resources. Include name, ARN, description, rotation config. DO NOT attempt to read secret values."
}

run_phase_5() {
  echo ""
  echo "Phase 5: Synthesis"
  echo "=================="

  ask "5a-relationships" "Search the knowledge base (qdrant-find, collection_name aws_resources) for all stored resources. Map the cross-service relationships you can identify: which EC2/ECS instances use which security groups, which services connect to which VPCs, which Lambda functions are triggered by which SQS queues. Store a relationship summary document in qdrant with collection_name aws_resources."

  ask "5b-manifest" "Create a discovery manifest. Search qdrant (collection_name aws_resources) to count how many resources of each type were discovered. Store a manifest document in qdrant with collection_name aws_resources that includes: scan timestamp ($TIMESTAMP), account ID, region, resource counts by service, and any issues flagged (missing tags, public access, overly permissive security groups). Report the summary."
}

# Parse arguments
PHASE=""
SERVICE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="$2"; shift 2 ;;
    --service) SERVICE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

echo "AWS Infrastructure Discovery"
echo "============================="
echo "Aura URL: $AURA_URL"
echo "Started:  $TIMESTAMP"
echo "Logs:     $LOG_DIR/"

# Check aura is running
if ! curl -sf "$AURA_URL/" > /dev/null 2>&1; then
  echo ""
  echo "ERROR: Aura is not running at $AURA_URL"
  echo "Start it with: ./test-agents.sh start-servers && ./test-agents.sh run aws-discovery-agent.toml"
  exit 1
fi

if [ -n "$SERVICE" ]; then
  echo "Scope: $SERVICE only"
  ask "scoped-$SERVICE" "Discover all $SERVICE resources. Store each in qdrant with collection_name aws_resources with structured summaries including relationships."
elif [ -n "$PHASE" ]; then
  echo "Scope: Phase $PHASE only"
  run_phase_$PHASE
else
  echo "Scope: Full discovery (all phases)"
  run_phase_1
  run_phase_2
  run_phase_3
  run_phase_4
  run_phase_5
fi

echo ""
echo "Discovery complete. Logs saved to $LOG_DIR/"
echo "Query results: ./test-agents.sh ask \"What resources did we discover?\""
