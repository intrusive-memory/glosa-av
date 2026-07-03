---
type: doc
---

# TODO — Pass commands + orchestrator (start: PHRASING)

Goal: replace the Stage Director's single-shot "fill one giant `SceneAnnotation` in one
LLM call" design with a set of **individual pass commands**, each doing **one focused
annotation task**, run in sequence by an **orchestrator**. Build the command + orchestrator
seam, ship exactly one command — **PHRASING** — and defer everything else. Once the
sequence runs end to end, the effort shifts to **optimizing each command** in isolation.

**PHRASING** = the command that finds long and/or irregularly phrased sentences and breaks
them up with `<breath>` tags. It is the only command we implement now.

Why this shape:
- One command does one thing well, instead of five things badly in one shot.
- Each command is independently runnable (`glosa <command> file.fountain`) and independently
  testable/optimizable — you can iterate on PHRASING's output without touching anything else.
- Focused commands carry only their own slice of the spec, so each prompt fits Apple
  Foundation Models' ~4k on-device window — the FM migration (Qwen/MLX/SwiftBruja → FM)
  becomes a later, smaller, drop-in step instead of a blocking rewrite.

The Director already isolates inference behind `SceneAnnotationProvider`
(`Sources/GlosaDirector/StageDirector.swift:12`); validation/merge (`validateAndCorrect`,
`StageDirector.swift:564`) and element mapping stay put.

---

## ⚠️ Read this before starting — candor

1. **Only PHRASING ships now.** SceneContext, Intent, Constraint, and Pause stay as deferred
   commands (Phase E). Until they exist, the orchestrator runs the existing single-shot
   provider for those four facets and the PHRASING command for breaths. That hybrid is a
   deliberate transition state, not the end state.

2. **Each command is another inference round-trip per scene.** Multi-command multiplies model
   calls, and PHRASING is itself two internal passes (find, then fix — Phase C). On-device FM
   is slow, so a cheap **heuristic pre-filter** runs *before any model call* to drop short/clean
   lines; a scene with no candidates makes **zero** PHRASING model calls.

3. **Build backend-agnostic, ship on Bruja first.** CI cannot run the real FM model (needs
   Apple Silicon + Apple Intelligence + the downloaded model). Build PHRASING behind a generic
   generator primitive so it runs on today's **Bruja** backend and a **mock** in CI; swap in the
   FM backend later (Phase F) without touching the command logic.

4. **Guided generation replaces JSON parsing.** Each command/pass gets its own narrow
   `@Generable` schema — far easier to decode than the wide `SceneAnnotation`. Annotations must
   not break the types' existing `Codable`/`Equatable` conformances.

---

## Architecture — commands + orchestrator

```
ScreenplayPass (protocol)          // one focused annotation command
   └─ run(screenplay, using: generator) async throws -> SceneAnnotationDelta-per-scene
        • PhrasingPass is the only conformer now (internally find → fix)

PassCommand (ArgumentParser subcommand)   // thin CLI wrapper around a ScreenplayPass
   • `glosa phrasing file.fountain`        → run PHRASING standalone, inspect its output
   • later: `glosa intent`, `glosa context`, … each a deferred command

Orchestrator                       // runs a configured sequence of passes
   • `glosa score file.fountain`   becomes the orchestrator (ScoreCommand.swift:73)
   • sequence = [<single-shot for the 4 deferred facets>, PhrasingPass()]  ← today
   • later: sequence = [ContextPass, IntentPass, ConstraintPass, PhrasingPass, PausePass]

SceneFacetGenerator (protocol)     // generic "respond with this schema" primitive
   └─ generate(Output.Type, instructions:, userPrompt:) async throws -> Output
        • Bruja impl  → Bruja.query(as:, system:, ...)   ← ship on this
        • Mock impl   → canned per-type for CI tests
        • FM impl     → LanguageModelSession(instructions:).respond(to:generating:)  ← later
```

`SceneAnnotationDelta` is an enum (`.breaths([BreathAnnotation])`, future `.intents(...)`, …):
a pass contributes exactly one facet, the orchestrator merges deltas, then
`validateAndCorrect` runs once on the merged `SceneAnnotation` — unchanged.

---

## Phase A — Generic generator primitive

- [x] **A.1** `SceneFacetGenerator` protocol — single generic method
      `generate<Output: Codable & Sendable>(_ : Output.Type, instructions:, userPrompt:, model:) async throws -> Output`.
      (`SceneFacetGenerator.swift`)
- [x] **A.2** `BrujaFacetGenerator` — wraps today's `Bruja.query(_:as:model:temperature:system:)`:
      `instructions` → `system:`, keep `temperature: 0.3`. PHRASING runs on the current backend now.
