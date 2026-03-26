# Aura SRE Platform — Instruqt Demo Environment Spec

**Status:** Draft
**Created:** 2026-03-23
**Author:** Platform Team

---

## 1. Executive Summary

This spec defines a hands-on demo environment on [Instruqt](https://instruqt.com) that showcases Aura's SRE-focused AI platform capabilities. Participants deploy Aura into a real AWS environment running **Bella Vista** — a fully instrumented restaurant reservation and ordering application — then watch Aura automatically discover the infrastructure, build a semantic knowledge base, and use 5 specialized agents to investigate, audit, and optimize the environment.

**What makes this demo compelling:** Bella Vista is a real, working application with built-in failure simulation, auto-generated traffic, and full OpenTelemetry instrumentation. Incidents are real. Logs are real. Traces are real. Aura investigates a live system, not a mock.

**Duration:** ~30 minutes (common path ~15 min + choose-your-own-adventure agents ~5 min each)

**Delivery:** Primarily self-paced with thorough instructions and guardrails. Also suitable for SE-led live demos and instructor-led workshops.

**Isolation guarantee:** Every sandbox is completely self-contained — its own AWS account, its own Bella Vista app instance, its own Qdrant knowledge base, its own aura agents. Zero shared state between participants.

---

## 2. Demo Narrative — "Day 1 SRE"

### The Story

> You just joined the platform team at **Bella Vista**, a growing restaurant chain that takes online orders and reservations. The previous SRE left, and the documentation is a README that says "run `python main.py`." You have AWS Console access, and that's it.
>
> There's a React frontend serving customers, an Express.js API handling orders and reservations, a database backing it all, message queues processing orders, and Lambda functions doing async work. You can see the app running in your browser — customers are actively placing orders — but you don't know what infrastructure supports it, how it connects, or what will break next.
>
> A CloudWatch alarm is firing. Something is wrong with the checkout flow. Your pager just went off.
>
> Then you deploy Aura.
>
> In under 3 minutes, Aura discovers every resource in the environment, maps their relationships, and builds a searchable knowledge base. You ask natural language questions: "What depends on the database?" "Which security groups are too permissive?" "What's the blast radius if the payment service goes down?"
>
> Then you trigger a real failure — Bella Vista's built-in failure simulator exhausts the database connection pool. Real 503 errors. Real error logs. Real broken traces. You use the incident response agent to triage: it finds the failing service, traces the blast radius through the knowledge base, checks CloudTrail for recent changes, and recommends actions.
>
> By the end of your first day, you know more about this environment than the previous SRE did after a year.

### Why This Story Works

| Audience | What Resonates |
|----------|---------------|
| SREs/DevOps | "I've been that person. Real app, real failures, real investigation — this would save me weeks." |
| Engineering Managers | "My team could onboard in hours instead of weeks." |
| Security/Compliance | "It found the 0.0.0.0/0 security group and the public S3 bucket automatically." |
| VPs/Directors | "One tool replaces 5 separate investigation workflows — and it works on a live system." |

---

## 3. Bella Vista — The Demo Application

### 3.1 What Is Bella Vista?

**Bella Vista** (`reserve-and-shop-easy`) is a production-grade restaurant reservation and ordering application built specifically for demos. It's a real, working app — not a stub.

| Component | Technology | Details |
|-----------|-----------|---------|
| Frontend | React + TypeScript + Vite + Tailwind + shadcn/ui | Full restaurant UI: menu, cart, checkout, reservations |
| Backend API | Express.js (Node.js) | REST API: products, orders, reservations, admin |
| Data Store | In-memory (simulates DB) | Products, orders, reservations, settings |
| Observability | OpenTelemetry SDK + Collector | Traces, logs, metrics — full instrumentation |
| Log Forwarding | Mezmo Agent (LogDNA) | Structured JSON logs with business events |
| Container | Docker (node:20-slim) | OTEL Collector baked in, ports 8080 + 3001 |
| Deployment | K8s (EKS) / ECS / Docker | eksctl config, K8s manifests, Docker Compose |

**Source:** `~/Documents/GitHub/reserve-and-shop-easy/`
**Docker image:** Already built and available in ECR (`627029844476.dkr.ecr.us-east-1.amazonaws.com/restaurant-app`)

### 3.2 Key Features for the Demo

#### Virtual Traffic Generator
Bella Vista has a built-in traffic manager (`server/services/virtualTraffic/`) that automatically generates realistic user behavior:
- Virtual users browse the menu, add items to cart, place orders, make reservations
- Configurable traffic volume and patterns
- Generates real API calls, real logs, real traces
- **Demo impact:** The environment is "alive" from the moment the learner opens the terminal

#### Failure Simulator
Built-in failure scenarios (`server/services/failureSimulator.js`) that create real, observable failures:

| Scenario | What Happens | Observable Symptoms |
|----------|-------------|-------------------|
| `connection_pool` | Connection pool saturated, 5s timeout on orders | 503 errors, error logs, broken traces, queue backup |
| `payment_gateway` | Payment processing fails | Orders stuck in `payment_pending`, error logs |
| `memory_leak` | Gradual memory growth | Increasing latency, eventual OOM signals |
| `cascading_failure` | Stage-by-stage service degradation | Progressive 503s across services, alarm triggers |
| `data_corruption` | Product data integrity violations | 422 errors on checkout, validation error logs |

**Demo impact:** These aren't simulated alarms — they're real failures producing real error logs, real broken traces, and real 503 responses. When Aura's incident response agent investigates, it's investigating a genuine incident.

#### OpenTelemetry Instrumentation
Full observability stack built into the app:
- **Traces:** Distributed tracing across all HTTP requests (Express instrumentation)
- **Logs:** Structured JSON logging via Winston (business events, performance, errors)
- **Metrics:** Request counts, latencies, error rates
- **Collector:** OTEL Collector baked into the Docker image, exports to configurable backends

### 3.3 API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/products` | GET | List menu items |
| `/api/products/:id` | GET | Get product detail |
| `/api/orders` | GET/POST | List/create orders |
| `/api/orders/:id` | GET/PUT | Get/update order |
| `/api/reservations` | GET/POST | List/create reservations |
| `/api/reservations/:id` | GET/PUT/DELETE | Manage reservations |
| `/api/settings` | GET/PUT | Restaurant settings |
| `/api/simulate/failure` | POST | Trigger failure scenario |
| `/api/simulate/stop` | POST | Stop active failure |
| `/api/simulate/status` | GET | Check failure state |

---

## 4. AWS Infrastructure

The demo environment combines Bella Vista's application infrastructure with supporting AWS services. Provisioned via **Terraform** in the Instruqt sandbox setup scripts.

### 4.1 Architecture Overview

```
                         Internet
                            │
                     ┌──────┴──────┐
                     │  Internet   │
                     │  Gateway    │
                     └──────┬──────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
              ▼             ▼             ▼
     ┌────────────┐  ┌──────────┐  ┌──────────────┐
     │    ALB     │  │  S3      │  │ CloudFront   │
     │  (public)  │  │ (assets) │  │ (optional)   │
     └─────┬──────┘  └──────────┘  └──────────────┘
           │
           ▼
  ┌──────────────────────────────────────────────┐
  │          ECS Fargate Cluster                  │
  │  ┌────────────────────────────────────────┐  │
  │  │  bella-vista-web (React + Express)     │  │
  │  │  ┌──────────────┐ ┌────────────────┐  │  │
  │  │  │  Frontend    │ │  API Server    │  │  │
  │  │  │  :8080       │ │  :3001         │  │  │
  │  │  └──────────────┘ └───────┬────────┘  │  │
  │  │                           │           │  │
  │  │  ┌──────────────┐  ┌─────┴──────┐   │  │
  │  │  │ OTEL         │  │ Mezmo      │   │  │
  │  │  │ Collector    │  │ Agent      │   │  │
  │  │  │ :4317/:4318  │  │            │   │  │
  │  │  └──────────────┘  └────────────┘   │  │
  │  └────────────────────────────────────────┘  │
  │                                              │
  │  ┌────────────────────────────────────────┐  │
  │  │  bella-vista-worker (order processing) │  │
  │  └───────────────┬────────────────────────┘  │
  └──────────────────┼───────────────────────────┘
                     │
        ┌────────────┼──────────────┐
        ▼            ▼              ▼
  ┌──────────┐ ┌──────────┐  ┌──────────────┐
  │   RDS    │ │   SQS    │  │   Lambda     │
  │ Postgres │ │  Queues  │  │  (order-     │
  │ (single  │ │          │  │  processor)  │
  │  AZ!)    │ │          │  │              │
  └──────────┘ └──────────┘  └──────────────┘
```

### 4.2 Resource Inventory

#### Networking

| Resource | Name | Details | Notes |
|----------|------|---------|-------|
| VPC | `bella-vista-vpc` | 10.0.0.0/16 | Primary VPC |
| Public Subnet (AZ-a) | `bella-vista-public-1a` | 10.0.1.0/24 | ALB, NAT Gateway |
| Public Subnet (AZ-b) | `bella-vista-public-1b` | 10.0.2.0/24 | ALB (multi-AZ) |
| Private Subnet (AZ-a) | `bella-vista-private-1a` | 10.0.10.0/24 | ECS tasks, RDS |
| Private Subnet (AZ-b) | `bella-vista-private-1b` | 10.0.11.0/24 | ECS tasks |
| NAT Gateway | `bella-vista-nat` | In public-1a | Internet access for private subnets |
| Internet Gateway | `bella-vista-igw` | Attached to VPC | |
| Security Group | `bella-vista-alb-sg` | 80, 443 from 0.0.0.0/0 | Expected — ALB is public |
| Security Group | `bella-vista-ecs-sg` | All traffic from ALB SG | ECS tasks |
| Security Group | `bella-vista-db-sg` | 5432 from ECS SG | RDS access |
| Security Group | `bella-vista-legacy-ssh-sg` | **22 from 0.0.0.0/0** | **ISSUE: Overly permissive** |

#### Compute — ECS Fargate

| Resource | Name | Details | Notes |
|----------|------|---------|-------|
| ECS Cluster | `bella-vista` | Fargate | |
| ECS Service | `bella-vista-web` | 2 tasks, Fargate | The main app: React frontend + Express API + OTEL Collector |
| ECS Service | `bella-vista-worker` | 1 task, Fargate | Order processing worker (consumes SQS) |
| Task Definition | `bella-vista-web` | ECR image, 1024 CPU, 2048 MiB | Ports 8080 (web) + 3001 (API) |
| Task Definition | `bella-vista-worker` | ECR image, 512 CPU, 1024 MiB | SQS consumer |
| ALB | `bella-vista-alb` | Internet-facing | Routes to ECS web service |
| Target Group | `bella-vista-web-tg` | Port 8080, health check `/` | |
| ECR Repository | `restaurant-app` | Already exists at 627029844476 | Docker image pre-built |

#### Compute — Lambda

| Resource | Name | Details | Notes |
|----------|------|---------|-------|
| Lambda Function | `bella-vista-order-processor` | Python 3.12, 256MB, 30s timeout | Triggered by SQS for async order events |
| Lambda Function | `bella-vista-image-resizer` | Python 3.12, **3072MB**, 60s timeout | **ISSUE: Over-provisioned (3GB for a simple function)** |

#### Compute — EC2 (Legacy)

| Resource | Name | Details | Notes |
|----------|------|---------|-------|
| EC2 Instance | `bella-vista-legacy-api` | t3.medium, **stopped** | **ISSUE: Cost waste — old monolith, stopped but not terminated** |
| EC2 Instance | `bella-vista-legacy-worker` | t3.large, **stopped**, **no Name tag** | **ISSUE: Cost waste + untagged — unknown purpose** |

#### Data

| Resource | Name | Details | Notes |
|----------|------|---------|-------|
| RDS PostgreSQL | `bella-vista-db` | db.t3.medium, **single-AZ** | **ISSUE: No multi-AZ — single point of failure for the restaurant** |
| DynamoDB Table | `bella-vista-sessions` | On-demand capacity | Session store for web auth |
| S3 Bucket | `bella-vista-assets-{random}` | Private, versioned | Menu images, static assets |
| S3 Bucket | `bella-vista-logs-{random}` | Private, lifecycle rules | OTEL + application logs |
| S3 Bucket | `bella-vista-uploads-{random}` | **Public read** | **ISSUE: Public bucket — customer data exposure risk** |

#### Messaging

| Resource | Name | Details | Notes |
|----------|------|---------|-------|
| SQS Queue | `bella-vista-order-queue` | Standard, 30s visibility | Web API → order worker |
| SQS Queue | `bella-vista-notification-queue` | Standard, 60s visibility | Order events → notifications |
| SQS Queue | `bella-vista-order-dlq` | Dead letter queue | Failed messages from order-queue |
| SNS Topic | `bella-vista-order-events` | No subscriptions | Order completion events |

#### Monitoring

| Resource | Name | Details | Notes |
|----------|------|---------|-------|
| CloudWatch Alarm | `bella-vista-5xx-high` | **ALARM state** | App 5xx errors > 10/min (triggered by failure simulator) |
| CloudWatch Alarm | `bella-vista-db-cpu` | OK state | RDS CPU > 80% |
| CloudWatch Alarm | `bella-vista-dlq-depth` | OK state | DLQ message count > 0 |
| CloudTrail | `bella-vista-trail` | Enabled, us-east-1 | Feeds change audit agent |

#### IAM

| Resource | Name | Details | Notes |
|----------|------|---------|-------|
| IAM Role | `bella-vista-ecs-task-role` | ECS task execution | S3, SQS, DynamoDB, Secrets Manager access |
| IAM Role | `bella-vista-ecs-execution-role` | ECS execution | ECR pull, CloudWatch Logs |
| IAM Role | `bella-vista-lambda-role` | Lambda execution | SQS, S3, CloudWatch Logs |

### 4.3 Intentional Issues Summary

These are the problems Aura's agents will discover. They make the demo impressive.

| # | Issue | Severity | Which Agent Finds It |
|---|-------|----------|---------------------|
| 1 | Security group `bella-vista-legacy-ssh-sg` allows SSH (22) from 0.0.0.0/0 | HIGH | Incident Response, Change Audit |
| 2 | RDS `bella-vista-db` is single-AZ (no failover) | HIGH | Capacity Planning |
| 3 | S3 bucket `bella-vista-uploads` has public read access | HIGH | Incident Response, Change Audit |
| 4 | Lambda `bella-vista-image-resizer` allocated 3GB memory for a simple function | MEDIUM | Capacity Planning |
| 5 | EC2 instances `bella-vista-legacy-*` are stopped but not terminated | MEDIUM | Capacity Planning |
| 6 | EC2 `bella-vista-legacy-worker` has no Name tag | LOW | Discovery (untagged resource) |
| 7 | CloudWatch alarm `bella-vista-5xx-high` is in ALARM state | HIGH | Incident Response |
| 8 | SNS topic `bella-vista-order-events` has zero subscriptions | LOW | Discovery |
| 9 | **Live failure: DB pool exhaustion** (triggered during demo) | CRITICAL | Incident Response, Post-Mortem |

### 4.4 Terraform Structure

```
demo/terraform/
├── main.tf              # Provider config, locals, tags
├── variables.tf         # Region, naming prefix, toggle flags
├── outputs.tf           # Resource IDs and ARNs, ALB DNS name
├── networking.tf        # VPC, subnets, IGW, NAT, route tables
├── security-groups.tf   # All SGs including the intentionally bad one
├── ecs.tf               # Cluster, task defs (using ECR image), services, ALB
├── rds.tf               # PostgreSQL (single-AZ intentionally)
├── dynamodb.tf          # Session store table
├── s3.tf                # 3 buckets including public one
├── sqs-sns.tf           # Queues, DLQ, SNS topic
├── lambda.tf            # 2 functions including over-provisioned one
├── ec2-legacy.tf        # Stopped instances (legacy monolith)
├── monitoring.tf        # CloudWatch alarms, CloudTrail
├── iam.tf               # Task roles, execution roles, Lambda role
├── ecr.tf               # ECR repository (or reference existing)
└── README.md            # How to apply, what gets created
```

**Estimated resource count:** ~55-65 AWS resources — the sweet spot for a 2-3 minute discovery.

---

## 5. Aura Agent Stack

### 5.1 Service Architecture

All aura components run as Docker containers on the Instruqt sandbox VM, alongside the Bella Vista app (or Bella Vista runs on ECS Fargate in the AWS sandbox).

```
┌─────────────────────────────────────────────────────────────────┐
│  Instruqt Sandbox VM (Docker Host)                              │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Aura Stack (docker-compose.yml)                         │   │
│  │                                                          │   │
│  │  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │   │
│  │  │   Qdrant     │  │ Qdrant MCP   │  │  AWS API MCP   │  │   │
│  │  │   :6333      │  │ :8000        │  │  :8091         │  │   │
│  │  └─────────────┘  └──────────────┘  └────────────────┘  │   │
│  │                                                          │   │
│  │  ┌──────────────┐  ┌──────────────┐                      │   │
│  │  │ Worker MCP   │  │  Discovery   │                      │   │
│  │  │ :8095        │  │  Worker      │                      │   │
│  │  │              │  │  :8080       │                      │   │
│  │  └──────────────┘  └──────────────┘                      │   │
│  │                                                          │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────┐  │   │
│  │  │ Orchestrator │  │  Incident    │  │  Change Audit  │  │   │
│  │  │ :3030        │  │  Response    │  │  :3032         │  │   │
│  │  │              │  │  :3031       │  │                │  │   │
│  │  └──────────────┘  └──────────────┘  └────────────────┘  │   │
│  │                                                          │   │
│  │  ┌──────────────┐  ┌──────────────┐                      │   │
│  │  │ Post-Mortem  │  │  Capacity    │                      │   │
│  │  │ :3033        │  │  Planning    │                      │   │
│  │  │              │  │  :3034       │                      │   │
│  │  └──────────────┘  └──────────────┘                      │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  AWS Credentials: injected by Instruqt → env vars               │
└─────────────────────────────────────────────────────────────────┘
        │
        │  AWS API calls (read-only) + Bedrock LLM calls
        ▼
┌───────────────────────────────────────────────────────┐
│  Instruqt AWS Sandbox Account                         │
│                                                       │
│  ┌─────────────────────────────────────────────────┐  │
│  │  Bella Vista App (ECS Fargate)                  │  │
│  │  - bella-vista-web (React + Express + OTEL)     │  │
│  │  - bella-vista-worker (order processing)        │  │
│  │  - ALB → Target Groups → Tasks                  │  │
│  │  - Virtual traffic generating real logs/traces  │  │
│  │  - Failure simulator ready for demo triggers    │  │
│  └─────────────────────────────────────────────────┘  │
│                                                       │
│  RDS PostgreSQL │ DynamoDB │ S3 Buckets │ SQS/SNS     │
│  Lambda │ EC2 (stopped) │ CloudWatch │ CloudTrail     │
└───────────────────────────────────────────────────────┘
```

### 5.2 Service Inventory

| Service | Port | Image/Config | Purpose |
|---------|------|-------------|---------|
| Qdrant | 6333 | `qdrant/qdrant:latest` | Vector database for knowledge base |
| Custom Qdrant MCP | 8000 | `mcp-proxy` + `aura-qdrant/server.py` | `discover_and_store`, filtered search, KB operations |
| AWS API MCP | 8091 | `mcp-proxy` + `awslabs.aws-api-mcp-server` | Read-only AWS API access |
| Aura Worker MCP | 8095 | `mcp-proxy` + `aura-worker/server.py` | Agent delegation with throttling |
| Discovery Worker | 8080 | `mezmo/aura:latest` + `aws-discovery-agent.toml` | Handles individual service discovery |
| **Orchestrator** | **3030** | `mezmo/aura:latest` + `aws-orchestrator-agent.toml` | **Primary entry point** — dispatches parallel workers |
| Incident Response | 3031 | `mezmo/aura:latest` + `aws-incident-response-agent.toml` | Real-time triage |
| Change Audit | 3032 | `mezmo/aura:latest` + `aws-change-audit-agent.toml` | CloudTrail analysis, risk-rated reports |
| Post-Mortem | 3033 | `mezmo/aura:latest` + `aws-postmortem-agent.toml` | Blameless post-mortem construction |
| Capacity Planning | 3034 | `mezmo/aura:latest` + `aws-capacity-planning-agent.toml` | Quota/scaling/cost analysis |

### 5.3 LLM Provider — AWS Bedrock

All agents use **AWS Bedrock** with Claude Sonnet 4. LLM traffic stays entirely within AWS.

```toml
[llm]
provider = "bedrock"
model = "us.anthropic.claude-sonnet-4-20250514-v1:0"
region = "us-east-1"
```

**Instruqt IAM requirement:** The sandbox AWS account MUST have Bedrock model access enabled.

```json
{
  "Effect": "Allow",
  "Action": ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
  "Resource": [
        "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-*",
        "arn:aws:bedrock:us-east-1:*:inference-profile/us.anthropic.*"
      ]
}
```

> **Risk:** Instruqt sandbox accounts may not have Bedrock model access by default. Validate during track development. If unavailable, fall back to OpenAI variants (`*-openai.toml` — already exist for every agent).

### 5.4 Existing Config Files

All agent TOML configs already exist:

| Config | Path |
|--------|------|
| Orchestrator | `examples/mcp-servers/aws/aws-orchestrator-agent.toml` |
| Discovery Worker | `examples/mcp-servers/aws/aws-discovery-agent.toml` |
| Incident Response | `examples/mcp-servers/aws/aws-incident-response-agent.toml` |
| Change Audit | `examples/mcp-servers/aws/aws-change-audit-agent.toml` |
| Post-Mortem | `examples/mcp-servers/aws/aws-postmortem-agent.toml` |
| Capacity Planning | `examples/mcp-servers/aws/aws-capacity-planning-agent.toml` |

Custom MCP servers:

| Server | Path |
|--------|------|
| Custom Qdrant MCP | `mcp-servers/aura-qdrant/server.py` |
| Aura Worker MCP | `mcp-servers/aura-worker/server.py` |

---

## 6. Instruqt Track Structure

### Track: "Aura SRE Platform — Intelligent Infrastructure Discovery"

### 6.1 Track Overview

```
COMMON PATH (everyone)                    CHOOSE YOUR OWN ADVENTURE (pick any)
┌──────────────────┐                      ┌──────────────────────┐
│ 1. Welcome to    │                      │ 5. Incident Response │
│    Bella Vista   │                      │    (~5 min)          │
│    (~3 min)      │                      └──────────────────────┘
└──────┬───────────┘                      ┌──────────────────────┐
       │                                  │ 6. Change Audit      │
┌──────┴───────────┐                      │    (~5 min)          │
│ 2. Deploy Aura   │                      └──────────────────────┘
│    (~3 min)      │                      ┌──────────────────────┐
└──────┬───────────┘                      │ 7. Post-Mortem       │
       │                                  │    (~5 min)          │
┌──────┴───────────┐                      └──────────────────────┘
│ 3. Discover      │                      ┌──────────────────────┐
│    Everything    │──────────────────▶   │ 8. Capacity Planning │
│    (~5 min)      │                      │    (~5 min)          │
└──────┬───────────┘                      └──────────────────────┘
       │                                  ┌──────────────────────┐
┌──────┴───────────┐                      │ 9. Build Your Own    │
│ 4. Query the     │                      │    Agent (~7 min)    │
│    Knowledge Base│                      └──────────────────────┘
│    (~5 min)      │                      ┌──────────────────────┐
└──────────────────┘                      │10. AI-Generated      │
                                          │    Agent (~5 min)    │
                                          └──────────────────────┘

                                          ┌──────────────────────┐
                                          │11. Wrap-Up &         │
                                          │    Next Steps        │
                                          │    (~2 min)          │
                                          └──────────────────────┘
```

### 6.2 Challenge Details

---

#### Challenge 1: Welcome to Bella Vista

**Time:** ~3 minutes
**Tabs:** Bella Vista App (browser), AWS Console, Terminal
**Goal:** Orient the user. See the live app. Feel the pain of not knowing the infrastructure.

**Instructions:**

> You've just joined the platform team at Bella Vista restaurant. Your manager says: "Here's your AWS Console access. The app is running. You're on-call starting Monday. Good luck."
>
> **Step 1:** Open the **Bella Vista App** tab. You'll see the restaurant's website — customers are browsing the menu, placing orders, and making reservations right now. This is a real, running application.
>
> **Step 2:** Switch to the **AWS Console** tab. Try to answer these questions:
> 1. What ECS services are running this app?
> 2. What database does it use? Is it resilient?
> 3. Are any CloudWatch alarms firing?
> 4. What security groups exist, and are any concerning?
> 5. How do orders flow through the system?
>
> Notice how long it takes to piece together the answers by clicking through the console. Now imagine doing this during a 3 AM incident — with customers unable to place orders.
>
> In the next challenge, you'll deploy Aura and get all these answers in minutes.

**Check script:** Always passes (informational challenge).

---

#### Challenge 2: Deploy Aura

**Time:** ~3 minutes
**Tabs:** Terminal, Editor (optional)
**Goal:** Start the aura stack and verify all services are healthy.

**Instructions:**

> Aura is pre-installed on this machine. Let's start the full agent stack.
>
> **Step 1:** Review the orchestrator config (optional):
> ```bash
> cat /opt/aura/configs/aws-orchestrator-agent.toml
> ```
> Notice: 5 agents, all using Bedrock (LLM traffic stays in AWS), connected to Qdrant for the knowledge base.
>
> **Step 2:** Start the stack:
> ```bash
> cd /opt/aura && docker compose up -d
> ```
>
> **Step 3:** Verify all 10 services are running:
> ```bash
> aura-status
> ```
>
> You should see all services showing `[OK]`.
>
> **Step 4:** Check the orchestrator is responding:
> ```bash
> curl -s http://localhost:3030/health
> ```

**Check script:**
```bash
#!/bin/bash
if ! docker compose -f /opt/aura/docker-compose.yml ps --format json 2>/dev/null | grep -q '"State":"running"'; then
  fail-message "The aura stack is not running. Run: cd /opt/aura && docker compose up -d"
  exit 1
fi
if ! curl -sf http://localhost:3030/health > /dev/null 2>&1; then
  fail-message "The orchestrator is not responding on port 3030. Check: docker compose -f /opt/aura/docker-compose.yml logs orchestrator"
  exit 1
fi
```

---

#### Challenge 3: Discover Everything

**Time:** ~5 minutes (includes ~2-3 min for discovery)
**Tabs:** Terminal
**Goal:** Trigger a full environment discovery and watch Aura catalog every resource.

**Instructions:**

> Send a discovery request to the orchestrator:
>
> ```bash
> curl -s http://localhost:3030/v1/chat/completions \
>   -H "Content-Type: application/json" \
>   -d '{"messages":[{"role":"user","content":"Discover my AWS environment in us-east-1. Catalog everything you find."}]}' \
>   | jq -r '.choices[0].message.content'
> ```
>
> **What's happening behind the scenes:**
> 1. The orchestrator dispatches 10 parallel workers (2 batches of 5)
> 2. Each worker calls `discover_and_store` for a specific service type
> 3. `discover_and_store` calls AWS via boto3, parses resources, generates embeddings, writes to Qdrant
> 4. No raw AWS data passes through any LLM context — it all happens inside the MCP server
> 5. The orchestrator reports a summary when complete
>
> This typically takes 2-3 minutes. You should see something like:
> ```
> Discovery complete. 58 resources cataloged across 10 service types.
> ```
>
> **Verify the knowledge base:**
> ```bash
> curl -s http://localhost:6333/collections/aws_resources | jq '.result.points_count'
> ```
>
> Aura now knows more about this environment than you could learn in a day of console-clicking.

**Check script:**
```bash
#!/bin/bash
POINTS=$(curl -sf http://localhost:6333/collections/aws_resources 2>/dev/null | jq -r '.result.points_count // 0')
if [ "$POINTS" -lt 10 ]; then
  fail-message "Knowledge base has fewer than 10 resources. Discovery may still be running — wait a minute and try the check again."
  exit 1
fi
```

---

#### Challenge 4: Query Your Knowledge Base

**Time:** ~5 minutes
**Tabs:** Terminal
**Goal:** Ask natural language questions about the Bella Vista infrastructure.

**Instructions:**

> Your knowledge base is populated. Ask Aura about the environment — use the helper script for convenience:
>
> **"What services run the Bella Vista app?"**
> ```bash
> aura-ask 3030 "What ECS services and tasks are running the Bella Vista restaurant application? What are their configurations?"
> ```
>
> **"What depends on the database?"**
> ```bash
> aura-ask 3030 "What resources depend on the Bella Vista database? Trace the full dependency chain from the database through services to the load balancer."
> ```
>
> **"Are there security concerns?"**
> ```bash
> aura-ask 3030 "Search the knowledge base for security concerns. Are any security groups too permissive? Any public S3 buckets? Any resources without proper access controls?"
> ```
>
> **"How do orders flow through the system?"**
> ```bash
> aura-ask 3030 "Trace the order processing flow: from the ALB through ECS to SQS queues to Lambda functions. What is the full path an order takes?"
> ```
>
> **Try your own questions!** Aura answers from the knowledge base it built — ask anything about the Bella Vista infrastructure.

**Check script:**
```bash
#!/bin/bash
POINTS=$(curl -sf http://localhost:6333/collections/aws_resources 2>/dev/null | jq -r '.result.points_count // 0')
if [ "$POINTS" -lt 10 ]; then
  fail-message "Knowledge base appears empty. Complete Challenge 3 first."
  exit 1
fi
```

---

#### Challenge 5: Incident Response (Choose Your Own Adventure)

**Time:** ~5 minutes
**Tabs:** Terminal, Bella Vista App (browser)
**Agent:** `aws-incident-response-agent` on port 3031
**Goal:** Trigger a real failure in Bella Vista and use Aura to triage it.

**Instructions:**

> Let's create a real incident. Bella Vista has a built-in failure simulator — we'll exhaust the database connection pool, which will cause real 503 errors on order creation. The failure lasts 5 minutes — plenty of time to investigate.
>
> **Step 1: Trigger the failure**
> ```bash
> # Get the Bella Vista ALB URL
> BELLA_VISTA_URL=$(terraform -chdir=/opt/aura/terraform output -raw alb_dns_name)
>
> # Trigger database connection pool exhaustion (lasts 120 seconds)
> curl -s -X POST "http://${BELLA_VISTA_URL}/api/simulate/failure" \
>   -H "Content-Type: application/json" \
>   -d '{"scenario": "connection_pool", "duration": 300}'
> ```
>
> Open the **Bella Vista App** tab — try placing an order. You'll see real errors.
>
> **Step 2: Triage with Aura**
>
> The incident response agent can now investigate a live incident:
> ```bash
> aura-ask 3031 "We have an active incident at Bella Vista restaurant. The app is returning 503 errors on order creation. CloudWatch alarm bella-vista-5xx-high is firing. Triage this: What is broken? What is the blast radius? What changed recently? What should we do?"
> ```
>
> **What to look for:**
> - Identifies the ECS service and its dependencies (RDS, SQS)
> - Maps the blast radius through the knowledge base
> - Checks CloudTrail for recent changes
> - Provides actionable recommendations
>
> **Step 3: Dig deeper**
> ```bash
> aura-ask 3031 "If the Bella Vista database goes down completely, what is the full blast radius? Which services fail, which queues back up, and which customers are affected?"
> ```

**Check script:** Always passes (exploration challenge).

---

#### Challenge 6: Change Audit (Choose Your Own Adventure)

**Time:** ~5 minutes
**Tabs:** Terminal
**Agent:** `aws-change-audit-agent` on port 3032
**Goal:** Find risky infrastructure changes via CloudTrail.

**Instructions:**

> Someone made a risky change to the Bella Vista environment. Let's find it.
>
> ```bash
> aura-ask 3032 "Scan CloudTrail for recent infrastructure changes in us-east-1. Risk-rate each change and flag anything concerning about the Bella Vista environment."
> ```
>
> **What to look for:**
> - Finds the security group change that opened port 22 to 0.0.0.0/0
> - Risk-rates it as HIGH
> - Identifies who made the change and when
> - Compares current state against the KB baseline
>
> **Follow-up — investigate the risky change:**
> ```bash
> aura-ask 3032 "The security group bella-vista-legacy-ssh-sg has SSH open to the world. What resources use this security group? What is the exposure? Is any Bella Vista infrastructure at risk?"
> ```

**Check script:** Always passes (exploration challenge).

---

#### Challenge 7: Post-Mortem Construction (Choose Your Own Adventure)

**Time:** ~5 minutes
**Tabs:** Terminal
**Agent:** `aws-postmortem-agent` on port 3033
**Goal:** Construct a blameless post-mortem from the database incident.

**Instructions:**

> The database connection pool incident from Challenge 5 is over. Let's construct a proper post-mortem.
>
> ```bash
> aura-ask 3033 "Construct a blameless post-mortem for the Bella Vista database connection pool exhaustion incident. The alarm bella-vista-5xx-high was firing, order creation was failing with 503 errors. Reconstruct the timeline, identify contributing factors, assess blast radius, and recommend action items."
> ```
>
> **What to look for:**
> - **Blameless language** — focuses on systems and processes, not individuals
> - **Timeline** — correlates CloudTrail events with alarm state changes
> - **Contributing factors** — single-AZ database, no connection pooling limits, no circuit breaker
> - **Action items** — concrete improvements: enable multi-AZ, add connection pool monitoring, implement circuit breakers
> - **Blast radius** — orders affected, revenue impact, customer experience
>
> The post-mortem is stored in Qdrant (`aws_postmortems` collection) as institutional memory.

**Check script:** Always passes (exploration challenge).

---

#### Challenge 8: Capacity Planning (Choose Your Own Adventure)

**Time:** ~5 minutes
**Tabs:** Terminal
**Agent:** `aws-capacity-planning-agent` on port 3034
**Goal:** Find waste, right-sizing opportunities, and resilience gaps.

**Instructions:**

> ```bash
> aura-ask 3034 "Run a full capacity planning review of the Bella Vista environment. Check for: underutilized resources, cost waste, resilience gaps, over-provisioned services, and quota limits approaching."
> ```
>
> **What Aura should find:**
>
> | Finding | Severity | Details |
> |---------|----------|---------|
> | Single-AZ RDS | HIGH | `bella-vista-db` has no failover — the restaurant's database is a single point of failure |
> | Over-provisioned Lambda | MEDIUM | `bella-vista-image-resizer` has 3GB memory for a simple image resize function |
> | Stopped EC2 instances | MEDIUM | `bella-vista-legacy-api` and `bella-vista-legacy-worker` — old monolith, still paying for EBS volumes |
> | Untagged resources | LOW | `bella-vista-legacy-worker` has no Name tag — unknown purpose |
>
> **Follow-up:**
> ```bash
> aura-ask 3034 "For the single-AZ Bella Vista database, what would be the impact of enabling multi-AZ? Given the connection pool incident we just had, how critical is database resilience for this restaurant's order flow?"
> ```

**Check script:** Always passes (exploration challenge).

---

#### Challenge 9: Build Your Own Agent (Choose Your Own Adventure)

**Time:** ~7 minutes
**Tabs:** Terminal, Editor
**Goal:** Create a custom Aura agent from a TOML config — no code, just configuration.

**Why this challenge matters:** Everything you've used so far was pre-built. This challenge proves that creating a new agent is just writing a TOML file. No code. No deploy pipeline. No waiting. You write a config, start it, and it works — connected to the same knowledge base the other agents built.

**Instructions:**

> You've seen what the pre-built agents can do. Now build your own.
>
> **Step 1: Pick a persona**
>
> Choose one of these starter templates, or invent your own:
>
> | Persona | What It Does | Best For |
> |---------|-------------|----------|
> | **Security Auditor** | Scans KB for compliance issues, access patterns, encryption gaps | Security-focused users |
> | **Onboarding Guide** | Explains the environment to a new team member in plain language | Managers, new hires |
> | **Cost Reporter** | Generates a cost optimization report with specific savings estimates | Finance-aware users |
> | **Custom** | Whatever you want — you write the system prompt | Power users |
>
> **Step 2: Create your config**
>
> Open the **Editor** tab and create a new file at `/opt/aura/configs/my-agent.toml`:
>
> ```toml
> # My Custom Aura Agent
> # Change the system_prompt to define your agent's persona and behavior.
>
> [llm]
> provider = "bedrock"
> model = "us.anthropic.claude-sonnet-4-20250514-v1:0"
> region = "us-east-1"
>
> [agent]
> name = "my-custom-agent"
> temperature = 0.3
> turn_depth = 10
> max_tokens = 8192
>
> # --- THIS IS WHERE THE MAGIC HAPPENS ---
> # Change this system prompt to define what your agent does.
> # It already has access to the Bella Vista knowledge base via Qdrant.
> system_prompt = """
> You are a Security Auditor for the Bella Vista restaurant platform.
> Your job is to review the AWS infrastructure knowledge base and identify
> security risks, compliance gaps, and hardening opportunities.
>
> When asked to audit, search the Qdrant knowledge base and check for:
> - Overly permissive security groups (especially 0.0.0.0/0 rules)
> - Public S3 buckets or unencrypted storage
> - IAM roles with excessive permissions
> - Resources without proper tagging (ownership, environment)
> - Single points of failure (single-AZ databases, no multi-AZ)
> - Missing encryption at rest or in transit
>
> Present findings as a risk-rated table: CRITICAL, HIGH, MEDIUM, LOW.
> Include specific resource names and ARNs from the knowledge base.
> """
>
> # Connect to the same knowledge base and AWS API used by other agents
> [mcp.servers.qdrant]
> transport = "http_streamable"
> url = "http://localhost:8000/mcp"
> description = "Bella Vista knowledge base"
>
> [mcp.servers.aws_api]
> transport = "http_streamable"
> url = "http://localhost:8091/mcp"
> description = "AWS API access (read-only)"
> ```
>
> Feel free to change the `system_prompt` to whatever persona interests you.
>
> **Step 3: Start your agent**
>
> ```bash
> # Start your custom agent on port 3035
> docker run -d --name my-agent --network aura_default \
>   -p 3035:3030 \
>   -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_REGION \
>   -v /opt/aura/configs/my-agent.toml:/app/config.toml \
>   mezmo/aura:latest
> ```
>
> **Step 4: Query your agent**
>
> ```bash
> aura-ask 3035 "Run a full security audit of the Bella Vista environment. Check the knowledge base for all security concerns and present them as a risk-rated report."
> ```
>
> **That's it.** You just created a custom AI agent — with its own persona, its own behavior, connected to a shared knowledge base — in under 5 minutes. No code. No deployment pipeline. Just a TOML file.
>
> **Try different prompts:**
> ```bash
> # If you built the Security Auditor:
> aura-ask 3035 "Which resources would be affected if the legacy SSH security group was exploited? Trace the blast radius."
>
> # If you built the Onboarding Guide:
> aura-ask 3035 "I'm a new SRE joining the Bella Vista team. Give me a complete overview of the infrastructure: what services exist, how they connect, and what I should watch out for."
>
> # If you built the Cost Reporter:
> aura-ask 3035 "Generate a cost optimization report. Identify every resource that is wasting money and estimate monthly savings for each recommendation."
> ```

**Check script:** Always passes (exploration challenge).

---

#### Challenge 10: AI-Generated Agent — Use Aura to Build Aura (Choose Your Own Adventure)

**Time:** ~5 minutes
**Tabs:** Terminal
**Goal:** Ask an existing Aura agent to design a new agent config for you. AI building AI.

**Why this challenge matters:** In Challenge 9 you wrote a TOML config by hand. But Aura already understands the environment — it knows what services exist, what the pain points are, and what the TOML config format looks like. So why not ask Aura to build the next agent for you?

This is the "aha" moment: **the platform improves itself.** An agent that understands your infrastructure can generate purpose-built agents tailored to what it discovered.

**Instructions:**

> You've seen Aura discover an environment, triage incidents, and audit changes. Now let's close the loop — ask Aura to design a new agent based on what it knows.
>
> **Step 1: Ask Aura to generate an agent config**
>
> Use the orchestrator (which has the full KB) to generate a TOML config for a new agent:
>
> ```bash
> aura-ask 3030 "You know this Bella Vista environment — you discovered it. Now I need you to generate a complete Aura TOML agent configuration file for a 'Bella Vista Reliability Agent' that:
>
> 1. Monitors the health of the critical order flow path (ALB → ECS → SQS → Lambda)
> 2. Knows about the specific risks you found (single-AZ database, public S3 bucket, open SSH)
> 3. Can answer questions like 'is the order flow healthy?' and 'what are the top 3 risks right now?'
> 4. Uses Bedrock as the LLM provider and connects to the Qdrant KB at http://localhost:8000/mcp and AWS API at http://localhost:8091/mcp
>
> Output ONLY the complete TOML file, ready to save and run. Include a detailed system_prompt that references the actual resource names, ARNs, and relationships you found in the knowledge base."
> ```
>
> **Step 2: Save the generated config**
>
> Copy Aura's output into a file:
> ```bash
> # Paste the TOML output from the previous command into this file
> # (or use the Editor tab to create it)
> cat > /opt/aura/configs/ai-generated-agent.toml << 'TOML'
> # Paste the generated TOML here
> TOML
> ```
>
> **Step 3: Launch the AI-generated agent**
>
> ```bash
> docker run -d --name ai-agent --network aura_default \
>   -p 3036:3030 \
>   -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_REGION \
>   -v /opt/aura/configs/ai-generated-agent.toml:/app/config.toml \
>   mezmo/aura:latest
> ```
>
> **Step 4: Query your AI-generated agent**
>
> ```bash
> aura-ask 3036 "Is the Bella Vista order flow healthy right now? Check each component in the path and report status."
> ```
>
> ```bash
> aura-ask 3036 "What are the top 3 reliability risks for Bella Vista right now, and what should we fix first?"
> ```
>
> **What just happened:** You asked an AI agent to design another AI agent — one that's tailored to the specific environment it discovered. The generated agent has a system prompt that references actual resource names and relationships from the knowledge base. It's not a generic template — it's a bespoke agent built from real infrastructure knowledge.
>
> **Try generating other agents:**
> ```bash
> aura-ask 3030 "Generate a complete Aura TOML config for a 'Bella Vista Compliance Agent' that checks this environment against CIS AWS Foundations Benchmark controls. Reference the actual resources you discovered. Output only the TOML file."
> ```
>
> ```bash
> aura-ask 3030 "Generate a complete Aura TOML config for a 'Bella Vista Runbook Agent' that serves as the on-call runbook for this environment. It should know every service, every dependency, every known issue, and provide step-by-step remediation for common failures. Output only the TOML file."
> ```

**Check script:** Always passes (exploration challenge).

---

#### Challenge 11: Review & Next Steps

**Time:** ~2 minutes
**Tabs:** Terminal
**Goal:** Summarize what was accomplished and show the path forward.

**Instructions:**

> **What you accomplished today:**
>
> In under 30 minutes, Aura:
> - Discovered and cataloged every resource supporting the Bella Vista restaurant app
> - Built a semantic knowledge base with cross-resource relationships
> - Answered natural language questions about infrastructure you'd never seen before
> - Triaged a **real** incident — database connection pool exhaustion with actual 503 errors
> - Audited infrastructure changes and found SSH open to the world
> - Constructed a blameless post-mortem with timeline and action items
> - Found the single-AZ database, over-provisioned Lambda, and cost waste from legacy EC2
> - **Built your own custom agent** — from TOML config to working AI agent in under 5 minutes, no code required
> - **Used AI to build AI** — asked Aura to generate a purpose-built agent tailored to the environment it discovered
>
> **This wasn't a mock.** Bella Vista is a real application. The traffic was real. The failure was real. The error logs and broken traces were real. Aura investigated a live production-like system.
>
> **What happens next in production:**
>
> - **Scheduled discovery** — Run the orchestrator daily/weekly to keep the KB current
> - **Proactive alerting** — Change audit agent on an hourly cron catches risky changes early
> - **Institutional memory** — Post-mortems stored in the KB inform future incident response
> - **Continuous optimization** — Capacity planning agent runs weekly to catch drift
>
> **Deploy in your environment:**
>
> All configs used in this demo are open source:
> - Agent configs: `examples/mcp-servers/aws/` in the aura-examples repo
> - Custom MCP servers: `mcp-servers/aura-qdrant/` and `mcp-servers/aura-worker/`
> - Docker Compose: Ready to deploy with your AWS credentials

**Check script:** Always passes.

---

## 7. Instruqt Sandbox Configuration

### 7.1 Sandbox Hosts

| Host | Type | Image | Purpose |
|------|------|-------|---------|
| `aura-host` | Container or VM | Ubuntu 22.04 + Docker | Runs the aura Docker Compose stack |

**Machine type:** `n1-standard-4` (4 vCPU, 15 GB RAM) — 10 aura containers need resources.

### 7.2 Cloud Accounts

| Account | Provider | Purpose |
|---------|----------|---------|
| AWS Account | AWS | Bella Vista app infrastructure (ECS, RDS, S3, SQS, etc.) |

### 7.3 Tabs

| Tab | Type | Target | Purpose |
|-----|------|--------|---------|
| Terminal | Terminal | `aura-host` | Primary interaction — curl/aura-ask commands |
| AWS Console | AWS Console | AWS Account | Browse the provisioned infrastructure |
| Bella Vista App | Service | ALB DNS → port 8080 | See the live restaurant app |
| Editor | Code Editor | `aura-host:/opt/aura/configs/` | View/edit TOML configs (optional) |

### 7.4 IAM Policies

#### Admin Policy (Setup Scripts)
Full access for Terraform provisioning.
```json
{ "Effect": "Allow", "Action": "*", "Resource": "*" }
```

#### Learner IAM Policy
Read-only AWS + Bedrock invoke.
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadOnlyAWS",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*", "ecs:Describe*", "ecs:List*",
        "rds:Describe*", "s3:List*", "s3:GetBucket*",
        "lambda:List*", "lambda:GetFunction*",
        "sqs:List*", "sqs:GetQueueAttributes",
        "sns:List*", "sns:GetTopicAttributes",
        "dynamodb:Describe*", "dynamodb:List*",
        "iam:List*", "iam:GetRole*", "iam:GetPolicy*",
        "cloudwatch:Describe*", "cloudwatch:List*", "cloudwatch:GetMetricData",
        "cloudtrail:LookupEvents", "cloudtrail:GetTrailStatus",
        "cloudformation:Describe*", "cloudformation:List*",
        "elasticloadbalancing:Describe*",
        "route53:List*", "route53:GetHostedZone",
        "sts:GetCallerIdentity",
        "servicequotas:List*", "servicequotas:Get*",
        "ecr:Describe*", "ecr:List*", "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Sid": "BedrockInvoke",
      "Effect": "Allow",
      "Action": ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
      "Resource": [
        "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-*",
        "arn:aws:bedrock:us-east-1:*:inference-profile/us.anthropic.*"
      ]
    }
  ]
}
```

#### Service Control Policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RegionRestrict",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringNotEquals": { "aws:RequestedRegion": ["us-east-1"] },
        "ForAnyValue:StringNotLike": { "aws:PrincipalArn": ["arn:aws:iam::*:role/instruqt-*"] }
      }
    },
    {
      "Sid": "BlockExpensiveServices",
      "Effect": "Deny",
      "Action": ["sagemaker:*", "redshift:*", "emr:*", "es:*", "kafka:*"],
      "Resource": "*"
    }
  ]
}
```

