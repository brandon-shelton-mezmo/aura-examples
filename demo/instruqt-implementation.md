# Instruqt Implementation Guide — API Reference & Status

**Created:** 2026-03-23
**Purpose:** Document Instruqt API patterns, team capabilities, and blockers for the Aura demo track implementation.

---

## 1. Team Status

| Field | Value |
|-------|-------|
| Team ID | `neehajbracrp` |
| Team Slug | `mezmo` |
| API Endpoint | `https://play.instruqt.com/graphql` |
| Auth | `Authorization: Bearer team-e516de8c...` |
| Existing Tracks | 28 (mostly starter/template tracks, no Aura tracks yet) |

## 2. Architecture: Hybrid Dual-Account Model

### Current State (Verified 2026-03-24)

| Component | Status | Details |
|-----------|--------|---------|
| `aws_accounts` feature | **Enabled** | Instruqt provisions a dedicated AWS account per sandbox |
| Managed account provisioning | **Working** | Verified: account `536697228052`, IAM user created |
| AWS Console tab | **Working** | `cloud-client` container with service tab on port 80 |
| Bedrock in managed accounts | **Blocked** | Org-level SCP explicitly denies `bedrock:InvokeModel`. Requires `cloud_ai_services` flag. |
| `cloud_ai_services` flag | **false** | Requested from Instruqt — waiting for enablement |

### Architecture: Split Credentials

Until `cloud_ai_services` is enabled, we use two AWS accounts:

```
┌─────────────────────────────────────────────────────┐
│  INSTRUQT MANAGED ACCOUNT (per sandbox, isolated)   │
│  Account: 536697228052 (varies per sandbox)         │
│                                                     │
│  Used for: ALL infrastructure                       │
│  - Terraform provisions Bella Vista (VPC, ECS, RDS) │
│  - Aura discovers resources via AWS API MCP         │
│  - AWS Console tab for learner browsing             │
│  - CloudTrail, CloudWatch, IAM — all here           │
│                                                     │
│  Credentials: Auto-injected by Instruqt             │
│  Isolation: Dedicated account per sandbox           │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  MEZMO BEDROCK ACCOUNT (shared, LLM calls only)     │
│  Account: (your Bedrock-capable account)            │
│                                                     │
│  Used for: ONLY Bedrock LLM inference               │
│  - Aura agents call bedrock-runtime:InvokeModel     │
│  - No infrastructure, no discovery, no state        │
│  - Read-only from aura's perspective                 │
│                                                     │
│  Credentials: Instruqt team secrets                 │
│  Isolation: Stateless — LLM calls don't create      │
│  resources, so sharing is safe                      │
└─────────────────────────────────────────────────────┘
```

**Why sharing the Bedrock account is safe:** Bedrock `InvokeModel` is stateless. It sends a prompt, gets a response. No resources created, no state stored, no cross-sandbox interference. Ten concurrent sandboxes making Bedrock calls is no different from ten users calling the same API.

### How It Wires Up in Docker Compose

```yaml
# MCP servers → Instruqt managed account (infrastructure discovery)
x-discovery-credentials: &discovery-creds
  AWS_ACCESS_KEY_ID: ${INSTRUQT_AWS_ACCESS_KEY_ID}
  AWS_SECRET_ACCESS_KEY: ${INSTRUQT_AWS_SECRET_ACCESS_KEY}
  AWS_REGION: us-east-1

# Aura agents → Mezmo Bedrock account (LLM calls only)
x-bedrock-credentials: &bedrock-creds
  AWS_ACCESS_KEY_ID: ${BEDROCK_AWS_ACCESS_KEY_ID}
  AWS_SECRET_ACCESS_KEY: ${BEDROCK_AWS_SECRET_ACCESS_KEY}
  AWS_REGION: us-east-1

services:
  # MCP servers use INSTRUQT managed account creds
  aws-mcp:
    environment:
      <<: *discovery-creds
  qdrant-mcp:       # discover_and_store uses boto3
    environment:
      <<: *discovery-creds

  # Aura agents use BEDROCK account creds (for [llm] provider = "bedrock")
  orchestrator:
    environment:
      <<: *bedrock-creds
      # MCP URLs still point to the MCP containers (HTTP, no AWS creds needed)
      AWS_MCP_URL: http://aws-mcp:8091/mcp
      QDRANT_MCP_URL: http://qdrant-mcp:8000/mcp
```

