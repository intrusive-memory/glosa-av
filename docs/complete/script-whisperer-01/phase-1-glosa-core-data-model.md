---
state: completed
updated: 2026-05-13
mission: script-whisperer-01
phase: 1
title: GlosaCore — Data Model & Parser
---

# Phase 1 — GlosaCore: Data Model & Parser

**State:** complete. Shipped as part of the `script-whisperer-01` mission (12 sorties, 184 tests passing) and carried forward through v0.2.0.

Foundation layer of the compiler: data model for the three GLOSA elements plus the parsers that extract them from Fountain `[[ ]]` notes and FDX `glosa:` namespace XML.

## Original requirements

- [x] `Package.swift` — Swift 6.2+, macOS 26+ / iOS 26+, multi-target layout
- [x] `GlosaScore`, `SceneContext`, `Intent`, `Constraint` data model (Swift structs, `Sendable`)
- [x] `Intent.scoped: Bool` and `Intent.lineCount: Int?` for optional closing tag support
- [x] `GlosaParser` — Fountain extraction: regex to pull GLOSA tags from `[[ ]]` note strings
- [x] `GlosaParser` — FDX extraction: XMLParser delegate for `glosa:` namespace
- [x] `GlosaValidator` — well-formedness and nesting rule checks, diagnostic output
- [x] Tests: parse scored Fountain/FDX examples, verify `GlosaScore` structure

## Evidence

- `Package.swift` — multi-target layout (`GlosaCore`, `GlosaAnnotation`, `GlosaDirector`, `glosa`), Swift 6.2, macOS 26+/iOS 26+.
- `Sources/GlosaCore/GlosaScore.swift`, `SceneContext.swift`, `Intent.swift`, `Constraint.swift`, `GlosaDiagnostic.swift`.
- `Sources/GlosaCore/GlosaParser.swift` — Fountain regex + FDX XMLParser paths.
- `Sources/GlosaCore/GlosaValidator.swift`.
- Tests: `Tests/GlosaCoreTests/DataModelTests.swift`, `GlosaParserFountainTests.swift`, `GlosaParserFDXTests.swift`, `GlosaValidatorTests.swift`.