---

## 8. Sandbox Isolation — Zero Bleed-Over

Every demo environment must be completely self-contained. No shared state, no shared services, no possibility of one participant's actions affecting another's results.

### 8.1 What Instruqt Provides

Instruqt provisions a **dedicated, temporary AWS account** for each sandbox instance. This means:
- Each participant gets their own AWS account (not a shared account with IAM boundaries)
- Resources created by Terraform are in a completely separate account
- CloudTrail, CloudWatch, IAM — all isolated at the account level
- When the sandbox expires, the entire account is cleaned up

### 8.2 What We Must Ensure

| Layer | Isolation Mechanism | Details |
|-------|---------------------|---------|
| **AWS Infrastructure** | Separate Instruqt AWS account per sandbox | Terraform creates all resources in the participant's own account. No cross-account references. |
| **Bella Vista App** | ECS tasks in participant's own account | App runs on Fargate in the sandbox account. In-memory data store — no shared database. |
| **Bella Vista Docker Image** | Pulled from public/shared ECR, runs locally | Image is read-only. All runtime state is per-instance. |
| **Qdrant Knowledge Base** | Runs on sandbox VM (`localhost:6333`) | Each VM has its own Qdrant instance with its own data volume. Zero network exposure. |
| **Aura Agents** | Run on sandbox VM (ports 3030-3034) | All agents are localhost-only. Each sandbox has its own agent instances. |
| **MCP Servers** | Run on sandbox VM (ports 8000, 8091, 8095) | All MCP servers connect to the participant's own AWS account and Qdrant. |
| **LLM (Bedrock)** | Calls to Bedrock from participant's own account | Each sandbox authenticates to Bedrock with its own IAM credentials. No shared API keys. |
| **Virtual Traffic** | Generated within the participant's own app instance | Traffic manager runs inside the Bella Vista container. No external traffic sources. |
| **Failure Simulator** | Triggered per-instance via API | Failure state is in-memory in the Express server. Triggering a failure in one sandbox has zero effect on others. |

