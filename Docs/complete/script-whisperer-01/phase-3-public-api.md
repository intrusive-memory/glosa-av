---
state: completed
updated: 2026-05-13
mission: script-whisperer-01
phase: 3
title: GlosaCore — Public API & Compiler
---

# Phase 3 — GlosaCore: Public API & Compiler

**State:** complete. Shipped in the `script-whisperer-01` mission.

Top-level `GlosaCompiler` entry point that composes parser + resolver + composer into a single deterministic, Foundation-only API. Returns `CompilationResult` with per-line instruct strings, diagnostics, and provenance.

## Original requirements

- [x] `GlosaCompiler` — public API combining parser + resolver + composer
- [x] `CompilationResult` — `instructs: [Int: String]`, `diagnostics: [GlosaDiagnostic]`, `provenance: [InstructProvenance]`
- [x] Fallback behavior: empty instructs dict when no GLOSA annotations present
- [x] Tests: end-to-end compilation from scored Fountain → instruct strings

## Evidence

- `Sources/GlosaCore/GlosaCompiler.swift`, `CompilationResult.swift`, `GlosaVersion.swift`.
- Tests: `Tests/GlosaCoreTests/GlosaCompilerTests.swift`.
