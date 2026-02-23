# OpenTelemetry (Traceloop) MCP Integration Examples

Connect an aura agent to OpenTelemetry backends (Jaeger, Grafana Tempo, Traceloop) for querying distributed traces, analyzing spans, and investigating errors.

## Prerequisites

- **Python 3.10+** with `uvx` ([install uv](https://docs.astral.sh/uv/getting-started/installation/))
- **An OTEL-compatible backend** (Jaeger, Grafana Tempo, or Traceloop)
- **Environment variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENAI_API_KEY` | Yes | OpenAI API key for the LLM provider |
| `BACKEND_TYPE` | Yes | Backend type: `jaeger`, `tempo`, or `traceloop` |
| `BACKEND_URL` | Yes | Backend URL (e.g., `http://localhost:16686` for Jaeger) |

```bash
export OPENAI_API_KEY="your-openai-key"
export BACKEND_TYPE="jaeger"
export BACKEND_URL="http://localhost:16686"
```

### Backend-Specific Setup

**Jaeger** (recommended for local development):
```bash
docker run -d --name jaeger \
  -p 16686:16686 \
  -p 4317:4317 \
  jaegertracing/all-in-one:latest

export BACKEND_TYPE="jaeger"
export BACKEND_URL="http://localhost:16686"
```

**Grafana Tempo**:
```bash
export BACKEND_TYPE="tempo"
export BACKEND_URL="http://localhost:3200"
```

## MCP Server

Uses the [`opentelemetry-mcp`](https://pypi.org/project/opentelemetry-mcp/) package via `uvx` (stdio transport).

**Available tools include:** trace search, span analysis, service dependency mapping, and error pattern detection.

## Configs

| Config | Tier | Description |
|--------|------|-------------|
| `otel-basic.toml` | Basic | Minimal OTEL MCP connection with Jaeger backend |
| `otel-explorer.toml` | Explorer | Tool discovery mode — exercises each trace tool individually |
| `otel-trace-investigator.toml` | Use Case | Distributed trace debugging persona |
| `otel-error-analyst.toml` | Use Case | Error pattern detection and categorization persona |

## Running

```bash
# Local (basic example with Jaeger)
CONFIG_PATH=examples/mcp-servers/opentelemetry/otel-basic.toml \
  ~/Documents/GitHub/aura/target/release/aura-web-server

# Docker
docker run \
  -v $(pwd)/examples/mcp-servers/opentelemetry/otel-basic.toml:/app/config.toml \
  -e OPENAI_API_KEY=$OPENAI_API_KEY \
  -e BACKEND_TYPE=$BACKEND_TYPE \
  -e BACKEND_URL=$BACKEND_URL \
  -p 3030:3030 \
  mezmo/aura:latest
```

## Example Prompts

### Basic / Explorer
- "What tools do you have available for trace analysis?"
- "List all services that have reported traces recently"
- "Show me a sample trace from the user-auth service"

### Trace Investigator
- "Find traces with errors in user-auth service from the last 30 minutes"
- "Show me the slowest database spans across all services"
- "What's the critical path in traces for the /api/checkout endpoint?"

### Error Analyst
- "What are the most common error types in the last hour?"
- "Which services have the highest error rate?"
- "Group errors by exception type and show the top 5"