### 8.3 Isolation Architecture

```
┌─────────────────────────────────────┐  ┌─────────────────────────────────────┐
│  Participant A's Sandbox            │  │  Participant B's Sandbox            │
│                                     │  │                                     │
│  VM: aura-host-A                    │  │  VM: aura-host-B                    │
│  ├── Qdrant (localhost:6333)        │  │  ├── Qdrant (localhost:6333)        │
│  ├── Aura agents (localhost:3030+)  │  │  ├── Aura agents (localhost:3030+)  │
│  └── MCP servers (localhost:8xxx)   │  │  └── MCP servers (localhost:8xxx)   │
│                                     │  │                                     │
│  AWS Account: 111111111111          │  │  AWS Account: 222222222222          │
│  ├── VPC: bella-vista-vpc           │  │  ├── VPC: bella-vista-vpc           │
│  ├── ECS: bella-vista (own tasks)   │  │  ├── ECS: bella-vista (own tasks)   │
│  ├── RDS: bella-vista-db            │  │  ├── RDS: bella-vista-db            │
│  ├── S3: bella-vista-assets-abc123  │  │  ├── S3: bella-vista-assets-xyz789  │
│  └── CloudTrail: bella-vista-trail  │  │  └── CloudTrail: bella-vista-trail  │
│                                     │  │                                     │
│  NO CONNECTION BETWEEN A AND B      │  │  NO CONNECTION BETWEEN A AND B      │
└─────────────────────────────────────┘  └─────────────────────────────────────┘
```

