---
type: project
title: glosa-av 0.9.0 — GLOSA notation 2.0 (JSON block directives)
updated: 2026-10-20
state: draft
glosa_notation: "2.0"
release: glosa-av 0.9.0
---

# glosa-av 0.9.0 — GLOSA notation 2.0

GLOSA block directives — `<shot/>` and `<include/>` — become **JSON objects** inside
Fountain notes. Performance directives (`<breath/>`, `<Intent>`, `<SceneContext>`,
`<Constraint>`, pauses) keep their tag form. The tag form of a block directive is still
read, with a deprecation diagnostic, and a migration function rewrites it.

This is a **version bump of the notation**, not just the package: the syntax through
glosa-av 0.8.x is **GLOSA notation 1.0**; this release defines **GLOSA notation 2.0**.
A notation 2.0 document cannot be read by a 0.8.x parser — its shots would be silently
ignored — so consumers must move to 0.9.0 before any document is written in 2.0.

GlosaCore also gains the two computations every shot consumer needs and today
re-implements: **folding defaults** into an effective shot, and a **render digest** that
says whether two effective shots would produce the same picture.

## Why

1. **The tag form cannot carry every value.** `extractAttribute`
   (`GlosaParser.swift:521`) is a regex over `name="…"` then `name='…'` with no escape
   mechanism. A value containing both quote characters cannot be written; a value
   containing `]]` closes the Fountain note early. Editors that write shots have to
   refuse such values.
2. **Lists are strings.** `ref` is `"A,B,C"`, so an entry cannot contain a comma.
3. **Unknown attributes vanish.** `parseShotTag` (`GlosaParser.swift:451`) reads a fixed
   attribute list. A tool that re-serializes a `Shot` erases every attribute added after
   it was built.
4. **Shot data has three shapes.** The note, the metadata a renderer records beside each
   image, and a storyboard manifest each describe the same shot differently. With JSON
   they can be one object in one schema.
5. **The fold is re-implemented downstream.** Each renderer and editor folds promptless
   defaults shots itself; a digest computed over differently folded shots is useless.

## 1. The notation

### 1.1 Block directive form (Fountain carrier)

A block directive is a Fountain note whose trimmed content is a JSON object with
**exactly one key**, the directive name:

```fountain
[[ {"shot": {
  "prompt": "A lighthouse keeper climbs the spiral stair at dusk, lantern in hand",
  "caption": "The light has to be lit by nine.",
  "style": "ink wash, muted blue palette",
  "model": "klein4b",
  "aspect": "wide",
  "ref": ["KEEPER", "lighthouse-interior.png"],
  "output": "storyboards/keeper-01.png"
}} ]]

[[ {"include": {"src": "audio/surf.m4a", "gain": -12.0, "mode": "bed"}} ]]
```

- Known block directives in 2.0: `shot`, `include`. Their object keys are the same names
  and meanings as the 1.0 attributes (`Shot.swift`, `Include.swift`), with JSON types:
  integers, numbers, booleans, strings, and `ref` as an array of strings.
- A note may span lines (Fountain allows line breaks in a note; it does not allow blank
  lines, and canonical JSON output never contains one).
- **Detection is by prefix, because the parser cannot tell notes from dialogue.**
  `parseFountain(notes:)` receives one array that mixes note contents and dialogue lines
  (`GlosaParser.swift:17–23`, `:295–303`). An element is a **candidate block directive**
  only when its trimmed text starts with `{` followed by optional whitespace and then
  `"` (so `{"shot"` and `{ "shot"` both qualify). `{beat} Fine.` and other prose starting with `{` stay exactly as in 1.0.
  Known limitation, documented in the README: a dialogue line that itself starts with
  `{"` is treated as a candidate (and, if it is not a valid directive, reported and
  dropped). Regression test: `{beat} Fine.` inside an `<Intent>` span stays dialogue and
  every following line index and breath/pause offset is unchanged.
