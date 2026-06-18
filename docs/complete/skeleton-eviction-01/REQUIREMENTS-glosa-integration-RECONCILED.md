# REQUIREMENTS — Glosa Integration (RECONCILED, sequenced plan)

**Status:** Proposed — supersedes the two draft docs
**Supersedes:**
- `glosa-av/REQUIREMENTS-glosa-integration.md` (producer draft)
- `SwiftCompartido/REQUIREMENTS-glosa-integration.md` (consumer draft)

This document reconciles the two drafts into one sequenced plan and resolves the
contradiction between them: the producer draft declared *"glosa-av does not
depend on SwiftCompartido"* while the repo on disk **already does**, and the
consumer draft asked SwiftCompartido to **depend on glosa-av** — which together
form an illegal SwiftPM package cycle.

---

## 0. The decision (architecture)

**Dependency arrow is one-way: `SwiftCompartido → GlosaCore`. glosa-av's library
tier never imports SwiftCompartido.**

The value that crosses the boundary is a **Codable, Sendable DTO** produced by
glosa-av. SwiftCompartido owns all SwiftData concerns (the `@Model`, the
`ModelContainer`, schema versioning) and stores the DTO at the correct
sequential position. glosa-av owns parsing, compilation, and the DTO *shape*.

### Why a value (not a `@Model`) crosses the boundary — verified facts
- SwiftData `@Model` instances are **not `Sendable`** and are bound to the
  `ModelContext` that created them; they cannot be constructed off-thread and
  handed across an actor boundary. A Codable value is the only safe hand-off.
- SwiftCompartido's writer is **`DocumentModelActor` (`@ModelActor`)**, not a
  main-thread class. It serializes context access and is the natural place to
  instantiate + insert the `@Model` from glosa's DTO.
- Sequencing is `GuionElementModel.chapterIndex` + `orderIndex`. A glosa record
  "falls into place" because **SwiftCompartido assigns the index at insert
  time** — glosa-av needs no knowledge of SwiftCompartido's types to participate.

### Why this kills the cycle
The cycle is created by **manifests**, not by the data path. SwiftPM rejects the
graph the instant `glosa-av/Package.swift` lists SwiftCompartido **and**
SwiftCompartido lists glosa-av — regardless of which target uses it. Therefore
the package SwiftCompartido depends on (`GlosaCore`) must have **zero**
SwiftCompartido reference in its manifest.

### Packaging (recommended: Path Y)
glosa-av today bundles a pure library (`GlosaCore`) with a SwiftCompartido-
dependent tool tier (`GlosaAnnotation` ~1,450 LOC, `GlosaDirector`, the `glosa`
CLI). The leaf must be cleanly separated from the tool tier:

- **Path Y (recommended) — glosa-av *is* the leaf.** glosa-av's package keeps
  only `GlosaCore` (+ the new DTO/compile API) and **drops the SwiftCompartido
  dependency from its manifest**. The tool tier (`GlosaAnnotation`,
  `GlosaDirector`, `glosa` CLI) moves to a new `glosa-tools` package that
  depends on **both** the released `GlosaCore` **and** SwiftCompartido. This
  literally satisfies "glosa shouldn't depend on Compartido at all."
- **Path X (lower churn) — extract `GlosaCore` to its own repo.** glosa-av's
  repo keeps the tool tier and its SwiftCompartido dependency; `GlosaCore`
  becomes a new standalone leaf repo. `SwiftCompartido → GlosaCore` and
  `glosa-av → GlosaCore + SwiftCompartido` — all edges point down, no cycle.
  Less moving of code, but the "glosa-av" name no longer denotes the core lib.

Both are correct. The plan below assumes **Path Y**; Phase 2 is where the two
diverge.

---

## 1. Roles after reconciliation

