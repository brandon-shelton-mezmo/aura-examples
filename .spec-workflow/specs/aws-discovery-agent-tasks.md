# AWS Discovery Agent — Implementation Tasks

**Spec:** `.spec-workflow/specs/aws-discovery-agent.md`
**Created:** 2026-03-17

## Dependency Graph

```
WAVE 0 — Validate (sequential, must complete before all else)
  └── T0: Validate MCP server installations

WAVE 1 — Scaffold (parallel)
  ├── T1a: Create directory structure
  ├── T1b: Create IAM CloudFormation template
  └── T1c: Create IAM Terraform module

WAVE 2 — Core Configs (parallel, after Wave 1)
  ├── T2a: Create preflight agent config (Bedrock)
  ├── T2b: Create discovery agent config (Bedrock)
  ├── T2c: Create docker-compose.yml
  └── T2d: Create security review document

WAVE 3 — Variants + Specialized Agents (parallel, after Wave 2)
  ├── T3a: Create preflight OpenAI variant
  ├── T3b: Create discovery agent OpenAI variant
  ├── T3c: Create discovery agent dev variant (local Qdrant path)
  ├── T3d: Create change audit agent config (Bedrock + OpenAI)
  ├── T3e: Create incident response agent config (Bedrock + OpenAI)
  ├── T3f: Create post-mortem agent config (Bedrock + OpenAI)
  ├── T3g: Create capacity planning agent config (Bedrock + OpenAI)
  └── T3h: Create query-only agent config (Bedrock + OpenAI)

WAVE 4 — Documentation (parallel, after Wave 3)
  ├── T4a: Write AWS agents README
  ├── T4b: Write knowledge base README
  ├── T4c: Write quick-start guide
  ├── T4d: Write troubleshooting runbook
  └── T4e: Write cost estimate document

WAVE 5 — Finalize (sequential, after Wave 4)
  ├── T5a: Update examples/CLAUDE.md inventory
  ├── T5b: Validate all TOML configs
  └── T5c: End-to-end test
```

---

## WAVE 0 — Validate

### T0: Validate MCP Server Installations

- **Purpose:** Confirm both MCP servers install, start, and expose the expected tools. All subsequent tasks depend on the exact tool names and parameters discovered here.
- **Files:** None created — research task only. Update spec if tool names differ.
- _Requirements: R1, R2_
- _Prompt: Role: DevOps engineer validating MCP tool integrations for the aura agent framework | Task: Install and validate two MCP servers, documenting exact tool names, parameters, and behavior. (1) Install awslabs.aws-api-mcp-server via `uvx awslabs.aws-api-mcp-server@latest`. Confirm it starts. Use `npx @modelcontextprotocol/inspector --cli --method tools/list uvx awslabs.aws-api-mcp-server@latest` to list all tools. Document each tool name, description, and parameters. Confirm READ_OPERATIONS_ONLY=true env var is respected. Check whether the aws CLI binary is required or if boto3 is used internally (look at package dependencies). (2) Install mcp-server-qdrant via `uvx mcp-server-qdrant`. Confirm it starts. Use the MCP inspector to list tools. Document `qdrant-store` and `qdrant-find` parameters. Confirm the `collection_name` parameter is accepted per-call (not just via env var). Test with QDRANT_LOCAL_PATH mode to confirm embedded Qdrant works. (3) Report findings in a structured format: tool names, parameter schemas, confirmed behaviors, any surprises. If tool names differ from what the spec assumes (`call_aws`, `suggest_aws_commands`, `qdrant-store`, `qdrant-find`), note the correct names so all subsequent configs can be updated. | Restrictions: Do not create any config files or modify the spec. This is pure validation and documentation. Install tools in a temporary location if needed. | Success: Both MCP servers install and start successfully. All tool names and parameters are documented. READ_OPERATIONS_ONLY behavior confirmed. Qdrant per-call collection_name confirmed or denied. AWS CLI binary dependency confirmed or denied._

---

## WAVE 1 — Scaffold (run in parallel)

### T1a: Create Directory Structure

- **Purpose:** Create the directory layout for all AWS agent configs and supporting files.
- **Files created:**
  - `examples/mcp-servers/aws/` (directory)
  - `examples/rag/aws-knowledge-base/` (directory)
  - `iam/` (directory)
  - `docs/quick-start.md` (placeholder — content in T4c)
  - `docs/security-review.md` (placeholder — content in T2d)
  - `docs/troubleshooting.md` (placeholder — content in T4d)
  - `docs/cost-estimate.md` (placeholder — content in T4e)
- _Requirements: None (scaffold)_
- _Prompt: Role: Project scaffolder for the aura-examples repository | Task: Create the directory structure for the AWS discovery agent ecosystem. Create these directories: `examples/mcp-servers/aws/`, `examples/rag/aws-knowledge-base/`, and `iam/`. Create empty placeholder files with a single comment header in each: `docs/quick-start.md`, `docs/security-review.md`, `docs/troubleshooting.md`, `docs/cost-estimate.md`. Each placeholder should contain only `# [Title]\n\nTODO: Content will be added in a later task.` | Restrictions: Do not create any TOML configs or substantial content. Just directories and placeholders. Follow existing project structure conventions from `.claude/rules/project-structure.md`. | Success: All directories exist. All placeholder files exist with headers. No other files created._

