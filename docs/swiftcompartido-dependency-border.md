---
type: reference
---

# SwiftCompartido ↔ glosa-av Dependency Border

**Version**: SwiftCompartido 7.0.5-dev, glosa-av 0.6.0-dev  
**Last Updated**: 2026-06-18

## Overview

SwiftCompartido depends on **glosa-av's GlosaCore** library for screenplay dialogue annotation. This document defines the exact API surface, data flow, and architectural constraints at the dependency border.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         SwiftCompartido                                  │
│                    (Screenplay parsing & storage)                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ DocumentModelActor                                                │  │
│  │ (SwiftData actor for concurrent database operations)              │  │
│  │                                                                    │  │
│  │  parseAndSaveDocument(from:progress:parseGlosa:)                  │  │
│  │       │                                                            │  │
│  │       └──> annotateGlosa(document:) ───┐                          │  │
│  │                                         │                          │  │
│  │       ┌─────────────────────────────────┘                          │  │
│  │       ▼                                                            │  │
│  │  private func annotateGlosa(document: GuionDocumentModel) {       │  │
│  │    // 1. Extract Fountain notes and dialogue from SwiftData       │  │
│  │    let fountainNotes: [String] = []                               │  │
│  │    let rawDialogueLines: [(character: String, rawText: String)]   │  │
│  │                                                                    │  │
│  │    // 2. Call GlosaCore                                           │  │
│  │    let annotations = try compileAnnotations(  ─────────┐          │  │
│  │      fountainNotes: fountainNotes,                     │          │  │
│  │      rawDialogueLines: rawDialogueLines                │          │  │
│  │    )                                                   │          │  │
│  │                                                        │          │  │
│  │    // 3. Write glosa fields to GuionElementModel      │          │  │
│  │    element.glosaSpokenText = dto.spokenText           │          │  │
│  │    element.glosaBreathOffsets = dto.breathOffsets     │          │  │
│  │    element.glosaBreathStrengths = dto.breathStrengths │          │  │
│  │    element.glosaInstruct = dto.instruct               │          │  │
│  │    element.glosaPausePoints = encode(dto.pausePoints) │          │  │
│  │  }                                                     │          │  │
│  └────────────────────────────────────────────────────────┼──────────┘  │
│                                                            │             │
│  ┌────────────────────────────────────────────────────────┼──────────┐  │
│  │ GuionElementModel (SwiftData model)                    │          │  │
│  │                                                        │          │  │
│  │  var glosaSpokenText: String? = nil      ◄─────────────┘          │  │
│  │  var glosaBreathOffsets: [Int]? = nil                             │  │
│  │  var glosaBreathStrengths: [String]? = nil                        │  │
│  │  var glosaInstruct: String? = nil                                 │  │
│  │  var glosaPausePoints: Data? = nil                                │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ import GlosaCore
                                    │
═══════════════════════════════════╪═══════════════════════════════════════
          DEPENDENCY BORDER         │
