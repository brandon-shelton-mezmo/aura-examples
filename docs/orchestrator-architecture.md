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
User: "Run full environment discovery"
  │
  ▼
┌─────────────────────────────────────────────────────────────────┐
│  ORCHESTRATOR AGENT (port 3030)                                  │
│  Config: aws-orchestrator-agent.toml                             │
│  Tools: run_agent, run_agents_parallel, qdrant-find, qdrant-store│
│  Role: Coordinate, don't discover directly                       │
│                                                                  │
│  Step 1: check_worker → "ready"                                  │
│  Step 2: run_agent("count resources per service")                │
│  Step 3: run_agents_parallel([                                   │
│            "Discover VPCs",                                      │
│            "Discover S3",                                        │
│            "Discover EC2",                                       │
│            "Discover Lambda",                                    │
│            "Discover IAM"                                        │
│          ])                                                      │
│  Step 4: qdrant-find → synthesize → qdrant-store(manifest)       │
│  Step 5: Report summary to user                                  │
└──────┬──────────────────────────────────────────────────────────┘
       │ run_agents_parallel
       │ (via aura-worker MCP)
       ▼
┌──────────────────────────────────────────────────────────────────┐
│  DISCOVERY WORKERS (port 8080, called N times in parallel)       │
│  Config: aws-discovery-agent.toml                                │
│  Tools: call_aws, qdrant-store, qdrant-find, run_agents_parallel │
│  Role: Discover one service group, store in KB                   │
│                                                                  │
│  Normal flow (< 50 resources):                                   │
│    call_aws("describe-vpcs --query ...") → qdrant-store → done   │
│                                                                  │
│  Large resource flow (50+ resources):                            │
│    call_aws("list-buckets --query Buckets[].Name")               │
│    → sees 1000 buckets                                           │
│    → run_agents_parallel([                                       │
│        "Detail buckets 1-25, store in KB",                       │
│        "Detail buckets 26-50, store in KB",                      │
│        "Detail buckets 51-75, store in KB",                      │
│        ...                                                       │
│      ])                                                          │
└──────┬───────────────────────────────────────────────────────────┘
       │ run_agents_parallel
       │ (via aura-worker MCP, same endpoint)
       ▼
┌──────────────────────────────────────────────────────────────────┐
│  SUB-WORKERS (port 8080, called M times in parallel)             │
│  Same config as workers — but these handle a specific chunk      │
│  and do NOT sub-delegate further (max 1 level of delegation)     │
│                                                                  │
│  call_aws("get-bucket-tagging --bucket X --query ...")           │
│  qdrant-store(bucket details)                                    │
│  → return summary to parent worker                               │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│  QDRANT KNOWLEDGE BASE (port 6333)                               │
│  Shared across all agents — orchestrator, workers, sub-workers   │
│                                                                  │
│  Collection: aws_resources                                       │
│  All discovery results end up here regardless of which agent     │
│  stored them. Orchestrator reads from here for synthesis.        │
└──────────────────────────────────────────────────────────────────┘
```

## Delegation Rules

### When the Orchestrator Delegates

The orchestrator NEVER queries AWS directly. It always delegates via `run_agent`
or `run_agents_parallel`. Its job is to:

1. Determine scope (which services, which regions)
2. Get resource counts (via a worker)
3. Dispatch parallel workers per service
4. Synthesize results from the knowledge base
5. Report to user

### When a Worker Sub-Delegates

A worker queries AWS directly for most tasks. It sub-delegates only when:

| Condition | Action |
|-----------|--------|
| Resource count > 50 | Split into chunks, use run_agents_parallel |
| call_aws response truncated or too large | Split the query into smaller ranges |
| Detailed enumeration needed on many items | Chunk by ID ranges |

### Chunk Size Guidelines

| Resource Type | Chunk Size | Reason |
|--------------|-----------|--------|
| S3 buckets | 25 per worker | Each needs location, tags, versioning, encryption checks |
| VPCs | 10 per worker | Each has subnets, route tables, SGs to enumerate |
| EC2 instances | 20 per worker | Need SG, subnet, IAM role details |
| Lambda functions | 30 per worker | Relatively lightweight per function |
| IAM roles | 25 per worker | Need attached policies, trust policy |
| Security groups | 20 per worker | Need full inbound/outbound rule details |

### Delegation Depth Limit

```
Orchestrator → Worker → Sub-Worker → (STOP, no further delegation)
```

Sub-workers do NOT delegate further. This prevents infinite recursion and keeps
the pattern predictable. One level of delegation is sufficient because sub-workers
handle a small enough chunk to fit in a single context window.

## Service Components

| Component | Port | Config | Role |
|-----------|------|--------|------|
| Qdrant DB | 6333 | Docker image | Persistent vector storage |
| AWS MCP (via mcp-proxy) | 8091 | mcp-proxy wrapping awslabs.aws-api-mcp-server | AWS API access |
| Qdrant MCP | 8000 | mcp-server-qdrant | KB read/write |
| Aura Worker MCP | 8095 | mcp-proxy wrapping mcp-servers/aura-worker/server.py | Agent delegation |
| Worker Aura | 8080 | aws-discovery-agent.toml | Discovery execution |
| Orchestrator Aura | 3030 | aws-orchestrator-agent.toml | Coordination |

## Data Flow Example: 1000 S3 Buckets

```
1. User → Orchestrator: "Discover all S3 buckets"

