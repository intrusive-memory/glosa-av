---
kind: test-cleanup-report
state: completed
mission: cleaving-breath-01
updated: 2026-06-09
---

# Test Cleanup Report — OPERATION CLEAVING BREATH

Mission branch: `mission/cleaving-breath/01`
Starting commit: `1672036493f163794a16e2bd2f2030df9bea8c67`
Cleanup date: 2026-06-09

---

## Removed

*None.* All 24 mission test files are CI-safe. No tests were deleted.

| file:test_name | reason | confidence |
|---|---|---|
| — | — | — |

---

## Flagged for Review

Files over 200 lines (borderline — long but not inherently flaky; no action required):

| file | lines | concern | recommended action |
|---|---|---|---|
| `Tests/GlosaAnnotationTests/BreathBridgeTests.swift` | 211 | Slightly over 200-line threshold | No action needed; all tests are well-structured and hermetic |
| `Tests/GlosaAnnotationTests/BreathSerializerFDXTests.swift` | 337 | Over 200 lines | No action needed; tests are hermetic round-trips with inline fixtures |
| `Tests/GlosaAnnotationTests/BreathSerializerFountainTests.swift` | 379 | Over 200 lines | No action needed; tests are hermetic round-trips with inline fixtures |
| `Tests/GlosaAnnotationTests/PauseSerializerFountainTests.swift` | 206 | Slightly over 200-line threshold | No action needed; tests are hermetic |
| `Tests/GlosaCoreTests/BreathCompilerTests.swift` | 216 | Over 200 lines | No action needed; uses hand-built `GlosaScore` fixtures |
| `Tests/GlosaCoreTests/BreathParserFDXTests.swift` | 251 | Over 200 lines | No action needed; uses inline XML fixtures |
| `Tests/GlosaCoreTests/BreathParserFountainTests.swift` | 291 | Over 200 lines | No action needed; uses inline Fountain fixtures |
| `Tests/GlosaCoreTests/BreathValidatorTests.swift` | 302 | Over 200 lines | No action needed; entirely hermetic |
| `Tests/GlosaCoreTests/PauseCompilerTests.swift` | 295 | Over 200 lines | No action needed; uses inline notes fixtures |
| `Tests/GlosaCoreTests/PauseParserFDXTests.swift` | 266 | Over 200 lines | No action needed; uses inline XML fixtures |
| `Tests/GlosaCoreTests/PauseParserFountainTests.swift` | 298 | Over 200 lines | No action needed; uses inline Fountain fixtures |
| `Tests/GlosaCoreTests/PauseTests.swift` | 217 | Over 200 lines | No action needed; pure Codable round-trip tests |
| `Tests/GlosaCoreTests/PauseValidatorTests.swift` | 239 | Over 200 lines | No action needed; hermetic parser diagnostic tests |
| `Tests/GlosaDirectorTests/BreathSchemaTests.swift` | 265 | Over 200 lines | No action needed; pure Codable round-trip tests |
| `Tests/GlosaDirectorTests/PauseSchemaTests.swift` | 233 | Over 200 lines | No action needed; pure Codable round-trip tests |

---

## Rationale for 0 Deletions

Every test in scope uses the hermetic inline-fixture pattern: Fountain snippets
and FDX XML strings are embedded directly in the test source, and all character
offsets are computed by hand against those fixed strings. The full checklist:

1. **Hardcoded local paths** — none found (`/Users/`, `~/`, etc.).
2. **Unmocked network calls** — none; no `URLSession`, `URLRequest`, or
   external host references.
3. **Local-only service dependencies** — none.
4. **Ungated env-var requirements** — none.
5. **`~/Library` / `~/.config` reads** — none.
6. **Sleep-based timing** — none (`Thread.sleep`, `Task.sleep`, `asyncAfter`
   not present).
7. **`Date()`/`Date.now()` assertions without frozen clock** — none.
8. **Unordered collection iteration** — `Dictionary.keys` accesses are always
   followed by `.sorted()` before assertion; `Set` not used for ordered claims.
9. **Unseeded randomness** — none (`Int.random`, `arc4random` not present).
10. **Pre-existing skip/ignore markers** — none.
11. **Empty test bodies / no-assertion tests** — none.
12. **Exact duplicates** — none.

---

## Build Verification

Skipped — `make test` invokes `xcodebuild test`, which is not run during
test-cleanup per the mission constraint "Do NOT run `swift test` or
`swift build`." The Makefile `test:` target is present at
`/Users/stovak/Projects/glosa-av/Makefile`.