═══════════════════════════════════╪═══════════════════════════════════════
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                              glosa-av                                     │
│                         (GLOSA compiler)                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │ GlosaCore (Foundation-only, zero dependencies)                    │  │
│  │                                                                    │  │
│  │  /// PUBLIC API: Boundary function for consumers                  │  │
│  │  public func compileAnnotations(                                  │  │
│  │    fountainNotes: [String],                                       │  │
│  │    rawDialogueLines: [(character: String, rawText: String)]       │  │
│  │  ) throws -> [Int: GlosaLineAnnotation]                           │  │
│  │                                                                    │  │
│  │  Internal pipeline:                                               │  │
│  │  ┌──────────────────────────────────────────────────────────┐    │  │
│  │  │ 1. GlosaInlineNotes.strip(rawText)                       │    │  │
│  │  │    - Strips [[<breath/>]] and [[<pause/>]] markers       │    │  │
│  │  │    - Produces spokenText                                 │    │  │
│  │  └──────────────────────────────────────────────────────────┘    │  │
│  │       │                                                            │  │
│  │       ▼                                                            │  │
│  │  ┌──────────────────────────────────────────────────────────┐    │  │
│  │  │ 2. GlosaCompiler.compile()                               │    │  │
│  │  │    - GlosaParser: extract GLOSA tags from Fountain notes │    │  │
│  │  │    - GlosaValidator: well-formedness checks              │    │  │
│  │  │    - ScoreResolver: resolve directives per line          │    │  │
│  │  │    - InstructComposer: compose instruct strings          │    │  │
│  │  └──────────────────────────────────────────────────────────┘    │  │
│  │       │                                                            │  │
│  │       ▼                                                            │  │
│  │  ┌──────────────────────────────────────────────────────────┐    │  │
│  │  │ 3. Project to DTO layer                                  │    │  │
│  │  │    - Convert BreathPoint → breathOffsets + strengths     │    │  │
│  │  │    - Convert PausePoint → PausePointDTO                  │    │  │
│  │  │    - Return GlosaLineAnnotation per dialogue line        │    │  │
│  │  └──────────────────────────────────────────────────────────┘    │  │
│  │                                                                    │  │
│  │  /// DTO: Crosses the glosa-av boundary                           │  │
│  │  public struct GlosaLineAnnotation: Codable, Sendable {           │  │
│  │    public let spokenText: String                                  │  │
│  │    public let breathOffsets: [Int]                                │  │
│  │    public let breathStrengths: [String]  // "weak|medium|strong"  │  │
│  │    public let instruct: String?                                   │  │
│  │    public let pausePoints: [PausePointDTO]                        │  │
│  │  }                                                                 │  │
│  │                                                                    │  │
│  │  public struct PausePointDTO: Codable, Sendable {                 │  │
│  │    public let offset: Int                                         │  │
│  │    public let lengthMs: Int                                       │  │
│  │    public let named: String?  // "comma"|"period"|"beat"|nil      │  │
│  │  }                                                                 │  │
│  └────────────────────────────────────────────────────────────────── ┘  │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## API Surface

### Input: What SwiftCompartido Provides

| Parameter | Type | Description |
|-----------|------|-------------|
| `fountainNotes` | `[String]` | Extracted Fountain `[[ ]]` note blocks in document order, including both GLOSA tags and dialogue lines |
| `rawDialogueLines` | `[(character: String, rawText: String)]` | Dialogue tuples with **raw** text (inline `[[<breath/>]]`/`[[<pause/>]]` markers intact) |

**Critical**: `rawText` must **NOT** be pre-stripped. `compileAnnotations()` handles stripping internally via `GlosaInlineNotes.strip()`.

### Output: What glosa-av Returns

**Type**: `[Int: GlosaLineAnnotation]`

A dictionary keyed by zero-based dialogue line index (matching `rawDialogueLines` order). Every line index has an entry, even if no annotation data exists.

#### GlosaLineAnnotation DTO

```swift
public struct GlosaLineAnnotation: Codable, Sendable {
  /// Notes-stripped text the actor speaks
  public let spokenText: String
  
  /// Unicode-scalar offsets where chunker should consider phrasing seams
  /// Sorted ascending; split *after* the nth scalar
  public let breathOffsets: [Int]
  
  /// Parallel to breathOffsets: "weak", "medium", or "strong"
  public let breathStrengths: [String]
  
  /// Optional LLM performance direction (nil if no active GLOSA directive)
  public let instruct: String?
  
  /// Timed-silence seam points
  public let pausePoints: [PausePointDTO]
}

public struct PausePointDTO: Codable, Sendable {
  /// Unicode-scalar offset where silence is placed
  public let offset: Int
  
  /// Target silence in milliseconds
  public let lengthMs: Int
  
  /// Named preset token: "comma"(150ms), "semicolon"(250ms), 
  /// "period"(400ms), "em-dash"(600ms), "beat"(1000ms), or nil
  public let named: String?
}
```

---

## Data Flow

### 1. SwiftCompartido Extract Phase

**Location**: `DocumentModelActor.annotateGlosa(document:)`

```swift
// Extract from SwiftData
var fountainNotes: [String] = []
var rawDialogueLines: [(character: String, rawText: String)] = []

for element in document.sortedElements {
  switch element.elementType {
  case .note:
    fountainNotes.append(element.elementText)
  case .dialogue:
    fountainNotes.append(element.elementText)  // Dialogue in notes too
  case .character:
    lastCharacter = element.elementText
  case .dialogue:
    rawDialogueLines.append((character: lastCharacter, rawText: element.elementText))
  default:
    break
  }
}
```

