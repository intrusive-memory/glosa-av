---
type: recon-report
state: current
requirements_file: REQUIREMENTS.md
requirements_sha256: 1d64310a5fe9d5d70df1c90dcd7c7a2dd0325d67b3d4dffdfe260fe7e77f2c50
project_head: 7d0d8c138198c72f39e3a0f71c6e208e6cbedc63
search_root: ~/Projects
generated: 2026-10-20
verdict: CLEAR
---

# RECON_REPORT.md — glosa-av 0.9.0 (GLOSA notation 2.0)

## Terminology

> **Mission** — A definable, testable scope of work.
> **Sortie** — An atomic, testable unit of work executed by a single agent in one dispatch.
> **Work Unit** — A grouping of sorties.

## Fourth pass (requirements revision 4, HEAD `7d0d8c1`)

Re-run by `breakdown` because the requirements hash changed. `git diff --stat 518ff02 HEAD --
Sources Tests Package.swift Makefile .github` is empty, so every citation below still holds.
The new requirement citations were checked: Parser:15–24 and :293–305 (the mixed
`notes:` doc comments) and `GlosaValidator.swift:29–67` (its own substring scan) — CONFIRMED.
Status of the third pass's non-blocking notes against revision 4:

| Note | Status |
|------|--------|
| 1 § 4 vs § 1.1 | Resolved (§ 4 now says `{"`-prefixed non-JSON is reported; `{beat} Fine.` untouched) |
| 2 whitespace after brace | Resolved (`{` + optional whitespace + `"`) |
| 3 schema-codec gaps | Resolved (`throws`, `documentIndex: Int = 0`, missing `prompt` ↔ `""`, empty omitted) |
| 4 detection order / validator scan | Resolved (§ 1.1 "Order and coverage") |
| 5 housekeeping list | Resolved (AGENTS.md, `docs/`, `graphify-out/` named). Grep also hits `Breath.swift` and `GlosaLineAnnotation.swift`, but only for a public package name, which the rule does not cover |
| 6 "Foundation-only" wording | Still implicit; `Package.swift:16` and `tests.yml:45,62,114` — planned as a task |
| 7 frontmatter type | Stamped by `breakdown` |

One new non-blocking gap: § 2.2 says `schemas/shot.schema.json` and § 5 says
`resources: [.copy("schemas")]` on the `GlosaCore` target. SwiftPM resources must live inside
the target directory, so the files go at `Sources/GlosaCore/schemas/`. That is the only
layout that compiles, so it is not a question.

## Verdict

**CLEAR** — 36 assumptions checked, 33 confirmed, 0 blocking, 3 unverifiable.

This is the third recon of the day. The second recon's blocking finding (A-26, detecting
JSON in a `notes:` array that mixes notes and dialogue) is resolved: § 1.1 now detects only
on a trimmed `{"` prefix, documents the limitation and adds the `{beat} Fine.` regression
test. Of the second recon's non-blocking notes, the compile path (old note 1), the JSON
reader (old 3), serialization format (old 5), migration of non-standalone directives
(old 7) and the housekeeping list (old 6, partly) are now addressed in the requirements.
The revision also added the bare-object schema codec (§ 2.8). Its presuppositions are
A-34 to A-36. All three hold, but the codec spec leaves two gaps (note 3).

Source is unchanged since `518ff02`. `eed3dc9` adds only the mission docs, and the working
tree's only changes are the two mission docs. So every line citation from the second recon still
holds and was spot-checked again (Parser :25, :47, :451, :521; `GlosaDiagnostic.swift:9–14`;
`IncludeShotValidatorTests.swift:41–47`; `GlosaCompiler.swift:48`). The repo has no package
dependencies. Recon ran single-hub with no spokes. It was read-only: no builds, no resolution,
no network. Every verdict carries a citation.

## Assumption Findings

Paths are relative to the repo root. "Parser" = `Sources/GlosaCore/GlosaParser.swift`.