The aura binary uses `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` for Bedrock calls. The MCP servers use their own credentials for AWS API calls. Different containers, different env vars, clean separation.

### Setup Script — Credential Bridging

```bash
#!/bin/bash
# Instruqt injects managed account creds on cloud-client.
# We need them on the aura-host VM for Terraform + MCP servers.
# Bedrock creds come from team secrets.

# 1. Get Instruqt managed account creds (from cloud-client or env)
INSTRUQT_AWS_ACCESS_KEY_ID="${INSTRUQT_AWS_ACCOUNT_TEST_AWS_AWS_ACCESS_KEY_ID}"
INSTRUQT_AWS_SECRET_ACCESS_KEY="${INSTRUQT_AWS_ACCOUNT_TEST_AWS_AWS_SECRET_ACCESS_KEY}"

# 2. Bedrock creds from team secrets (injected by Instruqt)
BEDROCK_AWS_ACCESS_KEY_ID="${BEDROCK_ACCESS_KEY_ID}"      # team secret
BEDROCK_AWS_SECRET_ACCESS_KEY="${BEDROCK_SECRET_ACCESS_KEY}"  # team secret

# 3. Write both to env file for Docker Compose
cat > /opt/aura/.env << EOF
# Instruqt managed account — for infrastructure discovery
INSTRUQT_AWS_ACCESS_KEY_ID=${INSTRUQT_AWS_ACCESS_KEY_ID}
INSTRUQT_AWS_SECRET_ACCESS_KEY=${INSTRUQT_AWS_SECRET_ACCESS_KEY}
# Mezmo Bedrock account — for LLM calls only
BEDROCK_AWS_ACCESS_KEY_ID=${BEDROCK_AWS_ACCESS_KEY_ID}
BEDROCK_AWS_SECRET_ACCESS_KEY=${BEDROCK_AWS_SECRET_ACCESS_KEY}
AWS_REGION=us-east-1
EOF

# 4. Terraform uses the managed account (for infrastructure)
export AWS_ACCESS_KEY_ID="$INSTRUQT_AWS_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$INSTRUQT_AWS_SECRET_ACCESS_KEY"
terraform -chdir=/opt/aura/terraform apply -auto-approve
```

### When `cloud_ai_services` Gets Enabled

Once Instruqt enables `cloud_ai_services`, the SCP deny on Bedrock is removed. Then:
1. Delete the Bedrock team secrets
2. Change Docker Compose: all containers use the same Instruqt creds
3. Remove the `x-bedrock-credentials` anchor
4. Everything simplifies to one credential set

This is a ~5 minute config change. No architecture redesign needed.

### Secrets to Create Now

| Secret Name | Value | Purpose |
|-------------|-------|---------|
| `BEDROCK_ACCESS_KEY_ID` | IAM access key from Bedrock-capable account | LLM calls |
| `BEDROCK_SECRET_ACCESS_KEY` | IAM secret key from Bedrock-capable account | LLM calls |

The managed account credentials are auto-injected by Instruqt — no secrets needed for those.

### Anti-Pattern Acknowledgment

Splitting LLM credentials from infrastructure credentials is not ideal. It means:
- Two sets of credentials to manage
- The Bedrock account is shared across all sandboxes (safe for stateless calls, but still shared)
- Setup script complexity increases

**This is a temporary workaround** until `cloud_ai_services` is enabled. The implementation doc and spec should both note this as a known compromise with a clear upgrade path.

---

## 3. Per-Sandbox Isolation (Managed Accounts)