| Concern | Owner |
|---|---|
| Glosa markup parsing, compilation, inline-note stripping | **GlosaCore** (Foundation-only leaf) |
| The Codable DTO shape that crosses the boundary | **GlosaCore** |
| `@Model`, `ModelContainer`, storing the DTO in sequence | **SwiftCompartido** |
| Versioned schema + migration stages | **SwiftCompartido** model + **the app** plan (see §6) |
| Audio coat / display coat representations | **SwiftCompartido** |
| Standalone screenplay tooling (CLI, director, annotation) | **glosa-tools** (depends on both) |
| Calling TTS `generate()` | downstream (VoxAlta / Produciesta) — out of scope |

---

## 2. The boundary contract (the Codable hand-off)

`GlosaCore` exposes a Foundation-only, `Codable`, `Sendable` value per dialogue
line. Shape (final names TBD in Phase 1):

```swift
public struct GlosaLineAnnotation: Codable, Sendable {
    /// Notes-stripped prose the actor/TTS reads. Offsets index THIS string.
    public let spokenText: String
    /// unicode-scalar offsets into spokenText, sorted ascending.
    public let breathOffsets: [Int]
    /// Parallel to breathOffsets; raw BreathStrength values.
    public let breathStrengths: [String]
    /// Composed performance direction for this line.
    public let instruct: String?
    /// Stored for display + future TTS; not consumed by today's TTS.
    public let pausePoints: [PausePointDTO]
}

public struct PausePointDTO: Codable, Sendable {
    public let offset: Int
    public let lengthMs: Int
    public let named: String?
}
```

- **Offset convention:** `unicodeScalars.count` indices into `spokenText`.
- **Round-trip invariant:** splitting `spokenText` at `breathOffsets` reconstructs
  `spokenText` losslessly (mirrors mlx-audio-swift `splitTextAtBreaths`, without
  depending on mlx).

---

## 3. Phase 1 — glosa-av (`GlosaCore`): producer work

Self-contained; no SwiftCompartido needed. Do this first.

### FR1 — Public canonical notes-stripper (kills RISK-1 at the source)
Expose the single source of truth for inline-note stripping:
```swift
public enum GlosaInlineNotes {
    public static func strip(_ dialogue: String) -> String
    public static func split(_ dialogue: String) -> (stripped: String, notes: [String])
}
```
- Refactor the **two existing private copies** to call this:
  `GlosaParser.extractInlineNotes` (`Sources/GlosaCore/GlosaParser.swift:491`)
  and the CLI's `stripInlineNotes` (`Sources/glosa/CompileCommand.swift:147`).
- Invariant: `split(raw).stripped` is byte-identical to the text the parser
  builds and that `compile()` matches by string equality.

### FR2 — Convenience compile-to-DTO entry point (eliminates caller stripping)
Because the consumer should never re-implement stripping, expose an entry point
that strips internally and returns the DTO keyed by dialogue-line index:
```swift
public func compileAnnotations(
    fountainNotes: [String],
    rawDialogueLines: [(character: String, rawText: String)]  // inline [[ ]] intact
) throws -> [Int: GlosaLineAnnotation]
```
Built on the existing `compile(fountainNotes:dialogueLines:)`
(`Sources/GlosaCore/GlosaCompiler.swift:33`) + FR1. The existing `compile`
stays for back-compat.

### FR3 — Make `GlosaCore` a clean leaf (Path Y)
- Move `GlosaAnnotation`, `GlosaDirector`, and the `glosa` CLI **out** of this
  package (→ Phase 2). Remove the `SwiftCompartido` (and, if now unused for the
  leaf, `SwiftBruja`/`SwiftAcervo`) dependencies from `glosa-av/Package.swift`.
- `GlosaCore` must remain Foundation-only, zero transitive package deps,
  `Sendable`-clean, Swift 6 strict-concurrency clean.

### FR4 — Release
Tag a release (≥ next minor over current **v0.4.0**) containing FR1 + FR2 + the
leaf-only `GlosaCore`. SwiftCompartido pins to this tag; **no downstream depends
on a glosa-av branch** in a released/CI build.

**Phase 1 acceptance**
- AC1: `GlosaInlineNotes.split(raw).stripped` equals the parser's stripped text
  for the same input (test runs both paths).
- AC2: offsets in the DTO index correctly into `spokenText` for a multi-breath
  fixture (incl. emoji / combining marks / `after=` positioning).
