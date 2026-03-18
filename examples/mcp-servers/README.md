# MCP Server Integration Examples

Aura agents connect to external tool servers using the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/). These examples demonstrate integrations with popular observability platforms.

## Which Platform Should I Start With?

| If you... | Start with |
|-----------|------------|
| Use Datadog for monitoring | [datadog/](datadog/) |
| Want a vendor-neutral OTEL approach | [opentelemetry/](opentelemetry/) |
| Run Grafana + Prometheus + Loki | [grafana/](grafana/) |
| Use Dynatrace with DQL | [dynatrace/](dynatrace/) |
| Use New Relic (no local install needed) | [newrelic/](newrelic/) |
| Want to discover and catalog your AWS infrastructure | [aws/](aws/) |
| Want to query multiple platforms at once | [cross-platform/](cross-platform/) |

## Transport Types

Aura supports two MCP transport types:

| Transport | When to Use | Example |
|-----------|-------------|---------|
| `stdio` | Local MCP server process (npx, uvx, Go binary) | Datadog, OTEL, Grafana, Dynatrace |
| `http_streamable` | Remote-hosted MCP server (SaaS) | New Relic |

## Platform Comparison

| Platform | Package | Transport | Auth Method | Local Install |
|----------|---------|-----------|-------------|---------------|
| **Datadog** | `@winor30/mcp-server-datadog` | `stdio` | API key + App key via env | Yes (npx) |
| **OpenTelemetry** | `opentelemetry-mcp` | `stdio` | Backend URL via env | Yes (uvx) |
| **Grafana** | `mcp-grafana` | `stdio` | Service account token via env | Yes (Go binary) |
| **Dynatrace** | `@dynatrace-oss/dynatrace-mcp-server` | `stdio` | Platform token via env | Yes (npx) |
| **New Relic** | Remote-hosted | `http_streamable` | User API key via header | No |

## Config Tiers

Each platform has configs at three levels of complexity:

| Tier | Purpose | turn_depth |
|------|---------|------------|
| **Basic** | Minimal MCP connection — proves the integration works | Default (5) |
| **Explorer** | Tool discovery — exercises each tool individually | 3 |
| **Use Case** | Specific persona with multi-step reasoning | 10 |

Start with **Basic** to verify connectivity, then move to **Explorer** to learn available tools, and finally use **Use Case** configs for production-style agent behavior.

## Bedrock Variants

Every config has a `-bedrock.toml` variant that uses **AWS Bedrock** instead of OpenAI/Anthropic as the LLM provider. Bedrock variants authenticate via the AWS credentials chain (`~/.aws/credentials`, environment variables, or IAM role) — no third-party LLM API key is needed.

To use a Bedrock variant, simply swap the config file name:
```bash
# OpenAI version
CONFIG_PATH=examples/mcp-servers/datadog/datadog-basic.toml aura-web-server

# Bedrock version
CONFIG_PATH=examples/mcp-servers/datadog/datadog-basic-bedrock.toml aura-web-server
```

## Security

All examples follow these security practices:
- API keys use `{{ env.VAR }}` syntax — never hardcoded
- MCP server env vars are passed via `[mcp.servers.*.env]` sub-tables
- HTTP headers use `[mcp.servers.*.headers]` for remote MCP auth
