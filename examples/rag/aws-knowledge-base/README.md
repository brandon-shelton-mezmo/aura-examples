# AWS Knowledge Base Query Agent

An aura agent that answers questions about your AWS infrastructure by searching a
Qdrant knowledge base. It does not connect to AWS APIs directly -- it only queries
resources that were previously discovered and stored.

Think of it as a search engine for your AWS environment.

## Prerequisite: Populate the Knowledge Base First

This agent searches existing data. If the knowledge base is empty, there is nothing
to search. Run the discovery agent first:

```
examples/mcp-servers/aws/aws-discovery-agent.toml
```

The discovery agent connects to AWS APIs, catalogs your resources (EC2, ECS, RDS,
VPCs, Lambda, etc.), and stores them in Qdrant. You only need to run discovery
once per scan -- then use this query agent as many times as you want.

## Quick Start

```bash
# 1. Make sure Qdrant is running with a populated 'aws_resources' collection
docker run -p 6333:6333 qdrant/qdrant

# 2. Start the query agent (Bedrock)
export AWS_REGION=us-east-1
CONFIG_PATH=examples/rag/aws-knowledge-base/aws-kb-query-agent.toml aura-web-server

# 3. Ask a question
curl -s http://localhost:3030/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"What ECS services are running?"}]}'
```

## Example Questions

These cover the kinds of things the query agent handles well:

| Category | Question |
|----------|----------|
| Resource lookup | "List all RDS instances and their engine versions" |
| Resource lookup | "What Lambda functions exist in us-east-1?" |
| Relationship | "What resources are inside vpc-abc123?" |
| Relationship | "Which security groups are attached to the production ECS cluster?" |
| Ownership | "Show me all resources tagged with team=platform" |
| Ownership | "What EC2 instances are in the staging environment?" |
| Change context | "When was the last discovery scan for ECS services?" |
| Change context | "Are there any resources discovered more than 7 days ago?" |
| Cross-service | "What load balancers route traffic to ECS services?" |
| Troubleshooting | "Which subnets have no running instances?" |

If the agent says it cannot find something, that resource was not included in the
last discovery scan. Re-run the discovery agent to pick it up.

## Data Freshness

Every stored resource includes a timestamp from when it was discovered. The agent
includes these timestamps in its answers so you know how current the data is.

Keep in mind:

- The knowledge base is a **snapshot**, not a live view. Resources created or
  deleted after the last scan will not be reflected.
- For environments that change frequently, re-run the discovery agent on a
  schedule (daily, hourly -- whatever fits your needs).
- The agent will warn you when results look sparse or outdated and suggest
  re-scanning.

## Bedrock vs OpenAI

Two config files are provided. They are identical except for the LLM provider.

| Config | Provider | When to use |
|--------|----------|-------------|
| `aws-kb-query-agent.toml` | AWS Bedrock | Default. All LLM traffic stays in AWS. Uses IAM credentials -- no API key needed. |
| `aws-kb-query-agent-openai.toml` | OpenAI | Use when Bedrock is not available. Requires `OPENAI_API_KEY`. |

Both use the same Qdrant knowledge base and produce the same results. The only
difference is where the LLM inference runs.
