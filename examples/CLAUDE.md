# Examples Directory

This directory contains aura agent configuration examples organized by feature category.

## File Inventory

| Directory | Purpose |
|-----------|---------|
| `basic/` | Minimal getting-started examples — one concept each |
| `providers/` | Provider-specific configurations (OpenAI, Anthropic, Bedrock, Gemini, Ollama) |
| `mcp-servers/` | MCP tool server integration patterns (HTTP, SSE, STDIO) |
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

## Common Mistakes in This Directory

| Mistake | Fix |
|---------|-----|
| Hardcoded API key | Replace with `{{ env.VAR }}` |
| Missing provider or model field | Every config needs `[llm]` with `provider` and `model` |
| Wrong transport type string | Use `"http_streamable"`, `"sse"`, or `"stdio"` |
| No inline comments | Add comments explaining what each section configures |
| Using localhost URLs in Docker examples | Use `host.docker.internal` or Docker network names |