2. Orchestrator → Worker (via run_agent):
   "Count S3 buckets: aws s3api list-buckets --query 'length(Buckets)'"
   → Worker returns: "1000 buckets"

3. Orchestrator → Workers (via run_agents_parallel):
   "Discover S3 buckets and store in KB"
   → Single worker receives task

4. Worker runs: aws s3api list-buckets --query "Buckets[].Name"
   → Gets list of 1000 bucket names
   → Decides: 1000 > 50, need to sub-delegate

5. Worker → Sub-Workers (via run_agents_parallel, 40 workers):
   [
     "Detail buckets bucket-001 through bucket-025. For each:
      aws s3api get-bucket-location, get-bucket-tagging.
      Store in qdrant with collection_name aws_resources.",
     "Detail buckets bucket-026 through bucket-050...",
     ... (40 chunks of 25)
   ]

6. Each sub-worker:
   - Runs 2-3 aws calls per bucket (location, tags, versioning)
   - Stores each bucket in Qdrant
   - Returns: "25 buckets stored"

7. Worker collects: "1000 buckets stored by 40 sub-workers"
   → Returns summary to orchestrator

8. Orchestrator:
   - Searches Qdrant for all S3 data
   - Reports: "1000 S3 buckets discovered and cataloged"

Total context used by orchestrator: ~2000 tokens (summaries only)
Total context used by each sub-worker: ~5000 tokens (25 buckets)
No single agent exceeds context limits.
```

## How to Run

### Local Development

```bash
# 1. Start Qdrant
docker run -d --name qdrant -p 6333:6333 qdrant/qdrant

# 2. Start AWS MCP (via mcp-proxy)
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=us-east-1
uvx mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8091 \
  -e READ_OPERATIONS_ONLY true -e AWS_REGION $AWS_REGION \
  -e AWS_ACCESS_KEY_ID $AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY $AWS_SECRET_ACCESS_KEY \
  -- awslabs.aws-api-mcp-server &

# 3. Start Qdrant MCP
QDRANT_URL=http://localhost:6333 COLLECTION_NAME=aws_resources \
  mcp-server-qdrant --transport streamable-http &

# 4. Start Worker Aura (port 8080)
CONFIG_PATH=examples/mcp-servers/aws/aws-discovery-agent.toml \
  aura-web-server &

# 5. Start Aura Worker MCP (port 8095, wraps worker aura)
uvx mcp-proxy --transport streamablehttp --host 127.0.0.1 --port 8095 \
  -e AURA_WORKER_URL http://127.0.0.1:8080 \
  -- python mcp-servers/aura-worker/server.py &

# 6. Start Orchestrator Aura (port 3030)
CONFIG_PATH=examples/mcp-servers/aws/aws-orchestrator-agent.toml \
  aura-web-server --port 3030 &

# 7. Run discovery
curl -s http://localhost:3030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Run a full environment discovery"}]}'
```

### Docker Compose

All services are defined in `examples/mcp-servers/aws/docker-compose.yml`.

```bash
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=us-east-1
docker compose up -d
curl -s http://localhost:3030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Run a full environment discovery"}]}'
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Orchestrator doesn't query AWS | Keeps orchestrator context tiny — only summaries |
| Workers can sub-delegate | Handles large resource sets without context overflow |
| Max 1 level of delegation | Prevents infinite recursion, keeps pattern predictable |
| All agents share Qdrant | Single source of truth, any agent can read any other's results |
| Workers are the same config | No special sub-worker config — same discovery agent handles both roles |
| mcp-proxy for HTTP transport | Works around aura's per-request MCP connection lifecycle |

## Comparison to Single-Agent Discovery

| Metric | Single Agent | Orchestrator + Workers |
|--------|-------------|----------------------|
| Max resources per request | ~100 (context limit) | Unlimited (chunked) |
| Time for 5 services | 30-60s (sequential) | 39s (parallel) |
| Time for 1000 S3 buckets | Fails (context overflow) | ~2 min (40 parallel workers) |
| Context usage | Accumulates per turn | Each worker starts fresh |
| Failure impact | Entire scan lost | Only failed chunk retried |
