# Architecture Rules

## Examples Repository Pattern

This repository contains only configuration examples and documentation — no Rust source
code. The aura binary is built from `~/Documents/GitHub/aura` and runs with config files
from this repo.

## Example Structure

Every example MUST follow this structure:

| Component | Required | Purpose |
|-----------|----------|---------|
| `config.toml` (or descriptive name) | Yes | The aura TOML configuration |
| `README.md` | Yes | What the example demonstrates, prerequisites, how to run |
| Supporting files (docker-compose, scripts) | If needed | Additional infrastructure |

## Configuration Hierarchy

Aura configs have these top-level sections:

| Section | Purpose | Required |
|---------|---------|----------|
| `[llm]` | LLM provider, model, API key | Yes |
| `[agent]` | Agent name, system prompt, behavior | Yes |
| `[mcp]` | Global MCP settings | Only if using MCP tools |
| `[mcp.servers.*]` | Individual MCP server connections | Only if using MCP tools |
| `[[vector_stores]]` | RAG vector store backends | Only if using RAG |
| `[tools]` | Built-in tool settings | Optional |

## Env Var Resolution

All secrets and environment-specific values MUST use aura's env var syntax:
- Correct: `api_key = "{{ env.OPENAI_API_KEY }}"`
- Wrong: `api_key = "sk-abc123..."`

## Provider-Specific Patterns

| Provider | Auth Config | Model Format |
|----------|------------|--------------|
| OpenAI | `api_key = "{{ env.OPENAI_API_KEY }}"` | `model = "gpt-4o"` |
| Anthropic | `api_key = "{{ env.ANTHROPIC_API_KEY }}"` | `model = "claude-sonnet-4-20250514"` |
| Bedrock | Uses AWS credentials chain | `model = "us.anthropic.claude-sonnet-4-20250514-v1:0"` |
| Gemini | `api_key = "{{ env.GEMINI_API_KEY }}"` | `model = "gemini-2.0-flash"` |
| Ollama | No auth needed (local) | `model = "llama3.2"` |
