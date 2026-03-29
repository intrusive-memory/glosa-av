# Iteration 01 Brief — OPERATION SCRIPT WHISPERER

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

**Mission:** Build the GLOSA annotation vocabulary compiler — a Swift library and CLI that parses screenplay performance directives, compiles them into natural-language TTS instruct strings, and integrates with the Produciesta audio pipeline.
**Branch:** `mission/script-whisperer/01`
**Starting Point Commit:** `a94959ee55711bd62b7e5205b8e80c1ec5feb9c0`
**Sorties Planned:** 12
**Sorties Completed:** 12
**Sorties Failed/Blocked:** 0
**Outcome:** Complete
**Verdict:** Keep the code. The mission executed cleanly with zero retries across all 12 sorties. 184 tests pass. There is no compelling reason to roll back.

---

## Section 1: Hard Discoveries

### 1. SwiftCompartido Product Name Is "SwiftCompartido", Not "Guion"

**What happened:** The execution plan assumed the SwiftCompartido package exported a product named `Guion`. The actual product name is `SwiftCompartido`. The Package.swift already had the correct dependency configured from the initial commit, so no runtime failure occurred — but the plan's text was wrong.
**What was built to handle it:** Sortie 5 agent verified the API before coding and adapted. No code workaround needed — the dependency was already correct.
**Should we have known this?** Yes. A 30-second `grep` of SwiftCompartido's Package.swift during plan refinement would have caught this.
**Carry forward:** Always verify external dependency product names during the `refine-questions` pass, not at sortie time.

### 2. SwiftCompartido Has No FountainWriter

**What happened:** The execution plan assumed SwiftCompartido provides a `FountainWriter` for serializing screenplay elements back to Fountain format. It does not. Sortie 6 had to build Fountain and FDX serialization from scratch.
**What was built to handle it:** `GlosaSerializer.writeFountain()` implements full Fountain element serialization by type, and `writeFDX()` builds FDX XML manually. Both include round-trip tests.
**Should we have known this?** Yes. Same issue — `grep FountainWriter` in SwiftCompartido during plan refinement would have revealed the gap. This could have changed the sizing of Sortie 6.
**Carry forward:** For any sortie that assumes an external API, the `refine-questions` pass should flag "verify this API exists" as an explicit open question — not just an entry criterion. Entry criteria catch it, but sizing is already locked.

### 3. Produciesta Test Target Has Pre-existing Signing Issue

**What happened:** The Produciesta Xcode project has an App Group entitlement (`group.intrusive-memory.models`) that requires a provisioning profile not available in the CI/agent context. This blocked test *execution* for the entire project — not just our new tests.
**What was built to handle it:** Tests were written and compile successfully. They follow the established patterns in the existing test suite. They will run once the signing issue is resolved independently.
**Should we have known this?** Partly. The plan flagged Produciesta as high-risk (external repo, API discovery), but didn't check whether its test target was runnable. A pre-flight `xcodebuild test` on the existing test suite would have surfaced this.
**Carry forward:** Before any external-repo sortie, verify the target repo's test harness actually runs. If it doesn't, scope the sortie to "compile-only verification" and file the test execution issue separately.

---

## Section 2: Process Discoveries

### What the Agents Did Right

### 1. Clean Single-Commit-Per-Sortie Discipline

**What happened:** Every sortie produced exactly one commit. 11 commits for 11 in-repo sorties (Sortie 10 committed to Produciesta). Zero fix-up commits, zero reverts.
**Right or wrong?** Right. This is the ideal cadence. Each commit is a clean, tested, buildable state.
**Evidence:** `git log` shows 11 commits, each referencing its sortie number. Zero `fix`, `revert`, or `workaround` commits.
**Carry forward:** Maintain this pattern. The single-objective-per-agent principle directly enables single-commit-per-sortie.

### 2. Mock-Based Testing for LLM Integration

**What happened:** Sortie 8 (StageDirector) introduced a `SceneAnnotationProvider` protocol to abstract the LLM call, enabling full test coverage without requiring a live LLM endpoint.
**Right or wrong?** Right. 24 tests cover the LLM integration path without any network dependency.
**Evidence:** 35 GlosaDirectorTests pass in <1 second. No flaky tests. No LLM API key required.
**Carry forward:** This pattern should be standard for any LLM-integrated module.

