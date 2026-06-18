---
feature_name: OPERATION SKELETON EVICTION
iteration: 1
state: completed
---

# SUPERVISOR_STATE.md — OPERATION SKELETON EVICTION

> **Terminology**: A *mission* is the definable scope of work. A *sortie* is an
> atomic agent task within that mission. A *work unit* groups sorties.

## Mission Metadata

- Operation: **OPERATION SKELETON EVICTION**
- Mission: Decouple glosa-av into a Foundation-only `GlosaCore` leaf — public
  inline-notes stripper (FR1), compile-to-DTO API (FR2), rehome tool tier into
  `../glosa-tools` (FR0), CI leaf-guard + release prep (FR3).
- Iteration: 1
- Starting point commit: `1d9ff321d0ff4998c96b0f07ee3dfd301d5de4d5`
- Mission branch: `mission/skeleton-eviction/01`
- max_retries: 3
- Pre-build dependency purge: run (DerivedData + SPM cache + Package.resolved cleared)
- Purge ran at: 2026-06-17
- intrusive-memory floors bumped: 0 of 3 (SwiftCompartido 7.0.5 / SwiftBruja 1.7.1 / SwiftAcervo 0.19.2 already at latest release)

## Plan Summary

- Work units: 4
- Total sorties: 6
- Dependency structure: layered (0 → 1 → 2 → 3)
- Dispatch mode: dynamic (Approach B — no template in plan)
- Recommended order: S1 → S3 → S4 → S2 → S5 → S6
- Agent constraint: **sub-agents do NOT run builds**; the supervising agent owns
  every compile/test gate (verification cascade §3). Sub-agents make code changes
  only.

## Work Units

| Name | Directory | Sorties | Layer | Dependencies |
|------|-----------|---------|-------|--------------|
| GlosaCore-API | `Sources/GlosaCore` | S1, S2 | 0–1 | none |
| glosa-tools | `../glosa-tools` (new sibling) | S3 | 1 | GlosaCore-API (S1) |
| glosa-av-leaf | `Package.swift` (root) | S4 | 2 | glosa-tools (S3) |
| ci-and-release | `.github/workflows`, root | S5, S6 | 3 | glosa-av-leaf (S4) + GlosaCore-API (S2, for S6) |

### Sortie dependency edges
- S1 → S2 (within GlosaCore-API; S2 needs `GlosaInlineNotes.split`)
- S1 → S3 (CLI routes its stripper through `GlosaInlineNotes`)
- S3 → S4 (tool-tier sources gone before manifest drops their deps)
- S4 → S5 (CI guard locks in the leaf invariant)
- S4 + S5 + S2 → S6 (release prep needs leaf manifest, CI guard, FR2 DTO)

## Per-Work-Unit State

### GlosaCore-API
- Work unit state: COMPLETED
- Current sortie: S2 of 2 (S1 + S2 COMPLETED)
- Sortie state: COMPLETED
- Sortie type: code
- Model: sonnet (S2); opus (S1)
- Complexity score: 9 (S2); 17 (S1)
- Attempt: 1 of 3 (S2)
- Last verified: S2 — build SUCCEEDED + AC2a offset indexing (emoji+combining), AC2b unicodeScalars round-trip lossless, OQ-3 pause-mapping projection all pass; compile()/CompilationResult unchanged (additions only). Committed c2388ca.
- Notes: GlosaCore-API DONE. Minor: S2 used positional breaths instead of an explicit after= fixture (acceptable — scalar arithmetic still exercised).

### glosa-tools
- Work unit state: COMPLETED
- Current sortie: S3 of 1 (COMPLETED)
- Sortie state: COMPLETED
- Sortie type: code
- Model: opus
- Complexity score: 22
- Attempt: 1 of 3
- Last verified: glosa-tools BUILD SUCCEEDED + TEST SUCCEEDED (relocated Annotation/Director/CLI swift-testing suites green — AC4); moved dirs absent from glosa-av; CLI delegates to GlosaInlineNotes.strip. glosa-av commit f9db2e1 (code-only after amend); glosa-tools initial commit 0fb560c.
- Notes: Coupling resolved — glosa-av left as resolvable GlosaCore-only package with dead dep entries for S4.

### glosa-av-leaf
- Work unit state: COMPLETED
- Current sortie: S4 of 1 (COMPLETED)
- Sortie state: COMPLETED
- Sortie type: code
- Model: sonnet
- Complexity score: 7
- Attempt: 1 of 3
- Last verified: AC0 grep zero matches; `swift package show-dependencies` → dependencies []; leaf build SUCCEEDED + all GlosaCore suites pass (AC3). Committed 5bddeb5.
- Notes: ⚠️ Scheme renamed `glosa-av-Package` → `glosa-av` (single-product package). S5 must reconcile CI/workflow scheme references.

### ci-and-release
- Work unit state: COMPLETED
- Current sortie: S6 of 2 (S5 + S6 COMPLETED)
- Sortie state: COMPLETED
- Sortie type: code
- Model: sonnet (S5, S6)
- Complexity score: 6 (S5), 8 (S6)
- Attempt: 1 of 3
- Last verified: S5 — YAML valid (jobs code-quality + unit-tests, macos-26); AC0 guard both arms tested (clean leaf exit 0, injected SwiftBruja exit 1); scheme→glosa-av; integration-tests job removed; required_status_checks still ["Unit Tests"]. Committed 3814905.
- Notes: S6 (release prep) now unlocked (S2✅+S4✅+S5✅). Next minor over v0.4.0 = 0.5.0.

## Active Agents