With Instruqt managed AWS accounts now working, the original spec's isolation model applies:

| Layer | Isolation | How |
|-------|-----------|-----|
| AWS Infrastructure | **Dedicated account per sandbox** | Instruqt provisions a fresh account. Terraform creates resources in it. Account destroyed on cleanup. |
| Qdrant KB | **Per-VM** | Runs on sandbox VM localhost. No network exposure. |
| Aura Agents | **Per-VM** | All agents on sandbox VM. Localhost only. |
| Bedrock LLM | **Shared account (temporary)** | Stateless calls. No cross-sandbox interference. |
| Bella Vista App | **Per-sandbox account** | ECS tasks in the managed account. |

**No prefix gymnastics needed.** Each sandbox gets its own AWS account, so `bella-vista-vpc` doesn't collide — it's in a different account entirely. This is the cleanest isolation model.

---

## 4. Instruqt Secrets — Bedrock Credentials

Only two secrets needed — the Bedrock-capable account credentials. Infrastructure credentials are auto-injected by Instruqt's managed accounts.

### Secrets to Create

| Secret Name | Value | Purpose |
|-------------|-------|---------|
| `BEDROCK_ACCESS_KEY_ID` | IAM access key from Bedrock-capable account | Aura agent LLM calls |
| `BEDROCK_SECRET_ACCESS_KEY` | IAM secret key from Bedrock-capable account | Aura agent LLM calls |

### API Commands to Create Secrets

```bash
INSTRUQT_TOKEN="team-e516de8c..."

# Create BEDROCK_ACCESS_KEY_ID
ACCESS_KEY_B64=$(echo -n "AKIA..." | base64)
curl -s -X POST https://play.instruqt.com/graphql \
  -H "Authorization: Bearer $INSTRUQT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"mutation { upsertTeamSecret(teamSlug: \\\"mezmo\\\", name: \\\"BEDROCK_ACCESS_KEY_ID\\\", description: \\\"Bedrock account access key for Aura LLM calls\\\", secret: \\\"${ACCESS_KEY_B64}\\\") { name } }\"}"

# Create BEDROCK_SECRET_ACCESS_KEY
SECRET_KEY_B64=$(echo -n "wJal..." | base64)
curl -s -X POST https://play.instruqt.com/graphql \
  -H "Authorization: Bearer $INSTRUQT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"mutation { upsertTeamSecret(teamSlug: \\\"mezmo\\\", name: \\\"BEDROCK_SECRET_ACCESS_KEY\\\", description: \\\"Bedrock account secret key for Aura LLM calls\\\", secret: \\\"${SECRET_KEY_B64}\\\") { name } }\"}"
```

### Track Config — Reference Secrets

```yaml
secrets:
  - name: BEDROCK_ACCESS_KEY_ID
  - name: BEDROCK_SECRET_ACCESS_KEY
```

### Lifecycle Script — Credential Bridging

```bash
#!/bin/bash
# INSTRUQT managed account creds — auto-injected on cloud-client
# Access via INSTRUQT_AWS_ACCOUNT_{NAME}_{CREDENTIAL} pattern
INFRA_KEY="${INSTRUQT_AWS_ACCOUNT_BELLA_VISTA_AWS_AWS_ACCESS_KEY_ID}"
INFRA_SECRET="${INSTRUQT_AWS_ACCOUNT_BELLA_VISTA_AWS_AWS_SECRET_ACCESS_KEY}"

# BEDROCK creds — from team secrets (available in lifecycle scripts)
BEDROCK_KEY="${BEDROCK_ACCESS_KEY_ID}"
BEDROCK_SECRET="${BEDROCK_SECRET_ACCESS_KEY}"

# Write env file for Docker Compose (two credential sets)
cat > /opt/aura/.env << EOF
# Instruqt managed account — MCP servers use these for discovery
INSTRUQT_AWS_ACCESS_KEY_ID=${INFRA_KEY}
INSTRUQT_AWS_SECRET_ACCESS_KEY=${INFRA_SECRET}
# Bedrock account — Aura agents use these for LLM calls
BEDROCK_AWS_ACCESS_KEY_ID=${BEDROCK_KEY}
BEDROCK_AWS_SECRET_ACCESS_KEY=${BEDROCK_SECRET}
AWS_REGION=us-east-1
EOF

# Terraform uses managed account creds (infrastructure)
export AWS_ACCESS_KEY_ID="$INFRA_KEY"
export AWS_SECRET_ACCESS_KEY="$INFRA_SECRET"
export AWS_REGION=us-east-1
```