- AC3: `GlosaCore` builds with zero non-Foundation deps; existing GlosaCore
  tests pass; parser + (relocated) CLI route through the public stripper.
- AC4: a SwiftPM-resolvable release tag exists.

---

## 4. Phase 2 — Rehome the tool tier (`glosa-tools`)

(Path Y. Skip entirely under Path X.)
- New package `glosa-tools` depending on the released `GlosaCore` **and**
  SwiftCompartido (+ SwiftBruja/SwiftAcervo as the CLI needs).
- Move `GlosaAnnotation`, `GlosaDirector`, and the `glosa` executable here
  unchanged except for the dependency on `GlosaCore` now being the remote
  release instead of a local target.
- Note overlap: parts of `GlosaAnnotation` (combining compile output with
  screenplay elements) are superseded by SwiftCompartido's Phase 3 annotation
  pass. Decide per-file whether to keep (standalone CLI rendering) or drop.

**Phase 2 acceptance:** `glosa-tools` builds and the CLI's compile/preview/score
commands behave identically to today.

---

## 5. Phase 3 — SwiftCompartido: consumer work

Depends on Phase 1's release.

### FR1 — Dependency
- Add `GlosaCore` to `SwiftCompartido/Package.swift` via the `sibling(...)`
  helper, pinned to the Phase 1 release tag. `GlosaCore` requires macOS 26 /
  iOS 26 — already matches.

### FR2 — Storage
SwiftCompartido decides the storage representation for the DTO. Two acceptable
shapes (pick one in implementation):
- **(a) Flattened fields** on `GuionElementModel`: `glosaSpokenText: String?`,
  `glosaBreathOffsets: [Int]?`, `glosaBreathStrengths: [String]?`,
  `glosaInstruct: String?`, `glosaPausePoints: Data?` (encoded `[PausePointDTO]`).
- **(b) Encoded blob**: store the whole `GlosaLineAnnotation` as `Data?` and
  decode on access.
Keep `elementText` **unchanged** (raw, with `[[ ]]` markers) for lossless
export. `glosaSpokenText`/`spokenText` is the spoken projection.
- Define local DTO mirrors so SwiftData isn't coupled to glosa's concrete types
  beyond `Codable` decoding (or re-export the DTO if acceptable).

### FR3 — Annotation pass (parse → compile → store, in sequence)
Invoke after `GuionDocumentModel.from(...)`, inside / alongside
`DocumentModelActor`, gated by `parseGlosa: Bool = true`:
1. Collect dialogue elements in `sortedElements` order (`(chapterIndex,
   orderIndex)`); keep a parallel dialogue-line-index → element map.
2. Build `rawDialogueLines` from the **raw** element text (inline `[[ ]]`
   intact) and collect `fountainNotes` (standalone `.comment` elements + inline
   notes, document order).
3. Call `GlosaCore.compileAnnotations(fountainNotes:rawDialogueLines:)`
   (FR2 of Phase 1) — **do not** strip locally; matching glosa's stripping is a
   hard correctness requirement (RISK-1).
4. On the `@ModelActor`, for each dialogue-line index `i`, write the DTO onto the
   element (FR2 shape) at its existing `orderIndex` — no re-sequencing needed.
5. Surface `diagnostics` (log; optionally persist on `GuionDocumentModel`).
- **Graceful degradation:** a glosa throw/diagnostic must NOT abort import —
  leave glosa fields `nil`, record diagnostics.

### FR4 — Audio coat
```swift
public protocol SpeakableElement {
    var spokenText: String { get }     // glosaSpokenText ?? elementText
    var breathOffsets: [Int] { get }   // glosaBreathOffsets ?? []
    var instruct: String? { get }
}
```
Conform `GuionElementModel` and the `ElementReference` DTO (mirroring
`DisplayableElement` dual-conformance). This is the sole surface the TTS layer
consumes — **no mlx types appear here**.

### FR5 — Display coat (light)
Expose `breathOffsets` / pause data from the display path so a future overlay can
render markers. Full breath-visualizing views are out of scope for v1.

