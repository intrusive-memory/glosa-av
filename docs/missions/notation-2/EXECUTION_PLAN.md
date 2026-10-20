---
type: execution-plan
feature_name: OPERATION JASON ARGONAUT
starting_point_commit: 7d0d8c138198c72f39e3a0f71c6e208e6cbedc63
mission_branch: mission/jason-argonaut/01
iteration: 1
---

# EXECUTION_PLAN.md — glosa-av 0.9.0 (GLOSA notation 2.0)

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

## Source

- Requirements: `docs/missions/notation-2/REQUIREMENTS.md` (cited below as "REQ § n")
- Recon: `docs/missions/notation-2/RECON_REPORT.md` — CLEAR (fourth pass). Its `CONFIRMED`
  citations (A-01 … A-36) are ground truth and are not re-verified by sorties.

## Mission-wide rules (every sortie)

- Build and test only with `make build` / `make test` (xcodebuild). Never `swift build` / `swift test`.
- Commit at the end of the sortie on the mission branch. Commit messages end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push, tag, or force-push.
- PUBLIC repository: never add the names of private downstream apps to code, tests,
  fixtures, docs, or commit messages. Fixtures are synthetic text only. The supervisor
  supplies the name pattern in the dispatch prompt; it is deliberately not written here.
- Do not change `GlosaVersion.version` (it stays the `-dev` marker; the release is a separate step).
- New code goes in new files where the plan says so. `GlosaParser.swift` is ~61 KB and CI
  fails any Swift file over 100 KB.
- Pre-existing tests stay green **unmodified**, except the one named in Sortie 4 (REQ Acceptance 1).

## Decisions taken at breakdown (non-blocking; recorded so sorties don't re-decide)

- **D-1 Schema files location.** `Sources/GlosaCore/schemas/{shot,include}.schema.json`, declared as
  `resources: [.copy("schemas")]`. SwiftPM resources must live inside the target directory.
- **D-2 `GlosaJSONValue` shape.** `public enum GlosaJSONValue: Sendable, Equatable, Hashable, Codable`
  with cases `string(String)`, `number(Double)`, `bool(Bool)`, `null`, `array([GlosaJSONValue])`,
  `object([GlosaJSONMember])`, where `public struct GlosaJSONMember { key: String; value: GlosaJSONValue }`
  keeps member order. `extraAttributes: [GlosaJSONMember]`.
- **D-3 Wrong-typed known key in a 2.0 note** (valid JSON, schema mismatch, e.g. `"width": "wide"`)
  → `invalidBlockDirectiveJSON` (error), message naming the key; the note yields no event.
  Same treatment for a missing `src` on `include`. Rationale: REQ § 3 makes a silently absent shot an error.
- **D-4 Unrecognized `include.mode` string** is handled as the 1.0 parser handles it
  (`IncludeMode.init(rawValue:)` → `nil`, `GlosaParser.swift:432`), not as a type error.
- **D-5 Extra-attribute numbers** serialize with ECMAScript number formatting (the JCS rule);
  only the five named non-integer known keys get the forced decimal (REQ § 2.7).
- **D-6 Standalone note boundaries.** Start and end of the document count as blank-line boundaries
  for `GlosaFountainNotes.standaloneNotes`.
- **D-7 Compile path.** Parser diagnostics are appended to `CompilationResult.diagnostics` without
  duplicating a diagnostic the validator already reports for the same line and code.

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| glosa-av | `.` (repo root) | 11 | 0 | none |

### Sortie 1: JSON foundation — order-preserving reader and JCS writer

**Priority**: 31.5 — every later code sortie depends on it (depth 10), foundation, custom algorithm (JCS numbers).

**Entry criteria**:
- [ ] First sortie — mission branch checked out, `make build` succeeds at the starting commit.

**Tasks**:
1. Create `Sources/GlosaCore/GlosaJSON.swift`: `GlosaJSONValue` and `GlosaJSONMember` per D-2.
   Codable via a single-value container (objects encode as an array of `{key,value}` so order survives `JSONEncoder`).
