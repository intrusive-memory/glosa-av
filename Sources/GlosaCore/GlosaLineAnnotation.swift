/// A serializable annotation for a single dialogue line produced by
/// `compileAnnotations(_:rawDialogueLines:)`.
///
/// `GlosaLineAnnotation` is the DTO that crosses the glosa-av / consumer
/// boundary. It carries the notes-stripped spoken text, all breath and pause
/// seam points, and the optional LLM instruct string — everything a TTS
/// pipeline needs to chunk and deliver a dialogue line.
///
/// ## Offset convention
///
/// `breathOffsets` and `pausePoints[n].offset` are `unicodeScalars.count`
/// indices into `spokenText`. An offset of `n` denotes the boundary after
/// the `n`-th Unicode scalar of `spokenText`. Splitting
/// `spokenText.unicodeScalars` at these offsets and reassembling must
/// reproduce `spokenText` byte-identically. This matches the convention
/// established by `GlosaInlineNotes` and the parsers (spec §6.4).
public struct GlosaLineAnnotation: Codable, Sendable {

  /// The notes-stripped prose the actor speaks.
  ///
  /// This is the result of `GlosaInlineNotes.strip(rawText)` — every
  /// `[[<breath …/>]]` and `[[<pause …/>]]` inline note is removed.
  /// Offsets in `breathOffsets` and `pausePoints` index into this string's
  /// `unicodeScalars`.
  public let spokenText: String

  /// Unicode-scalar boundary offsets in `spokenText` where the chunker should
  /// consider inserting a sub-utterance seam (phrasing hint).
  ///
  /// Sorted ascending. Empty when no `<breath/>` markers were present.
  /// An entry of `n` means: split *after* the `n`-th Unicode scalar —
  /// equivalently, the chunk before this offset is
  /// `spokenText.unicodeScalars.prefix(n)`.
  public let breathOffsets: [Int]

  /// Chunker priorities parallel to `breathOffsets`.
  ///
  /// `breathStrengths[i]` is the `.rawValue` of `BreathStrength` for the
  /// breath at `breathOffsets[i]`: one of `"weak"`, `"medium"`, or
  /// `"strong"`. Same count as `breathOffsets`.
  public let breathStrengths: [String]

  /// Optional LLM instruct string for this line.
  ///
  /// `nil` when no active GLOSA directive (scene-context, intent, or
  /// constraint) covered this line — the consumer falls back to the
  /// screenplay parenthetical or neutral delivery.
  public let instruct: String?

  /// Timed-silence seam points for this line.
  ///
  /// Sorted ascending by offset. Empty when no `<pause/>` markers were
  /// present. Each pause forces a chunk seam at its offset and injects an
  /// audible silence of the specified duration.
  public let pausePoints: [PausePointDTO]

  public init(
    spokenText: String,
    breathOffsets: [Int],
    breathStrengths: [String],
    instruct: String?,
    pausePoints: [PausePointDTO]
  ) {
    self.spokenText = spokenText
    self.breathOffsets = breathOffsets
    self.breathStrengths = breathStrengths
    self.instruct = instruct
    self.pausePoints = pausePoints
  }
}

/// A single timed-silence seam point in a serialized `GlosaLineAnnotation`.
///
/// `PausePointDTO` is the wire representation of a `PausePoint`: it replaces
/// the `PauseLength` enum with concrete milliseconds (and an optional name
/// token) so consumers do not need the glosa-av type system to interpret the
/// value.
///
/// ## PauseLength → wire mapping
///
/// Named presets map to fixed calibration values (centralized in
/// `PausePointDTO.milliseconds(for:)` — the single source of truth):
///
/// | `PauseLength` | `lengthMs` | `named`       |
/// |---------------|-----------|---------------|
/// | `.comma`      | 150       | `"comma"`     |
/// | `.semicolon`  | 250       | `"semicolon"` |
/// | `.period`     | 400       | `"period"`    |
/// | `.emDash`     | 600       | `"em-dash"`   |
/// | `.beat`       | 1000      | `"beat"`      |
/// | `.explicit(s)`| rounded   | `nil`         |
///
/// For `.explicit(seconds)`, `lengthMs = Int((seconds * 1000).rounded())` and
/// `named = nil`.
public struct PausePointDTO: Codable, Sendable {

