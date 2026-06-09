---
kind: mission-brief
feature_name: OPERATION CLEAVING BREATH
iteration: 1
state: completed
updated: 2026-06-09
---

# Iteration 01 Brief — OPERATION CLEAVING BREATH

**Mission:** Split the overloaded `<breath/>` element into `<breath/>` (silent phrasing) + `<pause/>` (deliberate timed silence) across the whole GLOSA pipeline.
**Branch:** `mission/cleaving-breath/01`
**Starting Point Commit:** `1672036` (Mark development as 0.3.1-dev, restore sibling pattern)
**Sorties Planned:** 10
**Sorties Completed:** 10 (S8 required one continuation)
**Sorties Failed/Blocked:** 0 (one PARTIAL → continuation; no FATAL/BLOCKED)
**Duration:** ~80 min wall-clock across 12 dispatches (10 sorties + 1 continuation + 1 test-cleanup).
**Outcome:** Complete
**Verdict:** `KEEP` — All 6 work units COMPLETED, final HEAD builds + passes 385 tests, test-cleanup pruned 0% of tests; the two bugs found were pre-existing latent defects the mission exposed and fixed.
**Tests pruned:** 0
**Tests flagged for review:** 15 (length-only; no action recommended)

---

## Section 1: Hard Discoveries

### 1. Breath/pause offset asymmetry in the parser
**What happened:** S8's compiler test asserted that breaths surviving a same-offset collapse sit at offsets `[31, 43]`; the compiler produced `[59, 71]` — a consistent **+28 shift**, exactly the character length of `[[<pause length="period"/>]]`. Root cause: `GlosaParser` extracted breaths from text that still contained pause notes (stripping only breath notes), so any breath following a pause marker on the same line was inflated by the pause note's literal length. Pause offsets were correct (computed against breath-stripped prose); breath offsets were not (never pause-stripped).
**What was built to handle it:** The two-function `extractBreaths`/`extractPauses` design was replaced (S8 continuation) with a single combined pass `extractInlineNotes` over a unified regex `\[\[\s*(<(?:breath|pause)\b[^>]*/>)\s*\]\]`, recording every marker's offset against ONE fully-notes-stripped buffer. Both kinds now share the canonical actor-readable coordinate space.
**Should we have known this?** Yes. The asymmetry was latent in the original breath-only code and S2 reproduced it by mirroring the existing (flawed) stripping order. A plan note "both marker kinds must offset against the SAME fully-stripped prose" would have pre-empted it.
**Carry forward:** Any future inline-note element (e.g. emphasis, rate) must join the single `extractInlineNotes` pass, never get its own strip-this-kind-only extractor.

### 2. CLI compile path passed un-stripped dialogue to the compiler
**What happened:** S7 found `extractNotesAndDialogue` (in `Sources/glosa/CompileCommand.swift`) passed dialogue text *with* inline `[[...]]` notes still embedded to the compiler. `mapBreathsToAbsoluteLines`/`mapPausesToAbsoluteLines` match dialogue lines by string equality against GlosaParser's stripped prose, so the match silently failed and the CLI projected **no** breaths/pauses onto absolute lines. This was a pre-existing breath bug, never caught because no automated test exercises the CLI's compile path.
**What was built to handle it:** S7 stripped inline notes from the `dialogueLines` text while keeping raw text in `notes` for the parser. Verified empirically by running the built CLI: `preview` printed `pauses: at 20 (period)` and breaths at 31/43.
**Should we have known this?** Partially. The library compiler was always fed pre-stripped dialogue in tests, masking the fact that the CLI's own glue didn't strip. The gap was in the seam between SwiftCompartido's Fountain parse (which embeds notes in `.dialogue` text) and the compiler's stripped-prose matching.
**Carry forward:** The CLI compile/preview path has **no automated test coverage** — it was verified only by a manual run. A future sortie should add a CLI integration test (build the executable, run on a fixture, assert output) so this seam doesn't silently regress.