- [x] **A.3** `MockFacetGenerator` — JSON responder keyed by `Output.Type`, with a `callCount`
      spy for the zero-call assertion.

## Phase B — Pass + orchestrator seam

- [x] **B.1** `ScreenplayPass` protocol + `SceneAnnotationDelta` enum
      (`Passes/ScreenplayPass.swift`).
- [ ] **B.2** Orchestrator that runs an ordered `[any ScreenplayPass]`, merges per-scene deltas
      into the accumulating `SceneAnnotation`, then calls `validateAndCorrect`. For now its
      sequence = the existing single-shot call (4 deferred facets, breaths stripped) **+**
      `PhrasingPass`. **(deferred — standalone command works; `score` integration not yet wired.)**
- [ ] **B.3** Wire the orchestrator into `ScoreCommand.run()` (`ScoreCommand.swift:73`),
      replacing the bare `director.annotate(...)`. Behavior unchanged except breaths now come
      from PHRASING. **(deferred with B.2.)**
- [x] **B.4** `glosa phrasing` subcommand (`PhrasingCommand.swift`, registered in
      `GlosaCommand.subcommands`) — runs `PhrasingPass.annotateScreenplay` alone and serializes.

## Phase C — PHRASING command (THE focus): add `<breath>` tags to long sentences

`Sources/GlosaDirector/Passes/PhrasingPass.swift` conforming to `ScreenplayPass`. **The
design landed differently than first sketched** (offsets → rewrite-and-validate) after two
real runs; what's below is the shipped shape.

- [x] **C.1 Word-count gate (no model call).** `PhrasingPass.isCandidate` = `wordCount >=
      minWordCount` (24). Replaced the char/structure heuristic *and* the model find pass:
      the rewrite returns long-but-clean lines unchanged on its own, so a separate find call is
      redundant. Sub-threshold lines never reach the model.
- [x] **C.2 Rewrite fix pass (one call per candidate line).** The model returns the line
      **rewritten with `<breath>` inserted inline** (`BreathPassPrompts.fixInstructions`) — it
      edits text (its strength) instead of emitting offsets (its weakness).
- [x] **C.3 Word-for-word validation → derived offsets.** `breathOffsets(fromRewrite:original:)`
      tokenizes, strips markers, and rejects the line unless it matches the original word for
      word; offsets are computed by us from marker positions, then `sanitizeOffsets` drops edge
      hits, de-dups, enforces min-gap, caps. A miscount/loop/paraphrase can't corrupt the line.
- [x] **C.4 Direct element mapping.** `annotateScreenplay` walks the parser's `GuionElement`s
      and attaches `BreathPoint`s straight onto each dialogue element — no `SceneAnalyzer`, no
      scene-local indices. The element *is* the mapping.
- [ ] **C.5** `@Generable`/`@Guide` schema for the rewrite. **(deferred to the Foundation
      Models phase — the rewrite is plain text today, validated by us; guided generation may
      later carry a structured rewrite + strength.)**
- [ ] **C.6** Remove breaths from the single-shot path so the model isn't asked twice.
      **(deferred — only bites once the `score` orchestrator (B.2/B.3) runs both single-shot and
      PHRASING; standalone `phrasing` is already breath-only.)**

Verified on `confessions/episode_61.fountain` (Qwen via Bruja): 11 breaths, all at genuine
sentence/clause boundaries, **zero text corruption** (stripping markers → byte-identical
dialogue). 30 calls (one per >24-word line). No mid-word splits (impossible by construction).

## Phase D — Optimize the PHRASING command

The rewrite-and-validate approach fixed the placement-quality and corruption problems. Remaining
optimization is about cost and edge cases, not correctness.

- [ ] **D.1 Tune `minWordCount`** against more screenplays — the gate sends every long line to
      the model, including well-phrased ones that come back unchanged (wasted calls). Measure the
      unchanged-rate; consider a light structural signal to skip obvious no-ops.
- [ ] **D.2 Strength.** The rewrite drops `strength` (all breaths default `.medium`). Let the
      model mark seam strength (e.g. `<breath:strong>`) and parse it in `breathOffsets`, or defer
      to the `@Generable` backend.
- [ ] **D.3 Tighten the prohibitions.** A few seams still split a verb + short object
      (`stop | defaulting`). Add a post-validation check that rejects such offsets, reusing the
      rules already in `fixInstructions`.
- [ ] **D.4 Concurrency.** Fix calls run sequentially per line; they're independent, so a bounded
      `TaskGroup` would cut wall-clock (watch the single ANE/GPU contention).
- [ ] **D.5** Re-evaluate once the Foundation Models `@Generable` backend lands — guided
      generation may make a structured (rewrite + strength) schema reliable.