### T1b: Create IAM CloudFormation Template

- **Purpose:** One-click IAM role deployment for the discovery agent's read-only AWS access.
- **Files created:** `iam/aura-readonly-role.yaml`
- _Leverage: IAM policy from spec section "Infrastructure > AWS IAM Policy (Minimum Read-Only)"_
- _Requirements: R5_
- _Prompt: Role: AWS CloudFormation engineer | Task: Create a CloudFormation template at `iam/aura-readonly-role.yaml` that deploys an IAM role named `aura-discovery-role` with a read-only policy for infrastructure discovery. The policy must include exactly these actions: `sts:GetCallerIdentity`, `ec2:Describe*`, `ecs:Describe*`, `ecs:List*`, `lambda:List*`, `lambda:GetFunction`, `lambda:GetPolicy`, `rds:Describe*`, `dynamodb:Describe*`, `dynamodb:List*`, `s3:ListAllMyBuckets`, `s3:GetBucketLocation`, `s3:GetBucketPolicy`, `s3:GetBucketTagging`, `s3:GetEncryptionConfiguration`, `iam:List*`, `iam:GetRole`, `iam:GetPolicy`, `iam:GetPolicyVersion`, `elasticloadbalancing:Describe*`, `route53:List*`, `route53:GetHostedZone`, `cloudfront:List*`, `cloudfront:GetDistribution`, `sqs:List*`, `sqs:GetQueueAttributes`, `sns:List*`, `sns:GetTopicAttributes`, `cloudformation:Describe*`, `cloudformation:List*`, `cloudwatch:Describe*`, `cloudwatch:List*`, `logs:Describe*`, `secretsmanager:ListSecrets`, `secretsmanager:DescribeSecret`, `ssm:DescribeParameters`, `eks:Describe*`, `eks:List*`. Add `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` as a separate statement conditioned on a parameter `EnableBedrock` (default true). The trust policy should allow the role to be assumed by EC2 and ECS tasks. Include CloudFormation Outputs for the role ARN and name. Add a comment block at the top explaining what this is for and how to deploy it: `aws cloudformation deploy --template-file iam/aura-readonly-role.yaml --stack-name aura-discovery-role --capabilities CAPABILITY_NAMED_IAM`. CRITICAL: Do NOT include `secretsmanager:GetSecretValue` or `ssm:GetParameter`. | Restrictions: Standard CloudFormation YAML only. No custom resources or macros. | Success: Template validates with `aws cloudformation validate-template`. Deploys successfully. Role has exactly the specified permissions — no more, no less._

### T1c: Create IAM Terraform Module

- **Purpose:** Terraform equivalent of the CloudFormation template for teams using Terraform.
- **Files created:** `iam/terraform/main.tf`, `iam/terraform/variables.tf`, `iam/terraform/outputs.tf`
- _Leverage: Same IAM policy as T1b_
- _Requirements: R5_
- _Prompt: Role: Terraform module developer | Task: Create a Terraform module at `iam/terraform/` with three files: `main.tf`, `variables.tf`, `outputs.tf`. The module creates an IAM role named `aura-discovery-role` (configurable via variable) with the same read-only policy as the CloudFormation template in T1b. Use the exact same action list. Include a variable `enable_bedrock` (default true) that conditionally adds Bedrock InvokeModel permissions. Include a variable `trusted_principals` (default: EC2 and ECS task assume-role). Output the role ARN and name. Add a header comment in main.tf explaining usage: `cd iam/terraform && terraform init && terraform apply`. CRITICAL: Do NOT include `secretsmanager:GetSecretValue` or `ssm:GetParameter`. | Restrictions: Terraform HCL only. AWS provider required. No external modules — self-contained. Terraform >= 1.0 compatible. | Success: `terraform validate` passes. `terraform plan` shows expected resources. Policy matches CloudFormation template exactly._

---

## WAVE 2 — Core Configs (run in parallel, after Wave 1)

### T2a: Create Preflight Agent Config

- **Purpose:** The first config an SRE runs — validates their environment and recommends agent configuration.
- **Files created:** `examples/mcp-servers/aws/aws-mcp-preflight.toml`
- _Leverage: Spec section "Preflight Config: aws-mcp-preflight.toml", existing Datadog basic config as pattern reference (`examples/mcp-servers/datadog/datadog-basic.toml`)_
- _Requirements: R1, R2_
- _Prompt: Role: Aura TOML configuration developer building an AWS preflight validation agent | Task: Create `examples/mcp-servers/aws/aws-mcp-preflight.toml` — the preflight validation agent that SREs run first to validate their environment. Read the full config from the spec at `.spec-workflow/specs/aws-discovery-agent.md` under "Preflight Config: aws-mcp-preflight.toml" and extract it into the actual file. Follow the exact inline comment and header style from `examples/mcp-servers/datadog/datadog-basic.toml` (comment block at top with description, provider, features, usage, prerequisites). The config must include: (1) `[llm]` section with Bedrock provider, (2) `[agent]` section with name, temperature 0.2, turn_depth 8, and the full preflight system prompt from the spec, (3) `[mcp.servers.aws_api]` with stdio transport, uvx command, READ_OPERATIONS_ONLY=true, (4) `[mcp.servers.qdrant]` with stdio transport, uvx command, QDRANT_URL with default. All secrets must use `{{ env.VAR }}` syntax. Every non-obvious TOML setting must have an inline comment. | Restrictions: TOML only — no code. Must follow aura config schema from `~/Documents/GitHub/aura/docs/toml-schema-design.md`. Use only valid transports: `http_streamable` or `stdio`. Provider must be lowercase. Do not hardcode any API keys or URLs. | Success: `python3 -c "import tomllib; tomllib.load(open('examples/mcp-servers/aws/aws-mcp-preflight.toml', 'rb'))"` passes. Config has all required sections. Inline comments explain every setting._