### 2. GlosaCore Compilation

**Location**: `GlosaLineAnnotation.compileAnnotations(fountainNotes:rawDialogueLines:)`

**Pipeline**:
1. **Strip**: Each `rawText` → `spokenText` via `GlosaInlineNotes.strip()`
2. **Parse**: `GlosaParser.parseFountain(notes:)` → `GlosaScore`
3. **Validate**: `GlosaValidator.validate()` → `[GlosaDiagnostic]`
4. **Resolve**: `ScoreResolver.resolveFlat()` → per-line `ResolvedDirectives`
5. **Compose**: `InstructComposer.compose()` → instruct strings
6. **Project**: Internal types → `GlosaLineAnnotation` DTOs

### 3. SwiftCompartido Persistence

**Location**: `DocumentModelActor.annotateGlosa(document:)`

```swift
for (i, element) in dialogueElements.enumerated() {
  guard let dto = annotations[i] else { continue }
  
  element.glosaSpokenText = dto.spokenText
  element.glosaBreathOffsets = dto.breathOffsets
  element.glosaBreathStrengths = dto.breathStrengths
  element.glosaInstruct = dto.instruct
  element.glosaPausePoints = try? JSONEncoder().encode(dto.pausePoints)
}
```

---

## Offset Convention

**Unicode Scalar Boundary Indices**

All offsets (`breathOffsets`, `pausePoints[n].offset`) are `unicodeScalars.count` indices into `spokenText`.

- Offset `n` denotes the boundary **after** the nth Unicode scalar
- Splitting `spokenText.unicodeScalars` at these offsets and reassembling reproduces `spokenText` byte-identically
- Matches the convention from `GlosaInlineNotes` (spec §6.4)

**Example**:
```swift
spokenText = "Hello world"  // 11 scalars
breathOffsets = [5]         // Split after "Hello" (before " world")
pausePoints = [PausePointDTO(offset: 11, lengthMs: 400, named: "period")]
```

---

## Error Handling & Graceful Degradation

### GlosaCore Guarantees

- **Never throws** (currently; signature allows future errors)
- **Empty notes fallback**: `fountainNotes.isEmpty` → empty `CompilationResult`
- **Validation diagnostics**: Errors captured in `GlosaDiagnostic`, not thrown

### SwiftCompartido Handling

**Location**: `DocumentModelActor.annotateGlosa(document:)`

```swift
do {
  let annotations = try compileAnnotations(...)
  // Write to SwiftData
} catch {
  // Graceful degradation: log and leave glosa fields nil
  glosaLog.error("Glosa annotation pass failed; leaving glosa fields nil: \(error)")
}
```

**Critical**: Glosa failure **NEVER aborts import**. All five glosa fields default to `nil` on failure.

---

## SwiftData Schema Integration

### GuionElementModel Fields

Added in SwiftCompartido v7.0.5 (Schema V2):

```swift
@Model
public final class GuionElementModel {
  // ... existing fields ...
  
  /// GLOSA annotation fields (V2 schema)
  public var glosaSpokenText: String? = nil
  public var glosaBreathOffsets: [Int]? = nil
  public var glosaBreathStrengths: [String]? = nil
  public var glosaInstruct: String? = nil
  public var glosaPausePoints: Data? = nil  // JSON-encoded [PausePointDTO]
}
```

### Schema Migration

**V1 → V2**: Lightweight migration adding five optional fields (all default to `nil`)

Consumer apps must include both schema versions:

```swift
enum MyAppMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] {
    [SwiftCompartidoSchemaV1.self, SwiftCompartidoSchemaV2.self]
  }
  static var stages: [MigrationStage] {
    [SwiftCompartidoSchemaV2.migrationStage]
  }
}
```

---

## Architectural Constraints

### glosa-av Side

1. **Zero dependencies**: GlosaCore is Foundation-only
2. **No SwiftData/SwiftUI**: Pure data transformation
3. **Sendable DTOs**: All boundary types are `Codable & Sendable`
4. **No consumer knowledge**: glosa-av has no awareness of SwiftCompartido

