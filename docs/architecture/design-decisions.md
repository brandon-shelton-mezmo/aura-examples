# Design Decisions

## DD-01: Separate Examples Repository

**Decision:** Example configurations live in a separate repository from the aura source.

**Rationale:** Keeps examples independent of the aura release cycle. Examples can be
updated, reorganized, and expanded without requiring aura releases. Users can clone
just the examples without the full Rust codebase.

**Alternatives considered:**
- Examples inside the aura repo — rejected because it couples example evolution to code releases
- Examples as a git submodule — rejected because it adds friction for users

**Implications:**
- Examples must reference the aura binary externally (Docker image or local build)
- Config schema changes in aura may require updating examples

---

## DD-02: TOML Config as Only Interface

**Decision:** Examples contain only TOML configuration files and documentation — no Rust code.

**Rationale:** The target audience (developers, SREs) should not need to write Rust to
deploy an aura agent. TOML configuration is aura's primary interface.

**Alternatives considered:**
- Rust code examples showing embedded usage — rejected for this repo (belongs in aura docs)
- Python/JS wrapper examples — rejected as unnecessary complexity

**Implications:**
- Every feature demonstrated must be expressible through TOML config
- If a use case requires code, it belongs in aura's documentation, not here

---

## DD-03: Category-Based Organization

**Decision:** Examples are organized by feature category: basic, providers, mcp-servers, rag, deployment.

**Rationale:** Users typically search by what they want to do (connect to Bedrock, add MCP tools,
deploy with Docker) rather than by complexity level.

**Alternatives considered:**
- Organization by difficulty level — rejected because it's subjective and hard to maintain
- Flat directory — rejected because it doesn't scale past 10 examples

**Implications:**
- Some examples could fit multiple categories — place in the primary category
- Each category has its own README with an index

---

## DD-04: Self-Documenting Configs

**Decision:** Every example TOML file includes inline comments explaining each setting.

**Rationale:** Comments make configs usable without requiring a separate doc lookup.
Users can read and modify configs directly.

**Implications:**
- Configs are longer but more accessible
- Comments must be maintained when updating configs

---

## DD-05: Env Var Resolution for Secrets

**Decision:** All secrets use aura's `{{ env.VAR }}` syntax, never hardcoded values.

**Rationale:** Security. API keys must never be committed to git.

**Implications:**
- Every example README must list required env vars
- Users must set env vars before running examples

---

## DD-06: Dual Run Instructions

**Decision:** Every example provides both local (binary) and Docker run instructions.

**Rationale:** Some users build aura from source, others use the Docker image.
Both paths must be documented.

**Implications:**
- Docker examples need attention to volume mounts and networking
- Local examples need build instructions or binary path