### T2b: Create Discovery Agent Config (Bedrock)

- **Purpose:** The core discovery agent that inventories AWS resources and stores them in Qdrant.
- **Files created:** `examples/mcp-servers/aws/aws-discovery-agent.toml`
- _Leverage: Spec section "Primary Config: aws-discovery-agent.toml", data model section for system prompt details, existing Datadog incident responder as pattern reference (`examples/mcp-servers/datadog/datadog-incident-responder.toml`)_
- _Requirements: R1, R2, R3, R4, R5_
- _Prompt: Role: Aura TOML configuration developer building the core AWS infrastructure discovery agent | Task: Create `examples/mcp-servers/aws/aws-discovery-agent.toml` — the primary discovery agent that systematically scans an AWS environment and stores findings in a Qdrant knowledge base. Read the full config from the spec at `.spec-workflow/specs/aws-discovery-agent.md` under "Primary Config: aws-discovery-agent.toml" and extract it into the actual file. The system prompt is the most critical part — it must include: the 5 core principles (read-only, no secrets, structured output, relationship aware, search first), the 2 tool descriptions (AWS API and Qdrant), the 5-phase discovery methodology with specific CLI commands for each phase, the document format template for qdrant-store, scoped discovery instructions, knowledge base querying instructions, and interaction style guidelines. All from the spec. Config must include: `[llm]` Bedrock provider with Claude Sonnet 4, `[agent]` with temperature 0.3, turn_depth 15, max_tokens 8192, context array, `[mcp.servers.aws_api]` with READ_OPERATIONS_ONLY=true, `[mcp.servers.qdrant]` with TOOL_STORE_DESCRIPTION and TOOL_FIND_DESCRIPTION. Follow the inline comment style from `examples/mcp-servers/datadog/datadog-incident-responder.toml` (the use-case tier pattern with rich comments). | Restrictions: TOML only. Must follow aura config schema. All secrets via `{{ env.VAR }}`. The system prompt must be comprehensive — this is the agent's entire brain. Do not truncate it. | Success: TOML parses. System prompt includes all 5 discovery phases with specific AWS CLI commands. Both MCP servers configured. Context array present._

### T2c: Create Docker Compose Stack

- **Purpose:** One-command startup for Qdrant + aura with all dependencies.
- **Files created:** `examples/mcp-servers/aws/docker-compose.yml`
- _Leverage: Spec section "Infrastructure > Docker Compose Stack"_
- _Requirements: R2_
- _Prompt: Role: Docker Compose engineer building an all-in-one stack for the aura AWS discovery agent | Task: Create `examples/mcp-servers/aws/docker-compose.yml` that starts Qdrant and aura with a single `docker compose up`. Must include: (1) `qdrant` service using `qdrant/qdrant:latest`, port 6333, named volume `qdrant_data` for persistence. (2) `aura` service using `mezmo/aura:latest`, port 3030, volume mount for the discovery agent config, environment variables passthrough for AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, QDRANT_URL pointing to `http://qdrant:6333`, depends_on qdrant. (3) Named volume `qdrant_data` for persistent storage. Add comments explaining: what each service does, how to start (`docker compose up -d`), how to view logs (`docker compose logs -f aura`), how to switch configs (change the volume mount path), that `qdrant_data` persists across restarts. Note in comments that the aura image must have Python/uvx available for MCP servers — if not, document the workaround. | Restrictions: Standard docker-compose v3 syntax. Do not hardcode any secrets. Use environment variable passthrough (just the variable name, no value). | Success: `docker compose config` validates. Services start in correct order. Qdrant is accessible at localhost:6333. Aura is accessible at localhost:3030._

### T2d: Create Security Review Document

