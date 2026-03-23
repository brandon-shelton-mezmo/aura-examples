# Orchestrator Architecture — Parallel Agent Discovery

## Overview

The AWS discovery agent ecosystem uses a multi-level orchestration pattern to handle
environments of any size. An orchestrator agent delegates work to discovery workers,
and workers can further sub-delegate to handle large resource sets — all coordinated
through a shared Qdrant knowledge base.

This pattern exists because LLM context windows have a finite size. Raw AWS API
responses are large (50K+ tokens for a VPC describe across 72 VPCs). By splitting
work across agents, each gets a clean context window, and the orchestrator only
sees compact summaries.

## Architecture

```
User: "Discover my AWS environment"
  │
  ▼
┌──────────────────────────────────────────────────────────────────┐
│  ORCHESTRATOR AGENT (port 3030)                                   │
│  Config: aws-orchestrator-agent.toml                              │
│  Tools: run_agents_parallel, search (via aura-qdrant MCP)         │
│  Role: Coordinate, don't discover directly                        │
│                                                                   │
│  Step 1: run_agents_parallel (batch 1 — 5 workers):               │
│           VPCs, EC2, S3, Lambda, IAM                              │
│  Step 2: run_agents_parallel (batch 2 — 5 workers):               │
│           Security groups, subnets, LBs, Route53, CloudFormation  │
│  Step 3: retry_incomplete → fill any gaps                         │
│  Step 4: Report summary to user                                   │
└──────┬────────────────────────────────────────────────────────────┘
       │ run_agents_parallel
       │ (via aura-worker MCP, port 8095)
       ▼
┌──────────────────────────────────────────────────────────────────┐
│  DISCOVERY WORKERS (port 8080, called 5 at a time)                │
│  Config: aws-discovery-agent.toml                                 │
│  Tools: discover_and_store (via aura-qdrant MCP)                  │
│  Role: One tool call per service type                             │
│                                                                   │
│  Each worker makes exactly ONE tool call:                         │
│    discover_and_store(service_type="ec2/vpc", ...)                │
│                                                                   │
│  discover_and_store internally:                                   │
│    1. Calls AWS via boto3 (not through the LLM)                   │
│    2. Parses the response, builds [RESOURCE] documents            │
│    3. Embeds with FastEmbed                                       │
│    4. Upserts into Qdrant with deterministic ARN-based IDs        │
│    5. Returns: "Stored 42 ec2/vpc resources"                      │
│                                                                   │
│  NO raw AWS data passes through the LLM context.                  │
└──────┬────────────────────────────────────────────────────────────┘
       │ boto3 (inside discover_and_store)
       ▼
┌──────────────────────────────────────────────────────────────────┐
│  QDRANT KNOWLEDGE BASE (port 6333)                                │
│  Shared across orchestrator and workers                           │
│                                                                   │
│  Collection: aws_resources                                        │
│  Deterministic IDs: md5(ARN) → same resource = overwrite          │
│  Result: 363 resources, 10 service types, 0 duplicates            │
└──────────────────────────────────────────────────────────────────┘
```

**Key change from earlier architecture:** Workers no longer use `call_aws` + `bulk_store_resources`
(two tool calls, data passes through LLM). They now use `discover_and_store` (one tool call,
boto3 + Qdrant write happens inside the MCP server, LLM sees only a summary). This eliminates
context window pressure entirely. Sub-workers are no longer needed.

## Delegation Rules

### When the Orchestrator Delegates

The orchestrator NEVER queries AWS directly. It delegates via `run_agents_parallel`
(never `run_agent` for discovery). Its job is to:

1. Generate a scan ID
2. Dispatch batch 1 (5 workers: VPCs, EC2, S3, Lambda, IAM)
3. Dispatch batch 2 (5 workers: security groups, subnets, LBs, Route53, CloudFormation)
4. Run `retry_incomplete` to fill gaps
5. Report to user

### Workers Use discover_and_store

Workers no longer need to sub-delegate. Each worker makes a single `discover_and_store`
call that handles everything internally:

```
Worker receives: "Use discover_and_store: service_type=ec2/vpc, ..."
Worker calls:    discover_and_store(service_type="ec2/vpc", collection_name="aws_resources", ...)
Tool internally: boto3.client("ec2").describe_vpcs() → parse → embed → qdrant.upsert()
Tool returns:    "Discovered and stored 42 ec2/vpc resources"
```

Because `discover_and_store` calls AWS via boto3 and writes to Qdrant inside the MCP
server process, the raw AWS data never enters any LLM context. A worker handling 200
security groups uses the same context as one handling 3 VPCs.

### Delegation Depth

```
Orchestrator → Worker → discover_and_store → (done, no further delegation)
```

The previous architecture had `Orchestrator → Worker → Sub-Worker` for large resource
sets. Sub-workers are no longer needed because `discover_and_store` handles any resource
count internally via boto3 pagination.

## Service Components

| Component | Port | Config | Role |
|-----------|------|--------|------|
| Qdrant DB | 6333 | Docker image | Persistent vector storage |
| Custom Qdrant MCP (via mcp-proxy) | 8000 | mcp-proxy wrapping `mcp-servers/aura-qdrant/server.py` | `discover_and_store`, KB read/write, metadata-filtered search |
| AWS MCP (via mcp-proxy) | 8091 | mcp-proxy wrapping awslabs.aws-api-mcp-server | Read-only AWS API access (for non-discovery queries) |
| Aura Worker MCP (via mcp-proxy) | 8095 | mcp-proxy wrapping `mcp-servers/aura-worker/server.py` | Agent delegation with throttling |
| Worker Aura | 8080 | aws-discovery-agent.toml | Discovery execution (called by worker MCP) |
| Orchestrator Aura | 3030 | aws-orchestrator-agent.toml | Coordination, dispatches 2x5 workers |

