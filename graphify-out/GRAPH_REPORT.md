# Graph Report - .  (2026-07-08)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 725 nodes · 1191 edges · 46 communities (24 shown, 22 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 39 edges (avg confidence: 0.78)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `011860cf`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Breath Tag Parsing|Breath Tag Parsing]]
- [[_COMMUNITY_Line Annotation Compiler|Line Annotation Compiler]]
- [[_COMMUNITY_Glosa Compiler Core|Glosa Compiler Core]]
- [[_COMMUNITY_Inline Notes & Validation|Inline Notes & Validation]]
- [[_COMMUNITY_Glosa Score Model|Glosa Score Model]]
- [[_COMMUNITY_Instruct Composer Tests|Instruct Composer Tests]]
- [[_COMMUNITY_Score Resolver Tests|Score Resolver Tests]]
- [[_COMMUNITY_Fountain Pause Parser Tests|Fountain Pause Parser Tests]]
- [[_COMMUNITY_Validator Diagnostics Tests|Validator Diagnostics Tests]]
- [[_COMMUNITY_Pause Model Tests|Pause Model Tests]]
- [[_COMMUNITY_Project Docs & Briefs|Project Docs & Briefs]]
- [[_COMMUNITY_Diagnostic Codes|Diagnostic Codes]]
- [[_COMMUNITY_Breath Validator Tests|Breath Validator Tests]]
- [[_COMMUNITY_IncludeShot Parser Tests|Include/Shot Parser Tests]]
- [[_COMMUNITY_FDX Pause Parser Tests|FDX Pause Parser Tests]]
- [[_COMMUNITY_Compilation Result Model|Compilation Result Model]]
- [[_COMMUNITY_Score Resolver|Score Resolver]]
- [[_COMMUNITY_Glosa Compiler Tests|Glosa Compiler Tests]]
- [[_COMMUNITY_Breath Model|Breath Model]]
- [[_COMMUNITY_Data Model Round-Trip Tests|Data Model Round-Trip Tests]]
- [[_COMMUNITY_Pause Validator Tests|Pause Validator Tests]]
- [[_COMMUNITY_Requirements & Mission Docs|Requirements & Mission Docs]]
- [[_COMMUNITY_Pause Length Parsing|Pause Length Parsing]]
- [[_COMMUNITY_Pause Compiler Tests|Pause Compiler Tests]]
- [[_COMMUNITY_Include Directive Model|Include Directive Model]]
- [[_COMMUNITY_Breath Model Tests|Breath Model Tests]]
- [[_COMMUNITY_Fountain Breath Parser Tests|Fountain Breath Parser Tests]]
- [[_COMMUNITY_Inline Notes Tests|Inline Notes Tests]]
- [[_COMMUNITY_Fountain Glosa Parser Tests|Fountain Glosa Parser Tests]]
- [[_COMMUNITY_IncludeShot Codable Tests|Include/Shot Codable Tests]]
- [[_COMMUNITY_Resolved Directives Model|Resolved Directives Model]]
- [[_COMMUNITY_FDX Glosa Parser Tests|FDX Glosa Parser Tests]]
- [[_COMMUNITY_Instruct Provenance Model|Instruct Provenance Model]]
- [[_COMMUNITY_Shot Directive Model|Shot Directive Model]]
- [[_COMMUNITY_FDX Breath Parser Tests|FDX Breath Parser Tests]]
- [[_COMMUNITY_Intent Model|Intent Model]]
- [[_COMMUNITY_Breath Compiler Tests|Breath Compiler Tests]]
- [[_COMMUNITY_Scene Context Model|Scene Context Model]]
- [[_COMMUNITY_Constraint Model|Constraint Model]]
- [[_COMMUNITY_Pause Model|Pause Model]]
- [[_COMMUNITY_Glosa Version|Glosa Version]]
- [[_COMMUNITY_Stage Director Phase Docs|Stage Director Phase Docs]]
- [[_COMMUNITY_Glosa CLI Phase Docs|Glosa CLI Phase Docs]]
- [[_COMMUNITY_Package Manifest|Package Manifest]]
- [[_COMMUNITY_Community 45|Community 45]]