| Work Unit | Sortie | Sortie State | Attempt | Model | Complexity Score | Task ID | Output File | Dispatched At |
|-----------|--------|-------------|---------|-------|------------------|---------|-------------|---------------|
| GlosaCore-API | S1 | COMPLETED | 1/3 | opus | 17 | aea15c71ed6e6b598 | tasks/aea15c71ed6e6b598.output | 2026-06-17 |
| glosa-tools | S3 | COMPLETED | 1/3 | opus | 22 | ad9e9533ff0461c6e | tasks/ad9e9533ff0461c6e.output | 2026-06-17 |
| glosa-av-leaf | S4 | COMPLETED | 1/3 | sonnet | 7 | afd85fdf622011233 | tasks/afd85fdf622011233.output | 2026-06-17 |
| GlosaCore-API | S2 | COMPLETED | 1/3 | sonnet | 9 | af9d347d968830930 | tasks/af9d347d968830930.output | 2026-06-17 |
| ci-and-release | S5 | COMPLETED | 1/3 | sonnet | 6 | ab69e39916baaa0d1 | tasks/ab69e39916baaa0d1.output | 2026-06-17 |
| ci-and-release | S6 | COMPLETED | 1/3 | sonnet | 8 | a2a148d42dd204a3a | tasks/a2a148d42dd204a3a.output | 2026-06-17 |

## Decisions Log

| Timestamp | Work Unit | Sortie | Decision | Rationale |
|-----------|-----------|--------|----------|-----------|
| 2026-06-17 | — | — | Committed pre-existing Phrasing WIP on `development` (1d9ff32) before forking mission branch | Working tree was dirty in `Sources/glosa` + `Sources/GlosaDirector` — exactly the dirs Sortie 3 git-mv's. User directive: commit if it compiles, stash if it breaks. Build SUCCEEDED → committed. Mission forks from clean tree. |
| 2026-06-17 | GlosaCore-API | S1 | Model: opus (score 17) | foundation_score=1 (establishes GlosaInlineNotes API for S2 & S3) + dependency depth 5 (blocks all downstream) → Force Opus override; byte-identical parser refactor is delicate. |
| 2026-06-17 | GlosaCore-API | S1 | S1 COMPLETED, committed d1a2edc | Build + GlosaCoreTests green incl. AC1 equivalence suite; parser dedup verified by grep. |
| 2026-06-17 | glosa-tools/glosa-av-leaf | S3/S4 | S3 also reduces glosa-av manifest (drop moved products/targets) — NOT a plan deviation, a mechanical necessity | glosa-tools depends on the glosa-av PACKAGE for the GlosaCore product; glosa-av must stay resolvable. S3 leaves dead dep entries for S4 to prune + prove AC0. Plan's S3/S4 are coupled by SPM resolution. |
| 2026-06-17 | glosa-tools | S3 | Model: opus (score 22) | Largest sortie: new package + cross-repo move + manifest authoring + CLI refactor; high mechanical risk. |
| 2026-06-17 | glosa-av-leaf | S4 | S4 COMPLETED, committed 5bddeb5 | AC0 zero forbidden tokens; show-dependencies empty; leaf build+tests green (AC3). |
| 2026-06-17 | glosa-av-leaf → ci | S4/S5 | ⚠️ Build scheme renamed `glosa-av-Package` → `glosa-av` after leaf reduction (single product → no `-Package` aggregate scheme) | S5 (CI tests.yml) and the plan's documented build commands reference `glosa-av-Package`; S5 must update CI to `-scheme glosa-av` or CI will fail to find the scheme. |
| 2026-06-17 | GlosaCore-API | S2 | Model: sonnet (score 9) | Precisely specified (exact fields + OQ-3 constants) → sonnet sufficient; AC2 round-trip gate catches offset errors → BACKOFF forces opus on retry if needed. |
| 2026-06-17 | ci-and-release | S5 | EXPANDED S5 scope beyond plan: also fix unit-tests scheme glosa-av-Package→glosa-av, trim print-grep to GlosaCore, remove dead integration-tests job | Leaf reduction broke existing CI: scheme renamed; GlosaAnnotation/GlosaDirector grep targets gone; integration-tests `make release` builds the now-absent glosa CLI. Branch protection: `development` unprotected, `main` requires only "Unit Tests" → removing the (non-required) integration-tests job needs NO branch-protection change; OQ-4 "required_status_checks unchanged" still holds. |
| 2026-06-17 | ci-and-release | — | FINDING (for brief, not fixed): Makefile is fully CLI-oriented (SCHEME=glosa, BINARY=glosa) and is dead weight in the leaf | The CLI + its Makefile logically belong to glosa-tools now. Left in place but unexercised once integration-tests job removed. Recommend moving to glosa-tools in a follow-up. |

## Overall Status

- Mission **COMPLETED** — all 6 sorties verified & committed on `mission/skeleton-eviction/01`.
- All 4 work units COMPLETED. No FATAL/BLOCKED states; every sortie passed on attempt 1.
- Mission commits: d1a2edc (S1) · f9db2e1 (S3) · 5bddeb5 (S4) · c2388ca (S2) · 3814905 (S5) · 17c690c (S6).
- Sibling repo created: ../glosa-tools (initial commit 0fb560c, branch master, no remote per OQ-1).
- Findings for brief: (1) dead CLI-oriented Makefile in the leaf; (2) README Architecture/Testing prose still describes the moved tool tier (stale); (3) glosa-tools needs its own CI + remote/release in a follow-up mission.
- Next: post-mission auto-chain → test-cleanup → brief → clean.
