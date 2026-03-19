# Hybrid Storage Architecture — GitHub Repo + Qdrant

## The Approach

Use both Git and Qdrant, each for what it does best:

```
Discovery Agent
  │
  ├── Writes YAML files to a Git repo (structured source of truth)
  │     └── Commit per scan → git diff shows exactly what changed
  │
  └── Stores in Qdrant (semantic search for agents)
        └── Upsert with cleanup → one copy per resource, always current
```

**Git is the source of truth.** Structured YAML, version-controlled, human-browsable.
**Qdrant is the search index.** Semantic search, fast retrieval, agent-friendly.

## Why Both

| Need | Git Repo | Qdrant | Winner |
|------|---------|--------|--------|
| Version history / diff | `git log`, `git diff` | Nothing | Git |
| Change tracking | Commit messages, PR history | Requires separate [CHANGE] docs | Git |
| Human visibility | Browse on GitHub | Opaque without tooling | Git |
| Deduplication | One file per resource, overwrite | Random UUID per store, duplicates | Git |
| Structured data | YAML, parseable, lintable | Free-text, LLM-dependent quality | Git |
| Semantic search | Not possible | "What relates to checkout?" works | Qdrant |
| Natural language queries | Not possible | Core capability | Qdrant |
| Agent query speed | Clone + grep (slow) | Milliseconds | Qdrant |
| Relationship traversal | Parse YAML references | Semantic match on "→ VPC: X" | Both |

## Git Repo Structure

```
aws-inventory/
├── us-east-1/
│   ├── ec2/
│   │   ├── instances/
│   │   │   ├── i-0cf9995ffb0ac0a5b.yaml
│   │   │   ├── i-07595a32e5d252ca2.yaml
│   │   │   └── ...
│   │   ├── vpcs/
│   │   │   ├── vpc-0e7b33f367e8985c5.yaml
│   │   │   └── ...
│   │   ├── security-groups/
│   │   │   ├── sg-0d5264943fcd04259.yaml
│   │   │   └── ...
│   │   └── subnets/
│   │       └── ...
│   ├── lambda/
│   │   ├── mezmo_pipeline_http_ritahnabaggala.yaml
│   │   └── ...
│   ├── ecs/
│   │   └── ...
│   ├── rds/
│   │   └── ...
│   ├── elbv2/
│   │   └── ...
│   ├── sqs/
│   │   └── ...
│   └── cloudwatch/
│       └── ...
├── global/
│   ├── s3/
│   │   ├── 8451-archiving-bucket.yaml
│   │   └── ...
│   ├── iam/
│   │   ├── roles/
│   │   │   ├── AWSServiceRoleForAccessAnalyzer.yaml
│   │   │   └── ...
│   │   └── policies/
│   │       └── ...
│   └── route53/
│       └── ...
├── scans/
│   ├── scan-2026-03-19-001.yaml    # Manifest for each scan
│   ├── scan-2026-03-19-002.yaml
│   └── ...
└── README.md
```

## YAML Resource Format

```yaml
# vpc-0e7b33f367e8985c5.yaml
arn: "arn:aws:ec2:us-east-1:627029844476:vpc/vpc-0e7b33f367e8985c5"
service: ec2
type: vpc
name: "Default VPC"
region: us-east-1
account: "627029844476"
scan_id: scan-2026-03-19-002
discovered: "2026-03-19T17:08:48Z"

configuration:
  cidr_block: "172.31.0.0/16"
  is_default: true
  state: available
  dhcp_options: dopt-02732cf586a71980e

tags:
  Name: "Default VPC"

relationships:
  subnets:
    - id: subnet-abc123
      az: us-east-1a
    - id: subnet-def456
      az: us-east-1b
  security_groups:
    - id: sg-0d5264943fcd04259
      name: default
  instances:
    - id: i-0cf9995ffb0ac0a5b
      name: otel-demo-docker
    - id: i-07595a32e5d252ca2
      name: otel-demo-k8s
  load_balancers:
    - arn: "arn:aws:elasticloadbalancing:us-east-1:627029844476:loadbalancer/net/..."
      name: api-nlb

summary: >
  Default VPC in us-east-1 with CIDR 172.31.0.0/16. Contains 6 subnets
  across all AZs, multiple OpenTelemetry demo instances, and the default
  security group. Used primarily for demo and test workloads.
```

## What This Solves

### Problem 1: Versioning and Change Tracking

**Before (Qdrant only):** No way to see what changed between scans. Duplicates accumulate.

**After (Git + Qdrant):**
```bash
# What changed in the last scan?
git diff HEAD~1 aws-inventory/

# When did this VPC's config change?
git log aws-inventory/us-east-1/ec2/vpcs/vpc-0e7b33f367e8985c5.yaml

# What did the environment look like last Tuesday?
git show HEAD~5:aws-inventory/us-east-1/ec2/instances/

# Who/what triggered the change?
git log --format='%ai %s' aws-inventory/
```

The Change Audit agent doesn't need to build [CHANGE] documents anymore —
it can just read `git diff` from the repo.

### Problem 2: Deduplication

**Before:** `qdrant-store` generates a random UUID every time. Same VPC stored
3 times = 3 documents in Qdrant with different IDs.

**After:** One file per resource. Discovery overwrites the file:
```
aws-inventory/us-east-1/ec2/vpcs/vpc-0e7b33f367e8985c5.yaml
```