2. In the same file (or `GlosaJSONReader.swift`), a hand-written RFC 8259 reader
   `GlosaJSONReader.parse(_ text: String) throws(GlosaJSONError) -> GlosaJSONValue` that keeps
   member order and reports errors as `GlosaJSONError { message, line, column }` (1-based, within the input).
   Handles `\uXXXX` escapes including surrogate pairs (so `]\u005d` decodes to `]]`).
3. Create `Sources/GlosaCore/GlosaJCS.swift`: `GlosaJCS.canonicalString(_ value: GlosaJSONValue) -> String`
   per RFC 8785 — members sorted by UTF-16 code units, ECMAScript `Number.prototype.toString`
   formatting for doubles, minimal string escaping per RFC 8785 § 3.2.2.2.
4. Tests in `Tests/GlosaCoreTests/GlosaJSONTests.swift`: reader (all value kinds, order preserved,
   nested, escapes, surrogate pairs, error line/column for at least 3 malformed inputs) and JCS
   (key sort incl. non-ASCII, numbers `1.0`→`1`, `1e21`, `1e-7`, `-0`→`0`, `0.1`, `123456789012345680000`).

**Exit criteria**:
- [ ] `make test` passes, including every pre-existing test.
- [ ] `grep -c "@Test" Tests/GlosaCoreTests/GlosaJSONTests.swift` ≥ 15.
- [ ] `grep -rn "JSONSerialization\|JSONDecoder" Sources/GlosaCore/GlosaJSON*.swift Sources/GlosaCore/GlosaJCS.swift` returns nothing.
- [ ] `git status --porcelain` is empty after the sortie's commit.

### Sortie 2: Model — notation constant, extra attributes, schema-form codec

**Priority**: 29.5 — depth 9, foundation for parse/serialize/digest.

**Entry criteria**:
- [ ] Sortie 1 committed (`GlosaJSONValue`, `GlosaJSONReader`, `GlosaJCS` exist).

**Tasks**:
1. `GlosaVersion.notation = "2.0"` in `GlosaVersion.swift` (REQ § 2.1). Leave `version` unchanged.
2. `Shot.extraAttributes` and `Include.extraAttributes: [GlosaJSONMember]`, default `[]`, added to
   memberwise inits with a default. Hand-written `init(from:)` so legacy JSON lacking the field decodes to `[]` (REQ § 2.3).
3. Create `Sources/GlosaCore/Shot+Schema.swift` and `Include+Schema.swift`: `schemaJSON()`, `schemaJSONData()`,
   `init(schemaJSON:documentIndex:) throws`, `init(schemaJSONData:documentIndex:) throws` per REQ § 2.8
   (canonical key order REQ § 2.7; `prompt` omitted when empty, missing → `""`; `seed` accepted as integer or
   decimal string, emitted as string above 2^53 − 1; unknown keys at top level; throw on non-object,
   wrong-typed known key, missing `include.src`).
4. Tests `Tests/GlosaCoreTests/ShotSchemaCodecTests.swift`: legacy-JSON decode (no `extraAttributes` field → `[]`),
   schema round-trip for Shot and Include, defaults shot (`prompt` absent ↔ `""`), seed > 2^53 round-trip
   (integer and string input), unknown keys at top level preserved in order, and each throw case.

**Exit criteria**:
- [ ] `make test` passes; all pre-existing tests pass unmodified.
- [ ] `grep -n 'notation = "2.0"' Sources/GlosaCore/GlosaVersion.swift` matches; `git diff <starting_commit> -- Sources/GlosaCore/GlosaVersion.swift` shows the `version` line unchanged.
- [ ] `ShotSchemaCodecTests.swift` contains ≥ 10 `@Test` functions (`grep -c "@Test"`).
- [ ] `git status --porcelain` is empty after the sortie's commit.

### Sortie 3: Shipped JSON Schemas as package resources

**Priority**: 26 — depth 8 in the chain; low risk.

**Entry criteria**:
- [ ] Sortie 2 committed (the canonical key list and types are fixed in `Shot+Schema.swift` / `Include+Schema.swift`).

**Tasks**:
1. Create `Sources/GlosaCore/schemas/shot.schema.json` and `include.schema.json` (JSON Schema 2020-12,
   `$schema` 2020-12, `$id` containing `2.0`, every known key with its type — `ref` an array of strings, `seed`
   integer-or-decimal-string — `additionalProperties: true`, `required: ["src"]` for include, none for shot).
