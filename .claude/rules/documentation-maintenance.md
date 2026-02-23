# Documentation Maintenance Rules

## Update Rules

| Change Type | Update These Files |
|-------------|-------------------|
| New example added | `examples/CLAUDE.md` inventory, category README |
| New example category | `examples/CLAUDE.md`, `.claude/rules/project-structure.md`, root `CLAUDE.md` |
| Config schema change in aura | All affected example TOMLs, `docs/` references |
| New design decision | Root `CLAUDE.md` DD table, `docs/architecture/design-decisions.md` |
| New anti-pattern discovered | `.claude/rules/anti-patterns.md` |
| New error pattern found | `.claude/rules/error-recovery.md` |

## Placement Rules

- **Global rules** → `.claude/rules/`
- **Directory-scoped** → `[dir]/CLAUDE.md`
- **Detailed reference** → `docs/[topic]/`
- **Implementation plans** → `.claude/plans/`
- **Example-specific docs** → `examples/[category]/[name]/README.md`

## Cross-Reference Integrity

- All doc-to-doc references MUST use project-root-relative paths
- When moving or renaming a doc, grep for references and update in the same commit
- Broken cross-references are treated as bugs

## Aura Source References

When referencing the aura source, use `~/Documents/GitHub/aura/` as the base path.
Key files to reference:
- Config structs: `~/Documents/GitHub/aura/crates/aura-config/src/config.rs`
- TOML schema docs: `~/Documents/GitHub/aura/docs/toml-schema-design.md`
- Production config: `~/Documents/GitHub/aura/configs/aura-config.toml`
