# Scaling Discovery for Large AWS Environments

## The Problem

When the discovery agent scans AWS resources, each `call_aws` response (VPCs, EC2
instances, S3 buckets, etc.) stays in the LLM's context window for all subsequent
turns. After 5-6 tool calls, the context is full and Bedrock times out.

This means a single request can discover roughly one service group (VPCs, or S3, or
Lambda) before hitting context limits. A full environment scan of a non-trivial AWS
account requires multiple requests.

This is NOT an aura bug — it's a fundamental LLM constraint. The context window has
a finite size, and raw AWS API responses are large.

## What Works Today

### Individual service discovery (single request)

Each request handles one scope completely:

```
Request 1: "Discover VPCs and security groups. Store in knowledge base."
Request 2: "Discover EC2 and Lambda. Store in knowledge base."
Request 3: "Discover S3 and IAM roles. Store in knowledge base."
Request 4: "What's the full picture? Search the knowledge base."
```

Each request is self-contained. The agent discovers, stores, and reports within
one call. The knowledge base accumulates across requests.

### Filtered output with --query

Using JMESPath `--query` in AWS CLI commands reduces response size dramatically:

```
BAD:  aws ec2 describe-vpcs                    (returns ~50K tokens for 13 VPCs)
GOOD: aws ec2 describe-vpcs --query "Vpcs[].{Id:VpcId,Cidr:CidrBlock}"  (~500 tokens)
```

The discovery agent's system prompt includes `--query` examples for every service.

## Three Paths to Single-Shot Full Discovery

### Path 1: Context Compression in Aura (Recommended)

**What:** After the agent processes a tool result and stores it in Qdrant, aura
replaces the raw result in the context with a short summary.

**Example flow:**
```
Turn 1: call_aws("describe-vpcs") → LLM receives 50K token JSON
Turn 2: LLM calls qdrant-store(vpc summary) → stored
         [Aura replaces 50K VPC JSON in context with: "VPC data: 13 VPCs stored"]
Turn 3: call_aws("list-buckets") → LLM receives 30K token JSON
         Context now has room because VPC data was compressed
Turn 4: LLM calls qdrant-store(s3 summary) → stored
         [Aura compresses S3 data too]
...continues through all services in one request
```

**Impact:** Agent could scan entire environment in one request. No multi-agent
needed for this use case.

**Effort:** Medium. Requires changes in aura's streaming handler to detect when
a tool result has been "consumed" (stored in Qdrant or referenced in LLM output)
and replace it with a summary in the conversation history for subsequent turns.

### Path 2: Agent Orchestration (Most Powerful) -- IMPLEMENTED

**Status:** Implemented and tested. See `docs/orchestrator-architecture.md`.

**What:** An orchestrator agent dispatches workers via the aura-worker MCP server.
Workers use `discover_and_store` (Path 3) for zero-context discovery.

**How it works now:**
```
Orchestrator receives: "Discover my AWS environment"
  → Batch 1: run_agents_parallel(5 workers — VPCs, EC2, S3, Lambda, IAM)
  → Batch 2: run_agents_parallel(5 workers — SGs, subnets, LBs, Route53, CFN)
  → retry_incomplete → fill any gaps from rate limit errors
  → Report: "363 resources, 10 service types, 0 duplicates"
```

**Implementation:** The aura-worker MCP (`mcp-servers/aura-worker/server.py`) wraps
aura's `/v1/chat/completions` API. It handles concurrency throttling (MAX_CONCURRENT=2),
staggered starts (DELAY_BETWEEN_WORKERS=5s), and retry on rate limits (MAX_RETRIES=3).
No changes to aura source were needed — this is built entirely with MCP + config.

### Path 3: Custom Discovery MCP Server (No Aura Changes) -- IMPLEMENTED

**Status:** Implemented and tested. See `mcp-servers/aura-qdrant/README.md`.

**What:** A custom MCP server (`mcp-servers/aura-qdrant/server.py`) that calls AWS
via boto3 and stores results in Qdrant directly. The LLM sees only a summary string.

**The actual tool (simplified):**
```python
@server.tool()
def discover_and_store(service_type: str, collection_name: str, scan_id: str, region: str = "us-east-1") -> str:
    config = AWS_DISCOVERY_CONFIG[service_type]        # e.g., ec2/vpc → describe_vpcs
    client = boto3.client(config["client"], region_name=region)
    items = getattr(client, config["method"])()        # calls AWS directly
    for item in items:
        doc, arn, meta = _build_resource_doc(item, ...)  # structured [RESOURCE] document
        vector = embed_text(doc)                          # FastEmbed
        qdrant.upsert(points=[PointStruct(id=md5(arn), vector=vector, payload=...)])
    return f"Discovered and stored {len(items)} {service_type} resources"
```

The LLM sees a 50-token summary instead of 50K of JSON. Context stays tiny.

**12 supported service types:** ec2/vpc, ec2/instance, ec2/security-group, ec2/subnet,
s3/bucket, lambda/function, iam/role, elbv2/load-balancer, route53/hosted-zone,
cloudformation/stack, rds/instance, dynamodb/table.

**Key features beyond the original proposal:**
- Deterministic IDs from `md5(arn)` — re-running produces 0 duplicates
- Metadata payload indexes for filtered search (service, region, type, scan_id)
- Batch upsert in groups of 50 for performance
- Auto-detect AWS account ID via STS
- ~1100 lines of code (more than the estimated 500, due to robust JSON parsing
  in `bulk_store_resources` and relationship extraction)

## Current Status

**Path 2 (Agent Orchestration) and Path 3 (Custom Discovery MCP) are both implemented
and working together.** This combination is the production architecture.

### Path 3: IMPLEMENTED — `discover_and_store`

The custom Qdrant MCP server (`mcp-servers/aura-qdrant/server.py`) implements the exact
pattern described above. The `discover_and_store` tool calls AWS via boto3 and stores
results in Qdrant in a single MCP tool call. The LLM sees only a summary string.

12 service types are supported: ec2/vpc, ec2/instance, ec2/security-group, ec2/subnet,
s3/bucket, lambda/function, iam/role, elbv2/load-balancer, route53/hosted-zone,
cloudformation/stack, rds/instance, dynamodb/table.

See: `mcp-servers/aura-qdrant/README.md`

### Path 2: IMPLEMENTED — Orchestrator + Workers

The orchestrator agent (`aws-orchestrator-agent.toml`) dispatches 2 batches of 5
parallel workers via the worker MCP (`mcp-servers/aura-worker/server.py`). Each worker
makes a single `discover_and_store` call. The worker MCP handles throttling
(MAX_CONCURRENT=2, staggered starts) and retry on rate limits.

Tested result: 363 resources, 10 service types, 0 duplicates, 0 errors.

See: `docs/orchestrator-architecture.md`, `mcp-servers/aura-worker/README.md`

### Path 1: NOT YET IMPLEMENTED — Context Compression in Aura

Still on the aura roadmap. Would benefit ad-hoc queries that use `call_aws` directly
(incident response, change audit agents). Not needed for discovery now that
`discover_and_store` handles it.

## Recommendation

**For discovery:** Use the orchestrator + `discover_and_store` (Paths 2+3). This is the
tested, working architecture.

**For ad-hoc queries:** The non-discovery agents (incident response, change audit,
capacity planning) still use `call_aws` directly and benefit from Path 1 (context
compression) when it ships in aura. For now, keep their queries focused on specific
resources rather than broad scans.