  /// Unicode-scalar boundary offset in `spokenText` where the silence is
  /// placed. Semantics are identical to `GlosaLineAnnotation.breathOffsets`.
  public let offset: Int

  /// Target audible silence in milliseconds.
  ///
  /// For named presets, this is the fixed calibration constant (see class
  /// documentation). For `.explicit(seconds)`, this is
  /// `Int((seconds * 1000).rounded())`.
  public let lengthMs: Int

  /// Wire-format name token for named presets; `nil` for `.explicit` values.
  ///
  /// One of: `"comma"`, `"semicolon"`, `"period"`, `"em-dash"`, `"beat"`,
  /// or `nil`.
  public let named: String?

  public init(offset: Int, lengthMs: Int, named: String?) {
    self.offset = offset
    self.lengthMs = lengthMs
    self.named = named
  }

  // MARK: — PauseLength mapping (single source of truth — OQ-3)

  /// Projects a `PauseLength` into `(lengthMs, named)`.
  ///
  /// This is the **single source of truth** for the OQ-3 mapping. All code
  /// that converts a `PauseLength` to wire values MUST route through here;
  /// no other file should duplicate these constants.
  ///
  /// Named presets are calibrated values agreed with SwiftVoxAlta; the
  /// `em-dash` wire token mirrors the attribute text a writer types.
  static func components(for length: PauseLength) -> (lengthMs: Int, named: String?) {
    switch length {
    case .comma:
      return (150, "comma")
    case .semicolon:
      return (250, "semicolon")
    case .period:
      return (400, "period")
    case .emDash:
      return (600, "em-dash")
    case .beat:
      return (1000, "beat")
    case .explicit(let seconds):
      return (Int((seconds * 1000).rounded()), nil)
    }
  }

  /// Initialises a `PausePointDTO` from a compiler-side `PausePoint`.
  init(from point: PausePoint) {
    let (ms, name) = Self.components(for: point.length)
    self.offset = point.offset
    self.lengthMs = ms
    self.named = name
  }
}

// MARK: - GlosaScriptAnnotation

/// The full result of compiling a screenplay's GLOSA annotations: the per-line
/// annotations plus the document-ordered, script-level standalone events.
///
/// `compileAnnotations(fountainNotes:rawDialogueLines:)` returns only the
/// per-line dictionary for backward compatibility. `compileScript` returns this
/// richer surface so consumers can also see `<include>` and `<shot>` directives,
/// which are not tied to any single dialogue line.
public struct GlosaScriptAnnotation: Codable, Sendable {

  /// Per-line annotations keyed by zero-based dialogue-line index — identical to
  /// the dictionary `compileAnnotations` returns.
  public let lines: [Int: GlosaLineAnnotation]

  /// Audio-include events in ascending `documentIndex` order. Empty when the
  /// screenplay declares no `<include>` directives.
  public let includes: [Include]

  /// Storyboard-shot events in ascending `documentIndex` order. Empty when the
  /// screenplay declares no `<shot>` directives.
  public let shots: [Shot]

  public init(
    lines: [Int: GlosaLineAnnotation],
    includes: [Include],
    shots: [Shot]
  ) {
    self.lines = lines
    self.includes = includes
    self.shots = shots
  }
}

// MARK: - compileAnnotations