### Upgrade Path (When `cloud_ai_services` Enabled)

Once Instruqt enables `cloud_ai_services` and removes the Bedrock SCP deny:
1. Delete the two team secrets (`BEDROCK_ACCESS_KEY_ID`, `BEDROCK_SECRET_ACCESS_KEY`)
2. Remove `secrets` from track config
3. Change Docker Compose: all containers use the same Instruqt managed account creds
4. Simplify setup script: one credential set instead of two
5. ~5 minute change, no architecture redesign

---

## 5. Team Feature Flags (Current State)

| Feature | Enabled | Relevance to Demo |
|---------|---------|-------------------|
| `containers` | true | Can use container-based sandbox hosts |
| `virtual_machines` | true | Can use VM-based sandbox hosts (needed for Docker Compose) |
| `custom_machine_type` | true | Can specify `n1-standard-4` or custom CPU/memory |
| `hot_start` | true | Can pre-warm sandboxes for faster startup |
| `global_sandboxes` | true | Sandboxes can be shared globally |
| `embedded` | true | Can embed tracks in external sites |
| `max_tracks` | 0 (unlimited) | No limit on track count |
| `max_timelimit` | 0 (unlimited) | No limit on track duration |
| `max_hot_start_pool_size_always_on` | 20 | Can keep 20 sandboxes warm |
| `max_hot_start_pool_size_scheduled` | 200 | Can schedule up to 200 warm sandboxes |
| **`aws_accounts`** | **false** | **BLOCKER — cannot provision AWS sandbox accounts** |
| **`cloud_ai_services`** | **false** | **BLOCKER — may gate Bedrock access** |
| `gcp_projects` | false | Not needed |
| `azure_subscriptions` | false | Not needed |
| `gpus_enabled` | false | Not needed |
| `pauseable_tracks` | false | Nice-to-have for long demos |
| `sandbox_isolation` | false | May affect per-sandbox isolation guarantees |

---

## 6. API Operations Reference

### 4.1 Track Lifecycle

| Operation | Mutation/Query | Key Fields |
|-----------|---------------|------------|
| **Create track** | `createTrack(track: TrackInput)` | slug, title, description, challenges[], config, scripts[], timelimit, skipping_enabled |
| **Update track** | `updateTrack(track: TrackInput)` | Same as create (include id) |
| **Update complete track** | `updateCompleteTrack(track: TrackInput)` | Atomic update of entire track + challenges |
| **Delete track** | `deleteTrack(trackID: ID)` | |
| **Get track** | `track(trackID: ID)` or `track(trackSlug, teamSlug)` | |
| **Get track config** | `trackConfig(trackID: ID)` | Returns sandbox config (VMs, containers, AWS accounts) |
| **List tracks** | `tracks(teamSlug: String)` | |
| **Start track** | `startTrack(trackID: ID)` | Spins up a sandbox |
| **Stop track** | `stopTrack(trackID: ID)` | Tears down sandbox |

### 4.2 Challenge Lifecycle

| Operation | Mutation/Query | Key Fields |
|-----------|---------------|------------|
| **Create challenge** | `createChallenge(challenge: ChallengeInput)` | slug, title, assignment (markdown), tabs[], scripts[], timelimit |
| **Update challenge** | `updateChallenge(challenge: ChallengeInput)` | Same (include id) |
| **Delete challenge** | `deleteChallenge(challengeID: ID)` | |
| **Reorder challenges** | `updateChallengeIndexes(trackID, challenges[])` | |
| **Get challenges** | `challenges(trackID: ID)` | |