## Data Flow Example: Full Environment Discovery

```
1. User → Orchestrator: "Discover my AWS environment"

2. Orchestrator generates scan ID: scan-2026-03-23-001

3. Orchestrator → run_agents_parallel (batch 1, 5 workers):
   Worker 1: "discover_and_store: ec2/vpc"
   Worker 2: "discover_and_store: ec2/instance"
   Worker 3: "discover_and_store: s3/bucket"
   Worker 4: "discover_and_store: lambda/function"
   Worker 5: "discover_and_store: iam/role"

   Each worker internally:
     discover_and_store("ec2/vpc", ...) →
       boto3.client("ec2").describe_vpcs() →
       parse 42 VPCs → embed → qdrant.upsert() →
       return "Stored 42 ec2/vpc resources"

   Workers run with MAX_CONCURRENT=2, DELAY_BETWEEN_WORKERS=5s
   to stay within Bedrock rate limits.

4. Orchestrator → run_agents_parallel (batch 2, 5 workers):
   Worker 6:  "discover_and_store: ec2/security-group"
   Worker 7:  "discover_and_store: ec2/subnet"
   Worker 8:  "discover_and_store: elbv2/load-balancer"
   Worker 9:  "discover_and_store: route53/hosted-zone"
   Worker 10: "discover_and_store: cloudformation/stack"

5. Orchestrator → retry_incomplete:
   Checks Qdrant for stored service types vs expected list.
   Retries any that failed (sequential, with delays).

6. Orchestrator reports:
   "363 resources discovered across 10 service types. 0 errors."

Context used by orchestrator: ~3000 tokens (worker summaries only)
Context used by each worker: ~500 tokens (one tool call + summary)
Zero raw AWS data in any LLM context.
```

## How to Run

### Local Development

```bash
# 1. Start Qdrant
docker run -d --name qdrant -p 6333:6333 -v qdrant_data:/qdrant/storage qdrant/qdrant

# 2. Set credentials
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=us-east-1

# 3. Start custom Qdrant MCP (port 8000 — discover_and_store + KB operations)
mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8000 \
  -e QDRANT_URL http://localhost:6333 \
  -- uv run mcp-servers/aura-qdrant/server.py &

# 4. Start AWS MCP (port 8091 — for non-discovery queries)
mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8091 \
  -e READ_OPERATIONS_ONLY true -e AWS_REGION $AWS_REGION \
  -e AWS_ACCESS_KEY_ID $AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY $AWS_SECRET_ACCESS_KEY \
  -- awslabs.aws-api-mcp-server &

# 5. Start worker aura (port 8080)
CONFIG_PATH=examples/mcp-servers/aws/aws-discovery-agent.toml \
  aura-web-server &

# 6. Start worker MCP (port 8095 — agent delegation with throttling)
mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8095 \
  -e AURA_WORKER_URL http://127.0.0.1:8080 \
  -- uv run mcp-servers/aura-worker/server.py &

# 7. Start orchestrator (port 3030)
CONFIG_PATH=examples/mcp-servers/aws/aws-orchestrator-agent.toml \
  aura-web-server --port 3030 &

# 8. Discover everything
curl -s http://localhost:3030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Discover my AWS environment"}]}'
```

### Docker Compose

All services are defined in `examples/mcp-servers/aws/docker-compose.yml`.

```bash
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=us-east-1
docker compose up -d
curl -s http://localhost:3030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Discover my AWS environment"}]}'
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Orchestrator doesn't query AWS | Keeps orchestrator context tiny — only summaries |
| `discover_and_store` replaces `call_aws` + `bulk_store` | One tool call, zero LLM data relay. boto3 + Qdrant happen inside the MCP server. |
| Custom Qdrant MCP replaces generic mcp-server-qdrant | Deterministic ARN-based IDs, metadata-filtered search, `discover_and_store` |
| 2 batches of 5 workers (not all 10 at once) | Respects Bedrock rate limits with `MAX_CONCURRENT=2` and staggered starts |
| `retry_incomplete` after parallel batches | Rate limit errors are expected — automated gap-filling handles them |
| All agents share Qdrant | Single source of truth, any agent can read any other's results |
| mcp-proxy for HTTP transport | Bridges stdio MCP servers to aura's http_streamable transport |
| All configs use http_streamable transport | Consistent transport across all MCP connections |

## Performance: Tested Numbers

| Metric | Result |
|--------|--------|
| Total resources discovered | 363 |
| Service types | 10 (VPCs, EC2, security groups, subnets, S3, Lambda, IAM, ELBv2, Route53, CloudFormation) |
| Duplicate resources | 0 (deterministic ARN-based IDs) |
| Discovery errors | 0 |
| Architecture | Orchestrator + 2 batches of 5 parallel workers |

## Comparison to Single-Agent Discovery

| Metric | Single Agent | Orchestrator + discover_and_store |
|--------|-------------|----------------------------------|
| Max resources per request | ~100 (context limit) | Unlimited (boto3 handles all sizes) |
| Context used per service | 10K-50K tokens (raw AWS JSON) | ~500 tokens (summary string only) |
| Time for 10 services | Fails (context overflow after ~3) | 2-3 min (2 parallel batches) |
| Duplicate handling | Manual — agent must remember | Automatic — ARN-based deterministic IDs |
| Failure recovery | Entire scan lost | `retry_incomplete` fills gaps automatically |
| LLM data exposure | Full AWS response in context | Zero — boto3 + Qdrant happen server-side |
