# Datadog MCP Integration Examples

Connect an aura agent to Datadog for querying logs, metrics, traces, monitors, incidents, and dashboards using natural language.

## Prerequisites

- **Datadog account** with API and Application keys
- **Node.js 18+** (for `npx` to run the MCP server)
- **Environment variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENAI_API_KEY` | Yes | OpenAI API key for the LLM provider |
| `DATADOG_API_KEY` | Yes | Datadog API key ([create here](https://app.datadoghq.com/organization-settings/api-keys)) |
| `DATADOG_APP_KEY` | Yes | Datadog Application key ([create here](https://app.datadoghq.com/organization-settings/application-keys)) |
| `DATADOG_SITE` | No | Datadog site (defaults to `datadoghq.com`; use `datadoghq.eu` for EU) |

```bash
export OPENAI_API_KEY="your-openai-key"
export DATADOG_API_KEY="your-datadog-api-key"
export DATADOG_APP_KEY="your-datadog-app-key"
# export DATADOG_SITE="datadoghq.eu"  # Only if using EU site
```

## MCP Server

Uses the community [`@winor30/mcp-server-datadog`](https://www.npmjs.com/package/@winor30/mcp-server-datadog) package via `npx` (stdio transport).

**Available tools include:** `list_incidents`, `get_logs`, `list_spans`, `get_metric`, `list_monitors`, `list_dashboards`, and more.

## Configs

| Config | Tier | Description |
|--------|------|-------------|
| `datadog-basic.toml` | Basic | Minimal MCP connection — proves Datadog tools are accessible |
| `datadog-explorer.toml` | Explorer | Tool discovery mode — exercises each Datadog tool individually |
| `datadog-incident-responder.toml` | Use Case | Incident investigation persona with multi-step reasoning |
| `datadog-performance-investigator.toml` | Use Case | Latency and regression analysis persona |

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
