---
type: doc
---

# `<shot caption="…">` — authored panel captions

> **Status (2026-07-27): done ✅.** Implemented on `feat/shot-caption-attribute` off
> `development` — §§1–4 and §6 landed, §5 confirmed as a deliberate no-op. `make build`
> and `make test` green (268 tests in 25 suites, 6 net-new tests plus the extended
> full-option-set test); `make format` produced no further changes. Additive and
> non-breaking. `GlosaVersion.swift` and `Package.swift` untouched — the release itself
> is a follow-up `/ship-swift-library` run.

## Why

The Vinetas storyboard viewer (`intrusive-memory/Vinetas`, `skills/vinetas-cli/`) renders
a `board.json` manifest in which every panel carries a `script.text` caption — "what makes
the board a shooting board rather than a slideshow."

The original design inferred that caption from the screenplay text surrounding each
`<shot>`. That was tested against the one real production screenplay
(`podcasts/granville/episodes/episode_1_01_cold_open_storyboards.fountain`, 10 shots) and
**produced an empty caption for all ten panels**: every shot there is immediately followed
by another shot or a scene heading, and the file's narrative prose lives in Fountain
synopsis lines (`= …`) in scenes that contain no shots at all.

Inference is the wrong tool. The caption is an authoring decision, so the author should
write it. This TODO adds `caption` as a first-class `<shot>` attribute; the downstream
manifest then reads it directly and emits `""` when it is absent.

**GlosaCore stays parse-and-carry**: it does not interpret, compose, or default the
caption. It parses the attribute and hands it to consumers, exactly as it does for `style`
and `negative`.

---

## Scope

Adding an attribute to an **existing** standalone block-event directive. This is *not* the
full `docs/ADDING-A-DIRECTIVE.md` checklist — no new model type, no `GlosaScore` field, no
`CompilationResult` change, no façade change. Five touch points only.

---

## 1. Model — `Sources/GlosaCore/Shot.swift`

Add the stored property and its initializer parameter.

- **Property**: place `caption` immediately after `prompt` (it is prose about the panel,
  not a generate option — the remaining fields all map to `vinetas generate` flags).

  ```swift
  /// Author-written description of the story beat this panel illustrates, for
  /// display beneath the image on a storyboard/shooting board. Unlike every
  /// other attribute here, `caption` does **not** map to a `vinetas generate`
  /// flag — it is never sent to the image model and never affects rendering.
  /// GlosaCore parses and carries it; downstream consumers decide how to show
  /// it. `nil` when the author wrote no caption.
  public var caption: String?
  ```

- **Initializer**: add `caption: String? = nil` after `prompt`, and the matching
  `self.caption = caption` assignment. **The default value is required** — it keeps every
  existing call site source-compatible.

- **Type doc-comment**: `Shot.swift:1–35` is the authoritative spec for this directive
  (the attribute set is not tabulated in `README.md` or `docs/REQUIREMENTS.md`). Add a
  short paragraph after the "Defaults convention" section noting that `caption` is
  display-only, is **not** inherited through the promptless-defaults mechanism, and is
  ignored by the generate-argv projection.

  **Decision — `caption` does not participate in defaults inheritance.** A shared caption
  across panels is meaningless; each beat gets its own or none. Say so explicitly so the
  downstream folding implementation does not guess.

`Codable` conformance is synthesized, and an added `Optional` property decodes to `nil`
from legacy JSON — so this is wire-compatible in both directions. Pin that with a test
(§4).

---

## 2. Parse (Fountain) — `Sources/GlosaCore/GlosaParser.swift:451`

In `parseShotTag(_:documentIndex:)`, add to the `Shot(...)` construction:

```swift
caption: extractAttribute("caption", from: text),
```

### The trap this must not fall into

Every `negative` value in the Granville screenplay contains the literal word `caption`, as
a render-avoidance term:

```
negative="text, words, letters, lettering, typography, title, masthead, magazine cover,
magazine layout, cover text, headline, caption, signage, watermark, …"
```

A naive substring search for `caption` matches there and returns garbage.

