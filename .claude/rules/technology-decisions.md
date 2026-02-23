# Locked Technology Decisions

These decisions are FINAL. Do not propose alternatives, evaluate other options,
or introduce different libraries.

## Core Stack

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Agent Framework | Mezmo Aura (Rust) | Production aura runtime at `~/Documents/GitHub/aura` |
| Configuration | TOML files | Aura's declarative config format — no code needed |
| LLM Providers | OpenAI, Anthropic, AWS Bedrock, Google Gemini, Ollama | Aura's supported providers via `[llm]` config |
| Tool Protocol | MCP (Model Context Protocol) | Aura's tool integration layer via `[mcp.servers.*]` |
| MCP Transports | HTTP Streamable, SSE, STDIO | Three transport types supported by aura |
| Vector Stores | In-memory, Qdrant | Aura's supported RAG backends |
| API Format | OpenAI-compatible (`/v1/chat/completions`) | Aura-web-server exposes this API |
| Container Runtime | Docker | For running aura with example configs |
| Documentation | Markdown | All docs and READMEs |

## Aura Source Reference

The aura project is located at `~/Documents/GitHub/aura`. Key reference files:

| File | Contains |
|------|----------|
| `crates/aura-config/src/config.rs` | All config struct definitions |
| `docs/toml-schema-design.md` | TOML schema reference |
| `configs/aura-config.toml` | Production config example |
| `README.md` | Feature overview and usage |

## Rejected Alternatives

| Rejected | Why |
|----------|-----|
| Writing Rust code in examples | Examples demonstrate configuration only (DD-02) |
| Python/JS wrapper scripts | Adds complexity; TOML + Docker is sufficient |
| YAML or JSON config | Aura uses TOML exclusively |
| Hardcoded API keys | Security risk; use `{{ env.VAR }}` resolution |