2. Add `resources: [.copy("schemas")]` to the `GlosaCore` target (D-1) and change the `Package.swift:16`
   comment to "Foundation and CryptoKit".
3. Test `Tests/GlosaCoreTests/SchemaResourceTests.swift`: both files load via `Bundle.module`, parse with
   `GlosaJSONReader`, `$id` contains `2.0`, and the shot schema's `properties` keys equal the canonical key list
   used by `Shot.schemaJSON()` (same for include).

**Exit criteria**:
- [ ] `make test` passes.
- [ ] `grep -n 'resources: \[.copy("schemas")\]' Package.swift` matches.
- [ ] `git status --porcelain` is empty after the sortie's commit.

### Sortie 4: Diagnostics and validator model rule

**Priority**: 22 — depth 7; small, but the parser needs the new codes.

**Entry criteria**:
- [ ] Sortie 3 committed.

**Tasks**:
1. Add `Severity.error` (`GlosaDiagnostic.swift:9–14`).
2. Add codes `invalidBlockDirectiveJSON`, `unknownBlockDirective`, `deprecatedTagDirective` (REQ § 3), each with doc comment.
3. Replace `GlosaValidator.knownShotModels` with: warn `shotUnknownModel` only when `model` is the empty string.
   Remove the closed list.
4. Rewrite only `IncludeShotValidatorTests.swift:41–47` (`sd-xl`) for the new rule, and add a test that
   `"google-nano-banana-2.1"` yields no `shotUnknownModel` (REQ Acceptance 6) and `""` yields one.

**Exit criteria**:
- [ ] `make test` passes.
- [ ] `git diff <starting_commit> -- Tests/` touches no pre-existing test other than the `sd-xl` case.
- [ ] `grep -n "knownShotModels" Sources/` returns nothing.
- [ ] `git status --porcelain` is empty after the sortie's commit.

### Sortie 5: Parser and validator read notation 2.0; compile path surfaces parser diagnostics

**Priority**: 23.5 — depth 6, highest regression risk (note loop ordering).

**Entry criteria**:
- [ ] Sorties 1–4 committed.
- [ ] A-32 (callers pass a multi-line note as one element) is unverifiable here; the parser must accept
  a candidate containing newlines, and this sortie does not depend on caller behaviour beyond that.

**Tasks**:
1. In `GlosaParser.parseFountainWithDiagnostics`, before every existing substring check in the note loop,
   detect candidates (trimmed text matches `^\{\s*"`), decode via Sortie 2's schema codec into `Shot`/`Include`
   with the note's `documentIndex`, and emit `invalidBlockDirectiveJSON` (with reader line/column in the message),
   `unknownBlockDirective`, or D-3 errors; a candidate never falls through to tag or dialogue handling.
2. Emit `deprecatedTagDirective` (info) for each 1.0 `<shot/>` / `<include/>` read, naming the 2.0 replacement.
3. In `GlosaValidator.validate(notes:)` apply the same candidate skip so JSON values containing `</Intent>`,
   `<SceneContext` etc. raise no structural warnings.
4. `GlosaCompiler.compile` uses `parseFountainWithDiagnostics` and appends parser diagnostics per D-7.
5. Tests `Tests/GlosaCoreTests/NotationTwoParserTests.swift`: the REQ § 1.1 example (Acceptance 2), every key/type,
   `ref` array, unknown keys with JSON types, multi-line note, escaped `]]`/`[[`, invalid JSON with position,
   wrong shapes, `{ "shot": …}` detected, JSON value containing `</Intent>` (parser and validator), deprecated
   info on 1.0 tags, compile-path surfacing of an invalid JSON shot, and the `{beat} Fine.` regression inside an
   `<Intent>` span with line indices and breath/pause offsets unchanged.

**Exit criteria**:
- [ ] `make test` passes; all pre-existing tests pass unmodified.
- [ ] The new suite contains a test named for Acceptance 2 asserting `ref == ["KEEPER", "lighthouse-interior.png"]` and `gain == -12.0`.
- [ ] `wc -c Sources/GlosaCore/GlosaParser.swift` < 100000.
- [ ] `git status --porcelain` is empty after the sortie's commit.

