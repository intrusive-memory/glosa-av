---
feature_name: OPERATION SKELETON EVICTION
iteration: 1
state: completed
---

# Iteration 01 Brief — OPERATION SKELETON EVICTION

**Mission:** Decouple glosa-av into a Foundation-only `GlosaCore` leaf — public inline-notes stripper (FR1), compile-to-DTO API (FR2), rehome the tool tier into `../glosa-tools` (FR0), CI leaf-guard + release prep (FR3).
**Branch:** mission/skeleton-eviction/01
**Starting Point Commit:** 1d9ff321d0ff4998c96b0f07ee3dfd301d5de4d5
**Sorties Planned:** 6
**Sorties Completed:** 6
**Sorties Failed/Blocked:** 0
**Duration:** 6 sortie dispatches, single supervising agent; every sortie passed on attempt 1.
**Outcome:** Complete
**Verdict:** `KEEP` — all six sorties landed on the first attempt behind machine-verified build/test gates; zero retries, zero non-CI-safe tests, clean leaf invariant proven both directions.
**Tests pruned:** 0
**Tests flagged for review:** 0

---

## Section 1: Hard Discoveries

### 1. GlosaCore is a *product of the glosa-av package*, coupling S3 and S4 through SPM resolution

**What happened:** The plan treated S3 (move the tool tier out) and S4 (reduce glosa-av's manifest to a leaf) as cleanly separable. They are not. `GlosaCore` is vended by the glosa-av *package*, so `glosa-tools` must depend on the glosa-av package (local sibling path `../glosa-av`) to consume `GlosaCore`. That requires glosa-av to remain a **valid, resolvable package** the entire time. But S3 removes `Sources/GlosaAnnotation|GlosaDirector|glosa` while the manifest still declares them as targets — making glosa-av unresolvable, so glosa-tools couldn't build, so S3's own exit criterion (`swift_package_build` on glosa-tools) was unsatisfiable until S4.
**What was built to handle it:** S3's dispatch was expanded to also make the *minimal* glosa-av manifest edit (drop the moved products/targets, keep `GlosaCore` + `GlosaCoreTests`), leaving the dead dependency *entries* for S4 to prune. Clean split: S3 = "rehome, both packages resolve"; S4 = "prune dead deps + prove AC0."
**Should we have known this?** Yes. Inspecting `Package.swift` before planning would have revealed that `GlosaCore` is a package product, not its own repo. The plan's OQ-1 wording ("pin GlosaCore via sibling") implied a standalone GlosaCore checkout that does not exist.
**Carry forward:** When a sortie moves source out of a package that another package depends on *for a product*, the manifest-validity edit must travel with the *move* sortie, not the later cleanup sortie. State this as a precondition in any future split.

### 2. Reducing to a single product renames the Xcode-generated scheme `glosa-av-Package` → `glosa-av`

**What happened:** With multiple products, SwiftPM generates a `<package>-Package` aggregate scheme. After the leaf reduction (one product), that scheme ceased to exist; the only scheme is `glosa-av`. Every plan exit-criterion command, the Makefile (`PACKAGE_SCHEME`), and `tests.yml` referenced the now-nonexistent `glosa-av-Package`.
**What was built to handle it:** Supervisor switched all local build/test gates to `-scheme glosa-av`; S5 was expanded to fix the two `tests.yml` scheme references.
**Should we have known this?** Partially. The scheme-name dependence on product count is a known-but-easily-forgotten SwiftPM behavior.
**Carry forward:** Any sortie that changes a package's product set must audit every hardcoded `-scheme` reference (CI, Makefile, docs) in the same change.

### 3. "Reduce to a leaf" broke more CI than the AC0-guard task accounted for

**What happened:** The leaf has no CLI and no GlosaAnnotation/GlosaDirector. That invalidated the `integration-tests` job (`make release` → `./bin/glosa`) and made the library-`print()` grep target two directories that no longer exist — neither of which the plan's narrowly-scoped S5 ("add the AC0 guard") addressed.
**What was built to handle it:** S5 was expanded to remove the dead `integration-tests` job and trim the print-grep to `Sources/GlosaCore`, in addition to the AC0 guard. Verified safe against branch protection: `development` is unprotected and `main` requires only the `"Unit Tests"` check, so no `required_status_checks` change was needed.
**Should we have known this?** Yes. "Move the CLI out" obviously orphans CLI-based CI jobs. The plan should have folded a CI-reconciliation task into S5 from the start.
**Carry forward:** A decoupling mission must inventory *all* CI jobs that exercise the moved code and reconcile them in the same mission, not just add the new guard.

---

## Section 2: Process Discoveries

#### What the Agents Did Right
### 1. Supervisor-owns-the-build model held perfectly
**What happened:** Per the plan's hard constraint, every sub-agent made code changes only and never built; the supervising agent ran all build/test/AC0 gates.
**Right or wrong?** Right. Every sortie was verified against the real toolchain, catching nothing-wrong-but-trust-nothing. Self-authored tests (a known risk) were validated by the supervisor running them, not by the author's say-so.
**Evidence:** 6/6 sorties passed their gates on attempt 1; AC2 round-trip and AC0 both-arms tests were run by the supervisor independently of the authoring agent.
**Carry forward:** Keep this model for any mission where sub-agents can't self-verify.

#### What the Agents Did Wrong
### 2. Minor scope shortcuts left two small gaps
**What happened:** S2 substituted a positional-breath fixture for the requested explicit `after=` fixture; S6 left the README Architecture/Testing prose describing the moved tool tier (scoped to the install snippet only).
**Right or wrong?** Acceptable but worth noting. S2's substitution still exercised the critical unicode-scalar arithmetic; S6's omission was within its stated scope.
**Evidence:** Agent self-reports + `grep` confirm stale README prose.
**Carry forward:** Stale-doc cleanup should be an explicit task when a mission moves code between packages.

#### What the Planner Did Wrong
### 3. S3/S4 coupling and S5 under-scoping (see Hard Discoveries 1 & 3)
**What happened:** The plan modeled two coupled operations as independent and under-scoped the CI reconciliation.
**Right or wrong?** Wrong, but low-cost — the supervisor reconciled both at dispatch time without a retry.
**Evidence:** S3 dispatch absorbed the manifest-validity edit; S5 dispatch absorbed scheme/print-grep/integration-job fixes. Both documented in the Decisions Log.
**Carry forward:** Pre-flight every "move/decouple" plan by reading the manifest topology and the CI jobs first.

---

## Section 3: Open Decisions

### 1. glosa-tools remote + release + CI
**Why it matters:** glosa-tools is a local-only sibling (OQ-1) with no GitHub remote, no release, and no CI. Its `sibling("glosa-av", from: "0.5.0")` pin only resolves remotely once glosa-av v0.5.0 is tagged; until then glosa-tools builds only with the local glosa-av checkout present.
**Options:** (A) follow-up mission to publish glosa-tools after glosa-av v0.5.0 is tagged; (B) leave local-only indefinitely.
**Recommendation:** (A) — schedule a glosa-tools publish mission immediately after glosa-av v0.5.0 ships.

### 2. Stale README + dead Makefile in the leaf
**Why it matters:** The README still documents GlosaAnnotation/GlosaDirector/the CLI as part of glosa-av, and the Makefile is entirely CLI-oriented (`SCHEME=glosa`, `BINARY=glosa`) — dead weight now that the CLI lives in glosa-tools.
**Options:** (A) trim both in glosa-av and move the CLI Makefile to glosa-tools; (B) defer to the glosa-tools publish mission.
**Recommendation:** (A) for the README prose (cheap, avoids misleading consumers); move the Makefile with the glosa-tools publish mission.

---

## Section 4: Sortie Accuracy

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| S1 | FR1 GlosaInlineNotes stripper + parser dedup | opus | 1 | ✓ | Byte-identical refactor proven by AC1 equivalence suite; survived unchanged. |
| S3 | FR0 move tool tier → glosa-tools | opus | 1 | ✓ | Largest sortie; cross-repo move + manifest authoring + CLI refactor, all green. Absorbed the S3/S4 coupling fix. |
| S4 | FR0 reduce glosa-av to leaf | sonnet | 1 | ✓ | AC0 zero forbidden tokens; show-dependencies empty. |
| S2 | FR2 GlosaLineAnnotation + compileAnnotations | sonnet | 1 | ✓ | AC2 unicode round-trip lossless; back-compat preserved (additions only). Minor fixture substitution. |
| S5 | AC0 CI guard + CI reconciliation | sonnet | 1 | ✓ | Guard tested both arms by supervisor; scheme/print-grep/integration-job reconciled. |
| S6 | FR3 release prep (0.5.0, changelog) | sonnet | 1 | ✓ | Manifest already release-shaped; toggle-sibling no-op. README prose left stale (scoped out). |

Every sortie's output survived into the final state. No reverts, no rework, no deletions of prior-sortie work. Model selection was accurate: the one opus override (S1, foundation+depth) and the opus pick for the largest sortie (S3) were justified; no sonnet sortie needed an upgrade.

## Section 5: Harvest Summary

The single most important thing learned: **package topology and CI surface must be read before planning a decouple.** Two of the three hard discoveries (S3/S4 SPM coupling, S5 CI breakage) were knowable from `Package.swift` and `tests.yml` alone, and both forced the supervisor to expand sortie scope at dispatch time. The mission still landed cleanly because the supervisor-owns-the-build model surfaced every issue at a real gate, but a 15-minute pre-flight read of the manifest and workflow would have folded those expansions into the plan. Test cleanup pruned 0 of 2 mission tests — both new GlosaCoreTests suites are hermetic and CI-safe; no systemic test-quality issue.

## Section 6: Files

**Preserve (read-only reference for next iteration):**
| File | Branch | Why |
|------|--------|-----|
| `OPERATION_SKELETON_EVICTION_01_BRIEF.md` | mission/skeleton-eviction/01 | This brief — inputs to the glosa-tools publish mission. |
| `../glosa-tools/` (repo) | master | The evicted tool tier; needs remote+release+CI in a follow-up. |

**Discard (will not exist after rollback):**
| File | Why it's safe to lose |
|------|----------------------|
| _(none — verdict is KEEP; nothing to discard)_ | — |

## Iteration Metadata

**Starting point commit:** `1d9ff32` (Phrasing WIP committed pre-mission on development)
**Mission branch:** `mission/skeleton-eviction/01`
**Final commit on mission branch:** `17c690c`
**Rollback target:** `1d9ff32` (same as starting point commit) — not exercised (KEEP)
**Next iteration branch:** n/a (mission KEPT; follow-up is a new mission: publish glosa-tools)

## Rollback Verdict

**Verdict:** `KEEP`

**Reasoning:** All four work units reached COMPLETED with zero retries and zero BLOCKED/FATAL states (Section 4). Every acceptance criterion was machine-verified by the supervisor: AC0 (both arms), AC1 (parser equivalence), AC2 (unicode round-trip), AC3 (leaf build+tests), AC4 (relocated tests green). Test cleanup removed 0% of mission tests (Section 5). The three hard discoveries were planning gaps the supervisor absorbed at dispatch time without rework — they make the *next* plan better, not this branch worse.

**Recommended action:**
- Merge `mission/skeleton-eviction/01` into `development` (PR target per project convention; CI's new leaf-guard + fixed scheme will gate it).
- Follow-up tickets: (1) publish glosa-tools (remote + release + CI) after glosa-av v0.5.0 is tagged; (2) trim stale README Architecture/Testing prose and relocate the CLI Makefile to glosa-tools.
- Tag glosa-av v0.5.0 via `/ship-swift-library` (human-gated) once the PR merges.
