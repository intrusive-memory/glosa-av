---
state: completed
updated: 2026-05-13
mission: script-whisperer-01
phase: 2
title: GlosaCore — Score Resolver & Instruct Composer
---

# Phase 2 — GlosaCore: Score Resolver & Instruct Composer

**State:** complete. Shipped in the `script-whisperer-01` mission.

Stateful resolver that walks dialogue lines and resolves the active `SceneContext` / `Intent` / `Constraint` triple per line, plus the template-based composer that renders those directives into the natural-language instruct strings consumed downstream.

## Original requirements

- [x] `ScoreResolver` — stateful scope tracker: given a character + line index, returns `ResolvedDirectives`
- [x] Scoped Intent gradient: precise arc position (line N of M)
- [x] Marker Intent gradient: linear interpolation or steady blend
- [x] Neutral delivery when no Intent active (returns `nil` intent)
- [x] Per-character Constraint tracking (independent, keyed by character name)
- [x] `InstructComposer` — template-based composition: `ResolvedDirectives` → `String`
- [x] `InstructProvenance` — traceable mapping from directives to output
- [x] Tests: verify scope resolution at each line position across multiple scenes

## Evidence

- `Sources/GlosaCore/ScoreResolver.swift`, `ResolvedDirectives.swift`.
- `Sources/GlosaCore/InstructComposer.swift`, `InstructProvenance.swift`.
- Tests: `Tests/GlosaCoreTests/ScoreResolverTests.swift`, `InstructComposerTests.swift`.