### Sortie 6: Canonical note serialization

**Priority**: 19 — depth 5; migration depends on it.

**Entry criteria**:
- [ ] Sortie 5 committed.

**Tasks**:
1. `Shot.serialize()` and `Include.serialize()` in `Sources/GlosaCore/GlosaSerialize.swift`, per REQ § 2.7
   (wrapper `[[ {"shot": {` … `}} ]]`, one key per line, two-space indent, canonical order then extras in read order,
   forced decimal on the five named keys, arrays on one line, `]]`/`[[` escaped, seed rule from REQ § 2.6, D-5).
2. Tests `Tests/GlosaCoreTests/SerializeTests.swift`: Acceptance 3 byte-for-byte; property test
   `parse(serialize(x)) == x` over ≥ 200 generated shots covering every key, extras, and seeds above 2^53
   (seeded generator, fixed seed; `documentIndex` controlled); `serialize(parse(n)) == n` for ≥ 5 canonical notes;
   key order; decimal formatting; escapes.

**Exit criteria**:
- [ ] `make test` passes.
- [ ] A test named for Acceptance 3 exists and passes.
- [ ] `git status --porcelain` is empty after the sortie's commit.

### Sortie 7: Fold and render digest

**Priority**: 15 — depth 4; digest is frozen for notation 2.x, so golden vectors must be right.

**Entry criteria**:
- [ ] Sortie 6 committed.

**Tasks**:
1. `Shot.effective(given:)` and `GlosaScore.effectiveShots` in `Sources/GlosaCore/Shot+Effective.swift` (REQ § 2.4–2.5):
   per-key replacement in document order, own keys win, `caption`/`output` never inherited, extras fold per key.
2. Replace the `Shot.swift` charter text ("parse-and-carry … does not compute effective shots") with a description of the fold.
3. `Shot.renderDigest` in `Sources/GlosaCore/Shot+Digest.swift`: SHA-256 (CryptoKit) of JCS of the schema object minus
   `caption`, `output`, `preview`, `telemetry`; `seed` as decimal string; lowercase hex.
4. Golden vectors: `Tests/GlosaCoreTests/Fixtures/digest/*.json` (input shot JSON + expected hex, ≥ 6 vectors, synthetic),
   test target `resources: [.copy("Fixtures")]`. Expected hashes computed independently of the Swift code
   (e.g. a Python JCS + `hashlib` script run once; script not committed) and recorded.
5. Tests `FoldDigestTests.swift`: fold rules; Acceptance 5 (caption/output don't change the digest; prompt, style,
   `ref` order, an unknown key do); source key order irrelevant; JCS number edge cases.

**Exit criteria**:
- [ ] `make test` passes; golden-vector test loads files via `Bundle.module`.
- [ ] `grep -n "does not compute effective shots" Sources/GlosaCore/Shot.swift` returns nothing.
- [ ] `grep -n "import CryptoKit" Sources/GlosaCore/Shot+Digest.swift` matches.
- [ ] `git status --porcelain` is empty after the sortie's commit.

### Sortie 8: Standalone notes and migration

**Priority**: 12 — depth 3.

**Entry criteria**:
- [ ] Sortie 7 committed.

**Tasks**:
1. `GlosaFountainNotes.standaloneNotes(in:)` in `Sources/GlosaCore/GlosaFountainNotes.swift` (REQ § 2.9, D-6).
2. `GlosaMigration.migrateBlockDirectives(in:)` in `Sources/GlosaCore/GlosaMigration.swift` (REQ § 2.10): rewrite
   standalone 1.0 `<shot/>`/`<include/>` notes with `serialize()`; count non-standalone ones in `skipped`; every other byte identical.
3. Tests `MigrationTests.swift` with a synthetic mixed document: only block directives migrate, rest byte-identical,
   idempotent (second run migrates 0), re-parse yields equal `Shot`/`Include` values ignoring `documentIndex` (Acceptance 4),
   inline 1.0 block directive counted in `skipped`.

**Exit criteria**:
- [ ] `make test` passes.
- [ ] A test named for Acceptance 4 exists and passes.
- [ ] `git status --porcelain` is empty after the sortie's commit.

### Sortie 9: README, CHANGELOG and dependency wording