## God Nodes (most connected - your core abstractions)
1. `GlosaParser` - 32 edges
2. `String` - 32 edges
3. `FDXParserDelegate` - 29 edges
4. `InstructComposerTests` - 24 edges
5. `ScoreResolverTests` - 23 edges
6. `UniversalPromptTests` - 22 edges
7. `PauseParserFountainTests` - 21 edges
8. `GlosaValidatorTests` - 20 edges
9. `PauseTests` - 18 edges
10. `GlosaCompiler` - 16 edges

## Surprising Connections (you probably didn't know these)
- `Adding a GLOSA Directive` --references--> `GlosaCompiler`  [EXTRACTED]
  docs/ADDING-A-DIRECTIVE.md → Sources/GlosaCore/GlosaCompiler.swift
- `Phase 3 — Public API & Compiler` --references--> `GlosaCompiler`  [EXTRACTED]
  docs/complete/script-whisperer-01/phase-3-public-api.md → Sources/GlosaCore/GlosaCompiler.swift
- `Phase 1 — GlosaCore Data Model & Parser` --references--> `GlosaParser`  [EXTRACTED]
  docs/complete/script-whisperer-01/phase-1-glosa-core-data-model.md → Sources/GlosaCore/GlosaParser.swift
- `Phase 2 — Resolver & Composer` --references--> `ScoreResolver`  [EXTRACTED]
  docs/complete/script-whisperer-01/phase-2-resolver-and-composer.md → Sources/GlosaCore/ScoreResolver.swift
- `Breath struct / BreathStrength` --conceptually_related_to--> `<breath> tag spec`  [EXTRACTED]
  Sources/GlosaCore/Breath.swift → docs/complete/breath-tag.md

## Import Cycles
- None detected.

## Communities (46 total, 22 thin omitted)

### Community 0 - "Breath Tag Parsing"
Cohesion: 0.09
Nodes (36): Breath, BreathTagOutcome, after, inline, skip, FDXParserDelegate, GlosaParser, InlineNoteExtraction (+28 more)

### Community 1 - "Line Annotation Compiler"
Cohesion: 0.08
Nodes (27): CodingKeys, breathOffsets, breathPrompts, breathStrengths, instruct, lengthMs, named, offset (+19 more)

### Community 2 - "Glosa Compiler Core"
Cohesion: 0.08
Nodes (31): Breath struct / BreathStrength, <breath> tag spec, CHANGELOG, OPERATION CLEAVING BREATH Brief, CLEAVING BREATH TODO, CodingKey, CLEAVING BREATH Execution Plan, CodingKeys (+23 more)

### Community 3 - "Inline Notes & Validation"
Cohesion: 0.10
Nodes (35): SwiftAcervo 0.16.x Migration TODO, Adding a GLOSA Directive, compileAnnotations, compileScript, AGENTS.md — AI Agent Instructions, GLOSA-AV Agent Instructions, GlosaCompiler, GlosaCore (+27 more)

### Community 4 - "Glosa Score Model"
Cohesion: 0.10
Nodes (18): BreathPoint, CompilationResult, Float, GlosaCompiler, InstructComposer, Phase 3 — Public API & Compiler, ResolvedDirectives, ResolvedIntent (+10 more)

### Community 5 - "Instruct Composer Tests"
Cohesion: 0.13
Nodes (15): GlosaInlineNotes, InlineNoteMatch, ScanResult, BreathKey, GlosaValidator, Hashable, NSRange, NSRegularExpression (+7 more)

### Community 7 - "Fountain Pause Parser Tests"
Cohesion: 0.14
Nodes (14): ResolvedDirectives, ResolvedIntent, ScoreResolver, Phase 2 — Resolver & Composer, Constraint, Float, Intent, SceneContext (+6 more)

### Community 12 - "Breath Validator Tests"
Cohesion: 0.13
Nodes (3): UniversalPromptTests, Data, String

### Community 13 - "Include/Shot Parser Tests"
Cohesion: 0.16
Nodes (14): Breath, BreathStrength, medium, strong, weak, Token, beat, comma (+6 more)

### Community 14 - "FDX Pause Parser Tests"
Cohesion: 0.15
Nodes (15): Code, breathCollapsedByPause, breathDuplicateOffset, breathMissingOnLongLine, breathOutsideDialogue, includeMissingSrc, promptEmpty, shotMissingPrompt (+7 more)

### Community 15 - "Compilation Result Model"
Cohesion: 0.24
Nodes (4): BreathValidatorTests, Breath, GlosaScore, String