| ID | Kind | Claim | Locus | Verdict | Evidence |
|----|------|-------|-------|---------|----------|
| A-01 | A-API | `extractAttribute` (`GlosaParser.swift:521`) is a regex for `name="…"`, then `name='…'`, with no escapes | repo | CONFIRMED | Parser:521–546 |
| A-02 | A-API | `parseShotTag` (`:451`) reads a fixed attribute list | repo | CONFIRMED | Parser:451–477 |
| A-03 | A-DATA | 1.0 `ref` is comma-separated; the model type is already an array | repo | CONFIRMED | `refList` Parser:500–505; `Shot.ref: [String]?` `Shot.swift:120` |
| A-04 | A-API | `Shot` keys match the § 2.7 order list (+ `documentIndex`) | repo | CONFIRMED | `Shot.swift:51–125` |
| A-05 | A-API | `Include` keys are `src, gain, mode, fadeIn, fadeOut, prompt`; `mode` accepts `bed` | repo | CONFIRMED | `Include.swift:25,30,34,37,40,46`; `.bed` :73 |
| A-06 | A-API | `ref`/`character` are already on `development` at `518ff02` | repo | CONFIRMED | `git log`: `518ff02 feat(shot): add ref and character`; `Shot.swift:120,125` |
| A-07 | A-API | `parseFountain(notes:)` is at :25 and `parseFountainWithDiagnostics(notes:)` at :47 | repo | CONFIRMED | Parser:25, :47 |
| A-08 | A-API | `GlosaVersion.version` is in `GlosaVersion.swift`, and there is no `notation` yet | repo | CONFIRMED | `GlosaVersion.swift:3` (`"0.8.1-dev"`) |
| A-09 | A-DATA | The `Shot.swift` header says "parse-and-carry … does not compute effective shots" | repo | CONFIRMED | `Shot.swift:30–33` |
| A-10 | A-BEHAVIOR | Today only `caption` is exempt from inheritance, so excluding `output` is a behaviour change | repo | CONFIRMED | `Shot.swift:17–28`, `:37–46`; `CHANGELOG.md:29` |
| A-11 | A-API | `GlosaScore.shots` holds every shot in document order | repo | CONFIRMED | `GlosaScore.swift:74–77`; append order Parser:213–214 |
| A-12 | A-API | `GlosaDiagnostic.Code` exists and can be extended | repo | CONFIRMED | `GlosaDiagnostic.swift:18–62` |
| A-13 | A-API | `Severity` has only `warning` and `info` at `GlosaDiagnostic.swift:9–14` (adding `error` is a deliverable) | repo | CONFIRMED | `GlosaDiagnostic.swift:9,11,13`. Nothing in `Sources/` or `Tests/` switches over `Severity`; the only use is `== .warning` (`GlosaValidator.swift:424`), so the new case breaks nothing inside the package |
| A-14 | A-API | `GlosaValidator.knownShotModels` warns `shotUnknownModel` on unlisted models | repo | CONFIRMED | `GlosaValidator.swift:325–335`; `private static` list :357 |
| A-15 | A-BEHAVIOR | FDX `<glosa:shot/>` uses XML attributes with a comma `ref` | repo | CONFIRMED | `handleShotStart` Parser:1343–1362 (`refList`) |
| A-16 | A-BEHAVIOR | Inline `[[<breath/>]]` notes and paired `<Intent>` are handled apart from block parsing | repo | CONFIRMED | `GlosaInlineNotes.swift:24–30`; Parser:183–202, :222–239 |
| A-17 | A-API | `Shot`/`Include` are Codable + Equatable, and legacy-JSON decode is tested | repo | CONFIRMED | `Shot.swift:47`, `Include.swift:15`; `IncludeShotParserTests.swift:240,263`. Both use **synthesized** Codable (no `init(from:)`/`CodingKeys` in either file) |
| A-18 | A-INVARIANT | GlosaCore has no package dependencies, and adding CryptoKit doesn't trip the CI leaf guard | repo | CONFIRMED | `Package.swift:14,19` `dependencies: []`; the guard regex is `.github/workflows/tests.yml:85` (named packages only, `CryptoKit` does not match) |
| A-19 | A-INVARIANT | The only test that breaks under the § 3 model rule is `IncludeShotValidatorTests.swift:41–47` (`sd-xl`) | repo | CONFIRMED | `shotUnknownModel` appears in Tests only at :41–46 (grep) |
| A-20 | A-INVARIANT | The new `deprecatedTagDirective` info diagnostic breaks no existing test | repo | CONFIRMED | No test asserts the parser-diagnostic count/emptiness on a `<shot>`/`<include>` note (the 3 files containing them were checked; `UniversalPromptTests.swift:294–309` checks only `.promptEmpty`). The compile path drops parser diagnostics anyway (`GlosaCompiler.swift:48`) |
| A-21 | A-DATA | The README documents no directives today | repo | CONFIRMED | `README.md` headings :14–118; no `<shot`/`<include` |
| A-22 | A-CONFIG | `Package.swift` declares no resources | repo | CONFIRMED | `Package.swift:16–30` (no `resources:` on either target); no `schemas/` or `Tests/GlosaCoreTests/Fixtures/` exists |
| A-23 | A-DEP | CryptoKit is available on the package's platforms | toolchain | CONFIRMED | Platforms `.macOS(.v26), .iOS(.v26)` `Package.swift:7–10`; `CryptoKit.framework` present in local MacOSX27.0 and iPhoneOS27.1 SDKs (`ls`); CI is `macos-26` (`tests.yml:23,138`). No Linux target |
| A-24 | A-API | GlosaCore can't find notes in a Fountain document, and the new names don't collide | repo | CONFIRMED | Public API is `parseFountain*(notes:)` + `GlosaInlineNotes.strip/split` (dialogue breath/pause only, `GlosaInlineNotes.swift:129,148`); grep finds no `GlosaFountainNotes`, `GlosaMigration`, `GlosaJSONValue`, `extraAttributes`, `renderDigest` or `serialize` |
| A-25 | A-DATA | § 5 housekeeping: private downstream names appear in `README.md`, `Include.swift`, `Shot.swift`, `GlosaValidator.swift`, `GlosaDiagnostic.swift`, two test files and older CHANGELOG entries | repo | CONFIRMED (list still incomplete) | Hit counts: README 2, CHANGELOG 6, `Include.swift` 1, `GlosaDiagnostic.swift` 2, `GlosaValidator.swift` 4, `Shot.swift` 10, `IncludeShotParserTests.swift` 1, `IncludeShotValidatorTests.swift` 1. Also present, not listed: `AGENTS.md` (8), 16 files under `docs/`, and tracked `graphify-out/graph.{json,html}`. See note 5 |
| A-26 | A-BEHAVIOR | (revised) The parser cannot tell notes from dialogue, so a `{"` prefix test is the only discriminator; `{beat} Fine.` inside an `<Intent>` reaches the dialogue fall-through unchanged | repo | CONFIRMED | `notes:` doc Parser:20–22, :303; a non-tag element inside an open intent goes to `extractInlineNotes` and `sceneDialogueLineCount += 1` (Parser:222–240). No existing test passes the parser an element starting with `{"` (the only `{"` literals in Tests are Codable fixtures: `IncludeShotParserTests.swift:240,263`, `IncludeShotValidatorTests.swift:88`) |
| A-27 | A-BEHAVIOR | 1.0 block detection is substring-based and comes after the scope-tag checks | repo | CONFIRMED | `contains("<shot")` Parser:452; `</SceneContext>`/`</Intent>`/SceneContext/Constraint/Intent checks Parser:84–202 run first. See note 2 |
| A-28 | A-API | `GlosaDiagnostic` carries `line` and `code`; the "line" is the note-array index | repo | CONFIRMED | `GlosaDiagnostic.swift:85,87`; `lineNumber = noteIndex + 1` Parser:81. There is no column field, so position goes in `message` as § 3 says |
| A-29 | A-CONFIG | `make build`/`make test` exist (xcodebuild) | repo | CONFIRMED | `Makefile:17–23` |
| A-30 | A-BEHAVIOR | Downstream renderers and editors each re-implement the fold | external | UNVERIFIABLE | Outside this repo |
| A-31 | A-BEHAVIOR | Fountain notes allow line breaks but not blank lines, and `]]` ends a note | external | UNVERIFIABLE | Fountain spec, plus each caller's extractor |
| A-32 | A-BEHAVIOR | Callers hand a multi-line note to the parser intact, as one `notes` element | external | UNVERIFIABLE | Caller extraction code |
| A-33 | A-API | `GlosaCompiler.compile` calls `parseFountain` and drops parser diagnostics (`GlosaCompiler.swift:48`); the result type can carry them | repo | CONFIRMED | `GlosaCompiler.swift:48` (score only), :51–53 (validator diagnostics only); `CompilationResult.diagnostics` `CompilationResult.swift:102,150,159`. It is the only parse call in the compile path: `compileScript` routes through `compiler.compile` (`GlosaLineAnnotation.swift:351`) and `compileAnnotations` through `compileScript` |
| A-34 | A-API | `Shot`/`Include` carry a `documentIndex` that the schema form omits | repo | CONFIRMED | `Shot.swift:51`, `Include.swift:22`, both non-optional `Int`. `Shot(schemaJSON:)` must therefore invent one; see note 3 |
| A-35 | A-API | A defaults shot is a `Shot` with an empty `prompt`; panel shots have a non-empty one | repo | CONFIRMED | `prompt: String` (non-optional) `Shot.swift:57`; convention `Shot.swift:30–31`; validator skips empty prompt `GlosaValidator.swift:298–299,317–320` |
| A-36 | A-API | The revision's new names (`schemaJSON`, `schemaJSONData`, `effectiveShots`, `notation`, `GlosaJSONValue`) do not collide with existing symbols | repo | CONFIRMED | `grep -rn` over `Sources/` and `Tests/` returns nothing for any of them |