- **Purpose:** Pre-written answers for the security team review that will gate deployment.
- **Files created:** `docs/security-review.md`
- _Leverage: Spec section "Adoption & Usability > IAM Setup: Remove the Fear"_
- _Requirements: R5_
- _Prompt: Role: Security engineer writing a review document for an AI-powered infrastructure discovery tool | Task: Create `docs/security-review.md` — a document that answers every question a security team will ask before approving deployment of the aura discovery agent. Structure it as a Q&A format. Must cover: (1) What does it access? — Read-only AWS APIs only. Include the exact permission list. No write/delete/modify. (2) Can it change our infrastructure? — No. READ_OPERATIONS_ONLY enforced at MCP server level. IAM policy has zero mutating permissions. (3) Does it see our secrets? — No. secretsmanager:GetSecretValue and ssm:GetParameter explicitly excluded from IAM policy. (4) Where does our data go? — Qdrant runs in your VPC (self-hosted Docker). LLM calls go to AWS Bedrock (stays in your AWS account). No data leaves AWS when using Bedrock. (5) What about the AI model? — AWS Bedrock, same compliance as any other AWS service. Data not used for model training. (6) Can we audit what it does? — Yes. All AWS API calls appear in CloudTrail. All Qdrant writes are timestamped. (7) Can we revoke access instantly? — Delete the IAM role or disable access key. (8) Is the code open source? — Yes, aura and all configs. (9) What data is stored in Qdrant? — Resource metadata only. Never secrets, passwords, connection strings, or parameter values. (10) Network requirements? — Qdrant on localhost or private VPC. Bedrock API endpoint. No public internet access required. Include a "Deployment Checklist" section at the end: IAM role deployed, credentials configured, Qdrant running, network access verified, CloudTrail logging confirmed. | Restrictions: No marketing language. Factual, concise, auditable. Reference specific IAM actions and config settings. | Success: Document answers all 10 security questions. Includes exact permission list. Includes deployment checklist. A security engineer can read this and make an approval decision._

---

## WAVE 3 — Variants + Specialized Agents (run in parallel, after Wave 2)

### T3a: Create Preflight OpenAI Variant

- **Purpose:** Preflight config using OpenAI instead of Bedrock for teams not using AWS Bedrock.
- **Files created:** `examples/mcp-servers/aws/aws-mcp-preflight-openai.toml`
- _Leverage: T2a (Bedrock preflight) — copy and swap LLM provider_
- _Requirements: R1, R2_
- _Prompt: Role: Aura TOML configuration developer | Task: Create `examples/mcp-servers/aws/aws-mcp-preflight-openai.toml` — an OpenAI variant of the preflight agent. Copy `examples/mcp-servers/aws/aws-mcp-preflight.toml` and make these changes: (1) Change `[llm]` to `provider = "openai"`, `model = "gpt-4o"`, add `api_key = "{{ env.OPENAI_API_KEY }}"`. (2) Remove the `region` field from `[llm]`. (3) Update the comment header to say "Provider: openai" and add OPENAI_API_KEY to prerequisites. (4) Keep everything else identical — same system prompt, same MCP servers, same agent settings. | Restrictions: Only change the LLM provider section and comment header. System prompt and MCP configs must be identical to the Bedrock variant. | Success: TOML parses. Only difference from Bedrock variant is the `[llm]` section and header comments._

### T3b: Create Discovery Agent OpenAI Variant

- **Purpose:** Discovery agent using OpenAI instead of Bedrock.
- **Files created:** `examples/mcp-servers/aws/aws-discovery-agent-openai.toml`
- _Leverage: T2b (Bedrock discovery) — copy and swap LLM provider_
- _Requirements: R1, R2, R3, R4, R5_
- _Prompt: Role: Aura TOML configuration developer | Task: Create `examples/mcp-servers/aws/aws-discovery-agent-openai.toml` — an OpenAI variant of the discovery agent. Copy `examples/mcp-servers/aws/aws-discovery-agent.toml` and make these changes: (1) Change `[llm]` to `provider = "openai"`, `model = "gpt-4o"`, add `api_key = "{{ env.OPENAI_API_KEY }}"`. (2) Remove the `region` field from `[llm]`. (3) Update the comment header to say "Provider: openai" and add OPENAI_API_KEY to prerequisites. (4) Keep everything else identical. | Restrictions: Only change the LLM provider section and header comments. | Success: TOML parses. Only difference from Bedrock variant is the `[llm]` section and header comments._

### T3c: Create Discovery Agent Dev Variant

- **Purpose:** Development config with local Qdrant path (no Docker needed) and lower turn_depth.
- **Files created:** `examples/mcp-servers/aws/aws-discovery-agent-dev.toml`
- _Leverage: Spec section "Dev Config: aws-discovery-agent-dev.toml", T2b as base_
- _Requirements: R1, R2_
- _Prompt: Role: Aura TOML configuration developer | Task: Create `examples/mcp-servers/aws/aws-discovery-agent-dev.toml` — a development variant optimized for local iteration. Read the dev config from the spec at `.spec-workflow/specs/aws-discovery-agent.md` under "Dev Config". Key differences from the production Bedrock config: (1) Uses OpenAI provider (gpt-4o), (2) turn_depth = 10 (lower for faster iteration), (3) max_tokens = 4096 (lower), (4) Qdrant MCP uses QDRANT_LOCAL_PATH instead of QDRANT_URL — no separate Qdrant server needed, data persists to filesystem directory. (5) Comment header emphasizes this is for development and explains the local Qdrant path mode. Same system prompt as production. | Restrictions: The Qdrant MCP env must use QDRANT_LOCAL_PATH not QDRANT_URL. This is the key differentiator for dev convenience. | Success: TOML parses. Uses OpenAI. Uses QDRANT_LOCAL_PATH. turn_depth is 10._

