# Aura SRE Platform — Vision & Technology Decisions

## Vision

Aura is a foundational AI platform for engineering teams. By co-locating knowledge
from four data sources — the live AWS environment, infrastructure as code, code
repositories, and observability data — into a shared semantic knowledge base, AI
agents can reason across the full stack to troubleshoot issues, assess change risk,
construct post-mortems, and provide architectural guidance.

No single data source provides a complete picture:

```
"Why is checkout slow?"

AWS Environment alone:  "ECS service is running, 3 healthy tasks"
                        (doesn't know it's slow)

Observability alone:    "p99 latency spiked to 2s at 14:15"
                        (doesn't know why)

IaC alone:              "Terraform applied at 14:10, changed RDS instance class"
                        (doesn't know the impact)

Code alone:             "No connection pooling, opens new DB connection per request"
                        (doesn't know about the infra change)

ALL FOUR TOGETHER:      "Terraform downsized RDS from db.r5.xlarge to db.t3.micro
                        at 14:10. The checkout service opens a new DB connection
                        per request (no pooling). The smaller instance can't handle
                        the connection volume. p99 latency spiked to 2s.
                        Fix: add connection pooling or revert the RDS change."
```

## The Four Pillars

### Pillar 1: AWS Environment (What Exists)

**What it provides:** Running resources, configurations, relationships, network
topology, IAM permissions, current state.

**Without it:** Agents don't know what's deployed, what connects to what, or
what the blast radius of a change is.

**Status:** Built. Discovery agent, orchestrator, parallel workers, Qdrant storage.

### Pillar 2: Infrastructure as Code (How It Got There)

**What it provides:** Intended state, deployment history, who approved changes,
Terraform/CDK module structure, drift detection between IaC and actual state.

**Without it:** Can't distinguish intentional changes from drift. Can't trace
a resource back to the code that created it. Can't answer "who owns this?"
from the IaC perspective.

**Integration path:** Git MCP server to read Terraform/CDK repos. Index module
definitions, resource mappings, and variable configs into the knowledge base.
Cross-reference with AWS resource ARNs to link IaC → live resources.

### Pillar 3: Code Repositories (What It Does)

**What it provides:** Application logic, dependencies, configuration files,
error handling patterns, retry policies, README documentation, team ownership.

**Without it:** Can't understand why a service behaves a certain way. Can't
find the code causing an error. Can't identify which team owns what service.

**Integration path:** Same Git MCP server. Index service READMEs, dependency
files (package.json, go.mod, Cargo.toml), configuration, and key application
patterns. Link to AWS resources via service name tags.

### Pillar 4: Observability — MELT (How It's Behaving)

**What it provides:** Metrics (CPU, latency, error rates), Events (deploys,
scaling), Logs (application output, errors), Traces (request paths, latencies).

**Without it:** Don't know something is broken. Can't measure impact. Can't
find root cause in application behavior.

**Status:** MCP integrations exist for Datadog, Grafana, New Relic, Dynatrace,
and OpenTelemetry (38 configs in aura-examples). These query live data — they
don't need to be stored in the knowledge base.

## Cross-Pillar Correlation

The value multiplies when agents can reason across all four sources:

