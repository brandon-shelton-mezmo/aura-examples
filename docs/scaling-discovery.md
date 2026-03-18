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

### Path 2: Agent Orchestration (Most Powerful)

**What:** An orchestrator agent spawns worker agents, each with its own context
window. Workers handle one service each. Orchestrator collects summaries.

**Example:**
```
Orchestrator receives: "Full environment discovery"
  → Spawns: VPC-worker, EC2-worker, S3-worker, Lambda-worker (parallel)
  → Each worker: call_aws → qdrant-store → return "Found X resources"
  → Orchestrator: collects summaries → synthesizes → reports
```

**For large environments (72 VPCs):**
```
Orchestrator: call_aws("describe-vpcs --query Vpcs[].VpcId")
  → Gets 72 VPC IDs
  → Spawns 7 workers (10 VPCs each) in parallel
  → Each worker: describe-vpc-detail → store → return summary
  → Orchestrator: "72 VPCs discovered and stored"
```

**Impact:** Unlimited scale. Full parallelism. Each worker has a clean context.

**Effort:** High. Requires the multi-agent orchestration feature that's on aura's
roadmap (`aura.worker_phase` SSE event). Not available today.

**Aura roadmap reference:**
- `docs/streaming-api-guide.md:68` — `aura.worker_phase` marked as "Future"
- `docs/aura-customer-deployment-guide.md:851` — "Multi-Agent Mode" listed
- `docs/aura-sre-developer-use-cases.md:683` — "Incident Commander + Service Investigators"

### Path 3: Custom Discovery MCP Server (No Aura Changes)

**What:** Build a custom MCP server that does discovery internally (using boto3
and qdrant-client directly) and returns only summaries to the LLM.

**Example tool:**
```python
@server.tool()
def discover_vpcs(region: str) -> str:
    """Discover VPCs and store in knowledge base. Returns summary only."""
    vpcs = boto3.client('ec2', region_name=region).describe_vpcs()
    # Process, format, store in Qdrant directly
    qdrant.upsert(collection="aws_resources", points=[...])
    return f"Discovered {len(vpcs)} VPCs. Stored in knowledge base."
```

The LLM sees a 50-token summary instead of 50K of JSON. Context stays tiny.
Full environment scan in one request.

**Impact:** Solves the problem completely. No aura changes. Buildable today.

**Effort:** Medium. Need to write a Python MCP server wrapping boto3 + qdrant-client.
~500 lines of code. One tool per service group, plus a `full_discovery()` that
calls them all.

**Trade-off:** This moves intelligence OUT of the LLM and into code. The LLM no
longer reasons about raw AWS data — it just orchestrates pre-built discovery tools.
Less flexible, but much more reliable and scalable.

## Recommendation

**Short term:** Path 3 (custom MCP server). Buildable today, solves the problem,
no aura changes needed. The LLM orchestrates, the MCP server does the heavy lifting.

**Medium term:** Path 1 (context compression). Makes the generic `call_aws` approach
scale. Benefits all agents, not just discovery.

**Long term:** Path 2 (agent orchestration). The most powerful and flexible, but
requires the most aura development. Enables true parallelism for massive environments.

All three paths are complementary — you could ship Path 3 now, add Path 1 to make
ad-hoc queries scale, and add Path 2 for the full multi-agent SRE platform vision.
