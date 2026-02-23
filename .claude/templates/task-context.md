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
- [ ] `aura-config-expert` (any TOML config changes)
- [ ] `core:code-reviewer` (always)
- [ ] `core:qa-engineer` (always)

---

## Phase 1 — Planning Output
### Aura Config Expert
- Key decisions:
- Constraints:

---

## Phase 2 — Synthesized Plan
### Confirmed Requirements
1. [Requirement]

### Acceptance Criteria
- [ ] AC-1: [criterion]

### Task Breakdown
- [ ] Task 1: [description]

---

## Phase 3 — Implementation Notes
### Files Changed
| File | What Changed |
|------|-------------|

---

## Phase 3.5 — Validation Results
- [ ] Config validation — pass/fail
- [ ] Docker build test — pass/fail (if applicable)

---

## Phase 4 — Review Findings
### Blocking
| # | Finding | Reviewer | File:Line |
|---|---------|----------|-----------|

### Advisory
| # | Finding | Reviewer | File:Line |
|---|---------|----------|-----------|

---

## Phase 5 — Fix & Iterate
### Iteration 1
- Fixed: [description]
- Re-validated: pass/fail

---

## Phase 6 — Ship
### Release Notes Entry
**Category:** Added | Changed | Fixed | Removed
[Summary]

### Ship Checklist
- [ ] Release notes written above
- [ ] Documentation updated
- [ ] PR created: [URL]
