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
| File | Tier | Description |
|------|------|-------------|
| `datadog-basic.toml` | Basic | Minimal Datadog MCP connection |
| `datadog-explorer.toml` | Explorer | Tool discovery mode for Datadog |
| `datadog-incident-responder.toml` | Use Case | Incident investigation persona |
| `datadog-performance-investigator.toml` | Use Case | Latency and regression analysis |

### OpenTelemetry (`mcp-servers/opentelemetry/`)
| File | Tier | Description |
|------|------|-------------|
| `otel-basic.toml` | Basic | Minimal OTEL MCP connection (Jaeger backend) |
| `otel-explorer.toml` | Explorer | Tool discovery mode for OTEL traces |
| `otel-trace-investigator.toml` | Use Case | Distributed trace debugging |
| `otel-error-analyst.toml` | Use Case | Error pattern detection |

### Grafana (`mcp-servers/grafana/`)
| File | Tier | Description |
|------|------|-------------|
| `grafana-basic.toml` | Basic | Minimal Grafana MCP connection |
| `grafana-sre-dashboard.toml` | Use Case | SRE health check (metrics + logs + alerts) |

### Dynatrace (`mcp-servers/dynatrace/`)
| File | Tier | Description |
|------|------|-------------|
| `dynatrace-basic.toml` | Basic | Minimal Dynatrace MCP connection |
| `dynatrace-explorer.toml` | Explorer | Tool discovery mode for DQL and entities |
| `dynatrace-natural-language-query.toml` | Use Case | NL-to-DQL + Davis CoPilot (Anthropic provider) |
| `dynatrace-k8s-ops.toml` | Use Case | K8s event monitoring and entity health |

### New Relic (`mcp-servers/newrelic/`)
| File | Tier | Description |
|------|------|-------------|
| `newrelic-basic.toml` | Basic | Minimal remote MCP connection (http_streamable) |
| `newrelic-explorer.toml` | Explorer | Tool discovery mode for NRQL and entities |
| `newrelic-deployment-validator.toml` | Use Case | Deployment impact analysis |
| `newrelic-golden-metrics-review.toml` | Use Case | Multi-service golden metrics health |

### Cross-Platform (`mcp-servers/cross-platform/`)
| File | Tier | Description |
|------|------|-------------|
| `multi-observability-agent.toml` | Use Case | Datadog + Grafana in one agent |

## Common Mistakes in This Directory

| Mistake | Fix |
|---------|-----|
| Hardcoded API key | Replace with `{{ env.VAR }}` |
| Missing provider or model field | Every config needs `[llm]` with `provider` and `model` |
| Wrong transport type string | Use `"http_streamable"` or `"stdio"` |
| No inline comments | Add comments explaining what each section configures |
| Using localhost URLs in Docker examples | Use `host.docker.internal` or Docker network names |