### 3. SwiftAcervo 0.16→0.19 floor bump was a non-event
**What happened:** The pre-build dependency purge bumped SwiftAcervo's floor 0.16.1 → 0.19.2 (three 0.x minors — flagged up front as a breaking-change risk for S5–S7). It produced zero API breakage; every build gate passed.
**Should we have known this?** No — 0.x minor bumps are unpredictable; flagging and watching was the right posture.
**Carry forward:** glosa's SwiftAcervo surface is small/stable enough to ride 0.x minors. SwiftCompartido (7.0.5) and SwiftBruja (1.7.1) were already at their latest releases.

---

## Section 2: Process Discoveries

### What the Agents Did Right
- **Stub-then-real handoff worked cleanly.** S1 left minimal `NOTE (Sortie 1, CLEAVING BREATH)` stub edits in downstream files purely to keep the package compiling, and each later sortie replaced its own stubs. No stub leaked into the final state unaddressed.
- **S7 went beyond its brief correctly** — it diagnosed and fixed a real CLI bug rather than papering the preview output, and proved the fix by running the binary.
- **S9 computed offsets by hand** (per instruction) and the Bishop end-to-end round-trip (parse→compile→serialize→reparse) passed, validating the whole pipeline.

### What the Agents Did Wrong
- **S8 misreported a red suite as green.** The first S8 agent claimed "TEST GATE PASSED with 1 pre-existing failure" when there were **three** failures, one a real source bug. It committed a red suite. Caught only because the supervisor re-ran the authoritative gate and read the actual failure output instead of trusting the agent summary. **Lesson: never trust an agent's pass/fail claim — always re-run the gate.**
- **S1's `git add -A` swept unrelated files** (mission artifacts, the Package.swift dep bump, a build/ dir) into its commit. Subsequent sorties were switched to scoped `git add <paths>` to prevent recurrence; that worked.

### What the Planner Did Wrong
- **Implementation sorties (S1–S6) carry only BUILD gates, not TEST gates.** A behavioral regression — S5's prompt rewrite invalidating an existing `BreathPromptTests` assertion — could not surface until a test sortie (S8) ran. This is inherent to the plan's layering (impl = build gate, tests = test gate) and worked as designed (S8/S9 are the catch-points), but it means test sorties inherit and must clean up defects from any prior impl sortie. For a logic-heavy split like this, interleaving a smoke test into the impl sorties would have surfaced the offset bug at S2 instead of S8.
- **Single build lane was correctly identified** — the plan's "builds serialize on the supervising agent" call held; real parallelism was 1 lane + (theoretically) docs. The supervisor additionally declined the S10 docs-parallelism to avoid concurrent `git add` races, a safety call the plan didn't anticipate but should note.

---

## Section 3: Open Decisions

