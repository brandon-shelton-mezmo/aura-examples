# Security Review — Aura AWS Discovery Agent

**Prepared for:** Security team review prior to deployment approval
**Date:** 2026-03-17
**Agent:** `aws-discovery-agent`
**Repository:** `aura-examples`

---

## Q1: What does it access?

Read-only AWS APIs only. The IAM policy grants these permissions and nothing else:

```
sts:GetCallerIdentity
ec2:Describe*
ecs:Describe*, ecs:List*
lambda:List*, lambda:GetFunction, lambda:GetPolicy
rds:Describe*
dynamodb:Describe*, dynamodb:List*
s3:ListAllMyBuckets, s3:GetBucketLocation, s3:GetBucketPolicy,
  s3:GetBucketTagging, s3:GetEncryptionConfiguration
iam:List*, iam:GetRole, iam:GetPolicy, iam:GetPolicyVersion
elasticloadbalancing:Describe*
route53:List*, route53:GetHostedZone
cloudfront:List*, cloudfront:GetDistribution
sqs:List*, sqs:GetQueueAttributes
sns:List*, sns:GetTopicAttributes
cloudformation:Describe*, cloudformation:List*
cloudwatch:Describe*, cloudwatch:List*
logs:Describe*
secretsmanager:ListSecrets, secretsmanager:DescribeSecret
ssm:DescribeParameters
eks:Describe*, eks:List*
bedrock:InvokeModel, bedrock:InvokeModelWithResponseStream
```

Every action in this list is a read operation. There are zero `Create*`, `Put*`, `Delete*`, `Update*`, `Modify*`, `Run*`, or `Terminate*` permissions.

The `bedrock:InvokeModel*` permissions are for the LLM provider only (agent reasoning). They do not grant access to infrastructure resources.

---

## Q2: Can it change our infrastructure?

No. Two independent layers prevent mutation:

**Layer 1 — IAM policy:** The policy contains only `Describe*`, `List*`, and `Get*` actions. AWS will reject any mutating API call at the authorization level regardless of what the agent attempts.

**Layer 2 — MCP server enforcement:** The AWS API MCP server runs with `READ_OPERATIONS_ONLY=true`. This environment variable causes the server process itself to reject mutating commands before they reach AWS. Even if the IAM policy were misconfigured, this server-side control blocks writes.

These two layers are independent. Both would need to fail simultaneously for any infrastructure change to occur.

---

## Q3: Does it see our secrets?

No.

**IAM policy excludes secret access:**
- `secretsmanager:GetSecretValue` is not in the policy. The agent cannot retrieve secret contents.
- `ssm:GetParameter` is not in the policy. The agent cannot read SSM parameter values, including SecureString parameters.

**What it can see about secrets:**
- `secretsmanager:ListSecrets` and `secretsmanager:DescribeSecret` — returns secret names, ARNs, descriptions, rotation status, and last rotation date. Never the secret value.
- `ssm:DescribeParameters` — returns parameter names, types, and tiers. Never the parameter value.

**System prompt reinforcement:** The agent's system prompt explicitly instructs: "Never store secret values, passwords, keys, or connection strings. For Secrets Manager and SSM, record only metadata: name, ARN, description, rotation status."

**Additional exclusions from stored data:**
- RDS/database passwords
- IAM user passwords or access key secrets
- EC2 user data scripts (may contain bootstrap tokens)
- Lambda function source code
- Environment variable values in ECS/Lambda task definitions (names stored, values excluded)

---

## Q4: Where does our data go?

Two data paths exist:

**Qdrant vector database:** Self-hosted. Runs as a Docker container in your VPC or on your host. Resource metadata (names, ARNs, configurations, tags, relationships) is stored here. You control the storage volume. No data is sent to any Qdrant-managed service unless you explicitly choose Qdrant Cloud.

**LLM inference (AWS Bedrock):** When using the Bedrock provider, all LLM calls go to the Bedrock API endpoint in your configured AWS region. Traffic stays within your AWS account. Bedrock does not retain your prompts or completions for model training (per AWS Bedrock data privacy terms).

**No data leaves AWS when using the Bedrock provider.** The agent communicates with AWS APIs (in-account), stores results in Qdrant (in-VPC), and reasons via Bedrock (in-account).

---

## Q5: What about the AI model?

**Primary provider: AWS Bedrock**
- Uses `us.anthropic.claude-sonnet-4-20250514-v1:0`
- Same compliance posture as any other AWS service in your account
- Covered by your existing AWS BAA, SOC 2, ISO 27001, and other AWS compliance certifications
- AWS does not use your inputs or outputs to train models
- Data does not leave your AWS region

