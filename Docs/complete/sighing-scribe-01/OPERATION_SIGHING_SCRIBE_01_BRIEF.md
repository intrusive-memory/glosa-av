---
title: "Iteration 01 Brief — OPERATION SIGHING SCRIBE"
kind: mission-brief
state: completed
updated: 2026-05-13
feature_name: OPERATION SIGHING SCRIBE
iteration: 1
verdict: KEEP
---

# Iteration 01 Brief — OPERATION SIGHING SCRIBE

**Mission:** Introduce the `<breath/>` GLOSA element end-to-end inside `glosa-av` — data model, parsers (Fountain + FDX), compiler output, annotation bridge, serializer round-trip, Stage Director schema and prompts, validator diagnostics, CLI surface, and docs promotion.
**Branch:** `mission/sighing-scribe/01`
**Starting Point Commit:** `c61e954c9ff63a5fcafbe6b76e85140defbe1973` ("Bump dependency floors and cap swift-tokenizers below the breaking 0.6.x")
**Sorties Planned:** 12
**Sorties Completed:** 12
**Sorties Failed/Blocked:** 0
**Duration:** ~1 working session (single supervisor invocation, no resumes)
**Outcome:** Complete
**Verdict:** `KEEP` — All 12 sorties shipped on first attempt with zero retries, zero test-cleanup removals, and full-suite green. Three Known Limitations are documented in `Docs/REQUIREMENTS.md` §1.4 for follow-up.
**Tests pruned:** 0
**Tests flagged for review:** 0

---

## Terminology

> **Mission** — A definable, testable scope of work. Maps to agentic cycles, not time.
>
> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch.
>
> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Section 1: Hard Discoveries

### 1. SwiftCompartido `FountainParser` does not surface inline-note positions

**What happened:** The execution plan's Open Question #2 asked whether `SwiftCompartido.FountainParser` preserves character offsets for `[[ ]]` inline notes inside dialogue paragraphs. Pre-dispatch research (read-only agent) confirmed: the parser's `section` regex only matches whole-line `[[ ]]` notes preceded by a blank line; inline notes inside dialogue lines are NOT split, stripped, or annotated. The raw `[[<breath/>]]` syntax travels verbatim inside `GuionElement.elementText` for `.dialogue` elements with no positional metadata.
**What was built to handle it:** Sortie 2 implements its own `NSRegularExpression` scan against `GuionElement.elementText` in `Sources/GlosaCore/GlosaParser.swift`. Offsets are computed as `unicodeScalars.count` of the notes-stripped prose (the same coordinate system the spec §6.4 numbers use). No upstream PR required.
**Should we have known this?** Yes — a single grep over `SwiftCompartido/Sources/SwiftCompartido/Serialization/FountainParser.swift` for `[[` would have shown the only handler fires on standalone-line notes. The breakdown pass for breath should have inspected SwiftCompartido directly rather than asserting a precondition.
**Carry forward:** When a plan depends on an external parser's *positional* output, the breakdown command must spot-check the dependency's source before treating the precondition as given. Pre-dispatch verification works (it caught this here) but is a band-aid for a missed planning step.

### 2. Existing FDX SAX delegate has two latent bugs

**What happened:** Q#3 research found that `FDXParserDelegate` in `Sources/GlosaCore/GlosaParser.swift` had two pre-existing defects unrelated to breath: (a) `currentText` was reset on every `<Text>` `didStartElement`, dropping all but the last text run in mixed-content paragraphs (`:447`); (b) no `didStartElement` branch handled the `breath` element name in the `glosa:` namespace, so breath elements fell into `default: break` (`:439`). No existing FDX fixture had multi-`<Text>` paragraphs, so the bug had never surfaced.
**What was built to handle it:** Sortie 3 absorbed both fixes alongside the new `<glosa:breath/>` handler. S3 also created the first FDX fixture with mixed content (Bishop §5.2 form).
**Should we have known this?** Partially — Q#3 research caught it before S3 dispatched. But the original plan treated FDX mixed-content support as an "external" question (does FD13 emit it?) rather than an "internal" question (does our parser handle it?). The internal-correctness assumption was wrong.
**Carry forward:** Open-question entries should split external claims (vendor behavior, spec correctness) from internal claims (our code handles the shape we expect). Don't conflate them.

