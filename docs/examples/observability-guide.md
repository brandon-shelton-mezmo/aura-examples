# Observability MCP Integration Guide

This guide explains how to use aura agents with observability platforms via MCP (Model Context Protocol), covering concepts, platform comparison, and best practices.

## How It Works

```
User (natural language) → Aura Agent → MCP Protocol → Observability Platform API
                              ↑                              ↓
                         LLM (reasoning)              Data (logs, metrics, traces)
```

1. The user asks a question in natural language (e.g., "What's the error rate for the API service?")
2. The aura agent uses its LLM to understand the intent and select the right MCP tool
3. The agent calls the MCP tool, which translates to an API call against the observability platform
4. The platform returns raw data, which the agent interprets and presents in plain English

## Key Concepts

### MCP (Model Context Protocol)

MCP is a standard protocol for connecting AI agents to external tools. Each observability platform has an MCP server that exposes its API as a set of tools the agent can call.

### Transports

Aura supports two ways to connect to MCP servers:

- **`stdio`** — The MCP server runs as a local child process. Aura launches it, communicates via stdin/stdout. Used by Datadog, OTEL, Grafana, and Dynatrace.
- **`http_streamable`** — The MCP server is hosted remotely. Aura connects over HTTP. Used by New Relic.

### Agent Personas

Use-case configs define agent personas — specialized system prompts that guide how the agent reasons about observability data. A well-crafted persona includes:

- **Role**: What the agent is (e.g., "Incident Response Agent")
- **Responsibilities**: What it should do
- **Methodology**: Step-by-step approach to common tasks
- **Interaction style**: How it presents information
- **Fallback behavior**: What to do when tools are unavailable

## Platform Comparison

### Feature Matrix

| Feature | Datadog | OTEL | Grafana | Dynatrace | New Relic |
|---------|---------|------|---------|-----------|-----------|
| Logs | Yes | — | Yes (Loki) | Yes (DQL) | Yes (NRQL) |
| Metrics | Yes | — | Yes (Prometheus) | Yes (DQL) | Yes (NRQL) |
| Traces | Yes | Yes | Yes (Tempo) | Yes (DQL) | Yes (NRQL) |
| Alerts/Monitors | Yes | — | Yes | Yes | Yes |
| Incidents | Yes | — | — | — | — |
| Dashboards | Yes | — | Yes | — | — |
| NL Queries | — | — | — | Yes (Davis) | — |
| Entity Search | — | — | — | Yes | Yes |
| Golden Metrics | — | — | — | — | Yes |
| Vulnerabilities | — | — | — | Yes | — |

### When to Choose Which

**Datadog** — Best for teams already using Datadog. Broadest tool coverage (logs, metrics, traces, monitors, incidents, dashboards) in a single MCP server.

**OpenTelemetry (Traceloop)** — Best for vendor-neutral trace analysis. Works with any OTEL-compatible backend (Jaeger, Tempo, Traceloop). Focused on distributed tracing.

**Grafana** — Best for teams running the Grafana + Prometheus + Loki stack. Covers metrics, logs, alerts, and dashboards from a single Grafana instance.

**Dynatrace** — Best for enterprise environments using DQL. Unique natural language-to-DQL capability via Davis CoPilot. Strong K8s and entity health features.

**New Relic** — Best for teams wanting zero local setup. Remote-hosted MCP server means no packages to install. NRQL is powerful for ad-hoc querying. Golden metrics feature provides standardized health views.

## Configuration Patterns

### Basic Config Pattern

Every MCP integration starts with the same structure:

```toml
[llm]
provider = "openai"
model = "gpt-4o"
api_key = "{{ env.OPENAI_API_KEY }}"

[agent]
name = "my-agent"
system_prompt = "You are an assistant connected to [platform]..."

[mcp.servers.platform_name]
transport = "stdio"  # or "http_streamable"
# ... transport-specific fields
description = "What this MCP server provides"
```

### STDIO Transport (Local MCP Server)

```toml
[mcp.servers.my_server]
transport = "stdio"
cmd = ["npx"]                           # Executable only
args = ["-y", "@package/name"]          # Arguments separate from cmd
description = "Description of capabilities"

[mcp.servers.my_server.env]             # Sub-table for env vars
API_KEY = "{{ env.MY_API_KEY }}"
```

### HTTP Streamable Transport (Remote MCP Server)

```toml
[mcp.servers.my_server]
transport = "http_streamable"
url = "https://mcp.example.com/mcp/"
description = "Description of capabilities"

[mcp.servers.my_server.headers]         # Sub-table for auth headers
Api-Key = "{{ env.MY_API_KEY }}"
```

### Multi-MCP Agent

Connect to multiple observability platforms in a single agent:

```toml
[mcp.servers.datadog]
transport = "stdio"
cmd = ["npx"]
args = ["-y", "@winor30/mcp-server-datadog"]
description = "Datadog tools"

[mcp.servers.grafana]
transport = "stdio"
cmd = ["mcp-grafana"]
description = "Grafana tools"
```

Each MCP server gets a unique key under `[mcp.servers.*]`.

## Best Practices

1. **Start with the Basic config** — Verify connectivity before adding complexity
2. **Use Explorer configs to learn** — Understand available tools before building personas
3. **Set appropriate turn_depth** — Basic (default 5), Explorer (3), Use Case (10)
4. **Keep secrets in env vars** — Use `{{ env.VAR }}` syntax, never hardcode
5. **Add descriptions to MCP servers** — Helps the LLM understand what tools to use
6. **Test with simple prompts first** — "What tools do you have?" is a good starting point
7. **Include fallback instructions** — Tell the agent what to do when tools are unavailable

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| "MCP server failed to start" | Package not installed or wrong cmd | Check `npx`/`uvx`/binary is in PATH |
| "Connection refused" | Remote MCP server unreachable | Check URL and network connectivity |
| "Authentication failed" | Wrong or missing API key | Verify env var is set and key is valid |
| "No tools available" | MCP server connected but no tools listed | Check MCP server docs for required env vars |
| Agent doesn't use tools | System prompt doesn't mention tools | Add tool usage guidance to system_prompt |
| Too many tool calls | turn_depth too high for the task | Lower turn_depth for simple queries |