**Phase 3 acceptance**
- AC1: importing Fountain with inline `[[<breath/>]]` yields an element whose
  `spokenText` is the notes-stripped prose and whose `breathOffsets` are the
  expected unicode-scalar offsets.
- AC2: `String(spokenText.unicodeScalars)` split at `breathOffsets` reconstructs
  `spokenText` (lossless).
- AC3: a screenplay with no glosa markup imports unchanged; glosa fields
  `nil`/`[]`; no regression.
- AC4: offsets fed to mlx's `splitTextAtBreaths(spokenText, offsets:)` land where
  glosa intended (value-test fixture, no mlx dependency).
- AC5: tests under `SwiftCompartidoTests` (SwiftFijos fixture pattern) cover
  FR2–FR4 and the no-markup case.

---

## 6. Phase 4 — Schema versioning & migration (app + SwiftCompartido)

**Correction to the consumer draft:** it assumed *"the main app already provides
the `VersionedSchema`/`SchemaMigrationPlan` foundation."* Verified: **there is no
`VersionedSchema`/`SchemaMigrationPlan` anywhere in SwiftCompartido today.** So
this foundation must be established, and it lives where the `ModelContainer` is
built — the **app**.

- Introduce a `VersionedSchema` (e.g. `SwiftCompartidoSchemaV<next>`) capturing
  the post-change shape of every affected `@Model` (`GuionElementModel`, plus any
  other touched model).
- Register an explicit `MigrationStage` from the prior version. All additions are
  optional, so a **`.lightweight`** stage is acceptable — but it must be
  **explicitly declared**, not inferred.
- The **app** composes `ModelContainer(for: Schema([...]))` and owns the
  `SchemaMigrationPlan.schemas` / `.stages` ordering. Coordinate the version
  number with the app.
- Migration test: open a store created at the prior version, confirm it migrates
  cleanly, new glosa fields default to `nil`, pre-existing data intact.

**Phase 4 acceptance**
- AC6: migration test passes; new fields default to `nil`; old data intact.

---

## 7. Sequencing summary

1. **Phase 1 — GlosaCore**: public stripper + DTO + compile-to-DTO API; strip
   SwiftCompartido from the leaf; **tag release**. *(blocks everything)*
2. **Phase 2 — glosa-tools**: rehome CLI/Director/Annotation onto the release.
   *(parallel-able with Phase 3 once Phase 1 ships)*
3. **Phase 3 — SwiftCompartido**: depend on the release; storage + annotation
   pass + audio/display coats.
4. **Phase 4 — app**: versioned schema + migration plan + migration test.

No phase may consume a glosa-av branch in a released/CI build (Phase 1's tag is
the gate).

---

## 8. Risks & non-goals

- **RISK-1 (offset drift):** `compile()` matches lines by string equality on
  stripped text. Mitigated structurally — the consumer calls
  `compileAnnotations` (which strips via the canonical `GlosaInlineNotes`), so it
  never strips on its own.
- **RISK-2 (pause not TTS-consumable):** mlx-audio-swift has no silence/pause
  API. Pause points are stored for display + future use only.
- **RISK-3 (strength flattened):** mlx `breathOffsets` is `[Int]`. Strength is
  preserved in storage (`breathStrengths`) but the audio coat flattens to
  offsets. Strength-aware chunking is future mlx work.
- **RISK-4 (cross-package migration):** schema changes ship via explicit
  `VersionedSchema` + `MigrationStage` composed by the app — never implicit
  auto-migration. Mis-sequencing can corrupt stores.
- **RISK-5 (cycle regression):** if anyone re-adds a SwiftCompartido dependency
  to the `GlosaCore` package manifest, the SwiftPM graph breaks again. CI on
  `GlosaCore` should assert zero non-Foundation deps.
- **Non-goal:** `GlosaCore` does not depend on SwiftCompartido, mlx-audio-swift,
  SwiftData, or SwiftBruja/SwiftAcervo.
- **Non-goal:** calling `generate()` / producing audio (VoxAlta/Produciesta).
- **Non-goal:** authoring/round-trip-editing glosa markup in the UI.
</content>
</invoke>
