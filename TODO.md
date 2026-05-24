# SwiftAcervo 0.16.x Migration

> **Status (2026-05-24): blockers addressed; build + 80 tests green on `development`.** Items 1, 2, 4, 7, 8 are done. Items 3, 6, 14 remain as optional polish — see annotations below.

Audit performed against `SwiftAcervo/Docs/USAGE-library.md` (library version `0.16.1-dev`). glosa-av is currently pinned `from: "0.13.0"`. The codebase is largely well-aligned with the new public surface — it already uses the component registry (`Acervo.register`, `Acervo.component`, `Acervo.ensureComponentReady`) rather than reaching into the repo-keyed API directly — but a handful of items must change before bumping the pin.

---

## Package.swift / Package.resolved bumps

### 1. Bump `SwiftAcervo` pin from `0.13.0` to `0.16.0` ✅ 2026-05-24

- **File**: `/Users/stovak/Projects/glosa-av/Package.swift:62-65`
- **Current**:
  ```swift
  sibling(
    "SwiftAcervo",
    remote: "https://github.com/intrusive-memory/SwiftAcervo.git",
    from: "0.13.0"),
  ```
- **Required**:
  ```swift
  sibling(
    "SwiftAcervo",
    remote: "https://github.com/intrusive-memory/SwiftAcervo.git",
    from: "0.16.0"),
  ```