- **Order and coverage.** Candidate detection runs **before** the existing substring
  checks for `</Intent>`, `<shot`, etc. in the note loop, and the same rule is applied in
  `GlosaValidator.validate(notes:)`, which scans notes independently
  (`GlosaValidator.swift:29–67`).
- A candidate that parses as a JSON object with exactly one key naming a known block
  directive is that directive. If it does not parse, or has another shape, the
  parser emits a diagnostic (§ 3) and the note yields no event — it is never silently
  treated as a 1.0 tag or as prose.
- Inside JSON strings, `]]` is written `]\u005d` and `[[` is written `[\u005b`, so a value
  can never end or nest the note. The parser needs nothing special: JSON decodes them.

### 1.2 Notation 1.0 stays readable

`<shot …/>` and `<include …/>` notes parse exactly as in 0.8.x, plus `ref`/`character`
(already on `development`, `518ff02`). Each 1.0 block directive yields a
`.deprecatedTagDirective` **info** diagnostic naming the replacement. Removal of the 1.0
block form is a later notation major (3.0), not this release.

### 1.3 What does not change

- Performance directives and inline notes (`[[<breath/>]]` mid-line, paired
  `<Intent>`…`</Intent>`) — unchanged.
- The FDX carrier — `<glosa:shot …/>` elements keep XML attributes; FDX is XML natively.
  `ref` there remains comma-separated. A JSON FDX form is out of scope.
- `parseFountain(notes:)` / `parseFountainWithDiagnostics(notes:)` signatures
  (`GlosaParser.swift:25`, `:47`): callers still pass note texts.

## 2. API

1. **`GlosaVersion.notation = "2.0"`** beside the package `version`
   (`GlosaVersion.swift`).
2. **The shot schema.** `schemas/shot.schema.json` (JSON Schema 2020-12), `$id`
   containing `2.0`, describing the `shot` object: every `Shot` key with its type,
   `additionalProperties: true`. Shipped as a package resource and documented in the
   README. A matching `schemas/include.schema.json`.
3. **`Shot.extraAttributes`** and **`Include.extraAttributes`**: unknown keys, in the
   order read, as raw JSON values (a small `GlosaJSONValue` enum: string, number, bool,
   null, array, object). Empty when there are none. Codable round-trip; legacy JSON
   without the field decodes to empty.
4. **`Shot.effective(given defaults: [Shot]) -> Shot`** — fold: walk `defaults` (the
   promptless shots preceding this one, in document order), each key replacing the
   accumulated value; the shot's own keys win; `caption` and `output` are never
   inherited (**behaviour change**: today downstream folds exclude only `caption`; an
   inherited `output` makes every later panel overwrite one file, so excluding it is
   deliberate and goes in the CHANGELOG); `extraAttributes` fold per key like any other. **Charter amendment:** the
   `Shot.swift` header's "GlosaCore stays parse-and-carry … does not compute effective
   shots" is replaced with a description of this function.
5. **`GlosaScore.effectiveShots`** — convenience returning every panel shot (non-empty
   `prompt`) already folded, in document order.
6. **`Shot.renderDigest: String`** — lowercase hex SHA-256 of the **RFC 8785 (JCS)**
   canonical JSON of the effective shot object, **excluding** `caption`, `output`,
   `preview`, `telemetry` and `documentIndex`, **including** unknown keys. JCS is
   implemented in GlosaCore (number formatting per ECMAScript, UTF-16 key ordering);
   SHA-256 comes from **CryptoKit**, so GlosaCore's dependency statement changes from
   "Foundation only" to "Foundation and CryptoKit" (both system frameworks; no package
   dependency). **`seed` enters the digest preimage as a decimal string**, because JCS
   numbers are IEEE doubles and a `UInt64` seed above 2^53 would lose precision and
   collide. Frozen for notation 2.x: a change is a notation major.
   In the note itself `seed` is a JSON integer; the parser also accepts a decimal string
   (for writers in languages without 64-bit integers), and the serializer writes a
   string when the value exceeds 2^53 − 1.