**The existing helper is already safe** — `extractAttribute` (`GlosaParser.swift:508`)
builds the pattern `name + #"="([^"]*)""#`, so it requires `caption=` immediately followed
by a quote. Inside a `negative` value the word appears as `caption,`, which cannot match.
Verified by reading the implementation; **do not refactor it.**

Add the regression test anyway (§4) — the safety is incidental to the helper's design and
a future rewrite of `extractAttribute` could silently break it.

---

## 3. Parse (FDX) — `Sources/GlosaCore/GlosaParser.swift:1330`

In `handleShotStart(attributes:)`, add:

```swift
caption: attributes["caption"],
```

Exact dictionary lookup — no substring hazard on this path.

---

## 4. Tests — `Tests/GlosaCoreTests/IncludeShotParserTests.swift`

The suite uses **swift-testing** (`@Test`, `struct` suites), not XCTest. Match it.

Add to `IncludeShotParserFountainTests`:

1. `<shot caption=…> parses the caption` — a shot with both `prompt` and `caption`;
   assert the exact string round-trips.
2. `<shot> without caption yields nil` — assert `shot.caption == nil`, not `""`.
3. **`<shot> whose negative contains the word "caption" yields nil caption`** — use a
   realistic Granville-style `negative` value (copy one verbatim from the screenplay
   named above). This is the regression guard for §2.
4. `<shot caption=…> with single-quoted value parses` — `extractAttribute` supports both
   quote styles; cover the second path.
5. `caption survives Codable round-trip, and legacy JSON without it decodes to nil` —
   encode/decode a `Shot`, then decode a hand-written JSON object omitting `caption` and
   assert `nil`. This is the wire-compatibility guarantee from §1.

Add to `IncludeShotParserFDXTests`:

6. `<glosa:shot caption=…/> parses the caption` — the FDX path from §3.

Also extend the existing `"<shot> parses the full Vinetas generate option set"` test
(`:94`) so the full-attribute fixture includes `caption`, keeping "full option set"
honest.

---

## 5. Validator — `Sources/GlosaCore/GlosaValidator.swift`

**No change. No new `GlosaDiagnostic` case.**

Recorded as a deliberate decision, not an oversight: 0.7.0 added `.promptEmpty` for
empty `prompt` values, so the symmetric move would be a `.captionEmpty` advisory. Skip it.
An empty `caption=""` is a legitimate way for an author to say "this panel gets no
caption," the downstream viewer already collapses an empty caption area to zero height,
and a new diagnostic case is public API surface that cannot be withdrawn cheaply.

---

## 6. CHANGELOG — `CHANGELOG.md`

Add under `## [Unreleased]` → `### Added`, matching the existing entries' level of detail:

- **`caption` attribute on `<shot>`** — an author-written description of the story beat a
  panel illustrates, parsed from both Fountain block tags and FDX `glosa:shot` elements
  and carried on `Shot.caption`. Display-only: it never reaches the image model, does not
  participate in the promptless-defaults inheritance, and is ignored by the generate-argv
  projection. Absent attribute yields `nil`. Added for the Vinetas storyboard-viewer
  board manifest, which previously tried to infer panel captions from surrounding
  screenplay text.

**Do not bump `Sources/GlosaCore/GlosaVersion.swift`** (currently `0.7.1-dev`) and do not
edit `Package.swift`. Version selection belongs to the follow-up `/ship-swift-library`
run; an additive public-API field makes that our next **minor** release version.

---

## Verification

Build and test through the Makefile. **Never `swift build` or `swift test`.**

```bash
make build
make test
make format   # then re-run `make test` if it rewrites anything
```

### Definition of done

- [x] `make build` exits 0.
- [x] `make test` exits 0, with 7 net-new assertions (6 new tests + the extended full-option-set test).
- [x] `grep -c 'caption' Sources/GlosaCore/Shot.swift` ≥ 3 (property, init param, assignment).
- [x] Both parse paths carry it: `grep -c 'caption' Sources/GlosaCore/GlosaParser.swift` == 2.
- [x] `git diff --stat` touches only `Shot.swift`, `GlosaParser.swift`, `IncludeShotParserTests.swift`, `CHANGELOG.md`, and this file.
- [x] `GlosaVersion.swift` and `Package.swift` are **unmodified**.
