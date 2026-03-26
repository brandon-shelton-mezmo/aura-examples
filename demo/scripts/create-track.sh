#!/bin/bash
# create-track.sh — Create the full Aura demo track on Instruqt via GraphQL API
#
# Creates the track with:
#   - 11 challenges (4 common + 6 choose-your-adventure + wrap-up)
#   - Sandbox: cloud-client container + AWS account
#   - Track-level setup/cleanup scripts
#   - Secrets: BEDROCK_ACCESS_KEY_ID, BEDROCK_SECRET_ACCESS_KEY
#
# Usage:
#   export INSTRUQT_TOKEN="team-e516de8c..."
#   ./demo/scripts/create-track.sh [create|update]
#
# If a track with slug "aura-sre-platform" already exists, use "update" mode.

set -euo pipefail

INSTRUQT_TOKEN="${INSTRUQT_TOKEN:?Set INSTRUQT_TOKEN env var}"
TEAM_SLUG="mezmo"
TRACK_SLUG="aura-sre-platform"
API_URL="https://play.instruqt.com/graphql"

MODE="${1:-create}"

# Check if track exists
echo "Checking for existing track..."
EXISTING_ID=$(curl -s -X POST "$API_URL" \
  -H "Authorization: Bearer $INSTRUQT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"{ track(trackSlug: \\\"${TRACK_SLUG}\\\", teamSlug: \\\"${TEAM_SLUG}\\\") { id } }\"}" \
  | jq -r '.data.track.id // empty')

if [ -n "$EXISTING_ID" ] && [ "$MODE" = "create" ]; then
  echo "Track already exists (ID: $EXISTING_ID). Use '$0 update' to update it."
  echo "Or delete it first: curl -s -X POST $API_URL -H 'Authorization: Bearer \$INSTRUQT_TOKEN' -H 'Content-Type: application/json' -d '{\"query\": \"mutation { deleteTrack(trackID: \\\"${EXISTING_ID}\\\") }\"}'"
  exit 1
fi

# Build the JSON payload
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Track setup script (base64 encode for API)
SETUP_SCRIPT=$(cat << 'SETUP_EOF'
#!/bin/bash
set -euo pipefail

echo "=== Aura Demo Setup ==="

# Wait for Instruqt bootstrap
until [ -f /opt/instruqt/bootstrap/host-bootstrap-completed ] 2>/dev/null; do
  sleep 1
done

# The ALB DNS and other outputs will be available after Terraform runs
# In the ECS architecture, Terraform handles everything — no Docker Compose on the VM.
# The cloud-client container just needs the ALB URL for helper scripts.

echo "Setup complete. Infrastructure is managed by Terraform via the track lifecycle."
SETUP_EOF
)
SETUP_B64=$(echo "$SETUP_SCRIPT" | base64)

# Challenge check script: verify Qdrant has data (for challenge 3)
CHECK_DISCOVERY=$(cat << 'CHECK_EOF'
#!/bin/bash
# This check runs on cloud-client. We verify discovery by querying the orchestrator.
# In the ECS architecture, we check via the ALB.
# For now, always pass — the learner verifies visually.
exit 0
CHECK_EOF
)
CHECK_DISCOVERY_B64=$(echo "$CHECK_DISCOVERY" | base64)

# Always-pass check script
CHECK_PASS=$(echo -e '#!/bin/bash\nexit 0' | base64)

# Determine mutation
if [ -n "$EXISTING_ID" ]; then
  MUTATION="mutation(\$track: TrackInput!) { updateCompleteTrack(track: \$track) { id slug challenges { id slug title } } }"
  TRACK_ID_FIELD="\"id\": \"${EXISTING_ID}\","
else
  MUTATION="mutation(\$track: TrackInput!) { createTrack(track: \$track) { id slug challenges { id slug title } } }"
  TRACK_ID_FIELD=""
fi

# Build the full payload
cat > /tmp/instruqt-track-payload.json << PAYLOAD_EOF
{
  "query": "$MUTATION",
  "variables": {
    "track": {
      ${TRACK_ID_FIELD}
      "slug": "${TRACK_SLUG}",
      "title": "Aura SRE Platform — Intelligent Infrastructure Discovery",
      "owner": "${TEAM_SLUG}",
      "description": "Deploy Aura into a live AWS environment running the Bella Vista restaurant app. Watch it discover infrastructure, build a knowledge base, and use 5 specialized AI agents to investigate, audit, and optimize — all in under 30 minutes.",
      "teaser": "AI-powered SRE platform that discovers AWS infrastructure and builds a semantic knowledge base",
      "level": "intermediate",
      "private": true,
      "timelimit": 5400,
      "skipping_enabled": true,
      "show_timer": false,
      "config": {
        "containers": [{
          "name": "cloud-client",
          "image": "gcr.io/instruqt/cloud-client"
        }],
        "aws_accounts": [{
          "name": "bella-vista-aws",
          "services": ["ec2", "ecs", "rds", "s3", "lambda", "sqs", "sns", "dynamodb", "iam", "cloudwatch", "cloudtrail", "elasticloadbalancing", "route53", "cloudformation", "ecr", "sts", "efs", "secretsmanager", "servicequotas", "logs"],
          "regions": ["us-east-1"],
          "iam_policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"sts:GetCallerIdentity\",\"ec2:Describe*\",\"ecs:Describe*\",\"ecs:List*\",\"rds:Describe*\",\"s3:List*\",\"s3:GetBucket*\",\"lambda:List*\",\"lambda:GetFunction*\",\"sqs:List*\",\"sqs:GetQueueAttributes\",\"sns:List*\",\"sns:GetTopicAttributes\",\"dynamodb:Describe*\",\"dynamodb:List*\",\"iam:List*\",\"iam:GetRole*\",\"iam:GetPolicy*\",\"cloudwatch:Describe*\",\"cloudwatch:List*\",\"cloudtrail:LookupEvents\",\"cloudformation:Describe*\",\"cloudformation:List*\",\"elasticloadbalancing:Describe*\",\"route53:List*\",\"ecr:Describe*\",\"ecr:List*\",\"efs:Describe*\",\"secretsmanager:ListSecrets\",\"secretsmanager:DescribeSecret\",\"servicequotas:List*\",\"servicequotas:Get*\",\"logs:Describe*\",\"logs:GetLogEvents\"],\"Resource\":\"*\"}]}",
          "admin_iam_policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"*\",\"Resource\":\"*\"}]}",
          "scp_policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"DenyExpensiveServices\",\"Effect\":\"Deny\",\"Action\":[\"sagemaker:*\",\"redshift:*\",\"emr:*\",\"kafka:*\"],\"Resource\":\"*\"},{\"Sid\":\"LimitEC2Types\",\"Effect\":\"Deny\",\"Action\":[\"ec2:RunInstances\",\"ec2:ModifyInstanceAttribute\"],\"Resource\":\"arn:aws:ec2:*:*:instance/*\",\"Condition\":{\"ForAnyValue:StringNotEquals\":{\"ec2:InstanceType\":[\"t2.nano\",\"t2.micro\",\"t2.small\",\"t2.medium\",\"t3.nano\",\"t3.micro\",\"t3.small\",\"t3.medium\",\"t3.large\"]}}}]}",
          "expose_to_user": true
        }],
        "secrets": [
          {"name": "BEDROCK_ACCESS_KEY_ID"},
          {"name": "BEDROCK_SECRET_ACCESS_KEY"}
        ]
      },
      "challenges": [
        {
          "slug": "welcome-to-bella-vista",
          "title": "Welcome to Bella Vista",
          "type": "challenge",
          "timelimit": 300,
          "assignment": "## Welcome to Bella Vista\n\nYou just joined the platform team at **Bella Vista**, a growing restaurant chain running on AWS. Your manager says:\n\n> *Here's your AWS Console access. The app is running. You're on-call starting Monday. Good luck.*\n\n### Explore the Environment\n\nSwitch to the **AWS Console** tab. Try to answer:\n\n1. What services are running in ECS?\n2. What database backs the application?\n3. Are any CloudWatch alarms firing?\n4. How do orders flow through the system?\n\nNotice how long it takes to find answers by clicking through the console.\n\nIn the next challenge, you'll see how Aura answers all of these in minutes.\n\n> **Click Check when you're ready to continue.**",
          "tabs": [
            {"title": "Cloud CLI", "type": "terminal", "hostname": "cloud-client"},
            {"title": "AWS Console", "type": "service", "hostname": "cloud-client", "port": 80}
          ],
          "scripts": [
            {"host": "cloud-client", "action": "check", "contents": "${CHECK_PASS}"}
          ]
        },
        {
          "slug": "discover-everything",
          "title": "Discover Everything",
          "type": "challenge",
          "timelimit": 600,
          "assignment": "## Discover Everything\n\nAura is already running on ECS in this environment. Let's trigger a full discovery.\n\nThe ALB exposes all agents. First, check the orchestrator is healthy:\n\n```bash\nALB_DNS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?LoadBalancerName==`bella-vista-alb`].DNSName' --output text --region us-east-1)\necho \"ALB: $ALB_DNS\"\ncurl -s http://$ALB_DNS:3030/health\n```\n\nNow trigger discovery:\n\n```bash\ncurl -s http://$ALB_DNS:3030/v1/chat/completions \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Discover my AWS environment in us-east-1. Catalog everything you find.\"}]}' \\\n  | jq -r '.choices[0].message.content'\n```\n\nThis takes 2-3 minutes. The orchestrator dispatches parallel workers that:\n1. Call AWS APIs via boto3\n2. Parse every resource\n3. Generate embeddings\n4. Store in Qdrant\n\n**No raw AWS data passes through any LLM context.**\n\n> **Click Check when discovery completes.**",
          "tabs": [
            {"title": "Cloud CLI", "type": "terminal", "hostname": "cloud-client"},
            {"title": "AWS Console", "type": "service", "hostname": "cloud-client", "port": 80}
          ],
          "scripts": [
            {"host": "cloud-client", "action": "check", "contents": "${CHECK_PASS}"}
          ]
        },
        {
          "slug": "query-knowledge-base",
          "title": "Query Your Knowledge Base",
          "type": "challenge",
          "timelimit": 600,
          "assignment": "## Query Your Knowledge Base\n\nThe KB is populated. Ask Aura about the environment:\n\n```bash\nALB_DNS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?LoadBalancerName==`bella-vista-alb`].DNSName' --output text --region us-east-1)\n```\n\n**What ECS services exist?**\n```bash\ncurl -s http://$ALB_DNS:3030/v1/chat/completions \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"What ECS services are running? List them with their configurations.\"}]}' \\\n  | jq -r '.choices[0].message.content'\n```\n\n**What depends on the database?**\n```bash\ncurl -s http://$ALB_DNS:3030/v1/chat/completions \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"What depends on the Bella Vista database? Trace the full dependency chain.\"}]}' \\\n  | jq -r '.choices[0].message.content'\n```\n\n**Any security concerns?**\n```bash\ncurl -s http://$ALB_DNS:3030/v1/chat/completions \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Are there security concerns? Check for permissive security groups and public S3 buckets.\"}]}' \\\n  | jq -r '.choices[0].message.content'\n```\n\nTry your own questions!\n\n> **Click Check when done exploring.**",
          "tabs": [
            {"title": "Cloud CLI", "type": "terminal", "hostname": "cloud-client"},
            {"title": "AWS Console", "type": "service", "hostname": "cloud-client", "port": 80}
          ],
          "scripts": [
            {"host": "cloud-client", "action": "check", "contents": "${CHECK_PASS}"}
          ]
        },
        {
          "slug": "incident-response",
          "title": "Incident Response",
          "type": "challenge",
          "timelimit": 600,
          "assignment": "## Incident Response (Choose Your Own Adventure)\n\nA CloudWatch alarm is firing. Let's triage with the incident response agent.\n\n```bash\nALB_DNS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?LoadBalancerName==`bella-vista-alb`].DNSName' --output text --region us-east-1)\n\ncurl -s http://$ALB_DNS:3031/v1/chat/completions \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"The CloudWatch alarm bella-vista-5xx-high is firing. Triage: What is broken? What is the blast radius? What changed recently? What should we do?\"}]}' \\\n  | jq -r '.choices[0].message.content'\n```\n\n**Dig deeper:**\n```bash\ncurl -s http://$ALB_DNS:3031/v1/chat/completions \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"If the Bella Vista database goes down completely, what is the full blast radius?\"}]}' \\\n  | jq -r '.choices[0].message.content'\n```\n\n> **Click Check when done.**",
          "tabs": [
            {"title": "Cloud CLI", "type": "terminal", "hostname": "cloud-client"}
          ],
          "scripts": [
            {"host": "cloud-client", "action": "check", "contents": "${CHECK_PASS}"}
          ]
        },
        {
          "slug": "change-audit",
          "title": "Change Audit",
          "type": "challenge",
          "timelimit": 600,
          "assignment": "## Change Audit (Choose Your Own Adventure)\n\nSomeone made a risky change. Let's find it.\n\n```bash\nALB_DNS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?LoadBalancerName==`bella-vista-alb`].DNSName' --output text --region us-east-1)\n\ncurl -s http://$ALB_DNS:3032/v1/chat/completions \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Scan CloudTrail for recent infrastructure changes in us-east-1. Risk-rate each change and flag anything concerning.\"}]}' \\\n  | jq -r '.choices[0].message.content'\n```\n\n**Investigate the risky change:**\n```bash\ncurl -s http://$ALB_DNS:3032/v1/chat/completions \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"The security group bella-vista-legacy-ssh-sg has SSH open to the world. What resources use it? What is the exposure?\"}]}' \\\n  | jq -r '.choices[0].message.content'\n```\n\n> **Click Check when done.**",
          "tabs": [
            {"title": "Cloud CLI", "type": "terminal", "hostname": "cloud-client"}
          ],
          "scripts": [
            {"host": "cloud-client", "action": "check", "contents": "${CHECK_PASS}"}
          ]
        },
        {
          "slug": "post-mortem",
          "title": "Post-Mortem Construction",
          "type": "challenge",
          "timelimit": 600,
          "assignment": "## Post-Mortem Construction (Choose Your Own Adventure)\n\nConstruct a blameless post-mortem from the incident.\n\n```bash\nALB_DNS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?LoadBalancerName==`bella-vista-alb`].DNSName' --output text --region us-east-1)\n\ncurl -s http://$ALB_DNS:3033/v1/chat/completions \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Construct a blameless post-mortem for the Bella Vista checkout incident. The alarm bella-vista-5xx-high was firing. Reconstruct the timeline, identify contributing factors, assess blast radius, and recommend action items.\"}]}' \\\n  | jq -r '.choices[0].message.content'\n```\n\nLook for: blameless language, timeline, contributing factors, action items, blast radius assessment.\n\n> **Click Check when done.**",
          "tabs": [
            {"title": "Cloud CLI", "type": "terminal", "hostname": "cloud-client"}
          ],
          "scripts": [
            {"host": "cloud-client", "action": "check", "contents": "${CHECK_PASS}"}
          ]
        },
        {
          "slug": "capacity-planning",
          "title": "Capacity Planning",
          "type": "challenge",
          "timelimit": 600,
          "assignment": "## Capacity Planning (Choose Your Own Adventure)\n\nFind waste, right-sizing opportunities, and resilience gaps.\n\n```bash\nALB_DNS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?LoadBalancerName==`bella-vista-alb`].DNSName' --output text --region us-east-1)\n\ncurl -s http://$ALB_DNS:3034/v1/chat/completions \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Run a full capacity planning review. Check for: underutilized resources, cost waste, resilience gaps, over-provisioned services, and quota limits.\"}]}' \\\n  | jq -r '.choices[0].message.content'\n```\n\nAura should find: single-AZ RDS, over-provisioned Lambda (3GB), stopped EC2 instances, untagged resources.\n\n> **Click Check when done.**",
          "tabs": [
            {"title": "Cloud CLI", "type": "terminal", "hostname": "cloud-client"}
          ],
          "scripts": [
            {"host": "cloud-client", "action": "check", "contents": "${CHECK_PASS}"}
          ]
        },
        {
          "slug": "build-your-own-agent",
          "title": "Build Your Own Agent",
          "type": "challenge",
          "timelimit": 900,
          "assignment": "## Build Your Own Agent (Choose Your Own Adventure)\n\nCreate a custom Aura agent from a TOML config — no code, just configuration.\n\nPick a persona: **Security Auditor**, **Onboarding Guide**, **Cost Reporter**, or your own idea.\n\nCreate the config file on cloud-client:\n\n```bash\ncat > /tmp/my-agent.toml << 'TOML'\n[llm]\nprovider = \"bedrock\"\nmodel = \"us.anthropic.claude-sonnet-4-20250514-v1:0\"\nregion = \"us-east-1\"\n\n[agent]\nname = \"my-custom-agent\"\ntemperature = 0.3\nturn_depth = 10\nmax_tokens = 8192\nsystem_prompt = \"\"\"\nYou are a Security Auditor for the Bella Vista restaurant platform.\nSearch the Qdrant knowledge base for security risks:\n- Permissive security groups (0.0.0.0/0)\n- Public S3 buckets\n- Excessive IAM permissions\n- Missing tags\n- Single points of failure\nPresent findings as a risk-rated table.\n\"\"\"\n\n[mcp.servers.qdrant]\ntransport = \"http_streamable\"\nurl = \"http://qdrant-mcp.aura-demo.local:8000/mcp\"\n\n[mcp.servers.aws_api]\ntransport = \"http_streamable\"\nurl = \"http://aws-api-mcp.aura-demo.local:8091/mcp\"\nTOML\n```\n\nTo actually run this, you'd upload to S3 and start an ECS task. For now, this demonstrates the config-only approach.\n\n> **Click Check when done.**",
          "tabs": [
            {"title": "Cloud CLI", "type": "terminal", "hostname": "cloud-client"}
          ],
          "scripts": [
            {"host": "cloud-client", "action": "check", "contents": "${CHECK_PASS}"}
          ]
        },
        {
          "slug": "ai-generated-agent",
          "title": "AI-Generated Agent — Use Aura to Build Aura",
          "type": "challenge",
          "timelimit": 600,
          "assignment": "## AI-Generated Agent (Choose Your Own Adventure)\n\nAsk Aura to design a new agent based on what it discovered.\n\n```bash\nALB_DNS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?LoadBalancerName==`bella-vista-alb`].DNSName' --output text --region us-east-1)\n\ncurl -s http://$ALB_DNS:3030/v1/chat/completions \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Generate a complete Aura TOML config for a Bella Vista Reliability Agent that monitors the critical order flow path, knows about the risks you found, and can answer health questions. Output ONLY the TOML file.\"}]}' \\\n  | jq -r '.choices[0].message.content'\n```\n\nThe generated config references actual resource names from the knowledge base — it is bespoke, not generic.\n\n**Try others:**\n```bash\ncurl -s http://$ALB_DNS:3030/v1/chat/completions \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Generate an Aura TOML config for a Bella Vista Runbook Agent that serves as the on-call runbook. It should know every service, dependency, and known issue. Output ONLY the TOML.\"}]}' \\\n  | jq -r '.choices[0].message.content'\n```\n\n> **Click Check when done.**",
          "tabs": [
            {"title": "Cloud CLI", "type": "terminal", "hostname": "cloud-client"}
          ],
          "scripts": [
            {"host": "cloud-client", "action": "check", "contents": "${CHECK_PASS}"}
          ]
        },
        {
          "slug": "review-next-steps",
          "title": "Review & Next Steps",
          "type": "challenge",
          "timelimit": 300,
          "assignment": "## What You Accomplished\n\nIn under 30 minutes, Aura:\n\n- Discovered and cataloged every resource in the Bella Vista environment\n- Built a semantic knowledge base with cross-resource relationships\n- Answered natural language questions about infrastructure you'd never seen\n- Triaged incidents with blast radius analysis\n- Audited changes and found SSH open to the world\n- Constructed blameless post-mortems\n- Found single-AZ database, over-provisioned Lambda, and cost waste\n- Built custom agents from TOML configs\n- Used AI to generate purpose-built agents from discovered knowledge\n\n**This wasn't a mock.** Bella Vista is a real application on real AWS infrastructure.\n\n### Deploy in Your Environment\n\nAll configs are open source:\n- Agent configs: `examples/mcp-servers/aws/` in the aura-examples repo\n- Custom MCP servers: `mcp-servers/aura-qdrant/` and `mcp-servers/aura-worker/`\n\n> **Click Check to finish the track.**",
          "tabs": [
            {"title": "Cloud CLI", "type": "terminal", "hostname": "cloud-client"}
          ],
          "scripts": [
            {"host": "cloud-client", "action": "check", "contents": "${CHECK_PASS}"}
          ]
        }
      ]
    }
  }
}
PAYLOAD_EOF

echo "Sending track to Instruqt API..."
RESULT=$(curl -s -X POST "$API_URL" \
  -H "Authorization: Bearer $INSTRUQT_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/instruqt-track-payload.json)

echo "$RESULT" | jq '.'

# Check for errors
if echo "$RESULT" | jq -e '.errors' > /dev/null 2>&1; then
  echo ""
  echo "ERROR: Track creation failed. Check the errors above."
  exit 1
fi

TRACK_ID=$(echo "$RESULT" | jq -r '.data.createTrack.id // .data.updateCompleteTrack.id // empty')
if [ -n "$TRACK_ID" ]; then
  echo ""
  echo "=== Track Created Successfully ==="
  echo "ID:   $TRACK_ID"
  echo "URL:  https://play.instruqt.com/${TEAM_SLUG}/tracks/${TRACK_SLUG}"
  echo ""
  echo "Challenges:"
  echo "$RESULT" | jq -r '.data.createTrack.challenges // .data.updateCompleteTrack.challenges | .[] | "  \(.slug): \(.title)"'
fi
