# glosa-av

**GLOSA** (Annotation Vocabulary) is a performance notation system for screenplays -- named for the medieval manuscript tradition where scholars wrote explanatory notes (*glosses*) in the margins of texts. The score directives are literally glosses: marginal annotations that explain how to interpret the text. GLOSA provides a vocabulary of annotations that direct generated voice actors through emotional arcs, scene atmosphere, and character behavioral constraints.

glosa-av is a Swift package that implements GLOSA through two complementary roles:

- A **compiler** (Foundation-only, deterministic) that parses GLOSA annotations and resolves them into per-line instruct strings for TTS pipelines
- A **Stage Director** (LLM-powered) that analyzes raw screenplays and generates GLOSA annotations automatically

## Requirements

- macOS 26+
- Swift 6.2+
- Xcode 26+

## Installation

Add glosa-av as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/intrusive-memory/glosa-av.git", from: "0.2.0"),
]
```

Import the layer you need:

```swift
import GlosaCore        // Foundation-only compiler pipeline
import GlosaAnnotation  // Element bridge (adds SwiftCompartido)
import GlosaDirector    // LLM-powered Stage Director (adds SwiftBruja)
```

## Architecture

glosa-av uses layered targets separated by dependency weight:

| Target | Role | Dependencies |
|---|---|---|
| **GlosaCore** | Compiler: GLOSA tags to instruct strings | Foundation only |
| **GlosaAnnotation** | Element bridge: attaches instructs to parsed screenplay elements | GlosaCore, SwiftCompartido |
| **GlosaDirector** | Stage Director: raw screenplay to GLOSA-annotated screenplay via LLM | GlosaAnnotation, SwiftBruja, SwiftAcervo |
| **glosa** | CLI tool | GlosaDirector, ArgumentParser |

### GLOSA Annotation Layers

1. **SceneContext** -- physical and atmospheric environment (location, time, ambience). Required closing tag.
2. **Intent** -- emotional trajectory of a beat (`from` -> `to`), delivery pace, and spacing. Scoped (with closing tag) for precise gradient, or marker (no closing tag) for forward-applying.
3. **Constraint** -- character-level behavioral direction, keyed by character name. Forward-applying marker, no closing tag.

Annotations live invisibly inside the screenplay -- in Fountain `[[ ]]` notes or as an XML namespace in FDX files. The screenplay remains readable and valid without them.

### Pipeline Flow

```
Path A: Stage Director (annotation -> disk)
  Raw .fountain -> SwiftCompartido.parse() -> StageDirector.annotate()
    -> GlosaAnnotatedScreenplay -> GlosaSerializer.writeFountain()
    -> annotated .fountain on disk (reviewable, hand-tunable)

Path B: Compiler (annotation -> generation)
  Scored .fountain -> SwiftCompartido.parse() -> GlosaCompiler.compile()
    -> GlosaAnnotatedScreenplay
    -> for each element: instruct = annotatedElement.instruct ?? parenthetical
    -> GenerationContext(phrase:instruct:) -> SwiftVoxAlta (unchanged)
```

## CLI Usage

The `glosa` CLI provides five subcommands:

```
glosa score <file>      Analyze a raw screenplay via LLM and write the GLOSA-scored version
glosa compile <file>    Compile an already-scored screenplay and output instruct strings
glosa preview <file>    Debug view: print resolved directives and composed instructs per line
glosa compare <file>    Diff template-compiled vs LLM-annotated instruct strings
glosa glossary          Manage the GLOSA vocabulary glossary (list, add, remove)
```

### Shared Options

```
--model <id>            LLM model identifier for annotation inference
--glossary <path>       Path to a custom vocabulary glossary JSON file
--format <fountain|fdx> Output format override
```

## Testing

The project includes 205+ unit tests across three test targets:

| Target | Coverage |
|---|---|
| **GlosaCoreTests** | Parser (Fountain/FDX), Validator, Compiler, ScoreResolver, InstructComposer, Data Models |
| **GlosaAnnotationTests** | AnnotatedScreenplay, Serializers (Fountain/FDX) |
| **GlosaDirectorTests** | StageDirector, SceneAnalyzer, VocabularyGlossary, Compare |

Run tests with xcodebuild:

```bash
xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS'
```

Tests run automatically on pull requests to `main` via GitHub Actions.

## Related Projects

- [SwiftVoxAlta](https://github.com/intrusive-memory/SwiftVoxAlta) -- TTS synthesis. Receives instruct strings via `GenerationContext`. No changes needed for GLOSA.
- [SwiftCompartido](https://github.com/intrusive-memory/SwiftCompartido) -- Fountain and FDX parsers. Provides the `GuionElement` model that GlosaAnnotation extends.
- [SwiftBruja](https://github.com/intrusive-memory/SwiftBruja) -- Local LLM inference on Apple Silicon. Powers the Stage Director.
- [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) -- Shared model management for LLM model discovery and downloads.
- [Produciesta](https://github.com/intrusive-memory/Produciesta) -- Podcast generation pipeline. Orchestrates glosa-av for annotation/compilation, then SwiftVoxAlta for audio.

## Documentation

- [REQUIREMENTS.md](REQUIREMENTS.md) -- Full GLOSA language specification
- [EXAMPLES.md](EXAMPLES.md) -- Annotated screenplay examples with compiled output
- [AGENTS.md](AGENTS.md) -- AI agent working instructions
- [CLAUDE.md](CLAUDE.md) -- Claude Code agent-specific instructions
- [GEMINI.md](GEMINI.md) -- Gemini agent-specific instructions

## App Group configuration (required)

This package depends on [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) for shared model storage. SwiftAcervo v0.10.0 resolves its App Group ID in this order: `ACERVO_APP_GROUP_ID` env var → `com.apple.security.application-groups` entitlement (macOS only) → `fatalError`. There is **no silent fallback**.

- **Signed UI apps (macOS / iOS)**: declare `com.apple.security.application-groups` with `group.intrusive-memory.models` in your `.entitlements` file. iOS apps additionally need `ACERVO_APP_GROUP_ID=group.intrusive-memory.models` in the launch environment.
- **CLI tools, scripts, CI jobs, test runners**: export `ACERVO_APP_GROUP_ID=group.intrusive-memory.models` in the shell or job environment. The standard place is `~/.zprofile`:

    ```sh
    export ACERVO_APP_GROUP_ID=group.intrusive-memory.models
    ```

Without this, `Acervo.sharedModelsDirectory` traps with `fatalError`. See [SwiftAcervo's USAGE.md](https://github.com/intrusive-memory/SwiftAcervo/blob/main/USAGE.md) for full details.

## License

Copyright Intrusive Memory Productions.
