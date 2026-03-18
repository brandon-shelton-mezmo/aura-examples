# Examples Directory

This directory contains aura agent configuration examples organized by feature category.

## File Inventory

| Directory | Purpose |
|-----------|---------|
| `basic/` | Minimal getting-started examples — one concept each |
| `providers/` | Provider-specific configurations (OpenAI, Anthropic, Bedrock, Gemini, Ollama) |
| `mcp-servers/` | MCP tool server integration patterns (stdio, http_streamable) |
| `rag/` | RAG and vector store examples (in-memory, Qdrant) |
| `deployment/` | Docker, Docker Compose, K8s, and Helm deployment patterns |

## Conventions Specific to This Directory

- Every example is either a single TOML file (with rich inline comments) or a directory with config + README
- File names are descriptive: `openai-simple.toml`, `bedrock-mezmo-tools.toml`
- All secrets use `{{ env.VAR }}` syntax — never hardcoded
- Examples progress from simple to complex within each category

## Adding a New Example

1. Copy from template: `.claude/templates/new-example.toml`
2. Or study an existing example in the target category
3. Place in the appropriate category directory
4. Add inline TOML comments explaining every section
5. Include run instructions (local + Docker) as comments at top of file or in README
6. Validate: `python3 -c "import tomllib; tomllib.load(open('your-file.toml', 'rb'))"`
7. Update this inventory when adding new examples

## MCP Servers Inventory

### Datadog (`mcp-servers/datadog/`)
| File | Tier | Provider | Description |
|------|------|----------|-------------|
| `datadog-basic.toml` | Basic | OpenAI | Minimal Datadog MCP connection |
| `datadog-basic-bedrock.toml` | Basic | Bedrock | Minimal Datadog MCP connection (AWS Bedrock) |
| `datadog-explorer.toml` | Explorer | OpenAI | Tool discovery mode for Datadog |
| `datadog-explorer-bedrock.toml` | Explorer | Bedrock | Tool discovery mode for Datadog (AWS Bedrock) |
| `datadog-incident-responder.toml` | Use Case | OpenAI | Incident investigation persona |
| `datadog-incident-responder-bedrock.toml` | Use Case | Bedrock | Incident investigation persona (AWS Bedrock) |
| `datadog-performance-investigator.toml` | Use Case | OpenAI | Latency and regression analysis |
| `datadog-performance-investigator-bedrock.toml` | Use Case | Bedrock | Latency and regression analysis (AWS Bedrock) |

### OpenTelemetry (`mcp-servers/opentelemetry/`)
| File | Tier | Provider | Description |
|------|------|----------|-------------|
| `otel-basic.toml` | Basic | OpenAI | Minimal OTEL MCP connection (Jaeger backend) |
| `otel-basic-bedrock.toml` | Basic | Bedrock | Minimal OTEL MCP connection (AWS Bedrock) |
| `otel-explorer.toml` | Explorer | OpenAI | Tool discovery mode for OTEL traces |
| `otel-explorer-bedrock.toml` | Explorer | Bedrock | Tool discovery mode for OTEL traces (AWS Bedrock) |
| `otel-trace-investigator.toml` | Use Case | OpenAI | Distributed trace debugging |
| `otel-trace-investigator-bedrock.toml` | Use Case | Bedrock | Distributed trace debugging (AWS Bedrock) |
| `otel-error-analyst.toml` | Use Case | OpenAI | Error pattern detection |
| `otel-error-analyst-bedrock.toml` | Use Case | Bedrock | Error pattern detection (AWS Bedrock) |

### Grafana (`mcp-servers/grafana/`)
| File | Tier | Provider | Description |
|------|------|----------|-------------|
| `grafana-basic.toml` | Basic | OpenAI | Minimal Grafana MCP connection |
| `grafana-basic-bedrock.toml` | Basic | Bedrock | Minimal Grafana MCP connection (AWS Bedrock) |
| `grafana-sre-dashboard.toml` | Use Case | OpenAI | SRE health check (metrics + logs + alerts) |
| `grafana-sre-dashboard-bedrock.toml` | Use Case | Bedrock | SRE health check (AWS Bedrock) |