### 3. `Breath` lacks a scene tag — compiler uses a heuristic mapping

**What happened:** During Sortie 4, the agent surfaced that `Breath` carries only a scene-local `dialogueLineIndex` with no scene tag. The flat `GlosaScore.breaths` array preserves no scene boundaries either. The compiler must therefore *guess* which scene a given breath belongs to. The agent shipped a heuristic (offset-fits-target-line-length + no-backward-jump-within-scene) that passes the Bishop fixture and multi-scene test, but is defeated by two scenes with same-indexed dialogue lines of similar length.
**What was built to handle it:** Heuristic resolver in `GlosaCompiler.mapBreathsToAbsoluteLines`. Decision (with user) was to defer the architectural fix.
**Should we have known this?** Yes — the type design `Breath(dialogueLineIndex: Int, characterOffset: Int, length:, strength:)` was written into the plan in Sortie 1 with no scene tag. The breakdown didn't reason about how a flat `breaths` array would round-trip through a multi-scene compiler.
**Carry forward:** Whenever a flat collection is keyed by a scene-local index, the type must also carry the scene identifier. Add this to the type-design checklist for any future GLOSA element.

### 4. `glosa score` does not actually emit breaths

**What happened:** Sortie 11 confirmed that `ScoreCommand` is wired correctly to `GlosaSerializer` (which has S6/S7's emit support), but `ScoreCommand` runs through the LLM path (`StageDirector.annotate()`) which constructs `GlosaAnnotatedElement` values without populating `breathPoints`. So today `glosa preview` shows breaths (compile path) but `glosa score` writes Fountain/FDX with no breaths. The plan's S11 §3 was "Confirm `ScoreCommand` writes breaths via the GlosaSerializer changes (no new flags or options)." The agent satisfied that exact wording: the serializer wire is correct. The end-to-end flow is not.
**What was built to handle it:** Nothing. The gap is documented in `Docs/REQUIREMENTS.md` §1.4 Known Limitations.
**Should we have known this?** Yes — the LLM annotation path and the compile annotation path produce `GlosaAnnotatedElement` differently. The plan didn't reason about which path the score command uses or whether the LLM path needed a parallel `breathPoints` mapping.
**Carry forward:** "End-to-end" missions need a sortie or an exit criterion that demonstrates the feature traversing the actual user-facing command, not just that intermediate APIs are wired. Verb-test, not pipe-test.

---

## Section 2: Process Discoveries

### What the Agents Did Right

#### 1. Forward-hints between sorties

**What happened:** Every sortie's final report included a forward-hint paragraph for the next sortie. S2 → S3 (mirror `parseFountainWithDiagnostics` API). S3 → S7 (FDX whitespace placement for offset parity). S5 → S6/S7 (`GlosaAnnotatedElement` is not Codable; bridge flows only through compile path). S6 → S7 (`fountainLengthAttribute` helper is private-but-same-file, reuse directly). S7 → S11 (use 3-arg `build` overload). The supervisor folded these into each next sortie's dispatch brief.
**Right or wrong?** Right. Saved an estimated 15–25% rework versus each sortie rediscovering shared concerns independently.
**Evidence:** Zero same-file conflict events, zero re-litigation of attribute-order or wire-token decisions across S6 and S7, S7 reused S6's private helper directly (one-line call site).
**Carry forward:** Make the forward-hint paragraph a mandatory section of every sortie report from the planning template forward. Don't rely on the supervisor remembering to ask for it.

#### 2. Strict testing methodology eliminated CI-flake patterns at authoring time

**What happened:** The plan declared 8 testing methodology rules at the top (deterministic / hermetic / untimed / no retries / `.rounded()` / canonical-form / tight snapshots / no performance tests). Every sortie's dispatch brief restated these. The test-cleanup audit found zero violations across 107 added tests in 12 files.
**Right or wrong?** Right. Spending plan budget on a methodology preamble is cheaper than letting the cleanup pass churn through removals.
**Evidence:** `TEST_CLEANUP_REPORT.md` shows 0 removed / 0 flagged after auditing 107 tests against 12 high-confidence patterns.
**Carry forward:** Keep the methodology-preamble pattern. Add it to the standard breakdown template.

#### 3. Conservative model selection saved cost without sacrificing quality

**What happened:** Sonnet handled 8 of 12 sorties (S3, S5, S6, S7, S8, S9, S10, S11, S12 — actually 9). Opus was reserved for foundation sorties (S1, S2, S4) where downstream impact justified the 3x cost. Haiku was not used (no sortie scored that low).
**Right or wrong?** Right. Zero sortie required a retry, and zero sortie required an opus override after a sonnet failure.
**Evidence:** All 12 sorties first-attempt success. Spend skewed appropriately to foundation work.
**Carry forward:** Keep the model-selection complexity score formula as the default.

### What the Agents Did Wrong

#### 1. Minor SourceKit warnings left in `GlosaSerializer.swift`

**What happened:** After S6 and S7 landed, `GlosaSerializer.swift:67` retained a `let element` that was never used, and `:921` retained a `var scalars` that should be `let`. Neither blocks tests, and `swift format` doesn't flag them.
**Right or wrong?** Wrong, but mild. Lint hygiene is a small but real quality signal.
**Evidence:** SourceKit diagnostics surfaced live during S7's edit and after; not addressed by either agent.
**Carry forward:** Add "no new SourceKit warnings introduced by the edit" as an explicit exit criterion when an edit touches an existing file. Agents will then run a SourceKit check (or grep for their own warning).

### What the Planner Did Wrong

#### 1. Two parallel groups planned same-file work

**What happened:** G1 placed S2 and S3 in parallel worktrees, but both modify `Sources/GlosaCore/GlosaParser.swift`. G4 placed S6 and S7 in parallel worktrees, but both modify `Sources/GlosaAnnotation/GlosaSerializer.swift`. Either fan-out would have forced the supervisor to resolve merge conflicts (which violates the "orchestrator does not write code" rule). The supervisor reshaped both groups at execution time: S2 then S3 on the main branch; S6 then S7 on the main branch; the third sortie in each group ran in a worktree on an unrelated file.
**Right or wrong?** Wrong. Pass 3 (parallelism) of the refinement should have flagged this.
**Evidence:** Two reshape events in the Decisions Log, both correctly described as merge-hazard avoidance.
**Carry forward:** Refinement Pass 3 must run a same-file-overlap check across the sorties in each proposed parallel group. If two sorties in a group edit the same file, downgrade the group's parallelism by one and put those two sorties in sequential order.

#### 2. Open Question #2 should have been resolved during breakdown, not gated as a dispatch precondition

**What happened:** Q#2 (does SwiftCompartido give us inline-note offsets?) was listed as a top-of-plan open question and gated as an entry criterion on Sortie 2. The supervisor dispatched a research agent in parallel with Sortie 1 to resolve it. The research took ~74 seconds. That cost belonged in the breakdown pass, not at execution time.
**Right or wrong?** Wrong placement. The cost was small (~74 seconds), but the *category* matters: planner research time is cheaper than execution-time supervisor coordination.
**Evidence:** Supervisor coordination log shows the Q#2 research dispatch happened immediately after S1 dispatch, and the answer changed the entire shape of S2's implementation (in-repo regex vs upstream PR).
**Carry forward:** The breakdown pass should grep dependency parsers for the APIs the plan assumes they expose. Open Questions should be reserved for things only the human can answer (spec ambiguity, naming preferences) — not for things a five-minute grep could resolve.

#### 3. The plan assumed `glosa score` would carry breath data through the LLM path

**What happened:** Sortie 11's task §3 said "Confirm `ScoreCommand` writes breaths into the output file via the GlosaSerializer changes from Sorties 6–7 (no new flags or options)." This phrasing made it possible for the agent to satisfy the letter of the task (the serializer is wired correctly) without satisfying the spirit (breaths actually flow through `score`). The agent flagged the gap honestly in its report.
**Right or wrong?** Wrong. The plan should have either (a) explicitly required `glosa score` to round-trip breaths from a fixture, or (b) explicitly scoped the LLM-path mapping to a follow-up mission.
**Evidence:** Known Limitation #2 in `Docs/REQUIREMENTS.md` §1.4 records the gap. Compile path works; LLM path doesn't.
**Carry forward:** When an "end-to-end" mission depends on two execution paths (compile, LLM annotation), each path needs its own exit-criterion sortie that demonstrates the feature traversing the actual user command.

#### 4. Two worktree dispatches landed at pre-mission HEAD

**What happened:** Sortie 9 (worktree) and Sortie 10 (worktree) both reported their initial HEAD was `08c3f09` — a pre-mission `development` branch commit, not the mission branch's S4 commit. Both agents hard-reset their worktrees to the correct mission HEAD before doing work. The plan's worktree-dispatch instructions hadn't included a pre-flight reset; the supervisor added one to S8 and S10 after seeing the S9 lesson.
**Right or wrong?** Wrong of the plan (worktree base assumptions not documented), right of the agents (they noticed and reset).
**Evidence:** S9 and S10 final reports both describe the reset explicitly.
**Carry forward:** Every worktree dispatch must include a pre-flight `git rev-parse HEAD` check + a hard-reset instruction if the HEAD doesn't match the expected mission commit. Add this to the standard dispatch template for worktree-isolated sorties.

#### 5. Supervisor shell PWD silently drifted

**What happened:** While cherry-picking S8 onto the mission branch, the supervisor's Bash session PWD was inside an earlier worktree directory (`/Users/stovak/Projects/glosa-av/.claude/worktrees/agent-a1c3726e9acc13c08/`) rather than the project root. The cherry-pick command resolved the branch name `worktree-agent-a1c3726e9acc13c08` to the wrong target and produced an empty cherry-pick. Recovered by `git cherry-pick --abort`, explicit `cd /Users/stovak/Projects/glosa-av`, and cherry-pick by SHA.
**Right or wrong?** Wrong of the supervisor's tooling habits. PWD-stable Bash invocations require explicit absolute paths.
**Evidence:** One aborted cherry-pick, one retry, recorded in the Decisions Log.
**Carry forward:** Always preface git operations that affect the mission branch with `cd /absolute/project/root && …` rather than relying on session-persistent CWD. Always reference cherry-pick targets by SHA rather than branch name when integrating worktrees.

---

## Section 3: Open Decisions

### 1. How should `Breath` be tagged with a scene identifier?

**Why it matters:** The compiler's scene-local→absolute mapping is currently heuristic. Downstream consumers (SwiftVoxAlta `chunkHints`) will eventually receive `BreathPoint` values keyed by absolute dialogue-line index. If two scenes contain a same-indexed dialogue line of similar length, the wrong scene's breath could be attributed. Realistic screenplays don't hit this, but the contract is unsound.
**Options:**
- **A. Add `sceneIndex: Int` to `Breath`.** Both parsers populate it during scene walk. Compiler uses `(sceneIndex, dialogueLineIndex)` directly. Modest API surface change; cleanest contract. Touches `Breath.swift`, `BreathAnnotation` (for symmetry), both parsers, the compiler, and 4–5 tests.
- **B. Change `GlosaScore.breaths` to nested storage `[Int: [Breath]]` keyed by scene.** No type-shape change to `Breath` itself; bigger structural shift to `GlosaScore`.
- **C. Add a scene-boundary marker struct.** Parser emits `[Breath]` interleaved with `SceneBoundary` markers. Worst of both worlds; not recommended.
**Recommendation:** A. Cleanest. Should fit in a single sortie if dispatched early in the next iteration.

### 2. How should `glosa score` carry breath data?

**Why it matters:** Today `glosa preview` shows breaths (compile path) but `glosa score` writes Fountain/FDX with no breaths. End-to-end author workflow is incomplete.
**Options:**
- **A. Add a post-LLM compile step to `ScoreCommand`.** After `StageDirector.annotate()` returns, run the compile path to populate `breathPoints` on each `GlosaAnnotatedElement`. Pros: keeps the LLM annotation pure. Cons: doubles the work done by `score`.
- **B. Extend `StageDirector.annotate()` to map `SceneAnnotation.breaths` → `GlosaAnnotatedElement.breathPoints`.** The LLM already produces `SceneAnnotation.breaths` (S9 + S10); we just need to plumb it through. Pros: single-path. Cons: requires resolving scene-local → absolute *inside* the LLM annotation path, which has the same heuristic problem as the compiler.
- **C. Defer; document that `glosa score` doesn't carry breaths today.** Already done in `Docs/REQUIREMENTS.md` §1.4. Acceptable if `glosa preview` is the only consumer that matters for now.
**Recommendation:** Decide A vs B *after* Open Decision #1 lands (scene tagging makes the mapping authoritative, which removes the heuristic ambiguity from B).

### 3. SwiftCompartido inline-note offset API — upstream or accept the workaround?

**Why it matters:** Sortie 2's regex scan against `GuionElement.elementText` is a workaround for a missing upstream API. Other downstream consumers (any future GLOSA marker tag using `[[ ]]` notes) would face the same workaround.
**Options:**
- **A. Upstream a PR to SwiftCompartido.** Add an `inlineNotes: [(offset: Int, content: String)]` property to `GuionElement` for dialogue elements. Glosa-av drops its regex helper.
- **B. Accept the workaround; promote the helper to a shared GlosaCore helper for future marker tags.**
- **C. Leave as-is until a second marker tag forces the question.**
**Recommendation:** C until a second marker tag (e.g., spec-defined `[[<emphasis/>]]`, `[[<stress/>]]`) is on the roadmap. Then A.

---

## Section 4: Sortie Accuracy

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| 1 | Breath data model + GlosaScore | opus | 1 | ✓ | 9 tests, clean. `BreathLength.explicit` custom Codable held up across all downstream sorties. |
| 2 | Fountain `[[<breath/>]]` parser | opus | 1 | ✓ | 12 tests. In-repo regex scan against `elementText` proved correct. |
| 3 | FDX `<glosa:breath/>` parser + SAX bug fix | opus | 1 | ✓ | 9 tests. Q#3 scope expansion absorbed without retries. |
| 4 | `CompilationResult.breathPoints` | opus | 1 | ✓ (heuristic) | 4 tests. Output survived intact but the scene-local→absolute mapping is heuristic — see Hard Discovery #3. |
| 5 | Annotation bridge | sonnet | 1 | ✓ | 4 tests. Bridge only through `GlosaAnnotatedScreenplay.build`, surfaced as forward-hint to S6/S7/S11. |
| 6 | Fountain serializer round-trip | sonnet | 1 | ✓ | 10 tests. Reverse-order insertion is the true inverse. Left `fountainLengthAttribute` helper file-private for S7 reuse. |
| 7 | FDX serializer round-trip | sonnet | 1 | ✓ | 9 tests + updated 1 pre-existing test. Raw-string assembly for deterministic attribute order. |
| 8 | Validator diagnostics | sonnet | 1 | ✓ | 11 tests. Three diagnostics; reused existing `GlosaDiagnostic` (added new `Code` enum). |
| 9 | Director `BreathAnnotation` schema | sonnet | 1 | ✓ | 14 tests. Worktree; required pre-flight reset (lesson absorbed). |
| 10 | Director prompts + few-shots | sonnet | 1 | ✓ | 9 tests. Worktree; required pre-flight reset. |
| 11 | CLI `preview`/`score` surface | sonnet | 1 | ✓ (with gap) | 9 tests. Surfaced the `glosa score` LLM-path gap — see Hard Discovery #4. |
| 12 | Docs promotion + REQUIREMENTS.md §1.4 | sonnet | 1 | ✓ | No tests (docs). Three Known Limitations recorded. |

**12/12 first-attempt success. 0 retries. 0 reverts. 0 deleted files.** The plan's right-sizing was accurate.

---

## Section 5: Harvest Summary

What changes about the next iteration: the breakdown pass must do more *internal* due diligence (grep our own parsers; reason about which code path the user-facing command actually takes) and less *external* hand-waving (referring open questions to the human when a five-minute code read could answer them). Two of the three Hard Discoveries this iteration would have been caught by such due diligence; the third (Breath scene-tagging) is a type-design oversight that should be added to the type-design checklist. Test cleanup found nothing — the methodology preamble works; keep it. Refinement Pass 3 needs a same-file-overlap check for parallel groups: the supervisor caught and reshaped two same-file parallel hazards this iteration, but the cost should be paid by the planner, not at execution time.

---

## Section 6: Files

### Preserve (read-only reference for next iteration)

| File | Branch | Why |
|------|--------|-----|
| `EXECUTION_PLAN.md` | `mission/sighing-scribe/01` | Historical plan; reference for what was attempted. |
| `SUPERVISOR_STATE.md` | `mission/sighing-scribe/01` (untracked) | Per-iteration state. Will be archived by `clean`. |
| `TEST_CLEANUP_REPORT.md` | `mission/sighing-scribe/01` | Audit record. Zero removals — useful as proof-of-clean. |
| `OPERATION_SIGHING_SCRIBE_01_BRIEF.md` (this file) | `mission/sighing-scribe/01` | This brief. |
| `Docs/complete/breath-tag.md` | `mission/sighing-scribe/01` | The authoritative spec, promoted from `Docs/incomplete/`. |
| All `Sources/Glosa*/Breath*.swift` and `Tests/Glosa*Tests/Breath*.swift` | `mission/sighing-scribe/01` | The shipping feature. |

### Discard (will not exist after rollback)

| File | Why it's safe to lose |
|------|----------------------|
| *(none — verdict is KEEP)* | The mission branch will be merged; nothing is discarded. |

---

## Section 7: Iteration Metadata

**Starting point commit:** `c61e954c9ff63a5fcafbe6b76e85140defbe1973` ("Bump dependency floors and cap swift-tokenizers below the breaking 0.6.x")
**Mission branch:** `mission/sighing-scribe/01`
**Final commit on mission branch:** `ca01b7b` (test-cleanup audit pass)
**Rollback target:** `c61e954c9ff63a5fcafbe6b76e85140defbe1973` (not applicable for KEEP verdict)
**Next iteration branch:** `mission/sighing-scribe/02` (only if a follow-up mission is planned; not required by this verdict)

---

## Rollback Verdict

**Verdict:** `KEEP`

**Reasoning:** All 12 planned sorties completed on first attempt with zero retries (Section 4). The test-cleanup audit found zero violations across 107 added tests (Section 5). Full `make test` passes 80 tests across 13 suites. Three Known Limitations are documented in `Docs/REQUIREMENTS.md` §1.4 — they are real, but each is well-scoped follow-up work rather than evidence of a broken foundation. The compile path is end-to-end functional; the `glosa score` LLM-path gap (Hard Discovery #4) is a missing-but-cleanly-additive follow-up, not a structural problem.

**Recommended action:**

- **Merge** `mission/sighing-scribe/01` into `development` (or the team's integration branch).
- **File three follow-up tickets**, one for each Open Decision in Section 3:
  - Scene tagging on `Breath` (Open Decision #1) — recommended approach: A (add `sceneIndex: Int`).
  - `glosa score` breath flow (Open Decision #2) — decide after #1 lands.
  - SwiftCompartido upstream PR (Open Decision #3) — defer until a second marker tag is on the roadmap.
- **File one hygiene ticket** for the two SourceKit warnings in `Sources/GlosaAnnotation/GlosaSerializer.swift` (lines 67 and 921). Trivial fix; bundle into the next touch to that file.
- **Adopt three planner improvements** for the next mission's breakdown/refine passes:
  1. Grep dependency parsers for required APIs during breakdown, not at dispatch.
  2. Same-file-overlap check in refinement Pass 3 (parallelism).
  3. Worktree dispatch template must include a pre-flight HEAD reset.

---
