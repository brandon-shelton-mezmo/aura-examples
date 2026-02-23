# Observability MCP Integration — Product Roadmap

**Version:** 1.0 | **Last Updated:** February 2026

## Vision

Enable SREs and developers to investigate production issues, analyze performance, and monitor
system health using natural language — powered by aura agents connected to observability
platforms via MCP.

Instead of context-switching between dashboards, writing query languages, and correlating
data manually, users describe what they need in plain English and the agent handles the rest.

## Target Personas

| Persona | Goals | Key Use Cases |
|---------|-------|---------------|
| **Developer** | Explore observability data during development | Trace debugging, error investigation, log search |
| **SRE** | Investigate incidents and monitor production health | Incident response, golden metrics review, alert triage |
| **Platform Engineer** | Standardize observability agent configs across teams | Config templates, multi-platform governance, deployment patterns |

## Platform Priority

| Priority | Platform | Rationale |
|----------|----------|-----------|
| 1 | **Datadog** | Largest market share in cloud monitoring; mature community MCP server |
| 2 | **OpenTelemetry** | Vendor-neutral standard; growing adoption; Traceloop MCP server |
| 3 | **Grafana** | Popular open-source stack (Prometheus + Loki + Tempo); official MCP server |
| 4 | **Dynatrace** | Enterprise-grade with unique DQL natural language capability; official MCP server |
| 5 | **New Relic** | Remote-hosted MCP (http_streamable) — demonstrates different transport pattern |

## Phased Delivery

### Phase 1 — Basic Connectivity (Current)

Prove that aura agents can connect to each observability platform via MCP and execute basic queries.

| Deliverable | Status |
|-------------|--------|
| Datadog basic + explorer configs | In Progress |
| OpenTelemetry basic + explorer configs | In Progress |
| Grafana basic config | In Progress |
| Dynatrace basic + explorer configs | In Progress |
| New Relic basic + explorer configs | In Progress |
| Platform comparison guide | In Progress |

**Success criteria:** All configs parse valid TOML, required sections present, env var secrets only.

### Phase 2 — Use-Case Configs

Purpose-built agent personas with tailored system prompts and multi-step reasoning.

| Deliverable | Status |
|-------------|--------|
| Datadog incident responder + performance investigator | In Progress |
| OTEL trace investigator + error analyst | In Progress |
| Grafana SRE dashboard persona | In Progress |
| Dynatrace NL-to-DQL + K8s ops personas | In Progress |
| New Relic deployment validator + golden metrics review | In Progress |
| Cross-platform multi-observability agent | In Progress |

**Success criteria:** Each use-case config includes 3+ example prompts and persona-specific system prompt.

### Phase 3 — Advanced Patterns (Future)

| Deliverable | Status |
|-------------|--------|
| Multi-MCP agent combining 3+ observability sources | Planned |
| RAG-enhanced agents with runbook knowledge bases | Planned |
| Deployment-specific configs (Docker Compose, K8s, Helm) | Planned |
| Alert-driven agent workflows (webhook triggers) | Planned |
| Cost optimization agent (cross-platform spend analysis) | Planned |

### Phase 4 — Enterprise Patterns (Future)

| Deliverable | Status |
|-------------|--------|
| RBAC and token rotation patterns | Planned |
| Multi-tenant observability agent configs | Planned |
| Audit logging and compliance patterns | Planned |
| High-availability deployment examples | Planned |

## Success Metrics

| Metric | Target |
|--------|--------|
| TOML validation | 100% of configs pass syntax and schema validation |
| Example prompts | 3+ demo prompts per use-case config |
| Setup time | Under 15 minutes from clone to running agent |
| Platform coverage | 5 platforms with basic + explorer + use-case configs |
| Documentation | Every example has run instructions and prerequisites |

## Dependencies

| Dependency | Risk | Mitigation |
|------------|------|------------|
| Community MCP server stability (`@winor30/mcp-server-datadog`) | Medium — community-maintained | Pin versions in examples; document known-working versions |
| Traceloop OTEL MCP server maturity | Medium — newer project | Test with Jaeger backend; document limitations |
| New Relic MCP preview access | High — requires account approval | Document signup process; mark as preview in README |
| Dynatrace platform token permissions | Low — well-documented | List exact scopes needed in README |
| Grafana MCP server binary availability | Low — official Go binary | Provide install instructions for multiple platforms |

## Out of Scope

- **Custom MCP server development** — examples use existing community and vendor MCP servers only
- **Webhook/push integrations** — aura agents pull data via MCP; push patterns require aura source changes
- **Grafana Cloud specifics** — examples target self-hosted Grafana; Cloud config may differ
- **Provider-specific billing optimization** — configs demonstrate capability, not cost management
- **MCP server source modifications** — examples configure, not extend, MCP servers
