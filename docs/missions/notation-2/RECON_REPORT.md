---
type: recon-report
state: current
requirements_file: REQUIREMENTS.md
requirements_sha256: b86bc6bbd74f41dd37c05b5d15be07079a17575f6a2c70c4223a06e3b9051cc7
project_head: 518ff02171720f60c8718ceb74086a62e500229f
search_root: ~/Projects
generated: 2026-10-20
verdict: BLOCKED
---

# RECON_REPORT.md — glosa-av 0.9.0 (GLOSA notation 2.0)

## Terminology

> **Mission** — A definable, testable scope of work.
> **Sortie** — An atomic, testable unit of work executed by a single agent in one dispatch.
> **Work Unit** — A grouping of sorties.

## Verdict

**BLOCKED** — 25 assumptions checked, 18 confirmed, 4 blocking (2 substantive, 2 cosmetic), 3 unverifiable.

The repo has no dependencies, so drift can't happen here. Every verdict was checked
in the single authoritative checkout at `518ff02` (`development`). Recon ran single-hub
with no spokes, read-only, and every verdict below carries a citation.

## Assumption Findings

Paths are relative to the repo root. "Parser" = `Sources/GlosaCore/GlosaParser.swift`.

| ID | Kind | Claim | Locus | Verdict | Evidence |
|----|------|-------|-------|---------|----------|
| A-01 | A-API | `extractAttribute` at `GlosaParser.swift:509`: regex `name="…"` then `name='…'`, no escape | repo | **STALE** (line only) | Behaviour matches at Parser:519–546 (`func` at :521). Line 509 is inside `boolAttribute` |
| A-02 | A-API | `parseShotTag` at `GlosaParser.swift:451` reads a fixed attribute list | repo | CONFIRMED | Parser:451–477 |
| A-03 | A-DATA | 1.0 `ref` is a comma-separated string | repo | CONFIRMED | Parser:474, `refList` Parser:500–505. The model type is already `[String]?` (`Shot.swift:120`) |
| A-04 | A-API | `Shot` keys = prompt, caption, style, model, aspect, width, height, steps, guidance, seed, negative, lora, loraScale, ref, character, output, preview, telemetry (+ documentIndex) | repo | CONFIRMED | `Shot.swift:51–125` (18 keys + `documentIndex`, an exact match for the § 2.7 order list) |
| A-05 | A-API | `Include` has `src`, `gain` (number), `mode` accepting `"bed"` | repo | CONFIRMED | `Include.swift:25,30,34`; `IncludeMode.bed` `Include.swift:73`. Also has `fadeIn`, `fadeOut`, `prompt` (:37,:40,:46) |
| A-06 | A-API | `ref`/`character` on `Shot` at `518ff02` on `development` | repo | CONFIRMED | `git log` HEAD = `518ff02 feat(shot): add ref and character`; `Shot.swift:120,125` |
| A-07 | A-API | `parseFountain(notes:)` at :25, `parseFountainWithDiagnostics(notes:)` at :47 | repo | CONFIRMED | Parser:25, Parser:47 |
| A-08 | A-API | `GlosaVersion.version` exists in `GlosaVersion.swift` | repo | CONFIRMED | `GlosaVersion.swift:3` (`"0.8.1-dev"`; no `notation` yet) |
| A-09 | A-DATA | The `Shot.swift` header says GlosaCore stays parse-and-carry and does not compute effective shots | repo | CONFIRMED | `Shot.swift:30–33` |
| A-10 | A-BEHAVIOR | Promptless shots are defaults; later keys replace; the shot's own keys win; caption is not inherited | repo | CONFIRMED | `Shot.swift:17–28`, `:37–46` |
| A-11 | A-API | `GlosaScore.shots` holds every shot in document order | repo | CONFIRMED | `GlosaScore.swift:74–77`; parser appends in note order Parser:213–214 |
| A-12 | A-API | `GlosaDiagnostic.Code` exists, so new cases can be added | repo | CONFIRMED | `GlosaDiagnostic.swift:20–72` |
| A-13 | A-API | A diagnostic **error** severity exists (§ 3 table: `invalidBlockDirectiveJSON` = error) | repo | **REFUTED** | `GlosaDiagnostic.swift:9–14`: `Severity` has only `warning` and `info` |
| A-14 | A-API | `GlosaValidator.knownShotModels` warns `shotUnknownModel` on unlisted models | repo | CONFIRMED | `GlosaValidator.swift:325–335`; list at :357 (`private static`, `klein4b`, `klein9b`, `pixart-sigma`) |
| A-15 | A-BEHAVIOR | FDX `<glosa:shot …/>` uses XML attributes; `ref` is comma-separated there | repo | CONFIRMED | Parser:1340–1362 (`GlosaParser.refList(attributes["ref"])`) |
| A-16 | A-BEHAVIOR | Inline `[[<breath/>]]` mid-line and paired `<Intent>`…`</Intent>` exist and are separate from block parsing | repo | CONFIRMED | `GlosaInlineNotes.swift:24–30`; `parseIntentTag` Parser:398; block events Parser:205–214 |
| A-17 | A-API | `Shot`/`Include` are Codable + Equatable; legacy-JSON decode is already tested | repo | CONFIRMED | `Shot.swift:47`, `Include.swift:15`; `IncludeShotParserTests.swift:240,263` |
| A-18 | A-INVARIANT | GlosaCore is Foundation-only with no dependencies | repo | CONFIRMED | `Package.swift` `dependencies: []`; the only import in `Sources/` is `import Foundation` (5 files) |
| A-19 | A-INVARIANT | The § 3 validator change leaves "existing suites green unmodified" (§ 4, Acceptance 1) | repo | **REFUTED** | `Tests/GlosaCoreTests/IncludeShotValidatorTests.swift:41–47` expects `.shotUnknownModel` for `model: "sd-xl"` |
| A-20 | A-INVARIANT | Adding a `deprecatedTagDirective` info diagnostic to 1.0 shot/include notes breaks no existing test | repo | CONFIRMED | Only 3 test files contain `<shot`/`<include` (grep). None of them asserts `diagnostics.isEmpty`/`.count` on a parse result (`IncludeShotParserTests.swift`, `UniversalPromptTests.swift:292–309` check only `.promptEmpty`) |
| A-21 | A-CONFIG | `make build` / `make test` exist (xcodebuild) | repo | CONFIRMED | `Makefile:17–23` |
| A-22 | A-DATA | README has a "notation section" to rewrite | repo | **REFUTED** | `README.md` sections at :14–118: no notation section, and no mention of `<shot>`/`<include>` (grep). The closest is "GLOSA Annotation Layers" :44 |
| A-23 | A-BEHAVIOR | Renderers and editors downstream each re-implement the fold | external | UNVERIFIABLE | Outside this repo |
| A-24 | A-BEHAVIOR | Fountain notes allow line breaks but not blank lines, and `]]` ends a note | external | UNVERIFIABLE | Fountain spec, plus each caller's note extractor |
| A-25 | A-BEHAVIOR | Callers hand the parser multi-line note text intact as one `notes` element | external | UNVERIFIABLE | GlosaCore has no Fountain-document → notes extractor. Public API is `parseFountain*(notes:)`, `GlosaInlineNotes.strip/split` (dialogue only). Callers own the extraction |