### 4.3 Sandbox Config

The track `config` field defines the sandbox resources:

```graphql
config: {
  containers: [ContainerConfigInput]
  virtualmachines: [VirtualMachineConfigInput]
  aws_accounts: [AwsAccountConfigInput]
  gcp_projects: [GcpProjectConfigInput]
  azure_subscriptions: [AzureSubscriptionConfigInput]
  secrets: [SecretConfigInput]
}
```

#### Container Config
```graphql
{
  name: String          # Hostname (e.g., "cloud-client")
  image: String         # Docker image (e.g., "gcr.io/instruqt/cloud-client")
  ports: [Int]          # Exposed ports
  shell: String         # Default shell
  environment: [EnvironmentInput]  # Env vars
  memory: Int           # Memory limit (MB)
}
```

#### Virtual Machine Config
```graphql
{
  name: String          # Hostname (e.g., "aura-host")
  image: String         # VM image (e.g., "instruqt/docker-2010")
  machine_type: String  # GCE machine type (e.g., "n1-standard-4")
  cpus: Int             # Override CPU count
  memory: Int           # Override memory (MB)
  shell: String         # Default shell
  environment: [EnvironmentInput]
  allow_external_ingress: [String]  # Firewall rules
  nested_virtualization: Boolean
}
```

#### AWS Account Config
```graphql
{
  name: String              # Account identifier
  iam_policy: String        # JSON — learner IAM policy
  admin_iam_policy: String  # JSON — admin policy (for setup scripts)
  managed_policies: [String]
  admin_managed_policies: [String]
  scp_policy: String        # JSON — service control policy
  services: [String]        # Allowed AWS services (e.g., ["ec2", "s3", "bedrock"])
  regions: [String]         # Allowed regions (e.g., ["us-east-1"])
  expose_to_user: Boolean   # Show credentials to learner
}
```

### 4.4 Tabs

```graphql
{
  title: String                  # Tab display name
  type: ChallengeTabType         # terminal | service | code | website | external | browser | feedback
  hostname: String               # Which sandbox host this tab connects to
  port: Int                      # Port for service tabs
  path: String                   # URL path for service tabs
  protocol: ChallengeTabProtocol # http | https
  url: String                    # For external tabs
  workdir: String                # Working directory for terminal tabs
  cmd: String                    # Command to run in terminal
}
```

**Tab types for our demo:**
| Tab | Type | Config |
|-----|------|--------|
| Terminal | `terminal` | `hostname: "aura-host"` |
| AWS Console | `service` | `hostname: "cloud-client", port: 80, path: "/"` |
| Bella Vista App | `external` or `service` | Dynamic URL from ALB — set via `setSandboxVariable` |
| Editor | `code` | `hostname: "aura-host", path: "/opt/aura/configs"` |

### 4.5 Scripts

**Track-level scripts** (run once when sandbox starts/stops):
```graphql
{
  host: String      # Which host to run on
  action: String    # "setup" or "cleanup"
  contents: String  # Base64-encoded bash script
}
```

**Challenge-level scripts** (run per challenge):
```graphql
{
  host: String      # Which host to run on
  action: String    # "setup", "check", "cleanup", or "solve"
  contents: String  # Base64-encoded bash script
}
```

**Script actions:**
| Action | When It Runs | Purpose |
|--------|-------------|---------|
| `setup` | When challenge starts | Prepare the environment for this challenge |
| `check` | When learner clicks "Check" | Validate challenge completion |
| `cleanup` | After challenge completes | Clean up before next challenge |
| `solve` | (dev/test only) | Auto-solve for testing |

### 4.6 Invites

