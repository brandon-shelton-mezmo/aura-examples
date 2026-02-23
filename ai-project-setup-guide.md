# Architecting a Project for AI-Driven Development with Claude Code

> A comprehensive guide for structuring any software project so Claude Code can work as an effective autonomous collaborator — from day one through production maturity.

**Based on:** Patterns extracted from a production multi-tenant platform with dozens of design decisions, 15 rules files, 5 custom agents, 120+ integration tests, and a 7-phase development workflow.

---

## Table of Contents

- [Part 1: Foundations](#part-1-foundations)
  - [1. Why This Architecture](#1-why-this-architecture)
  - [2. Directory Structure](#2-directory-structure)
  - [3. Three-Tier Documentation Hierarchy](#3-three-tier-documentation-hierarchy)
- [Part 2: The Files You Write First](#part-2-the-files-you-write-first)
  - [4. Root CLAUDE.md](#4-root-claudemd)
  - [5. Rules Files](#5-rules-files)
  - [6. Design Decisions Registry](#6-design-decisions-registry)
  - [7. Templates](#7-templates)
- [Part 3: Agents and Workflow](#part-3-agents-and-workflow)
  - [8. Custom Agents](#8-custom-agents)
  - [9. Seven-Phase Workflow](#9-seven-phase-workflow)
  - [10. Task Context Files](#10-task-context-files)
- [Part 4: Enforcement and Quality](#part-4-enforcement-and-quality)
  - [11. Hooks](#11-hooks)
  - [12. Quality Patterns](#12-quality-patterns)
  - [13. PR and Release Format](#13-pr-and-release-format)
- [Part 5: Appendix](#part-5-appendix)
  - [14. Scaffold Script](#14-scaffold-script)
  - [15. Setup Order](#15-setup-order)
  - [16. Readiness Checklist](#16-readiness-checklist)

---

# Part 1: Foundations

## 1. Why This Architecture

### The Problem: AI Amnesia

Claude Code starts every session with zero memory. It doesn't know your stack, your conventions, your past decisions, or why you chose PostgreSQL over MongoDB. Every session is a blank slate.

Without encoded knowledge, you'll spend the first 10 minutes of every session re-explaining the same rules. Worse, the AI will make reasonable-but-wrong suggestions that violate decisions you made weeks ago. It will propose Prisma when you've already rejected ORMs. It will use `ID!` when your project uses `UUID!`. It will add soft deletes when your policy is physical deletes with audit logs.

### The Solution: File-Encoded Knowledge

The architecture in this guide turns your project's decisions, conventions, and constraints into files that Claude Code reads automatically. The AI gets the same context every session, without you saying a word.

### Three Principles

| Principle | What It Means |
|-----------|---------------|
| **Decisions as data** | Every architectural choice is written in a file, not stored in your head. Design decisions get IDs (DD-01, DD-02) and are referenced everywhere. |
| **Layered context** | Not everything loads every time. Critical rules load always; directory-specific context loads on demand. This respects context window limits. |
| **Enforcement over reminders** | Hooks, agents, and checklists catch violations automatically. You shouldn't need to say "remember to update the docs" — the system should catch it. |

### What You Get

- **Consistent behavior** — The AI follows the same rules whether it's your first session or your fiftieth
- **Reduced re-explanation** — Rules files eliminate repetitive prompting
- **Guardrails on autopilot** — Hooks block bad commits; agents catch convention violations
- **Recoverable state** — Context files survive session restarts and context window compaction
- **Scalable knowledge** — New team members (human or AI) onboard by reading the same files

---

## 2. Directory Structure

The `.claude/` directory is the AI's knowledge base. Everything the AI needs to know about your project lives here or is referenced from here.

```
your-project/
├── CLAUDE.md                          # Routing table — always loaded (150-line limit)
│
├── .claude/
│   ├── agents/                        # Custom agent definitions
│   │   ├── [domain]-expert.md         # Domain-specific validation agent
│   │   ├── [layer]-guardian.md        # Convention enforcement agent
│   │   └── [pattern]-checker.md       # Consistency verification agent
│   │
│   ├── hooks/                         # Shell scripts for enforcement
│   │   ├── doc-check.sh               # Documentation sync validation
│   │   └── review-check.sh            # Review phase enforcement
│   │
│   ├── plans/                         # Persistent state across sessions
│   │   ├── ctx-feature-xxx.md         # Per-branch task context (ephemeral, gitignored)
│   │   ├── phase1-*.md / phase4-*.md  # Agent outputs (ephemeral, gitignored)
│   │   └── [plan-name].md             # Long-lived implementation plans (committed)
│   │
│   ├── rules/                         # Always-loaded domain knowledge
│   │   ├── technology-decisions.md    # Locked stack, rejected alternatives
│   │   ├── architecture.md            # System architecture rules
│   │   ├── database-conventions.md    # Column standards, indexing patterns
│   │   ├── api-conventions.md         # API/schema design patterns
│   │   ├── domain-context.md          # Business domain, glossary, identifiers
│   │   ├── status-lifecycles.md       # Entity state machines
│   │   ├── anti-patterns.md           # Known mistakes — DO NOT / DO INSTEAD
│   │   ├── canonical-patterns.md      # Reference files + templates index
│   │   ├── development-workflow.md    # Multi-phase dev cycle
│   │   ├── testing-strategy.md        # Test philosophy, tools, patterns
│   │   ├── ui-testing-strategy.md     # E2E / interactive UI testing rules
│   │   ├── external-integrations.md   # External service layer architecture
│   │   ├── documentation-maintenance.md # Doc hierarchy, update rules
│   │   ├── project-structure.md       # Directory tree with annotations
│   │   └── error-recovery.md          # Common failures + fixes
│   │
│   ├── settings.json                  # Hook configuration
│   │
│   └── templates/                     # Copy-ready boilerplate
│       ├── new-[entity].ext           # File templates for common patterns
│       └── task-context.md            # Context file template
│
├── docs/                              # Detailed reference documentation
│   ├── architecture/                  # System design docs
│   ├── data-model/                    # Entity reference, design decisions
│   └── planning/                      # Roadmap, open items, scorecard
│
├── src/                               # Source code
│   ├── [module]/CLAUDE.md             # Directory-level context (200-line limit)
│   └── ...
│
└── tests/
    └── CLAUDE.md                      # Test-specific conventions
```

### Key Directories Explained

| Directory | Purpose | Who Writes | When Read |
|-----------|---------|-----------|-----------|
| `.claude/rules/` | Non-negotiable project rules | You (human) | Every session (auto-loaded) |
| `.claude/agents/` | Custom agent definitions | You (human) | When agent is triggered |
| `.claude/hooks/` | Enforcement scripts | You (human) | Pre-tool-use events |
| `.claude/plans/` | Session-surviving state (two kinds — see below) | Both | Cross-session handoff + long-term plans |
| `.claude/templates/` | Boilerplate for new files | You (human) | When creating new files |
| `[dir]/CLAUDE.md` | Directory-scoped context | You (human) | When working in that directory |

### Gitignore Patterns

Add these to your `.gitignore` — context files and agent outputs are ephemeral:

```gitignore
# Claude Code ephemeral files
.claude/plans/ctx-*
.claude/plans/phase1-*
.claude/plans/phase4-*
.playwright-screenshots/
```

---

## 3. Three-Tier Documentation Hierarchy

Not all context is equal. Some rules must load every session; others only matter when you're working in a specific directory. The three-tier hierarchy balances completeness against context window efficiency.

### The Three Tiers

| Tier | Location | Loaded | Size Limit | Purpose |
|------|----------|--------|------------|---------|
| **1. Routing table** | Root `CLAUDE.md` | Always (every session) | 150 lines | Quick-start, critical rules, links to everything |
| **2. Domain rules** | `.claude/rules/*.md` | Always (every session) | 150 lines each | Non-negotiable conventions, patterns, anti-patterns |
| **3. Directory context** | `[dir]/CLAUDE.md` | On-demand (when working in that dir) | 200 lines each | Module-specific conventions, file inventories |

### Why Size Limits Matter

Claude Code's context window is finite. If your `CLAUDE.md` is 500 lines, it competes with actual code for space. Strict limits force you to:

1. **Be concise** — Tables over prose. IDs over paragraphs.
2. **Link, don't inline** — Put details in `docs/`, reference from rules.
3. **Tier appropriately** — Only globally-relevant rules go in always-loaded files.

### Overflow Extraction Pattern

When ANY tiered file exceeds its limit — including `CLAUDE.md` (150 lines), rules files (150 lines each), and directory `CLAUDE.md` files (200 lines each):

1. Extract the overflowing section into a detailed document under `docs/`
2. Replace the extracted section with a one-line link: `Full details: docs/[topic]/[file].md`
3. Grep the repo for any references to the removed heading or content
4. Update references in the same commit

This pattern applies to all three tiers. Rules files in `.claude/rules/` hit the 150-line limit most often as conventions accumulate — extract detailed reference tables into `docs/` and keep the rules file as a concise summary with links.

### Cross-Reference Integrity

- All doc-to-doc references MUST use project-root-relative paths
- When moving or renaming a doc, grep for references and update in the same commit
- Broken cross-references are treated as bugs

### Example Tier Distribution

```
ALWAYS LOADED (Tier 1+2):
  CLAUDE.md (routing table)               ← 150 lines max
  .claude/rules/technology-decisions.md    ← 150 lines max
  .claude/rules/architecture.md            ← 150 lines max
  .claude/rules/database-conventions.md    ← 150 lines max
  .claude/rules/anti-patterns.md           ← 150 lines max
  ... (all rules/*.md files)

ON-DEMAND (Tier 3):
  src/resolvers/CLAUDE.md                  ← 200 lines max, only when editing resolvers
  migrations/CLAUDE.md                     ← 200 lines max, only when editing migrations
  tests/CLAUDE.md                          ← 200 lines max, only when editing tests

NEVER AUTO-LOADED (linked references):
  docs/data-model/design-decisions.md      ← Full DD details, any length
  docs/architecture/stack.md               ← Detailed architecture, any length
  docs/planning/production-roadmap.md      ← Roadmap, any length
```

---

# Part 2: The Files You Write First

## 4. Root CLAUDE.md

The root `CLAUDE.md` is the most important file in the entire architecture. It loads every session and tells Claude Code what this project is, what rules to follow, and where to find everything else.

**Hard limit: 150 lines.** This is a routing table, not a novel.

### Annotated Skeleton

Copy this skeleton and fill in the `[placeholders]`:

```markdown
# [YourProject]

**Version:** [X.Y] | **Last Updated:** [Month Year]

[1-2 sentence description of what the project does and who it serves.]

## Quick Start

\```bash
[install command]            # Install dependencies
[env setup]                  # Set up environment
[database start]             # Start database
[migration command]          # Run migrations
[seed command]               # Seed data
[dev command]                # Start development server
\```

## Critical Rules

These are non-negotiable. Detailed rationale lives in `.claude/rules/`.

1. **[Stack declaration]** — locked stack, no alternatives
2. **[API approach]** — [schema-first / code-first / etc.]
3. **[Security model]** — [how isolation/auth works]
4. **[Data access pattern]** — [ORM/query builder/raw SQL]
5. **[Testing mandate]** — [real DB / mocks / etc.]
6. **[Enum strategy]** — [CHECK constraints / TypeScript unions / etc.]
7. **[Delete strategy]** — [soft / physical / archive]
8. **[Follow the N-phase development workflow]** — see `.claude/rules/development-workflow.md`

## Key Workflows

### Adding a [Primary Entity]
1. [Step 1]
2. [Step 2]
3. See `[dir]/CLAUDE.md` for full checklist

### Adding a [Secondary Pattern]
1. [Step 1]
2. [Step 2]

## Design Decisions (DD-01 through DD-[NN])

| ID | Summary |
|----|---------|
| DD-01 | [Decision summary] |
| DD-02 | [Decision summary] |
| ... | ... |

Full details: `docs/[topic]/design-decisions.md`

## Reference Documents

| Category | Key Documents |
|----------|--------------|
| Schema | `[schema-dir]/` |
| Data Model | `docs/data-model/` |
| Architecture | `docs/architecture/` |
| Planning | `docs/planning/` |

## Directory-Specific Context

Each directory has a `CLAUDE.md` loaded automatically when working in that directory.
Key directories: `[list your main source directories]`.

## Always-Loaded Rules (`.claude/rules/`, [N] files)

| File | Content |
|------|---------|
| `technology-decisions.md` | Locked stack + rejected alternatives |
| `architecture.md` | [Brief description] |
| `database-conventions.md` | [Brief description] |
| ... | ... |

## Custom Agents (`.claude/agents/`, [N] agents)

| Agent | Purpose |
|-------|---------|
| `[domain]-expert` | [What it validates] |
| `[layer]-guardian` | [What it enforces] |

Templates in `.claude/templates/`: [list template files]
Plans in `.claude/plans/`. After compaction/restart: `TaskList` + read `ctx-{branch}.md`.
```

### What Goes in CLAUDE.md vs Rules Files

| Content | Goes In |
|---------|---------|
| Project identity (name, version, description) | `CLAUDE.md` |
| Quick start commands | `CLAUDE.md` |
| Critical rules (numbered, 1-sentence each) | `CLAUDE.md` |
| Design decision index (ID + summary) | `CLAUDE.md` |
| Reference document links | `CLAUDE.md` |
| Agent and template inventories | `CLAUDE.md` |
| Detailed conventions with tables | `.claude/rules/` |
| Column type standards | `.claude/rules/database-conventions.md` |
| Anti-pattern lists | `.claude/rules/anti-patterns.md` |
| Full design decision rationale | `docs/data-model/design-decisions.md` |

---

## 5. Rules Files

Rules files are the backbone of your AI-encoded knowledge. Each file covers one domain and is loaded every session. They tell Claude Code what to do, what not to do, and why.

### Rules File Anatomy

Every rules file follows the same structure:

```markdown
# [Domain] Rules

## [Topic 1]

| Pattern | Correct | Wrong |
|---------|---------|-------|
| [thing] | [do this] | [not this] |

## [Topic 2]

[Brief explanation, then table or list]

## [Topic 3]

| DO NOT | DO INSTEAD | Why |
|--------|-----------|-----|
| [anti-pattern] | [correct pattern] | [reason] |
```

**Key formatting principles:**
- **Tables over prose** — Scannable, unambiguous, hard to misinterpret. Tables are the highest-signal format for AI consumption — a table with explicit right/wrong columns is unambiguous in a way that prose paragraphs never are.
- **"Correct vs Wrong" columns** — The most effective format for conventions. Leave zero room for interpretation. The AI sees `Correct: X / Wrong: Y` and follows it exactly.
- **"DO NOT / DO INSTEAD / Why" format** — For anti-patterns. The three-column structure forces you to explain not just what's wrong, but what's right and why — which makes the rule stick.
- **Templates are copy-ready** — Include the exact code/SQL/config to use. The AI can copy and paste, not interpret and guess.

### The Complete Rules File Set

Below are all 15 rules files you should create, with generic examples for each. Start with the ones most relevant to your project and add more over time. Not every project needs all 15 on day one — see [Section 15](#15-setup-order) for the recommended adoption order.

---

### 5.1 technology-decisions.md

Lock your stack decisions so the AI never proposes alternatives.

```markdown
# Locked Technology Decisions

These decisions are FINAL. Do not propose alternatives, evaluate other options,
or introduce different libraries.

## Core Stack

| Layer | Choice | Rationale |
|-------|--------|-----------|
| Language | [TypeScript / Python / Go / etc.] | [Why] |
| Framework | [Next.js / Django / Gin / etc.] | [Why] |
| Database | [PostgreSQL / MySQL / etc.] | [Why] |
| ORM / Query Builder | [Kysely / SQLAlchemy / GORM / etc.] | [Why] |
| API Style | [GraphQL / REST / gRPC] | [Why] |
| Testing | [Vitest / pytest / go test] | [Why] |
| Package Manager | [npm / uv / go modules] | [Why] |
| Auth Provider | [Cognito / Auth0 / Clerk / etc.] | [Why] |

## Rejected Alternatives

| Rejected | Why |
|----------|-----|
| [Alternative 1] | [Specific reason it was rejected] |
| [Alternative 2] | [Specific reason it was rejected] |
```

---

### 5.2 architecture.md

Document your system's structural rules — connection patterns, middleware behavior, security boundaries.

```markdown
# Architecture Rules

## [Primary Architecture Pattern]

[2-3 sentence description of the core architectural pattern.]

## [Connection/Data Access Strategy]

| Setting | Value | Rationale |
|---------|-------|-----------|
| [Config 1] | [Value] | [Why] |
| [Config 2] | [Value] | [Why] |

## [Security Model]

- [Rule 1]: [Where security enforcement happens]
- [Rule 2]: [What resolvers/handlers must NOT do]
- [Rule 3]: [What middleware handles]

## [Data Loading Strategy]

[E.g., "ALL child collection resolvers MUST batch via DataLoader.
Create new instances per request, not global."]
```

---

### 5.3 database-conventions.md

Column standards, naming conventions, required columns on every table, indexing patterns.

```markdown
# Database Conventions

## Column Standards

| Column | Correct | Wrong |
|--------|---------|-------|
| Timestamps | `TIMESTAMPTZ NOT NULL DEFAULT now()` | `TIMESTAMP`, `DATETIME` |
| Primary keys | `UUID PRIMARY KEY DEFAULT gen_random_uuid()` | `SERIAL`, `BIGSERIAL` |
| Booleans | `BOOLEAN NOT NULL DEFAULT false` | `CHAR(1)`, `INTEGER` |
| Enums | `CHECK (col IN ('a', 'b', 'c'))` | `CREATE TYPE AS ENUM` |
| [Domain-specific 1] | [Correct] | [Wrong] |
| [Domain-specific 2] | [Correct] | [Wrong] |

## Every Table Requires

1. [Required column 1 with exact definition]
2. [Required column 2 with exact definition]
3. [Required trigger or policy]
4. [Required index]

**Exceptions:** [List any tables that deviate and why]

## [Security Policy Template]

\```sql
-- Copy this exactly for every new table
[Your RLS policy / access control template]
\```

## Delete Strategy

- **Default:** [CASCADE / RESTRICT / etc.]
- **[Exception case]:** [Different strategy]
- **No soft deletes** [or whatever your policy is]

## Indexing Patterns

| Pattern | When to Use |
|---------|-------------|
| [Index type 1] | [Condition] |
| [Index type 2] | [Condition] |
```

---

### 5.4 api-conventions.md

Your API design patterns — type naming, pagination, error handling, input/output consistency.

```markdown
# API Conventions

## Type Naming

| Pattern | Correct | Wrong |
|---------|---------|-------|
| [Entity types] | `[FullName]` | `[Abbreviated]` |
| [Pagination] | [Your pattern] | [Anti-pattern] |
| [Inputs] | `[InputNaming]` | [Anti-pattern] |
| [IDs] | [Your ID type] | [Wrong ID type] |

## [Schema / API Design] Workflow

1. [Step 1 — define types/schema]
2. [Step 2 — generate code]
3. [Step 3 — implement handlers]
4. Never [do this thing that breaks the workflow]

## Pagination Enforcement

[Your pagination rules — e.g., max page size, default page size]

## Error Handling

- [Error type 1]: [How to handle]
- [Error type 2]: [How to handle]
- [Error type 3]: [How to handle]

## Enum Casing

DB: [your DB casing]. API: [your API casing]. [Where transforms happen.]
```

---

### 5.5 domain-context.md

The business domain your project lives in. Identifiers, entities, glossary, stakeholders.

```markdown
# Domain Context

## Project Overview

[2-3 paragraphs: What the project does, who uses it, why it exists.]

## Key Entities

| Entity | Identifies | Key Fields |
|--------|------------|------------|
| [Entity 1] | [What it represents] | [Important fields] |
| [Entity 2] | [What it represents] | [Important fields] |

## Industry Identifiers

| Identifier | Format | Identifies |
|------------|--------|------------|
| [ID type 1] | [Format/pattern] | [What it identifies] |
| [ID type 2] | [Format/pattern] | [What it identifies] |

## System Boundaries

- [YourProject] does [this]
- [YourProject] does NOT [that] — [external system] handles it
- Deferred features designed for but NOT built: [list]

## Quick Glossary

| Term | Means | NOT |
|------|-------|----|
| [Term 1] | [Correct meaning] | [Common misunderstanding] |
| [Term 2] | [Correct meaning] | [Common misunderstanding] |

## Who Uses the Platform

| Persona | Role | Primary Needs |
|---------|------|---------------|
| [User 1] | [Role] | [What they need] |
| [User 2] | [Role] | [What they need] |
```

---

### 5.6 status-lifecycles.md

Entity state machines — what states exist, what transitions are valid.

```markdown
# Status Lifecycles

## [Primary Entity] Status

\```
draft -> active -> archived
           |
       suspended
\```

- `draft`: [Definition]
- `active`: [Definition]
- `suspended`: [Definition]
- `archived`: [Definition]

## [Secondary Entity] Status

\```
pending -> approved -> completed
              |
          rejected
\```
```

---

### 5.7 anti-patterns.md

The most impactful rules file. Prevents the AI from reintroducing mistakes you've already fixed.

```markdown
# Anti-Patterns

Caught across [N] rounds of review. Do not reintroduce.

## Database

| DO NOT | DO INSTEAD | Why |
|--------|-----------|-----|
| [Bad pattern 1] | [Correct pattern] | [Why it's bad] |
| [Bad pattern 2] | [Correct pattern] | [Why it's bad] |

## API / Schema

| DO NOT | DO INSTEAD | Why |
|--------|-----------|-----|
| [Bad pattern 1] | [Correct pattern] | [Why it's bad] |
| [Bad pattern 2] | [Correct pattern] | [Why it's bad] |

## Implementation

| DO NOT | DO INSTEAD | Why |
|--------|-----------|-----|
| [Bad pattern 1] | [Correct pattern] | [Why it's bad] |
| [Bad pattern 2] | [Correct pattern] | [Why it's bad] |
```

---

### 5.8 canonical-patterns.md

Points to the canonical "copy from this file" references and available templates.

```markdown
# Canonical Patterns

When implementing a common pattern, **copy from the canonical reference file**
rather than writing from scratch.

## Reference Files

| Pattern | Canonical File | Template |
|---------|---------------|----------|
| [Pattern 1] | `path/to/reference-file` | `.claude/templates/new-[pattern].ext` |
| [Pattern 2] | `path/to/reference-file` | -- |
| [Pattern 3] | `path/to/reference-file` | `.claude/templates/new-[pattern].ext` |

## When to Use Templates vs References

- **New file from scratch** → Start with the template from `.claude/templates/`
- **Adding to an existing pattern** → Copy the structure from the canonical file
- **Unfamiliar with a pattern** → Read the canonical file first, then implement
```

---

### 5.9 development-workflow.md

The multi-phase development cycle. See [Section 9](#9-seven-phase-workflow) for the full breakdown.

---

### 5.10 testing-strategy.md

How your project tests things.

```markdown
# Testing Strategy

## Philosophy

- [Real database / mocks / both]
- [Integration-first / unit-first]
- [What MUST be tested vs what's optional]

## Test Categories

| Category | What It Tests | Required For |
|----------|---------------|--------------|
| [Category 1] | [Scope] | [When required] |
| [Category 2] | [Scope] | [When required] |

## Running Tests

\```bash
[test command]              # All tests
[test command subset]       # Specific subset
\```

## Do NOT

- [Testing anti-pattern 1]
- [Testing anti-pattern 2]
```

---

### 5.11 documentation-maintenance.md

Rules for keeping documentation in sync.

```markdown
# Documentation Maintenance Rules

## Update Rules

| Change Type | Update These Files |
|-------------|-------------------|
| [Change 1] | [File A] and [File B] |
| [Change 2] | [File C] |

## Placement Rules

- **Global rules** → `.claude/rules/`
- **Directory-scoped** → `[dir]/CLAUDE.md`
- **Detailed reference** → `docs/[topic]/`
- **Implementation plans** → `.claude/plans/`
```

---

### 5.12 project-structure.md

Annotated directory tree.

```markdown
# Project Structure

\```
your-project/
├── CLAUDE.md                  # AI routing table
├── .claude/                   # AI knowledge base
├── src/                       # Source code
│   ├── [module-1]/            # [Purpose]
│   └── [module-2]/            # [Purpose]
├── tests/                     # Test suite
└── docs/                      # Reference documentation
\```

## Key Directories

| Directory | Files | Details In |
|-----------|-------|-----------|
| `[dir-1]/` | [count] files | `[dir-1]/CLAUDE.md` |
| `[dir-2]/` | [count] files | `[dir-2]/CLAUDE.md` |

## Generated Files (Do Not Edit)

| File | Generated By | Source |
|------|-------------|--------|
| `[generated-1]` | `[tool]` | [source] |
| `[generated-2]` | `[tool]` | [source] |
```

---

### 5.13 error-recovery.md

Common failures and their fixes. Grows organically as you encounter issues.

```markdown
# Error Recovery Patterns

## [Category 1]

| Symptom | Cause | Recovery |
|---------|-------|----------|
| [Error message or behavior] | [Root cause] | [How to fix] |
| [Error message or behavior] | [Root cause] | [How to fix] |

## [Category 2]

| Symptom | Cause | Recovery |
|---------|-------|----------|
| [Error message or behavior] | [Root cause] | [How to fix] |
```

---

### 5.14 external-integrations.md

Rules for external service layers — APIs you call, third-party services, message queues, webhook consumers. Any project that calls external services benefits from encoding the integration architecture.

```markdown
# External Integration Architecture

## Service Layer Rules

- [Service layer] calls [API/service], never the database directly
- Auth is extracted from [source] at [lifecycle point] and is immutable for the [scope]
- [Client instances] are [shared/per-request] — [rationale]

## Transport and Sessions

| Setting | Value | Rationale |
|---------|-------|-----------|
| Transport | [HTTP / gRPC / WebSocket / etc.] | [Why] |
| Session model | [per-request / per-session / singleton] | [Why] |
| Timeout | [value] | [Why] |

## Tool/Endpoint Design Principles

1. [Principle 1 — e.g., "Fat responses — return related data in one call"]
2. [Principle 2 — e.g., "Pre-computed aggregations — never delegate math to the caller"]
3. [Principle 3 — e.g., "Dynamic field selection via include parameter"]

## Anti-Patterns

| DO NOT | DO INSTEAD | Why |
|--------|-----------|-----|
| [Call database from integration layer] | [Call API layer] | [Bypasses security/validation] |
| [Create client per request] | [Share stateless singleton] | [Performance] |
| [Accept auth in request params] | [Extract from headers/context] | [Security] |
```

---

### 5.15 ui-testing-strategy.md

Rules for UI and end-to-end testing. Separate from `testing-strategy.md` because UI testing often follows fundamentally different patterns (interactive vs scripted, visual vs assertion-based).

```markdown
# UI Testing Strategy

## Approach

[Choose one: AI-driven interactive testing / Coded E2E tests / Both]

## [If AI-driven interactive testing:]

Use [browser automation tool] for UI testing. [Do / Do NOT] write coded
test files (*.spec.ts). AI-driven interactive testing replaces traditional
scripted E2E tests.

### How to Test
1. Navigate to the target page
2. Capture page state (snapshot / screenshot)
3. Interact (click, type, fill forms)
4. Verify expected state
5. Test edge cases

### Test Scenarios to Cover
- Default/initial state renders correctly
- Primary interaction works
- State changes propagate to all affected components
- Edge cases (outside click, duplicate actions, empty states)
- Persistence across page reload (if applicable)

## [If coded E2E tests:]

### Framework
[Playwright / Cypress / etc.]

### File Conventions
- Test files: `[pattern]`
- Page objects: `[pattern]`
- Fixtures: `[pattern]`

## Do NOT
- [Testing anti-pattern 1]
- [Testing anti-pattern 2]
```

---

### Cross-Referencing Between Rules Files

Rules files are not isolated documents — they form a web of references. Keeping these cross-references consistent is critical.

**Common cross-reference patterns:**

| File | References |
|------|-----------|
| `development-workflow.md` | Agent names from `.claude/agents/`, template paths from `.claude/templates/` |
| `canonical-patterns.md` | Source file paths, template file paths |
| `anti-patterns.md` | Design decision IDs (DD-XX) from `CLAUDE.md` |
| `documentation-maintenance.md` | Directory `CLAUDE.md` paths, `docs/` paths |
| `error-recovery.md` | Commands and config from `technology-decisions.md` |
| `testing-strategy.md` | Test patterns from `canonical-patterns.md` |

**Rules for cross-references:**

1. **Always use project-root-relative paths** — `docs/data-model/design-decisions.md`, not `../data-model/design-decisions.md`
2. **Reference DDs by ID** — say "DD-23" not "the rule about required columns on child tables"
3. **When renaming an agent or template**, grep all rules files for references and update in the same commit
4. **When adding a new DD**, update both `CLAUDE.md` (index) and `docs/data-model/design-decisions.md` (full detail)
5. **Treat broken cross-references as bugs** — fix immediately

---

## 6. Design Decisions Registry

Design decisions (DD-XX) are the backbone of architectural consistency. Every significant "we chose X over Y" gets an ID, a summary, and a rationale. These IDs are referenced throughout rules files, agent definitions, and code comments.

### Why Number Them

- **Reference from anywhere** — Rules files say "DD-23" instead of re-explaining the decision
- **Prevent re-litigation** — When the AI proposes an alternative, you can say "that violates DD-07"
- **Traceability** — Code comments can reference `// DD-15: physical deletes, no soft deletes`
- **Onboarding** — New contributors read the DD table to understand the "why" behind the "what"

### DD Format

The index table goes in `CLAUDE.md` (within the 150-line limit). Full rationale goes in `docs/data-model/design-decisions.md`:

**In CLAUDE.md (index only):**

```markdown
## Design Decisions (DD-01 through DD-[NN])

| ID | Summary |
|----|---------|
| DD-01 | [Entity X] is polymorphic — [types A, B, C] are all [Entity X] records |
| DD-02 | [Property A/B/C] are always three independent values |
| DD-03 | Multi-tenancy via [column] on every row |
| DD-04 | Session-variable [security model] for database-level isolation |
| DD-05 | Physical deletes + audit log — no soft deletes |
```

**In docs/data-model/design-decisions.md (full detail):**

```markdown
## DD-01: [Entity X] is Polymorphic

**Decision:** [Entity types A, B, and C] are all stored as [Entity X] records,
differentiated by a [type/role] column.

**Rationale:** [Why this is better than separate tables.]

**Alternatives considered:**
- Separate tables per type — rejected because [reason]
- STI with type column — similar but [tradeoff]

**Implications:**
- Queries for "all [entity]s" are simple single-table scans
- Type-specific fields may be NULL for other types
- [Framework/tool] resolvers use a [pattern] for type discrimination
```

### Naming Convention

| Range | Domain |
|-------|--------|
| DD-01 through DD-10 | Core data model |
| DD-11 through DD-20 | Cross-cutting concerns (tenancy, security, audit) |
| DD-21 through DD-30 | API and schema design |
| DD-31 through DD-40 | External integrations |
| DD-41 through DD-50 | Auth, roles, permissions |

Number ranges are guidelines, not strict rules. The important thing is that every decision gets a unique, stable ID.

---

## 7. Templates

Templates live in `.claude/templates/` and provide copy-ready boilerplate for common patterns. They eliminate the "blank page problem" — instead of writing from scratch, the AI copies a template and fills in the specifics.

### Template Anatomy

Every template follows this structure:

```
# [File header with placeholder markers]

[Required boilerplate — imports, configurations]

# --- BEGIN CUSTOMIZATION ---

[Sections the AI fills in, marked with [PLACEHOLDER] tokens]

# --- END CUSTOMIZATION ---

[Required footer — exports, cleanup]
```

### What to Template

Create templates for any file pattern you create more than twice:

| Pattern | Template Name | Trigger |
|---------|--------------|---------|
| Database migration | `new-migration.sql` | Adding a table or column |
| API handler/resolver | `new-handler.ext` | Adding an endpoint |
| Data loader/batch | `new-loader.ext` | Adding a child collection |
| Integration test | `new-test.ext` | Testing a new feature |
| Task context file | `task-context.md` | Starting a multi-file change |

### Task Context Template

This is the most important template — it structures cross-session state:

```markdown
# Task Context: [BRANCH NAME]

**Branch:** `feature/[xxx]`
**Created:** [YYYY-MM-DD]
**Status:** Planning | Implementing | Reviewing | Shipping | Complete
**Current Phase:** [1-Plan | 2-Synthesize | 3-Implement | 3.5-Validate | 4-Review | 5-Fix | 6-Ship]
**Last Updated:** [YYYY-MM-DD]

> **RESUME INSTRUCTIONS (read after compaction/restart):**
> 1. Check Status + Current Phase above to know where you are
> 2. Before doing ANY work, update this file if the last phase's output is empty
> 3. After completing ANY phase or task, update this file immediately
> 4. See `.claude/rules/development-workflow.md` for exact update rules

## Task Description

[What is being built/changed and why]

## Files Expected to Change

| File | Change |
|------|--------|
| `path/to/file` | description |

## Triggered Agents

- [ ] `[agent-1]` ([trigger condition])
- [ ] `[agent-2]` ([trigger condition])
- [ ] `core:code-reviewer` (always)
- [ ] `core:qa-engineer` (always)

---

## Phase 1 — Planning Output

### [Agent 1 Name]
- Key decisions:
- Constraints:

### [Agent 2 Name]
- Domain implications:
- Rules:

---

## Phase 2 — Synthesized Plan

### Confirmed Requirements
1. [Requirement from multiple agents agreeing]

### Resolved Disagreements
- [Disagreement]: resolved by [rule/decision] → [outcome]

### Acceptance Criteria
- [ ] AC-1: [specific, testable criterion]
- [ ] AC-2: [specific, testable criterion]

### Task Breakdown
- [ ] Task 1: [description]
- [ ] Task 2: [description]

---

## Phase 3 — Implementation Notes

### Files Changed
| File | What Changed |
|------|-------------|
| `path/to/file` | description |

### Implementation Decisions
- [Decision made during coding that wasn't in the plan]

### Deviations from Plan
- [Anything that changed from Phase 2 and why]

---

## Phase 3.5 — Validation Results

- [ ] [Build command] — pass/fail
- [ ] [Codegen command] — pass/fail (if applicable)
- [ ] Test suite — pass/fail (X passing, Y failing)

---

## Phase 4 — Review Findings

### Blocking (must fix before ship)
| # | Finding | Reviewer | File:Line |
|---|---------|----------|-----------|
| B-1 | [description] | [agent] | `path:NN` |

### Advisory (nice to have, don't block)
| # | Finding | Reviewer | File:Line |
|---|---------|----------|-----------|
| A-1 | [description] | [agent] | `path:NN` |

---

## Phase 5 — Fix & Iterate

### Iteration 1
- Fixed: B-1 ([brief description of fix])
- Re-validated: pass/fail
- Re-reviewed: clean / [remaining issues]

---

## Phase 6 — Ship

### Release Notes Entry
**Category:** Added | Changed | Fixed | Removed
[1-3 sentence stakeholder-facing summary.]
**Impact:** [Who is affected]

### Ship Checklist
- [ ] Release notes written above
- [ ] Documentation updated per checklist
- [ ] Change summary produced
- [ ] PR created: [URL]
```

### The Canonical Reference Pattern

Beyond templates for new files, maintain a table of canonical reference files — existing files that exemplify a pattern:

```markdown
| Pattern | Canonical File | Template |
|---------|---------------|----------|
| [Complex query handler] | `src/handlers/orders.ts` | `.claude/templates/new-handler.ts` |
| [Migration with FK] | `migrations/005_orders.sql` | `.claude/templates/new-migration.sql` |
| [Integration test] | `tests/orders.test.ts` | `.claude/templates/new-test.ts` |
```

This way, the AI doesn't just start from a skeleton — it can study a real implementation of the same pattern.

### Directory-Level CLAUDE.md Template

Every major source directory should have its own `CLAUDE.md` (Tier 3, 200-line limit). Here's the template:

```markdown
# [Directory Name]

[1-2 sentence description of what this directory contains and its role.]

## File Inventory

| File | Purpose |
|------|---------|
| `[file-1]` | [What it does] |
| `[file-2]` | [What it does] |

## Conventions Specific to This Directory

- [Convention 1 — e.g., "All files in this directory export a default function"]
- [Convention 2 — e.g., "File names match the entity they handle: orders.ts, users.ts"]
- [Convention 3 — e.g., "Every new file must be registered in index.ts"]

## Adding a New [File Type]

1. Copy from template: `.claude/templates/new-[type].ext`
2. Or study the canonical reference: `[existing-file-in-this-dir]`
3. [Register it / wire it up / add to index]
4. [Add corresponding test in tests/[dir]/]

## Common Mistakes in This Directory

| Mistake | Fix |
|---------|-----|
| [Mistake 1] | [How to fix] |
| [Mistake 2] | [How to fix] |
```

**Tips for effective directory context:**
- Focus on conventions that are *specific* to this directory, not global rules (those go in `.claude/rules/`)
- Include a file inventory so the AI knows what exists without globbing
- The "Adding a New [File Type]" section is the most useful — it's the action the AI performs most often
- Update the inventory when files are added or removed

---

# Part 3: Agents and Workflow

## 8. Custom Agents

Custom agents are specialized reviewers that Claude Code launches as subprocesses. Each agent has a narrow focus, a specific trigger condition, and a set of things it checks. They're defined in `.claude/agents/` as markdown files with YAML frontmatter.

### Why Custom Agents

| Without Agents | With Agents |
|----------------|-------------|
| You remember to check conventions | Agents check automatically when triggered |
| Reviews happen inconsistently | Every relevant change gets the right reviewers |
| Domain knowledge lives in your head | Domain knowledge is encoded in agent prompts |
| Single-pass review misses cross-cutting concerns | Parallel agents catch issues from multiple angles |

### Agent Anatomy

```markdown
---
name: [agent-name]
description: "[Description with <example> blocks for Claude Code to match triggers]"
model: [opus / sonnet / haiku]
---

[System prompt for the agent — who it is, what it checks, how it reports]

## Validation Checklists

### [Checklist 1]
1. [Check item]
2. [Check item]

### [Checklist 2]
| Pattern | Correct | Wrong |
|---------|---------|-------|
| [item] | [correct] | [wrong] |

## How You Operate

1. [Step 1 — what to read first]
2. [Step 2 — what to check]
3. [Step 3 — how to report]

### What You Should NOT Do
- [Boundary 1]
- [Boundary 2]
```

### The Trigger Table

Every agent has a trigger condition. The trigger table lives in `.claude/rules/development-workflow.md` and maps file paths to required agents:

```markdown
## Mandatory Agent Triggers

| Agent | MUST Use When | Phase |
|-------|--------------|-------|
| `[domain]-expert` | Any change touching: [entity list] | Plan (1) + Review (4) |
| `[layer]-guardian` | Any change in `[directory pattern]` | Plan (1) + Review (4) |
| `[pattern]-checker` | Any change in `[file patterns]` | Review (4) |
| `core:code-reviewer` | Every code change, no exceptions | Review (4) |
| `core:qa-engineer` | Every code change, no exceptions | Review (4) |
```

**How to decide which agents to trigger:** Before implementing, list the files you expect to change. Match each file path against the trigger conditions. Launch ALL matching agents.

### Starter Agent Set

Most projects benefit from three to five custom agents. Here's a recommended starter set:

| Agent | Focus | Trigger |
|-------|-------|---------|
| **Domain Expert** | Business rules, terminology, entity relationships | Changes to core domain entities |
| **Schema/Data Guardian** | Database conventions, column standards, migration quality | Changes to migrations, schema, seed data |
| **API Consistency Checker** | API type system, handler-to-schema mapping, pagination | Changes to API schema or handlers |
| **Test Generator** | Integration test patterns, coverage requirements | New code without corresponding tests |

You don't need all four on day one. Start with the Domain Expert (it catches the most mistakes) and add more as patterns stabilize.

### Full Generic Agent Example

Here's a complete, copy-ready agent definition:

```markdown
---
name: [your-domain]-expert
description: "Use this agent when any change touches [list of entities/concepts].
It validates business rules, naming conventions, and domain constraints.

<example>
Context: Developer is adding a new entity type.
user: \"I'm adding a [new-entity] table and resolver.\"
assistant: \"Let me use the [your-domain]-expert agent to validate the entity
design against domain rules and naming conventions.\"
<commentary>
New entities must follow naming conventions and satisfy domain constraints.
The agent catches violations early.
</commentary>
</example>

<example>
Context: Developer is modifying business logic.
user: \"I'm changing the [calculation/workflow] logic.\"
assistant: \"I'll use the [your-domain]-expert agent to verify the business
rules are correctly implemented.\"
<commentary>
Business logic changes need domain validation to prevent silent rule violations.
</commentary>
</example>"
model: opus
---

You are a domain expert for [YourProject]. Your job is to validate all changes
against the project's business rules, naming conventions, and domain constraints.
You treat domain violations as bugs, not suggestions.

## Domain Rules

### Entity Naming
| Entity | Correct Name | Wrong Name | Why |
|--------|-------------|------------|-----|
| [Entity 1] | `[correct]` | `[wrong]` | [Reason] |
| [Entity 2] | `[correct]` | `[wrong]` | [Reason] |

### Business Constraints
1. [Rule 1 — e.g., "Amounts must always be positive"]
2. [Rule 2 — e.g., "Status transitions must follow the lifecycle"]
3. [Rule 3 — e.g., "Every [entity] must have a [required field]"]

### Naming Conventions
- Database: `snake_case`
- API: `camelCase` / `PascalCase`
- Enums: DB `lowercase`, API `UPPER_CASE`
- Transforms happen in [layer], never in [other layer]

## Design Decisions You Enforce

| DD | Rule |
|----|------|
| DD-[XX] | [Summary] |
| DD-[YY] | [Summary] |

## How You Operate

1. **Read the changed files** completely before commenting
2. **Check entity names** against the naming table
3. **Validate business constraints** — report violations as blocking
4. **Verify design decision compliance** — flag violations with DD number
5. **Report results** as: PASS (no issues), WARN (advisory), FAIL (blocking)

### What You Should NOT Do
- Do not suggest [rejected technology] — [locked choice] only
- Do not suggest [rejected pattern] — [correct pattern] only
- Do not suggest [out-of-scope feature] — deferred to [phase/version]
```

### Agent Model Selection

| Model | Use For | Cost/Speed |
|-------|---------|------------|
| `opus` | Domain experts, guardians, architectural review | Slower, highest quality |
| `sonnet` | Code review, consistency checks, test generation | Good balance |
| `haiku` | Simple validation, formatting checks | Fastest, cheapest |

Use `opus` for agents that need to reason about domain rules. Use `sonnet` or `haiku` for mechanical checking.

---

## 9. Seven-Phase Workflow

The development workflow ensures that non-trivial changes go through planning, implementation, validation, and review — with the right agents at each phase. It's encoded in `.claude/rules/development-workflow.md`.

### When to Use the Full Workflow

| Change Size | Workflow |
|-------------|----------|
| Multi-file feature, architecture change, domain-sensitive | Full 7-phase |
| Single-file bug fix | Phase 3 → 3.5 → 4 → 6 |
| Documentation-only | Direct edit |

### Phase Overview

```
Phase 1: Plan          → Launch planning agents in parallel
Phase 2: Synthesize    → Reconcile agent outputs, create task list
Phase 3: Implement     → Write the code
Phase 3.5: Validate    → Build + test (gate — must pass to proceed)
Phase 4: Review        → Launch review agents in parallel
Phase 5: Fix & Iterate → Address blocking findings
Phase 6: Ship          → Document, commit, PR (user-initiated)
```

### Phase-by-Phase Breakdown

#### Phase 1 — Plan (Parallel Agents)

Launch all triggered planning agents **in parallel**. Each agent gets:
- The task description
- Relevant file paths
- Domain-specific questions

```
Example parallel launch:
  Agent 1: [domain]-expert     → "What domain rules apply to this change?"
  Agent 2: [layer]-guardian     → "What schema conventions must this follow?"
  Agent 3: technical-architect  → "What's the right approach for this change?"
```

**After Phase 1:** Write planning output to context file. Update Status to `Planning`.

#### Phase 2 — Synthesize

The orchestrator (Claude Code, not an agent) reconciles outputs:

1. **Identify agreements** across agents — confirmed requirements
2. **Flag disagreements** — resolve using project rules (CLAUDE.md, `.claude/rules/`)
3. **Create phase-level tasks** via `TaskCreate` so progress survives compaction
4. **If unknowns surfaced**, use `AskUserQuestion` before proceeding

**After Phase 2:** Append synthesized plan + acceptance criteria to context file. Update Status to `Implementing`.

**Do NOT skip synthesis.** This is where conflicting agent advice gets resolved.

#### Phase 3 — Implement

Launch `core:developer` agent with explicit instructions:
- "Read `.claude/plans/ctx-{branch}.md` for full context"
- **File paths** to modify (be explicit — don't make the agent search)
- **Template references** — point to `.claude/templates/`
- **Canonical patterns** — reference from `.claude/rules/canonical-patterns.md`
- **Anti-patterns** to avoid

**After Phase 3:** Append files changed and implementation decisions to context file.

#### Phase 3.5 — Validate (Gate)

This is a hard gate. Do not proceed to review if validation fails.

```bash
# Run these in order:
[codegen command]          # If schema/types changed
[build command]            # Catch type errors
[test command]             # Run relevant test suite
```

**Only proceed to Phase 4 if build + tests pass.**

**After Phase 3.5:** Append validation results to context file.

#### Phase 4 — Review (Parallel Agents)

Launch ALL triggered review agents **in parallel**. Always required:
- `core:code-reviewer`
- `core:qa-engineer`

Conditional (per trigger table):
- `[domain]-expert`
- `[layer]-guardian`
- `[pattern]-checker`

Each reviewer gets:
- "Read `.claude/plans/ctx-{branch}.md` for acceptance criteria"
- `git diff` of changed files
- Specific checklist for their domain

**After Phase 4:** Append review findings to context file.

#### Phase 5 — Fix & Iterate

1. Collect findings from all reviewers (already in context file)
2. Categorize: **blocking** (must fix) vs **advisory** (nice to have)
3. Fix blocking issues
4. Re-run Phase 3.5 validation
5. Re-review changed files only
6. Repeat until zero blocking findings

#### Phase 6 — Ship (User-Initiated)

Only proceed when user explicitly requests. This phase:

1. **Generate release notes** from the context file
2. **Update documentation** per the update checklist
3. **Clean up ephemeral files** (context file, phase outputs)
4. **Stage specific files** (never `git add -A`)
5. **Create PR** with release notes in body

### Workflow Profiles

Not every project needs all seven phases from day one. Adopt incrementally:

| Profile | Phases Used | When |
|---------|-------------|------|
| **Minimal** | 3 → 3.5 → 6 | Solo developer, early project |
| **Standard** | 3 → 3.5 → 4 → 5 → 6 | Established patterns, adding features |
| **Full** | 1 → 2 → 3 → 3.5 → 4 → 5 → 6 | Multi-file, architectural, domain-sensitive |

Start with Minimal. Add review (Phase 4) once you have agents defined. Add planning (Phases 1-2) once your project has enough conventions to validate against.

---

## 10. Task Context Files

Context files are the single most important mechanism for surviving AI session interruptions. They persist state across context window compaction and session restarts.

### The Problem They Solve

Claude Code's context window compresses older messages when it runs out of space. Without a context file:
- The AI forgets what phase it was in
- Planning output is lost
- Review findings disappear
- The AI starts over or makes inconsistent decisions

With a context file:
- Every phase's output is saved to disk
- After compaction, the AI reads the file and knows exactly where it left off
- Review findings persist even when the conversation is compressed

### Lifecycle

```
Branch created → Context file created (.claude/plans/ctx-{branch}.md)
    ↓
Phase boundary → Context file updated (MANDATORY — last action of every phase)
    ↓
Compaction/restart → AI reads context file to recover state
    ↓
Branch merged → Context file deleted (never committed to git)
```

### Context File Update Checklist

After each phase, update these fields BEFORE moving on:

| After Phase | Update These Fields |
|-------------|-------------------|
| Phase 1 (Plan) | Status → `Planning`, append agent outputs to Phase 1 section |
| Phase 2 (Synthesize) | Status → `Implementing`, Current Phase → `3-Implement`, append plan + acceptance criteria |
| Phase 3 (Implement) | Current Phase → `3.5-Validate`, append files changed |
| Phase 3.5 (Validate) | Current Phase → `4-Review`, append build/test results |
| Phase 4 (Review) | Status → `Reviewing`, append review findings |
| Phase 5 (Fix) | Status → `Implementing` or `Ready to Ship`, append fixes |
| Phase 6 (Ship) | Status → `Complete`, append PR URL |

### Pre-Compaction Checkpoint

Claude Code warns when the context window is getting full before compressing older messages. When this happens, **immediately update the context file** before any more work:

1. Update Status and Current Phase to reflect where you are right now
2. Fill in any output sections for the current phase (even if incomplete, note "in progress")
3. Save the file

This proactive save means you'll have state *before* context is lost, rather than trying to reconstruct it after.

### Recovery Protocol

When resuming after compaction or restart:

1. Run `TaskList` to see current task status
2. Read `.claude/plans/ctx-{branch}.md` to recover full context
3. Check Status and Current Phase to determine where to resume
4. Fill any empty output sections from the current phase
5. Continue from where you left off

### Two Kinds of Plans

The `.claude/plans/` directory serves two distinct purposes:

| Kind | Pattern | Committed? | Lifespan |
|------|---------|-----------|----------|
| **Ephemeral context** | `ctx-{branch}.md`, `phase1-*.md`, `phase4-*.md` | No (gitignored) | Deleted when branch merges |
| **Persistent plans** | `[descriptive-name]-plan.md` | Yes (committed) | Long-lived technical roadmaps |

Persistent plans are implementation strategies that span multiple sessions and branches — e.g., `api-migration-plan.md`, `auth-implementation-plan.md`. They're committed to the repo so any session can reference them. Ephemeral context files are per-branch working state that is discarded after merge.

### Gitignore Rules

Ephemeral files MUST NOT be committed:

```gitignore
.claude/plans/ctx-*          # Per-branch context files
.claude/plans/phase1-*       # Phase 1 agent outputs
.claude/plans/phase4-*       # Phase 4 review outputs
```

---

# Part 4: Enforcement and Quality

## 11. Hooks

Hooks are shell scripts that run automatically before Claude Code executes certain tools. They catch documentation drift, missing reviews, and convention violations before they make it into commits.

### How Hooks Work

Claude Code supports `PreToolUse` hooks that intercept tool calls. The hook receives JSON on stdin describing the tool call, and its exit code determines the outcome:

| Exit Code | Meaning |
|-----------|---------|
| 0 | Allow (optionally print a warning) |
| 2 | Block (print reason, tool call is prevented) |

### settings.json

The hook configuration lives in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/doc-check.sh"
          },
          {
            "type": "command",
            "command": ".claude/hooks/review-check.sh"
          }
        ]
      }
    ]
  }
}
```

This configuration runs both hooks before every `Bash` tool use — which includes `git commit`, `git push`, `gh pr create`, and other shell commands.

### doc-check.sh — Documentation Sync Validation

This hook warns when code changes without corresponding documentation updates. Copy and customize:

```bash
#!/usr/bin/env bash
# Pre-commit documentation validation hook
# Checks that when source files change, corresponding docs were updated.
#
# Exit codes:
#   0 = allow (docs are in sync or no doc-sensitive files changed)
#   2 = block (doc-sensitive files changed without doc updates)

set -euo pipefail

# Read the tool input from stdin (JSON with tool_input.command)
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c \
  "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" \
  2>/dev/null || echo "")

# Only intercept git commit and gh pr create commands
if [[ "$COMMAND" != *"git commit"* && "$COMMAND" != *"gh pr create"* ]]; then
  exit 0
fi

# Get staged files
STAGED=$(git diff --cached --name-only 2>/dev/null || echo "")
if [[ -z "$STAGED" ]]; then
  exit 0
fi

WARNINGS=""

# === CUSTOMIZE THESE CHECKS FOR YOUR PROJECT ===

# Check: [source-dir-1] changed -> [source-dir-1]/CLAUDE.md should be updated
if echo "$STAGED" | grep -q "^[source-dir-1]/" \
   && ! echo "$STAGED" | grep -q "^[source-dir-1]/CLAUDE.md"; then
  WARNINGS="${WARNINGS}\n  - [source-dir-1] changed but [source-dir-1]/CLAUDE.md not updated"
fi

# Check: [schema-dir] changed -> regenerate types
if echo "$STAGED" | grep -q "^[schema-dir]/"; then
  if ! echo "$STAGED" | grep -q "^[generated-types-path]"; then
    WARNINGS="${WARNINGS}\n  - Schema files changed but generated types not staged (run [codegen command])"
  fi
fi

# Check: feature code changed -> roadmap should be updated
if echo "$STAGED" | grep -qE "^(src/)" \
   && ! echo "$STAGED" | grep -q "^docs/planning/"; then
  WARNINGS="${WARNINGS}\n  - Feature code changed but planning docs not updated"
fi

# Check: context file exists but not staged (feature branch only)
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [[ -n "$BRANCH" && "$BRANCH" != "main" && "$BRANCH" != "master" ]]; then
  CTX_FILE=".claude/plans/ctx-${BRANCH}.md"
  if [[ -f "$CTX_FILE" ]] && ! echo "$STAGED" | grep -qF "$CTX_FILE"; then
    WARNINGS="${WARNINGS}\n  - Context file ${CTX_FILE} exists but not staged"
  fi
fi

# === END CUSTOMIZATION ===

if [[ -n "$WARNINGS" ]]; then
  echo "Documentation check warnings:${WARNINGS}"
  echo ""
  echo "Review .claude/rules/documentation-maintenance.md"
  # Exit 0 = warning only. Change to exit 2 for hard block.
  exit 0
fi

exit 0
```

### review-check.sh — Review Phase Enforcement

This hook reminds about the review phase before pushing code:

```bash
#!/usr/bin/env bash
# Review enforcement hook
# Reminds about review phase when pushing code.
#
# Exit codes:
#   0 = allow (with reminder)
#   2 = block

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c \
  "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" \
  2>/dev/null || echo "")

# Only intercept git push commands
if [[ "$COMMAND" != *"git push"* ]]; then
  exit 0
fi

BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [[ -z "$BRANCH" || "$BRANCH" == "main" ]]; then
  exit 0
fi

# Count commits ahead of main
AHEAD=$(git rev-list --count main.."$BRANCH" 2>/dev/null || echo "0")

if [[ "$AHEAD" -gt 0 ]]; then
  echo "Pre-push reminder: $AHEAD commit(s) ahead of main on '$BRANCH'."
  echo "Ensure review agents were called per development-workflow.md:"
  echo "  - core:code-reviewer (required for ALL code changes)"
  echo "  - core:qa-engineer (required for ALL code changes)"
  # Warning only — change to exit 2 for hard block
  exit 0
fi

exit 0
```

### Making Hooks Executable

After creating hook scripts:

```bash
chmod +x .claude/hooks/doc-check.sh
chmod +x .claude/hooks/review-check.sh
```

### Escalation Strategy

Start with hooks as warnings (exit 0). Once the team is comfortable, escalate to blockers (exit 2) for critical checks:

| Check | Start As | Escalate To | When |
|-------|----------|-------------|------|
| Missing docs update | Warning (exit 0) | Blocker (exit 2) | After 2 weeks |
| Missing codegen | Warning (exit 0) | Blocker (exit 2) | Immediately (causes build failures) |
| Missing review | Warning (exit 0) | Warning (exit 0) | Keep as reminder |

---

## 12. Quality Patterns

Beyond hooks and agents, several patterns keep quality high across sessions.

### Anti-Pattern Evolution

The anti-patterns file (`.claude/rules/anti-patterns.md`) is a living document. When you catch the AI making a mistake:

1. Fix the mistake
2. Add an entry to anti-patterns.md with the "DO NOT / DO INSTEAD / Why" format
3. The AI will never make that mistake again (in any future session)

This creates a ratchet — quality can only improve over time.

### Canonical Reference Pattern

Instead of describing how to write a resolver/handler/migration, point to a real file:

```
"When adding a new [handler], copy the structure from `src/handlers/orders.ts`
(the canonical reference) and use the template at `.claude/templates/new-handler.ts`."
```

This is more reliable than prose descriptions because:
- The reference file is always up to date (it's real code that runs)
- The AI can read and copy actual patterns, not interpret descriptions
- Discrepancies between description and reality are impossible

### Error Recovery as Documentation

When you encounter and fix an error, add it to `.claude/rules/error-recovery.md`:

```markdown
| Symptom | Cause | Recovery |
|---------|-------|----------|
| `[Error message]` | [What went wrong] | [How to fix it] |
```

This serves double duty:
- Future AI sessions can self-diagnose common issues
- Human developers get a searchable troubleshooting guide

### Testing Philosophy Encoding

Your testing rules go in `.claude/rules/testing-strategy.md`. The key sections:

1. **What MUST be tested** — e.g., "Every new endpoint needs an integration test"
2. **What MUST NOT be mocked** — e.g., "Never mock the database; use real instances"
3. **Test categories and their triggers** — e.g., "Security tests for any auth change"
4. **Verification categories** — e.g., "Every test must check: isolation, constraints, audit trail"

### Change Summary Format

After any implementation, produce a structured summary. This format goes in `.claude/rules/canonical-patterns.md`:

```markdown
## Change Summary
- **Files modified:** (list with brief description of each change)
- **Schema changes:** (new types, fields — or "none")
- **Migration changes:** (new tables, columns, constraints — or "none")
- **Design decisions referenced:** (DD-XX numbers)
- **Anti-patterns checked:** (list verified patterns)
- **Tests added/modified:** (list with coverage description)
- **Documentation updated:** (list affected docs — or "none needed")
```

---

## 13. PR and Release Format

Standardized PR descriptions make release notes generation automatic. Define the format in `.claude/rules/canonical-patterns.md`:

### PR Description Template

```markdown
## Summary
<1-3 bullet points — what changed and why>

## Release Notes
**Category:** Added | Changed | Fixed | Removed
<1-3 sentence stakeholder-facing summary — what users can now do, not how it works>
**Impact:** <who is affected>

## Roadmap Items Completed
<List roadmap IDs completed — or "None">

## Test Plan
- [ ] <verification steps>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### Release Notes Aggregation

PR descriptions are the source of truth for release notes. To generate a release notes document:

```bash
# Aggregate merged PR descriptions for release notes
gh pr list --state merged --base main --json title,body --limit 50
```

### Roadmap Maintenance

If your project tracks a roadmap (`docs/planning/production-roadmap.md`), update it at Phase 6:
- Move completed items to a "Completed" section
- Update counts and progress percentages
- Update the critical path if it changed

---

# Part 5: Appendix

## 14. Scaffold Script

Run this to create the entire `.claude/` directory structure:

```bash
#!/usr/bin/env bash
# Scaffold the Claude Code AI architecture for a new project
set -euo pipefail

echo "Creating .claude/ directory structure..."

# Core directories
mkdir -p .claude/{agents,hooks,plans,rules,templates}

# Rules files (create stubs) — 15 files, see Section 5 for contents
for rule in \
  technology-decisions \
  architecture \
  database-conventions \
  api-conventions \
  domain-context \
  status-lifecycles \
  anti-patterns \
  canonical-patterns \
  development-workflow \
  testing-strategy \
  ui-testing-strategy \
  external-integrations \
  documentation-maintenance \
  project-structure \
  error-recovery; do
  # Title-case the filename for the header (portable across macOS + Linux)
  TITLE=$(echo "$rule" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
  echo "# ${TITLE} Rules" > ".claude/rules/${rule}.md"
  echo "" >> ".claude/rules/${rule}.md"
  echo "[TODO: Fill in from ai-project-setup-guide.md Section 5]" >> ".claude/rules/${rule}.md"
done

# Hook scripts
cat > .claude/hooks/doc-check.sh << 'HOOK_EOF'
#!/usr/bin/env bash
# Documentation sync validation — customize for your project
set -euo pipefail
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
if [[ "$COMMAND" != *"git commit"* && "$COMMAND" != *"gh pr create"* ]]; then exit 0; fi
# Add your checks here (see ai-project-setup-guide.md Section 11)
exit 0
HOOK_EOF

cat > .claude/hooks/review-check.sh << 'HOOK_EOF'
#!/usr/bin/env bash
# Review phase enforcement — customize for your project
set -euo pipefail
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
if [[ "$COMMAND" != *"git push"* ]]; then exit 0; fi
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [[ -z "$BRANCH" || "$BRANCH" == "main" ]]; then exit 0; fi
AHEAD=$(git rev-list --count main.."$BRANCH" 2>/dev/null || echo "0")
if [[ "$AHEAD" -gt 0 ]]; then
  echo "Pre-push reminder: $AHEAD commit(s) ahead of main. Ensure review agents were called."
fi
exit 0
HOOK_EOF

chmod +x .claude/hooks/doc-check.sh
chmod +x .claude/hooks/review-check.sh

# Settings
cat > .claude/settings.json << 'SETTINGS_EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/doc-check.sh"
          },
          {
            "type": "command",
            "command": ".claude/hooks/review-check.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS_EOF

# Task context template
cat > .claude/templates/task-context.md << 'CTX_EOF'
# Task Context: [BRANCH NAME]

**Branch:** `feature/[xxx]`
**Created:** [YYYY-MM-DD]
**Status:** Planning | Implementing | Reviewing | Shipping | Complete
**Current Phase:** [1-Plan | 2-Synthesize | 3-Implement | 3.5-Validate | 4-Review | 5-Fix | 6-Ship]
**Last Updated:** [YYYY-MM-DD]

> **RESUME INSTRUCTIONS:**
> 1. Check Status + Current Phase to know where you are
> 2. Update this file if the last phase's output is empty
> 3. See `.claude/rules/development-workflow.md` for update rules

## Task Description
[What is being built/changed and why]

## Files Expected to Change
| File | Change |
|------|--------|
| `path/to/file` | description |

## Triggered Agents
- [ ] `core:code-reviewer` (always)
- [ ] `core:qa-engineer` (always)
CTX_EOF

# Gitignore additions
if [[ -f .gitignore ]]; then
  if ! grep -q "ctx-\*" .gitignore 2>/dev/null; then
    echo "" >> .gitignore
    echo "# Claude Code ephemeral files" >> .gitignore
    echo ".claude/plans/ctx-*" >> .gitignore
    echo ".claude/plans/phase1-*" >> .gitignore
    echo ".claude/plans/phase4-*" >> .gitignore
    echo ".playwright-screenshots/" >> .gitignore
  fi
else
  cat > .gitignore << 'GI_EOF'
# Claude Code ephemeral files
.claude/plans/ctx-*
.claude/plans/phase1-*
.claude/plans/phase4-*
.playwright-screenshots/
GI_EOF
fi

# Root CLAUDE.md stub
if [[ ! -f CLAUDE.md ]]; then
  cat > CLAUDE.md << 'CLAUDE_EOF'
# [YourProject]

**Version:** 0.1 | **Last Updated:** [Month Year]

[1-2 sentence project description.]

## Quick Start

```bash
# TODO: Add your setup commands
```

## Critical Rules

1. **[Stack]** — locked, no alternatives
2. **[Follow development workflow]** — see `.claude/rules/development-workflow.md`

## Design Decisions

| ID | Summary |
|----|---------|
| DD-01 | [First decision] |

## Always-Loaded Rules

| File | Content |
|------|---------|
| `technology-decisions.md` | Locked stack + rejected alternatives |
| `architecture.md` | System architecture rules |
| `anti-patterns.md` | Known mistakes to avoid |
CLAUDE_EOF
fi

echo ""
echo "Scaffold complete. Next steps:"
echo "  1. Edit CLAUDE.md with your project details"
echo "  2. Fill in .claude/rules/ files (start with technology-decisions.md)"
echo "  3. See ai-project-setup-guide.md for detailed instructions"
```

---

## 15. Setup Order

Don't try to write everything on day one. Adopt incrementally.

### Quick Wins (10 minutes)

After running the scaffold script, do these three things to see immediate value:

1. **Fill `technology-decisions.md`** with your stack (5 min) — Next session, the AI will never propose rejected alternatives
2. **Add 3 entries to `anti-patterns.md`** from recent mistakes (3 min) — The AI will never repeat those mistakes
3. **Start a Claude Code session** and notice it respects your choices (2 min) — Verification that the system works

### Day 1 — Minimum Viable AI Architecture

| Action | Time | Impact |
|--------|------|--------|
| Run scaffold script | 2 min | Creates directory structure |
| Fill `CLAUDE.md` with project identity + quick start | 15 min | AI knows what the project is |
| Fill `technology-decisions.md` with locked stack | 15 min | AI stops proposing alternatives |
| Fill `anti-patterns.md` with 5-10 known mistakes | 20 min | AI avoids your most common issues |

**Result:** AI sessions are immediately more productive. No more re-explaining your stack.

### Week 1 — Core Conventions

| Action | Time | Impact |
|--------|------|--------|
| Fill `database-conventions.md` | 30 min | Consistent schema changes |
| Fill `api-conventions.md` | 30 min | Consistent API design |
| Fill `domain-context.md` with glossary | 20 min | AI uses correct terminology |
| Create 1 custom agent (domain expert) | 30 min | Automated domain validation |

**Result:** AI follows your conventions without reminders. Domain expert catches business rule violations.

### Week 2 — Workflow and Enforcement

| Action | Time | Impact |
|--------|------|--------|
| Write `development-workflow.md` | 45 min | Multi-phase process encoded |
| Customize `doc-check.sh` for your project | 20 min | Documentation drift caught |
| Create `task-context.md` template | 10 min | Sessions survive interruptions |
| Add `canonical-patterns.md` with reference files | 20 min | AI copies from real code |

**Result:** Changes go through proper workflow. Documentation stays in sync.

### Week 3 — Full Maturity

| Action | Time | Impact |
|--------|------|--------|
| Add 2-3 more custom agents | 1 hr | Full review coverage |
| Fill `error-recovery.md` with known issues | 30 min | AI self-diagnoses problems |
| Fill `status-lifecycles.md` | 15 min | AI respects state machines |
| Create file templates for common patterns | 30 min | Faster implementation |
| Number design decisions (DD-XX) | 30 min | Decisions are referenceable |

**Result:** Full AI architecture. Every session starts with complete context. Agents catch issues automatically. Context survives interruptions.

---

## 16. Readiness Checklist

Use this checklist to assess whether your project is ready for effective AI-driven development:

### Tier 1: Essential (Day 1)

- [ ] `CLAUDE.md` exists at project root (under 150 lines)
- [ ] `.claude/rules/technology-decisions.md` lists your locked stack
- [ ] `.claude/rules/anti-patterns.md` has at least 5 entries
- [ ] `.gitignore` includes `ctx-*` and `phase*-*` patterns

### Tier 2: Productive (Week 1)

- [ ] `.claude/rules/` has 5+ rules files covering your core conventions
- [ ] Design decisions are numbered (DD-XX) and indexed in CLAUDE.md
- [ ] At least 1 custom agent defined in `.claude/agents/`
- [ ] Directory-level `CLAUDE.md` exists for your main source directories

### Tier 3: Mature (Week 2-3)

- [ ] `.claude/settings.json` configures at least one hook
- [ ] `.claude/hooks/doc-check.sh` validates documentation sync
- [ ] `.claude/hooks/review-check.sh` reminds about review phase
- [ ] `.claude/templates/task-context.md` exists for cross-session state
- [ ] `.claude/rules/development-workflow.md` defines your multi-phase process
- [ ] `.claude/rules/canonical-patterns.md` points to reference files + templates
- [ ] `.claude/rules/error-recovery.md` has at least 10 entries
- [ ] 3+ custom agents with trigger conditions documented

### Tier 4: Fully Autonomous (Month 1+)

- [ ] All 15 rules files are filled with project-specific content
- [ ] 5+ custom agents cover domain, data, API, and testing
- [ ] Hooks escalated from warnings to blockers where appropriate
- [ ] PR template includes release notes format
- [ ] Roadmap document tracks progress and is updated at Phase 6
- [ ] Scorecard tracks project quality dimensions
- [ ] Error recovery covers 20+ known failure modes
- [ ] Templates exist for every file pattern created more than twice
- [ ] Every design decision has a DD-XX ID referenced in code and docs

---

## License

This guide is extracted from production patterns and shared for reuse. Adapt it freely for your projects.
