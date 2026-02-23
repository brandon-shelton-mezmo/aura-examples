# Project Structure

```
aura-examples/
├── CLAUDE.md                          # AI routing table
├── .claude/                           # AI knowledge base
│   ├── agents/                        # Custom agent definitions
│   ├── hooks/                         # Enforcement scripts
│   ├── plans/                         # Session state
│   ├── rules/                         # Always-loaded rules
│   ├── settings.json                  # Hook configuration
│   └── templates/                     # File templates
├── examples/                          # Example configurations
│   ├── CLAUDE.md                      # Examples directory context
│   ├── basic/                         # Minimal getting-started configs
│   ├── providers/                     # Provider-specific configs (OpenAI, Anthropic, Bedrock, etc.)
│   ├── mcp-servers/                   # MCP tool server integration examples
│   ├── rag/                           # RAG / vector store examples
│   └── deployment/                    # Docker, K8s, Helm deployment examples
├── docs/                              # Reference documentation
│   ├── architecture/                  # System design, design decisions
│   ├── examples/                      # Example catalog and guides
│   └── planning/                      # Roadmap, open items
└── ai-project-setup-guide.md          # Source guide for this setup
```

## Key Directories

| Directory | Purpose | Details In |
|-----------|---------|-----------|
| `examples/basic/` | Minimal one-concept examples | `examples/CLAUDE.md` |
| `examples/providers/` | Provider-specific configurations | `examples/CLAUDE.md` |
| `examples/mcp-servers/` | MCP tool integration patterns | `examples/CLAUDE.md` |
| `examples/rag/` | RAG and vector store configs | `examples/CLAUDE.md` |
| `examples/deployment/` | Docker, K8s, Helm patterns | `examples/CLAUDE.md` |
| `docs/` | Reference documentation | Linked from `CLAUDE.md` |

## Example Directory Convention

Every example directory follows:
```
examples/[category]/[example-name]/
├── config.toml          # The aura configuration
├── README.md            # What it demonstrates, how to run
└── [supporting files]   # docker-compose.yml, scripts, etc.
```

Or for single-file examples:
```
examples/[category]/[example-name].toml   # Self-documented via inline comments
```