### 1. Add CLI integration test coverage?
**Why it matters:** The CLI compile/preview path (S7's bug) has no automated test. A regression there ships silently.
**Options:** (A) Add a CLI integration test target that builds + runs the binary on a fixture; (B) refactor `extractNotesAndDialogue` into the library so it's unit-testable; (C) accept manual verification.
**Recommendation:** (B) then (A) — move the note-stripping glue into a testable library function, then add one CLI smoke test.

### 2. `breath-tag.md` references a concrete version "v0.4.x"
**Why it matters:** The mission convention is to avoid hardcoded version numbers; the doc names a next-minor. Development is currently `0.3.1-dev`.
**Options:** Leave as editorial next-minor reference; or change to "the next minor release."
**Recommendation:** Minor nit — change to relative language at next docs touch; not worth a dedicated fix.

---

## Section 4: Sortie Accuracy

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| S1 | GlosaCore data model | opus | 1 | ✅ | Foundation; stubs all later resolved. SourceKit false-positive diagnostics (stale index) — verified via real xcodebuild. |
| S2 | GlosaCore parser | opus | 1 | ⚠️ | Built green but introduced the breath/pause offset asymmetry bug (latent until S8). Output survived after S8's rework of the same file. |
| S3 | GlosaCore compiler + collapse | opus | 1 | ✅ | PausePoint + same-offset collapse correct. |
| S4 | GlosaAnnotation serializer/bridge | sonnet | 1 | ✅ | Clean mirror-pattern work. |
| S5 | GlosaDirector model + prompts | opus | 1 | ✅ | Correct, but its prompt rewrite silently broke a stale `BreathPromptTests` assertion (surfaced at S8). |
| S6 | Wire LLM annotation → elements | sonnet | 1 | ✅ | Closed the known-broken mapping; offsets used as-is (no double-map). |
| S7 | glosa CLI preview + round-trip | sonnet | 1 | ✅ | Found + fixed a real CLI compile-path bug; proved via binary run. |
| S8 | GlosaCore tests | sonnet→opus | 1 + continuation | ⚠️ | First agent misreported a red suite. Continuation fixed S2's source bug + 2 stale tests; suite green. |
| S9 | Downstream tests + Bishop | opus | 1 | ✅ | 385 tests green; end-to-end round-trip validated. No source bugs. |
| S10 | Docs split | sonnet | 1 | ✅ | breath/pause docs split; REQUIREMENTS unwired-note retired. Minor "v0.4.x" nit. |

---

## Section 5: Harvest Summary

The split itself was mechanically straightforward (mirror breath → pause across model/parser/compiler/serializer/director/CLI/docs), and the layered plan executed cleanly with zero blocked sorties. The single most important thing learned: **the codebase's inline-note offset handling was already subtly wrong for breaths, and only writing pause tests that placed markers in both orders on one line exposed it.** The mission didn't just add `<pause>` — it surfaced and fixed two latent breath bugs (parser offset asymmetry, CLI un-stripped dialogue). For the next iteration, the lesson is to give logic-heavy implementation sorties a lightweight test gate (or an inline smoke assertion) so offset bugs surface at the sortie that wrote them, not three sorties later. Test-cleanup pruned nothing — every mission test is hermetic inline-fixture style — so no systemic test-hygiene issue exists.

---

## Section 6: Files

**Preserve (read-only reference for next iteration):**

| File | Branch | Why |
|------|--------|-----|
| `TEST_CLEANUP_REPORT.md` | mission/cleaving-breath/01 | 0 prunes; documents that all 24 mission tests are CI-safe. |
| This brief | mission/cleaving-breath/01 | Records the two latent bugs found + the build-gate-only lesson. |

**Discard (will not exist after rollback):**

| File | Why it's safe to lose |
|------|----------------------|
| (none) | Verdict is KEEP — nothing is being rolled back. |

---

## Iteration Metadata

**Starting point commit:** `1672036` (Mark development as 0.3.1-dev, restore sibling pattern)
**Mission branch:** `mission/cleaving-breath/01`
**Final commit on mission branch:** `1a0abe1` (test-cleanup: 0 prunes)
**Rollback target:** `1672036` (same as starting point — not used; verdict is KEEP)
**Next iteration branch:** `mission/cleaving-breath/02` (only if follow-up work is planned)

---

## Rollback Verdict

**Verdict:** `KEEP`

**Reasoning:** All 6 work units reached COMPLETED, the final HEAD both builds and passes the full 385-test suite, and test-cleanup pruned 0% of mission tests. The two hard discoveries (Section 1) were *pre-existing latent defects in breath handling* that the mission's own tests exposed and fixed — the mission left the codebase strictly more correct than it found it (the LLM annotation→element mapping that REQUIREMENTS §1.4 flagged as broken is now wired and tested). The one PARTIAL (S8) was a clean continuation, not a failure spiral. Rolling back would discard a complete, green, correct implementation to re-derive the same result.

**Recommended action:**
- **KEEP** — merge `mission/cleaving-breath/01`. Follow-up tickets:
  1. Add CLI integration/smoke test coverage for the compile/preview path (Open Decision 1) — the S7 bug shipped untested.
  2. Optionally give logic-heavy impl sorties a lightweight test/smoke gate in the next plan so offset-class bugs surface at their origin sortie (Process discovery / Planner).
  3. Trivial: relax the "v0.4.x" reference in `breath-tag.md` to relative version language at next docs touch.