- After bumping, regenerate `Package.resolved` via `make resolve` / `xcodebuild -resolvePackageDependencies` so a downstream consumer pulling the published version pins through to 0.16.x (the sibling-checkout path on Tom's machine does not exercise the remote pin).

---

## Code changes

### 2. `ModelCatalog.descriptors` should use the un-hydrated `ComponentDescriptor` initializer ✅ 2026-05-24

- **File**: `/Users/stovak/Projects/glosa-av/Sources/GlosaDirector/ModelCatalog.swift:27-42`
- **Current** (pre-hydrated, hard-coded `files:` array — exactly the v0.10.0 audit finding, still present):
  ```swift
  public static let descriptors: [ComponentDescriptor] = [
    ComponentDescriptor(
      id: defaultModelId,
      type: .languageModel,
      displayName: "Qwen2.5 3B Instruct (4-bit MLX)",
      repoId: defaultModelId,
      files: [
        ComponentFile(relativePath: "config.json"),
        ComponentFile(relativePath: "tokenizer.json"),
        ComponentFile(relativePath: "tokenizer_config.json"),
        ComponentFile(relativePath: "model.safetensors"),
      ],
      estimatedSizeBytes: 0,
      minimumMemoryBytes: 0
    )
  ]
  ```
- **Why**: 0.16.x has a bare initializer (`init(id:type:displayName:repoId:minimumMemoryBytes:metadata:)`) for descriptors whose file list comes from the CDN manifest. The hard-coded list here is brittle — it will drift the moment the published manifest adds a new shard (e.g. sharded safetensors), and `ensureComponentReady` will then under-download. `USAGE-library.md` §13 (Hydration) explicitly warns that the pre-hydrated initializer is only for bundle-pattern descriptors where multiple components share a `repoId`. This is a single-component repo — hydration is the correct path.
- **Required**:
  ```swift
  public static let descriptors: [ComponentDescriptor] = [
    ComponentDescriptor(
      id: defaultModelId,
      type: .languageModel,
      displayName: "Qwen2.5 3B Instruct (4-bit MLX)",
      repoId: defaultModelId,
      minimumMemoryBytes: 0,
      metadata: [:]
    )
  ]
  ```
  `Acervo.ensureComponentReady` auto-hydrates before downloading (USAGE §11), so `ensureModelReady` in this file does not need to change.

### 3. `StageDirector` should gate on `Acervo.isModelAvailable(_:)` (fast path) before calling the checker

- **File**: `/Users/stovak/Projects/glosa-av/Sources/GlosaDirector/StageDirector.swift:128`
- **Current**: unconditionally calls `modelChecker.ensureModelReady(resolvedModel, progress: progress)` for every `annotate` invocation, even when the model is fully present on disk.
- **Why**: `ensureComponentReady` does have its own fast path, but it still performs registry lookup, hydration coalescing, and acquires the per-model lock. For interactive CLI use (compile one screenplay, exit) this is fine; for a future server / batch use case `Acervo.isModelAvailable(_:)` is a strict synchronous probe that short-circuits to a single FS scan. Optional polish, not blocking.
- **Suggested** (only if a fast path matters here):
  ```swift
  if !Acervo.isModelAvailable(resolvedModel) {
      try await modelChecker.ensureModelReady(resolvedModel, progress: progress)
  }
  ```
  Skip this item if the explicit `SkipModelCheck` injection path in tests is the only "fast path" we care about.

### 4. Discriminate `AcervoError` in `ModelCatalog.ensureModelReady` ✅ 2026-05-24

- **File**: `/Users/stovak/Projects/glosa-av/Sources/GlosaDirector/ModelCatalog.swift:60-69`
- **Current**: re-throws every error from `Acervo.ensureComponentReady` unchanged. Callers in `glosa` CLI surface them as opaque `Error.localizedDescription`.
- **Why**: 0.16.x has a richer `AcervoError` (USAGE §"AcervoError"). Three cases are worth catching at the GlosaDirector boundary so the CLI can render actionable messages:
  - `.offlineModeActive` — "ACERVO_OFFLINE=1 is set; cannot download Qwen2.5-3B."
  - `.componentNotHydrated(id:)` / `.componentNotDownloaded(_:)` — should never escape `ensureComponentReady`, but if they do the message should point at SwiftAcervo, not at GLOSA.
  - `.integrityCheckFailed(file:expected:actual:)` — "Local model file failed SHA-256 verification; rerun with `--force` or delete `~/Library/Group Containers/.../<slug>/`."
- **Required** — wrap the call with a `do/catch` that switches on `AcervoError` and rethrows a `ModelCatalogError` case (extend the enum) carrying user-facing copy. Example:
  ```swift
  do {
      try await Acervo.ensureComponentReady(modelId, progress: progress)
  } catch let error as AcervoError {
      switch error {
      case .offlineModeActive:
          throw ModelCatalogError.offlineModeRequiresLocalModel(modelId)
      case .integrityCheckFailed(let file, _, _):
          throw ModelCatalogError.integrityFailure(modelId: modelId, file: file)
      default:
          throw error
      }
  }
  ```

### 5. (Confirmed addressed) `Acervo.modelDirectory(for:)` gating in StageDirector

- The v0.10.0 audit flagged `StageDirector.swift:47` as missing an `Acervo.modelDirectory(for:)` resolution before handing the model id to SwiftBruja. After re-reading current source, `StageDirector.annotate` (line 128) calls `modelChecker.ensureModelReady` and then passes `resolvedModel` (the bare model id string) to `provider.annotateScene(... model: resolvedModel)` — SwiftBruja resolves the path internally. No direct `Documents/Models/...` path construction is present anywhere in glosa-av. **No code change required.**

### 6. Availability UX in the `glosa` CLI

- **File**: `/Users/stovak/Projects/glosa-av/Sources/glosa/ProgressReporter.swift` and the surrounding commands (`CompileCommand.swift`, `PreviewCommand.swift`, `ScoreCommand.swift`).
- **Current**: the CLI commands call straight into `StageDirector.annotate(... progress:)`, which routes through `ModelCatalog.ensureModelReady`. There is no upfront `availability(_:)` check, so the CLI cannot distinguish "already cached, no progress bar needed" from "fresh download starting" before invoking the director.
- **Why**: `DownloadProgressReporter` already lazily defers bar construction until the first progress event (line 44), so the existing flow does *not* misrender for cached models. However, the four-state `ModelAvailability` would let the CLI print a one-line status before the (potentially silent) ensure call:
  - `.available` → "Model ready: …"
  - `.downloading(progress: p)` → "Resuming download at \(p*100)%…"
  - `.partial(missing: m)` → "Repairing \(m.count) missing shard(s)…"
  - `.notAvailable` → "Downloading Qwen2.5-3B-Instruct-4bit (~1.9 GB)…"
- **Suggested** (optional polish — does not block the migration): in each CLI command that triggers a download, call `await AcervoManager.shared.availability(modelId)` once and emit the appropriate prelude. Skip if you're happy with the silent-then-progress-bar UX.

---

## Documentation updates

### 7. README — SwiftAcervo version reference is stale ✅ 2026-05-24

- **File**: `/Users/stovak/Projects/glosa-av/README.md:128, 137`
- **Current**:
  - L128: "SwiftAcervo v0.10.0 resolves its App Group ID in this order…"
  - L137: links to `USAGE.md` (renamed in upstream).
- **Required**:
  - Update "v0.10.0" → "v0.16.x" (the resolution order itself is unchanged, but pinning the wrong version misleads readers about what they're consuming).
  - Update doc link `USAGE.md` → `Docs/USAGE-library.md` (upstream split into `USAGE-library.md` + `USAGE-cli.md`).

### 8. AGENTS.md — same version drift ✅ 2026-05-24

- **File**: `/Users/stovak/Projects/glosa-av/AGENTS.md:144, 153`
- **Current**: identical "v0.10.0" / `USAGE.md` references as README.
- **Required**: same edits as item 7. Keep the two files in sync.

### 9. CLAUDE.md — no SwiftAcervo content to change

- `/Users/stovak/Projects/glosa-av/CLAUDE.md` delegates App Group configuration to AGENTS.md. No edit needed once item 8 is done.

### 10. GEMINI.md — verify

- Grep returned no SwiftAcervo references in `GEMINI.md`. No edit needed.

---

## CI / Makefile / entitlements

### 11. (Confirmed in place) CI workflows already export `ACERVO_APP_GROUP_ID`

- `/Users/stovak/Projects/glosa-av/.github/workflows/release.yml:13` — sets `ACERVO_APP_GROUP_ID: group.intrusive-memory.models`.
- `/Users/stovak/Projects/glosa-av/.github/workflows/tests.yml:11` — same.
- `/Users/stovak/Projects/glosa-av/.github/workflows/ensure-model-cdn.yml:24` — same.
- **No change required.** This was flagged in the v0.10.0 audit and has since been fixed.

### 12. Makefile — confirm no Acervo-specific targets need updating

- Grep returned no SwiftAcervo references in `Makefile`. **No edit needed.**

### 13. Entitlements — no UI app target in this repo

- glosa-av ships only a CLI executable (`glosa`) and three libraries. There is no `.entitlements` file to update; UI consumers of `GlosaDirector` (e.g. a future GUI on top) must supply the App Group entitlement themselves. Document this expectation in AGENTS.md if you have not already (current language at line 146 covers it).

---

## Tests

### 14. No SwiftAcervo test coverage in glosa-av

- Grep across `Tests/` returned **zero** references to `Acervo`, `SwiftAcervo`, `AcervoError`, `ComponentDescriptor`, or `ModelDownloadManager`. All `GlosaDirectorTests` use `SkipModelCheck` (the test-only `ModelAvailabilityChecker` defined in `ModelCatalog.swift:118`) to bypass the registry entirely.
- This is **fine** as a design choice — exercising the real component registry from unit tests would require either network or a fixture CDN — but two regression checks would be cheap and worth adding:
  - **Hydration shape**: a unit test that constructs `ModelCatalog.descriptors[0]` and asserts `isHydrated == false` after the change in item 2. Catches future regressions where someone re-adds an explicit `files:` array.
  - **Registration smoke test**: call `ModelCatalog.registerAll()` then `Acervo.component(ModelCatalog.defaultModelId)` and assert non-nil. This does not require network and verifies the registry plumbing survives a SwiftAcervo version bump.
- **File to add**: `/Users/stovak/Projects/glosa-av/Tests/GlosaDirectorTests/ModelCatalogTests.swift` (new — there is no existing test for this module).

---

## Summary

Real code changes are concentrated in **one file** (`ModelCatalog.swift` — item 2 is the only blocker for adopting 0.16.x cleanly; item 4 is good hygiene). Items 3 and 6 are optional polish. Items 5, 9, 10, 11, 12, 13 are confirmations that prior audit findings have already been addressed. Doc bumps (7, 8) and the version pin (1) are mechanical.