```graphql
createTrackInvite(invite: TrackInviteInput) {
  publicTitle: String!        # Displayed to invitees
  publicDescription: String
  trackIDs: [String]          # Which tracks to include
  inviteLimit: Int            # Max number of participants
  playTTL: Int                # Sandbox lifetime (seconds)
  expiresAt: Time             # Invite expiration
  allowAnonymous: Boolean     # Allow without login
  type: TrackInviteType       # self_paced | live_event
  instructorToolsEnabled: Boolean
}
```

### 4.7 Sandbox Runtime

| Operation | Mutation | Purpose |
|-----------|----------|---------|
| `setSandboxVariable(key, value, hostname, sandboxID)` | Set runtime variable on a host | Use to pass Terraform outputs (ALB URL) to tabs |
| `getSandboxVariable(key, hostname, sandboxID)` | Read runtime variable | |
| `updateSandboxTTL(sandboxID, until)` | Extend sandbox lifetime | |
| `stopSandbox(sandboxID)` | Force stop a sandbox | |
| `sandbox(sandboxID)` | Get sandbox state | States: creating → created → active → cleaning → cleaned |

### 4.8 Hot Start Pools

Pre-warm sandboxes for faster startup (eliminates Terraform wait):

```graphql
createHotStartPool(pool: HotStartPoolInput) {
  name: String
  tracks: [String]         # Track IDs
  size: Int                # Pool size (max 20 always-on, 200 scheduled)
  auto_refill: Boolean     # Refill as sandboxes are consumed
  starts_at: Time          # For scheduled pools
  ends_at: Time
  team_slug: String
  region: String
}
```

**This is critical for our demo.** With RDS taking 5-8 min to provision, hot start pools mean the sandbox is already running when the learner starts. Pool size 5-10 for scheduled events, 2-3 for always-on.

### 4.9 Host Images (Custom VM Images)

```graphql
createHostImage(input: HostImageInput) {
  slug: String          # Image identifier
  description: String
  teamID: ID
}
startHostImage(hostImageID, vmConfig)  # Start a sandbox to build the image
stopHostImage(hostImageID)             # Save the image
```

**This is how we pre-bake.** Create a custom host image with all Docker images, tools, and configs pre-loaded. Then reference it in the VM config instead of `instruqt/docker-2010`.

---

## 7. Existing Track Patterns (From Mezmo's Tracks)

### AWS Cloud Account Track (`0ytrmq5i2xlu`)
- Uses `cloud-client` container (`gcr.io/instruqt/cloud-client`) for AWS Console access
- AWS Console exposed as `service` tab on `cloud-client:80`
- IAM policy grants EC2 access
- SCP restricts to `t2.nano` instances
- Services whitelist: `["ec2", "autoscaling"]`
- Region: `["us-east-1"]`
- Track setup script: sets region + creates default VPC

### Docker VM Track (`uzxqici3wh6h`)
- Uses VM image `instruqt/docker-2010`
- Machine type: `n1-standard-1`
- No AWS account

### Key Pattern: AWS Console Tab
The `cloud-client` container is Instruqt's special image that:
1. Auto-receives AWS credentials
2. Proxies the AWS Console on port 80
3. Pre-configures the `aws` CLI
4. Must be present for the "AWS Console" tab to work

---

## 8. Implementation Plan (Updated for BYOA)

### Phase 1: Bedrock Validation (Can Do Now — No Instruqt Needed)

Since we're using our own AWS account, test Bedrock from any machine with the account's credentials:

```bash
aws bedrock invoke-model \
  --model-id us.anthropic.claude-sonnet-4-20250514-v1:0 \
  --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":50,"messages":[{"role":"user","content":"Hello"}]}' \
  --region us-east-1 \
  /dev/stdout 2>/dev/null | jq .
```

If it works → Bedrock confirmed. If not → enable model access in the AWS console (Bedrock → Model access → Request access for Anthropic Claude models). No Instruqt dependency.

### Phase 2: Store AWS Credentials as Team Secrets