### T3d: Create Change Audit Agent Configs

- **Purpose:** Agent that detects changes via CloudTrail and diffs against KB baseline.
- **Files created:** `examples/mcp-servers/aws/aws-change-audit-agent.toml`, `examples/mcp-servers/aws/aws-change-audit-agent-openai.toml`
- _Leverage: Spec section "Agent 4: Change Audit Agent", discovery agent as structural pattern, data model "Type 2: Change Record" and "Type 4: CloudTrail Event Summary" for document formats_
- _Requirements: R1, R2, R3, R5_
- _Prompt: Role: Aura TOML configuration developer building an AWS change detection agent | Task: Create two config files for the change audit agent: (1) `examples/mcp-servers/aws/aws-change-audit-agent.toml` (Bedrock) and (2) `examples/mcp-servers/aws/aws-change-audit-agent-openai.toml` (OpenAI variant). The change audit agent runs on a schedule (every 1-4 hours) and detects what changed in the AWS environment. Config: `[llm]` Bedrock Claude Sonnet 4 (OpenAI gpt-4o for variant), `[agent]` temperature 0.2, turn_depth 10. System prompt must instruct the agent to: (A) Query CloudTrail for recent mutating API calls using `call_aws` with `aws cloudtrail lookup-events --start-time <since-last-audit>`, filtering for Create/Update/Delete/Put/Modify actions. (B) For each significant event, search the knowledge base with `qdrant-find` in collection `aws_resources` to get context on the affected resource. (C) Compare current live state (via `call_aws`) against stored KB snapshot. (D) Rate each change as HIGH/MEDIUM/LOW risk based on: security group changes=HIGH, IAM changes=HIGH, deployments=MEDIUM, scaling=LOW, tag changes=LOW. (E) Store change records using `qdrant-store` in collection `aws_changes` following the [CHANGE] document template from the spec's data model section. (F) Store a [CLOUDTRAIL] period summary document. (G) Report findings to the user with the risk-rated format shown in the spec under "Agent 4: Change Audit Agent > Example output". Both MCP servers: aws_api (READ_OPERATIONS_ONLY=true) and qdrant. Context array should mention the agent has access to both `aws_resources` (baseline) and `aws_changes` (change history) collections. Follow inline comment style from existing examples. | Restrictions: TOML only. Same MCP server config pattern as discovery agent. System prompt must include the specific [CHANGE] document format template and risk rating criteria. The OpenAI variant should differ ONLY in the `[llm]` section. | Success: Both TOMLs parse. System prompts include CloudTrail query methodology, risk rating criteria, [CHANGE] document format, and period summary format._

### T3e: Create Incident Response Agent Configs

- **Purpose:** Real-time triage agent used during active incidents.
- **Files created:** `examples/mcp-servers/aws/aws-incident-response-agent.toml`, `examples/mcp-servers/aws/aws-incident-response-agent-openai.toml`
- _Leverage: Spec section "Agent 2: Incident Response Agent" including the example interaction_
- _Requirements: R1, R2, R3, R5_
- _Prompt: Role: Aura TOML configuration developer building an incident response triage agent | Task: Create two config files: (1) `examples/mcp-servers/aws/aws-incident-response-agent.toml` (Bedrock) and (2) `examples/mcp-servers/aws/aws-incident-response-agent-openai.toml` (OpenAI). The incident response agent is triggered during active incidents to answer: "What's broken? What changed? What's the blast radius?" Config: `[llm]` Bedrock Claude Sonnet 4, `[agent]` temperature 0.2, turn_depth 20 (deep investigation), max_tokens 8192. System prompt must instruct the agent to follow this triage methodology: (1) TRIAGE — Check CloudWatch alarms in ALARM state via `call_aws aws cloudwatch describe-alarms --state-value ALARM`. (2) CONTEXT — Search KB with `qdrant-find` in `aws_resources` for the affected service to get its relationships, dependencies, configuration, and ownership tags. (3) CHANGE CORRELATION — Query CloudTrail for recent changes in the blast radius: `call_aws aws cloudtrail lookup-events --start-time <4h-ago>`. Also search `aws_changes` collection for recent change records. (4) HEALTH CHECK — Check current status of all resources in the dependency chain (ECS service status, target group health, RDS status). (5) TIMELINE — Build a chronological event sequence (deploy → alarm → impact). (6) SUGGEST — Recommend next actions based on findings (rollback, scale up, contact team). Output format: "What's broken → What changed → What's affected → Suggested actions". Always flag ownership tags so the user knows who to escalate to. Never make changes — read-only only. Include the example interaction from the spec (checkout-svc 500s scenario) as a comment block showing expected behavior. Both MCP servers configured. Context array mentions access to `aws_resources`, `aws_changes`, and `aws_postmortems` collections. | Restrictions: TOML only. turn_depth MUST be 20 (highest of any agent — incidents need deep investigation). OpenAI variant differs only in `[llm]`. | Success: Both TOMLs parse. System prompt includes the 6-step triage methodology. turn_depth is 20._

