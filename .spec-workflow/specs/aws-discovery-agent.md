# AWS Discovery Agent — Design Specification

**Status:** Validated Draft
**Created:** 2026-03-17
**Category:** `examples/mcp-servers/aws/` + `examples/rag/aws-knowledge-base/`
**Spec Type:** Design (design-template)

---

## Overview

An Aura agent that connects to an AWS environment via MCP tools, systematically discovers
and inventories all resources across services, and stores structured summaries in a
persistent Qdrant knowledge base via the Qdrant MCP server — enabling future sessions
to query the infrastructure without re-scanning AWS.

### Steering Document Alignment

**Technical Standards (tech.md):** Uses only aura TOML configuration (DD-02), env var
resolution for secrets (DD-05), follows the three-tier example pattern (basic/explorer/use-case)
established by existing observability MCP examples.

**Project Structure (structure.md):** New examples placed under `examples/mcp-servers/aws/`
following the established per-platform directory pattern.

---

## Validated Findings

> These findings were validated on 2026-03-17 by reading aura source code and
> researching the AWS MCP ecosystem. They replace the original open questions.

### Finding 1: Aura Vector Stores Are READ-ONLY

**Status: CONFIRMED — critical architecture impact**

Aura agents can only **search** vector stores via `DynamicVectorSearchTool` (tool name:
`vector_search_{store_name}`). A `VectorIngestTool` exists in aura source code
(`crates/aura/src/rag_tools.rs:163-259`) but is **never registered** with agents in
`builder.rs`. The `add_documents()` method in `vector_store.rs:154-166` is a placeholder.

**Impact:** The original design using aura's `[[vector_stores]]` config for write storage
is not viable. A different storage mechanism is needed.

**Solution:** Use the **Qdrant MCP Server** (`mcp-server-qdrant`) as an MCP tool connection
instead of aura's built-in vector store. This server exposes both `qdrant-store` (write)
and `qdrant-find` (search) tools to the agent. This is actually a cleaner architecture —
both AWS discovery and knowledge storage happen through MCP tools.

### Finding 2: AWS MCP Server Ecosystem

**Status: CONFIRMED — the correct packages are identified**

There is no single `@awslabs/mcp` npm package. AWS Labs provides **66 specialized MCP
servers** as Python packages installed via `uvx` (not `npx`).

**Primary server for infrastructure discovery:**

| Server | Package | Install | Transport |
|--------|---------|---------|-----------|
| **AWS API MCP Server** | `awslabs.aws-api-mcp-server` | `uvx awslabs.aws-api-mcp-server@latest` | stdio (default) |

Key capabilities:
- **`call_aws`** — Executes any AWS CLI command with validation
- **`suggest_aws_commands`** — Recommends CLI commands from natural language
- **`get_execution_plan`** — Structured multi-step guidance (experimental)
- **`READ_OPERATIONS_ONLY=true`** — Enforces read-only at the server level
- Covers **all AWS services** available in the AWS CLI

**Alternative: Core MCP Server (multi-server proxy)**

| Server | Package | Install |
|--------|---------|---------|
| **Core MCP Server** | `awslabs.core-mcp-server` | `uvx awslabs.core-mcp-server@latest` |

Routes to specialized servers via role-based env vars. Relevant roles:
- `aws-foundation` → aws-knowledge-server, aws-api-server
- `monitoring-observability` → cloudwatch, appsignals, prometheus, cloudtrail
- `container-orchestration` → eks-server, ecs-server, finch-server
- `security-identity` → iam-server, support-server, well-architected-security
- `solutions-architect` → diagram, pricing, cost-explorer

**Service-specific servers (optional, for deeper coverage):**

| Server | Package | Purpose |
|--------|---------|---------|
| ECS MCP Server | `awslabs-ecs-mcp-server` | Deep ECS operations |
| EKS MCP Server | `awslabs.eks-mcp-server` | Kubernetes cluster management |
| CloudWatch MCP Server | `awslabs.cloudwatch-mcp-server` | Metrics, alarms, logs |
| IAM MCP Server | `awslabs.iam-mcp-server` | IAM user/role/policy management |
| DynamoDB MCP Server | `awslabs.dynamodb-mcp-server` | DynamoDB operations |
| Cost Explorer MCP Server | `awslabs.cost-explorer-mcp-server` | Cost analysis |

### Finding 3: Qdrant MCP Server Supports Read AND Write

**Status: CONFIRMED — solves the storage gap**

