---
state: completed
updated: 2026-05-13
mission: script-whisperer-01
phase: 6
title: glosa CLI — score, compile, preview, glossary, compare
---

# Phase 6 — `glosa` CLI

**State:** complete. Shipped in `script-whisperer-01`, with `compare` and `glossary` subcommands added as part of the Phase 8 vocabulary tooling work.

Public command-line surface for working with GLOSA-annotated screenplays. Uses swift-argument-parser. `SharedOptions` carries `--model`, `--glossary`, `--format`, plus a verbosity flag.

## Original requirements

- [x] `glosa score <file>` — annotate a raw screenplay, write scored version to disk
- [x] `glosa compile <file>` — compile an already-scored screenplay, print instruct table
- [x] `glosa preview <file>` — show resolved directives per line with arc positions (no audio)
- [x] `--model <id>` flag for LLM model override
- [x] `--glossary <path>` flag for custom vocabulary glossary
- [x] `--format fountain|fdx` flag for output format override

## Additional subcommands shipped (beyond original plan)

- `glosa glossary {list,add,remove}` — supports Phase 8 vocabulary discovery.
- `glosa compare` — template-compiled vs LLM-annotated instruct strings, line by line, for quality comparison.

## Evidence

- `Sources/glosa/GlosaCommand.swift` (entry + `SharedOptions`), `ScoreCommand.swift`, `CompileCommand.swift`, `PreviewCommand.swift`, `GlossaryCommand.swift`, `CompareCommand.swift`, `ProgressReporter.swift`.
- Package executable target `glosa` defined in `Package.swift`.
