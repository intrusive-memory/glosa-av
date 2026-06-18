# Changelog

All notable changes to glosa-av are recorded here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions align with git tags on `main`.

---

## [Unreleased]

## [0.5.0] — 2026-06-17

### Added

- **`GlosaInlineNotes` public API (FR1)** — new `public enum GlosaInlineNotes` in `GlosaCore` with `strip(_:)` and `split(_:)` static methods. This is the single source of truth for `[[ … ]]` inline-note stripping. Both `GlosaParser` and the `glosa` CLI now route through this API; the previously duplicated regex is gone.
- **`GlosaLineAnnotation` + `PausePointDTO` DTOs (FR2)** — new `public struct GlosaLineAnnotation: Codable, Sendable` and `public struct PausePointDTO: Codable, Sendable` in `GlosaCore`. Fields: `spokenText`, `breathOffsets: [Int]`, `breathStrengths: [String]`, `instruct: String?`, `pausePoints: [PausePointDTO]`; `PausePointDTO` carries `offset`, `lengthMs`, and `named`.
- **`compileAnnotations(fountainNotes:rawDialogueLines:)` entry point (FR2)** — new public function in `GlosaCore` that accepts raw dialogue lines, strips inline notes via `GlosaInlineNotes.strip`, delegates to the existing `compile(fountainNotes:dialogueLines:)` compiler, and projects `CompilationResult` into `[Int: GlosaLineAnnotation]` DTOs. Consumers receive clean `spokenText` and do not strip themselves.

### Changed

- **glosa-av is now a Foundation-only `GlosaCore` leaf (FR0) — BREAKING.** The tool tier (`GlosaAnnotation`, `GlosaDirector`, and the `glosa` CLI executable) has moved to a new sibling package `glosa-tools`. Consumers who imported `GlosaAnnotation`, `GlosaDirector`, or the `glosa` CLI from glosa-av must update their dependency to point at `glosa-tools` instead. `GlosaCore` itself is unchanged and source-compatible.
- **Package manifest reduced to zero remote dependencies.** `Package.swift` now lists exactly one product (`GlosaCore`) and one non-test target (`GlosaCore`) with `dependencies: []`. All third-party dependencies (`SwiftCompartido`, `SwiftBruja`, `SwiftAcervo`, `swift-argument-parser`, `Progress.swift`, `swift-tokenizers`) live in `glosa-tools`.
- **CI guard added.** A dedicated step in `.github/workflows/tests.yml` now fails the build if any non-Foundation dependency appears in the `Package.swift` text or the resolved dependency graph, preventing silent regressions of the leaf invariant.

## [0.4.0] — 2026-06-09

### Added

- **`<pause>` element** — new first-class GLOSA element for deliberate timed silence. Accepts a `length` attribute (`comma` / `semicolon` / `period` (default) / `em-dash` / `beat` / explicit `"350ms"` / `"0.4s"`). Always forces a chunk seam; always honored regardless of the chunker's budget heuristics. Implemented across GlosaCore (data model, parser, compiler), GlosaAnnotation (bridge, serializer), GlosaDirector (annotation schema, prompts), and the `glosa` CLI (`preview` output).
- **Same-offset collapse** — if a `<breath>` and a `<pause>` land at the same character offset in the same dialogue line, the breath is dropped and the pause is retained (one chunk seam). An info diagnostic notes the collapse.
- **LLM annotation wiring** — `SceneAnnotation.breaths` and `SceneAnnotation.pauses` from the Stage Director are now fully wired through to `GlosaAnnotatedElement.breathPoints` and `GlosaAnnotatedElement.pausePoints`. This closes the previously broken mapping that caused `glosa score` to produce empty `breathPoints` via the LLM path.

### Changed

- **`<breath/>` is now a silent phrasing hint only.** It accepts only a `strength` attribute (`weak` / `medium` / `strong`). It carries no `length` and produces ~0 actual silence. For deliberate audible gaps, use `<pause>` instead.

### Removed

- **`length` attribute on `<breath>` — BREAKING CHANGE, no migration window.** glosa-av is pre-release; there is no corpus to migrate. A `length` attribute on `<breath>` is silently **ignored** by the parser and emits a warning diagnostic: "`length` is not valid on `<breath>`; use `<pause>`". No automatic migration is performed. Update affected Fountain / FDX files by hand: replace `[[<breath length="period"/>]]` with `[[<pause length="period"/>]]` (and remove the `strength` attribute if present, since `<pause>` does not accept `strength`).
- **`BreathLength` type renamed to `PauseLength`.** `BreathLength` is removed; all duration cases now live on `PauseLength` (owned by `Pause`). Code that referenced `BreathLength` must be updated to `PauseLength`.

---

## [0.3.1] — 2026-05-14

- SwiftAcervo 0.16.x migration, CI hardening, dependency bumps.

## [0.3.0] — 2026-05-01

- `<breath/>` element: sub-utterance chunk hints (phrasing, `strength`, initial LLM placement).
- Dependency floor bumps; release-shape `Package.swift`.

## [0.2.1] — earlier

- See git log for pre-changelog history.