The official Qdrant MCP server ([github.com/qdrant/mcp-server-qdrant](https://github.com/qdrant/mcp-server-qdrant)):

| Tool | Purpose |
|------|---------|
| `qdrant-store` | Write/store documents with metadata |
| `qdrant-find` | Semantic search/retrieval |

- **Package:** `mcp-server-qdrant` (install via `uvx mcp-server-qdrant`)
- **Transport:** stdio (default), also supports streamable-http
- **Embeddings:** Built-in via FastEmbed (`sentence-transformers/all-MiniLM-L6-v2` default) — **no OpenAI API key needed for embeddings**
- **Storage:** Qdrant server (remote URL) or local file path
- Customizable tool descriptions via `TOOL_STORE_DESCRIPTION` / `TOOL_FIND_DESCRIPTION`

Sources:
- [AWS MCP Servers - Official Catalog](https://awslabs.github.io/mcp/)
- [AWS API MCP Server](https://awslabs.github.io/mcp/servers/aws-api-mcp-server)
- [Core MCP Server](https://awslabs.github.io/mcp/servers/core-mcp-server)
- [Qdrant MCP Server](https://github.com/qdrant/mcp-server-qdrant)

---

## Architecture

### Revised High-Level Flow

```
┌─────────────────────────┐
│                         │
│   Aura Agent            │
│   "aws-discovery"       │
│                         │
│   turn_depth = 15       │
│   temperature = 0.3     │
│                         │
└──┬──────────┬───────────┘
   │          │
   │ MCP      │ MCP
   │ (stdio)  │ (stdio)
   │          │
   ▼          ▼
┌──────────┐ ┌──────────────┐
│ AWS API  │ │ Qdrant MCP   │
│ MCP Svr  │ │ Server       │
│          │ │              │
│ call_aws │ │ qdrant-store │  ──► Qdrant DB (persistent)
│ suggest  │ │ qdrant-find  │  ◄── Qdrant DB
│          │ │              │
│ READ     │ │ FastEmbed    │
│ ONLY     │ │ (built-in)   │
└──────────┘ └──────────────┘
   │
   │ AWS CLI
   ▼
┌──────────┐
│ AWS APIs │     Agent LLM: AWS Bedrock (Claude Sonnet 4)
│ (all     │     or OpenAI gpt-4o
│ services)│
└──────────┘
```

### Why This Architecture

| Decision | Choice | Rationale |
|----------|--------|-----------|
| AWS discovery tool | `awslabs.aws-api-mcp-server` | Covers ALL AWS services via CLI; has `READ_OPERATIONS_ONLY` mode; one server instead of 20 specialized ones |
| Knowledge storage | Qdrant MCP Server (`mcp-server-qdrant`) | Provides both write (`qdrant-store`) and read (`qdrant-find`) via MCP tools. Aura's built-in `[[vector_stores]]` is read-only — cannot write during conversation |
| NOT using aura `[[vector_stores]]` | Replaced by Qdrant MCP | Aura's `VectorIngestTool` exists but is never registered with agents. `add_documents()` is a placeholder. MCP-based Qdrant is the correct approach |
| Embeddings | FastEmbed (built into Qdrant MCP) | No OpenAI API key needed for embeddings. Uses `sentence-transformers/all-MiniLM-L6-v2` by default. Reduces external dependencies |
| LLM provider | AWS Bedrock (primary) | Keeps all traffic in AWS; uses IAM credential chain; no separate API key. OpenAI variant for local dev |
| turn_depth | 15 | Deep discovery across many services requires many sequential tool calls |
| `READ_OPERATIONS_ONLY` | Enforced on AWS MCP server | Defense in depth — system prompt says read-only AND the MCP server enforces it |

### Components

| Component | Role | MCP Server | Key Tools |
|-----------|------|------------|-----------|
| **AWS API MCP Server** | Query AWS resources | `awslabs.aws-api-mcp-server` | `call_aws`, `suggest_aws_commands` |
| **Qdrant MCP Server** | Store & retrieve resource docs | `mcp-server-qdrant` | `qdrant-store`, `qdrant-find` |
| **Aura Agent** | Orchestrates discovery workflow | — (TOML config) | System prompt drives methodology |
| **Qdrant Database** | Persistent vector storage | — (Docker service) | Stores embeddings + metadata |
| **LLM (Bedrock/OpenAI)** | Reasoning engine | — (`[llm]` config) | Drives discovery strategy |

### Integration Points

- **AWS API MCP → AWS APIs:** Uses standard AWS credential chain (env vars / IAM role / profile)
- **Qdrant MCP → Qdrant DB:** Connects via `QDRANT_URL` or `QDRANT_LOCAL_PATH`
- **Aura → MCP Servers:** Both via stdio transport, managed by aura's MCP manager
- **Agent → LLM:** Bedrock (IAM auth) or OpenAI (API key)

### Qdrant Persistence Model

Qdrant is a **disk-persisted** vector database, not an in-memory cache. Understanding the
three-layer persistence model is critical for knowledge base reliability:

```
Layer 3: Aura Agent (STATELESS)
  ↓  Spawned per session. No memory between sessions.
  ↓  Uses MCP tools to read/write knowledge.
  ↓
Layer 2: Qdrant MCP Server (STATELESS PROCESS)
  ↓  Spawned by aura as stdio child process per session.
  ↓  Thin client — connects to Qdrant DB, embeds via FastEmbed.
  ↓  No state of its own. Destroyed when aura stops.
  ↓
Layer 1: Qdrant Database (PERSISTENT)
  ↓  Writes all data to disk immediately.
  ↓  Survives restarts, container recreation, agent sessions.
  ↓  Data persists as long as the storage volume exists.
```

**Two deployment modes for persistence:**

| Mode | Config | Persistence | Use Case |
|------|--------|-------------|----------|
| **Remote Qdrant Server** | `QDRANT_URL=http://qdrant:6333` | Docker volume or cloud-hosted Qdrant | Production, multi-agent, shared KB |
| **Local Embedded Path** | `QDRANT_LOCAL_PATH=/data/aws-kb` | Directory on host filesystem | Single-user dev, simpler setup |

**Remote Server mode (production recommended):**
- Qdrant runs as a separate Docker container or cloud service
- Data stored in `/qdrant/storage` inside the container
- Docker named volume (`qdrant_data`) survives `docker compose down` / `up` cycles
- Multiple aura agent instances can read/write the same collection simultaneously
- Supports Qdrant Cloud for fully managed persistence

**Local Embedded Path mode (dev convenience):**
- No separate Qdrant server needed — the MCP server runs an embedded Qdrant instance
- Data persisted to a directory on the host filesystem
- Simpler setup: just set `QDRANT_LOCAL_PATH` instead of `QDRANT_URL`
- Single-agent access only (file locking)
- Survives agent restarts as long as the path exists

**Cross-session knowledge flow:**
```
Session 1 (Discovery):
  User: "Discover all ECS resources"
  Agent → call_aws → AWS APIs (discover resources)
  Agent → qdrant-store → Qdrant MCP → Qdrant DB (written to disk)

[Agent stops. MCP servers stop. Qdrant DB still has data on disk.]

Session 2 (Query — could be hours/days later):
  User: "What ECS services are running?"
  Agent → qdrant-find → Qdrant MCP → Qdrant DB (reads from disk)
  Agent: "Based on discovery from 2026-03-17, you have 3 clusters..."

Session 3 (Refresh):
  User: "Re-scan Lambda, we deployed new ones"
  Agent → call_aws → AWS APIs (fresh Lambda data)
  Agent → qdrant-store → Qdrant DB (adds/updates Lambda docs)
```

---

## Data Collection Plan

### What We Collect (by Domain)

#### Identity & Access (IAM)

| Resource | Key Properties | Relationships Captured |
|----------|---------------|----------------------|
| IAM Roles | ARN, name, trust policy (who can assume), attached policy names, creation date, tags | → Policies attached, → EC2/ECS/Lambda using this role |
| IAM Policies | ARN, name, description, permission summary (actions/resources), version | → Roles/Users/Groups attached to |
| IAM Users | ARN, name, groups, MFA enabled, last login date, access key age | → Groups, → Policies |
| Instance Profiles | ARN, name, associated role | → EC2 instances using this profile |

#### Networking (VPC)

| Resource | Key Properties | Relationships Captured |
|----------|---------------|----------------------|
| VPCs | ID, CIDR blocks, name tag, DNS hostnames/resolution, tenancy | → Subnets, → Route Tables, → IGW, → Peering connections |
| Subnets | ID, CIDR, AZ, public/private (auto-assign public IP), available IPs | → VPC, → Route Table, → NAT Gateway |
| Security Groups | ID, name, inbound rules (ports, CIDRs, SG refs), outbound rules | → VPC, → All resources using this SG |
| Route Tables | ID, routes (destination CIDR → target), main/custom | → VPC, → Subnets, → IGW/NAT/Peering targets |
| NAT Gateways | ID, public IP, state, AZ | → Subnet, → Elastic IP |
| Internet Gateways | ID, state | → VPC |
| VPC Peering | ID, requester/accepter VPC + account, CIDR blocks, status | → Both VPCs |
| Load Balancers | ARN, DNS name, type (ALB/NLB), scheme (public/internal), listeners, ports | → Target Groups, → VPC, → Subnets, → SGs, → ACM certs |
| Target Groups | ARN, health check config, target type, registered targets, health status | → ALB/NLB, → EC2/ECS/Lambda targets |

#### Compute

| Resource | Key Properties | Relationships Captured |
|----------|---------------|----------------------|
| EC2 Instances | ID, type, state, AMI, AZ, public/private IP, platform, launch time | → VPC, → Subnet, → SGs, → IAM Role, → Key Pair |
| ECS Clusters | ARN, name, status, capacity providers, running task count | → Services, → Task Definitions |
| ECS Services | ARN, name, desired/running/pending count, launch type, deployment config | → Cluster, → Task Def, → ALB/Target Group, → Subnets, → SGs |
| ECS Task Definitions | ARN, family:revision, CPU/memory, container definitions (image, ports, env), log driver | → IAM Task Role, → IAM Execution Role, → Log Groups |
| Lambda Functions | ARN, name, runtime, memory, timeout, handler, code size, last modified | → IAM Role, → VPC/Subnets (if VPC-attached), → Triggers |
| Lambda Event Sources | UUID, function, source ARN, batch size, state | → Lambda Function, → SQS/DynamoDB/Kinesis source |
| EKS Clusters | ARN, name, K8s version, endpoint, platform version, status | → VPC, → Subnets, → SGs, → IAM Role |
| EKS Node Groups | Name, instance types, scaling config (min/max/desired), AMI type | → Cluster, → Subnets, → IAM Role, → Launch Template |

#### Data & Storage

| Resource | Key Properties | Relationships Captured |
|----------|---------------|----------------------|
| S3 Buckets | Name, region, versioning status, encryption (SSE-S3/KMS), public access block, lifecycle rules | → KMS key (if CMK), → Lambda triggers, → CloudFront origins |
| RDS Instances | ARN, engine + version, class, storage (type/size/IOPS), multi-AZ, endpoint, backup retention | → VPC, → Subnet Group, → SGs, → Parameter Group, → KMS key |
| RDS Clusters (Aurora) | ARN, engine, instance count, endpoints (writer/reader), serverless config | → VPC, → Member Instances, → SGs |
| DynamoDB Tables | Name, key schema (PK/SK), billing mode, provisioned capacity, GSI names, stream status | → IAM policies granting access |
| ElastiCache Clusters | ID, engine (Redis/Memcached), node type, node count, version | → VPC, → Subnet Group, → SGs |

#### Application Integration

| Resource | Key Properties | Relationships Captured |
|----------|---------------|----------------------|
| SQS Queues | URL, ARN, type (standard/FIFO), visibility timeout, retention period, DLQ config | → DLQ (if configured), → Lambda triggers |
| SNS Topics | ARN, name, subscription count, subscription protocols, encryption | → Subscriptions (Lambda, SQS, HTTP endpoints) |
| API Gateway (REST) | ID, name, endpoint type, stages | → Lambda integrations, → Custom domains |
| EventBridge Rules | Name, event pattern, state, schedule expression | → Target services (Lambda, SQS, ECS, etc.) |

#### DNS & CDN

| Resource | Key Properties | Relationships Captured |
|----------|---------------|----------------------|
| Route 53 Hosted Zones | ID, name, record count, public/private, comment | → VPC (if private zone) |
| Route 53 Records | Name, type (A/AAAA/CNAME/ALIAS), value/target, TTL | → ALBs, → CloudFront, → EC2, → S3 (alias targets) |
| CloudFront Distributions | ID, domain name, origins, behaviors, status, WAF web ACL | → S3 origins, → ALB origins, → ACM certificates |

#### Infrastructure as Code

| Resource | Key Properties | Relationships Captured |
|----------|---------------|----------------------|
| CloudFormation Stacks | Name, status, description, creation/update time, outputs, parameter names (not secret values) | → Resources managed by this stack |
| Stack Resources | Logical ID, physical resource ID, type, status | → Parent stack |

#### Observability

| Resource | Key Properties | Relationships Captured |
|----------|---------------|----------------------|
| CloudWatch Alarms | Name, metric name/namespace, threshold, comparison, state, actions | → SNS topics (alarm actions), → Monitored resource |
| CloudWatch Log Groups | Name, retention days, stored bytes, metric filters | → Lambda functions, → ECS tasks, → EC2 |
| CloudWatch Dashboards | Name, widget count, metrics referenced | → Resources being monitored |

#### Security Metadata (NO SECRET VALUES)

| Resource | Key Properties | Relationships Captured |
|----------|---------------|----------------------|
| Secrets Manager | Name, ARN, description, rotation enabled, rotation lambda, last rotated date | → Lambda rotation function |
| SSM Parameters | Name, type (String/SecureString/StringList), tier, last modified | (names and types only) |
| KMS Keys | Key ID, alias, state, key manager (AWS/Customer), creation date | → Services/resources using this key |
| ACM Certificates | ARN, domain name, status, expiry, type (imported/AWS-issued), SANs | → CloudFront distributions, → ALB listeners |

### SRE & Operational Data (Troubleshooting / Post-Mortem Support)

The following data goes beyond static inventory to capture **operational state** —
the information SREs need at 3am during an incident or when writing a post-mortem.

#### Operational Health & State

| Data Point | Why SREs Need It | `call_aws` Command |
|-----------|-----------------|-------------------|
| CloudWatch alarm **current states** | First thing checked in any incident — "is anything already firing?" | `aws cloudwatch describe-alarms --state-value ALARM` |
| ECS service **deployment status** | Is a rollback in progress? Stuck deployment? How many tasks unhealthy? | `aws ecs describe-services` (deployments array, events) |
| ECS **stopped task reasons** | Why did containers die? OOM killed? Health check failed? Exit code? | `aws ecs describe-tasks` (stoppedReason, containers[].exitCode) |
| Target group **health status** | Which backends are unhealthy? Since when? | `aws elbv2 describe-target-health` |
| RDS **status & recent events** | Is the DB in failover? Storage full? Maintenance window hit? | `aws rds describe-events --source-type db-instance --duration 1440` |
| Lambda **concurrency & throttles** | Is the function throttling? Hitting reserved concurrency limit? | `aws lambda get-function-concurrency` |
| EC2 **instance status checks** | System-level reachability vs instance-level — is the hypervisor the problem? | `aws ec2 describe-instance-status` |
| Auto-scaling **current vs limits** | Can this service actually scale up? Is it already at max? | `aws ecs describe-services` (desiredCount vs max), `aws autoscaling describe-auto-scaling-groups` |
| NAT Gateway **state** | Is cross-AZ traffic flowing? | `aws ec2 describe-nat-gateways` (state) |

#### Change History (The #1 Incident Question: "What Changed?")

| Data Point | Why SREs Need It | `call_aws` Command |
|-----------|-----------------|-------------------|
| CloudTrail **recent API calls** | Who changed what, when — the incident timeline backbone | `aws cloudtrail lookup-events --start-time <24h-ago>` |
| ECS **deployment history** | When was the last deploy? Did it succeed? Is it rolling back? | `aws ecs describe-services` (deployments array with timestamps) |
| Lambda **version/alias history** | Which version is live? When was it last published? | `aws lambda list-versions-by-function`, `aws lambda get-alias` |
| CloudFormation **stack events** | Did an infra update just fail? Which resource? | `aws cloudformation describe-stack-events --stack-name <name>` |
| CloudFormation **drift status** | Has infrastructure drifted from the template? | `aws cloudformation detect-stack-drift` |
| Security group **rule changes** | Did someone open a port or block traffic? | CloudTrail: `AuthorizeSecurityGroupIngress` / `RevokeSecurityGroupIngress` events |
| RDS **recent events** | Failover events, parameter changes, maintenance window actions | `aws rds describe-events --duration 1440` |
| S3 **bucket policy changes** | Was a bucket accidentally made public? | CloudTrail: `PutBucketPolicy` events |

#### Ownership & Operational Metadata (via Resource Tags)

| Tag Key (Convention) | Why SREs Need It | Used For |
|---------------------|-----------------|----------|
| `team` / `owner` | Who to page, who knows this service intimately | Incident escalation |
| `environment` | prod vs staging vs dev — determines severity and urgency | Triage priority |
| `tier` / `criticality` | tier-1 customer-facing vs tier-3 internal batch job | Impact assessment |
| `service` / `application` | Groups resources into logical services across AWS resource types | Blast radius analysis |
| `runbook` / `wiki` / `docs` | Direct link to troubleshooting documentation | First-responder guidance |
| `cost-center` / `business-unit` | Business impact assessment | Post-mortem stakeholder identification |
| `pagerduty` / `opsgenie` / `oncall` | On-call escalation path or integration ID | Incident routing |
| `repo` / `repository` | Source code repository for this service | Root cause investigation |
| `deploy-pipeline` / `ci-cd` | CI/CD pipeline that deploys this service | Rollback path identification |

> **Note:** The agent stores all tags found on every resource. The above are conventions
> that, when present, significantly improve incident response. The agent should flag
> resources that are **missing critical tags** (team, environment, service) as a
> finding during discovery.

#### Capacity & Limits

| Data Point | Why SREs Need It | `call_aws` Command |
|-----------|-----------------|-------------------|
| Service Quotas (limits) | "We hit a limit nobody knew about" — common incident cause | `aws service-quotas list-service-quotas --service-code <svc>` |
| ECS service scaling bounds | min/max task count — can this service absorb a traffic spike? | `aws ecs describe-services` (deploymentConfiguration) |
| Lambda reserved concurrency | Is the function throttling at the account or function level? | `aws lambda get-function-concurrency` |
| RDS storage autoscaling | Will the DB run out of disk? What's the ceiling? | `describe-db-instances` (MaxAllocatedStorage, AllocatedStorage) |
| DynamoDB provisioned vs consumed | Throttling because provisioned capacity is too low? | `describe-table` (ProvisionedThroughput) |
| ALB/NLB limits | Connection count, new connections/sec, rules per ALB | CloudWatch: `ActiveConnectionCount`, `NewConnectionCount` |
| NAT Gateway bandwidth | Cross-AZ bottleneck? | CloudWatch: `BytesOutToDestination`, `PacketsDropCount` |
| S3 request rate | Hitting the 5,500 GET/s or 3,500 PUT/s per-prefix limit? | CloudWatch: `AllRequests` metric |

#### Resilience & DR Configuration

| Data Point | Why Post-Mortems Ask | `call_aws` Command |
|-----------|---------------------|-------------------|
| RDS Multi-AZ status | "Was failover actually available?" | `describe-db-instances` (MultiAZ) |
| RDS backup config & last snapshot | "Could we have restored?" Retention period, last backup time | `describe-db-instances`, `describe-db-snapshots --db-instance-identifier` |
| S3 versioning & replication | "Can we recover deleted/corrupted data?" | `s3api get-bucket-versioning`, `get-bucket-replication` |
| ECS circuit breaker config | "Would a bad deploy auto-rollback?" | `describe-services` (deploymentCircuitBreaker: {enable, rollback}) |
| Lambda DLQ / on-failure dest | "Were failed invocations captured or silently lost?" | `lambda get-function-event-invoke-config` |
| SQS DLQ config | "Did poison messages get captured?" | `sqs get-queue-attributes` (RedrivePolicy) |
| Route 53 health checks & failover | "Is DNS failover configured for this service?" | `route53 list-health-checks`, record set failover routing |
| CloudFront origin failover groups | "Is there a backup origin if the primary goes down?" | `cloudfront get-distribution` (OriginGroups) |
| Backup plans (AWS Backup) | "What's the backup coverage?" | `aws backup list-backup-plans`, `list-protected-resources` |

#### Network Path Analysis

| Data Point | Why SREs Need It | `call_aws` Command |
|-----------|-----------------|-------------------|
| Security group **rule cross-reference** | "Can service A talk to service B on port 5432?" | `describe-security-groups` (cross-ref inbound/outbound by SG ID) |
| Network ACL rules | "Is a subnet-level DENY overriding the SG ALLOW?" | `ec2 describe-network-acls` |
| VPC Flow Logs config | "Can we see traffic logs for this interface?" | `ec2 describe-flow-logs` |
| VPC Endpoints | "Is S3/DynamoDB traffic staying in VPC or going over internet?" | `ec2 describe-vpc-endpoints` |
| Transit Gateway routes | "Is cross-VPC routing configured correctly?" | `ec2 describe-transit-gateway-route-tables` |
| Private DNS zones | "Is internal DNS resolving correctly for this service?" | Route 53 private hosted zone VPC associations |
| Elastic Network Interfaces | "What IPs are attached to this resource?" | `ec2 describe-network-interfaces --filters Name=group-id,Values=sg-xxx` |

### What We Explicitly DO NOT Collect

| Excluded Data | Reason |
|--------------|--------|
| Secret values (Secrets Manager `GetSecretValue`) | Security — never store credentials. IAM policy excludes this action. |
| SSM Parameter values (`GetParameter`) | Security — SecureString params contain secrets. IAM policy excludes this. |
| S3 object contents | Not infrastructure metadata; too much data volume |
| CloudWatch log events | Not inventory data; use CloudWatch MCP for log analysis |
| IAM user passwords or access key secrets | Security — only metadata (key age, last used, MFA status) |
| RDS/database passwords | Security — never store connection credentials |
| EC2 user data scripts | May contain embedded secrets or bootstrap tokens |
| Lambda function source code | Not infrastructure inventory; too large |
| Environment variable values in ECS/Lambda | May contain secrets; store env var names only |

### Relationship Graph (Cross-Service Dependencies)

The agent captures these relationship types to enable "what depends on X?" queries:

```
Route 53 Record
  └──→ CloudFront Distribution
        └──→ S3 Bucket (origin)
        └──→ ALB (origin)
              └──→ Target Group
                    └──→ ECS Service
                          └──→ ECS Task Definition
                          │     └──→ IAM Task Role → IAM Policies
                          │     └──→ CloudWatch Log Group
                          │     └──→ ECR Image
                          └──→ VPC / Subnets / Security Groups
                          └──→ RDS Instance (app dependency)

Lambda Function
  └──→ IAM Execution Role → IAM Policies
  └──→ SQS Queue (event source)
  │     └──→ DLQ (dead letter queue)
  └──→ S3 Bucket (trigger)
  └──→ DynamoDB Table (read/write)
  └──→ VPC / Subnets / Security Groups (if VPC-attached)
```

---

## Data Model & Storage Strategy

### Core Principle: The Text IS The Index

Qdrant MCP's `qdrant-find` performs semantic (vector similarity) search on the document
text. There is no structured field filtering. This means:

- Every dimension you want to search by must appear **in the text itself**
- Document structure directly determines search quality
- Prefixes, markers, and consistent formatting act as pseudo-schema

### Collection Strategy

Use **separate Qdrant collections** for different document types. Both `qdrant-store` and
`qdrant-find` accept a `collection_name` parameter (falls back to the configured default).
Separation prevents resource snapshots from drowning out change records in search results.

| Collection | Document Type | Written By | Queried By |
|-----------|--------------|------------|------------|
| `aws_resources` (default) | Resource snapshots — current state of each AWS resource | Discovery Agent, Change Audit Agent | All agents |
| `aws_changes` | Change records, drift detections, CloudTrail event summaries | Change Audit Agent, Discovery Agent | Incident Response, Post-Mortem, Change Audit |
| `aws_postmortems` | Post-mortem summaries, incident learnings | Post-Mortem Agent | Incident Response, Post-Mortem |
| `aws_manifests` | Discovery scan manifests (what was scanned, when, counts) | Discovery Agent | All agents (freshness checks) |

**Why separate collections?**
- Searching `aws_resources` for "ECS services" returns resource docs, not change noise
- Searching `aws_changes` for "what changed today" returns change records, not static inventory
- Post-mortem agent can search `aws_postmortems` for "has this service failed before?"
- Prevents the most common failure: a query for "checkout service" returning 50 change records instead of the current resource snapshot

### Document Types & Templates

#### Type 1: Resource Snapshot (`aws_resources` collection)

Stored by the Discovery Agent for every resource found. Updated by the Change Audit Agent
when drift is detected. This is the "current known state" of a resource.

**Search patterns this serves:**
- "What ECS services exist?" → matches `Service: ECS | Type: Service`
- "Tell me about checkout-svc" → matches `Name: checkout-svc`
- "What uses vpc-abc123?" → matches `Relationships: → VPC: vpc-abc123`
- "What does the payments team own?" → matches `Team: payments`
- "What's in us-east-1?" → matches `Region: us-east-1`

**Template:**
```
[RESOURCE] Service: ECS | Type: Service | Region: us-east-1
Account: 123456789012 | Scan: 2026-03-17T02:00:00Z | Version: 42
ARN: arn:aws:ecs:us-east-1:123456789012:service/prod-cluster/checkout-svc
Name: checkout-svc

Configuration:
  Cluster: prod-cluster
  Task Definition: checkout-svc:42
  Desired Count: 3 | Running: 3 | Pending: 0
  Launch Type: FARGATE | CPU: 1024 | Memory: 2048
  Circuit Breaker: enabled (rollback: true)
  Deployment Strategy: rolling (min 50%, max 200%)

Networking:
  VPC: vpc-abc123 (prod-vpc)
  Subnets: subnet-111 (us-east-1a), subnet-222 (us-east-1b)
  Security Groups: sg-xyz789 (checkout-svc-sg)
  Load Balancer: arn:aws:elasticloadbalancing:...:targetgroup/checkout-tg/abc123

Relationships:
  → VPC: vpc-abc123 (prod-vpc)
  → ALB Target Group: checkout-tg
  → Task Role: arn:aws:iam::123456789012:role/checkout-task-role
  → Execution Role: arn:aws:iam::123456789012:role/ecs-execution-role
  → Log Group: /ecs/checkout-svc
  → Depends On: prod-checkout-db (RDS, application dependency)

Operational:
  Health: 3/3 targets healthy in checkout-tg
  Last Deployment: 2026-03-16T18:30:00Z (succeeded)
  Alarms: checkout-svc-5xx-alarm (OK), checkout-svc-latency-alarm (OK)

Tags: env=production, team=payments, service=checkout, tier=tier-1
      runbook=https://wiki.internal/checkout-runbook
      repo=github.com/acme/checkout-svc
      oncall=payments-oncall

Summary: Production ECS Fargate service "checkout-svc" in cluster "prod-cluster"
(us-east-1). Running 3 healthy tasks on task def revision 42 with circuit breaker
enabled. Connected to ALB target group "checkout-tg" across 2 AZs in vpc-abc123.
Tier-1 customer-facing service owned by payments team. Depends on RDS instance
"prod-checkout-db".
```

**Why this structure works for semantic search:**

| Query | What matches in the text |
|-------|-------------------------|
| "ECS services" | `Service: ECS \| Type: Service` header + `ECS Fargate service` in summary |
| "checkout-svc" | `Name: checkout-svc` + ARN + summary mentions |
| "what uses vpc-abc123?" | `→ VPC: vpc-abc123` in Relationships + Networking section |
| "payments team resources" | `team=payments` in Tags + `payments team` in summary |
| "tier-1 services" | `tier=tier-1` in Tags + `Tier-1 customer-facing` in summary |
| "what depends on prod-checkout-db?" | `→ Depends On: prod-checkout-db` in Relationships |
| "unhealthy targets" | `Health: 3/3 targets healthy` (or `1/3 unhealthy` when problematic) |
| "circuit breaker configuration" | `Circuit Breaker: enabled (rollback: true)` in Configuration |

#### Type 2: Change Record (`aws_changes` collection)

Stored by the Change Audit Agent when a mutation is detected via CloudTrail or by
comparing live state against the KB baseline. Each change is a standalone document.

**Search patterns this serves:**
- "What changed today?" → matches `[CHANGE] ... Detected: 2026-03-17`
- "Security group changes" → matches `Type: SECURITY_GROUP_MODIFICATION`
- "Changes by jane.doe" → matches `Changed By: ... jane.doe`
- "What changed on checkout-svc?" → matches resource name in Affected Resource

**Template:**
```
[CHANGE] Detected: 2026-03-17T14:23:00Z | Risk: HIGH
Type: SECURITY_GROUP_MODIFICATION
Region: us-east-1 | Account: 123456789012

Affected Resource:
  Service: EC2 | Resource Type: Security Group
  ID: sg-abc123 | Name: prod-api-sg

What Changed:
  ADDED: Inbound rule — TCP port 22 (SSH) from 0.0.0.0/0 (open to internet)
  PREVIOUS: TCP port 22 restricted to 10.0.0.0/8 (internal only)

Who Changed It:
  Principal: arn:aws:iam::123456789012:user/jane.doe
  Method: AWS Console (not via IaC pipeline)
  CloudTrail Event: AuthorizeSecurityGroupIngress
  Event Time: 2026-03-17T14:15:00Z

Blast Radius (from knowledge base):
  → 12 EC2 instances using sg-abc123
  → 3 ECS services in VPC vpc-abc123: checkout-svc, inventory-svc, api-gateway-svc
  → Team: payments (checkout-svc), warehouse (inventory-svc), platform (api-gateway-svc)

Summary: HIGH RISK — Security group "prod-api-sg" (sg-abc123) had SSH port 22
opened to the entire internet (0.0.0.0/0) via AWS Console by jane.doe at 14:15 UTC.
Previously restricted to internal network (10.0.0.0/8). Affects 12 EC2 instances
and 3 production ECS services across 3 teams.
```

#### Type 3: Drift Record (`aws_changes` collection)

Stored when the Discovery or Change Audit agent detects that a resource's current state
differs from its last stored snapshot. These are infrastructure diffs.

**Search patterns this serves:**
- "Drift on checkout-svc" → matches resource name
- "What drifted since last scan?" → matches `[DRIFT]` prefix
- "Task definition changes" → matches specific field diffs

**Template:**
```
[DRIFT] Detected: 2026-03-17T02:15:00Z | Severity: INFORMATIONAL
Resource: checkout-svc (ECS Service)
ARN: arn:aws:ecs:us-east-1:123456789012:service/prod-cluster/checkout-svc
Region: us-east-1

Previous State (Version 41, scanned 2026-03-16T02:00:00Z):
  Task Definition: checkout-svc:41
  Desired Count: 3
  Running Count: 3

Current State (Version 42, scanned 2026-03-17T02:00:00Z):
  Task Definition: checkout-svc:42
  Desired Count: 5
  Running Count: 5

Fields Changed:
  - task_definition: checkout-svc:41 → checkout-svc:42 (new deployment)
  - desired_count: 3 → 5 (scaled up)

Likely Cause: CI/CD deployment (task def revision bump) + auto-scaling or
manual scale-up (desired count increase).

Summary: ECS service "checkout-svc" drifted between daily scans. Task definition
updated from revision 41 to 42 (deployment), and desired count increased from
3 to 5 (scaling event). Both changes appear routine.
```

#### Type 4: CloudTrail Event Summary (`aws_changes` collection)

Stored by the Change Audit Agent for significant CloudTrail events. Groups related
events and annotates with KB context.

**Template:**
```
[CLOUDTRAIL] Period: 2026-03-17T10:00:00Z to 2026-03-17T14:00:00Z
Region: us-east-1 | Account: 123456789012
Events Analyzed: 847 | Mutating Events: 23 | Flagged: 3

HIGH RISK Events:
  1. AuthorizeSecurityGroupIngress on sg-abc123 by jane.doe (Console)
     → See [CHANGE] document for full analysis

MEDIUM RISK Events:
  2. UpdateService on checkout-svc by ci-cd-role (CLI)
     → New task definition deployed: checkout-svc:42
     → Team: payments | Service: checkout
  3. CreateFunction: data-export-v2 by ci-cd-role (CLI)
     → New Lambda function, missing tags: team, environment, runbook

LOW RISK Events:
  4-23. Routine: DescribeInstances, ListBuckets, AssumeRole (monitoring)

Summary: 23 mutating API calls in 4-hour window. 1 HIGH risk (SSH opened to
internet on prod security group), 2 MEDIUM (deployment + new untagged Lambda).
20 routine read/monitoring operations.
```

#### Type 5: Discovery Manifest (`aws_manifests` collection)

Stored after each discovery scan to track coverage and freshness.

**Template:**
```
[MANIFEST] Scan: 2026-03-17T02:00:00Z | Version: 42 | Duration: 12m 34s
Region: us-east-1 | Account: 123456789012
Trigger: Scheduled daily scan (cron)

Coverage:
  Phase 1 (Foundation): COMPLETE
    VPCs: 3 | Subnets: 12 | Security Groups: 28 | IAM Roles: 45
  Phase 2 (Compute & Data): COMPLETE
    EC2: 15 | ECS Clusters: 3 | ECS Services: 12 | Lambda: 34 | RDS: 4 | DynamoDB: 8
  Phase 3 (Networking & DNS): COMPLETE
    ALBs: 5 | NLBs: 1 | Target Groups: 14 | Route 53 Zones: 3 | CloudFront: 2
  Phase 4 (Supporting): COMPLETE
    SQS: 8 | SNS: 5 | CloudFormation Stacks: 12 | CloudWatch Alarms: 67
  Phase 5 (Synthesis): COMPLETE
    Relationships mapped | Issues flagged: 7

Total Resources: 267 | New Since Last Scan: 3 | Changed: 8 | Removed: 1

Issues Flagged:
  - 14 resources missing 'team' tag
  - 2 security groups with 0.0.0.0/0 inbound rules
  - 1 S3 bucket with public access (data-exports-public)
  - 3 RDS instances without Multi-AZ enabled

Not Scanned: EKS (no clusters found), ElastiCache (none found)

Summary: Full discovery scan v42 completed in 12m 34s. 267 resources cataloged
across us-east-1. 3 new resources, 8 changed, 1 removed since v41. 7 issues
flagged including public S3 bucket and missing team tags.
```

#### Type 6: Post-Mortem Summary (`aws_postmortems` collection)

Stored by the Post-Mortem Agent after incident analysis.

**Template:**
```
[POSTMORTEM] Incident: checkout-svc OOM failures
Date: 2026-03-17 | Duration: 45 minutes | Severity: SEV-2
Services Affected: checkout-svc, payment-processing (downstream)
Teams: payments, platform
Detection Time: 8 minutes (alarm fired at 14:23, incident started ~14:15)

Timeline:
  14:12 — CI/CD pipeline deploys checkout-svc task def v42
  14:15 — New tasks start, begin processing requests
  14:18 — First OOM kill detected (task memory limit 512MB, usage peaked at 510MB)
  14:20 — 2 of 5 tasks stopped, ALB routing to 3 healthy targets
  14:23 — CloudWatch alarm "checkout-svc-5xx" enters ALARM state
  14:25 — PagerDuty alert fires, oncall payments engineer paged
  14:32 — Engineer identifies OOM via ECS stopped task reasons
  14:38 — Rollback to task def v41 initiated
  14:45 — All tasks healthy on v41, alarm returns to OK
  14:57 — Incident resolved, monitoring confirmed stable

Root Cause: Task definition v42 introduced a memory regression in the checkout
service. A new dependency loaded a large dataset into memory at startup, exceeding
the 512MB container memory limit. The change passed CI tests (which use smaller
test datasets) but failed under production data volumes.

Contributing Factors:
  - No memory limit increase in task def v42 despite new dependency
  - CI test dataset did not represent production data volume
  - No canary/staged deployment — all 5 tasks updated simultaneously

What Worked:
  - Circuit breaker was enabled but did not trigger (only 2/5 tasks failed, below threshold)
  - CloudWatch alarm detected 5xx errors within 8 minutes
  - ALB automatically routed around unhealthy targets

What Didn't Work:
  - Circuit breaker threshold too high (default 50% — needed 3/5 failures to trigger)
  - No memory usage alarm (only 5xx alarm)
  - Staged rollout not configured

Action Items:
  1. Add CloudWatch alarm for ECS task memory utilization > 80%
  2. Lower circuit breaker threshold to 2 failures
  3. Implement staged deployment (canary → 25% → 50% → 100%)
  4. Update CI to include production-scale memory test
  5. Increase memory limit to 1024MB for checkout-svc

Summary: Checkout service experienced 45 minutes of degraded performance due to
OOM failures after deploying task def v42 with a memory regression. 2 of 5 tasks
failed. Impact limited by ALB routing around unhealthy targets. Root cause was
a new dependency loading production-scale data that exceeded 512MB memory limit.
Previously similar incident: none found in knowledge base.
```

### Version Management & Staleness

Since Qdrant MCP's `qdrant-store` **adds** documents (no update/delete via MCP), the
collection will accumulate historical snapshots. This is managed through:

**1. Scan Version Numbers**

Every document includes a `Version: N` field incremented per discovery scan. When
an agent finds multiple results for the same resource, it uses the highest version.

```
Agent gets 3 results for "checkout-svc":
  - Version 40 (2026-03-15) ← stale
  - Version 41 (2026-03-16) ← stale
  - Version 42 (2026-03-17) ← CURRENT — use this one
```

The system prompt instructs the agent: "When multiple documents match the same resource,
always use the one with the highest Version number and most recent scan timestamp."

**2. Timestamps in Text**

Every document embeds its timestamp prominently so the agent can assess freshness:
- `Scan: 2026-03-17T02:00:00Z` in resource docs
- `Detected: 2026-03-17T14:23:00Z` in change docs
- User can ask "is this data fresh?" and the agent can answer precisely

**3. Discovery Manifests**

The manifest document tracks what was scanned and when. Any agent can search
`aws_manifests` to determine: "When was ECS last scanned?" before deciding whether
to query AWS live or trust the KB.

**4. Future: Qdrant Cleanup Job**

For long-running installations, old snapshots should be pruned. This requires
direct Qdrant API access (not via MCP server), implemented as a scheduled cleanup:
- Keep latest 3 versions of each resource
- Keep all change records for 90 days
- Keep all post-mortems indefinitely
- This is a Phase 3 concern — not blocking for initial implementation

### Change Detection Flow

How the "what changed?" capability works end-to-end:

```
┌─────────────────────────────────────────────────────────┐
│                  Change Detection Flow                   │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  1. BASELINE: Discovery Agent populates aws_resources    │
│     └── Stores resource snapshots with Version: N        │
│                                                          │
│  2. AUDIT: Change Audit Agent runs (hourly/triggered)    │
│     ├── Queries CloudTrail for recent mutating events    │
│     │   └── call_aws: cloudtrail lookup-events           │
│     │       --start-time <since-last-audit>              │
│     │                                                    │
│     ├── For each significant event:                      │
│     │   ├── qdrant-find in aws_resources:                │
│     │   │   "What do we know about <affected resource>?" │
│     │   │                                                │
│     │   ├── call_aws: get current state of resource      │
│     │   │                                                │
│     │   ├── Compare: KB snapshot vs current state         │
│     │   │   └── Identify specific field differences      │
│     │   │                                                │
│     │   ├── qdrant-store in aws_changes:                 │
│     │   │   [CHANGE] document with diff + blast radius   │
│     │   │                                                │
│     │   └── qdrant-store in aws_resources:               │
│     │       Updated resource snapshot (Version: N+1)     │
│     │                                                    │
│     └── qdrant-store in aws_changes:                     │
│         [CLOUDTRAIL] period summary document             │
│                                                          │
│  3. QUERY: Incident/PostMortem agent asks "what changed?"│
│     ├── qdrant-find in aws_changes:                      │
│     │   "changes on checkout-svc in last 24 hours"       │
│     │                                                    │
│     └── Returns: [CHANGE] and [DRIFT] documents          │
│         with full context, blast radius, who/when/why    │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Drift Detection Flow

Drift detection happens during scheduled discovery scans. The Discovery Agent
compares its current findings against what's already in the KB:

```
For each resource discovered:
  1. qdrant-find in aws_resources: "ECS service checkout-svc"
  2. Get previous snapshot (Version N-1)
  3. Compare key fields: desired_count, task_definition, security_groups, etc.
  4. If different:
     a. qdrant-store in aws_changes: [DRIFT] document with field-by-field diff
     b. qdrant-store in aws_resources: updated snapshot (Version N)
  5. If same:
     a. qdrant-store in aws_resources: refreshed snapshot (Version N, same data)
```

**What counts as drift:**

| Field Category | Examples | Drift Severity |
|---------------|----------|---------------|
| Security | SG rules, IAM policies, public access, encryption | HIGH |
| Deployment | Task def revision, Lambda version, image tag | MEDIUM |
| Scaling | Desired count, min/max, provisioned capacity | LOW-MEDIUM |
| Configuration | Parameters, environment variables (names only), timeouts | MEDIUM |
| Tags | Missing required tags, changed ownership | LOW |
| Network | Subnet changes, route changes, endpoint changes | HIGH |
| Status | Alarm state changes, health check failures | HIGH (immediate) |

### Search Optimization Guidelines

Instructions embedded in each agent's system prompt to maximize search quality:

**For the agent writing documents:**
- Always include the resource name, ARN, and key identifiers in both the header AND summary
- Always spell out relationship targets with their names and IDs
- Always include team/service/environment tags as readable text
- Always include the scan version and timestamp prominently
- Use consistent field names across all resource types (Service, Type, Region, ARN, Name)

**For the agent searching documents:**
- Search with **specific terms**: "ECS service checkout-svc" not "checkout"
- Search with **relationship framing**: "resources in vpc-abc123" or "depends on prod-checkout-db"
- Search the **right collection**: `aws_changes` for "what changed", `aws_resources` for "what exists"
- When multiple results match, prefer the **highest Version number**
- For time-sensitive queries, check the **scan timestamp** and note freshness to the user

---

## Requirements

### R1: AWS Resource Discovery

**User Story:** As a DevOps engineer, I want an agent that can scan my AWS environment and catalog all resources, so that I have a complete picture of my infrastructure without manually navigating the console.

#### Acceptance Criteria

1. WHEN the agent is started with valid AWS credentials THEN it SHALL connect to the AWS API MCP server and have access to `call_aws` and `suggest_aws_commands` tools
2. WHEN asked to "discover this environment" THEN the agent SHALL systematically enumerate resources using `call_aws` with appropriate AWS CLI commands
3. WHEN a resource is discovered THEN the agent SHALL capture: service, resource type, ARN/ID, name/tags, region, key configuration, and relationships
4. WHEN executing AWS commands THEN the MCP server SHALL enforce read-only mode via `READ_OPERATIONS_ONLY=true`

#### Target AWS Services (Priority Order)

| Priority | Service | CLI Commands | Key Resources |
|----------|---------|-------------|---------------|
| P0 | EC2 | `aws ec2 describe-instances`, `describe-security-groups`, `describe-vpcs` | Instances, SGs, VPCs, subnets, route tables |
| P0 | IAM | `aws iam list-roles`, `list-policies`, `get-role` | Roles, policies, users, instance profiles |
| P0 | S3 | `aws s3api list-buckets`, `get-bucket-policy` | Buckets, policies, encryption |
| P1 | ECS | `aws ecs list-clusters`, `describe-services`, `describe-task-definition` | Clusters, services, task definitions |
| P1 | Lambda | `aws lambda list-functions`, `get-function` | Functions, triggers, layers |
| P1 | RDS | `aws rds describe-db-instances`, `describe-db-clusters` | Instances, clusters, subnet groups |
| P1 | DynamoDB | `aws dynamodb list-tables`, `describe-table` | Tables, GSIs, capacity |
| P2 | ELB | `aws elbv2 describe-load-balancers`, `describe-target-groups` | ALBs, NLBs, target groups |
| P2 | Route 53 | `aws route53 list-hosted-zones`, `list-resource-record-sets` | Zones, records |
| P2 | SQS/SNS | `aws sqs list-queues`, `aws sns list-topics` | Queues, topics, subscriptions |
| P3 | CloudFormation | `aws cloudformation list-stacks`, `describe-stacks` | Stacks, resources, outputs |
| P3 | CloudWatch | `aws cloudwatch describe-alarms`, `aws logs describe-log-groups` | Alarms, log groups |
| P3 | Secrets Manager | `aws secretsmanager list-secrets` | Names, ARNs (NEVER values) |
| P3 | EKS | `aws eks list-clusters`, `describe-cluster` | Clusters, node groups |

### R2: Knowledge Base Storage (via Qdrant MCP)

**User Story:** As a developer, I want discovered AWS information stored in a persistent, searchable knowledge base, so that I or future agent sessions can query it without re-scanning.

#### Acceptance Criteria

1. WHEN resources are discovered THEN the agent SHALL store each resource as a structured document using the `qdrant-store` MCP tool
2. WHEN storing data THEN each document SHALL include: service, resource type, ARN/ID, region, human-readable summary, key properties, relationships, and discovery timestamp
3. WHEN queried about infrastructure THEN the agent SHALL first search the knowledge base using the `qdrant-find` MCP tool before making new AWS API calls
4. IF the Qdrant database is persistent (Docker volume) THEN data SHALL survive agent restarts
5. WHEN storing secrets-adjacent resources THEN the agent SHALL NEVER store secret values — only metadata (name, ARN, description, rotation status)

#### Document Format (per resource stored via `qdrant-store`)

```
Service: ECS | Resource Type: Service
ARN: arn:aws:ecs:us-east-1:123456789:service/my-cluster/my-service
Name: my-service | Region: us-east-1 | Account: 123456789
Cluster: my-cluster | Task Definition: my-service:42 | Desired Count: 3
Launch Type: FARGATE | Subnets: subnet-111, subnet-222
Security Groups: sg-xyz789 | Load Balancer: arn:aws:elasticloadbalancing:...
Tags: env=production, team=platform
Relationships: VPC=vpc-abc123, ALB=my-service-alb, TaskRole=arn:aws:iam::123456789:role/my-service-role
Discovered: 2026-03-17T14:30:00Z
---
ECS Fargate service "my-service" in cluster "my-cluster" (us-east-1).
Running 3 tasks on revision 42. Connected to ALB across 2 subnets in vpc-abc123.
Tagged as production, owned by platform team.
```

### R3: Relationship Mapping

**User Story:** As an SRE, I want the agent to capture how resources relate to each other, so I can understand dependencies and blast radius.

#### Acceptance Criteria

1. WHEN discovering resources THEN the agent SHALL identify cross-service relationships (ECS service → ALB → target group → VPC)
2. WHEN storing a resource via `qdrant-store` THEN its relationships SHALL be included in the document text for semantic search context
3. WHEN asked "what depends on X?" THEN the agent SHALL query with `qdrant-find` and trace relationship chains

### R4: Incremental / Scoped Discovery

**User Story:** As a developer, I want to scope discovery to specific services or regions, so I don't wait for a full scan.

#### Acceptance Criteria

1. WHEN asked to "discover ECS resources" THEN the agent SHALL focus only on ECS-related CLI commands
2. WHEN asked to "discover resources in us-west-2" THEN the agent SHALL scope `call_aws` to that region
3. WHEN asked to "refresh Lambda" THEN the agent SHALL re-scan and store updated documents

### R5: Security Constraints

#### Acceptance Criteria

1. The AWS MCP server SHALL run with `READ_OPERATIONS_ONLY=true` — enforced at server level
2. The agent SHALL NEVER store secret values, passwords, API keys, or connection strings in Qdrant
3. All credentials in TOML config SHALL use `{{ env.VAR }}` syntax — no hardcoded values
4. The IAM policy SHALL intentionally EXCLUDE `secretsmanager:GetSecretValue` and `ssm:GetParameter`
5. The system prompt SHALL reinforce read-only and no-secrets principles as defense in depth

---

## Configuration Design

### Primary Config: `aws-discovery-agent.toml` (Bedrock + Qdrant MCP)

```toml
# AWS Discovery Agent — Aura Configuration
#
# Discovers and catalogs AWS resources into a persistent Qdrant knowledge base.
# Uses two MCP servers:
#   1. AWS API MCP Server — queries all AWS services via CLI (read-only)
#   2. Qdrant MCP Server — stores and retrieves resource documents
#
# Provider: AWS Bedrock (Claude Sonnet 4, all traffic stays in AWS)
# Features: Multi-MCP tool integration, persistent knowledge base, deep discovery
#
# Prerequisites:
#   - AWS credentials configured (env vars, IAM role, or ~/.aws/credentials)
#   - Qdrant running at localhost:6333 (docker run -p 6333:6333 qdrant/qdrant)
#   - Python uvx available (for MCP server installation)
#
# Usage:
#   export AWS_REGION=us-east-1
#   CONFIG_PATH=examples/mcp-servers/aws/aws-discovery-agent.toml aura-web-server
#
# Docker:
#   docker compose -f examples/mcp-servers/aws/docker-compose.yml up

# --- LLM Provider ---
# AWS Bedrock keeps all LLM traffic within AWS. Uses IAM credential chain.
[llm]
provider = "bedrock"
model = "us.anthropic.claude-sonnet-4-20250514-v1:0"
region = "{{ env.AWS_REGION | default: 'us-east-1' }}"

# --- Agent Configuration ---
[agent]
name = "aws-discovery-agent"
temperature = 0.3          # Low temp for factual, structured output
turn_depth = 15            # Deep discovery requires many sequential tool calls
max_tokens = 8192          # Large output for detailed resource descriptions

system_prompt = """
You are an AWS Infrastructure Discovery Agent. Your mission is to systematically
explore an AWS environment, catalog every resource you find, and store structured
summaries in your Qdrant knowledge base for future retrieval.

## Core Principles

1. **READ-ONLY** — You observe and record. Never attempt to create, modify, or delete AWS resources.
   The AWS MCP server enforces read-only mode, but you should never even attempt write operations.
2. **NO SECRETS** — Never store secret values, passwords, keys, or connection strings.
   For Secrets Manager and SSM, record only metadata: name, ARN, description, rotation status.
3. **STRUCTURED OUTPUT** — Every resource gets a consistent, searchable summary stored in Qdrant.
4. **RELATIONSHIP AWARE** — Always capture how resources connect to each other.
5. **SEARCH FIRST** — Before querying AWS, check if the information is already in your knowledge base
   using the qdrant-find tool. Only query AWS for fresh or missing data.

## Available Tools

You have two MCP servers providing tools:

### AWS API Server (call_aws, suggest_aws_commands)
- Use `call_aws` to execute read-only AWS CLI commands (e.g., `aws ec2 describe-instances`)
- Use `suggest_aws_commands` when you need help constructing the right CLI command
- All mutating commands are blocked at the server level

### Qdrant Knowledge Base (qdrant-store, qdrant-find)
- Use `qdrant-store` to save discovered resource summaries for future retrieval
- Use `qdrant-find` to search previously stored resources by semantic query
- Every resource you discover should be stored as a document

## Discovery Methodology

When asked to discover or scan an environment, follow this phased approach:

### Phase 1: Foundation (always start here)
1. Identify the AWS account ID and region: `aws sts get-caller-identity`
2. Discover VPCs and network topology: `aws ec2 describe-vpcs`, `describe-subnets`
3. Discover IAM roles: `aws iam list-roles`
4. Discover S3 buckets: `aws s3api list-buckets`
Store each resource in Qdrant as you go.

### Phase 2: Compute & Data
5. EC2 instances: `aws ec2 describe-instances`
6. ECS clusters and services: `aws ecs list-clusters`, then describe each
7. Lambda functions: `aws lambda list-functions`
8. RDS instances: `aws rds describe-db-instances`
9. DynamoDB tables: `aws dynamodb list-tables`

### Phase 3: Networking & DNS
10. Load balancers: `aws elbv2 describe-load-balancers`
11. Route 53: `aws route53 list-hosted-zones`
12. CloudFront: `aws cloudfront list-distributions`

### Phase 4: Supporting Services
13. SQS/SNS: `aws sqs list-queues`, `aws sns list-topics`
14. CloudFormation: `aws cloudformation list-stacks`
15. CloudWatch alarms: `aws cloudwatch describe-alarms`
16. Secrets Manager (metadata only!): `aws secretsmanager list-secrets`

### Phase 5: Synthesis
17. Review stored documents and map cross-service relationships
18. Store a discovery manifest: what was scanned, when, resource counts
19. Report summary to the user

## Document Format for qdrant-store

For each resource, store a document following this format:

```
Service: [AWS Service] | Resource Type: [Type]
ARN: [Full ARN or unique ID]
Name: [tag:Name or identifier] | Region: [region] | Account: [account-id]
[Key service-specific properties]
Tags: [key=value pairs]
Relationships: [Related resources by ARN/ID]
Discovered: [ISO 8601 timestamp]
---
[2-3 sentence human-readable summary including purpose, relationships, and notable config]
```

## Scoped Discovery

If asked to scan specific services or regions only:
- Focus on the requested scope
- Still note relationships to out-of-scope resources (by ARN reference)
- Store a scoped manifest noting what was and wasn't scanned

## Querying the Knowledge Base

When the user asks questions about the environment:
1. First search with qdrant-find for relevant resources
2. If found, answer from stored knowledge and cite the discovery timestamp
3. If not found or stale, offer to re-scan that service
4. For "what depends on X?" questions, search and trace relationship chains

## Interaction Style

- Be methodical and thorough — don't skip services
- Report progress: "Scanning ECS... found 3 clusters, 12 services"
- After discovery, provide a summary: total resources by service, key findings
- Flag potential issues: untagged resources, overly permissive security groups,
  public S3 buckets, unused resources, non-standard configurations
"""

# Static context injected into every prompt
context = [
    "You have access to AWS via the call_aws tool (read-only mode enforced).",
    "You have a Qdrant knowledge base via qdrant-store (write) and qdrant-find (search).",
    "Always store discovered resources in Qdrant. Always search Qdrant before querying AWS.",
    "All timestamps should use ISO 8601 format (e.g., 2026-03-17T14:30:00Z)."
]

# --- MCP Server: AWS API (read-only infrastructure discovery) ---
# Official AWS Labs MCP server. Executes AWS CLI commands with validation.
# READ_OPERATIONS_ONLY=true blocks all mutating operations at the server level.
# Install: uvx awslabs.aws-api-mcp-server@latest
[mcp.servers.aws_api]
transport = "stdio"
cmd = ["uvx"]
args = ["awslabs.aws-api-mcp-server@latest"]
description = "AWS API access for infrastructure discovery (read-only)"

[mcp.servers.aws_api.env]
AWS_REGION = "{{ env.AWS_REGION | default: 'us-east-1' }}"
AWS_ACCESS_KEY_ID = "{{ env.AWS_ACCESS_KEY_ID }}"
AWS_SECRET_ACCESS_KEY = "{{ env.AWS_SECRET_ACCESS_KEY }}"
READ_OPERATIONS_ONLY = "true"
# Optional: AWS_SESSION_TOKEN = "{{ env.AWS_SESSION_TOKEN }}"
# Optional: AWS_API_MCP_PROFILE_NAME = "{{ env.AWS_PROFILE }}"

# --- MCP Server: Qdrant (persistent knowledge base) ---
# Official Qdrant MCP server. Provides qdrant-store (write) and qdrant-find (search).
# Uses built-in FastEmbed for embeddings — no OpenAI API key needed.
# Install: uvx mcp-server-qdrant
[mcp.servers.qdrant]
transport = "stdio"
cmd = ["uvx"]
args = ["mcp-server-qdrant"]
description = "Persistent knowledge base for storing and retrieving AWS resource information"

[mcp.servers.qdrant.env]
QDRANT_URL = "{{ env.QDRANT_URL | default: 'http://localhost:6333' }}"
COLLECTION_NAME = "{{ env.QDRANT_COLLECTION | default: 'aws_resources' }}"
QDRANT_API_KEY = "{{ env.QDRANT_API_KEY }}"
TOOL_STORE_DESCRIPTION = "Store a discovered AWS resource summary in the knowledge base. Use this for every resource you discover."
TOOL_FIND_DESCRIPTION = "Search the AWS resource knowledge base. Use this to find previously discovered resources before querying AWS APIs."
```

### Dev Config: `aws-discovery-agent-dev.toml`

```toml
# AWS Discovery Agent — Development Variant
#
# Uses OpenAI instead of Bedrock for easier local development.
# Uses Qdrant LOCAL PATH mode — no separate Qdrant server needed!
# Data persists to a directory on your filesystem.
# Lower turn_depth for faster iteration.

[llm]
provider = "openai"
model = "gpt-4o"
api_key = "{{ env.OPENAI_API_KEY }}"

[agent]
name = "aws-discovery-agent-dev"
temperature = 0.3
turn_depth = 10          # Lower for faster dev iteration
max_tokens = 4096
system_prompt = """..."""  # Same system prompt as production variant

context = [
    "You have access to AWS via the call_aws tool (read-only mode enforced).",
    "You have a Qdrant knowledge base via qdrant-store (write) and qdrant-find (search).",
    "Always store discovered resources in Qdrant. Always search Qdrant before querying AWS.",
    "All timestamps should use ISO 8601 format."
]

# AWS API MCP Server (read-only)
[mcp.servers.aws_api]
transport = "stdio"
cmd = ["uvx"]
args = ["awslabs.aws-api-mcp-server@latest"]
description = "AWS API access for infrastructure discovery (read-only)"

[mcp.servers.aws_api.env]
AWS_REGION = "{{ env.AWS_REGION | default: 'us-east-1' }}"
AWS_ACCESS_KEY_ID = "{{ env.AWS_ACCESS_KEY_ID }}"
AWS_SECRET_ACCESS_KEY = "{{ env.AWS_SECRET_ACCESS_KEY }}"
READ_OPERATIONS_ONLY = "true"

# Qdrant MCP Server — LOCAL EMBEDDED MODE (no separate Qdrant server needed)
# Data persists to the specified directory on your filesystem.
# For remote Qdrant server mode, replace QDRANT_LOCAL_PATH with:
#   QDRANT_URL = "http://localhost:6333"
[mcp.servers.qdrant]
transport = "stdio"
cmd = ["uvx"]
args = ["mcp-server-qdrant"]
description = "Persistent knowledge base for AWS resource information"

[mcp.servers.qdrant.env]
QDRANT_LOCAL_PATH = "{{ env.QDRANT_LOCAL_PATH | default: '/tmp/aura-aws-kb' }}"
COLLECTION_NAME = "aws_resources"
```

### Preflight Config: `aws-mcp-preflight.toml`

```toml
# AWS MCP Preflight — Environment Validation & Stack Configuration Advisor
#
# Run this BEFORE deploying other agents. It validates your environment and
# recommends how to configure the agent stack for your specific AWS setup.
#
# What it does:
#   1. Validates MCP server connections (AWS API + Qdrant)
#   2. Verifies AWS credentials and discovers account/region info
#   3. Probes which AWS services have resources (quick scan)
#   4. Tests Qdrant read/write capability
#   5. Recommends agent configurations based on what it finds
#
# Usage:
#   CONFIG_PATH=examples/mcp-servers/aws/aws-mcp-preflight.toml aura-web-server
#   Then ask: "Run preflight checks and recommend agent configuration."
#
# This config is provider-agnostic by design. The preflight pattern works for
# any cloud environment — swap the AWS MCP server for GCP/Azure/IBM equivalents.

[llm]
provider = "bedrock"
model = "us.anthropic.claude-sonnet-4-20250514-v1:0"
region = "{{ env.AWS_REGION | default: 'us-east-1' }}"

[agent]
name = "aws-mcp-preflight"
temperature = 0.2
turn_depth = 8            # Enough for validation + quick probes
max_tokens = 4096
system_prompt = """
You are a Preflight Validation Agent for the Aura infrastructure intelligence stack.
Your job is to validate the environment and recommend how to configure the agent
ecosystem for this specific AWS setup.

## Preflight Checklist

Run these checks in order and report results:

### 1. MCP Server Validation
- List all available tools from each connected MCP server
- For each tool: confirm name, description, and parameters
- Flag any tools that are missing or unexpected

### 2. AWS Credential Validation
- Run: aws sts get-caller-identity
- Report: Account ID, IAM principal (role/user), region
- Confirm: READ_OPERATIONS_ONLY is enforced (attempt a describe call)
- Flag: If credentials are missing, expired, or insufficient

### 3. Qdrant Connectivity Validation
- Attempt a qdrant-store with a test document: "[PREFLIGHT_TEST] connection check"
- Attempt a qdrant-find for "PREFLIGHT_TEST"
- Confirm: Both write and read are working
- Report: Qdrant URL, collection name, embedding model

### 4. Environment Discovery (Quick Probe)
Run lightweight list commands to detect which services have resources:
- aws ec2 describe-vpcs (any VPCs?)
- aws ecs list-clusters (any ECS?)
- aws lambda list-functions --max-items 1 (any Lambda?)
- aws rds describe-db-instances (any RDS?)
- aws s3api list-buckets (any S3?)
- aws eks list-clusters (any EKS?)
- aws dynamodb list-tables --limit 1 (any DynamoDB?)
Report: which services are populated vs empty

### 5. Configuration Recommendations
Based on what you found, recommend:
- Which discovery phases are relevant (skip empty services)
- Recommended turn_depth based on environment size
- Which specialized agents would be most useful
- Any environment-specific settings (region, profile, multi-region)
- Estimated discovery scan time (small/medium/large environment)

## Output Format

```
PREFLIGHT RESULTS
=================

MCP Servers:
  ✓ aws_api: call_aws, suggest_aws_commands [READ_ONLY enforced]
  ✓ qdrant: qdrant-store, qdrant-find [read/write confirmed]

AWS Environment:
  Account: 123456789012
  Region: us-east-1
  Principal: arn:aws:iam::123456789012:role/aura-discovery-role

Services Detected:
  ✓ EC2 (3 VPCs, instances present)
  ✓ ECS (2 clusters)
  ✓ Lambda (34 functions)
  ✓ RDS (4 instances)
  ✗ EKS (no clusters)
  ✗ DynamoDB (no tables)

Recommendations:
  Environment Size: MEDIUM (~200 resources estimated)
  Discovery turn_depth: 15 (recommended)
  Skip Phases: EKS, DynamoDB (no resources detected)
  Recommended Agents: Discovery, Change Audit, Incident Response
  Estimated Full Scan Time: ~10-15 minutes
```

## Important
- Do NOT perform full discovery — only quick probes (list with --max-items 1 or similar)
- Clean up the preflight test document from Qdrant if possible
- Report any errors clearly with suggested fixes
"""

[mcp.servers.aws_api]
transport = "stdio"
cmd = ["uvx"]
args = ["awslabs.aws-api-mcp-server@latest"]
description = "AWS API MCP server — preflight validation"

[mcp.servers.aws_api.env]
AWS_REGION = "{{ env.AWS_REGION | default: 'us-east-1' }}"
AWS_ACCESS_KEY_ID = "{{ env.AWS_ACCESS_KEY_ID }}"
AWS_SECRET_ACCESS_KEY = "{{ env.AWS_SECRET_ACCESS_KEY }}"
READ_OPERATIONS_ONLY = "true"

[mcp.servers.qdrant]
transport = "stdio"
cmd = ["uvx"]
args = ["mcp-server-qdrant"]
description = "Qdrant knowledge base — preflight validation"

[mcp.servers.qdrant.env]
QDRANT_URL = "{{ env.QDRANT_URL | default: 'http://localhost:6333' }}"
COLLECTION_NAME = "{{ env.QDRANT_COLLECTION | default: 'aws_resources' }}"
```

### Query-Only Config: `aws-kb-query-agent.toml`

```toml
# AWS Knowledge Base Query Agent
#
# Queries a previously-populated Qdrant knowledge base of AWS resources.
# Does NOT connect to AWS — only searches existing knowledge.
# Use after running the discovery agent to populate the knowledge base.
#
# Usage:
#   CONFIG_PATH=examples/rag/aws-knowledge-base/aws-kb-query-agent.toml aura-web-server
#   Then ask: "What ECS services are running?" or "Show me all resources in vpc-abc123"

[llm]
provider = "bedrock"
model = "us.anthropic.claude-sonnet-4-20250514-v1:0"
region = "{{ env.AWS_REGION | default: 'us-east-1' }}"

[agent]
name = "aws-kb-query-agent"
temperature = 0.5
turn_depth = 5
system_prompt = """
You are an AWS Infrastructure Knowledge Agent. You have access to a knowledge base
of previously discovered AWS resources stored in Qdrant.

Answer questions about the AWS environment by searching the knowledge base with
qdrant-find. You do NOT have access to live AWS APIs — only the stored knowledge.

When answering:
- Always cite the discovery timestamp to indicate data freshness
- If the user asks about something not in the knowledge base, suggest they run
  the discovery agent to scan that service
- For relationship questions, search multiple times with different queries to
  trace dependency chains
- Be clear about what you know vs what might have changed since discovery
"""

[mcp.servers.qdrant]
transport = "stdio"
cmd = ["uvx"]
args = ["mcp-server-qdrant"]
description = "AWS resource knowledge base (read-only query)"

[mcp.servers.qdrant.env]
QDRANT_URL = "{{ env.QDRANT_URL | default: 'http://localhost:6333' }}"
COLLECTION_NAME = "{{ env.QDRANT_COLLECTION | default: 'aws_resources' }}"
```

---

## File Structure

```
examples/mcp-servers/aws/
├── aws-mcp-preflight.toml                # Preflight: validate env, recommend config
├── aws-mcp-preflight-openai.toml         # Preflight: OpenAI variant
├── aws-discovery-agent.toml              # Agent 1: Discovery (Bedrock + Qdrant)
├── aws-discovery-agent-openai.toml       # Agent 1: OpenAI variant
├── aws-discovery-agent-dev.toml          # Agent 1: Dev (local Qdrant path)
├── aws-change-audit-agent.toml           # Agent 2: Change detection (Bedrock)
├── aws-change-audit-agent-openai.toml    # Agent 2: OpenAI variant
├── aws-incident-response-agent.toml      # Agent 3: Incident triage (Bedrock)
├── aws-incident-response-agent-openai.toml
├── aws-postmortem-agent.toml             # Agent 4: Post-mortem (Bedrock)
├── aws-postmortem-agent-openai.toml
├── aws-capacity-planning-agent.toml      # Agent 5: Capacity analysis (Bedrock)
├── aws-capacity-planning-agent-openai.toml
├── docker-compose.yml                    # Qdrant + Aura stack
└── README.md                             # Setup, prerequisites, usage guide

examples/rag/aws-knowledge-base/
├── aws-kb-query-agent.toml               # Standalone KB query (no AWS API)
├── aws-kb-query-agent-openai.toml        # OpenAI variant
└── README.md                             # How to query a populated KB
```

> **Multi-Cloud Future:** The directory structure is `examples/mcp-servers/aws/` today.
> When GCP/Azure/IBM agents are added, they follow the same pattern:
> `examples/mcp-servers/gcp/`, `examples/mcp-servers/azure/`, etc. The preflight
> agent pattern is provider-agnostic — swap the cloud MCP server and the same
> validation/recommendation workflow applies. The Qdrant knowledge base layer
> and consumer agents (incident response, post-mortem) could potentially work
> cross-cloud with a unified KB.

---

## Infrastructure

### Docker Compose Stack

```yaml
# docker-compose.yml — Qdrant + Aura for AWS Discovery
services:
  qdrant:
    image: qdrant/qdrant:latest
    ports:
      - "6333:6333"   # REST API (used by Qdrant MCP server)
    volumes:
      - qdrant_data:/qdrant/storage

  aura:
    image: mezmo/aura:latest
    ports:
      - "3030:3030"
    volumes:
      - ./aws-discovery-agent.toml:/app/config.toml
    environment:
      - AWS_ACCESS_KEY_ID
      - AWS_SECRET_ACCESS_KEY
      - AWS_REGION
      - QDRANT_URL=http://qdrant:6333
    depends_on:
      - qdrant

volumes:
  qdrant_data:    # Persistent — survives container restarts
```

### AWS IAM Policy (Minimum Read-Only)

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AuraDiscoveryReadOnly",
            "Effect": "Allow",
            "Action": [
                "sts:GetCallerIdentity",
                "ec2:Describe*",
                "ecs:Describe*", "ecs:List*",
                "lambda:List*", "lambda:GetFunction", "lambda:GetPolicy",
                "rds:Describe*",
                "dynamodb:Describe*", "dynamodb:List*",
                "s3:ListAllMyBuckets", "s3:GetBucketLocation",
                "s3:GetBucketPolicy", "s3:GetBucketTagging",
                "s3:GetEncryptionConfiguration",
                "iam:List*", "iam:GetRole", "iam:GetPolicy",
                "iam:GetPolicyVersion",
                "elasticloadbalancing:Describe*",
                "route53:List*", "route53:GetHostedZone",
                "cloudfront:List*", "cloudfront:GetDistribution",
                "sqs:List*", "sqs:GetQueueAttributes",
                "sns:List*", "sns:GetTopicAttributes",
                "cloudformation:Describe*", "cloudformation:List*",
                "cloudwatch:Describe*", "cloudwatch:List*",
                "logs:Describe*",
                "secretsmanager:ListSecrets", "secretsmanager:DescribeSecret",
                "ssm:DescribeParameters",
                "eks:Describe*", "eks:List*",
                "bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"
            ],
            "Resource": "*"
        }
    ]
}
```

> `secretsmanager:GetSecretValue` and `ssm:GetParameter` are intentionally **EXCLUDED**.

---

## Error Handling

### Error Scenarios

1. **AWS credentials missing or expired**
   - **Handling:** `call_aws` returns auth error; agent reports to user
   - **User Impact:** "AWS credentials not configured. Please set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY."

2. **Qdrant not running**
   - **Handling:** `qdrant-store`/`qdrant-find` fail; agent can still query AWS but can't persist
   - **User Impact:** "Qdrant is not reachable. Discovery will work but results won't be stored."

3. **AWS API rate limiting**
   - **Handling:** `call_aws` returns throttling error; agent should back off and retry
   - **User Impact:** Agent reports "Rate limited on EC2 API, will retry..."

4. **MCP server process crash (known aura issue)**
   - **Handling:** stdio-based MCP servers can be killed prematurely before tool calls complete
   - **User Impact:** Partial results; known bug documented in `docs/testing/datadog-bedrock-test-results.md`

---

## Testing Strategy

| Test | Method | Pass Criteria |
|------|--------|---------------|
| TOML syntax | `python3 -c "import tomllib; ..."` | All configs parse without error |
| Config structure | Manual review | `[llm]`, `[agent]`, `[mcp.servers.aws_api]`, `[mcp.servers.qdrant]` present |
| AWS MCP server installs | `uvx awslabs.aws-api-mcp-server@latest --help` | Package installs, shows help |
| Qdrant MCP server installs | `uvx mcp-server-qdrant --help` | Package installs, shows help |
| Agent startup | `CONFIG_PATH=... timeout 15 aura-web-server` | No config parse errors |
| Preflight validation | Preflight config + "run preflight checks" | All checks pass, recommendations generated |
| Basic AWS query | Dev config + "describe EC2 instances" | Agent executes `call_aws` and returns results |
| Qdrant write | Dev config + "discover and store S3 buckets" | Agent uses `qdrant-store` successfully |
| Qdrant read | After write, "what S3 buckets exist?" | Agent uses `qdrant-find` and retrieves stored data |
| End-to-end | Full discovery → new session → query | Knowledge persists across sessions |
| Security | Review qdrant-store calls | No secret values in stored documents |
| Docker stack | `docker compose up` | Qdrant + Aura both healthy |

---

## Implementation Tasks

- [ ] 1. **Validate MCP server installation**
  - Install `awslabs.aws-api-mcp-server` via uvx and confirm tools
  - Install `mcp-server-qdrant` via uvx and confirm tools
  - Test with MCP inspector: `npx @modelcontextprotocol/inspector --cli --method tools/list`
  - Confirm whether `aws` CLI binary is required or if boto3 is used internally
  - _Requirements: R1, R2_

- [ ] 2. **Create preflight config** (`aws-mcp-preflight.toml`)
  - File: `examples/mcp-servers/aws/aws-mcp-preflight.toml`
  - Bedrock + OpenAI variants
  - Test: validates MCP tools, AWS credentials, Qdrant connectivity, quick service probe
  - Test: outputs environment-specific recommendations
  - _Requirements: R1, R2_

- [ ] 3. **Create primary discovery agent config** (`aws-discovery-agent.toml`)
  - File: `examples/mcp-servers/aws/aws-discovery-agent.toml`
  - Both AWS API and Qdrant MCP servers
  - Full system prompt with discovery methodology
  - Bedrock provider
  - _Requirements: R1, R2, R3, R4, R5_

- [ ] 4. **Create OpenAI and dev variants**
  - `aws-discovery-agent-openai.toml` — OpenAI + Qdrant
  - `aws-discovery-agent-dev.toml` — OpenAI + Qdrant + lower turn_depth
  - _Requirements: R1, R2_

- [ ] 5. **Create docker-compose.yml**
  - Qdrant + Aura services with persistent volume
  - Environment variable passthrough
  - _Requirements: R2_

- [ ] 6. **Create query-only agent** (`aws-kb-query-agent.toml`)
  - File: `examples/rag/aws-knowledge-base/aws-kb-query-agent.toml`
  - Qdrant MCP only (no AWS API)
  - Bedrock + OpenAI variants
  - _Requirements: R2, R3_

- [ ] 7. **Test end-to-end flow**
  - Start Qdrant, start discovery agent, run discovery
  - Stop agent, start query agent, verify knowledge persists
  - Verify no secrets in stored documents
  - _Requirements: All_

- [ ] 8. **Write README.md files**
  - `examples/mcp-servers/aws/README.md` — setup, prereqs, usage
  - `examples/rag/aws-knowledge-base/README.md` — query usage
  - _Requirements: All_

- [ ] 9. **Update documentation**
  - Update `examples/CLAUDE.md` inventory
  - Update `docs/examples/` with AWS discovery guide
  - Validate all TOML configs with `python3 -c "import tomllib; ..."`
  - _Requirements: All_

---

## Agent Ecosystem

The agent stack has three layers: **preflight** (validate & configure), **gatherers**
(populate the KB), and **consumers** (use the KB for SRE workflows). Each agent is
a separate TOML config sharing the same Qdrant knowledge base.

### Agent Overview

```
                    ┌──────────────┐
                    │  Preflight   │  ← Run once: validate env,
                    │  Agent       │    recommend stack config
                    └──────┬───────┘
                           │ recommends
         ┌─────────────────┴─────────────────┐
         │          GATHERERS                 │
         │  (populate & maintain the KB)      │
         ├────────────────┬───────────────────┤
         │                │                   │
    ┌─────────┐    ┌──────────┐               │
    │Discovery │    │ Change   │               │
    │ Agent    │    │ Audit    │               │
    │ WRITES   │    │ WRITES   │               │
    │ to KB    │    │ to KB    │               │
    └────┬─────┘    └────┬─────┘               │
         │               │                     │
         ▼               ▼                     │
┌──────────────────────────────────────────────┤
│           Qdrant Knowledge Base              │
│        (persistent, shared across agents)    │
├──────────────────────────────────────────────┤
         │               │              │
         ▼               ▼              ▼
    ┌─────────┐    ┌─────────┐    ┌─────────┐
    │Incident ││    │ Post-   │    │Capacity │
    │Response │    │ Mortem  │    │Planning │
    │ READS+  │    │ READS+  │    │ READS   │
    │ live AWS│    │ live AWS│    │ live AWS│
    └─────────┘    └─────────┘    └─────────┘
      On-demand      On-demand       Weekly
     (incidents)    (after inc)    (planning)
         │               │              │
         │       CONSUMERS               │
         │  (use the KB for SRE work)    │
         └───────────────────────────────┘
```

### Preflight Agent (Run First — Setup & Validation)

**Purpose:** Validate the environment and recommend how to configure the agent stack.
Not a long-running agent — run once during initial setup, and again after infrastructure
changes or when onboarding a new AWS account/region.

| Attribute | Value |
|-----------|-------|
| Config | `aws-mcp-preflight.toml` |
| MCP Servers | AWS API (read-only) + Qdrant (read/write) |
| KB Access | Write (test document only, cleaned up) |
| turn_depth | 8 |
| Trigger | Manual (setup, onboarding, troubleshooting) |

**What it does:**
1. Validates MCP server connections — confirms all tools are registered
2. Validates AWS credentials — account ID, principal, region, read-only enforcement
3. Validates Qdrant — tests write + read, confirms connectivity
4. Quick-probes AWS services — which services have resources, which are empty
5. Recommends configuration — turn_depth, which phases to run, which agents to deploy

**Multi-cloud extensibility:** The preflight pattern is provider-agnostic. For GCP, Azure,
or IBM Cloud, swap the cloud MCP server and the same validation/recommendation workflow
applies. The checklist structure (validate tools → validate credentials → probe services →
recommend config) works for any cloud provider.

### Agent 1: Discovery Agent (Foundation — Populates the KB)

**Purpose:** Systematically inventory an AWS environment and populate the knowledge base.

| Attribute | Value |
|-----------|-------|
| Config | `aws-discovery-agent.toml` |
| MCP Servers | AWS API (read-only) + Qdrant (read/write) |
| KB Access | Read + Write |
| turn_depth | 15 |
| Trigger | Scheduled (daily/weekly) or on-demand |
| Cadence | Full scan: daily or weekly. Scoped refresh: on-demand. |

**What it does:**
- Phases 1-5 discovery methodology (foundation → compute → networking → supporting → synthesis)
- Stores every resource as a structured document in Qdrant
- Maps cross-service relationships
- Flags issues: missing tags, public S3 buckets, overly permissive SGs

### Agent 2: Incident Response Agent

**Purpose:** Real-time triage during active incidents. Answers: "What's broken? What changed? What's the blast radius?"

| Attribute | Value |
|-----------|-------|
| Config | `aws-incident-response-agent.toml` |
| MCP Servers | AWS API (read-only) + Qdrant (read) + CloudWatch MCP (optional) |
| KB Access | Read (uses discovery KB for context) + live AWS queries |
| turn_depth | 20 (deep investigation chains) |
| temperature | 0.2 (precise, factual) |
| Trigger | Alert-triggered or manual during incident |

**What it does:**
1. **Triage:** Checks CloudWatch alarms in ALARM state, identifies what's firing
2. **Blast radius:** Queries KB for the affected resource's dependency chain
3. **Change correlation:** Queries CloudTrail for recent changes in the blast radius
4. **Health check:** Checks current status of all resources in the dependency chain
5. **Timeline construction:** Builds a chronological event sequence (deploy → alarm → impact)
6. **Suggests:** Next diagnostic steps based on the failure pattern

**Key system prompt behaviors:**
- Always check KB first for resource context and relationships
- Always query CloudTrail for changes in the last 4 hours
- Present findings as: "What's broken → What changed → What's affected → Suggested actions"
- Flag ownership tags so the user knows who to escalate to
- Never make changes — read-only investigation only

**Example interaction:**
```
User: "The checkout service is returning 500s"
Agent:
  1. Searches KB → finds ECS service "checkout-svc" in cluster "prod-api"
  2. Checks ECS → deployment in progress, 2/5 tasks failing health checks
  3. Checks CloudTrail → new task definition deployed 23 minutes ago by ci-cd-role
  4. Checks ALB target health → 3 healthy, 2 unhealthy targets
  5. Checks stopped tasks → Exit code 1, OOM killed (memory limit 512MB)
  Reports: "Deployment 23 min ago introduced a memory regression. 2 of 5
  tasks OOM-killed. ALB routing to 3 healthy targets. Team: payments
  (tag:team). Suggest: rollback to previous task def revision 41."
```

### Agent 3: Post-Mortem Agent

**Purpose:** Assists SREs in constructing post-mortem documents after an incident. Builds timelines, identifies contributing factors, and assesses impact.

| Attribute | Value |
|-----------|-------|
| Config | `aws-postmortem-agent.toml` |
| MCP Servers | AWS API (read-only) + Qdrant (read/write) |
| KB Access | Read (discovery KB) + Write (stores post-mortem artifacts) |
| turn_depth | 15 |
| temperature | 0.4 |
| Trigger | Manual, after incident resolution |

**What it does:**
1. **Timeline:** Reconstructs event chronology from CloudTrail, ECS events, alarm state changes
2. **Impact analysis:** Uses KB relationships to determine which services/customers were affected
3. **Contributing factors:** Identifies what conditions enabled the incident (missing circuit breaker, no DLQ, drift from IaC, missing alerts)
4. **Detection gap analysis:** "How long between the failure starting and the first alarm firing?"
5. **Resilience audit:** Checks if affected resources had Multi-AZ, backups, circuit breakers, DLQs
6. **Action items:** Suggests preventive measures based on findings
7. **Stores findings:** Writes a post-mortem summary document to Qdrant for institutional memory

**Key system prompt behaviors:**
- Ask the user for the incident time window (start/end) and affected services
- Use blameless language — focus on systems, not people
- Produce output in a standard post-mortem template format
- Always check: "Did we have monitoring for this? Did we have a runbook? Did we have DR?"
- Store the post-mortem summary in Qdrant so future incidents can reference past ones

### Agent 4: Change Audit Agent

**Purpose:** Proactive change detection — "What changed in the last N hours?" Catches risky changes before they cause incidents.

| Attribute | Value |
|-----------|-------|
| Config | `aws-change-audit-agent.toml` |
| MCP Servers | AWS API (read-only) + Qdrant (read/write) |
| KB Access | Read (baseline from discovery KB) + Write (change audit records) |
| turn_depth | 10 |
| temperature | 0.2 |
| Trigger | Scheduled (every 1-4 hours) or event-driven (EventBridge → aura API) |

**What it does:**
1. **CloudTrail scan:** Queries recent API calls, filters for mutating actions
2. **Diff against KB:** Compares current state to stored KB snapshot — what's different?
3. **Risk assessment:** Flags high-risk changes (SG rule changes, IAM policy modifications, public bucket changes)
4. **Drift detection:** Checks CloudFormation stacks for drift
5. **Untagged resource detection:** New resources missing required tags (team, environment, service)
6. **Stores audit trail:** Writes change summaries to Qdrant with timestamps

**Key system prompt behaviors:**
- Focus on changes that could cause incidents: security groups, IAM, deployments, DNS
- Rate each change: LOW / MEDIUM / HIGH risk
- For HIGH risk: explain why and suggest validation steps
- Compare against KB to distinguish intentional (deployed via pipeline) vs ad-hoc (console click) changes

**Example output:**
```
Change Audit — 2026-03-17 14:00 to 18:00 UTC

HIGH: Security group sg-abc123 ("prod-api-sg") — port 22 opened to 0.0.0.0/0
  Changed by: arn:aws:iam::123456789:user/jane.doe (console)
  Affects: 12 EC2 instances, 3 ECS services (via KB relationship lookup)
  Action: Verify this was intentional. SSH should not be open to the internet.

MEDIUM: New Lambda function "data-export-v2" deployed
  Changed by: arn:aws:iam::123456789:role/ci-cd-deploy
  Missing tags: team, environment, runbook
  Action: Add required tags.

LOW: RDS parameter group "prod-pg15-params" modified
  Changed by: arn:aws:iam::123456789:role/dba-admin
  Changes: max_connections 200 → 400
  Action: No immediate risk. Verify under load.
```

### Agent 5: Capacity Planning Agent

**Purpose:** Identifies resources approaching limits, underutilized resources (cost waste), and growth trends.

| Attribute | Value |
|-----------|-------|
| Config | `aws-capacity-planning-agent.toml` |
| MCP Servers | AWS API (read-only) + Qdrant (read) + Cost Explorer MCP (optional) |
| KB Access | Read (discovery KB for context) |
| turn_depth | 10 |
| temperature | 0.3 |
| Trigger | Scheduled (weekly) or on-demand |

**What it does:**
1. **Quota analysis:** Checks Service Quotas against current usage across services
2. **Scaling headroom:** Evaluates ECS/ASG min/max vs current desired — how much room to grow?
3. **Storage growth:** RDS allocated vs max, DynamoDB consumed vs provisioned
4. **Underutilization:** EC2 instances with low CPU, over-provisioned RDS, unused EIPs/NAT GWs
5. **Cost correlation:** If Cost Explorer MCP available, ties resource usage to spend
6. **Recommendations:** Right-sizing suggestions, reserved instance candidates

---

## Runtime & Scheduling Model

### How Aura Runs

Aura is a **long-running web server** that exposes an OpenAI-compatible API at
`/v1/chat/completions`. It does not run on a schedule itself — it is always on, waiting
for requests.

```
┌────────────────────┐        HTTP POST         ┌───────────────┐
│ Trigger            │ ──────────────────────► │ Aura Web Svr  │
│ (cron/EventBridge/ │   /v1/chat/completions   │ (always-on)   │
│  PagerDuty/human)  │ ◄────────────────────── │               │
└────────────────────┘    streaming response     └───────────────┘
```

**Discovery is triggered by sending a message** to the aura API. The trigger source
determines the agent's behavior.

### Triggering Mechanisms

| Mechanism | How It Works | Best For |
|-----------|-------------|----------|
| **Human (chat)** | User sends message via UI/curl/API client | Ad-hoc discovery, incident response |
| **Cron job** | `curl -X POST http://aura:3030/v1/chat/completions -d '{"messages":[...]}'` on a schedule | Scheduled full scans, change audits |
| **EventBridge rule** | AWS EventBridge → Lambda → calls aura API | Event-driven change detection |
| **Alert webhook** | PagerDuty/OpsGenie → webhook → calls aura API with incident context | Automatic incident triage |
| **CI/CD pipeline** | Post-deploy step calls aura to refresh KB for deployed service | Post-deployment validation |

### Recommended Cadences

| Agent | Cadence | Trigger | Rationale |
|-------|---------|---------|-----------|
| **Discovery (full scan)** | Daily (off-peak) or weekly | Cron | Infrastructure doesn't change hourly; daily keeps KB fresh |
| **Discovery (scoped refresh)** | On-demand or post-deploy | CI/CD hook or human | Refresh specific service after deployment |
| **Incident Response** | On-demand | PagerDuty webhook or human | Only during active incidents |
| **Post-Mortem** | On-demand | Human | After incident resolution |
| **Change Audit** | Every 1-4 hours | Cron or EventBridge | Catch risky changes early; hourly during business hours |
| **Capacity Planning** | Weekly | Cron | Growth trends measured over weeks, not hours |

### Example: Cron-Triggered Daily Discovery

```bash
# crontab — run full discovery at 2am UTC daily
0 2 * * * curl -s -X POST http://aura:3030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Run a full environment discovery. Scan all services in phases 1-5. Store everything in the knowledge base."}]}' \
  > /var/log/aura-discovery-$(date +\%F).log 2>&1
```

### Example: EventBridge → Lambda → Aura (Change Detection)

```
EventBridge Rule: rate(1 hour)
  → Lambda Function: "aura-change-audit-trigger"
    → POST to http://aura:3030/v1/chat/completions
       Body: "Run a change audit for the last hour. Check CloudTrail for
              mutating actions, compare against the knowledge base, and
              flag any HIGH risk changes."
```

### Example: PagerDuty Webhook → Aura (Incident Auto-Triage)

```
PagerDuty Alert fires
  → Webhook to API Gateway → Lambda
    → POST to http://aura-incident:3030/v1/chat/completions
       Body: "INCIDENT: {alert_title}. Service: {service_name}.
              Investigate: check alarm state, recent deployments,
              dependency chain, and suggest triage steps."
    → Response posted back to PagerDuty/Slack incident channel
```

### Deployment Topology Options

| Topology | Description | When |
|----------|------------|------|
| **Single agent, multiple configs** | One aura instance, swap configs per use case | Small environments, getting started |
| **Dedicated agent per persona** | Separate aura instances for discovery, incident, audit | Production, different turn_depth/LLM needs |
| **Shared Qdrant, multiple agents** | All agents point to same Qdrant URL/collection | All topologies — Qdrant is the shared brain |

```
Recommended Production Setup:

  aura-discovery:3030     (daily cron, turn_depth=15)     ──┐
  aura-incident:3031      (webhook-triggered, turn_depth=20)──┤── Qdrant DB
  aura-change-audit:3032  (hourly cron, turn_depth=10)    ──┤   (shared)
  aura-postmortem:3033    (on-demand, turn_depth=15)       ──┘
```

### AWS CLI Dependency Note

The `awslabs.aws-api-mcp-server` accepts commands in **AWS CLI syntax** (e.g.,
`aws ec2 describe-instances`) via its `call_aws` tool. However, the MCP server is
a Python package that likely uses **boto3** (AWS SDK for Python) internally — it
does **not** shell out to the `aws` CLI binary.

**Required dependencies:**
- Python 3.10+ and `uvx` (to install and run the MCP server)
- AWS credentials (env vars, IAM role, or `~/.aws/credentials`)
- **NOT required:** The `aws` CLI binary itself

> **Validation note:** This should be confirmed during Phase 1 implementation.
> If the MCP server does require the `aws` CLI, it must be installed in the
> container/environment. The Docker image should include it either way for
> safety.

---

## Adoption & Usability (Making This Easy for SREs)

The spec above is for *us* (builders). This section is about the experience for
*them* (SREs who may have zero AI experience and just want their infrastructure
to be easier to understand and operate).

### One-Command Quick Start

The gap between "I heard about this" and "I'm getting value" must be under 5 minutes.

```bash
# Clone
git clone <aura-examples> && cd examples/mcp-servers/aws

# Set credentials
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_REGION=us-east-1

# Start everything (Qdrant + Aura with preflight config)
docker compose up -d

# Run preflight (validates environment, recommends config)
curl -s http://localhost:3030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Run preflight checks"}]}'

# Start first discovery
curl -s http://localhost:3030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Discover all resources in this AWS environment"}]}'
```

**What this requires:**
- A `docker-compose.yml` that bundles Qdrant + aura + Python/uvx/MCP servers pre-installed
- A Docker image with all dependencies baked in (no "install uvx first")
- Default config that runs preflight, then discovery, with sensible defaults
- Clear terminal output (not raw JSON streaming)

### CLI Wrapper (Phase 2)

SREs work in terminals. A wrapper script makes the API calls feel native:

```bash
# Instead of curl + JSON
aura-sre preflight                          # Validate environment
aura-sre discover                           # Full discovery scan
aura-sre discover --service ecs             # Scoped scan
aura-sre audit                              # Run change audit
aura-sre ask "What ECS services are running?"
aura-sre ask "What changed in the last 24 hours?"
aura-sre incident "checkout-svc returning 500s"
aura-sre report                             # Generate summary report
```

This is a thin bash/python wrapper around `curl` to the aura API. It:
- Formats output for terminal readability (not raw JSON)
- Handles streaming responses
- Adds color coding for risk levels (RED for HIGH, YELLOW for MEDIUM)
- Pipes to less/pager for long output
- Supports `--json` flag for machine-readable output

### Zero AI Jargon in User-Facing Docs

The README and quick-start guide must avoid internal terminology:

| Spec Term (for us) | User-Facing Term (for them) | Why |
|--------------------|-----------------------------|-----|
| turn_depth | "scan thoroughness" or don't mention | SREs don't know what a "turn" is |
| temperature | (never mention) | Meaningless to non-AI users |
| Qdrant vector store | "knowledge base" | They know what a knowledge base is |
| MCP server | "plugin" or "connector" | Or don't mention — it's an implementation detail |
| FastEmbed / embeddings | (never mention) | Implementation detail |
| `qdrant-store` / `qdrant-find` | "saves to" / "searches the knowledge base" | Plain english |
| TOML config | "configuration file" | TOML is just a format name |
| system_prompt | "agent instructions" or "agent behavior" | They don't need to know the LLM term |
| LLM / Large Language Model | "AI" or "the agent" | Keep it simple |
| Semantic search | "smart search" or just "search" | Don't explain the mechanism |

### IAM Setup: Remove the Fear

SREs will need security team approval. Provide everything they need to get a fast "yes":

**One-click IAM deployment:**
```bash
# CloudFormation (one-click in console)
aws cloudformation deploy \
  --template-file iam-readonly-role.yaml \
  --stack-name aura-discovery-role \
  --capabilities CAPABILITY_NAMED_IAM

# Or Terraform
cd terraform/
terraform apply
```

**Pre-written security review document** answering every question the security team will ask:

| Security Question | Answer |
|------------------|--------|
| What does it access? | Read-only AWS APIs. Exact permission list attached. No write/delete/modify. |
| Can it change our infrastructure? | No. `READ_OPERATIONS_ONLY=true` enforced at MCP server level. IAM policy has zero mutating permissions. |
| Does it see our secrets? | No. `secretsmanager:GetSecretValue` and `ssm:GetParameter` are explicitly excluded from the IAM policy. |
| Where does our data go? | Qdrant runs in your VPC (self-hosted Docker). LLM calls go to AWS Bedrock (stays in your AWS account). No data leaves AWS. |
| What about the AI model? | AWS Bedrock — same compliance as any other AWS service. Your data is not used for model training. |
| Can we audit what it does? | Yes. All AWS API calls appear in CloudTrail under the aura IAM role. All Qdrant writes are timestamped. |
| Can we revoke access instantly? | Yes. Delete the IAM role or disable the access key. Agent stops working immediately. |
| Is the code open source? | Yes. Aura is open source. All agent configs are in this repo. |

**Files to ship:**
- `iam/aura-readonly-role.yaml` — CloudFormation template
- `iam/aura-readonly-role.tf` — Terraform module
- `docs/security-review.md` — Pre-written answers for security team

### Gradual Adoption Path

Don't ask a team to deploy 6 agents on day one. Ramp them in:

```
Week 1: SEE YOUR ENVIRONMENT
  Deploy: Preflight + Discovery Agent only
  Value: "Here's everything in your AWS account. Here are 14 resources
          missing team tags and 2 security groups open to the internet."
  Effort: docker compose up + set AWS credentials

Week 2: KNOW WHAT CHANGED
  Add: Change Audit Agent (hourly)
  Value: "Here's what changed since yesterday. 3 deployments, 1 HIGH risk
          security group change, 2 new Lambda functions missing tags."
  Effort: Add one config to docker-compose

Week 3: FASTER INCIDENT RESPONSE
  Add: Incident Response Agent
  Value: "Checkout-svc is 500ing because a deploy 23 min ago introduced
          an OOM bug. Here's the blast radius and suggested rollback."
  Effort: Add one config + PagerDuty webhook (optional)

Month 2: FULL SRE PLATFORM
  Add: Post-Mortem + Capacity Planning agents
  Value: Complete incident lifecycle + proactive capacity management
  Effort: Two more configs

Month 3: EMBEDDED IN WORKFLOW
  Add: Slack bot + CI/CD hooks + scheduled reports
  Value: Team asks questions in Slack, gets auto-triage on alerts,
         weekly change digest in email, post-deploy KB refresh
  Effort: Integration work (Lambda functions, Slack app)
```

### First-Value Moment: The Discovery Report

After the first discovery scan, the agent should produce something the SRE can
immediately show their team and manager — not raw API output, but a report:

```
AWS ENVIRONMENT SUMMARY
=======================
Account: 123456789012 | Region: us-east-1
Scanned: 2026-03-17 02:00 UTC | Duration: 12 minutes

RESOURCES FOUND: 267
  Networking:   3 VPCs, 12 subnets, 28 security groups, 5 load balancers
  Compute:      15 EC2 instances, 3 ECS clusters (12 services), 34 Lambda functions
  Data:         4 RDS instances, 8 DynamoDB tables, 23 S3 buckets
  Integration:  8 SQS queues, 5 SNS topics
  Observability: 67 CloudWatch alarms, 45 log groups

ISSUES FOUND: 7
  🔴 HIGH:   2 security groups with SSH (port 22) open to 0.0.0.0/0
  🔴 HIGH:   1 S3 bucket with public read access (data-exports-public)
  🟡 MEDIUM: 3 RDS instances without Multi-AZ enabled
  🟡 MEDIUM: 14 resources missing 'team' tag
  🟡 MEDIUM: 8 Lambda functions with no DLQ configured
  🟢 LOW:    5 ECS services without circuit breaker enabled
  🟢 LOW:    12 CloudWatch log groups with no retention policy (infinite storage)

TOP RELATIONSHIPS:
  checkout-svc → ALB → Route 53 → CloudFront (customer-facing path)
  payment-worker → SQS → Lambda → DynamoDB (async processing pipeline)
  data-pipeline → S3 → Lambda → RDS (ETL flow)

KNOWLEDGE BASE: 267 resources stored. Ready for queries.
  Try: "What depends on vpc-abc123?"
  Try: "Show me all tier-1 production services"
  Try: "What security groups allow public access?"
```

This is the "aha moment" — the SRE sees their entire environment mapped out, with
issues flagged, in 12 minutes. That's the hook.

### Cost Transparency

The first manager question: "What does this cost?"

| Component | Monthly Cost (Medium Env) | Notes |
|-----------|--------------------------|-------|
| AWS Bedrock (Discovery) | ~$3-5/day = $90-150/month | Daily full scan, Claude Sonnet 4 |
| AWS Bedrock (Change Audit) | ~$0.50-1/run x 24 = $12-24/month | Hourly audit, lighter scope |
| AWS Bedrock (Incident Response) | ~$1-3/incident | On-demand, maybe 5-10/month = $5-30 |
| Qdrant (self-hosted Docker) | $0 (just container CPU/RAM) | ~512MB RAM, minimal CPU |
| Qdrant Cloud (managed) | $25-100/month | If they don't want to manage Qdrant |
| AWS API calls | ~$0 | Describe/List are free or pennies |
| OpenAI (alternative to Bedrock) | ~2x Bedrock cost | gpt-4o pricing, data leaves AWS |

**Total self-hosted estimate: $100-200/month** for a medium environment with daily
discovery, hourly change audit, and on-demand incident response.

**Cost reduction tips:**
- Use Bedrock (cheaper than OpenAI for this volume, and data stays in AWS)
- Run discovery weekly instead of daily for stable environments
- Run change audit every 4 hours instead of hourly during off-peak
- Use the preflight agent to right-size turn_depth for your environment

### Troubleshooting Runbook

SREs think in runbooks. User-facing troubleshooting must follow the same pattern:

```
SYMPTOM: Agent says "AWS credentials not configured"
  CHECK:  echo $AWS_ACCESS_KEY_ID      → should not be empty
  CHECK:  aws sts get-caller-identity   → should return your account
  FIX:    export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...
  FIX:    Or attach an IAM role to the EC2/ECS task running aura

SYMPTOM: "Qdrant is not reachable"
  CHECK:  curl http://localhost:6333/health    → should return {"status":"ok"}
  CHECK:  docker ps | grep qdrant              → should show running container
  FIX:    docker compose up -d qdrant
  FIX:    Verify QDRANT_URL matches your setup (default: http://localhost:6333)

SYMPTOM: Discovery seems to miss resources
  CHECK:  Run preflight — it shows which services are detected
  CHECK:  Verify IAM policy includes the service (e.g., ecs:Describe*, ecs:List*)
  FIX:    Deploy updated IAM policy from iam/aura-readonly-role.yaml

SYMPTOM: Agent responses are slow (>60 seconds)
  CHECK:  What turn_depth is configured? Higher = slower but more thorough
  CHECK:  How many resources in the environment? Large envs take longer
  FIX:    Use scoped discovery ("discover just ECS") instead of full scan
  FIX:    Lower turn_depth to 10 for faster responses (less thorough)

SYMPTOM: Knowledge base returns stale results
  CHECK:  When was the last scan? Ask: "when was the last discovery scan?"
  CHECK:  Is the cron job running? Check cron logs.
  FIX:    Run a fresh discovery: "rediscover all resources"
  FIX:    Or scoped: "refresh Lambda resources"

SYMPTOM: Agent says "rate limited" on AWS APIs
  CHECK:  Normal for large environments. Agent should retry automatically.
  FIX:    If persistent, run scoped discovery for individual services
  FIX:    Check AWS Service Quotas for API rate limits
```

### Team Adoption Guide

How a team of 5-50 engineers adopts this:

| Audience | What They Need | How They Interact |
|----------|---------------|-------------------|
| **SRE Lead** (sponsor) | Security review doc, cost estimate, adoption plan | Approves deployment, configures IAM |
| **On-call SRE** | Incident response agent, quick-reference card | Asks questions during incidents |
| **Platform Engineer** | Full setup, scheduling, CI/CD integration | Manages the agent stack |
| **Developer** | Read-only KB access, "what connects to my service?" | Queries via Slack bot or CLI |
| **Engineering Manager** | Weekly summary reports, coverage metrics | Reads email digests |
| **Security Team** | Security review doc, IAM policy, audit trail | Reviews and approves |

### Deliverables Beyond TOML Configs

| Deliverable | Purpose | Priority |
|-------------|---------|----------|
| `docker-compose.yml` (all-in-one) | One-command start | P0 |
| `iam/aura-readonly-role.yaml` | CloudFormation IAM template | P0 |
| `iam/aura-readonly-role.tf` | Terraform IAM module | P0 |
| `docs/quick-start.md` | 5-minute getting started guide | P0 |
| `docs/security-review.md` | Pre-written security team answers | P0 |
| `scripts/aura-sre` | CLI wrapper for terminal usage | P1 |
| `docs/troubleshooting.md` | Runbook-style troubleshooting | P1 |
| `docs/adoption-guide.md` | Team rollout plan | P1 |
| `docs/cost-estimate.md` | Cost breakdown by environment size | P1 |
| `integrations/slack/` | Slack bot setup | P2 |
| `integrations/pagerduty/` | PagerDuty webhook Lambda | P2 |
| `integrations/cicd/` | Post-deploy KB refresh hook | P2 |
| `scripts/cleanup-qdrant.py` | KB maintenance / old version pruning | P2 |
| `grafana/dashboard.json` | KB visualization dashboard | P3 |

---

## Remaining Open Items

| # | Item | Risk | Notes |
|---|------|------|-------|
| 1 | Verify `aws` CLI binary is NOT required by `awslabs.aws-api-mcp-server` | Low | Likely uses boto3 internally. Confirm during Phase 1. Include `aws` CLI in Docker image regardless. |
| 2 | Qdrant MCP FastEmbed quality for AWS resource documents | Low | Default `all-MiniLM-L6-v2` may not handle AWS ARNs/technical terms well. Test with larger model if search quality is poor. |
| 3 | AWS API rate limits on large environments | Medium | Phased discovery helps. Add explicit throttling/pagination guidance in system prompt. Consider per-service rate limit handling. |
| 4 | MCP stdio process lifecycle bug (known aura issue) | Medium | Documented in existing test results; may cause partial discovery during long scans. Consider checkpointing. |
| 5 | Multi-region discovery | Phase 2 | System prompt can iterate regions; or run separate agent instances per region. |
| 6 | Multi-account discovery | Phase 3 | Requires assume-role support or per-account configs. |
| 7 | Knowledge base staleness/TTL | Phase 2 | No built-in TTL. Timestamps in docs let users assess freshness. Change Audit agent helps detect drift. |
| 8 | `uvx` availability in Docker | Low | Ensure Python/uvx in aura Docker image or add a multi-stage build step. |
| 9 | CloudTrail data volume in large accounts | Medium | CloudTrail `lookup-events` limited to 90 days and management events. For deep audit, may need CloudTrail Lake or Athena queries. |
| 10 | Incident Response agent latency | Medium | turn_depth=20 with multiple AWS+Qdrant queries could take 30-60s. Acceptable for incident triage but document expected response times. |
| 11 | Post-mortem storage model | Phase 2 | Storing post-mortem docs in the same Qdrant collection as resources may confuse semantic search. Consider a separate collection `aws_postmortems`. |
| 12 | Alert webhook integration shape | Phase 3 | PagerDuty/OpsGenie webhook payloads vary. Need a thin Lambda adapter to translate alert payload → aura chat message. |
| 13 | Specialized agent configs (Agents 2-5) | Phase 2 | This spec defines the personas. Separate implementation sessions for each agent's TOML config, system prompt, and testing. |
