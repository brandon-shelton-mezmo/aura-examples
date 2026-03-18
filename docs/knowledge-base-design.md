# Knowledge Base Design — Versioning, Relationships, and Document Structure

## Current State (Problems)

After running discovery against a live AWS account, we found:

| Issue | Current | Target |
|-------|---------|--------|
| Versioning | 0/39 docs have version numbers | Every doc has version + scan ID |
| Duplicates | 7 resources stored 2-3 times | One canonical doc per resource, old versions expired |
| Relationships | 24/39 have some cross-references | Every doc has a structured Relationships section |
| Document format | 2 styles (summary vs per-resource) | One consistent format per resource |
| Traversal | Search by keyword only | Search → find related → traverse chains |

## Solution: Structured Document Format

### Resource Document Template

Every resource stored in Qdrant MUST follow this exact format. This is enforced
by the discovery agent's system prompt.

```
[RESOURCE] Service: EC2 | Type: Instance | Version: 3 | Scan: scan-2026-03-18-001
ARN: arn:aws:ec2:us-east-1:627029844476:instance/i-0cf9995ffb0ac0a5b
Name: otel-demo-docker | Region: us-east-1 | Account: 627029844476

Configuration:
  Instance Type: t2.xlarge
  State: running
  AMI: ami-0abcdef1234567890
  Launch Time: 2025-11-15T10:30:00Z

Networking:
  VPC: vpc-0e7b33f367e8985c5 (Default VPC)
  Subnet: subnet-abc123 (us-east-1a)
  Private IP: 10.0.1.50
  Security Groups: sg-0d5264943fcd04259 (default)

Identity:
  IAM Role: arn:aws:iam::627029844476:role/otel-demo-role
  Key Pair: otel-demo-key

Tags:
  Name=otel-demo-docker, project=observability, team=platform, env=demo

Relationships:
  → VPC: vpc-0e7b33f367e8985c5 (Default VPC)
  → Subnet: subnet-abc123
  → Security Group: sg-0d5264943fcd04259 (default)
  → IAM Role: arn:aws:iam::627029844476:role/otel-demo-role
  → Related: otel-demo-k8s (same project tag)
  → Related: otel-demo-k8s-edge (same project tag)

Discovered: 2026-03-18T21:00:00Z
---
Running t2.xlarge EC2 instance "otel-demo-docker" in the default VPC (us-east-1).
Part of the OpenTelemetry demo infrastructure alongside otel-demo-k8s and
otel-demo-k8s-edge. Owned by platform team, demo environment.
```

### Key Format Rules

| Rule | Why |
|------|-----|
| `[RESOURCE]` prefix | Distinguishes from `[CHANGE]`, `[DRIFT]`, `[MANIFEST]` documents |
| `Version: N` in header | Enables "use the highest version" deduplication |
| `Scan: scan-YYYY-MM-DD-NNN` | Groups all docs from the same discovery run |
| ARN on its own line | Enables exact-match searches for a specific resource |
| Structured `Relationships:` section | Arrow format (→) makes traversal queries work |
| Tags on their own line | Enables ownership queries ("team=platform") |
| Summary after `---` | Human-readable context for the LLM |

### Relationship Format

The `Relationships:` section uses a consistent arrow format:

```
Relationships:
  → VPC: vpc-0e7b33f367e8985c5 (Default VPC)
  → Subnet: subnet-abc123
  → Security Group: sg-0d5264943fcd04259 (default)
  → IAM Role: arn:aws:iam::627029844476:role/otel-demo-role
  → Load Balancer: arn:aws:elasticloadbalancing:...
  → Depends On: prod-checkout-db (RDS, application dependency)
  → Triggers: arn:aws:sqs:us-east-1:...:order-queue (event source)
  → Related: otel-demo-k8s (same project tag)
```

**Relationship types:**
- `→ VPC:` / `→ Subnet:` / `→ Security Group:` — networking containment
- `→ IAM Role:` — identity/permissions
- `→ Load Balancer:` / `→ Target Group:` — traffic routing
- `→ Depends On:` — application-level dependency (database, cache, queue)
- `→ Triggers:` / `→ Triggered By:` — event-driven connections
- `→ Related:` — same tag group, same project, co-located

**Why arrows?** Semantic search on "→ VPC: vpc-abc123" reliably finds all resources
in that VPC. The arrow + type prefix + ID format is consistent enough for the LLM
to parse and traverse.

### How Relationship Traversal Works

When the incident response agent asks "what depends on vpc-abc123?":

```
Step 1: qdrant-find("→ VPC: vpc-abc123")
  → Returns: EC2 instances, ECS services, Lambda functions in that VPC

Step 2: For each EC2 instance found, get its security groups:
  qdrant-find("→ Security Group: sg-xyz789")
  → Returns: all resources sharing that SG

Step 3: For each IAM role found:
  qdrant-find("→ IAM Role: arn:aws:iam::...:role/my-role")
  → Returns: all resources using that role

Result: Full blast radius map from a single VPC.
```

