# New Relic MCP Integration Examples

Connect an aura agent to New Relic's remote-hosted MCP server for querying application performance, running NRQL queries, and analyzing golden metrics — all without installing any local packages.

## Prerequisites

- **New Relic account** with MCP access (preview feature — [request access](https://newrelic.com/platform/ai))
- **New Relic User API key** (NOT ingest key or license key)
- **LLM provider credentials:** OpenAI API key (default configs) or AWS credentials (Bedrock variants)
- **Environment variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENAI_API_KEY` | Yes (default configs) | OpenAI API key for the LLM provider |
| `NEW_RELIC_API_KEY` | Yes | New Relic User API key ([create here](https://one.newrelic.com/api-keys)) |

```bash
# For default (OpenAI) configs:
export OPENAI_API_KEY="your-openai-key"
export NEW_RELIC_API_KEY="NRAK-xxxxxxxxxxxxxxxxxxxx"

# For Bedrock variants: configure AWS credentials instead of OPENAI_API_KEY
# (via ~/.aws/credentials, environment variables, or IAM role)
```

### RBAC Note

New Relic MCP access is governed by your API key's permissions. The User API key inherits the permissions of the user who created it. Ensure the user has access to the accounts and entities you want the agent to query.

### Remote MCP Server

Unlike other observability examples that use local MCP servers via `stdio`, New Relic provides a **remote-hosted MCP server** accessible via `http_streamable` transport. No local package installation is required — the agent connects directly to `https://mcp.newrelic.com/mcp/`.

## MCP Server

Uses New Relic's remote MCP endpoint at `https://mcp.newrelic.com/mcp/` (http_streamable transport).

**Available tools include:** NRQL query execution, entity search, golden metrics retrieval, deployment markers, alert condition management, and more.

## Configs

| Config | Tier | Provider | Description |
|--------|------|----------|-------------|
| `newrelic-basic.toml` | Basic | OpenAI | Minimal remote MCP connection — proves NR tools are accessible |
| `newrelic-basic-bedrock.toml` | Basic | Bedrock | Same as above, using AWS Bedrock (no LLM API key needed) |
| `newrelic-explorer.toml` | Explorer | OpenAI | Tool discovery mode — exercises each NR tool individually |
| `newrelic-explorer-bedrock.toml` | Explorer | Bedrock | Same as above, using AWS Bedrock |
| `newrelic-deployment-validator.toml` | Use Case | OpenAI | Deployment impact analysis persona |
| `newrelic-deployment-validator-bedrock.toml` | Use Case | Bedrock | Same as above, using AWS Bedrock |
| `newrelic-golden-metrics-review.toml` | Use Case | OpenAI | Multi-service health summary via golden metrics |
| `newrelic-golden-metrics-review-bedrock.toml` | Use Case | Bedrock | Same as above, using AWS Bedrock |

## Running

```bash
# Local (basic example)
CONFIG_PATH=examples/mcp-servers/newrelic/newrelic-basic.toml \
  ~/Documents/GitHub/aura/target/release/aura-web-server

# Docker
docker run \
  -v $(pwd)/examples/mcp-servers/newrelic/newrelic-basic.toml:/app/config.toml \
  -e OPENAI_API_KEY=$OPENAI_API_KEY \
  -e NEW_RELIC_API_KEY=$NEW_RELIC_API_KEY \
  -p 3030:3030 \
  mezmo/aura:latest
```

## Example Prompts

### Basic / Explorer
- "What tools do you have available?"
- "List all monitored applications in my account"
- "Run a simple NRQL query to count transactions from the last hour"

### Deployment Validator
- "How did the last deployment affect order-service performance?"
- "What was the error rate before and after the 2pm release?"
- "Compare throughput for the API service over the last two deployments"
- "Show me any SLA violations since the latest deployment"

### Golden Metrics Review
- "Analyze the health of the API gateway service"
- "Which services have degraded golden metrics today?"
- "Give me a golden metrics summary for all production services"
- "What's the throughput, error rate, and latency for the checkout service?"