### Blocking findings

None.

## Local Dependency Map

| Dependency | Declared | Resolved | Local checkout | Local HEAD | Status |
|------------|----------|----------|----------------|-----------|--------|
| *(none)* | `dependencies: []` (`Package.swift:14,19`) | — | — | — | — |
| *(system)* CryptoKit | not a package; `import CryptoKit` | Apple SDK (macOS 26 / iOS 26 floor) | — | — | n/a (system framework) |

Exactly one non-derived checkout matches `github.com/intrusive-memory/glosa-av`:
`~/Projects/package-collection/pkg/glosa-av` (`development`, `eed3dc9`). No ambiguity. There
is no `Package.resolved`, which doesn't matter because there are no dependencies.

## What the revision got wrong or still leaves open (non-blocking, for breakdown)

1. **§ 4 contradicts § 1.1.** § 4 (lines 200–201) still says "a prose note starting with
   `{` is reported, not swallowed". Under the revised § 1.1 (lines 72–73), prose starting
   with `{` but not `{"` is **not** a candidate and stays exactly as in 1.0. Rewrite the
   § 4 bullet as "a non-directive element starting with `{"` is reported" plus the
   `{beat} Fine.` regression test, or the parse sortie gets contradictory criteria.
2. **Whitespace after the brace escapes detection.** The rule is "starts with `{"`", so
   `{ "shot": {…}}` (legal JSON, likely from hand-editing or other writers) is not a
   candidate. It then falls through silently: it becomes dialogue inside an open `<Intent>`
   (Parser:222–240) and is otherwise ignored. That is the "silently absent shot" § 3
   exists to prevent. Either widen the test to `{` + optional whitespace + `"` (what the
   second recon suggested; `{beat}` still never matches) or document this case beside the
   dialogue limitation.
3. **Schema-codec gaps (§ 2.8, new).**
   - `Shot(schemaJSON: GlosaJSONValue)` is listed **without** `throws`, but
     `Shot(schemaJSONData:)` throws. Decide what the non-throwing init does with a
     non-object, a missing `prompt`/`src`, or a wrong-typed key: throw, fail (`init?`), or
     default.
   - `documentIndex` is non-optional (A-34), so the schema init needs a stated value (a
     parameter with a default, or `0`). The `parse(serialize(x)) == x` property test also
     has to control `documentIndex`, because the parser assigns the note index.
   - `prompt` is a non-optional `String` and a defaults shot has `""` (A-35). "`nil` keys
     omitted" does not say whether a defaults shot serializes `"prompt": ""` or omits it,
     or what a missing `prompt` decodes to. Pick one, because round-trip and the digest
     both depend on it.
4. **Detection order and the validator's own note scan (carried over, still unstated).**
   The parser's scope checks (`contains("</SceneContext>")`, `contains("</Intent>")`, …,
   Parser:84–202) run before the block checks. A JSON shot whose string value contains
   `</Intent>` or `<shot` would be misrouted unless JSON detection runs first. Separately,
   `GlosaValidator.validate(notes:)` does its **own** substring scan of the raw notes
   (`GlosaValidator.swift:29–30`, `:52`, `:67`), and `compile` runs it (`GlosaCompiler.swift:52`).
   A JSON shot containing `</Intent>` or `<SceneContext` in a value would raise spurious
   structural warnings there too. The validator needs the same `{"` skip. Neither point is
   in the requirements.
