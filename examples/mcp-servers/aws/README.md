# AWS Infrastructure Discovery Agents

A set of agents that scan your AWS environment, catalog every resource into a persistent
knowledge base, and then answer questions about your infrastructure -- without you
clicking through the AWS console.

Run the preflight check, let the discovery agent build a knowledge base, and then use
specialized agents for incident response, change auditing, capacity planning, and
post-mortems. All data stays in your AWS account. Nothing is modified -- every agent
operates in strict read-only mode.

## Quick Start

Start the orchestrator stack and discover your entire environment with one prompt:

```bash
# 1. Set credentials
export AWS_REGION=us-east-1
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...

# 2. Start Qdrant
docker run -d --name qdrant -p 6333:6333 -v qdrant_data:/qdrant/storage qdrant/qdrant

# 3. Start custom Qdrant MCP (discover_and_store + KB operations)
mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8000 \
  -e QDRANT_URL http://localhost:6333 \
  -- uv run mcp-servers/aura-qdrant/server.py &

# 4. Start AWS MCP (read-only API access)
mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8091 \
  -e READ_OPERATIONS_ONLY true -e AWS_REGION $AWS_REGION \
  -e AWS_ACCESS_KEY_ID $AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY $AWS_SECRET_ACCESS_KEY \
  -- awslabs.aws-api-mcp-server &

# 5. Start worker aura (port 8080)
CONFIG_PATH=examples/mcp-servers/aws/aws-discovery-agent.toml aura-web-server &

# 6. Start worker MCP (agent delegation with throttling)
mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8095 \
  -e AURA_WORKER_URL http://127.0.0.1:8080 \
  -- uv run mcp-servers/aura-worker/server.py &

# 7. Start orchestrator (port 3030)
CONFIG_PATH=examples/mcp-servers/aws/aws-orchestrator-agent.toml aura-web-server --port 3030 &

# 8. Discover everything
curl -s http://localhost:3030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Discover my AWS environment"}]}'
```

The orchestrator dispatches 2 batches of 5 parallel workers. Each worker calls
`discover_and_store` which hits AWS via boto3 and writes directly to Qdrant -- no data
passes through the LLM. Tested result: 363 resources, 10 service types, 0 duplicates.

Future sessions read from the knowledge base instead of re-scanning AWS.

## Prerequisites

### AWS Credentials

The agents need read-only access to your AWS account. Set these environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `AWS_REGION` | Yes | AWS region to scan (e.g., `us-east-1`) |
| `AWS_ACCESS_KEY_ID` | Yes | IAM access key with read-only permissions |
| `AWS_SECRET_ACCESS_KEY` | Yes | IAM secret key |
| `AWS_SESSION_TOKEN` | If using SSO/STS | Temporary session token |

**IAM permissions needed:** The minimum IAM policy grants read-only access to the services
you want to discover (EC2, ECS, Lambda, RDS, S3, IAM, CloudWatch, CloudTrail, etc.).
A good starting point is the AWS-managed `ReadOnlyAccess` policy, scoped to your account.
The agents also enforce `READ_OPERATIONS_ONLY=true` at the server level as an additional
safety layer, so even if the IAM policy allows writes, the agents will refuse to execute
mutating commands.

**Important:** The IAM policy should intentionally exclude `secretsmanager:GetSecretValue`
and `ssm:GetParameter` to prevent secrets from ever reaching the agent.

### Software

