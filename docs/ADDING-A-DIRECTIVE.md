# Adding a GLOSA Directive

**Scope:** This guide describes the `GlosaCore` library *as it exists after OPERATION
SKELETON EVICTION* (#17) — a Foundation-only, deterministic compiler. There is no
`GlosaDirector`, no `GlosaAnnotation`, and no `glosa` CLI in this package anymore; the
root `README.md` / `AGENTS.md` architecture tables still describe the old four-target
layout and are **stale**. The only product is `.library(name: "GlosaCore")`
(`Package.swift`).

> The LLM-driven "Stage Director" that *generates* directives (the old `PhrasingPass`
> work) lives outside this leaf now. This document is only about how the **compiler**
> recognizes, represents, validates, and emits a directive. If your directive needs an
> LLM to be authored, that's a separate concern layered on top of GlosaCore — GlosaCore
> only consumes directives that are already written into the screenplay.

---

## 1. The three directive archetypes

Every existing directive is one of three kinds. **Decide which one yours is before writing
any code — it determines which streams you touch.**

| | **Scope directive** | **Point directive** | **Standalone block event** |
|---|---|---|---|
| Examples | `SceneContext`, `Intent`, `Constraint` | `<breath/>`, `<pause/>` | `<include/>`, `<shot/>` |
| What it is | A *region* of delivery semantics that applies to one or more whole dialogue lines | A *positional marker* at one character offset inside one dialogue line | A *document-positional event* that belongs to the screenplay, not to any dialogue line |
| Authored as | A block tag in a `[[ ]]` note: `[[<Intent from="calm" to="angry">]]` | An inline note embedded in prose: `She turned.[[<pause length="beat"/>]] Slowly.` | Its own `[[ ]]` note: `[[<shot prompt="wide, rain"/>]]` — may sit in action or before any scene |
| Lives in the model as | A node in the `GlosaScore` scene/intent tree (`GlosaScore.SceneEntry` / `IntentEntry`) | An element appended to a flat array on `GlosaScore` (`breaths`, `pauses`) | An element appended to a flat array on `GlosaScore` (`includes`, `shots`), carrying its own `documentIndex` |
| Resolves into | `ResolvedDirectives` (one per line) → composed natural-language **instruct text** | An offset-keyed **point** projected onto an absolute line (`breathPoints` / `pausePoints`) | *Nothing* — it skips resolve/compose **and** offset projection |
| Output stream | `CompilationResult.instructs[lineIndex]: String` → `GlosaLineAnnotation.instruct` | `CompilationResult.{breath,pause}Points` → `GlosaLineAnnotation.{breathOffsets,pausePoints}` | `CompilationResult.{includes,shots}: [T]` → `GlosaScriptAnnotation.{includes,shots}` (via the `compileScript` façade) |

If your directive answers *"how should this run of dialogue be performed?"* it is a **scope
directive**. If it answers *"something happens at exactly this spot in the line"* it is a
**point directive**. If it answers *"something happens at this point in the screenplay,
independent of any one spoken line"* — an audio insert, a storyboard panel — it is a
**standalone block event**.

### The standalone block-event archetype (the simplest path)

Use `Include`/`Shot` as your reference. A block event is the *least* plumbing of the three
because it skips two whole stages:

1. **Model** — `public struct X: Sendable, Codable, Equatable` in `Sources/GlosaCore/X.swift`
   carrying `documentIndex: Int` + your payload (pure data — these structs double as the
   public DTO, so no separate `…DTO` layer).
2. **Score** — add `public var xs: [X]` to `GlosaScore` with the usual `CodingKeys` /
   `init(from:)` (`decodeIfPresent(...) ?? []`) / `encode(to:)`.
3. **Parse (Fountain)** — add a `parseXTag(_:documentIndex:)` block matcher near
   `GlosaParser.swift`'s other matchers and call it in the main loop **before the dialogue
   fallthrough**, passing the current `noteIndex` as `documentIndex`. It opens no scope and
   `continue`s. (Do **not** touch `GlosaInlineNotes` — block events are whole-note tags, not
   inline-stripped.)
4. **Parse (FDX)** — add a `handleXStart(attributes:)` dispatched from `didStartElement`,
   assigning `documentIndex` from the delegate's `blockEventCounter`.
5. **Result + Compiler** — add `public let xs: [X]` to `CompilationResult` and copy
   `score.xs` through in `compile()`, sorted by `documentIndex`. **No `mapXs…` projection** —
   the event already carries its position.
6. **Façade** — surface it on `GlosaScriptAnnotation` (returned by `compileScript`). The
   legacy `compileAnnotations` keeps returning only `.lines`, so existing callers are
   untouched.
7. **Validate** — flat-list checks in `GlosaValidator.validate(score:)` + new
   `GlosaDiagnostic.Code` cases. Keep them advisory (warnings) and lenient unless a value is
   genuinely unusable.

Note these events are **not** keyed by dialogue-line index, so — unlike point directives —
they are never dropped for living outside a scene (`sceneIndex == -1`).

---

## 2. The pipeline (and where each archetype plugs in)

`GlosaCompiler.compile()` (`Sources/GlosaCore/GlosaCompiler.swift:33`) chains four stages,
then runs two projection passes:

```
            ┌────────── scope directives ──────────┐   ┌──── point directives ────┐
notes ──▶ Parse ──▶ Validate ──▶ Resolve ──▶ Compose          Project to points
        (GlosaParser) (GlosaValidator) (ScoreResolver) (InstructComposer)  (mapBreaths/mapPauses…)
            │             │              │                │                      │
            ▼             ▼              ▼                ▼                      ▼
       GlosaScore   [GlosaDiagnostic] [ResolvedDirectives] instructs[Int:String]  breathPoints / pausePoints
```

Both archetypes are parsed into the **same** `GlosaScore` (stage 1) and both can emit
diagnostics (stage 2). They diverge after that:

- **Scope** directives flow Resolve → Compose: `ScoreResolver` walks the score and emits a
  `ResolvedDirectives` for *every* dialogue line; `InstructComposer.compose()` turns the
  active directives into one instruct sentence.
- **Point** directives skip Resolve/Compose entirely. After composing, `compile()` runs
  `mapBreathsToAbsoluteLines` / `mapPausesToAbsoluteLines`
  (`GlosaCompiler.swift:172` / `:273`) to convert scene-local `(sceneIndex,
  dialogueLineIndex, offset)` coordinates into absolute-line-keyed point dictionaries.

---

## 3. The streams — what a directive can represent in

This is the direct answer to *"what streams are new directives available to
process/represent in?"* There are six, in dataflow order. A new directive opts into a
subset of them depending on its archetype.

### 3a. Input syntax streams (where authors write it)

1. **Fountain block tags** — a `[[ ]]` note whose entire body is a tag, e.g.
   `[[<SceneContext location="bar" time="night">]]`. Recognized in the parser's main loop
   by per-tag matchers: `parseSceneContextTag` (`GlosaParser.swift:327`), `parseConstraintTag`
   (`:343`), `parseIntentTag` (`:365`). **This is the channel for scope directives.**
2. **Fountain inline notes** — a `[[<tag/>]]` embedded *inside* a dialogue paragraph, whose
   character position matters. Matched by the single combined regex in
   `GlosaInlineNotes.inlineNotePattern` (`Sources/GlosaCore/GlosaInlineNotes.swift`):
   `#"\[\[\s*(<(?:breath|pause)\b[^>]*/>)\s*\]\]"#`. **This is the channel for point
   directives**, and the `(?:breath|pause)` alternation is a hard-coded allowlist you must
   extend.
3. **FDX `glosa:` namespace XML** — the same directives expressed as XML elements for Final
   Draft files, handled by the `XMLParser` delegate (`parser(_:didStartElement:…)` at
   `GlosaParser.swift:925` and `:1137`, with point handlers `handleBreathStart` `:1032` and
   `handlePauseStart` `:1099`). **Every directive must be parseable from both Fountain and
   FDX** — they are two syntaxes for one model.

### 3b. In-memory model stream

4. **`GlosaScore`** (`Sources/GlosaCore/GlosaScore.swift`) — the parsed tree.
   - Scope directives become nodes: `SceneEntry.context`, `IntentEntry.intent`,
     `IntentEntry.constraints`.
   - Point directives become flat top-level arrays: `GlosaScore.breaths`, `GlosaScore.pauses`.
   - `GlosaScore` is `Codable`; its `CodingKeys` / `init(from:)` / `encode(to:)` are
     hand-written and use `decodeIfPresent(… ) ?? []` so older serialized scores still load.
     **Add your field there the same way.**

### 3c. Resolution stream (scope directives only)

5. **`ResolvedDirectives`** (`Sources/GlosaCore/ResolvedDirectives.swift`) — the per-line
   snapshot of which scope directives are active, produced by `ScoreResolver.resolveFlat`
   (`ScoreResolver.swift:130`). Each field is optional (`nil` = inactive = neutral). A new
   scope directive needs a new optional field here, populated by the resolver.

### 3d. Output streams (`CompilationResult`, `Sources/GlosaCore/CompilationResult.swift`)

6. The compiler's outputs, all keyed by **absolute dialogue-line index**:
   - **`instructs: [Int: String]`** — composed natural-language delivery text. Scope
     directives land here via `InstructComposer`.
   - **`breathPoints` / `pausePoints: [Int: [...]]`** — offset-keyed positional points. Point
     directives land here (you add a sibling dictionary).
   - **`diagnostics: [GlosaDiagnostic]`** — warnings/info. *Any* directive can write here.
   - **`provenance: [InstructProvenance]`** — audit trail tying each instruct back to its
     source scope directives. Extend only if your scope directive should be auditable.

### 3e. Consumer DTO stream

The public façade `compileAnnotations(fountainNotes:rawDialogueLines:)`
(`GlosaLineAnnotation.swift:191`) projects `CompilationResult` into
**`GlosaLineAnnotation`** — the serializable, internal-type-free DTO that crosses the
glosa-av → TTS-consumer boundary. It currently exposes `spokenText`, `breathOffsets`,
`breathStrengths`, `instruct`, and `pausePoints` (`[PausePointDTO]`). **If a downstream
consumer must see your directive, you also extend this DTO and its projection loop
(`:218`–`:228`).** A directive that only affects `instruct` text (a scope directive) needs
no DTO change — it rides the existing `instruct` field.

---

## 4. There is no directive registry — every directive is special-cased

`GlosaParser` is a hand-rolled, sequential state machine, **not** a table-driven dispatcher.
There is no central `enum DirectiveKind` or registry; each directive is recognized by its
own matcher and threaded through its own variables in the main loop. Likewise the validator,
resolver, composer, and projector each have per-directive branches. Adding a directive is
therefore a **cross-cutting change** — you touch every stage by hand. The checklists below
enumerate the exact sites.

> Architectural note worth flagging: because there's no registry, the cost of each new
> directive is linear in the number of stages, and it's easy to wire a directive into the
> parser but forget the validator or the DTO. If GLOSA grows many more directives, a
> registry/protocol refactor (one `Directive` protocol with `parse` / `validate` /
> `resolve|project` hooks) would pay for itself. Today, follow the checklist.

---

## 5. Checklist — adding a **scope** directive `X`

Use `Constraint` as your reference implementation; it's the simplest scope directive
(forward-applying, no closing tag).

1. **Model** — new `public struct X: Sendable, Codable, Equatable` in
   `Sources/GlosaCore/X.swift` (mirror `Constraint.swift`).
2. **Score** — attach it to the tree in `GlosaScore.swift`: add it to `SceneEntry` or
   `IntentEntry` (e.g. an `[X]` array like `constraints`), update the `init`, and — if it's a
   top-level field — its `CodingKeys` / `init(from:)` / `encode(to:)`.
3. **Parse (Fountain)** — add `parseXTag(_:) -> X?` near `GlosaParser.swift:343`, and call it
   in the main loop alongside the other block-tag checks (~`:166`). Reuse `extractAttribute`
   (`:384`) for attributes. Decide scoping semantics: scoped-with-closing-tag (like `Intent`)
   vs. forward-marker (like `Constraint`).
4. **Parse (FDX)** — handle the `glosa:x` element in the `XMLParser` delegate
   (`didStartElement`, `:925` / `:1137`).
5. **Resolve** — add an optional field to `ResolvedDirectives` (`ResolvedDirectives.swift`)
   and populate it in `ScoreResolver.resolveFlat` (`ScoreResolver.swift:130`) as the resolver
   walks into/out of your directive's scope.
6. **Compose** — add a `composeX(_:) -> String` to `InstructComposer.swift` and append its
   sentence in `compose(_:)` (`:25`). This is what makes your directive show up in the
   `instruct` text stream.
7. **Validate** — add rules in `GlosaValidator.validate(notes:)` / `validate(score:)` and any
   new `GlosaDiagnostic.Code` cases (`GlosaDiagnostic.swift`).
8. **Provenance** (optional) — if auditability matters, add the field to `InstructProvenance`
   and populate it in `GlosaCompiler.compile()` (`:76`).
9. **DTO** — usually *nothing*: a scope directive's effect is already carried by
   `GlosaLineAnnotation.instruct`.

---

## 6. Checklist — adding a **point** directive `X`

Use `Pause` as your reference; `Breath`/`Pause` are near-mirror implementations, so most
sites already show you the exact pattern to copy.

1. **Model** — new `public struct X: Sendable, Equatable, Codable` in
   `Sources/GlosaCore/X.swift` carrying `sceneIndex`, `dialogueLineIndex`, `characterOffset`,
   and your payload (mirror `Pause.swift`). Define any payload enum (cf. `PauseLength`) with
   its `Codable` string mapping.
2. **Score** — add `public var xs: [X]` to `GlosaScore` plus its `CodingKeys` /
   `init(from:)` / `encode(to:)` entries, using `decodeIfPresent(...) ?? []`.
3. **Parse (Fountain inline)** — extend the allowlist alternation in
   `GlosaInlineNotes.inlineNotePattern` to `(?:breath|pause|x)`. Add `parseXTag(...)` near
   `GlosaParser.swift:735`, collect into the `xs` array in `extractInlineNotes` (`:482`),
   and emit an "outside dialogue" warning for stray notes (cf. breath/pause handling ~`:224`).
   Offsets must be `unicodeScalars.count` indices into the **notes-stripped** prose — route
   all stripping through `GlosaInlineNotes` so offsets stay consistent (see its *Offset
   convention* doc comment).
4. **Parse (FDX)** — add `handleXStart(attributes:)` (cf. `:1032`/`:1099`) and dispatch it
   from the `didStartElement` delegate.
5. **Project** — add a `PointX`/`XPoint` companion in `CompilationResult.swift` (cf.
   `BreathPoint`/`PausePoint`), add an `xPoints: [Int: [XPoint]]` field to
   `CompilationResult`, write `mapXsToAbsoluteLines` in `GlosaCompiler.swift` (copy
   `mapPausesToAbsoluteLines`, `:273`), and call it from `compile()` (~`:94`).
6. **Interactions** — if your point can collide with breath/pause at the same `(line,
   offset)`, decide precedence and handle it in the same-offset collapse block
   (`GlosaCompiler.swift:112`); add a `GlosaDiagnostic.Code` if you drop anything.
7. **Validate** — add rules + `GlosaDiagnostic.Code` cases (e.g. offset-out-of-range,
   duplicate-offset), mirroring the `breath*` codes in `GlosaDiagnostic.swift`.
8. **DTO** — extend `GlosaLineAnnotation` with your offsets/payload (cf. `breathOffsets` /
   `pausePoints: [PausePointDTO]`); if the payload is non-trivial add an `XPointDTO` like
   `PausePointDTO`, and project it in the `compileAnnotations` loop
   (`GlosaLineAnnotation.swift:218`–`:228`). **Point directives almost always need a DTO
   change** — that's how the consumer learns where the seam is.

---

## 7. Tests

Mirror the existing per-directive test coverage under `Tests/GlosaCoreTests/`. The
breath/pause suites are the template — for a point directive expect parser tests (Fountain +
FDX), validator tests, compiler/projection tests, and a round-trip; for a scope directive,
parser + resolver + composer + validator tests. Build and test with `xcodebuild` /
XcodeBuildMCP (`swift_package_test`) — never `swift build` / `swift test` (see `CLAUDE.md`).

---

## 8. Quick reference — touch-point map

| Stage | File | Scope directive | Point directive |
|---|---|---|---|
| Model | `X.swift` | ✅ new struct | ✅ new struct + payload enum |
| Score | `GlosaScore.swift` | tree node | flat `[X]` array + Codable |
| Parse Fountain | `GlosaParser.swift` | `parseXTag` block matcher | inline regex allowlist + `extractInlineNotes` |
| Parse FDX | `GlosaParser.swift` | `didStartElement` | `handleXStart` |
| Resolve | `ScoreResolver.swift` / `ResolvedDirectives.swift` | ✅ new optional field | — |
| Compose | `InstructComposer.swift` | ✅ `composeX` | — |
| Project | `GlosaCompiler.swift` / `CompilationResult.swift` | — | ✅ `mapXsToAbsoluteLines` + points dict |
| Validate | `GlosaValidator.swift` / `GlosaDiagnostic.swift` | ✅ rules + codes | ✅ rules + codes |
| DTO | `GlosaLineAnnotation.swift` | rarely (rides `instruct`) | ✅ offsets/payload + projection |
