# REQUIREMENTS — Glosa Integration (glosa-av)

**Status:** Proposed (revised — decoupling baked in)
**Owner repo role:** Source of the glosa markup language — a Foundation-only
**leaf** parser/compiler that emits a Codable value SwiftCompartido can store.
**Primary deliverable:** Decouple glosa-av's library tier from SwiftCompartido so
the dependency arrow is strictly one-way (`SwiftCompartido → GlosaCore`), then
expose the public notes-stripper + a compile-to-DTO entry point, and tag a
release.

> Cross-repo sequencing and the consumer side live in
> `REQUIREMENTS-glosa-integration-RECONCILED.md`. This doc is the **glosa-av-side
> (producer) requirements** only. SwiftCompartido's breakdown is owned in
> `../SwiftCompartido`.

---

## 1. Context & the problem this revision fixes

`GlosaCompiler.compile(fountainNotes:dialogueLines:)`
(`Sources/GlosaCore/GlosaCompiler.swift:33`) already produces the data downstream
needs. `GlosaCore` is Foundation-only with zero transitive package deps.

Two blockers stand between that and safe consumption by SwiftCompartido:

1. **Dependency cycle (structural, must fix first).** glosa-av's `Package.swift`
   currently declares a dependency on **SwiftCompartido** (for `GlosaAnnotation`,
   `GlosaDirector`, and the `glosa` CLI). The moment SwiftCompartido depends on
   glosa-av, SwiftPM rejects the graph as a cycle — *regardless* of which target
   uses the dependency, because the cycle is at the **manifest** level. So the
   package SwiftCompartido consumes (`GlosaCore`) must have **zero**
   SwiftCompartido reference in its manifest.

2. **Stripping drift (correctness).** The compiler matches dialogue by string
   equality on notes-stripped prose, but the stripping logic exists only as
   **private** helpers — `GlosaParser.extractInlineNotes`
   (`Sources/GlosaCore/GlosaParser.swift:491`) and the CLI's `stripInlineNotes`
   (`Sources/glosa/CompileCommand.swift:147`). A consumer that re-implements the
   regex risks silently dropping or misaligning annotations.

---

## 2. Goals
1. glosa-av's library tier (`GlosaCore`) **does not depend on SwiftCompartido,
   SwiftData, mlx, or anything beyond Foundation** — it is a clean leaf.
2. Consumers obtain the exact `(notes-stripped text, extracted notes)` pair glosa
   expects using glosa's own code — no reimplementation.
3. Consumers obtain a ready-to-store **Codable, Sendable** annotation value per
   dialogue line — they never touch glosa's internal types or SwiftData.
4. A tagged release exists containing all of the above.

---

## 3. Functional requirements

### FR0 — Decouple `GlosaCore` to a pure leaf (REQUIRED, do first)
glosa-av's package must stop referencing SwiftCompartido. The tool tier that
genuinely needs a screenplay parser is rehomed, not deleted.

- **Remove the `SwiftCompartido` dependency from `glosa-av/Package.swift`**, along
  with any of `SwiftBruja`/`SwiftAcervo`/`ArgumentParser`/`Progress` that are only
  needed by the relocated tool tier.
- **Move `GlosaAnnotation`, `GlosaDirector`, and the `glosa` executable** out of
  this package into a new sibling package **`glosa-tools`** that depends on the
  **released** `GlosaCore` **and** SwiftCompartido (Path Y of the reconciled
  plan). The `glosa` CLI's compile/score/preview/compare behavior must be
  preserved post-move.
- After the move, `glosa-av`'s products are `GlosaCore` only.
- **Invariant:** `GlosaCore` builds with **zero non-Foundation dependencies**,
  `Sendable`-clean, Swift 6 strict-concurrency clean (macOS 26 / iOS 26).
- **CI guard (RISK-5):** add a check that fails if any non-Foundation dependency
  is reintroduced to the `GlosaCore` package manifest.

> Note on overlap: parts of `GlosaAnnotation` (combining compile output with
> `GuionElement`) are superseded by SwiftCompartido's annotation pass. During the
> move, decide per file whether to keep (standalone CLI rendering) or drop.

### FR1 — Public canonical notes-stripper
Expose the single source of truth for inline-note stripping in `GlosaCore`:
```swift
public enum GlosaInlineNotes {
    /// The notes-stripped prose the actor/TTS reads — offsets index this string.
    public static func strip(_ dialogue: String) -> String
    /// One pass: the stripped prose plus the extracted `[[ ... ]]` contents in order.
    public static func split(_ dialogue: String) -> (stripped: String, notes: [String])
}
```
- Refactor **both** private copies (`extractInlineNotes`, CLI `stripInlineNotes`)
  to route through this API so the three can never diverge.