### T3f: Create Post-Mortem Agent Configs

- **Purpose:** Assists SREs in constructing post-mortem documents after incidents.
- **Files created:** `examples/mcp-servers/aws/aws-postmortem-agent.toml`, `examples/mcp-servers/aws/aws-postmortem-agent-openai.toml`
- _Leverage: Spec section "Agent 3: Post-Mortem Agent", data model "Type 6: Post-Mortem Summary" for document format_
- _Requirements: R1, R2, R3, R5_
- _Prompt: Role: Aura TOML configuration developer building a post-mortem analysis agent | Task: Create two config files: (1) `examples/mcp-servers/aws/aws-postmortem-agent.toml` (Bedrock) and (2) `examples/mcp-servers/aws/aws-postmortem-agent-openai.toml` (OpenAI). The post-mortem agent helps SREs construct post-mortem documents after an incident. Config: `[llm]` Bedrock Claude Sonnet 4, `[agent]` temperature 0.4 (slightly higher for analytical writing), turn_depth 15, max_tokens 8192. System prompt must instruct the agent to: (1) Ask the user for incident time window (start/end) and affected services. (2) TIMELINE — Reconstruct chronology from CloudTrail events, ECS deployment events, alarm state changes via `call_aws`. (3) IMPACT — Use KB relationships from `qdrant-find` in `aws_resources` to determine blast radius and affected services/teams. (4) CONTRIBUTING FACTORS — Identify conditions that enabled the incident: missing circuit breaker? No DLQ? Drift from IaC? Missing alerts? Check resource configs in KB. (5) DETECTION GAP — Calculate time between failure start and first alarm. (6) RESILIENCE AUDIT — Check if affected resources had Multi-AZ, backups, circuit breakers, DLQs via KB data. (7) ACTION ITEMS — Suggest preventive measures. (8) Store the post-mortem summary using `qdrant-store` in collection `aws_postmortems` following the [POSTMORTEM] document format from the spec's data model section. Also search `aws_postmortems` for "has this service failed before?" to include historical context. Use blameless language — focus on systems, not people. Both MCP servers configured. Context array mentions access to all 4 collections. | Restrictions: TOML only. Must include the [POSTMORTEM] document template in the system prompt. Blameless language requirement must be explicit in the prompt. OpenAI variant differs only in `[llm]`. | Success: Both TOMLs parse. System prompt includes post-mortem template, blameless language instruction, and historical incident search._

### T3g: Create Capacity Planning Agent Configs

- **Purpose:** Identifies resources approaching limits, underutilization, and growth trends.
- **Files created:** `examples/mcp-servers/aws/aws-capacity-planning-agent.toml`, `examples/mcp-servers/aws/aws-capacity-planning-agent-openai.toml`
- _Leverage: Spec section "Agent 5: Capacity Planning Agent", data collection section "Capacity & Limits"_
- _Requirements: R1, R2_
- _Prompt: Role: Aura TOML configuration developer building a capacity planning agent | Task: Create two config files: (1) `examples/mcp-servers/aws/aws-capacity-planning-agent.toml` (Bedrock) and (2) `examples/mcp-servers/aws/aws-capacity-planning-agent-openai.toml` (OpenAI). Config: `[llm]` Bedrock Claude Sonnet 4, `[agent]` temperature 0.3, turn_depth 10. System prompt must instruct the agent to: (1) QUOTA ANALYSIS — Check Service Quotas against current usage via `call_aws aws service-quotas list-service-quotas --service-code <svc>` for key services (EC2, ECS, Lambda, RDS, VPC). (2) SCALING HEADROOM — Evaluate ECS/ASG min/max vs current desired count. How much room to scale? (3) STORAGE GROWTH — RDS allocated vs max, DynamoDB consumed vs provisioned capacity. (4) UNDERUTILIZATION — Flag EC2 instances with potential low CPU (check instance types vs workload from KB tags), over-provisioned RDS, unused EIPs, idle NAT Gateways. (5) RECOMMENDATIONS — Right-sizing suggestions, reserved instance candidates, services approaching limits. Search KB first via `qdrant-find` in `aws_resources` for resource context before making live queries. Report findings in a structured format: quota name, current usage, limit, percentage used, recommendation. Both MCP servers: aws_api (read-only) and qdrant (read only for this agent — no writes). | Restrictions: TOML only. This agent reads from KB but does not write to it. OpenAI variant differs only in `[llm]`. | Success: Both TOMLs parse. System prompt covers quotas, scaling, storage, underutilization, and recommendations._

### T3h: Create Query-Only Agent Configs