7. **`Shot.serialize() -> String`** and **`Include.serialize() -> String`** — the
   canonical 2.0 note, `[[ {"shot": {` … `}} ]]`: one key per line, two-space indent,
   keys in the fixed order `prompt, caption, style, model, aspect, width, height, steps,
   guidance, seed, negative, lora, loraScale, ref, character, output, preview,
   telemetry` (for `include`: `src, gain, mode, fadeIn, fadeOut, prompt`), then
   `extraAttributes` in read order; `nil` keys omitted; every non-integer numeric key
   (`guidance`, `loraScale`, `gain`, `fadeIn`, `fadeOut`) with at least one decimal;
   arrays on one line (`"ref": ["A", "B"]`); `]]`/`[[` escaped as in § 1.1.
8. **Bare-object codec (schema form).** `Shot.schemaJSON() -> GlosaJSONValue`,
   `Shot.schemaJSONData() -> Data` (canonical key order, no wrapper), and
   `Shot(schemaJSON: GlosaJSONValue, documentIndex: Int = 0) throws` /
   `Shot(schemaJSONData: Data, documentIndex: Int = 0) throws` (both throw on a non-object
   or a wrongly typed known key; `documentIndex` is not part of the schema, so the caller
   supplies it). A defaults shot is an object without `prompt`; decoding sets `prompt`
   to `""`, and encoding omits `prompt` when it is empty. This is the bare
   `shot` object exactly as the schema describes it: no `documentIndex`, unknown keys at
   the top level (not nested under `extraAttributes`). `serialize()` wraps this in the
   note form; render records and CLI input use it directly. The synthesized `Codable`
   conformance stays for in-process persistence and is documented as *not* the schema
   form. Same pair for `Include`.
9. **`GlosaFountainNotes.standaloneNotes(in fountainText: String) -> [(range:
   Range<String.Index>, text: String)]`** — GlosaCore has no way today to find notes in a
   Fountain document (callers pass note texts in). This locates standalone `[[ … ]]`
   notes (own block, blank line before and after), for the migration below and for
   tests. It does not replace callers' own extraction.
10. **`GlosaMigration.migrateBlockDirectives(in fountainText: String) -> (text: String,
   migrated: Int, skipped: Int)`** — rewrites each 1.0 `<shot …/>` / `<include …/>` note to its 2.0
   serialization and leaves every other byte identical. Only standalone notes are migrated; a 1.0 block
   directive inside an action or dialogue line is left alone and counted in `skipped`
   (the CLI reports it with its line). Pure function; the CLI that
   applies it to files belongs in glosa-tools (follow-up, not this mission).

**A hand-written JSON reader.** Keeping unknown keys in read order and reporting errors
with line and column rule out `JSONSerialization` and `JSONDecoder`. GlosaCore gets a
small order-preserving JSON reader producing `GlosaJSONValue` with source positions;
JCS output is written by GlosaCore too.

**Compile path.** `GlosaCompiler.compile` calls `parseFountain` and drops parser
diagnostics (`GlosaCompiler.swift:48`). It must surface them (use
`parseFountainWithDiagnostics` and pass the diagnostics into the compilation result), or
an invalid JSON shot is silently absent from compiled output.

## 3. Diagnostics

**A new severity.** `GlosaDiagnostic.Severity` has only `warning` and `info`
(`GlosaDiagnostic.swift:9–14`). Add `error`. Adding a case to a public enum is
**source-breaking** for any consumer that switches over it exhaustively; the CHANGELOG
says so and the release is a minor (pre-1.0). An invalid JSON note is an error because
the author's shot is silently absent from every render otherwise.

New `GlosaDiagnostic.Code` cases (additive; existing cases untouched):