5. **Housekeeping list is still incomplete (A-25).** The named files are right, but
   `AGENTS.md` (8 hits), 16 files under `docs/` (`docs/complete/**`, `EXAMPLES.md`,
   `ADDING-A-DIRECTIVE.md`, `REQUIREMENTS.md`, …) and the tracked `graphify-out/graph.json`
   / `graph.html` also contain downstream app names. The "find them with a grep" clause
   would catch them, but the explicit list should say whether `docs/` and `graphify-out/`
   are in scope. The generated graph is otherwise re-dirtied by the next codemap refresh.
6. **Wording in the manifest and CI (carried over).** `Package.swift:16` (`// MARK: - GlosaCore
   (Foundation-only)`) and the `tests.yml` leaf-guard comments say "Foundation-only". Update
   them with the § 2.6 dependency statement. The guard regex itself needs no change (A-18).
7. **Requirements frontmatter.** `type: project`, not `type: requirements`. `breakdown` stamps
   the `type` key per the OKF rule. This is noted only so the change isn't a surprise.

## Unverifiable

| ID | Claim | Why | What would settle it |
|----|-------|-----|----------------------|
| A-30 | Downstream consumers re-implement the fold | External code | Read the consumers' fold code |
| A-31 | Fountain note rules (no blank lines, `]]` closes) | External spec | Fountain spec plus each caller's extractor |
| A-32 | Callers pass multi-line notes as one element | External callers | Inspect each caller's extraction, or make it an explicit entry criterion of the parse sortie |

## Handoff to breakdown

- The `CONFIRMED` facts are safe to use as sortie entry criteria without re-checking.
- The `UNVERIFIABLE` items (A-30 to A-32) become Open Questions or explicit verification
  steps, never silent assumptions.
- Notes 1–3 are decisions for `refine-blockers` (the § 4 wording, the whitespace rule, and
  the schema-init error and default semantics). Note 4 is an implementation constraint for
  the parse and validator sorties. Put the hand-written JSON reader in its own file:
  `GlosaParser.swift` is ~61 KB, and CI fails any Swift file over 100 KB.
- There are no dependency paths to carry: GlosaCore is dependency-free. CryptoKit is a
  system framework.