- **Purpose:** Lightweight agent that only queries the existing KB — no AWS API access.
- **Files created:** `examples/rag/aws-knowledge-base/aws-kb-query-agent.toml`, `examples/rag/aws-knowledge-base/aws-kb-query-agent-openai.toml`
- _Leverage: Spec section "Query-Only Config: aws-kb-query-agent.toml"_
- _Requirements: R2, R3_
- _Prompt: Role: Aura TOML configuration developer | Task: Create two config files: (1) `examples/rag/aws-knowledge-base/aws-kb-query-agent.toml` (Bedrock) and (2) `examples/rag/aws-knowledge-base/aws-kb-query-agent-openai.toml` (OpenAI). The query agent connects ONLY to Qdrant (no AWS API MCP server). Config: `[llm]` Bedrock Claude Sonnet 4, `[agent]` temperature 0.5, turn_depth 5. Read the full config from the spec under "Query-Only Config". System prompt must instruct the agent to: answer questions by searching KB with `qdrant-find`, always cite discovery timestamps, suggest running discovery agent if data is missing, search multiple times with different queries for relationship tracing, be clear about what it knows vs what may have changed. Only one MCP server: qdrant. No aws_api server. Comment header must explain this is for querying a previously-populated KB and list the discovery agent as a prerequisite. | Restrictions: TOML only. Must NOT include aws_api MCP server. This agent has no AWS access. OpenAI variant differs only in `[llm]`. | Success: Both TOMLs parse. Only qdrant MCP server configured. No aws_api. System prompt references qdrant-find only._

---

## WAVE 4 — Documentation (run in parallel, after Wave 3)

### T4a: Write AWS Agents README

- **Purpose:** Setup guide, prerequisites, and usage for all AWS agent configs.
- **Files created:** `examples/mcp-servers/aws/README.md`
- _Leverage: Spec sections on architecture, agent ecosystem, runtime model. Existing README pattern from `examples/mcp-servers/README.md`_
- _Requirements: All_
- _Prompt: Role: Technical writer creating SRE-focused documentation for the aura AWS agent ecosystem | Task: Create `examples/mcp-servers/aws/README.md`. This is the primary user-facing doc. It must be written for SREs with zero AI experience — no jargon (no turn_depth, temperature, embeddings, MCP). Structure: (1) One-paragraph overview of what this does. (2) Quick Start — 5 commands from clone to first discovery. (3) Prerequisites — AWS credentials, Docker, what IAM permissions are needed (link to iam/ templates). (4) Agent Inventory table — all configs in this directory with one-line description and when to use each. (5) Gradual Adoption Path — Week 1 through Month 3 ramp. (6) How It Works — simple diagram of agent → AWS + Qdrant → knowledge base. (7) Usage Examples — curl commands for preflight, discovery, asking questions. (8) Configuration — how to switch between Bedrock and OpenAI, how to use dev mode. (9) Troubleshooting — top 5 issues with SYMPTOM/CHECK/FIX format. (10) Cost Estimate — link to cost doc. Follow the tone and structure of `examples/mcp-servers/README.md` but adapt for the AWS use case. | Restrictions: No AI jargon. Write for an SRE who has never used an AI agent. Use "knowledge base" not "vector store". Use "agent" not "LLM". Use "configuration file" not "TOML config". Keep it under 300 lines. | Success: A mid-level SRE can read this and go from zero to running the discovery agent without asking anyone for help._

### T4b: Write Knowledge Base README

- **Purpose:** How to use the query-only agent after discovery has populated the KB.
- **Files created:** `examples/rag/aws-knowledge-base/README.md`
- _Requirements: R2, R3_
- _Prompt: Role: Technical writer | Task: Create `examples/rag/aws-knowledge-base/README.md`. Short doc explaining: (1) What this is — an agent that queries previously-discovered AWS infrastructure data. (2) Prerequisite — you must run the discovery agent first to populate the knowledge base. (3) Quick Start — 3 commands to start and query. (4) Example questions to ask. (5) How data freshness works (timestamps, when to re-scan). Keep it under 80 lines. No AI jargon. | Restrictions: Keep it short and practical. | Success: Explains the concept and gets someone querying in under 2 minutes of reading._

### T4c: Write Quick-Start Guide

- **Purpose:** The 5-minute path from zero to first value.
- **Files created:** `docs/quick-start.md`
- _Leverage: Spec section "Adoption & Usability > One-Command Quick Start"_
- _Prompt: Role: Technical writer creating a quick-start guide for SREs | Task: Create `docs/quick-start.md` — the fastest path from "I just heard about this" to "I can see my AWS environment." Structure: (1) What You'll Get — one sentence. (2) Prerequisites — AWS credentials, Docker. (3) Step 1: Clone. Step 2: Set credentials. Step 3: Start services. Step 4: Run preflight. Step 5: Run discovery. Step 6: Ask a question. Each step is a single command with expected output. (4) What Next — link to gradual adoption path in the AWS README. Total: under 60 lines. Every command must be copy-pasteable. | Restrictions: Absolute minimum content. No background, no architecture, no explanation of how it works. Just steps. | Success: Someone can follow this in 5 minutes and see their first discovery results._

### T4d: Write Troubleshooting Runbook

