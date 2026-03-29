# GLOSA-AV

**GLOSA** (Annotation Vocabulary) is a performance notation for screenplays — a vocabulary of annotations that direct generated voice actors.

**glosa-av** implements GLOSA through two complementary roles: a **compiler** (Foundation-only, deterministic) that parses existing annotations and resolves them into per-line instruct strings, and a **Stage Director** (LLM-powered) that analyzes raw screenplays and generates GLOSA annotations automatically. The package operates directly on SwiftCompartido's parsed element model — annotated elements can be serialized back to disk or sent directly to the audio generation pipeline.

## Project Goals

GLOSA addresses the gap between a screenplay and a vocal performance. Currently, the TTS generation pipeline (Produciesta -> VoiceLockManager -> Qwen) sends each line of dialogue to the model with at most a single instruct string derived from a Fountain parenthetical like "(speak softly)." The model has no knowledge of where it is in a scene, what emotional trajectory the conversation is following, or what behavioral constraints define the character.

GLOSA solves this by providing three layers of annotation:

1. **SceneContext** — the physical and atmospheric environment (location, time of day, ambient sound). Required closing tag.
2. **Intent** — the emotional trajectory of a beat (`from` -> `to`), delivery pace, and spacing. Optional closing tag — **scoped** when closed (precise gradient over enclosed lines), **marker** when unclosed (applies forward).
3. **Constraint** — character-level behavioral direction ("angry but speaking softly on purpose"), keyed by character name. Forward-applying marker, no closing tag.

These annotations live invisibly inside the screenplay — in Fountain `[[ ]]` notes or as an XML namespace in FDX files. The screenplay remains readable and valid without them.

## Architecture

glosa-av is a Swift package with layered targets that separate concerns by dependency weight:

| Target | Role | Dependencies |
|---|---|---|
| **GlosaCore** | Compiler: GLOSA tags -> instruct strings | Foundation only |
| **GlosaAnnotation** | Element bridge: attaches instructs to parsed screenplay elements | GlosaCore, SwiftCompartido |
| **GlosaDirector** | Stage Director: raw screenplay -> GLOSA-annotated screenplay via LLM | GlosaAnnotation, SwiftBruja, SwiftAcervo |
| **glosa** | CLI: `glosa score`, `glosa compile`, `glosa preview`, `glosa compare`, `glosa glossary` | GlosaDirector, ArgumentParser |

**glosa-av has no dependency on SwiftVoxAlta. SwiftVoxAlta has no dependency on glosa-av.** They communicate through a plain `String` — the instruct — with Produciesta as the orchestrator in between.

### GlosaCore — The Compiler

```
GlosaCore (Foundation only)
+-- GlosaParser         — extracts GLOSA tags from Fountain notes or FDX XML
+-- GlosaScore          — data model: SceneContext, Intent, Constraint
+-- ScoreResolver       — stateful scope tracker: resolves active directives per line
+-- InstructComposer    — template-based: resolved directives -> instruct string
+-- GlosaCompiler       — public API: combines parser + resolver + composer
+-- GlosaValidator      — well-formedness and nesting rule checks
```

### GlosaAnnotation — Element Bridge

```
GlosaAnnotation (depends on: GlosaCore, SwiftCompartido)
+-- GlosaAnnotatedElement      — pairs GuionElement with resolved directives + instruct string
+-- GlosaAnnotatedScreenplay   — wraps GuionParsedElementCollection with full annotation context
+-- GlosaSerializer            — writes annotated elements back to Fountain/FDX with GLOSA embedded
```

### GlosaDirector — Stage Director

```
GlosaDirector (depends on: GlosaAnnotation, SwiftBruja, SwiftAcervo)
+-- StageDirector       — LLM-powered annotation generator
+-- SceneAnalyzer       — feeds scenes to LLM, receives structured GLOSA annotations
+-- VocabularyGlossary  — curated terms the TTS model responds to well
```

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

## Design Principles

- **The screenplay IS the score** — one file, one source of truth.
- **Compiler, not component** — GlosaCore compiles annotations into instruct strings. It is not part of the TTS engine.
- **Stage Director, not ghostwriter** — the LLM generates structured annotations, not prose. Grammar and serialization are handled by code.
- **Directives live on elements** — GLOSA annotations attach to SwiftCompartido's parsed elements, flowing naturally through the pipeline.
- **Connected by String** — GlosaCore and SwiftVoxAlta share no dependencies. They communicate through a plain `String`.
- **Invisible in performance, visible in rehearsal** — the audience never sees GLOSA; the pipeline always does.
- **Director, not controller** — GLOSA sets boundaries and trajectory; the model fills in the micro-performance.
- **Graceful fallback** — screenplays without GLOSA annotations work identically to today.
- **Discovered vocabulary** — attribute values are empirical, co-evolving with the model. The grammar is stable; the vocabulary is alive.
- **Layered dependencies** — GlosaCore depends on nothing. GlosaAnnotation adds SwiftCompartido. GlosaDirector adds SwiftBruja. Each consumer imports only the layer it needs.

## Testing

glosa-av has 205+ unit tests across three test targets using Swift Testing (`@Test` / `@Suite` macros):

| Target | Files | Coverage |
|---|---|---|
| **GlosaCoreTests** | 7 | Parser (Fountain/FDX), Validator, Compiler, ScoreResolver, InstructComposer, Data Models |
| **GlosaAnnotationTests** | 3 | AnnotatedScreenplay, Serializers (Fountain/FDX) |
| **GlosaDirectorTests** | 4 | StageDirector (with mock providers), SceneAnalyzer, VocabularyGlossary, Compare |

Run all tests:

```bash
xcodebuild test -scheme glosa-av-Package -destination 'platform=macOS'
```

**Do not use `swift test`** — always use `xcodebuild`.

GlosaDirectorTests uses `MockAnnotationProvider` for deterministic LLM testing — no GPU or model download required.

## CI

GitHub Actions runs unit tests on every pull request to `main` (`.github/workflows/tests.yml`). The workflow uses `macos-26` runners with Swift 6.2+.

## Related Projects

- [SwiftVoxAlta](https://github.com/intrusive-memory/SwiftVoxAlta) — TTS synthesis library (`diga` CLI). Receives instruct strings via `GenerationContext`. **No changes needed for GLOSA.**
- [SwiftCompartido](https://github.com/intrusive-memory/SwiftCompartido) — Fountain and FDX parsers. Provides the `GuionElement` model that GlosaAnnotation extends.
- [SwiftBruja](https://github.com/intrusive-memory/SwiftBruja) — Local LLM inference on Apple Silicon. Powers the Stage Director's dramatic analysis.
- [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) — Shared model management. Handles LLM model discovery and downloads for the Stage Director.
- [Produciesta](https://github.com/intrusive-memory/Produciesta) — Podcast generation pipeline. Orchestrates the flow: uses glosa-av to annotate/compile instructs, then passes them to SwiftVoxAlta for audio generation.

## Reference

See [REQUIREMENTS.md](REQUIREMENTS.md) for the full language specification, element definitions, scope rules, format integration, architecture details, and implementation plan.
