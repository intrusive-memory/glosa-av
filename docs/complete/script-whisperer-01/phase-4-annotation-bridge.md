---
state: completed
updated: 2026-05-13
mission: script-whisperer-01
phase: 4
title: GlosaAnnotation — Element Bridge
---

# Phase 4 — GlosaAnnotation: Element Bridge

**State:** complete. Shipped in the `script-whisperer-01` mission.

Bridges the Foundation-only compiler to SwiftCompartido's parsed element model. Provides `GlosaAnnotatedElement` (a `GuionElement` paired with its resolved directives and instruct string) and the `GlosaSerializer` that writes annotated screenplays back to Fountain `[[ ]]` notes or FDX `glosa:` namespace XML with round-trip fidelity.

## Original requirements

- [x] Add SwiftCompartido dependency to `Package.swift` (`GlosaAnnotation` target only)
- [x] `GlosaAnnotatedElement` — wrapper pairing `GuionElement` with `ResolvedDirectives` and `instruct: String?`
- [x] `GlosaAnnotatedScreenplay` — wraps `GuionParsedElementCollection` with annotated elements, score, diagnostics, provenance
- [x] `GlosaSerializer` — write `GlosaAnnotatedScreenplay` back to Fountain with `[[ ]]` GLOSA notes
- [x] `GlosaSerializer` — write `GlosaAnnotatedScreenplay` back to FDX with `glosa:` namespace elements
- [x] Round-trip test: parse annotated Fountain → `GlosaAnnotatedScreenplay` → serialize → parse again → verify identical annotations
- [x] Tests: verify `GlosaAnnotatedElement.instruct` matches `CompilationResult.instructs[index]` for all dialogue elements

## Evidence

- `Package.swift` — `GlosaAnnotation` target with `SwiftCompartido` dependency.
- `Sources/GlosaAnnotation/GlosaAnnotatedElement.swift`, `GlosaAnnotatedScreenplay.swift`, `GlosaSerializer.swift`.
- Tests: `Tests/GlosaAnnotationTests/GlosaAnnotatedScreenplayTests.swift`, `GlosaSerializerFountainTests.swift`, `GlosaSerializerFDXTests.swift`.