Always one copy. Git tracks the history. Qdrant gets synced from the file.

### Problem 3: Document Quality

**Before:** LLM generates free-text documents with inconsistent formatting.
Some have Relationships sections, some don't. Some have Version numbers, some don't.

**After:** YAML schema is consistent. Every file has the same fields.
A linter can validate the format. The LLM fills in a template, not inventing structure.

### Problem 4: Human Visibility

**Before:** Only agents can read Qdrant. No way to browse the inventory.

**After:** Browse on GitHub. Search with GitHub's code search. Link specific
resources in Slack conversations. Review changes via Pull Requests.

## Keeping Qdrant Current (Dedup via Delete-Before-Store)

The Qdrant MCP server (`mcp-server-qdrant`) uses random UUIDs, so every `qdrant-store`
creates a new point. To keep only the latest copy, we need a delete-before-store pattern.

### Option A: REST API Cleanup in the Sync Process

When syncing from Git to Qdrant, delete existing points for the resource first:

```python
# Before upserting, delete by ARN filter
qdrant_client.delete(
    collection_name="aws_resources",
    points_selector=models.FilterSelector(
        filter=models.Filter(
            must=[
                models.FieldCondition(
                    key="metadata.arn",
                    match=models.MatchValue(value=resource_arn)
                )
            ]
        )
    )
)

# Then store the new version
qdrant_client.upsert(
    collection_name="aws_resources",
    points=[models.PointStruct(
        id=deterministic_id_from_arn(resource_arn),
        vector=embed(resource_text),
        payload={"document": resource_text, "metadata": {...}}
    )]
)
```

### Option B: Custom MCP Server with Upsert

Build a thin MCP server wrapping Qdrant that generates deterministic IDs from ARNs:

```python
import hashlib

def arn_to_id(arn: str) -> str:
    """Generate a deterministic UUID from an ARN."""
    return hashlib.md5(arn.encode()).hexdigest()

@server.tool()
async def store_resource(information: str, arn: str, collection_name: str, metadata: dict):
    """Store a resource, overwriting any existing document with the same ARN."""
    point_id = arn_to_id(arn)
    embeddings = embed(information)
    await qdrant_client.upsert(
        collection_name=collection_name,
        points=[PointStruct(id=point_id, vector=embeddings, payload={...})]
    )
```

Because `upsert` with the same ID overwrites, this naturally deduplicates.

### Option C: Periodic Cleanup Job

A scheduled script that:
1. Groups points by `metadata.arn`
2. For each ARN with multiple points, keeps the one with highest `metadata.version`
3. Deletes the rest

```bash
# Run weekly
python scripts/cleanup-qdrant.py --collection aws_resources --keep-latest
```

### Recommendation: Option B (Custom MCP) for the agent workflow, Option A for the Git sync.

## The Repo-to-Qdrant Sync Agent

### What It Does

Reads YAML files from the Git repo and syncs them into Qdrant. This is a one-way
sync: Git → Qdrant. The repo is the source of truth.

### When It's Useful

- After a manual edit to a YAML file (human corrects a tag, adds a relationship)
- After merging a PR that updates inventory data
- To rebuild Qdrant from scratch (cold start, new cluster)
- To keep Qdrant in sync if the discovery agent writes to Git only

### When It's NOT Useful

- If agents write to both Git and Qdrant simultaneously (already in sync)
- If Qdrant is the only consumer (no need for Git layer)
- For real-time sync (Git commits are too slow for sub-second updates)

### What Benefit It Provides

The main value is **decoupling the write path from the read path:**

```
WRITE PATH (discovery):
  Agent → AWS API → YAML files → Git commit
  (Structured, versioned, human-reviewable)

SYNC:
  Git repo → Sync agent → Qdrant
  (Automated, can run on webhook or schedule)

READ PATH (all other agents):
  Agent → Qdrant → semantic search → answer
  (Fast, natural language, relationship traversal)
```

This means:
- Discovery can be validated before it reaches Qdrant (PR review)
- Qdrant can be rebuilt from Git at any time (disaster recovery)
- Manual corrections in Git propagate to Qdrant automatically
- The sync agent handles dedup (one file = one point in Qdrant)

### When NOT to Build It

If the discovery agents write directly to both Git and Qdrant in parallel,
the sync agent is redundant for the initial write. It's only needed for:
- Git → Qdrant rebuild/recovery
- Manual edits propagating to Qdrant
- External systems writing to the Git repo

## Implementation Phases

### Phase 1: Git as Output (Now)

Add Git writing to the discovery agent alongside Qdrant:
- Discovery agent uses a Git MCP server to commit YAML files
- Agent writes to both Git and Qdrant in the same scan
- Git provides history, Qdrant provides search

### Phase 2: Custom Qdrant MCP with Dedup (Next)

Build a thin MCP server wrapping Qdrant with deterministic IDs:
- `store_resource(information, arn, collection_name, metadata)` → upsert by ARN hash
- `delete_resource(arn, collection_name)` → delete by ARN
- `find_resource(query, collection_name)` → semantic search (same as current)
- Eliminates duplicates entirely

### Phase 3: Git-to-Qdrant Sync Agent (Later)

Build when:
- Humans need to edit inventory data and have it reflected in agent queries
- Qdrant needs to be rebuilt from scratch
- External systems write to the Git repo

Not needed if agents write to both simultaneously.
