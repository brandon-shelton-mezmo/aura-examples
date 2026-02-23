# Development Workflow

## Workflow Profile: Minimal

This is an examples/documentation repository. Use the minimal workflow unless
the change is architecturally significant.

| Change Size | Workflow |
|-------------|----------|
| New example or doc update | Phase 3 → 3.5 → 6 |
| New category or structural change | Phase 1 → 2 → 3 → 3.5 → 4 → 6 |
| Fixing a broken example | Phase 3 → 3.5 → 6 |

## Phase 3 — Implement

1. Copy from template or existing example
2. Fill in configuration values with inline comments
3. Write README.md for the example
4. Ensure env vars use `{{ env.VAR }}` syntax

## Phase 3.5 — Validate (Gate)

Every example MUST pass validation before proceeding:

```bash
# 1. Check TOML syntax
python3 -c "import tomllib; tomllib.load(open('path/to/config.toml', 'rb'))"

# 2. If aura is built locally, test startup
CONFIG_PATH=path/to/config.toml timeout 10 aura-web-server 2>&1 || true
# (Will fail if provider API key missing — that's OK, check for config parse errors only)

# 3. If Docker examples, test compose up
docker compose -f path/to/docker-compose.yml config
```

**Only proceed if TOML parses and config is structurally valid.**

## Phase 4 — Review (For Significant Changes)

Launch review agents when making structural changes:

### Mandatory Agent Triggers

| Agent | MUST Use When | Phase |
|-------|--------------|-------|
| `aura-config-expert` | Any TOML config changes | Review (4) |
| `example-reviewer` | Any new example | Review (4) |

## Phase 6 — Ship

1. Update `examples/CLAUDE.md` if examples changed
2. Update `docs/` if new patterns introduced
3. Stage specific files (never `git add -A`)
4. Create PR with description of what examples were added/changed

## Context File Rules

For multi-file changes, create `.claude/plans/ctx-{branch}.md` from template.
Update at every phase boundary. Delete after merge.
