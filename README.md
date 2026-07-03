---
type: doc
updated: 2026-06-17
---

# glosa-av

**GLOSA** (Annotation Vocabulary) is a performance notation system for screenplays -- named for the medieval manuscript tradition where scholars wrote explanatory notes (*glosses*) in the margins of texts. The score directives are literally glosses: marginal annotations that explain how to interpret the text. GLOSA provides a vocabulary of annotations that direct generated voice actors through emotional arcs, scene atmosphere, character behavioral constraints, and phrasing.

glosa-av is the **GLOSA compiler**: a Foundation-only, deterministic Swift library (`GlosaCore`) that parses GLOSA annotations out of a screenplay and resolves them into per-line instruct strings and timing/phrasing seam points for TTS pipelines. It has **no third-party dependencies**.

> The LLM-powered "Stage Director" that *generates* GLOSA annotations from a raw screenplay was decoupled out of this package (OPERATION SKELETON EVICTION). glosa-av is now purely the compiler leaf — it consumes annotations that already exist in the screenplay. See [docs/ADDING-A-DIRECTIVE.md](docs/ADDING-A-DIRECTIVE.md) for how the compiler is structured and how to extend the vocabulary.

## Requirements

- macOS 26+ / iOS 26+
- Swift 6.2+
- Xcode 26+

## Installation

Add glosa-av as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/intrusive-memory/glosa-av.git", from: "0.6.0-dev"),
]
```

Then import the single library:

```swift
import GlosaCore   // Foundation-only GLOSA compiler
```

## Architecture

glosa-av ships one product, a Foundation-only library:

| Target | Role | Dependencies |
|---|---|---|
| **GlosaCore** | Compiler: GLOSA annotations -> instruct strings + breath/pause seam points | Foundation only |

### GLOSA Annotation Layers

1. **SceneContext** -- physical and atmospheric environment (location, time, ambience). Required closing tag.
2. **Intent** -- emotional trajectory of a beat (`from` -> `to`), delivery pace, and spacing. Scoped (with closing tag) for precise gradient, or marker (no closing tag) for forward-applying.
3. **Constraint** -- character-level behavioral direction, keyed by character name. Forward-applying marker, no closing tag.
4. **`<breath/>`** -- sub-utterance phrasing hint. Marks where a dialogue line should be split into sub-utterances for TTS. `strength` attribute only; produces ~0 actual silence. A chunk hint, not a silence directive.
5. **`<pause/>`** -- deliberate timed silence. Inserts an audible gap of the specified `length` (default `period` ≈ 400 ms; also `comma`, `semicolon`, `em-dash`, `beat`, or explicit e.g. `length="350ms"`). Always forces a chunk seam. Always honored regardless of chunker budget. If a `<breath>` and a `<pause>` land at the same offset, the pause wins (same-offset collapse).

`SceneContext`/`Intent`/`Constraint` are **scope directives** that compile into the per-line natural-language `instruct` string. `<breath/>`/`<pause/>` are **point directives** that compile into offset-keyed seam points. See [docs/ADDING-A-DIRECTIVE.md](docs/ADDING-A-DIRECTIVE.md) for the full distinction.

Annotations live invisibly inside the screenplay -- in Fountain `[[ ]]` notes or as an XML namespace in FDX files. The screenplay remains readable and valid without them.

### Compiler Pipeline

```
GlosaCore (Foundation only)
+-- GlosaParser        — extracts GLOSA tags from Fountain notes or FDX XML -> GlosaScore
+-- GlosaValidator     — well-formedness, nesting, and per-directive rule checks -> [GlosaDiagnostic]
+-- ScoreResolver      — stateful scope tracker: resolves active scope directives per line
+-- InstructComposer   — template-based: resolved directives -> natural-language instruct string
+-- GlosaCompiler      — chains the above + projects breath/pause points to absolute lines
```

The public façade is `compileAnnotations(fountainNotes:rawDialogueLines:)`, which returns a
`[Int: GlosaLineAnnotation]` keyed by dialogue-line index. Each `GlosaLineAnnotation`
carries the notes-stripped `spokenText`, the optional `instruct` string, and the
`breathOffsets` / `pausePoints` a downstream chunker/TTS pipeline needs:

```swift
let annotations = try compileAnnotations(
    fountainNotes: notes,            // strings from [[ ]] blocks, in document order
    rawDialogueLines: dialogueLines  // [(character:, rawText:)], notes still embedded
)
// annotations[0]?.instruct      -> "Late night in the study. Calm, early in arc toward angry."
// annotations[0]?.breathOffsets -> [42]
// annotations[0]?.pausePoints   -> [PausePointDTO(...)]
```

`GlosaCore` and the TTS engine (SwiftVoxAlta) share no dependencies — they communicate through plain `String` instructs, with an orchestrator (Produciesta) in between.

## Testing

Tests live in a single target using Swift Testing (`@Test` / `@Suite`):

| Target | Coverage |
|---|---|
| **GlosaCoreTests** | Parser (Fountain/FDX), Validator, Compiler, ScoreResolver, InstructComposer, breath/pause, data models |

Run tests with xcodebuild (never `swift test`):

```bash
xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS'
```

Tests run automatically on pull requests to `main` via GitHub Actions.

## Related Projects

glosa-av (`GlosaCore`) has no package dependencies. These are ecosystem siblings that
consume or sit alongside it:

- [SwiftVoxAlta](https://github.com/intrusive-memory/SwiftVoxAlta) -- TTS synthesis. Receives instruct strings via `GenerationContext`. No changes needed for GLOSA.
- [SwiftCompartido](https://github.com/intrusive-memory/SwiftCompartido) -- Fountain and FDX parsers. Provides the parsed screenplay element model an orchestrator uses to feed dialogue lines into the compiler.
- [Produciesta](https://github.com/intrusive-memory/Produciesta) -- Podcast generation pipeline. Orchestrates glosa-av for compilation, then SwiftVoxAlta for audio.

## Documentation

- [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) -- Full GLOSA language specification
- [docs/EXAMPLES.md](docs/EXAMPLES.md) -- Annotated screenplay examples with compiled output
- [docs/ADDING-A-DIRECTIVE.md](docs/ADDING-A-DIRECTIVE.md) -- How to add a new GLOSA directive to the compiler
- [AGENTS.md](AGENTS.md) -- AI agent working instructions
- [CLAUDE.md](CLAUDE.md) -- Claude Code agent-specific instructions
- [GEMINI.md](GEMINI.md) -- Gemini agent-specific instructions

## License

Copyright Intrusive Memory Productions.
