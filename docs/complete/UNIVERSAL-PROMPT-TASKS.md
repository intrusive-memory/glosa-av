---
type: mission
state: complete
updated: 2026-07-08
---

# Universal `prompt` Attribute — Tracking Document

**Goal:** Make `prompt` a universal, carried-through property of **every** GLOSA
directive. Each tag may carry `prompt="…"` — a freeform description of the audio
intent — which the compiler parses and surfaces on its output DTOs so the
downstream orchestrator (Produciesta → SwiftVoxAlta) can forward it to the audio
model. GlosaCore stays a deterministic, Foundation-only leaf; it **never**
interprets `prompt` or calls an LLM. GLOSA is the transport.

> Example: `[[<pause prompt="silence as a plastic grocery bag blows between them"/>]]`

## Design decisions

- **① `<shot>` keeps its single existing `prompt`.** Shot's `prompt` is the
  image/storyboard prompt piped to Vinetas; a shot emits no audio, so no second
  audio-prompt field is added. Shot already satisfies "every tag has a prompt."
- **② Scope prompts combine per-line.** A line under a scene + intent +
  constraint joins their prompts (scene → intent → constraint order, space
  separated) into one per-line `GlosaLineAnnotation.prompt`, mirroring `instruct`.
- **Backward compatibility:** every new field is optional / defaulted, so all
  existing call sites and serialized scores keep working.

## Surfacing map

| Tag | Archetype | Output surface for `prompt` |
|---|---|---|
| `SceneContext` | scope | combined into `GlosaLineAnnotation.prompt` |
| `Intent` | scope | combined into `GlosaLineAnnotation.prompt` |
| `Constraint` | scope | combined into `GlosaLineAnnotation.prompt` |
| `<breath/>` | point | parallel `GlosaLineAnnotation.breathPrompts: [String?]` |
| `<pause/>` | point | `PausePointDTO.prompt` |
| `<include/>` | block | `Include.prompt` on `GlosaScriptAnnotation.includes` |
| `<shot/>` | block | existing `Shot.prompt` (decision ①) |

## Status legend

- ☐ TODO · ⧗ IN PROGRESS · ✅ DONE (implemented) · 🧪 TESTED (verified via build/test)

## Tasks

| # | Task | Files | Status | Tested |
|---|------|-------|:------:|:------:|
| 1 | Add `prompt: String?` to models | `SceneContext.swift`, `Intent.swift`, `Constraint.swift`, `Breath.swift`, `Pause.swift`, `Include.swift` | ✅ | 🧪 |
| 2 | Add `prompt` to compiler companions + projection | `CompilationResult.swift` (`BreathPoint`/`PausePoint`), `GlosaCompiler.swift` (`mapBreaths…`/`mapPauses…`) | ✅ | 🧪 |
| 3 | Parse `prompt="…"` — Fountain | `GlosaParser.swift` (scene/intent/constraint block matchers, breath/pause inline matchers, include matcher) | ✅ | 🧪 |
| 4 | Parse `prompt="…"` — FDX | `GlosaParser.swift` (`handle*Start` / `didStartElement`) | ✅ | 🧪 |
| 5 | Resolve/compose scope prompts | `InstructComposer.swift` (`composePrompt`), `GlosaCompiler.swift` (`prompts` dict), `CompilationResult.swift` (`prompts`) | ✅ | 🧪 |
| 6 | DTO surfacing | `GlosaLineAnnotation.swift` (`prompt`, `breathPrompts`, `PausePointDTO.prompt`, projection loop) | ✅ | 🧪 |
| 7 | Validator advisory rule | `GlosaValidator.swift`, `GlosaDiagnostic.swift` (empty/whitespace `prompt`) | ✅ | 🧪 |
| 8 | Tests | `Tests/GlosaCoreTests/UniversalPromptTests.swift` (19 tests: parser F+FDX, compiler/projection, DTO, validator, Codable round-trip + legacy-JSON) | ✅ | 🧪 |
| 9 | Docs | `AGENTS.md`, `docs/ADDING-A-DIRECTIVE.md` §0 | ✅ | 🧪 |
| 10 | Build + test + `swift format` | whole package | ✅ | 🧪 |

> **All tasks complete and verified.** `xcodebuild test … ` → **262 tests in 25 suites
> passed** (including the new 19-test "Universal prompt attribute" suite). `swift format`
> applied to `Sources/` + `Tests/`.

## Verification evidence

- `xcodebuild build … BUILD SUCCEEDED` (after each stage).
- `xcodebuild test -scheme glosa-av -destination 'platform=macOS,arch=arm64'`
  → `Test run with 262 tests in 25 suites passed`.
- New suite covers all seven tags across Fountain + FDX, compiler projection,
  DTO surfacing (scope-combined `prompt`, `breathPrompts`, `PausePointDTO.prompt`,
  `Include.prompt`), the `.promptEmpty` advisory, and backward-compatible decoding
  of legacy JSON missing the new fields.

## Log

- 2026-07-08 — Document created; plan approved (carried-transport model, all 7 tags, decisions ① and ②).
- 2026-07-08 — Tasks 1–6 implemented (models, compiler companions/projection, Fountain + FDX parsing, resolve/compose, DTO surfacing); package builds clean.
- 2026-07-08 — Task 7 validator `.promptEmpty` advisory added; builds clean.
- 2026-07-08 — Task 8 test suite added (19 tests); full run = 262 tests passing.
- 2026-07-08 — Task 9 docs updated (AGENTS.md + ADDING-A-DIRECTIVE.md §0).
- 2026-07-08 — Task 10 `swift format` applied; final `xcodebuild test` = 262 passing. **Mission complete.**