### Blocking findings

#### A-13 — REFUTED (substantive)
**Claim**: § 3 table, "`invalidBlockDirectiveJSON` | error".
**Source**: REQUIREMENTS.md § 3, lines 133–135.
**Found**: `GlosaDiagnostic.Severity` = `{ warning, info }` (`GlosaDiagnostic.swift:9–14`). § 3 says only that Code cases are additive. Nothing in the requirements says to add a Severity case.
**Impact**: A sortie can't emit `.error`. Adding a case to a public non-frozen enum breaks exhaustive `switch` statements in downstream consumers. That is acceptable at 0.9.0, but it must be stated deliberately.
**Options**:
1. Amend § 3 to make `Severity.error` an explicit deliverable, and list it as a source-breaking change in the CHANGELOG *(recommended: an unparseable shot shouldn't be just a warning)*
2. Emit `invalidBlockDirectiveJSON` as `.warning`, which needs no API change

#### A-19 — REFUTED (substantive)
**Claim**: "existing suites stay green unmodified" (§ 4 line 146–147; Acceptance 1, line 180), together with § 3: "warn only on an empty `model` string".
**Found**: `IncludeShotValidatorTests.swift:41–47` (`shotUnknownModel`) asserts that `"sd-xl"` produces `.shotUnknownModel`. § 3 removes that warning, so the test must change. The two requirements contradict each other.
**Options**:
1. Amend Acceptance 1 / § 4 to say "unchanged except the `shotUnknownModel` test, rewritten to assert the empty-model case" *(recommended)*
2. Keep a closed model list (contradicts § 3 and Acceptance 6)

#### A-01 — STALE (cosmetic)
**Claim**: `extractAttribute` at `GlosaParser.swift:509`. **Actual**: `GlosaParser.swift:521`, and its behaviour matches the claim.
**Options**: 1. Fix the line reference to `:521` *(recommended)*. 2. Ignore it, since a sortie greps by name.

#### A-22 — REFUTED (cosmetic)
**Claim**: § 5 "README: the notation section shows the 2.0 block form first…". **Actual**: the README has no notation section and doesn't document `<shot>`/`<include>` at all.
**Options**: 1. Reword § 5 as "add a notation section to the README" (a new deliverable) *(recommended)*. 2. Fold it into "GLOSA Annotation Layers" (`README.md:44`).

## Local Dependency Map

| Dependency | Declared | Resolved | Local checkout | Local HEAD | Status |
|------------|----------|----------|----------------|-----------|--------|
| *(none)* | `dependencies: []` (`Package.swift`) | — | — | — | — |

The project itself has one non-derived checkout matching `github.com/intrusive-memory/glosa-av`: `~/Projects/package-collection/pkg/glosa-av` (`development`, `518ff02`). No ambiguity. `Package.resolved` is gitignored and irrelevant here (there are no deps).

## Other things the requirements get wrong or leave open (non-blocking, for breakdown)

1. **The escape rule is garbled.** Line 74 says "`]]` is written `]]` and `[[` is written `[[`", so the text names no escape. The intent is presumably a JSON `]]` / `[[`-style escape. "The parser needs nothing special" is true only if the serializer always escapes. A raw `]]` in a hand-written JSON string still ends the Fountain note before GlosaCore sees it. Clarify this before breakdown.
2. **SHA-256 isn't in Foundation.** § 2.6 says "Foundation only". The options are CryptoKit (an Apple system framework, not a third-party dep, available on macOS/iOS 26) or a hand-rolled SHA-256. Decide which.
3. **`seed` is `UInt64`** (`Shot.swift:92`). JCS formats numbers as IEEE-754 doubles (ECMAScript), so seeds above 2^53 lose precision in the canonical form and in the digest, and could collide. JSON parsing of large seeds has the same problem. Decide on a string encoding for seed or a documented range limit.
4. **`output` not inherited is a semantics change.** The current docs exempt only `caption` (`Shot.swift:37–46`, CHANGELOG:29). § 2.4 also exempts `output`. Call that out in the CHANGELOG.
5. **The `Include.serialize()` key order is unspecified.** § 2.7 fixes the order only for `shot`. `Include` has `src, gain, mode, fadeIn, fadeOut, prompt` (`Include.swift:25–46`).
6. **Acceptance 4 needs a document-level note extractor that GlosaCore lacks** (A-25). The migration test has to supply its own synthetic splitter, or the mission must add one.
7. **Package resources.** `Package.swift` declares no `resources:` for the `GlosaCore` or test targets. Shipping the schemas and the `Fixtures/digest/` vectors requires manifest edits (a deliverable, flagged so it isn't missed).
8. **Today a `{`-leading note inside an `<Intent>` is dialogue** (Parser:222 onward, the non-tag fallthrough). Under the § 1.1 detection rule it becomes a diagnostic with no event. That changes 1.0 behaviour for any prose note starting with `{`. No existing test covers this (grep of `Tests/` for `{`-leading notes finds only JSON-decode literals).
9. **Existing doc comments in this public repo name private downstream apps** (`Include.swift:13`, plus several CHANGELOG entries). The comment amendment in § 2.4 is a chance to make them neutral.

## Unverifiable

| ID | Claim | Why | What would settle it |
|----|-------|-----|----------------------|
| A-23 | Downstream consumers re-implement the fold | External code | Read the consumers' fold code |
| A-24 | Fountain note rules (no blank lines, `]]` closes) | External spec | Fountain spec + each caller's extractor |
| A-25 | Callers pass multi-line notes as one element | External callers | Inspect each caller's note extraction; otherwise make it an explicit entry criterion |

## Handoff to breakdown

- The `CONFIRMED` facts are safe to use as sortie entry criteria.
- The `UNVERIFIABLE` items (A-23 to A-25) become Open Questions or explicit verification steps, never silent assumptions.
- No dependency paths to carry: GlosaCore is dependency-free.
- Re-run recon after amending A-13, A-19, A-01 and A-22 (or run with `--accept-risk` to carry them as blocking Open Questions).
