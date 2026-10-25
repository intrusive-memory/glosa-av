---
type: reference
updated: 2026-10-25
---

# GLOSA-AV — AI Agent Instructions

**Version**: 0.9.1
**Purpose**: Guide AI agents working on glosa-av
**Audience**: Claude Code, Gemini, and other AI development assistants

## Product Overview

**GLOSA** (Annotation Vocabulary) is a performance notation for screenplays — a vocabulary of annotations that direct generated voice actors.

**glosa-av** is the **GLOSA compiler**: a deterministic library (`GlosaCore`, Foundation and CryptoKit only) that parses existing GLOSA annotations out of a screenplay and resolves them into per-line instruct strings plus breath/pause seam points. It has **no package dependencies on Apple platforms** (off Apple — Linux, Windows, Android — it links `apple/swift-crypto` for SHA-256 and uses `FoundationXML` for `XMLParser`) and ships exactly one product, `GlosaCore`.

> **Architectural history (read this first).** glosa-av once contained four targets — `GlosaCore`, `GlosaAnnotation`, `GlosaDirector` (an LLM-powered Stage Director), and a `glosa` CLI. OPERATION SKELETON EVICTION (PR #17) decoupled the package down to the `GlosaCore` leaf (Foundation and CryptoKit), removing `GlosaAnnotation`, `GlosaDirector`, the CLI, and the SwiftCompartido/SwiftBruja/SwiftAcervo dependencies. **Anything describing those targets, the `glosa` CLI, App Group configuration, or Stage Director code in this repo is obsolete.** The annotation-generation (Stage Director) role now lives outside this package; glosa-av only *consumes* annotations.

## Project Goals

GLOSA addresses the gap between a screenplay and a vocal performance. The TTS generation pipeline (orchestrator -> SwiftVoxAlta -> Qwen) sends each line of dialogue to the model with at most a single instruct string derived from a Fountain parenthetical like "(speak softly)." The model has no knowledge of where it is in a scene, what emotional trajectory the conversation is following, or what behavioral constraints define the character.

GLOSA closes that gap with seven annotation layers the compiler understands:

1. **SceneContext** — the physical and atmospheric environment (location, time of day, ambient sound). Required closing tag.
2. **Intent** — the emotional trajectory of a beat (`from` -> `to`), delivery pace, and spacing. Optional closing tag — **scoped** when closed (precise gradient over enclosed lines), **marker** when unclosed (applies forward).
3. **Constraint** — character-level behavioral direction ("angry but speaking softly on purpose"), keyed by character name. Forward-applying marker, no closing tag.
4. **`<breath/>`** — sub-utterance phrasing hint. Marks where a dialogue line should be split into sub-utterances for TTS. `strength` attribute only (`weak`/`medium`/`strong`); produces ~0 actual silence. Subject to the chunker's budget heuristics.
5. **`<pause/>`** — deliberate timed silence. Inserts an audible gap of the specified `length` (default `period` ≈ 400 ms; also `comma`, `semicolon`, `em-dash`, `beat`, or explicit e.g. `length="350ms"`). Always forces a chunk seam. Always honored regardless of budget. If a `<breath>` and a `<pause>` land at the same offset, the pause wins (same-offset collapse).
6. **`<include/>`** — (notation 2.0: a JSON note, `[[ {"include": {"src": …}} ]]`; the 1.0 tag form is still read with a `deprecatedTagDirective` info) marks an external audio file to fold into the mixdown at this point (`src` required; optional `gain`, `mode` = `overlay`/`bed`/`sequential`, `fadeIn`, `fadeOut`). Standalone block event — may appear anywhere, even before any scene. The compiler only parses and carries it; the actual mixdown happens downstream.
7. **`<shot/>`** — carries a storyboard-panel prompt plus the full storyboard CLI's generate option set (`prompt`; `caption`, `style`, `model`, `aspect`, `width`, `height`, `steps`, `guidance`, `seed`, `negative`, `lora`, `loraScale`, `output`, `preview`, `telemetry`, `ref` — an ordered list carried as `[String]`, `character` — a character slug) to be handed to a downstream renderer. Standalone block event; `model`/`aspect` are carried as raw strings (the leaf has no renderer dependency). In **notation 2.0** it is a JSON note, `[[ {"shot": {…}} ]]`, with unknown keys preserved on `extraAttributes`; the 1.0 tag form is still read and yields a `deprecatedTagDirective` info. Schemas: `Sources/GlosaCore/schemas/shot.schema.json`, `include.schema.json`. `Shot.serialize()` writes the canonical note; `GlosaMigration.migrateBlockDirectives(in:)` rewrites 1.0 notes.
   - **Defaults convention and the fold (now in GlosaCore):** a `shot` **with no `prompt`** renders nothing — its other keys become the active defaults for every subsequent shot. `Shot.effective(given:)` folds the preceding defaults shots into one shot (the shot's own keys win per key, unknown keys fold too) and `GlosaScore.effectiveShots` returns every panel shot folded. **`caption` and `output` are never inherited.** An empty `prompt` is not a validation warning; the validator warns `shotUnknownModel` only on an empty `model` string.
   - **Render digest:** `Shot.renderDigest` is the SHA-256 (hex) of the RFC 8785 JCS canonical JSON of the effective shot, excluding `caption`, `output`, `preview`, `telemetry` and `documentIndex`, including unknown keys; `seed` is hashed as a decimal string. Frozen for notation 2.x — changing it is a notation major.
   - **Detection:** a note whose trimmed text starts with `{` + optional whitespace + `"` is a candidate block directive; invalid JSON yields `invalidBlockDirectiveJSON` (error). A dialogue line starting with `{"` is a known limitation.

These annotations live invisibly inside the screenplay — in Fountain `[[ ]]` notes or as an XML namespace in FDX files. The screenplay remains readable and valid without them.

### The universal `prompt` attribute

**Every** directive above may additionally carry an optional `prompt="…"` attribute — a freeform description of the *audio intent* for that tag, e.g. `[[<pause prompt="silence as a plastic grocery bag blows between them"/>]]`. GlosaCore **never interprets** `prompt`; it parses it from both Fountain and FDX, transports it through the compiler untouched, and surfaces it on the output DTOs so the downstream orchestrator (→ SwiftVoxAlta) can forward it to the audio model. GLOSA is the transport. Surfacing: scope directives combine into `GlosaLineAnnotation.prompt`; `<breath>`/`<pause>` ride `breathPrompts` / `PausePointDTO.prompt`; `<include>` carries `Include.prompt`; `<shot>`'s existing `prompt` is its image prompt and already satisfies the rule (and, when empty, marks a defaults-declaration shot — see directive 7 above). See [docs/ADDING-A-DIRECTIVE.md §0](docs/ADDING-A-DIRECTIVE.md).

## Queryable Codemap

A prebuilt [graphify](https://pypi.org/project/graphifyy/) knowledge graph of this
codebase lives in [`graphify-out/`](graphify-out/) (1388 nodes · 2259 edges). **Prefer
querying it before grepping** for architecture or "what connects to what" questions:

```bash
graphify query "How does X flow through the system?"
graphify path "TypeA" "TypeB"      # shortest path between two nodes
graphify explain "SomeType"        # plain-language node explanation
```

Human-readable summary: [`graphify-out/GRAPH_REPORT.md`](graphify-out/GRAPH_REPORT.md).
Refresh after significant changes with `/codemap` (or
`graphify . --backend claude-cli`).

## Architecture

glosa-av is a single-target Swift package with no dependencies on Apple platforms:

| Target | Role | Dependencies |
|---|---|---|
| **GlosaCore** | Compiler: GLOSA annotations -> instruct strings + breath/pause seam points | Foundation and CryptoKit (system frameworks); off Apple: swift-crypto + FoundationXML |

**glosa-av has no dependency on SwiftVoxAlta. SwiftVoxAlta has no dependency on glosa-av.** They communicate through a plain `String` — the instruct — with a downstream audio orchestrator in between.

### GlosaCore — The Compiler

```
GlosaCore (Foundation and CryptoKit)
+-- GlosaParser          — extracts GLOSA tags from Fountain notes or FDX XML -> GlosaScore
+-- GlosaInlineNotes     — single source of truth for stripping [[<breath/>]] / [[<pause/>]] inline notes
+-- GlosaJSON / GlosaJSONReader / GlosaJCS — order-preserving JSON value + reader, RFC 8785 canonical output
+-- Shot+Schema / Include+Schema — schema-form codec (bare 2.0 object); schemas/*.schema.json resources
+-- GlosaParser+BlockJSON — notation 2.0 JSON block-directive detection and parsing
+-- GlosaSerialize       — Shot/Include.serialize(): canonical 2.0 note
+-- Shot+Effective       — fold of promptless defaults (effective(given:), GlosaScore.effectiveShots)
+-- Shot+Digest          — renderDigest (JCS + SHA-256 via CryptoKit; swift-crypto off Apple)
+-- GlosaFountainNotes   — locates standalone [[ ]] notes in Fountain text
+-- GlosaMigration       — rewrites 1.0 block directives to 2.0
+-- GlosaScore           — parsed model: scenes -> intents -> constraints + flat breaths/pauses/includes/shots
+-- GlosaValidator       — well-formedness, nesting, and per-directive rule checks -> GlosaDiagnostic
+-- ScoreResolver        — stateful scope tracker: resolves active scope directives per line
+-- InstructComposer     — template-based: ResolvedDirectives -> instruct string
+-- GlosaCompiler        — chains parse/validate/resolve/compose + projects breath/pause to absolute lines
+-- GlosaLineAnnotation  — consumer DTO + compileAnnotations(...) / compileScript(...) public façades
```

### Three directive archetypes

- **Scope directives** (`SceneContext`, `Intent`, `Constraint`) — apply to whole lines; resolve into `ResolvedDirectives`, compose into the natural-language `instruct` string.
- **Point directives** (`<breath/>`, `<pause/>`) — positional markers at a character offset inside a dialogue line; project into offset-keyed `breathPoints` / `pausePoints`.
- **Standalone block events** (`<include/>`, `<shot/>`) — document-positional events keyed by `documentIndex`; carried straight through as flat lists on `CompilationResult` and surfaced via the `compileScript(...)` façade (`GlosaScriptAnnotation.includes` / `.shots`). They open no scope and need no dialogue line, so they may appear before any `<SceneContext>`.

Adding a new directive touches every stage by hand — there is no registry. The full per-archetype checklist and stream map is in **[docs/ADDING-A-DIRECTIVE.md](docs/ADDING-A-DIRECTIVE.md)**; read it before extending the vocabulary.

### Pipeline Flow

```
Scored .fountain
  -> extract [[ ]] notes + dialogue lines (orchestrator, e.g. via SwiftCompartido)
  -> compileAnnotations(fountainNotes:rawDialogueLines:)
       GlosaParser -> GlosaValidator -> ScoreResolver -> InstructComposer
                                     \-> breath/pause projection
  -> [Int: GlosaLineAnnotation]  (spokenText, instruct?, breathOffsets, pausePoints)
  -> orchestrator builds GenerationContext(phrase:instruct:) -> SwiftVoxAlta
```

## Design Principles

- **The screenplay IS the score** — one file, one source of truth.
- **Compiler, not component** — GlosaCore compiles annotations into instruct strings and seam points. It is not part of the TTS engine.
- **Connected by String** — GlosaCore and SwiftVoxAlta share no dependencies. They communicate through a plain `String`.
- **System-framework leaf** — GlosaCore depends on nothing but Foundation and CryptoKit (SHA-256 for the render digest) on Apple platforms; off Apple, swift-crypto stands in for CryptoKit through a platform-conditional product dependency. Keep it that way; annotation *generation* (LLM work) belongs in a separate package.
- **Invisible in performance, visible in rehearsal** — the audience never sees GLOSA; the pipeline always does.
- **Director, not controller** — GLOSA sets boundaries and trajectory; the model fills in the micro-performance.
- **Graceful fallback** — screenplays without GLOSA annotations work identically to today (empty notes -> empty result).
- **Discovered vocabulary** — attribute values are empirical, co-evolving with the model. The grammar is stable; the vocabulary is alive.
- **Deterministic offsets** — breath/pause offsets are `unicodeScalars.count` indices into notes-stripped prose; all stripping routes through `GlosaInlineNotes` so offsets never drift.

## Testing

glosa-av tests live in one target using Swift Testing (`@Test` / `@Suite` macros):

| Target | Coverage |
|---|---|
| **GlosaCoreTests** | Parser (Fountain/FDX), Validator, Compiler, ScoreResolver, InstructComposer, breath/pause, data models |

Run all tests:

```bash
xcodebuild test -scheme glosa-av -destination 'platform=macOS,arch=arm64'
```

**Do not use `swift test` or `swift build`** — always use `xcodebuild` (or XcodeBuildMCP).

## CI

GitHub Actions runs unit tests on every pull request to `main` (`.github/workflows/tests.yml`). The workflow uses `macos-26` runners with Swift 6.2+.

## Consumers & Integration

### SwiftCompartido

**Primary consumer**: SwiftCompartido (screenplay parsing & storage library) integrates GlosaCore via `DocumentModelActor.annotateGlosa(document:)`.

**Boundary Function**: `compileAnnotations(fountainNotes:rawDialogueLines:)` → `[Int: GlosaLineAnnotation]`

**Data Flow**:
1. SwiftCompartido extracts Fountain notes and raw dialogue from SwiftData
2. Calls `compileAnnotations()` (graceful degradation; never aborts import)
3. Persists five glosa fields to `GuionElementModel`:
   - `glosaSpokenText: String?`
   - `glosaBreathOffsets: [Int]?`
   - `glosaBreathStrengths: [String]?`
   - `glosaInstruct: String?`
   - `glosaPausePoints: Data?` (JSON-encoded `[PausePointDTO]`)

**Full Specification**: See [SwiftCompartido Dependency Border](docs/swiftcompartido-dependency-border.md) for complete API contract, offset conventions, and error handling.

### SwiftVoxAlta

**Downstream consumer**: TTS engine consumes glosa fields (via orchestration) for chunking and instruct-based delivery.

**No direct dependency**: SwiftVoxAlta has no dependency on glosa-av. Communication is through plain `String` instruct values.

## Related Projects

GlosaCore has no package dependencies. These are ecosystem siblings:

- [SwiftVoxAlta](https://github.com/intrusive-memory/SwiftVoxAlta) — TTS synthesis library. Receives instruct strings via `GenerationContext`. **No changes needed for GLOSA.**
- [SwiftCompartido](https://github.com/intrusive-memory/SwiftCompartido) — Fountain and FDX parsers. An orchestrator uses its parsed element model to feed dialogue lines into the compiler.
- A downstream audio orchestrator — Podcast generation pipeline. Orchestrates glosa-av for compilation, then SwiftVoxAlta for audio.

## Critical Rules for AI Agents

1. **NEVER commit directly to `main`** — all changes go through the `development` branch
2. **NEVER delete the `development` branch** — it is long-lived
3. **ALWAYS use `xcodebuild`** — never use `swift build` or `swift test`
4. **ALWAYS read files before editing** — understand existing code first
5. **NEVER create files unless necessary** — prefer editing existing files
6. **Keep GlosaCore a leaf (Foundation and CryptoKit only)** — do not add package dependencies to this package
7. **Run tests before committing** — `xcodebuild test -scheme glosa-av -destination 'platform=macOS,arch=arm64'`
8. **Follow agent-specific instructions** — see [CLAUDE.md](CLAUDE.md) or [GEMINI.md](GEMINI.md)

## Reference

- [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) — Full GLOSA language specification
- [docs/EXAMPLES.md](docs/EXAMPLES.md) — Annotated screenplay examples with compiled output
- [docs/ADDING-A-DIRECTIVE.md](docs/ADDING-A-DIRECTIVE.md) — How to add a new GLOSA directive to the compiler
- [CLAUDE.md](CLAUDE.md) — Claude Code agent-specific instructions
- [GEMINI.md](GEMINI.md) — Gemini agent-specific instructions