### SwiftCompartido Side

1. **Single import point**: Only `DocumentModelActor` imports `GlosaCore`
2. **Optional annotation**: `parseGlosa: Bool` parameter (defaults to `true`)
3. **No glosa-av internal types**: Only DTOs cross the boundary
4. **Actor isolation**: Glosa compilation runs in `DocumentModelActor`'s isolated context

### Decoupling

- **No circular dependency**: glosa-av does not know about SwiftCompartido
- **Version independence**: glosa-av can evolve internal pipeline without breaking SwiftCompartido
- **DTO stability**: `GlosaLineAnnotation` and `PausePointDTO` are the stable API contract

---

## Usage Examples

### SwiftCompartido: Parse with GLOSA

```swift
let actor = DocumentModelActor(modelContainer: container)

// Parse screenplay with glosa annotation (default)
let documentID = try await actor.parseAndSaveDocument(from: url)

// Parse without glosa annotation
let documentID2 = try await actor.parseAndSaveDocument(
  from: url,
  parseGlosa: false
)
```

### Consumer: Read GLOSA Data

```swift
@MainActor
func displayElement(_ element: GuionElementModel) {
  guard element.elementType == .dialogue else { return }
  
  let spokenText = element.glosaSpokenText ?? element.elementText
  let instruct = element.glosaInstruct ?? "(neutral delivery)"
  
  if let pauseData = element.glosaPausePoints,
     let pauses = try? JSONDecoder().decode([PausePointDTO].self, from: pauseData) {
    print("Pause points: \(pauses.count)")
  }
}
```

---

## Future Evolution

### Planned Additions (No Breaking Changes)

1. **Stage Director integration**: SwiftCompartido may add LLM-powered GLOSA generation
2. **Real-time validation**: Live GLOSA linting during screenplay editing
3. **Diagnostic persistence**: Store `GlosaDiagnostic` results in SwiftData

### Breaking Change Risk Assessment

| Change | Risk | Mitigation |
|--------|------|------------|
| Add fields to `GlosaLineAnnotation` | **LOW** | Existing fields are stable; new fields additive |
| Change offset convention | **CRITICAL** | Requires coordinated SwiftVoxAlta + SwiftCompartido update |
| Remove `compileAnnotations()` | **CRITICAL** | This is the public boundary; deprecate instead |
| Internal pipeline refactor | **NONE** | Consumers only see DTOs |

---

## Cross-References

### SwiftCompartido Files

- [`DocumentModelActor.swift`](../Sources/SwiftCompartido/Actors/DocumentModelActor.swift) - Glosa integration point
- [`GuionElementModel.swift`](../Sources/SwiftCompartido/SwiftDataModels/GuionElementModel.swift) - Schema V2 with glosa fields
- [`SwiftCompartidoSchemaV2.swift`](../Sources/SwiftCompartido/Schemas/SwiftCompartidoSchemaV2.swift) - Migration documentation

### glosa-av Files

- [`GlosaLineAnnotation.swift`](https://github.com/intrusive-memory/glosa-av/blob/main/Sources/GlosaCore/GlosaLineAnnotation.swift) - Boundary function + DTOs
- [`GlosaCompiler.swift`](https://github.com/intrusive-memory/glosa-av/blob/main/Sources/GlosaCore/GlosaCompiler.swift) - Internal pipeline entry point
- [`GlosaInlineNotes.swift`](https://github.com/intrusive-memory/glosa-av/blob/main/Sources/GlosaCore/GlosaInlineNotes.swift) - Note stripping logic
- [`AGENTS.md`](https://github.com/intrusive-memory/glosa-av/blob/main/AGENTS.md) - glosa-av project documentation

### External Consumers

- **SwiftVoxAlta**: TTS engine that consumes glosa fields for chunking and delivery
- **Produciesta**: Orchestrates SwiftCompartido → glosa-av → SwiftVoxAlta pipeline

---

## Contact & Ownership

**SwiftCompartido**: Tom Stovall (stovak@gmail.com)  
**glosa-av**: Tom Stovall (stovak@gmail.com)  
**Boundary Coordination**: Update this document when either side changes the API contract