```bash
# Store the demo account credentials in Instruqt
ACCESS_KEY_B64=$(echo -n "$AWS_ACCESS_KEY_ID" | base64)
SECRET_KEY_B64=$(echo -n "$AWS_SECRET_ACCESS_KEY" | base64)

# Create secrets via API (see Section 4 for full commands)
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
```

### Phase 3: Terraform (Prefix-Aware)

Write all Terraform with a `var.prefix` that scopes every resource name and tag. See Section 3 for the pattern. Test locally with different prefixes to verify no collisions.

### Phase 4: Custom VM Image (Pre-Bake)

1. `createHostImage` → get a build sandbox
2. Install: Docker images, Terraform, jq, helper scripts, aura configs, MCP server code
3. `stopHostImage` → save the image
4. Reference as `virtualmachines: [{ image: "mezmo/aura-demo-vm" }]`

### Phase 5: Create Track via API

Single `createTrack` mutation with:
- Track metadata (title, slug, description, level, tags)
- Sandbox config: 1 VM (custom image) + secrets (AWS creds)
- 11 challenges with assignments, tabs, and scripts
- Track-level setup/cleanup scripts

**No `cloud-client` container needed** — with BYOA there's no Instruqt-managed AWS Console tab. The learner accesses AWS Console via the external URL in a `website` or `external` tab with credentials printed in the terminal instructions.

Alternatively, install the AWS CLI on the VM and skip the Console entirely — the demo is terminal-driven anyway.

### Phase 6: Test & Iterate

1. `startTrack` to spin up a test sandbox
2. Walk through all 11 challenges
3. Verify prefix isolation: start 2 sandboxes simultaneously, confirm resources don't collide
4. `updateCompleteTrack` for atomic updates

### Phase 7: Invite & Distribute

1. `createTrackInvite` for self-paced or live events
2. Optionally `createHotStartPool` (up to 20 always-on) to pre-warm sandboxes
3. Share invite link

### Phase 8: Safety Net — Cleanup Lambda

Deploy a Lambda in the demo account that runs nightly:
1. List all resources tagged `demo=aura-bella-vista`
2. Group by `sandbox_id` tag
3. For each group, check if it's older than 24 hours
4. If so → delete (Terraform destroy or direct API calls)

This catches leaked resources from crashed/timed-out sandboxes.

---

## 9. API Quick Reference — Common Commands

### List tracks
```bash
curl -s -X POST https://play.instruqt.com/graphql \
  -H "Authorization: Bearer $INSTRUQT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ tracks(teamSlug: \"mezmo\") { id slug title } }"}' | jq '.'
```

### Get track config (sandbox)
```bash
curl -s -X POST https://play.instruqt.com/graphql \
  -H "Authorization: Bearer $INSTRUQT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ trackConfig(trackID: \"TRACK_ID\") { containers { name image } virtualmachines { name image machine_type } aws_accounts { name services regions } } }"}' | jq '.'
```

### Get challenges + tabs + scripts
```bash
curl -s -X POST https://play.instruqt.com/graphql \
  -H "Authorization: Bearer $INSTRUQT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ challenges(trackID: \"TRACK_ID\") { id slug title timelimit tabs { title type hostname port } } }"}' | jq '.'
```