- [ ] **D.6 Serializer artifact:** the Fountain round-trip rewrites `FADE OUT.` → `> FADE OUT.`
      (transition re-rendering, pre-existing — not PHRASING). Confirm it's harmless or fix in the
      serializer.

## Phase E — Remaining commands (deferred)

- [ ] **E.1** Add `ContextPass`, `IntentPass`, `ConstraintPass`, `PausePass` as further
      `ScreenplayPass` conformers + thin subcommands, each one focused pass with its own sliced
      prompt + `@Generable` schema. Append to the orchestrator sequence; retire the single-shot
      path entirely.

## Phase F — Foundation Models backend (deferred, behind a working PHRASING)

- [ ] **F.1** Spike: `import FoundationModels`, a `@Generable` struct, one
      `LanguageModelSession(instructions:).respond(to:generating:)` call (Xcode/Swift 6.2+;
      `Package.swift:46` already `.macOS(.v26)`).
- [ ] **F.2** `FoundationModelsFacetGenerator: SceneFacetGenerator` — session per `instructions`,
      `GenerationOptions(temperature: 0.3)`, availability preflight via
      `SystemLanguageModel.default.availability`.
- [ ] **F.3** **Decide unavailability policy** (needs user input): throw / fall back to Bruja /
      config-driven.
- [ ] **F.4** Make the FM generator default; drop the model-download gate
      (`modelChecker.ensureModelReady`, `StageDirector.swift:128`; `AcervoModelChecker`/`ModelCatalog`).
- [ ] **F.5** Dependency cleanup once FM is the only backend: remove `SwiftBruja`
      (`Package.swift:~61`, `StageDirector.swift:5`), evaluate `SwiftAcervo` + `swift-tokenizers`
      cap pin (`Package.swift:70`–`76` — ⚠️ keep if anything still pulls it; see the
      `feedback_swift_tokenizers_pin` memory). Update `--model` CLI wiring
      (`GlosaCommand.swift:9`–`17`, `ScoreCommand.swift`).

## Tests

- [x] **T.1** PHRASING find: mock `BreathCandidates`; asserts pre-filter accept/reject + that
      a find-omitted candidate yields no breaths (`PhrasingPassTests.swift`).
- [x] **T.2** PHRASING fix: mock `LineBreaths`; asserts assembly into `[BreathAnnotation]` and
      that out-of-range offsets are dropped.
- [x] **T.3** Zero-candidate scene makes zero model calls (call-count spy).
- [x] **T.4** Existing mock-based tests still compile/pass — full suite green (`make test`).
- [ ] **T.5** Reconcile `BreathPromptTests`/`BreathSchemaTests` with the find/fix split.
- [ ] **T.6** Gated FM integration test that no-ops when
      `SystemLanguageModel.default.availability != .available` (with Phase F).

## Build / docs

- [ ] **Z.1** `xcodebuild build -scheme glosa-av-Package -destination 'platform=macOS'`
- [ ] **Z.2** `xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS'`
- [ ] **Z.3** `swift format -i -r Sources/ Tests/`
- [ ] **Z.4** Update `AGENTS.md`/`CLAUDE.md`/`README` for the command + orchestrator design and
      (with Phase F) removal of the Qwen/MLX/Acervo download flow + App Group model cache.

---

## Files touched (quick map)

| File | Change |
|------|--------|
| `Sources/GlosaDirector/SceneFacetGenerator.swift` | **New** — generic generate primitive + Bruja/Mock impls (Phase A) |
| `Sources/GlosaDirector/Passes/ScreenplayPass.swift` | **New** — pass protocol + `SceneAnnotationDelta` (Phase B) |
| `Sources/GlosaDirector/Passes/PhrasingPass.swift` | **New** — PHRASING command: find → fix breath tagging (Phase C) |
| `Sources/GlosaDirector/StageDirector.swift` | Orchestrate passes; strip breaths from single-shot; inject generator |
| `Sources/glosa/ScoreCommand.swift` | `score` becomes the orchestrator entry point |
| `Sources/glosa/PhrasingCommand.swift` | **New** — `glosa phrasing` thin subcommand (Phase B.4) |
| `Sources/glosa/GlosaCommand.swift` | Register `phrasing` subcommand |
| `Sources/GlosaDirector/Prompts.swift` | Split `breathPlacementSection` into find/fix slices |
| `Sources/GlosaDirector/SceneAnnotation.swift` | `@Generable`/`@Guide` on breath pass schemas; keep Codable |
| `Sources/GlosaDirector/FoundationModelsFacetGenerator.swift` | **New** — FM-backed generator (Phase F) |
| `Tests/GlosaDirectorTests/*` | PHRASING find/fix tests, call-count spy, verify mocks |