- **Invariant:** `split(raw).stripped` is byte-identical to the text the parser
  builds and that `compile()` matches by string equality.
- Document that offsets are `unicodeScalars.count` indices into `stripped`.

### FR2 — Compile-to-DTO entry point (the boundary contract)
Expose a Codable, Sendable value per dialogue line and an entry point that strips
internally (so the consumer never strips on its own — closes RISK-1 structurally):
```swift
public struct GlosaLineAnnotation: Codable, Sendable {
    public let spokenText: String        // notes-stripped; offsets index this
    public let breathOffsets: [Int]      // unicode-scalar offsets, ascending
    public let breathStrengths: [String] // parallel to breathOffsets
    public let instruct: String?         // composed performance direction
    public let pausePoints: [PausePointDTO]
}

public struct PausePointDTO: Codable, Sendable {
    public let offset: Int
    public let lengthMs: Int
    public let named: String?
}

public func compileAnnotations(
    fountainNotes: [String],
    rawDialogueLines: [(character: String, rawText: String)]  // inline [[ ]] intact
) throws -> [Int: GlosaLineAnnotation]                        // keyed by dialogue-line index
```
- Built on the existing `compile(fountainNotes:dialogueLines:)` + FR1. The
  existing `compile` / `CompilationResult` API stays unchanged for back-compat.
- **Round-trip invariant:** splitting `spokenText` at `breathOffsets` reconstructs
  `spokenText` losslessly (mirrors mlx `splitTextAtBreaths`, no mlx dependency).
- All public types referenced across the boundary (`GlosaLineAnnotation`,
  `PausePointDTO`, and any retained `BreathPoint`/`PausePoint`/`BreathStrength`/
  `PauseLength`/`GlosaDiagnostic`/`InstructProvenance`) remain `Sendable` and
  `Codable`.

### FR3 — Release
Cut a tagged release (≥ next minor over current **v0.4.0**) of `glosa-av`
containing FR0 (leaf-only `GlosaCore`) + FR1 + FR2. SwiftCompartido and
`glosa-tools` pin to this tag; **no released/CI build may depend on a glosa-av
branch.**

---

## 4. Non-functional requirements
- `GlosaCore` stays Foundation-only, zero transitive package deps, `Sendable`-
  and strict-concurrency-clean.
- No API breakage to existing `compile()` / `CompilationResult` consumers.
- The compile-to-DTO path is deterministic and side-effect-free.

## 5. Acceptance criteria
- AC0: `GlosaCore` resolves and builds with **zero non-Foundation dependencies**;
  `glosa-av`'s manifest contains no `SwiftCompartido` reference; a CI guard
  enforces this.
- AC1: `GlosaInlineNotes.split(raw).stripped` equals the parser's
  `extractInlineNotes` stripped text for the same input (test runs both paths).
- AC2: offsets in `GlosaLineAnnotation` index correctly into `spokenText` for a
  multi-breath fixture (incl. emoji / combining marks / `after=` positioning),
  and split-at-offsets round-trips `spokenText` losslessly.
- AC3: existing GlosaCore tests pass; parser + relocated CLI route through the
  public stripper.
- AC4: `glosa-tools` builds and the CLI behaves identically to today.
- AC5: a SwiftPM-resolvable release tag exists containing FR0+FR1+FR2.

## 6. Risks & non-goals
- **RISK-1 (offset drift):** mitigated structurally — consumers call
  `compileAnnotations`, which strips via the canonical `GlosaInlineNotes`.
- **RISK-5 (cycle regression):** if SwiftCompartido (or any package depending on
  it) is re-added to the `GlosaCore` manifest, the SwiftPM graph breaks again. The
  AC0 CI guard exists to catch this.
- **Non-goal:** `GlosaCore` does not depend on SwiftCompartido, SwiftData, mlx-
  audio-swift, SwiftBruja, or SwiftAcervo.
- **Non-goal:** glosa-av does not emit `breathOffsets`/`[Int]` for storage shape
  decisions — it emits `GlosaLineAnnotation`; how SwiftCompartido persists it
  (flattened fields vs encoded blob) is the consumer's choice.
- **Non-goal:** SwiftData `@Model` ownership, schema versioning/migration — these
  live entirely in SwiftCompartido + the app.
- **Non-goal:** calling `generate()` / producing audio (VoxAlta/Produciesta).
</content>
