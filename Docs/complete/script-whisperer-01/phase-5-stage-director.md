---
state: completed
updated: 2026-05-13
mission: script-whisperer-01
phase: 5
title: GlosaDirector — Stage Director (LLM annotation)
---

# Phase 5 — GlosaDirector: Stage Director

**State:** complete. Initial implementation shipped in `script-whisperer-01`. Extended in PR #6 ("Wire SwiftAcervo v2 component registry for on-demand LLM download", commit b0399f1) to integrate the v2 component registry so the LLM is fetched on demand rather than bundled.

The LLM-powered annotation generator: takes a raw parsed screenplay, segments it into scenes, and asks SwiftBruja to return structured `SceneAnnotation` output that the analyzer maps onto element indices. The LLM never sees or emits raw SGML — grammar and serialization stay in code.

## Original requirements

- [x] Add SwiftBruja and SwiftAcervo dependencies to `Package.swift` (`GlosaDirector` target only)
- [x] `SceneAnalyzer` — segment `GuionParsedElementCollection` into scenes by `sceneHeading` boundaries
- [x] `SceneAnnotation` Codable struct — structured output schema for LLM response
- [x] LLM system prompt: GLOSA spec + `VocabularyGlossary` + few-shot examples
- [x] `StageDirector.annotate()` — per-scene LLM call via `Bruja.query(as: SceneAnnotation.self)`, validation, element mapping
- [x] `VocabularyGlossary` — default glossary JSON, project-level override support
- [x] Tests: annotate a known screenplay, verify all dialogue lines receive instruct strings, verify GLOSA well-formedness

## Evidence

- `Sources/GlosaDirector/SceneAnalyzer.swift`, `SceneAnnotation.swift`, `Prompts.swift`, `StageDirector.swift`, `VocabularyGlossary.swift`, `ModelCatalog.swift` (v2 component registry integration).
- `Sources/GlosaDirector/Resources/` — bundled glossary JSON.
- Tests: `Tests/GlosaDirectorTests/SceneAnalyzerTests.swift`, `StageDirectorTests.swift`, `VocabularyGlossaryMutationTests.swift`.
