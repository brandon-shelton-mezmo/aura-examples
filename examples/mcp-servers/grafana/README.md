# Grafana MCP Integration Examples

Connect an aura agent to Grafana for querying Prometheus metrics, Loki logs, Tempo traces, dashboards, and alert rules using natural language.

## Prerequisites

- **Grafana instance** (self-hosted or Grafana Cloud) with a service account token
- **`mcp-grafana` binary** installed ([install instructions](https://github.com/grafana/mcp-grafana))
- **Environment variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENAI_API_KEY` | Yes | OpenAI API key for the LLM provider |
| `GRAFANA_URL` | Yes | Grafana instance URL (e.g., `http://localhost:3000`) |
| `GRAFANA_SERVICE_ACCOUNT_TOKEN` | Yes | Grafana service account token with viewer+ role |

```bash
export OPENAI_API_KEY="your-openai-key"
export GRAFANA_URL="http://localhost:3000"
export GRAFANA_SERVICE_ACCOUNT_TOKEN="glsa_xxxxxxxxxxxx"
```

### Installing mcp-grafana

```bash
# Using Go
go install github.com/grafana/mcp-grafana@latest

# Or download the binary from releases:
# https://github.com/grafana/mcp-grafana/releases
```

### Setting Up a Grafana Service Account

1. Go to **Administration > Service Accounts** in Grafana
2. Create a new service account with **Viewer** role (or higher for write operations)
3. Generate a token and set it as `GRAFANA_SERVICE_ACCOUNT_TOKEN`

## MCP Server

Uses the official [`mcp-grafana`](https://github.com/grafana/mcp-grafana) Go binary (stdio transport).

**Available tools include:** Prometheus metric queries, Loki log queries, Tempo trace search, dashboard listing, alert rule status, and datasource management.

## Configs

| Config | Tier | Description |
|--------|------|-------------|
| `grafana-basic.toml` | Basic | Minimal MCP connection — proves Grafana tools are accessible |
| `grafana-sre-dashboard.toml` | Use Case | SRE morning health check across metrics, logs, and alerts |

## Running

```bash
# Local (basic example)
CONFIG_PATH=examples/mcp-servers/grafana/grafana-basic.toml \
  ~/Documents/GitHub/aura/target/release/aura-web-server

# Docker (note: mcp-grafana must be accessible in the container)
docker run \
  -v $(pwd)/examples/mcp-servers/grafana/grafana-basic.toml:/app/config.toml \
  -e OPENAI_API_KEY=$OPENAI_API_KEY \
  -e GRAFANA_URL=$GRAFANA_URL \
  -e GRAFANA_SERVICE_ACCOUNT_TOKEN=$GRAFANA_SERVICE_ACCOUNT_TOKEN \
  -p 3030:3030 \
  mezmo/aura:latest
```

## Example Prompts

### Basic
- "What tools do you have available?"
- "List all dashboards in Grafana"
- "What datasources are configured?"

### SRE Dashboard
- "What's the request rate for the API service?"
- "Show error logs from the payment processor in the last hour"
- "Are any alert rules currently firing?"
- "Give me a morning health check: request rate, error rate, and active alerts"
