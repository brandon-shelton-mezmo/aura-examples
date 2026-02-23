# Aura Examples

**Version:** 0.1 | **Last Updated:** February 2026

Example configurations and usage patterns for the Mezmo Aura agent framework — a Rust-based AI agent runtime with declarative TOML configuration and MCP tool integration.

## Quick Start

```bash
# Clone this repo alongside the aura source
git clone <this-repo> ~/Documents/GitHub/aura-examples
cd ~/Documents/GitHub/aura-examples

# Aura source is at ~/Documents/GitHub/aura
# Build aura from source (if running examples locally)
cd ~/Documents/GitHub/aura && cargo build --release --bin aura-web-server

# Run an example config
CONFIG_PATH=~/Documents/GitHub/aura-examples/examples/basic/openai-simple.toml \
  ~/Documents/GitHub/aura/target/release/aura-web-server

# Or via Docker
docker run -v $(pwd)/examples/basic/openai-simple.toml:/app/config.toml \
  -e OPENAI_API_KEY=$OPENAI_API_KEY -p 3030:3030 mezmo/aura:latest
```

## Critical Rules

1. **TOML config only** — all examples use aura's TOML config format, no code modifications to aura itself
2. **Env var secrets** — never hardcode API keys; use `{{ env.VAR }}` syntax in TOML configs
3. **Reference aura source** — the aura project at `~/Documents/GitHub/aura` is the authoritative source for config schema
4. **Every example must be self-contained** — include a README, the config TOML, and any required supporting files
5. **Test every example** — validate configs load and the agent starts before committing
6. **Follow the development workflow** — see `.claude/rules/development-workflow.md`

## Key Workflows

### Adding a New Example
1. Copy template: `.claude/templates/new-example.toml`
2. Place in appropriate category under `examples/`
3. Add a README.md to the example directory
4. Validate: `CONFIG_PATH=<path> aura-web-server` starts without errors
5. Update `examples/CLAUDE.md` inventory

### Adding a New Category
1. Create directory under `examples/`
2. Add category README.md
3. Update `docs/` with category documentation
4. Update `.claude/rules/project-structure.md`

## Design Decisions (DD-01 through DD-06)

| ID | Summary |
|----|---------|
| DD-01 | Examples repo is separate from aura source — keeps examples independent of release cycle |
| DD-02 | TOML config is the only interface — no Rust code in examples, only configuration |
| DD-03 | Examples organized by feature category (basic, providers, mcp-servers, rag, deployment) |
| DD-04 | Every example includes inline TOML comments explaining each setting |
| DD-05 | Env var resolution via `{{ env.VAR }}` for all secrets and environment-specific values |
| DD-06 | Docker and local run instructions provided for every example |

Full details: `docs/architecture/design-decisions.md`

## Reference Documents

| Category | Key Documents |
|----------|--------------|
| Aura Config Schema | `~/Documents/GitHub/aura/docs/toml-schema-design.md` |
| Aura README | `~/Documents/GitHub/aura/README.md` |
| Streaming API | `~/Documents/GitHub/aura/docs/streaming-api-guide.md` |
| Examples Catalog | `docs/examples/` |
| Architecture | `docs/architecture/` |

## Directory-Specific Context

Each directory has a `CLAUDE.md` loaded automatically when working in that directory.
Key directories: `examples/`, `docs/`.

## Always-Loaded Rules (`.claude/rules/`, 10 files)

| File | Content |
|------|---------|
| `technology-decisions.md` | Locked stack: aura TOML config, supported providers |
| `architecture.md` | Examples repo structure and patterns |
| `domain-context.md` | Aura concepts, MCP, providers glossary |
| `anti-patterns.md` | Common config mistakes to avoid |
| `canonical-patterns.md` | Reference configs and templates |
| `development-workflow.md` | Minimal 3-phase workflow for examples |
| `testing-strategy.md` | How to validate example configs |
| `documentation-maintenance.md` | Doc update rules |
| `project-structure.md` | Annotated directory tree |
| `error-recovery.md` | Common aura startup failures and fixes |

## Custom Agents (`.claude/agents/`, 2 agents)

| Agent | Purpose |
|-------|---------|
| `aura-config-expert` | Validates TOML configs against aura schema |
| `example-reviewer` | Checks example completeness (README, comments, validation) |

Templates in `.claude/templates/`: `new-example.toml`, `task-context.md`
Plans in `.claude/plans/`. After compaction/restart: `TaskList` + read `ctx-{branch}.md`.