### Create track (skeleton)
```bash
curl -s -X POST https://play.instruqt.com/graphql \
  -H "Authorization: Bearer $INSTRUQT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation($track: TrackInput!) { createTrack(track: $track) { id slug } }",
    "variables": {
      "track": {
        "slug": "aura-sre-platform",
        "title": "Aura SRE Platform — Intelligent Infrastructure Discovery",
        "owner": "mezmo",
        "description": "Deploy Aura into a live AWS environment...",
        "level": "intermediate",
        "private": true,
        "timelimit": 3600,
        "skipping_enabled": true,
        "config": {
          "virtualmachines": [{
            "name": "aura-host",
            "image": "instruqt/docker-2010",
            "machine_type": "n1-standard-4"
          }],
          "containers": [{
            "name": "cloud-client",
            "image": "gcr.io/instruqt/cloud-client"
          }],
          "aws_accounts": [{
            "name": "bella-vista-aws",
            "services": ["ec2","ecs","rds","s3","lambda","sqs","sns","dynamodb","iam","cloudwatch","cloudtrail","elasticloadbalancing","route53","cloudformation","bedrock","ecr","servicequotas","sts"],
            "regions": ["us-east-1"],
            "iam_policy": "...",
            "admin_iam_policy": "...",
            "scp_policy": "..."
          }]
        },
        "challenges": [
          {
            "slug": "welcome-to-bella-vista",
            "title": "Welcome to Bella Vista",
            "assignment": "... markdown instructions ...",
            "timelimit": 300,
            "tabs": [
              { "title": "Terminal", "type": "terminal", "hostname": "aura-host" },
              { "title": "AWS Console", "type": "service", "hostname": "cloud-client", "port": 80 }
            ]
          }
        ],
        "scripts": [
          {
            "host": "aura-host",
            "action": "setup",
            "contents": "BASE64_ENCODED_SETUP_SCRIPT"
          }
        ]
      }
    }
  }'
```

### Start a test run
```bash
curl -s -X POST https://play.instruqt.com/graphql \
  -H "Authorization: Bearer $INSTRUQT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "mutation { startTrack(trackID: \"TRACK_ID\") { id } }"}' | jq '.'
```

### Delete track
```bash
curl -s -X POST https://play.instruqt.com/graphql \
  -H "Authorization: Bearer $INSTRUQT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "mutation { deleteTrack(trackID: \"TRACK_ID\") }"}' | jq '.'
```

---

## 10. Credential Variable Names (Verified Pattern)

From the existing AWS track, the credential injection pattern uses the AWS account `name` field:

If the AWS account config has `name: "bella-vista-aws"`, the injected env vars on the `cloud-client` container would be:
```
INSTRUQT_AWS_ACCOUNTS_BELLA_VISTA_AWS_AWS_ACCESS_KEY_ID
INSTRUQT_AWS_ACCOUNTS_BELLA_VISTA_AWS_AWS_SECRET_ACCESS_KEY
INSTRUQT_AWS_ACCOUNTS_BELLA_VISTA_AWS_AWS_SESSION_TOKEN
INSTRUQT_AWS_ACCOUNTS_BELLA_VISTA_AWS_ACCOUNT_ID
```

Pattern: `INSTRUQT_AWS_ACCOUNTS_{NAME_UPPERCASED_HYPHENS_TO_UNDERSCORES}_{CREDENTIAL}`

These are available on the `cloud-client` container. For the `aura-host` VM, we may need to copy them via the setup script or use `setSandboxVariable`.

---

## 11. Next Steps

| Priority | Action | Blocked By | Effort |
|----------|--------|------------|--------|
| **P0** | Verify Bedrock access in the demo AWS account | Nothing — do it now | 5 min |
| **P0** | Store AWS credentials as Instruqt team secrets | Bedrock verification | 10 min |
| **P1** | Request AWS limit increases (VPCs→20, EIPs→20) | Nothing | 10 min |
| **P1** | Write prefix-aware Terraform (`demo/terraform/`) | Nothing — can start now | Medium |
| **P1** | Write demo Docker Compose (`demo/docker-compose.yml`) | Nothing | Medium |
| **P2** | Build custom VM image via Instruqt API | Terraform + Docker Compose done | Medium |
| **P2** | Write track creation script | All above done | Medium |
| **P3** | End-to-end testing (single sandbox) | Track created | Medium |
| **P3** | Multi-sandbox isolation test (2 concurrent) | Single sandbox working | Small |
| **P4** | Deploy cleanup Lambda | Demo account access | Small |
| **P4** | Create hot start pool for events | Track published | Small |

**No Instruqt plan upgrade needed.** The BYOA approach works with the current team features (VMs + containers + secrets).