**Alternative provider: OpenAI**
- An OpenAI variant config exists for local development
- If OpenAI is used, prompts and responses are sent to OpenAI's API outside AWS
- OpenAI's data usage policy applies in that case
- For production deployments where data residency matters, use Bedrock

---

## Q6: Can we audit what it does?

Yes. Three audit surfaces:

**AWS CloudTrail:** Every AWS API call the agent makes appears in CloudTrail. The calls are attributed to the IAM role or user credentials configured for the agent. You can filter CloudTrail events by the aura IAM role ARN to see exactly what was queried, when, and from where.

**Qdrant stored documents:** Every document stored in Qdrant includes a discovery timestamp. You can query the Qdrant collection to see what data the agent has written and when.

**Agent conversation logs:** Aura logs all tool calls made during a session. The MCP tool invocations (both `call_aws` and `qdrant-store`) are visible in the agent's output.

---

## Q7: Can we revoke access instantly?

Yes. Any of the following will immediately stop the agent from accessing AWS:

- **Delete the IAM role** used by the agent. All AWS API calls will fail with authorization errors.
- **Disable or delete the IAM access key** if using access key authentication. Immediate effect.
- **Remove the IAM policy** from the role. The agent will lose all AWS permissions.
- **Stop the aura container or process.** The agent, its MCP server connections, and all AWS sessions terminate.

No residual access persists after credential revocation. The agent has no cached credentials or standing connections to AWS beyond standard SDK session behavior.

---

## Q8: Is the code open source?

Yes.

- **Aura** (the agent runtime) is open source.
- **Agent configurations** are TOML files in this repository (`aura-examples`). Every configuration is readable and auditable.
- **AWS API MCP Server** is published by AWS Labs (`awslabs.aws-api-mcp-server`). Source available at [awslabs.github.io/mcp](https://awslabs.github.io/mcp/servers/aws-api-mcp-server).
- **Qdrant MCP Server** is published by Qdrant (`mcp-server-qdrant`). Source available at [github.com/qdrant/mcp-server-qdrant](https://github.com/qdrant/mcp-server-qdrant).
- **Qdrant** database is open source (Apache 2.0).

There is no proprietary agent code. The agent's behavior is defined entirely by the TOML configuration file and the system prompt within it.

---

## Q9: What data is stored in Qdrant?

Resource metadata only. For each discovered resource, the agent stores:

- Resource identifiers: name, ARN, ID
- Service and type: e.g., ECS Service, Lambda Function, S3 Bucket
- Region and account
- Configuration properties: instance type, runtime, CIDR blocks, desired count, engine version
- Tags: all key-value tag pairs found on the resource
- Relationships: references to related resources by name and ARN (e.g., VPC, subnet, security group, IAM role, load balancer)
- Discovery timestamp

**Never stored:**
- Passwords or credentials
- Secret values from Secrets Manager
- SSM parameter values
- S3 object contents
- CloudWatch log event contents
- Lambda function source code
- Environment variable values (names only)
- Database connection strings
- IAM access key secrets
- EC2 user data scripts

---

## Q10: Network requirements?

**Outbound only.** No inbound internet access is required.

| Destination | Protocol | Purpose |
|-------------|----------|---------|
| AWS API endpoints | HTTPS (443) | Resource discovery via AWS CLI commands |
| AWS Bedrock endpoint | HTTPS (443) | LLM inference (if using Bedrock provider) |
| Qdrant | HTTP (6333) | Vector storage — localhost or private VPC subnet |

**Qdrant network posture:**
- Runs on `localhost:6333` (single-host) or on a private subnet within your VPC
- No internet-facing ports required
- No inbound connections from outside your network

**No inbound listeners:** The aura agent makes outbound API calls. It does not need to receive inbound traffic to perform discovery. The aura-web-server exposes an API for user interaction (default port 3030), which can be bound to localhost or placed behind internal load balancing.

---

## Deployment Checklist

- [ ] IAM role created with the read-only policy above (via CloudFormation or Terraform template in `iam/`)
- [ ] AWS credentials configured for the agent (environment variables, IAM instance profile, or ECS task role)
- [ ] Qdrant running and accessible (`curl http://localhost:6333/health` returns `{"status":"ok"}`)
- [ ] Network access to AWS API endpoints verified (`aws sts get-caller-identity` succeeds)
- [ ] CloudTrail logging confirmed for the agent's IAM role
- [ ] Preflight validation passed (`CONFIG_PATH=aws-mcp-preflight.toml aura-web-server` — run preflight checks to verify MCP tools, credentials, and Qdrant connectivity)
