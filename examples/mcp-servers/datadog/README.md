# Datadog MCP Integration Examples

Connect an aura agent to Datadog for querying logs, metrics, traces, monitors, incidents, and dashboards using natural language.

## Prerequisites

- **Datadog account** with API and Application keys
- **Node.js 18+** (for `npx` to run the MCP server)
- **LLM provider credentials:** OpenAI API key (default configs) or AWS credentials (Bedrock variants)
- **Environment variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENAI_API_KEY` | Yes (default configs) | OpenAI API key for the LLM provider |
| `DATADOG_API_KEY` | Yes | Datadog API key ([create here](https://app.datadoghq.com/organization-settings/api-keys)) |
| `DATADOG_APP_KEY` | Yes | Datadog Application key ([create here](https://app.datadoghq.com/organization-settings/application-keys)) |
| `DATADOG_SITE` | No | Datadog site (defaults to `datadoghq.com`; use `datadoghq.eu` for EU) |

```bash
# For default (OpenAI) configs:
export OPENAI_API_KEY="your-openai-key"
export DATADOG_API_KEY="your-datadog-api-key"
export DATADOG_APP_KEY="your-datadog-app-key"
# export DATADOG_SITE="datadoghq.eu"  # Only if using EU site

# For Bedrock variants: configure AWS credentials instead of OPENAI_API_KEY
# (via ~/.aws/credentials, environment variables, or IAM role)
```

## MCP Server

Uses the community [`@winor30/mcp-server-datadog`](https://www.npmjs.com/package/@winor30/mcp-server-datadog) package via `npx` (stdio transport).

**Available tools include:** `list_incidents`, `get_logs`, `list_spans`, `get_metric`, `list_monitors`, `list_dashboards`, and more.

## Configs

| Config | Tier | Provider | Description |
|--------|------|----------|-------------|
| `datadog-basic.toml` | Basic | OpenAI | Minimal MCP connection — proves Datadog tools are accessible |
| `datadog-basic-bedrock.toml` | Basic | Bedrock | Same as above, using AWS Bedrock (no LLM API key needed) |
| `datadog-explorer.toml` | Explorer | OpenAI | Tool discovery mode — exercises each Datadog tool individually |
| `datadog-explorer-bedrock.toml` | Explorer | Bedrock | Same as above, using AWS Bedrock |
| `datadog-incident-responder.toml` | Use Case | OpenAI | Incident investigation persona with multi-step reasoning |
| `datadog-incident-responder-bedrock.toml` | Use Case | Bedrock | Same as above, using AWS Bedrock |
| `datadog-performance-investigator.toml` | Use Case | OpenAI | Latency and regression analysis persona |
| `datadog-performance-investigator-bedrock.toml` | Use Case | Bedrock | Same as above, using AWS Bedrock |

## Running

```bash
# Local (basic example)
CONFIG_PATH=examples/mcp-servers/datadog/datadog-basic.toml \
  ~/Documents/GitHub/aura/target/release/aura-web-server

# Docker
docker run \
  -v $(pwd)/examples/mcp-servers/datadog/datadog-basic.toml:/app/config.toml \
  -e OPENAI_API_KEY=$OPENAI_API_KEY \
  -e DATADOG_API_KEY=$DATADOG_API_KEY \
  -e DATADOG_APP_KEY=$DATADOG_APP_KEY \
  -p 3030:3030 \
  mezmo/aura:latest
```

## Example Prompts

### Basic / Explorer
- "What tools do you have available?"
- "List all monitors that are currently alerting"
- "Show me the most recent logs from the payments service"

### Incident Responder
- "Are there any active P1 incidents?"
- "Show error logs from payments service in the last hour"
- "Find the slowest traces for the checkout endpoint"
- "Correlate the spike in error rate with recent deployments"

### Performance Investigator
- "What's the p99 latency for the API gateway today?"
- "Which service has the highest error rate this week?"
- "Compare CPU usage across API hosts"
- "Show me latency trends for the order service over the past 24 hours"