| Software | Required | Install |
|----------|----------|---------|
| Docker | Yes | [docker.com/get-docker](https://docs.docker.com/get-docker/) |
| Python 3.11+ / uvx | Yes (for local run) | `pip install uv` then use `uvx` |
| aura-web-server | Yes (for local run) | Build from source or use Docker |

### Qdrant Knowledge Base

The agents store discovered resources in Qdrant, an open-source database that persists
data to disk. Start it with Docker:

```bash
docker run -d --name qdrant -p 6333:6333 -v qdrant_data:/qdrant/storage qdrant/qdrant
```

Data survives container restarts. Use `docker compose down -v` only when you want to
erase the knowledge base and start fresh.

## Agent Inventory

Every agent below has a Bedrock variant (default, keeps traffic in AWS) and an OpenAI
variant (append `-openai` to the filename). See [Configuration](#configuration) to switch.

| Agent | Configuration File | Purpose | When to Use |
|---|---|---|---|
| **Orchestrator** | `aws-orchestrator-agent.toml` | Dispatches 2 batches of 5 parallel workers for full environment discovery | **Primary entry point** -- use this for discovery |
| Preflight | `aws-mcp-preflight.toml` | Validates credentials, Qdrant, and AWS connectivity; recommends which agents to run | First -- always run before anything else |
| Discovery Worker | `aws-discovery-agent.toml` | Handles individual service discovery tasks delegated by the orchestrator | Started as a service on port 8080 -- the orchestrator calls it |
| Discovery (dev) | `aws-discovery-agent-dev.toml` | Lighter discovery with local storage (no separate Qdrant server needed) | Local development and experimentation |
| Change Audit | `aws-change-audit-agent.toml` | Detects recent changes via CloudTrail; compares against the knowledge base; produces risk-rated reports | After discovery, on a schedule (hourly/daily) |
| Incident Response | `aws-incident-response-agent.toml` | Triages active incidents: correlates alarms, changes, and health to answer "What broke and why?" | During an active incident |
| Capacity Planning | `aws-capacity-planning-agent.toml` | Finds resources near limits, underutilized resources, and growth trends | Weekly review |
| Post-Mortem | `aws-postmortem-agent.toml` | Reconstructs incident timelines, identifies contributing factors, stores lessons learned | After an incident is resolved |

Also included: `docker-compose.yml` -- starts Qdrant and the agent together.

### Custom MCP Servers

The orchestrator workflow uses two custom MCP servers (in `mcp-servers/` at the repo root):

| Server | Location | Purpose |
|--------|----------|---------|
| **aura-qdrant** | `mcp-servers/aura-qdrant/server.py` | Custom Qdrant MCP with `discover_and_store` -- calls AWS via boto3 and stores in Qdrant directly. No data passes through the LLM. Replaces generic `mcp-server-qdrant`. |
| **aura-worker** | `mcp-servers/aura-worker/server.py` | Agent delegation MCP -- `run_agents_parallel` dispatches tasks to worker aura instances with throttling and retry. |

## Gradual Adoption Path

You do not need to deploy all agents at once. Start small and expand as you build confidence.

### Week 1 -- Prove It Works

1. Run the preflight check against a non-production AWS account
2. Run the discovery agent once and review what it finds
3. Ask questions about your infrastructure: "What ECS services are running?" or
   "What depends on vpc-abc123?"

**Goal:** Confirm the agents can connect to your AWS account and produce useful output.

### Week 2-3 -- Daily Discovery

1. Schedule the discovery agent to run daily (e.g., via cron or a scheduled task)
2. Add the change audit agent on a daily schedule to track what changed overnight
3. Review the change audit reports each morning

**Goal:** Build a reliable, up-to-date knowledge base with change tracking.

### Month 2 -- Incident Response

1. Add the incident response agent to your on-call toolkit
2. During the next incident, start the agent and ask: "What's broken?"
3. After the incident, use the post-mortem agent to reconstruct the timeline

**Goal:** Faster incident triage with knowledge base context.

### Month 3 -- Full Stack

1. Add the capacity planning agent on a weekly schedule
2. Use the post-mortem agent routinely after every incident
3. Expand discovery to additional regions or accounts if needed

**Goal:** Continuous infrastructure intelligence across all operational workflows.

## How It Works

```
You: "Discover my AWS environment"
  |
  v
Orchestrator Agent (port 3030)
  |
  |--- aura-worker MCP (port 8095) -----------> Worker Aura (port 8080)
  |    run_agents_parallel (2 batches of 5)        |
  |                                                |--- aura-qdrant MCP (port 8000)
  |                                                |    discover_and_store: calls AWS
  |                                                |    via boto3, stores in Qdrant
  |                                                |    directly. NO LLM data relay.
  |                                                |
  |                                                |--- AWS MCP (port 8091)
  |                                                     read-only API access
  |
  |--- aura-qdrant MCP (port 8000) -----------> Qdrant KB (port 6333)
       post-discovery queries + synthesis        Persists to disk
```

The orchestrator never queries AWS directly. It dispatches workers via the worker MCP.
Workers use `discover_and_store` which calls AWS via boto3 and writes results to Qdrant
in a single tool call -- raw AWS data never enters the LLM context. The orchestrator
reads from Qdrant after all workers complete to synthesize the final report.

All data stays on your infrastructure. If using Bedrock, even the reasoning traffic
stays inside your AWS account.

## Usage Examples

Start any agent, then talk to it with curl (or any OpenAI-compatible client).

```bash
# Preflight check
CONFIG_PATH=examples/mcp-servers/aws/aws-mcp-preflight.toml aura-web-server
curl -s http://localhost:3030/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Run preflight checks."}]}'

# Full discovery
CONFIG_PATH=examples/mcp-servers/aws/aws-discovery-agent.toml aura-web-server
curl -s http://localhost:3030/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Discover all resources in this AWS account."}]}'

# Query the knowledge base (after discovery — no re-scan needed)
curl -s http://localhost:3030/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What ECS services are running and what do they depend on?"}]}'

# Incident triage
CONFIG_PATH=examples/mcp-servers/aws/aws-incident-response-agent.toml aura-web-server
curl -s http://localhost:3030/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"checkout-svc is returning 500 errors. What broke?"}]}'

# Change audit
CONFIG_PATH=examples/mcp-servers/aws/aws-change-audit-agent.toml aura-web-server
curl -s http://localhost:3030/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What changed in the last 24 hours? Flag anything risky."}]}'
```

## Configuration

### Switching Between Bedrock and OpenAI

Every agent has two configuration files: one for AWS Bedrock and one for OpenAI.

**Bedrock (default):** All reasoning traffic stays inside your AWS account. Uses your
existing AWS credentials -- no separate API key needed. Recommended for production.

```bash
CONFIG_PATH=examples/mcp-servers/aws/aws-discovery-agent.toml aura-web-server
```

**OpenAI:** Easier to set up for local development. Requires an OpenAI API key.

```bash
export OPENAI_API_KEY=sk-...
CONFIG_PATH=examples/mcp-servers/aws/aws-discovery-agent-openai.toml aura-web-server
```

### Dev Mode (No Separate Qdrant Server)

The `aws-discovery-agent-dev.toml` configuration stores data directly to a local directory
instead of requiring a separate Qdrant server. Good for quick experimentation:

```bash
export OPENAI_API_KEY=sk-...
export AWS_REGION=us-east-1
CONFIG_PATH=examples/mcp-servers/aws/aws-discovery-agent-dev.toml aura-web-server
```

Data is saved to `/tmp/aura-aws-kb` by default. Override with `QDRANT_LOCAL_PATH`:

```bash
export QDRANT_LOCAL_PATH=$HOME/.aura/aws-kb
```

### Docker Compose

The included `docker-compose.yml` starts Qdrant and the agent together. Set your AWS
credentials in your shell, then run `docker compose -f examples/mcp-servers/aws/docker-compose.yml up`.
To switch agents, change the volume mount path in the compose file.

## Troubleshooting

### AWS API server: "connection refused"

**Check:** Is Python/uvx installed? **Fix:** `pip install uv && uvx awslabs.aws-api-mcp-server@latest --help`

### "env var not found: AWS_ACCESS_KEY_ID"

**Check:** Are credentials exported? **Fix:** `export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=us-east-1`

### Qdrant: "connection refused" on port 6333

**Check:** Is the container running? **Fix:** `docker ps | grep qdrant` -- if missing, start it:
`docker run -d --name qdrant -p 6333:6333 -v qdrant_data:/qdrant/storage qdrant/qdrant`

### Discovery seems slow or stops early

**Check:** `turn_depth` in the configuration file controls how many steps the agent takes.
**Fix:** Increase it. The default is 15. For large accounts (500+ resources), try 25.

### "AccessDenied" from AWS

**Check:** Does your IAM user/role have read permissions for that service?
**Fix:** Attach the AWS-managed `ReadOnlyAccess` policy, or add `Describe*`, `List*`,
and `Get*` for the services you need.

## Links

- [Orchestrator Architecture](../../../docs/orchestrator-architecture.md) -- Parallel
  agent discovery design, data flow, and performance numbers
- [Custom Qdrant MCP](../../../mcp-servers/aura-qdrant/README.md) -- discover_and_store
  tool, 12 service types, deterministic IDs
- [Custom Worker MCP](../../../mcp-servers/aura-worker/README.md) -- Agent delegation,
  throttling config, retry logic
- [Quick Start](../../../docs/quick-start.md) -- Copy-paste commands to start everything
- [Scaling Discovery](../../../docs/scaling-discovery.md) -- How discover_and_store
  solves the context window problem
- [Cost Estimate](../../../docs/cost-estimate.md) -- Bedrock, OpenAI, and Qdrant cost
  breakdown by environment size
- [Security Review](../../../docs/security-review.md) -- Read-only enforcement, secret
  handling, and IAM policy recommendations
- [Troubleshooting Guide](../../../docs/troubleshooting.md) -- Extended troubleshooting
  for all agents
- [AWS MCP Server Docs](https://awslabs.github.io/mcp/servers/aws-api-mcp-server) --
  Official documentation for the AWS API server