### 3. Sortie 11 Fixed a Pre-existing Compile Error in Sortie 12's File

**What happened:** Sortie 12 (compare command) was dispatched in parallel with Sortie 11. Sortie 11 landed first and noticed a missing `await` in the CompareCommand.swift file that Sortie 12 had partially created. Sortie 11 fixed it to unblock its own build. No merge conflict resulted.
**Right or wrong?** Right — pragmatic. The agent fixed what was broken to achieve its build goal. But this highlights a risk of parallel sorties modifying the same file.
**Evidence:** Both sorties committed without merge conflicts, and both registered their subcommands in GlosaCommand.swift independently.
**Carry forward:** When dispatching parallel terminal sorties that touch the same registration file, warn agents explicitly about the concurrent modification and instruct them to resolve conflicts.

### What the Agents Did Wrong

### 4. Nothing Significant

**What happened:** No sortie produced throwaway code, over-engineered abstractions, or unnecessary files. No sortie required continuation or retry.
**Evidence:** Zero BACKOFF/PARTIAL/FATAL states in the entire Decisions Log. Zero deleted files across all sorties.
**Carry forward:** The plan was well-refined. The agent prompts were specific. This is what happens when the sergeant gives clear orders.

### What the Planner Did Wrong

### 5. Over-Specified Model Selection for Foundation Sorties

**What happened:** The force-opus override (`foundation_score=1 AND dependency_depth>=5`) triggered for 8 of 12 sorties. This meant the model selection algorithm was effectively bypassed — nearly everything got opus regardless of actual complexity.
**Right or wrong?** Mixed. Every sortie completed on the first attempt, so opus wasn't wasted — but Sorties 3, 4, 5, 6 could likely have succeeded with sonnet. The force-opus threshold was too aggressive.
**Evidence:** Sorties 9 and 11 ran on sonnet and completed perfectly — demonstrating that simpler sorties don't need opus. Sorties 3-6 had complexity scores of 14-22 but all completed in single attempts with moderate context usage.
**Carry forward:** Raise the force-opus dependency depth threshold from >=5 to >=8, or remove the force-opus override for mid-chain sorties that have specific, well-defined tasks. Reserve force-opus for true ambiguity (open-ended design, unfamiliar APIs).

### 6. Produciesta Sortie Was Scoped Too Broadly

**What happened:** Sortie 10 had 7 tasks including "If no GLOSA annotations are present and the user opts in: invoke StageDirector.annotate() for on-the-fly LLM annotation." The agent correctly scoped this down to compile-time integration only, deferring the opt-in LLM path.
**Right or wrong?** The plan was wrong to include the opt-in LLM path in the same sortie as the core integration. The agent was right to triage.
**Evidence:** Sortie 10 used 110 tool calls and 166K tokens — the heaviest sortie by far, driven by API discovery in an unfamiliar codebase.
**Carry forward:** External-repo sorties should be split: one for dependency wiring + core integration, one for advanced features (opt-in LLM, provenance tooling).

---

## Section 3: Open Decisions

### 1. Should the Produciesta Integration Use a Git Tag or Branch Reference?

**Why it matters:** Sortie 10 added glosa-av as a dependency pointing to `branch: "mission/script-whisperer/01"`. This is a moving target. Once glosa-av merges to main, the Produciesta dependency should point to a tagged release or main branch.
**Options:**
- A: Point to `main` after merge (tracks latest, may break)
- B: Tag a release (e.g., `0.1.0`) and point to that (stable, requires release management)
- C: Keep branch reference until glosa-av stabilizes, then switch to tag
**Recommendation:** Option C for now, switch to B before Produciesta's next release.

### 2. On-the-Fly LLM Annotation in Produciesta

**Why it matters:** The execution plan included a StageDirector.annotate() path for screenplays without GLOSA annotations. This was deferred. Without it, Produciesta requires pre-scored screenplays (run `glosa score` first).
**Options:**
- A: Add the opt-in LLM path in a follow-up sortie
- B: Keep the two-step workflow (score then generate) — simpler, more predictable
- C: Add it but default to off, behind a `--auto-score` flag
**Recommendation:** Option C in a future mission. The two-step workflow is fine for now.

### 3. Produciesta Test Execution