- **Purpose:** SYMPTOM/CHECK/FIX format troubleshooting for common issues.
- **Files created:** `docs/troubleshooting.md`
- _Leverage: Spec section "Adoption & Usability > Troubleshooting Runbook"_
- _Prompt: Role: SRE writing a troubleshooting runbook | Task: Create `docs/troubleshooting.md` in the standard runbook format that SREs are used to. Each entry must follow SYMPTOM → CHECK → FIX structure. Cover at minimum: (1) AWS credentials not configured, (2) Qdrant not reachable, (3) Discovery misses resources, (4) Agent responses are slow, (5) Knowledge base returns stale results, (6) Agent says rate limited on AWS APIs, (7) Docker compose fails to start, (8) MCP server connection failed, (9) Agent doesn't store results in Qdrant, (10) Preflight fails on Qdrant write test. Each entry should have 1-2 CHECK commands and 1-2 FIX commands. Keep it practical — commands they can run, not explanations of architecture. | Restrictions: No AI jargon. Runbook format only. Every CHECK and FIX must be a runnable command or concrete action. | Success: An on-call SRE can find their issue and fix it without reading any other documentation._

### T4e: Write Cost Estimate Document

- **Purpose:** Answer "what will this cost?" for managers approving the project.
- **Files created:** `docs/cost-estimate.md`
- _Leverage: Spec section "Adoption & Usability > Cost Transparency"_
- _Prompt: Role: Technical writer creating a cost estimate for engineering managers | Task: Create `docs/cost-estimate.md` breaking down monthly costs by component and environment size. Include tables for: (1) Small environment (<100 resources) — estimated $50-80/month. (2) Medium environment (100-500 resources) — estimated $100-200/month. (3) Large environment (500+ resources) — estimated $200-400/month. Break down by: Bedrock LLM costs (per scan, per audit, per incident), Qdrant hosting (self-hosted = free, managed = $25-100), AWS API calls (negligible). Include cost reduction tips: weekly vs daily scans, 4-hour vs hourly audits, Bedrock vs OpenAI comparison. Include a "Quick Answer" at the top: "For a typical medium AWS environment: ~$100-200/month." | Restrictions: Be honest about estimates — these are approximations. Note that costs depend on environment size and scan frequency. No marketing language. | Success: An engineering manager can read the first 3 lines and know the ballpark cost._

---

## WAVE 5 — Finalize (sequential, after Wave 4)

### T5a: Update Examples Inventory

- **Purpose:** Add all new AWS configs to the examples/CLAUDE.md inventory.
- **Files modified:** `examples/CLAUDE.md`, `examples/mcp-servers/README.md`
- _Leverage: Existing inventory format in `examples/CLAUDE.md`_
- _Prompt: Role: Documentation maintainer for the aura-examples project | Task: Update two files to include the new AWS agent configs: (1) `examples/CLAUDE.md` — Add an "AWS Infrastructure Discovery" section under "MCP Servers Inventory" following the exact table format used for Datadog, OpenTelemetry, etc. List all TOML files in `examples/mcp-servers/aws/` with their tier (Preflight/Basic/Use Case), provider (Bedrock/OpenAI), and one-line description. Also add the `examples/rag/aws-knowledge-base/` configs under a new "RAG Examples Inventory" section. (2) `examples/mcp-servers/README.md` — Add an AWS entry to the "Which Platform Should I Start With?" table and any relevant sections. Read both files first to match existing format exactly. | Restrictions: Match existing format precisely. Do not modify entries for other platforms. | Success: New configs appear in the inventory. Format matches existing entries._

### T5b: Validate All TOML Configs

- **Purpose:** Confirm every TOML file parses without error.
- **Files:** All `.toml` files in `examples/mcp-servers/aws/` and `examples/rag/aws-knowledge-base/`
- _Prompt: Role: QA engineer validating configuration files | Task: Run TOML validation on every config file created in this project. For each file: `python3 -c "import tomllib; c = tomllib.load(open('<path>', 'rb')); print(f'OK: <path> — sections: {list(c.keys())}')"`. Also verify structural requirements: every config has `[llm]` with provider and model, `[agent]` with name and system_prompt, appropriate `[mcp.servers.*]` sections. Report any parse errors or missing required sections. List all configs validated and their status. | Restrictions: Do not fix errors — just report them. Fixes should be done by re-running the task that created the broken file. | Success: All TOML files parse. All have required sections. Zero errors._

### T5c: End-to-End Test

- **Purpose:** Verify the full flow works: preflight → discovery → query across sessions.
- **Files:** None created — test execution only.
- _Prompt: Role: QA engineer running end-to-end validation of the AWS discovery agent stack | Task: Run the full end-to-end test sequence if aura and Qdrant are available. (1) Start Qdrant: `docker run -d -p 6333:6333 qdrant/qdrant`. (2) Start aura with preflight config. Send "run preflight checks" message. Verify MCP tools are listed, AWS credentials validated, Qdrant read/write confirmed. (3) Stop aura, restart with discovery agent dev config. Send "discover S3 buckets and store them in the knowledge base." Verify agent uses call_aws and qdrant-store. (4) Stop aura, restart with query-only agent config. Send "what S3 buckets exist?" Verify agent uses qdrant-find and returns previously stored data. (5) Verify no secret values in any qdrant-store calls. Report: which steps passed, which failed, any issues found. If aura binary is not available, document the test plan for manual execution later. | Restrictions: This is a test — do not modify any config files. If any step fails, document the failure clearly. | Success: Preflight validates. Discovery stores data. Query retrieves it. No secrets stored. Full lifecycle confirmed._