### 8.4 Design Rules to Maintain Isolation

1. **No hardcoded account IDs** — Terraform must use `data.aws_caller_identity.current.account_id` for any account-specific references.
2. **S3 bucket names use random suffixes** — `bella-vista-assets-${random_id}` prevents cross-sandbox name collisions.
3. **No external service dependencies** — The demo must work with only the sandbox AWS account and the sandbox VM. No external APIs, no shared databases, no external OTEL backends.
4. **Qdrant binds to localhost only** — The Qdrant container must NOT expose ports beyond the sandbox VM.
5. **Aura agents bind to localhost only** — No external network access to agent APIs.
6. **Docker image must be pullable without account-specific auth** — Either public ECR, public Docker Hub, or pre-baked into the VM image.
7. **Bella Vista's in-memory data store is a feature, not a limitation** — Each instance starts fresh. No shared database means no shared state. If we add RDS as the backing store, it's in the participant's own account.

### 8.5 What This Means for the Bella Vista App

Bella Vista uses an **in-memory data store** by default (products, orders, reservations stored in a JS object). This is actually ideal for demo isolation:

- Each ECS task starts with the same default data (menu items, empty orders)
- Virtual traffic creates orders and reservations within that instance only
- Failure simulator state is in-process memory — per-task, not shared
- No external database dependency for the app to function (RDS exists in the Terraform for Aura to discover, but the app doesn't require it to run)

If we later connect Bella Vista to the RDS instance, it would be the participant's own RDS — still fully isolated.

---

## 9. Lifecycle Scripts

### 9.1 Track Setup (`setup-aura-host`)

```bash
#!/bin/bash
set -euo pipefail

# --- Wait for Instruqt bootstrap ---
until [ -f /opt/instruqt/bootstrap/host-bootstrap-completed ]; do
  echo "Waiting for Instruqt bootstrap..."
  sleep 1
done

# --- Install dependencies ---
apt-get update -qq && apt-get install -y -qq unzip jq > /dev/null
curl -fsSL https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip \
  -o /tmp/terraform.zip
unzip -o /tmp/terraform.zip -d /usr/local/bin/ && rm /tmp/terraform.zip

# --- Pull AWS credentials from Instruqt ---
export AWS_ACCESS_KEY_ID="${INSTRUQT_AWS_ACCOUNT_ID_AWS_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${INSTRUQT_AWS_ACCOUNT_ID_AWS_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION="us-east-1"

# --- Provision Bella Vista AWS infrastructure ---
echo "Provisioning Bella Vista environment..."
cd /opt/aura/terraform
terraform init -input=false
terraform apply -auto-approve -input=false

# --- Inject "risky change" into CloudTrail ---
# Open SSH to the world AFTER setup, so it appears as a recent change
aws ec2 authorize-security-group-ingress \
  --group-id "$(terraform output -raw legacy_ssh_sg_id)" \
  --protocol tcp --port 22 --cidr 0.0.0.0/0 \
  --region us-east-1 || true

# --- Wait for Bella Vista ECS to stabilize ---
echo "Waiting for Bella Vista app to be healthy..."
ALB_DNS=$(terraform output -raw alb_dns_name)
timeout 300 bash -c "until curl -sf http://${ALB_DNS}/ > /dev/null 2>&1; do sleep 5; done"

# --- Start Aura agent stack ---
echo "Starting Aura services..."
mkdir -p /opt/aura/configs
cp /opt/aura/examples/mcp-servers/aws/*.toml /opt/aura/configs/
export AWS_REGION="us-east-1"

cd /opt/aura && docker compose up -d

# Wait for aura services
for port in 6333 8000 8091 8095 8080 3030 3031 3032 3033 3034; do
  timeout 120 bash -c "until curl -sf http://localhost:$port/health > /dev/null 2>&1; do sleep 2; done" || true
done

# --- Install helper scripts ---
chmod +x /opt/aura/bin/aura-ask /opt/aura/bin/aura-status /opt/aura/bin/aura-agents
ln -sf /opt/aura/bin/aura-* /usr/local/bin/

# --- Optional: Pre-seed discovery ---
# Uncomment for SE-led demos where KB should be ready immediately.
# For self-paced, leave commented so the user triggers discovery in Challenge 3.
#
# echo "Pre-seeding knowledge base..."
# curl -s http://localhost:3030/v1/chat/completions \
#   -H "Content-Type: application/json" \
#   -d '{"messages":[{"role":"user","content":"Discover my AWS environment in us-east-1."}]}' \
#   > /dev/null 2>&1 &

echo "Setup complete. Bella Vista is running. Aura is ready."
```

### 9.2 Challenge Check Scripts

| Challenge | Logic |
|-----------|-------|
| 1. Welcome | Always pass |
| 2. Deploy Aura | `docker compose ps` shows running + orchestrator responds |
| 3. Discover | Qdrant `points_count >= 10` |
| 4. Query KB | Qdrant `points_count >= 10` |
| 5-8. Agent challenges | Always pass (exploration) |
| 9. Build Your Own Agent | Always pass (exploration) |
| 10. AI-Generated Agent | Always pass (exploration) |
| 11. Wrap-up | Always pass |

### 9.3 Cleanup (`cleanup-aura-host`)

```bash
#!/bin/bash
set -euo pipefail
cd /opt/aura && docker compose down -v || true
cd /opt/aura/terraform && terraform destroy -auto-approve -input=false || true
```

---

## 10. Helper Scripts

Installed to `/opt/aura/bin/` and symlinked to `/usr/local/bin/`.

### `aura-ask` — Query any agent

```bash
#!/bin/bash
# Usage: aura-ask <port> "your question"
PORT=${1:-3030}
QUESTION="${2:-What can you tell me about this environment?}"
PAYLOAD=$(jq -nc --arg q "$QUESTION" '{"messages":[{"role":"user","content":$q}]}')
curl -s "http://localhost:${PORT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  | jq -r '.choices[0].message.content'
```

### `aura-status` — Stack health check

```bash
#!/bin/bash
echo "=== Aura Stack Status ==="
for svc in qdrant:6333 qdrant-mcp:8000 aws-mcp:8091 worker-mcp:8095 \
           discovery:8080 orchestrator:3030 incident:3031 audit:3032 \
           postmortem:3033 capacity:3034; do
  name="${svc%%:*}"; port="${svc##*:}"
  if curl -sf "http://localhost:${port}/health" > /dev/null 2>&1; then
    echo "  [OK]   ${name} (:${port})"
  else
    echo "  [DOWN] ${name} (:${port})"
  fi
done
echo ""
echo "=== Knowledge Base ==="
POINTS=$(curl -sf http://localhost:6333/collections/aws_resources 2>/dev/null | jq -r '.result.points_count // "N/A"')
echo "  Resources in KB: ${POINTS}"
echo ""
echo "=== Bella Vista App ==="
ALB=$(cat /opt/aura/terraform/terraform.tfstate 2>/dev/null | jq -r '.outputs.alb_dns_name.value // "unknown"')
echo "  App URL: http://${ALB}"
```

### `aura-agents` — Quick reference

```bash
#!/bin/bash
echo "=== Aura Agent Ports ==="
echo "  Orchestrator (discovery):   http://localhost:3030"
echo "  Incident Response:          http://localhost:3031"
echo "  Change Audit:               http://localhost:3032"
echo "  Post-Mortem:                http://localhost:3033"
echo "  Capacity Planning:          http://localhost:3034"
echo ""
echo "Usage: aura-ask <port> \"your question\""
echo "Example: aura-ask 3031 \"Triage the Bella Vista 5xx alarm\""
```

### `bella-vista-fail` — Trigger failure scenarios

```bash
#!/bin/bash
# Usage: bella-vista-fail <scenario> [duration_seconds]
ALB=$(cat /opt/aura/terraform/terraform.tfstate 2>/dev/null | jq -r '.outputs.alb_dns_name.value // "localhost:8080"')
SCENARIO=${1:-connection_pool}
DURATION=${2:-300}

echo "Triggering failure: ${SCENARIO} for ${DURATION}s on Bella Vista..."
curl -s -X POST "http://${ALB}/api/simulate/failure" \
  -H "Content-Type: application/json" \
  -d "{\"scenario\": \"${SCENARIO}\", \"duration\": ${DURATION}}" | jq .

echo ""
echo "Available scenarios: connection_pool, payment_gateway, memory_leak, cascading_failure, data_corruption"
```

---

## 11. Pre-Seed vs Live Discovery Strategy

### Recommended: Hybrid Approach

| Mode | Pre-Seed? | Rationale |
|------|-----------|-----------|
| **Self-paced** (default) | No | Let the user trigger discovery in Challenge 3. The "watch it discover" experience is a highlight. |
| **SE-led demos** | Yes | Uncomment the pre-seed block in setup script. KB is ready immediately. SE can show selective re-scans. |
| **Instructor-led** | Optional | Depends on time. Pre-seed if tight on time; live discovery if time allows. |

The toggle is a single commented block in the setup script (Section 9.1).

---

## 12. Bella Vista Changes Required

### 12.1 Done

| Change | File | Status |
|--------|------|--------|
| Add `"demo"` config profile | `agents-config.json.template` | Done — Mezmo + OTEL disabled, `serviceName: "bella-vista-demo"` |

### 12.2 Required Before Demo

| Change | Details | Effort |
|--------|---------|--------|
| **Pre-bake Docker image into Instruqt VM** | Build Bella Vista image and `docker save` it into the custom VM image. On sandbox start, `docker load` instead of pulling from a registry. Eliminates ECR access issues entirely. | Medium |
| **Create demo `agents-config.json`** | Copy template with `"defaultConfig": "demo"`. Deploy to `/opt/bella-vista/agents-config.json` on the VM image. | Tiny |

### 12.3 Deferred Nice-to-Haves

These are not required for the demo to work but would improve polish. Document here so we can revisit later.

| # | Change | Why | Effort |
|---|--------|-----|--------|
| 1 | **Rename Docker image** from `restaurant-app` to `bella-vista` | Brand consistency across demo, configs, and docs | Small |
| 2 | **Demo-slim Dockerfile** (`Dockerfile.demo`) | Current image includes Claude Code CLI, LogDNA Agent, and OTEL Collector (~heavy). A slim variant strips these since the demo profile disables them. Faster `docker load`, smaller VM image. | Small |
| 3 | **Add "Bella Vista — Powered by Aura" to UI footer** | Screenshots and recordings are clearly branded for the demo context | Tiny |
| 4 | **Add `/health` endpoint to Express API** | Currently health check hits `/` (the full React app). A lightweight `/health` or `/api/health` endpoint is faster for ECS health checks and `aura-status`. | Tiny |
| 5 | **Add Aura badge/link to admin dashboard** | The app's admin UI (`/admin`) could show an "Aura Connected" indicator and link to the Aura orchestrator | Small |
| 6 | **Pre-configure virtual traffic for demo pacing** | Tune the traffic manager to generate orders/reservations at a rate that produces interesting CloudWatch metrics within the demo timeframe (~1 order every 10-15s) | Small |

---

## 13. Open Items & Risks

| # | Item | Status | Impact | Mitigation |
|---|------|--------|--------|------------|
| 1 | **Bedrock access in Instruqt sandbox** | Must validate | Blocks all agents | OpenAI fallback configs exist. Validate first. |
| 2 | **Sandbox VM sizing** | Must validate | 10 aura containers + pre-baked Bella Vista image need resources | Request `n1-standard-4` (4 vCPU, 15 GB) or larger |
| 3 | **ECS + RDS provisioning time** | Known (~5-8 min) | Adds to sandbox startup | RDS is slowest. Consider snapshot restore or Aurora Serverless v2. |
| 4 | **CloudTrail event delay** | Known AWS behavior (5-15 min) | Change audit may not see recent events | Inject risky SG change during setup to ensure visibility by Challenge 6 |
| 5 | **Bella Vista App tab** | Must configure | Browser tab to the ALB URL | Instruqt "Service" tab pointing to ALB DNS from Terraform output |
| 6 | **Cost per sandbox run** | ~55 AWS resources + ECS tasks + RDS | Charges per session | Use smallest instances, set sandbox TTL |
| 7 | **VM image build pipeline** | Need CI/CD to build/update the pre-baked image | Stale images if not updated | Automate with Packer or Instruqt's image builder |

---

## 14. Implementation Phases

| Phase | What | Deliverable | Effort |
|-------|------|-------------|--------|
| **1. Bedrock Validation** | Verify Bedrock model access in Instruqt sandbox | Go/no-go decision | Small |
| **2. VM Image (Pre-bake)** | Build custom Instruqt VM image with Bella Vista Docker image, Aura Docker images, MCP server deps, Terraform, helper scripts all pre-baked | Packer template or Instruqt image config | Medium |
| **3. Terraform** | Write IaC for Bella Vista AWS environment | `demo/terraform/` | Medium |
| **4. Docker Compose** | Demo-specific compose for all 10 aura services | `demo/docker-compose.yml` | Small |
| **5. Instruqt Track** | 9 challenges, lifecycle scripts, tabs, helper scripts | Track on Instruqt platform | Medium |
| **6. End-to-End Testing** | Sandbox start → Terraform → Bella Vista healthy → discovery → all agents | All challenges pass | Medium |
| **7. Polish** | Instructions, timing, error messages, fallback paths | Production-ready track | Small |

**Recommended order:** Phase 1 first (go/no-go gate). Then 2 → 3 → 4 → 5 → 6 → 7.

**Pre-bake strategy (Phase 2) details:**
```
# What gets baked into the VM image:
/opt/bella-vista/
├── bella-vista.tar          # docker save of the Bella Vista image
├── agents-config.json       # demo profile (Mezmo + OTEL disabled)
└── Dockerfile.demo          # (future: slim variant)

/opt/aura/
├── docker-compose.yml       # Demo-specific compose for all 10 services
├── configs/                 # Agent TOML configs
├── bin/                     # Helper scripts (aura-ask, aura-status, etc.)
├── examples/                # Copy of examples/mcp-servers/aws/
├── mcp-servers/             # Custom MCP server code
└── terraform/               # Terraform for AWS infrastructure

# Pre-pulled Docker images (docker save → docker load):
- qdrant/qdrant:latest
- mezmo/aura:latest
- mcp-proxy image
- bella-vista (restaurant-app) image

# Pre-installed tools:
- terraform
- docker + docker compose
- jq, curl, unzip
- python3, uvx (for MCP servers)
```

This means sandbox startup only needs to: load Docker images from disk, run `terraform apply`, and start Docker Compose. No network pulls.

---

## 15. Success Metrics

| Metric | Target | How to Measure |
|--------|--------|---------------|
| Track completion rate | > 70% complete common path | Instruqt analytics |
| Average completion time | < 30 min (common path) | Instruqt analytics |
| Discovery success rate | > 95% of runs catalog 40+ resources | Check script pass rate |
| Agent interaction rate | > 50% try at least 2 adventure agents | Challenge start counts |
| Failure demo trigger rate | > 60% trigger the incident in Challenge 5 | API call logging |
| NPS / satisfaction | > 8/10 | Post-track survey |

---

## Appendix A: Bella Vista Source Reference

| Item | Location |
|------|----------|
| Application source | `~/Documents/GitHub/reserve-and-shop-easy/` |
| Frontend (React) | `src/` — pages, components, hooks |
| Backend (Express) | `server/` — API routes, middleware, services |
| Failure simulator | `server/services/failureSimulator.js` |
| Virtual traffic | `server/services/virtualTraffic/` |
| OTEL instrumentation | `server/telemetry-simple.js` + OpenTelemetry SDK deps |
| Docker image | `Dockerfile` — multi-stage, includes OTEL Collector + Mezmo Agent |
| EKS config | `aws/eksctl-cluster.yaml` |
| K8s manifests | `k8s/` — deployments, services, monitoring, autoscaling |
| Agent config template | `agents-config.json.template` — includes `"demo"` profile for Instruqt |
| Demo config profile | `agents-config.json.template` → `configurations.demo` — Mezmo + OTEL disabled |

## Appendix B: Fallback — OpenAI Provider

If Bedrock is unavailable in Instruqt sandboxes:

1. Use `*-openai.toml` variants of all agent configs (already exist)
2. Inject `OPENAI_API_KEY` as an Instruqt track environment variable
3. SE or track admin provides the key when launching
4. All architecture remains identical — only the `[llm]` section changes

## Appendix C: Demo-Specific Config Modifications

For the Instruqt demo, create variants of agent configs in `demo/configs/` that:

1. Hardcode `region = "us-east-1"` (no env var resolution needed)
2. Use Docker network hostnames instead of localhost (e.g., `http://qdrant-mcp:8000/mcp` instead of `http://localhost:8000/mcp`)
3. Add Bella Vista context to system prompts (e.g., "This environment runs the Bella Vista restaurant app with ECS services, RDS PostgreSQL, SQS queues...")
4. Reference the failure simulator in the incident response agent prompt
5. Reduce `turn_depth` for faster responses in a demo context
6. **Augment the orchestrator's system prompt** to handle both discovery dispatch AND general KB queries. The current prompt is discovery-only ("You are an AWS Discovery Orchestrator. You coordinate parallel workers..."). For the demo, Challenge 4 uses the orchestrator to answer KB questions. Add to the system prompt: "When the user asks a question about the environment (not a discovery request), use your `search` tool to query the Qdrant knowledge base and answer directly. Only dispatch workers when asked to discover or scan."

## Appendix D: Known Instruqt Platform Constraints

These Instruqt-specific details must be validated during track development:

1. **Setup timeout** — Instruqt sandbox setup typically allows 15-20 minutes. RDS provisioning alone takes 5-8 min. Set `timeout: 1200` (20 min) in the track YAML. Consider splitting Terraform into "track setup" (runs once) and Docker into "challenge 2 setup."
2. **AWS credential variable names** — Format is `INSTRUQT_AWS_ACCOUNTS_{ACCOUNT_ID}_{CREDENTIAL}` where `ACCOUNT_ID` is the `id` field from the track config, uppercased, hyphens replaced with underscores. Verify against the actual Instruqt track YAML.
3. **Dynamic Bella Vista App tab** — The ALB DNS is a Terraform output that varies per sandbox. Instruqt requires `external_url` set dynamically in lifecycle scripts, not at track config time. The setup script must output the URL for the Service tab.
4. **Docker Compose is net-new** — The existing `examples/mcp-servers/aws/docker-compose.yml` has 4 services. The demo needs 10 services with custom Qdrant MCP, correct AWS credential injection to all containers, and Docker network hostnames. See Appendix E for the skeleton.
5. **Learner troubleshooting** — Add a troubleshooting section to the challenge instructions for common issues: discovery taking longer than 3 minutes, Bedrock rate limits, "service unavailable" errors on agent ports.

## Appendix E: Demo Docker Compose Skeleton

The existing `examples/mcp-servers/aws/docker-compose.yml` has 4 services. The demo needs 10. This skeleton shows the full service graph with dependencies, port mappings, credential injection, and volume mounts. It is the starting point for `demo/docker-compose.yml`.

**Key differences from the existing compose:**
- Custom Qdrant MCP (`aura-qdrant/server.py`) replaces generic `mcp-server-qdrant`
- Aura Worker MCP added for agent delegation
- Discovery worker on port 8080 (separate from orchestrator)
- 4 specialized agents on ports 3031-3034
- All aura containers receive AWS credentials (for Bedrock)
- All aura containers use Docker network hostnames for MCP URLs

```yaml
# demo/docker-compose.yml — Full Aura Demo Stack (10 services)
#
# Pre-baked into the Instruqt VM image. Started by the setup script.
# All images are pre-loaded via `docker load` — no network pulls.
#
# Usage:
#   export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=us-east-1
#   docker compose up -d

# Infrastructure credentials — Instruqt managed account (discovery + Terraform)
x-infra-credentials: &infra-creds
  AWS_ACCESS_KEY_ID: ${INSTRUQT_AWS_ACCESS_KEY_ID}
  AWS_SECRET_ACCESS_KEY: ${INSTRUQT_AWS_SECRET_ACCESS_KEY}
  AWS_REGION: ${AWS_REGION:-us-east-1}

# Bedrock credentials — separate Mezmo account (LLM calls only)
# TEMPORARY: Remove when Instruqt enables cloud_ai_services
x-bedrock-credentials: &bedrock-creds
  AWS_ACCESS_KEY_ID: ${BEDROCK_AWS_ACCESS_KEY_ID}
  AWS_SECRET_ACCESS_KEY: ${BEDROCK_AWS_SECRET_ACCESS_KEY}
  AWS_REGION: ${AWS_REGION:-us-east-1}

x-mcp-urls: &mcp-urls
  AWS_MCP_URL: http://aws-mcp:8091/mcp
  QDRANT_MCP_URL: http://qdrant-mcp:8000/mcp
  AURA_WORKER_MCP_URL: http://aura-worker-mcp:8095/mcp

x-aura-base: &aura-base
  image: mezmo/aura:latest
  environment:
    <<: [*bedrock-creds, *mcp-urls]  # Aura agents use Bedrock creds for LLM
  depends_on:
    aws-mcp:
      condition: service_healthy
    qdrant-mcp:
      condition: service_healthy
  restart: unless-stopped

services:
  # ============================================================
  # TIER 1: Data stores (no dependencies)
  # ============================================================

  qdrant:
    image: qdrant/qdrant:latest
    ports:
      - "6333:6333"
    volumes:
      - qdrant_data:/qdrant/storage
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:6333/ || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 5
      start_period: 5s

  # ============================================================
  # TIER 2: MCP servers (depend on Qdrant / AWS creds)
  # ============================================================

  # AWS API MCP — read-only AWS access via mcp-proxy
  # AWS API MCP — uses INFRASTRUCTURE creds (Instruqt managed account)
  aws-mcp:
    image: python:3.12-slim
    ports:
      - "8091:8091"
    environment:
      <<: *infra-creds
      READ_OPERATIONS_ONLY: "true"
    command: >
      bash -c "pip install -q mcp-proxy awslabs.aws-api-mcp-server &&
      mcp-proxy --transport streamablehttp --host 0.0.0.0 --port 8091
      -e READ_OPERATIONS_ONLY true
      -e AWS_REGION $$AWS_REGION
      -e AWS_ACCESS_KEY_ID $$AWS_ACCESS_KEY_ID
      -e AWS_SECRET_ACCESS_KEY $$AWS_SECRET_ACCESS_KEY
      -- awslabs.aws-api-mcp-server"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf -X POST http://localhost:8091/mcp -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d '{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"ping\"}' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 45s

  # Custom Qdrant MCP — discover_and_store, filtered search, KB operations
  # IMPORTANT: This replaces the generic mcp-server-qdrant.
  # Uses aura-qdrant/server.py which has discover_and_store (boto3 + Qdrant direct).
  # Custom Qdrant MCP — uses INFRASTRUCTURE creds (discover_and_store calls boto3)
  qdrant-mcp:
    image: python:3.12-slim
    ports:
      - "8000:8000"
    environment:
      <<: *infra-creds
      QDRANT_URL: http://qdrant:6333
    volumes:
      - ./mcp-servers/aura-qdrant:/app/mcp-server
    command: >
      bash -c "pip install -q mcp-proxy boto3 qdrant-client fastembed mcp &&
      mcp-proxy --transport streamablehttp --host 0.0.0.0 --port 8000
      -e QDRANT_URL http://qdrant:6333
      -e AWS_REGION $$AWS_REGION
      -e AWS_ACCESS_KEY_ID $$AWS_ACCESS_KEY_ID
      -e AWS_SECRET_ACCESS_KEY $$AWS_SECRET_ACCESS_KEY
      -- uv run /app/mcp-server/server.py"
    depends_on:
      qdrant:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -sf -X POST http://localhost:8000/mcp -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d '{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"ping\"}' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  # ============================================================
  # TIER 3: Discovery worker (depends on MCP servers)
  # ============================================================

  # Discovery worker — handles individual service discovery tasks
  # Called by the aura-worker-mcp when the orchestrator delegates work.
  discovery-worker:
    <<: *aura-base
    ports:
      - "8080:3030"
    volumes:
      - ./configs/aws-discovery-agent.toml:/app/config.toml

  # Aura Worker MCP — agent delegation with throttling
  # Wraps the discovery-worker's API for run_agents_parallel calls.
  aura-worker-mcp:
    image: python:3.12-slim
    ports:
      - "8095:8095"
    environment:
      AURA_WORKER_URL: http://discovery-worker:3030
    volumes:
      - ./mcp-servers/aura-worker:/app/mcp-server
    command: >
      bash -c "pip install -q mcp-proxy mcp httpx &&
      mcp-proxy --transport streamablehttp --host 0.0.0.0 --port 8095
      -e AURA_WORKER_URL http://discovery-worker:3030
      -- uv run /app/mcp-server/server.py"
    depends_on:
      discovery-worker:
        condition: service_started
    healthcheck:
      test: ["CMD-SHELL", "curl -sf -X POST http://localhost:8095/mcp -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d '{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"ping\"}' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  # ============================================================
  # TIER 4: Orchestrator + specialized agents (depend on MCP servers)
  # ============================================================

  # Orchestrator — primary entry point for discovery and KB queries
  orchestrator:
    <<: *aura-base
    ports:
      - "3030:3030"
    volumes:
      - ./configs/aws-orchestrator-agent.toml:/app/config.toml
    depends_on:
      aws-mcp:
        condition: service_healthy
      qdrant-mcp:
        condition: service_healthy
      aura-worker-mcp:
        condition: service_healthy

  # Incident Response Agent
  incident-response:
    <<: *aura-base
    ports:
      - "3031:3030"
    volumes:
      - ./configs/aws-incident-response-agent.toml:/app/config.toml

  # Change Audit Agent
  change-audit:
    <<: *aura-base
    ports:
      - "3032:3030"
    volumes:
      - ./configs/aws-change-audit-agent.toml:/app/config.toml

  # Post-Mortem Agent
  post-mortem:
    <<: *aura-base
    ports:
      - "3033:3030"
    volumes:
      - ./configs/aws-postmortem-agent.toml:/app/config.toml

  # Capacity Planning Agent
  capacity-planning:
    <<: *aura-base
    ports:
      - "3034:3030"
    volumes:
      - ./configs/aws-capacity-planning-agent.toml:/app/config.toml

volumes:
  qdrant_data:
```

### Service Dependency Graph

```
qdrant (6333)
  │
  └──► qdrant-mcp (8000)  ──────────────────────────────────┐
         │                                                    │
         ├──► discovery-worker (8080)                         │
         │      │                                             │
         │      └──► aura-worker-mcp (8095)                   │
         │             │                                      │
aws-mcp (8091) ────────┼──► orchestrator (3030) ◄─────────────┘
         │             │
         ├─────────────┼──► incident-response (3031)
         ├─────────────┼──► change-audit (3032)
         ├─────────────┼──► post-mortem (3033)
         └─────────────┴──► capacity-planning (3034)
```

### Implementation Notes

1. **Dual credential anchors** — `x-infra-creds` (Instruqt managed account) goes to MCP servers for AWS discovery. `x-bedrock-creds` (Mezmo Bedrock account) goes to Aura agents for LLM calls. When `cloud_ai_services` is enabled, collapse both into a single `x-aws-credentials` anchor. This is the ONLY change needed to switch to single-account mode.
2. **Port mapping pattern** — All aura containers listen internally on 3030 but are mapped to different host ports (3030-3034, 8080). This means the TOML configs don't need port changes.
3. **Volume mounts for configs** — Each agent mounts its TOML config from `./configs/`. These are the demo-specific variants (Appendix C), not the originals from `examples/`.
4. **Volume mounts for MCP servers** — The custom MCP server code (`aura-qdrant/`, `aura-worker/`) is mounted from `./mcp-servers/`.
5. **`pip install` in MCP containers** — For the pre-baked VM image, consider building custom Docker images with dependencies pre-installed to eliminate startup delay. The `pip install` approach works but adds 15-30s to each MCP container startup.
6. **Health check cascade** — The orchestrator waits for `aws-mcp`, `qdrant-mcp`, AND `aura-worker-mcp` to be healthy. The specialized agents only wait for `aws-mcp` and `qdrant-mcp` (they don't use the worker).
7. **`restart: unless-stopped`** — Aura containers restart if they crash. Important since Bedrock rate limits can cause transient failures during heavy parallel discovery.
