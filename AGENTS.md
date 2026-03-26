# GLOSA-AV

**GLOSA** (Annotation Vocabulary) is a performance notation for screenplays — a vocabulary of annotations that direct generated voice actors.

## Project Goals

GLOSA addresses the gap between a screenplay and a vocal performance. Currently, the TTS generation pipeline (Produciesta → VoiceLockManager → Qwen) sends each line of dialogue to the model in isolation, with at most a single instruct string like "speak softly." The model has no knowledge of where it is in a scene, what emotional trajectory the conversation is following, or what behavioral constraints define the character.

GLOSA solves this by providing three layers of annotation:

1. **SceneContext** — the physical and atmospheric environment (location, time of day, ambient sound) that wraps a scene with a required closing tag.
2. **Intent** — the emotional trajectory of a beat (`from` → `to`), delivery pace, and spacing between lines. A forward-applying marker with no closing tag.
3. **Constraint** — character-level behavioral direction ("angry but speaking softly on purpose"), keyed by character name. A forward-applying marker with no closing tag.

These annotations live invisibly inside the screenplay — in Fountain `[[ ]]` notes or as an XML namespace in FDX files. The screenplay remains readable and valid without them. A **Score Processor** reads the annotations, maintains cross-line state, and composes natural-language instruct strings that the TTS model can act on.

## Architecture

GLOSA is format-agnostic. It embeds in:
- **Fountain** — annotations inside `[[ ]]` note blocks
- **FDX (Final Draft XML)** — `glosa:` namespace elements, self-closing for markers
- **Highland** — Fountain rules apply (Highland is a ZIP containing Fountain)

GLOSA does not generate audio. It produces structured performance direction that feeds into an existing TTS pipeline. The layers below (VoiceLockManager, Qwen) never know GLOSA exists — they receive a `GenerationContext` with a better instruct string.

## Design Principles

- **The screenplay IS the score** — one file, one source of truth.
- **Invisible in performance, visible in rehearsal** — the audience never sees GLOSA; the pipeline always does.
- **Director, not controller** — GLOSA sets boundaries and trajectory; the model fills in the micro-performance.
- **Discovered vocabulary** — attribute values are empirical, co-evolving with the model. The grammar is stable; the vocabulary is alive.

## Related Projects

- [SwiftVoxAlta](https://github.com/intrusive-memory/SwiftVoxAlta) — TTS synthesis library (`diga` CLI). GLOSA parser and Score Processor will be implemented here.
- [SwiftCompartido](https://github.com/intrusive-memory/SwiftCompartido) — Fountain and FDX parsers. Will be extended to extract GLOSA annotations.
- [Produciesta](https://github.com/intrusive-memory/Produciesta) — Podcast generation pipeline that orchestrates the flow from screenplay to audio.