**Priority**: 3 — documentation; no downstream code depends on it.

**Entry criteria**:
- [ ] Sortie 8 committed.

**Tasks**:
1. README: add a notation section — 2.0 block form first, 1.0 tag form as deprecated, the `{"` dialogue limitation,
   links to `Sources/GlosaCore/schemas/shot.schema.json` and `include.schema.json`, the fold and the digest.
2. CHANGELOG: an `Unreleased` → **Notation 2.0** section: incompatibility for 0.8.x readers, `Severity.error`
   source break, `output` no longer inherited, validator model rule, CryptoKit dependency statement.
3. Replace "Foundation-only"/"Foundation only" dependency statements with "Foundation and CryptoKit" in
   `AGENTS.md`, README, `CLAUDE.md`/`GEMINI.md` if present, and the `.github/workflows/tests.yml` comments and
   echo messages (`tests.yml:45,62,114`). Leave the guard regex unchanged. Update the AGENTS.md `<shot/>` entry
   (directive 7) to describe the 2.0 JSON form, the fold now in GlosaCore, and the digest.

**Exit criteria**:
- [ ] `make test` passes.
- [ ] `grep -n "Notation 2.0" CHANGELOG.md` and `grep -n "shot.schema.json" README.md` match.
- [ ] `grep -rn "Foundation-only\|Foundation only" README.md AGENTS.md .github/ Package.swift` returns nothing.
- [ ] `git status --porcelain` is empty after the sortie's commit.

### Sortie 10: Private-name scrub — code, tests, root docs

**Priority**: 3 — public-repo rule.

**Entry criteria**:
- [ ] Sortie 9 committed.
- [ ] The dispatch prompt supplies the private-name pattern (`$PRIVATE_RE`); it is not written in the repo.

**Tasks**:
1. Reword every `$PRIVATE_RE` match in `Sources/`, `Tests/`, `README.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`
   and `CHANGELOG.md` generically ("a downstream renderer", "the storyboard CLI", "a downstream audio orchestrator").
   Test fixture strings that use a private name become synthetic names; assertions change only in that string.

**Exit criteria**:
- [ ] `grep -rliE "$PRIVATE_RE" Sources Tests README.md AGENTS.md CLAUDE.md GEMINI.md CHANGELOG.md` returns nothing.
- [ ] `make test` passes.
- [ ] `git status --porcelain` is empty after the sortie's commit.

### Sortie 11: Private-name scrub — `docs/` and codemap regeneration

**Priority**: 2 — last; regenerates a derived artifact from the final tree.

**Entry criteria**:
- [ ] Sortie 10 committed.

**Tasks**:
1. Reword every `$PRIVATE_RE` match under `docs/` (archived mission docs included) generically.
2. Regenerate `graphify-out/` with `graphify . --backend claude-cli` (the `/codemap` procedure), committing only the
   portable artifacts that `.gitignore` allows.

**Exit criteria**:
- [ ] `grep -rliE "$PRIVATE_RE" . --exclude-dir=.git --exclude-dir=build --exclude-dir=.build` returns nothing.
- [ ] `git status --porcelain` is empty after the sortie's commit.

## Parallelism Structure

**Critical Path**: Sortie 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 (length: 11 sorties)

**Parallel Execution Groups**: one sequential group. Every sortie runs `make test` — sub-agents may not build,
and two concurrent xcodebuild runs against the same scheme share DerivedData — and Sorties 2, 5, 6, 7, 10
all edit or extend `Shot.swift`'s type in one working tree. Sortie 4 depends only on Sortie 1 in principle,
but it is ~20 turns and parallelising it would interleave commits on one branch for no real saving.

**Agent Constraints**:
- **Supervising agent**: dispatches one sortie agent at a time; each sortie agent builds and tests (one build at a time).
- **Sub-agents**: verifier agents for `[judgment]` criteria only (none are defined in this plan).

## Open Questions

_No blocking open questions identified during breakdown._

## Summary

| Metric | Value |
|--------|-------|
| Work units | 1 |
| Total sorties | 11 |
| Open questions | 0 |
| Dependencies mapped | 0 (CryptoKit is a system framework) |
| Dependency structure | sequential (critical path 11) |
