# Canonical Patterns

When implementing a common pattern, **copy from the canonical reference file**
rather than writing from scratch.

## Reference Files

| Pattern | Canonical File | Template |
|---------|---------------|----------|
| Basic OpenAI config | `examples/basic/openai-simple.toml` | `.claude/templates/new-example.toml` |
| MCP server connection | `examples/mcp-servers/` (first example created) | `.claude/templates/new-example.toml` |
| RAG-enabled agent | `examples/rag/` (first example created) | `.claude/templates/new-example.toml` |
| Aura production config | `~/Documents/GitHub/aura/configs/aura-config.toml` | — |
| Test config reference | `~/Documents/GitHub/aura/crates/aura-web-server/tests/test-config.toml` | — |
| Task context | — | `.claude/templates/task-context.md` |

## When to Use Templates vs References

- **New example from scratch** — Start with `.claude/templates/new-example.toml`
- **New example similar to existing** — Copy the closest existing example and modify
- **Unfamiliar with aura config** — Read `~/Documents/GitHub/aura/docs/toml-schema-design.md` first

## Change Summary Format

After any implementation, produce:

```markdown
## Change Summary
- **Files modified:** (list with brief description)
- **Examples added/modified:** (list with what they demonstrate)
- **Documentation updated:** (list affected docs)
- **Config validated:** (yes/no — did aura-web-server start with the config?)
```