/// Compile GLOSA Fountain notes and raw dialogue lines into a per-line
/// annotation dictionary suitable for serialization and cross-boundary
/// consumption.
///
/// `compileAnnotations` is the public façade over `GlosaCompiler.compile()`.
/// It handles the two responsibilities a raw consumer cannot perform itself:
///
/// 1. **Stripping** — each `rawText` is stripped via
///    `GlosaInlineNotes.strip(_:)` before being forwarded to the compiler
///    (the compiler expects already-stripped prose in its `dialogueLines`
///    parameter, matching the convention in `mapBreathsToAbsoluteLines`).
///    The stripped text becomes `GlosaLineAnnotation.spokenText`.
///
/// 2. **Projection** — `CompilationResult`'s internal types (`BreathPoint`,
///    `PausePoint`, `PauseLength`) are projected to the serializable DTO
///    layer (`breathOffsets`, `breathStrengths`, `PausePointDTO`), so
///    consumers never depend on glosa-av's internal type system.
///
/// - Parameters:
///   - fountainNotes: Array of note strings extracted from `[[ ]]` blocks in
///     the screenplay, in document order (passed straight through to the
///     compiler/parser).
///   - rawDialogueLines: Dialogue lines as `(character:, rawText:)` tuples.
///     `rawText` is the *original* text including any inline `[[ … ]]` notes.
///     Stripping is performed internally; the caller must **not** pre-strip.
/// - Returns: A dictionary keyed by zero-based dialogue-line index (matching
///   the order of `rawDialogueLines`). Lines that have no annotation data at
///   all (no instruct, no breaths, no pauses, and stripped text identical to
///   raw text) are **still included** — every line index that exists in
///   `rawDialogueLines` has a corresponding entry so consumers can rely on
///   key presence for indexing.
/// - Throws: Propagates any error from `GlosaCompiler.compile()` (currently
///   none, but the signature is forward-compatible with future error conditions).
public func compileAnnotations(
  fountainNotes: [String],
  rawDialogueLines: [(character: String, rawText: String)]
) throws -> [Int: GlosaLineAnnotation] {
  try compileScript(
    fountainNotes: fountainNotes,
    rawDialogueLines: rawDialogueLines
  ).lines
}

/// Compile GLOSA Fountain notes and raw dialogue lines into the full script
/// annotation — per-line annotations **plus** the document-ordered standalone
/// `<include>` / `<shot>` events.
///
/// This is the superset of `compileAnnotations`: the per-line projection is
/// identical (and `compileAnnotations` is implemented in terms of this function,
/// returning only `.lines`), while `includes` and `shots` surface the
/// script-level block events that have no single owning dialogue line.
///
/// - Parameters:
///   - fountainNotes: Array of note strings extracted from `[[ ]]` blocks in
///     the screenplay, in document order (passed straight through to the
///     compiler/parser). Standalone `<include>`/`<shot>` notes are keyed by
///     their position in this stream.
///   - rawDialogueLines: Dialogue lines as `(character:, rawText:)` tuples.
///     `rawText` is the *original* text including any inline `[[ … ]]` notes;
///     stripping is performed internally (the caller must **not** pre-strip).
/// - Returns: A `GlosaScriptAnnotation` whose `lines` matches
///   `compileAnnotations`, plus `includes`/`shots` in ascending `documentIndex`
///   order.
/// - Throws: Propagates any error from `GlosaCompiler.compile()`.
public func compileScript(
  fountainNotes: [String],
  rawDialogueLines: [(character: String, rawText: String)]
) throws -> GlosaScriptAnnotation {

  // Strip each raw line to obtain the canonical spoken prose. This buffer is
  // what the compiler's internal mappers measured offsets against (they match
  // dialogue lines by string equality against the notes-embedded pipeline, and
  // GlosaParser.parseFountain strips via GlosaInlineNotes.scan before storing
  // dialogue lines in IntentEntry.dialogueLines).
  let strippedLines = rawDialogueLines.map { GlosaInlineNotes.strip($0.rawText) }

  // Forward to the existing compile() API. The compiler expects
  // (character:, text:) tuples where `text` is the notes-stripped prose —
  // i.e. the same buffer the parsers produce and store.
  let compiler = GlosaCompiler()
  let compiledLines = zip(rawDialogueLines, strippedLines).map {
    (character: $0.0.character, text: $0.1)
  }
  let result = try compiler.compile(
    fountainNotes: fountainNotes,
    dialogueLines: compiledLines
  )

  // Project CompilationResult into the DTO layer.
  var annotations: [Int: GlosaLineAnnotation] = [:]

  for (index, strippedText) in strippedLines.enumerated() {
    let breaths = result.breathPoints[index] ?? []
    let pauses = result.pausePoints[index] ?? []

    annotations[index] = GlosaLineAnnotation(
      spokenText: strippedText,
      breathOffsets: breaths.map(\.offset),
      breathStrengths: breaths.map { $0.strength.rawValue },
      instruct: result.instructs[index],
      pausePoints: pauses.map { PausePointDTO(from: $0) }
    )
  }

  return GlosaScriptAnnotation(
    lines: annotations,
    includes: result.includes,
    shots: result.shots
  )
}