| Scenario | Pillars Used | What You Get |
|----------|-------------|-------------|
| **Incident triage** | AWS (what's affected) + MELT (what's broken) + IaC (what changed) + Code (why it breaks that way) | Full root cause in minutes instead of hours |
| **Pre-deploy risk** | IaC (what's about to change) + AWS (current state + dependencies) + Code (what depends on this) + MELT (current baseline) | "This change will affect 3 services handling 5K req/s" |
| **Post-mortem** | All four | Complete timeline from code change → IaC deploy → AWS state change → observability anomaly |
| **Capacity planning** | AWS (current resources) + MELT (utilization trends) + IaC (scaling limits in Terraform) | "Auto-scaling max is 10 but you're at 8 during peak" |
| **Onboarding** | Code (README, architecture) + AWS (what's deployed) + IaC (how to deploy) | New engineer understands the system in hours not weeks |
| **Architecture review** | All four | "This service has no circuit breaker (code), single-AZ RDS (AWS), no health check in Terraform (IaC), and no latency alarm (MELT)" |

## Technology Decision: Qdrant as the Knowledge Base

### Why a Vector Database

AI agents reason in natural language. When an agent investigates "why is checkout
slow?", it needs to find relevant resources, code, and config without knowing exact
field names, resource IDs, or query syntax.

| Search Type | Query | Result |
|------------|-------|--------|
| Exact match (SQL, grep) | `WHERE name = 'checkout'` | Finds the service definition. Nothing about "slow." |
| Full-text (Elasticsearch) | `checkout AND slow` | Only matches if both words appear. Misses the RDS dependency. |
| Semantic (Qdrant) | "why is checkout slow" | Finds: ECS service, RDS dependency, ALB config, recent deploy, Terraform change — by meaning, not keywords |

Semantic search is the core enabler for the natural language SRE experience.

### Why Qdrant Specifically

| Factor | Qdrant | Alternatives |
|--------|--------|-------------|
| **MCP server exists** | `mcp-server-qdrant` — proven with aura | Pinecone, Weaviate have no MCP servers |
| **Self-hosted** | Docker, runs in your VPC, $0 | Pinecone is cloud-only |
| **Built-in embeddings** | FastEmbed included, no OpenAI key needed | Most alternatives require external embedding API |
| **Lightweight** | Single binary, ~512MB RAM | Weaviate, Milvus are heavier |
| **Payload filtering** | Metadata fields alongside vectors | Critical for hybrid queries (semantic + structured) |
| **Performance** | Millisecond search at 100K+ documents | Sufficient for infrastructure knowledge base scale |

### Alternatives Considered

| Technology | Verdict | Reason |
|-----------|---------|--------|
| PostgreSQL + pgvector | Not ideal | Bolts vectors onto relational. No native embedding management. Agents can't easily query SQL. |
| Elasticsearch / OpenSearch | Complementary, not replacement | Great for log search (MELT pillar). Weak at semantic understanding for infrastructure queries. |
| Neo4j | Complementary for relationships | Excellent graph traversal but LLMs can't easily write Cypher. No semantic search. |
| Pinecone | Viable but locked in | Cloud-only, vendor lock-in, more expensive, no MCP server. |
| Weaviate | Strong alternative | Similar capabilities. Heavier to self-host. Could replace Qdrant if needed. |

### Known Gaps and Solutions

| Gap | Impact | Solution |
|-----|--------|----------|
| No update/delete via MCP | Duplicates accumulate | Custom Qdrant MCP with deterministic IDs (see below) |
| No structured filtering via MCP | Can't narrow search by region/service | Custom Qdrant MCP with filter parameter |
| No relationship graph | Traversal requires sequential searches | Structured relationship fields + Git repo for graph queries |
| MCP server uses random UUIDs | Can't upsert/overwrite | Custom Qdrant MCP with ARN-based IDs |

## Custom Qdrant MCP Server

The standard `mcp-server-qdrant` has two tools: `qdrant-store` (add) and `qdrant-find`
(search). For the SRE platform, we need more capabilities.

### Required Tools

```
qdrant-store-resource
    Store a resource, overwriting any existing document with the same ARN.
    Uses deterministic ID from ARN hash. Includes metadata for filtering.

    Parameters:
      - information (str): Document text
      - arn (str): AWS resource ARN (used to generate deterministic point ID)
      - collection_name (str): Target collection
      - metadata (dict): Structured fields (service, type, region, account, version, scan_id)

qdrant-find
    Semantic search with optional metadata filters.

    Parameters:
      - query (str): Natural language search query
      - collection_name (str): Collection to search
      - filter_service (str, optional): Filter by service (ec2, s3, lambda, etc.)
      - filter_region (str, optional): Filter by region
      - filter_type (str, optional): Filter by resource type
      - limit (int, optional): Max results (default 10)

qdrant-delete-resource
    Delete a resource by ARN.

    Parameters:
      - arn (str): AWS resource ARN
      - collection_name (str): Collection

qdrant-list-resources
    List resources by metadata filter without semantic search.

    Parameters:
      - collection_name (str): Collection
      - filter_service (str, optional): Filter by service
      - filter_region (str, optional): Filter by region
      - limit (int, optional): Max results
```

### How Deterministic IDs Work

```python
import hashlib

def arn_to_point_id(arn: str) -> str:
    """Same ARN always produces the same Qdrant point ID."""
    return hashlib.md5(arn.encode()).hexdigest()

# First scan:
#   arn = "arn:aws:ec2:us-east-1:123:instance/i-abc"
#   id  = "a1b2c3d4e5f6..."
#   Action: INSERT (new point)

# Second scan:
#   Same ARN → same ID → UPSERT (overwrites previous)
#   No duplicates. Always one copy per resource.
```

### How Filtered Search Works

```python
# Agent asks: "What EC2 instances are in us-east-1?"
#
# Without filter: searches ALL documents (S3, Lambda, IAM, etc.)
#   → noisy results, may miss relevant EC2 instances
#
# With filter: narrows to service=ec2, region=us-east-1 THEN does semantic search
#   → precise results, faster, more relevant

await qdrant_client.search(
    collection_name="aws_resources",
    query_vector=embed("EC2 instances"),
    query_filter=models.Filter(
        must=[
            models.FieldCondition(key="metadata.service", match=models.MatchValue(value="ec2")),
            models.FieldCondition(key="metadata.region", match=models.MatchValue(value="us-east-1")),
        ]
    ),
    limit=20,
)
```

This becomes critical at scale — when the knowledge base has 10K+ documents across
all four pillars, unfiltered semantic search becomes noisy. Metadata filtering
narrows the candidate set before vector similarity ranking.

## Storage Architecture

### Dual-Write: Git + Qdrant

```
Discovery/Sync Agent
  │
  ├── Git Repo (source of truth)
  │   ├── Structured YAML files
  │   ├── One file per resource
  │   ├── Version history via commits
  │   ├── Change tracking via git diff
  │   └── Human-browsable on GitHub
  │
  └── Qdrant (search index)
      ├── Semantic search for agents
      ├── Deterministic IDs (no duplicates)
      ├── Metadata filtering
      └── Millisecond query response
```

### Collections Strategy

| Collection | Contents | Sources |
|-----------|----------|---------|
| `aws_resources` | AWS infrastructure inventory | Discovery agent |
| `aws_changes` | Change records, drift detections | Change audit agent |
| `aws_postmortems` | Incident learnings | Post-mortem agent |
| `iac_resources` | Terraform modules, CDK constructs, resource definitions | IaC sync agent |
| `code_services` | Service definitions, dependencies, README, config | Code sync agent |
| `aws_manifests` | Discovery scan manifests | Discovery agent |

Observability data (MELT) stays in the observability platforms (Datadog, Grafana, etc.)
and is queried live via their MCP servers — not stored in Qdrant. This data is too
voluminous and time-series in nature for a vector database.

## Implementation Roadmap

### Phase 1: AWS Environment (Done)
- Discovery agent ecosystem (preflight, discovery, orchestrator)
- Parallel worker architecture
- Qdrant storage with `mcp-server-qdrant`

### Phase 2: Custom Qdrant MCP + Git Storage
- Build custom Qdrant MCP with deterministic IDs, filtered search, delete
- Add Git writing to discovery agent (YAML files)
- Deduplication via ARN-based upsert

### Phase 3: Observability Integration
- Connect incident response agent to Datadog/Grafana MCP (already built)
- Cross-correlate AWS state with live metrics/logs during triage

### Phase 4: IaC + Code Repository Integration
- Git MCP server for reading Terraform/CDK repos
- Index IaC definitions into `iac_resources` collection
- Cross-reference IaC resources ↔ AWS resources by ARN
- Git MCP server for reading application code repos
- Index service metadata into `code_services` collection
- Link services to AWS resources by name/tag

### Phase 5: Full Cross-Pillar Agents
- Incident response agent queries all collections
- Post-mortem agent correlates IaC changes with incidents
- Architecture review agent checks code patterns against infra config
- Onboarding agent generates service overviews from all four sources