### Community 16 - "Score Resolver"
Cohesion: 0.30
Nodes (12): BreathStrength, BreathPoint, CompilationResult, PausePoint, InstructProvenance, BreathStrength, GlosaDiagnostic, Include (+4 more)

### Community 17 - "Glosa Compiler Tests"
Cohesion: 0.14
Nodes (4): IncludeShotParserFDXTests, IncludeShotParserFountainTests, Data, String

### Community 18 - "Breath Model"
Cohesion: 0.20
Nodes (3): PauseParserFDXTests, Data, String

### Community 22 - "Pause Length Parsing"
Cohesion: 0.18
Nodes (13): breath-tag source spec, Docs/REQUIREMENTS.md, SwiftCompartido REQUIREMENTS glosa-integration (consumer draft), Iteration 01 Brief — OPERATION SKELETON EVICTION, EXECUTION_PLAN — OPERATION SKELETON EVICTION, REQUIREMENTS — Glosa Integration (glosa-av), REQUIREMENTS — Glosa Integration (RECONCILED), SUPERVISOR_STATE — OPERATION SKELETON EVICTION (+5 more)

### Community 24 - "Include Directive Model"
Cohesion: 0.26
Nodes (10): Equatable, Include, IncludeMode, bed, overlay, sequential, IncludeMode, Double (+2 more)

### Community 30 - "Resolved Directives Model"
Cohesion: 0.27
Nodes (6): Codable, Constraint, SceneContext, Sendable, String, String

### Community 31 - "FDX Glosa Parser Tests"
Cohesion: 0.20
Nodes (9): Encoder, PauseLength, beat, comma, emDash, explicit, period, semicolon (+1 more)

### Community 33 - "Shot Directive Model"
Cohesion: 0.43
Nodes (6): InstructProvenance, Constraint, Int, ResolvedIntent, SceneContext, String

### Community 34 - "FDX Breath Parser Tests"
Cohesion: 0.43
Nodes (6): Shot, Bool, Double, Int, String, UInt64

### Community 36 - "Breath Compiler Tests"
Cohesion: 0.53
Nodes (4): Intent, Bool, Int, String

### Community 37 - "Scene Context Model"
Cohesion: 0.53
Nodes (4): Pause, Int, PauseLength, String

### Community 39 - "Pause Model"
Cohesion: 0.67
Nodes (3): Constraint directive, Intent directive, SceneContext directive

## Ambiguous Edges - Review These
- `Iteration 01 Brief — OPERATION SIGHING SCRIBE` → `Iteration 01 Brief — OPERATION SKELETON EVICTION`  [AMBIGUOUS]
  docs/complete/skeleton-eviction-01/OPERATION_SKELETON_EVICTION_01_BRIEF.md · relation: conceptually_related_to

## Knowledge Gaps
- **106 isolated node(s):** `comma`, `semicolon`, `period`, `emDash`, `beat` (+101 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **22 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Iteration 01 Brief — OPERATION SIGHING SCRIBE` and `Iteration 01 Brief — OPERATION SKELETON EVICTION`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `GlosaParser` connect `Breath Tag Parsing` to `Glosa Compiler Core`, `Glosa Score Model`, `Instruct Composer Tests`, `Validator Diagnostics Tests`, `Resolved Directives Model`?**
  _High betweenness centrality (0.138) - this node is a cross-community bridge._
- **Why does `GlosaCompiler` connect `Glosa Score Model` to `Breath Tag Parsing`, `Line Annotation Compiler`, `Inline Notes & Validation`, `Instruct Composer Tests`, `Fountain Pause Parser Tests`, `Score Resolver`, `Resolved Directives Model`?**
  _High betweenness centrality (0.107) - this node is a cross-community bridge._
- **Why does `compileScript()` connect `Line Annotation Compiler` to `Glosa Score Model`?**
  _High betweenness centrality (0.042) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `GlosaParser` (e.g. with `.compile()` and `.endToEndRequirementsExample()`) actually correct?**
  _`GlosaParser` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `comma`, `semicolon`, `period` to the rest of the system?**
  _106 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Breath Tag Parsing` be split into smaller, more focused modules?**
  _Cohesion score 0.0881287726358149 - nodes in this community are weakly interconnected._