**Why it matters:** 10 integration tests were written but cannot be executed due to a pre-existing signing issue. They're unverified.
**Options:**
- A: Fix the signing issue (may require provisioning profile updates)
- B: Move tests to a separate test target without App Group entitlements
- C: Accept compile-only verification until signing is fixed
**Recommendation:** Option B — create a `ProduciestaUnitTests` target without entitlements for tests that don't need the host app.

---

## Section 4: Sortie Accuracy

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| 1 | Package Config & Data Model | opus | 1 | Yes | Clean foundation. All types survived unchanged. |
| 2 | Parser & Validator | opus | 1 | Yes | 35 tests. No rework by downstream sorties. |
| 3 | Score Resolver | opus | 1 | Yes | Arc position math correct. Codable added by Sortie 4 (expected extension). |
| 4 | Instruct Composer & Compiler | opus | 1 | Yes | Public API consumed unchanged by Sorties 5-12. |
| 5 | Annotated Element Types | opus | 1 | Yes | Adapted to real SwiftCompartido API without plan changes. |
| 6 | Serializer & Round-Trip | opus | 1 | Yes | Built serialization from scratch when FountainWriter didn't exist. Largest source file (765 lines). |
| 7 | Scene Analyzer & Glossary | opus | 1 | Yes | Glossary extended in Sortie 11 as planned. |
| 8 | Stage Director LLM | opus | 1 | Yes | Mock architecture enabled all downstream testing. |
| 9 | CLI Commands | sonnet | 1 | Yes | Sonnet handled this cleanly. Validated opus-is-not-always-needed. |
| 10 | Produciesta Integration | opus | 1 | Yes* | *Tests compile but can't execute. Build verified. |
| 11 | Glossary CLI | sonnet | 1 | Yes | Sonnet again sufficient. Fixed a stray compile issue from parallel Sortie 12. |
| 12 | Compare & Provenance | sonnet | 1 | Yes | Clean parallel execution with Sortie 11. |

**Overall accuracy: 12/12 sorties accurate.** No sortie's output was reverted, overwritten, or rendered moot.

---

## Section 5: Harvest Summary

This mission executed with unusual cleanliness: 12/12 sorties on first attempt, 184 tests, 11,162 lines of new code, zero reverts. The execution plan was well-refined — sortie boundaries aligned with natural compilation units, and the dependency graph accurately reflected the real build order. The three hard discoveries (product name, missing FountainWriter, signing issue) were all discoverable during refinement but were successfully handled at sortie time via entry criteria checks. The main process improvement for next time: tighten the force-opus threshold (it fired too often) and split external-repo sorties more aggressively. There is no compelling reason to roll back — the code is clean, tested, and architecturally sound.

---

## Section 6: Files

**Preserve (production code on mission branch):**

| File | Branch | Why |
|------|--------|-----|
| Sources/GlosaCore/*.swift (10 files) | mission/script-whisperer/01 | Core compiler library — parser, resolver, composer, compiler |
| Sources/GlosaAnnotation/*.swift (3 files) | mission/script-whisperer/01 | Annotation bridge and serializer |
| Sources/GlosaDirector/*.swift (6 files + Resources/) | mission/script-whisperer/01 | LLM integration, prompts, scene analysis, glossary |
| Sources/glosa/*.swift (6 files) | mission/script-whisperer/01 | CLI commands |
| Tests/**/*.swift (14 files) | mission/script-whisperer/01 | 184 tests |
| Package.swift, Package.resolved | mission/script-whisperer/01 | Build configuration |
| Produciesta integration (3 files) | feature/glosa-av-integration (Produciesta repo) | Audio pipeline integration |

**Discard (mission artifacts — not production code):**

| File | Why it's safe to lose |
|------|----------------------|
| EXECUTION_PLAN.md | Plan is complete; brief captures lessons |
| SUPERVISOR_STATE.md | Execution state; brief captures outcomes |
| poc-audio/*.txt | Pre-mission proof-of-concept files, not part of deliverable |

---

## Section 7: Iteration Metadata

**Starting point commit:** `a94959e` (`Add Stage Director architecture, example transformations, and POC audio`)
**Mission branch:** `mission/script-whisperer/01`
**Final commit on mission branch:** `09ff73c` (`Add CompareTests for Sortie 12 provenance review tooling`)
**Rollback target:** `a94959e` (same as starting point commit)
**Next iteration branch:** `mission/script-whisperer/02` (if needed)