| Code | Severity | When |
|---|---|---|
| `invalidBlockDirectiveJSON` | error | a candidate note fails to parse; message carries the parser's line and column within the note |
| `unknownBlockDirective` | warning | valid JSON object whose single key is not a known block directive, or with more than one key |
| `deprecatedTagDirective` | info | a notation 1.0 `<shot/>` or `<include/>` was read |

**The validator's model list.** `GlosaValidator.knownShotModels` warns
(`shotUnknownModel`) on any model it does not list, which flags every cloud model in
use. Replace the closed list with a pattern-free check: warn only on an empty `model`
string. Model vocabulary belongs to the renderer.

## 4. Tests

- Parse: every 1.0 fixture still yields the same `Shot`/`Include` values (existing
  suites stay green unmodified).
- Parse 2.0: every key and type; `ref` array; unknown keys preserved with their JSON
  types; multi-line notes; escaped `]]`/`[[`; invalid JSON → `invalidBlockDirectiveJSON`
  with position; wrong shapes → `unknownBlockDirective`; `{ "shot": …}` (whitespace after
  the brace) is detected; a `{"`-prefixed note that is not valid JSON is reported, not
  swallowed; prose like `{beat} Fine.` is untouched.
- Serialize: `parse(serialize(x)) == x` for generated shots (property test over all
  keys); `serialize(parse(n)) == n` for canonical notes; key order; decimal formatting;
  escapes.
- Fold: per-key replacement, document order, caption/output not inherited, extras fold.
- Digest: golden vectors checked in under `Tests/…/Fixtures/digest/` (shot JSON →
  expected hex); excluded keys do not change it; key order in the source does not
  change it; JCS number edge cases (`1.0` vs `1`, exponents).
- Migration: a synthetic fixture with mixed 1.0 block and performance directives
  migrates only the block directives; the rest is byte-identical; idempotent.
- No private screenplays in fixtures — synthetic text only (repo visibility rule).

## 5. Release

- `GlosaVersion.version` → `0.9.0`; `GlosaVersion.notation` → `2.0`.
- CHANGELOG: a **Notation 2.0** section stating the incompatibility for 0.8.x readers.
- README: **add** a notation section (the README documents no directives today) showing
  the 2.0 block form first and the 1.0 form as deprecated; links both schemas.
- **Resources.** `Package.swift` declares none today. Add `resources: [.copy("schemas")]`
  (or process) to the `GlosaCore` target for the schemas, and test resources for the
  digest golden vectors.
- **Housekeeping (public repo rule).** Private downstream app names appear in
  `README.md`, `AGENTS.md`, `Include.swift`, `Shot.swift`, `GlosaValidator.swift`,
  `GlosaDiagnostic.swift`, two test files, older CHANGELOG entries, ~16 files under
  `docs/` and the tracked `graphify-out/` graph (regenerate it after the edits); reword them
  generically (find them with a grep of the org's app names).
- Ship with `/ship-swift-library minor`.

## Non-goals

- Converting performance directives to JSON.
- A JSON carrier for FDX or Markdown.
- The `glosa migrate` CLI (glosa-tools follow-up).
- Resolving `ref` names to files, or validating `character` — renderer concerns.

## Acceptance

1. All pre-existing tests pass unchanged, **except** the validator test that expects
   `shotUnknownModel` for `"sd-xl"` (`IncludeShotValidatorTests.swift:41–47`), which is
   rewritten for the new rule (warn only on an empty model).
2. The § 1.1 example parses to a `Shot` with `ref == ["KEEPER", "lighthouse-interior.png"]`
   and an `Include` with `gain == -12.0`.
3. `serialize` of that shot reproduces the § 1.1 note byte-for-byte (modulo the example's
   key order, which is already canonical).
4. A 1.0 document migrates to 2.0, re-parses to equal values, and its performance
   directives are byte-identical.
5. Golden digest vectors pass; changing `caption` or `output` leaves the digest equal;
   changing `prompt`, `style`, `ref` order or an unknown key changes it.
6. A shot with `"model": "google-nano-banana-2.1"` produces no `shotUnknownModel`.
