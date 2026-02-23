# Dynatrace MCP Integration Examples

Connect an aura agent to Dynatrace for running DQL queries, exploring entities, leveraging Davis CoPilot, and monitoring Kubernetes events.

## Prerequisites

- **Dynatrace SaaS environment** (must be `*.apps.dynatrace.com`)
- **Node.js 18+** (for `npx` to run the MCP server)
- **Dynatrace platform token** with appropriate scopes
- **Environment variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENAI_API_KEY` | Yes* | OpenAI API key (used by most configs) |
| `ANTHROPIC_API_KEY` | Yes* | Anthropic API key (used by NL query config) |
| `DT_ENVIRONMENT` | Yes | Dynatrace environment URL (must be `*.apps.dynatrace.com`) |
| `DT_PLATFORM_TOKEN` | Yes | Dynatrace platform token |

*Only one LLM provider key is needed — check the specific config file.

```bash
export OPENAI_API_KEY="your-openai-key"
export DT_ENVIRONMENT="https://your-env.apps.dynatrace.com"
export DT_PLATFORM_TOKEN="dt0c01.xxxxxxxx.yyyyyyyy"
```

### Creating a Dynatrace Platform Token

1. Go to **Account Management > Identity & access management > OAuth clients**
2. Create a token with these scopes (minimum):
   - `storage:logs:read`
   - `storage:metrics:read`
   - `storage:entities:read`
   - `storage:events:read`
   - `Davis CoPilot` (for NL query features)
3. Set the token as `DT_PLATFORM_TOKEN`

> **Cost warning:** Dynatrace DQL queries consume DDUs (Davis Data Units). Use the explorer config to understand available tools before running expensive queries in production.

## MCP Server

Uses the official [`@dynatrace-oss/dynatrace-mcp-server`](https://www.npmjs.com/package/@dynatrace-oss/dynatrace-mcp-server) package via `npx` (stdio transport).

**Available tools include:** DQL query execution, entity listing, Davis CoPilot natural language queries, event retrieval, and vulnerability scanning.

## Configs

| Config | Tier | Provider | Description |
|--------|------|----------|-------------|
| `dynatrace-basic.toml` | Basic | OpenAI | Minimal MCP connection — proves Dynatrace tools are accessible |
| `dynatrace-explorer.toml` | Explorer | OpenAI | Tool discovery mode — exercises DQL and entity tools |
| `dynatrace-natural-language-query.toml` | Use Case | **Anthropic** | NL-to-DQL conversion + Davis CoPilot integration |
| `dynatrace-k8s-ops.toml` | Use Case | OpenAI | K8s event monitoring and entity health persona |

## Running

```bash
# Local (basic example)
CONFIG_PATH=examples/mcp-servers/dynatrace/dynatrace-basic.toml \
  ~/Documents/GitHub/aura/target/release/aura-web-server

# Docker
docker run \
  -v $(pwd)/examples/mcp-servers/dynatrace/dynatrace-basic.toml:/app/config.toml \
  -e OPENAI_API_KEY=$OPENAI_API_KEY \
  -e DT_ENVIRONMENT=$DT_ENVIRONMENT \
  -e DT_PLATFORM_TOKEN=$DT_PLATFORM_TOKEN \
  -p 3030:3030 \
  mezmo/aura:latest
```

## Example Prompts

### Basic / Explorer
- "What tools do you have available?"
- "List all monitored entities in my environment"
- "Run a simple DQL query to count log entries from the last hour"

### Natural Language Query
- "Write a DQL query to find all database calls over 500ms"
- "Why is the order service experiencing high latency?"
- "Show me the top 10 slowest API endpoints this week"
- "Ask Davis: what anomalies were detected today?"

### K8s Ops
- "Show recent warning events from the production K8s cluster"
- "Which pods have restarted more than 3 times today?"
- "List critical vulnerabilities detected in the last 30 days"
- "What's the health status of all Kubernetes namespaces?"