### Dynatrace (`mcp-servers/dynatrace/`)
| File | Tier | Provider | Description |
|------|------|----------|-------------|
| `dynatrace-basic.toml` | Basic | OpenAI | Minimal Dynatrace MCP connection |
| `dynatrace-basic-bedrock.toml` | Basic | Bedrock | Minimal Dynatrace MCP connection (AWS Bedrock) |
| `dynatrace-explorer.toml` | Explorer | OpenAI | Tool discovery mode for DQL and entities |
| `dynatrace-explorer-bedrock.toml` | Explorer | Bedrock | Tool discovery mode for DQL and entities (AWS Bedrock) |
| `dynatrace-natural-language-query.toml` | Use Case | Anthropic | NL-to-DQL + Davis CoPilot |
| `dynatrace-natural-language-query-bedrock.toml` | Use Case | Bedrock | NL-to-DQL + Davis CoPilot (AWS Bedrock) |
| `dynatrace-k8s-ops.toml` | Use Case | OpenAI | K8s event monitoring and entity health |
| `dynatrace-k8s-ops-bedrock.toml` | Use Case | Bedrock | K8s event monitoring and entity health (AWS Bedrock) |

### New Relic (`mcp-servers/newrelic/`)
| File | Tier | Provider | Description |
|------|------|----------|-------------|
| `newrelic-basic.toml` | Basic | OpenAI | Minimal remote MCP connection (http_streamable) |
| `newrelic-basic-bedrock.toml` | Basic | Bedrock | Minimal remote MCP connection (AWS Bedrock) |
| `newrelic-explorer.toml` | Explorer | OpenAI | Tool discovery mode for NRQL and entities |
| `newrelic-explorer-bedrock.toml` | Explorer | Bedrock | Tool discovery mode for NRQL and entities (AWS Bedrock) |
| `newrelic-deployment-validator.toml` | Use Case | OpenAI | Deployment impact analysis |
| `newrelic-deployment-validator-bedrock.toml` | Use Case | Bedrock | Deployment impact analysis (AWS Bedrock) |
| `newrelic-golden-metrics-review.toml` | Use Case | OpenAI | Multi-service golden metrics health |
| `newrelic-golden-metrics-review-bedrock.toml` | Use Case | Bedrock | Multi-service golden metrics health (AWS Bedrock) |

### AWS Infrastructure Discovery (`mcp-servers/aws/`)
| File | Tier | Provider | Description |
|------|------|----------|-------------|
| `aws-mcp-preflight.toml` | Preflight | Bedrock | Environment validation and stack configuration advisor |
| `aws-mcp-preflight-openai.toml` | Preflight | OpenAI | Environment validation and stack configuration advisor |
| `aws-discovery-agent.toml` | Use Case | Bedrock | Discover and catalog AWS resources into Qdrant KB |
| `aws-discovery-agent-openai.toml` | Use Case | OpenAI | Discover and catalog AWS resources into Qdrant KB |
| `aws-discovery-agent-dev.toml` | Use Case | OpenAI | Discovery agent with local Qdrant (no server needed) |
| `aws-capacity-planning-agent.toml` | Use Case | Bedrock | Quota analysis, scaling headroom, underutilization detection |
| `aws-capacity-planning-agent-openai.toml` | Use Case | OpenAI | Quota analysis, scaling headroom, underutilization detection |
| `aws-change-audit-agent.toml` | Use Case | Bedrock | CloudTrail change detection and risk-rated audit reports |
| `aws-change-audit-agent-openai.toml` | Use Case | OpenAI | CloudTrail change detection and risk-rated audit reports |
| `aws-incident-response-agent.toml` | Use Case | Bedrock | Real-time incident triage and blast radius analysis |
| `aws-incident-response-agent-openai.toml` | Use Case | OpenAI | Real-time incident triage and blast radius analysis |
| `aws-postmortem-agent.toml` | Use Case | Bedrock | Blameless post-mortem construction with timeline reconstruction |
| `aws-postmortem-agent-openai.toml` | Use Case | OpenAI | Blameless post-mortem construction with timeline reconstruction |

### Cross-Platform (`mcp-servers/cross-platform/`)
| File | Tier | Provider | Description |
|------|------|----------|-------------|
| `multi-observability-agent.toml` | Use Case | OpenAI | Datadog + Grafana in one agent |
| `multi-observability-agent-bedrock.toml` | Use Case | Bedrock | Datadog + Grafana in one agent (AWS Bedrock) |

## RAG Examples Inventory

### AWS Knowledge Base (`rag/aws-knowledge-base/`)
| File | Provider | Description |
|------|----------|-------------|
| `aws-kb-query-agent.toml` | Bedrock | Query pre-populated Qdrant KB of AWS resources |
| `aws-kb-query-agent-openai.toml` | OpenAI | Query pre-populated Qdrant KB of AWS resources |

## Common Mistakes in This Directory

| Mistake | Fix |
|---------|-----|
| Hardcoded API key | Replace with `{{ env.VAR }}` |
| Missing provider or model field | Every config needs `[llm]` with `provider` and `model` |
| Wrong transport type string | Use `"http_streamable"` or `"stdio"` |
| No inline comments | Add comments explaining what each section configures |
| Using localhost URLs in Docker examples | Use `host.docker.internal` or Docker network names |