This works because EVERY document includes the full Relationships section, and
semantic search matches the arrow-format cross-references.

## Versioning Strategy

### How Versioning Works

Each discovery scan generates a scan ID: `scan-2026-03-18-001`

Every document stored during that scan includes:
- `Version: N` — increments each time this specific resource is re-scanned
- `Scan: scan-2026-03-18-001` — identifies which scan produced this document

```
First scan:   [RESOURCE] ... | Version: 1 | Scan: scan-2026-03-18-001
Second scan:  [RESOURCE] ... | Version: 2 | Scan: scan-2026-03-19-001
Third scan:   [RESOURCE] ... | Version: 3 | Scan: scan-2026-03-20-001
```

### Handling Duplicates

Since Qdrant MCP only adds documents (no update/delete via MCP tools), old versions
accumulate. This is managed by:

**1. LLM-side deduplication (in system prompt)**

The agent is instructed: "When multiple documents match the same resource (same ARN),
always use the one with the highest Version number."

**2. Pre-scan: Check existing version**

Before storing a resource, the discovery agent should:
```
qdrant-find("ARN: arn:aws:ec2:...:instance/i-0cf9995ffb0ac0a5b")
→ Found Version: 2
→ Store new document with Version: 3
```

**3. Cleanup job (periodic, outside aura)**

A scheduled script (not an agent) calls the Qdrant REST API directly to:
- Find all documents for the same ARN
- Keep the highest version
- Delete older versions

```bash
# Example cleanup (runs weekly)
curl -X POST http://localhost:6333/collections/aws_resources/points/delete \
  -H "Content-Type: application/json" \
  -d '{"filter": {"must": [{"key": "metadata.arn", "match": {"value": "..."}}]}}'
```

This requires storing the ARN in the metadata field (not just in the document text)
so Qdrant can filter on it.

### Metadata Fields

Every `qdrant-store` call should include metadata for filtering:

```python
qdrant-store(
    information="[RESOURCE] Service: EC2 | Type: Instance | Version: 3 ...",
    collection_name="aws_resources",
    metadata={
        "arn": "arn:aws:ec2:us-east-1:627029844476:instance/i-0cf9995ffb0ac0a5b",
        "service": "ec2",
        "resource_type": "instance",
        "version": 3,
        "scan_id": "scan-2026-03-18-001",
        "region": "us-east-1",
        "account": "627029844476"
    }
)
```

Note: The Qdrant MCP server's `qdrant-find` doesn't support metadata filtering
today (it's pure semantic search). The metadata is stored for future use by:
- The cleanup job (direct Qdrant API, supports filtering)
- Future MCP server versions that may add filtered search
- Any custom tooling that queries Qdrant directly

## Summary Documents vs Resource Documents

The current KB has two types that should be clearly separated:

### Resource Documents (one per resource)
```
[RESOURCE] Service: EC2 | Type: Instance | Version: 1 | Scan: scan-001
ARN: arn:aws:ec2:...:instance/i-abc123
...per-resource details...
```

### Service Summary Documents (one per service per scan)
```
[SUMMARY] Service: EC2 | Scan: scan-001
Region: us-east-1 | Account: 627029844476
Total Instances: 26 (7 running, 19 stopped)
Instance Types: 8x t2.xlarge, 5x t3.medium, 4x t3.large, ...
Key Findings: 73% instances stopped, 3 otel-demo instances running
Issues: No tagging on 8 instances
```

Summary documents are useful for quick overviews ("how many EC2 instances?")
without retrieving every individual resource document. They complement, not
replace, individual resource documents.

## Relationship Graph Example

Here's how the stored relationships enable dependency mapping:

```
Route 53: api.example.com
  │  → ALB: arn:aws:elasticloadbalancing:...:app/api-alb
  │
  └──► ALB: api-alb
        │  → Target Group: api-tg
        │  → VPC: vpc-abc123
        │  → Security Group: sg-alb-public
        │
        └──► ECS Service: api-service
              │  → Cluster: prod-cluster
              │  → Task Definition: api-task:42
              │  → IAM Task Role: api-task-role
              │  → Security Group: sg-api-private
              │  → Subnet: subnet-private-1, subnet-private-2
              │  → Load Balancer: api-alb (via target group)
              │  → Depends On: api-database (RDS)
              │  → Log Group: /ecs/api-service
              │
              └──► RDS: api-database
                    │  → VPC: vpc-abc123
                    │  → Subnet Group: db-subnets
                    │  → Security Group: sg-db-private
                    │  → Parameter Group: pg15-params
                    │  → Multi-AZ: true
```

Each box in this tree is a document in Qdrant. The arrows are in the
`Relationships:` section of each document. An agent traverses this by:

1. Search for the starting resource
2. Read its Relationships section
3. Search for each referenced resource
4. Read their Relationships sections
5. Continue until the desired depth is reached

No graph database needed — the structured text format enables traversal
through sequential semantic searches.
