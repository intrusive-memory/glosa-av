/// A single sub-utterance break point projected onto an absolute dialogue
/// line in the compiled screenplay.
///
/// `BreathPoint` is the compiler-side companion to `Breath` (the parser-side
/// type). Where `Breath` carries a scene-local `dialogueLineIndex`,
/// `BreathPoint` is keyed externally — its container dictionary
/// (`CompilationResult.breathPoints`) supplies the absolute line index, and
/// the point itself only carries the in-line offset and pause attributes
/// needed by the downstream chunker.
///
/// Conformances are limited to `Sendable` and `Equatable` per spec §7.4 — no
/// `Codable` is required here because `CompilationResult` is not itself
/// serialized; the breath data crosses to `GlosaAnnotation` in-process.
public struct BreathPoint: Sendable, Equatable {

  /// Character offset within the dialogue line text where the break is
  /// placed. Measured in `unicodeScalars.count` of the notes-stripped prose,
  /// matching the convention established by the parsers (spec §6.4).
  public let offset: Int

  /// Chunker priority. Inherited verbatim from the source `Breath`. Defaults
  /// match the named-attribute defaults (`.medium`).
  public let strength: BreathStrength

  public init(offset: Int, strength: BreathStrength) {
    self.offset = offset
    self.strength = strength
  }
}

/// A single deliberate audible-silence point projected onto an absolute
/// dialogue line in the compiled screenplay.
///
/// `PausePoint` is the compiler-side companion to `Pause` (the parser-side
/// type). Where `Pause` carries a scene-local `dialogueLineIndex`,
/// `PausePoint` is keyed externally — its container dictionary
/// (`CompilationResult.pausePoints`) supplies the absolute line index, and
/// the point itself only carries the in-line offset and the silence duration
/// needed by the downstream chunker.
///
/// Conformances are limited to `Sendable` and `Equatable`, mirroring
/// `BreathPoint` — no `Codable` is required here because `CompilationResult`
/// is not itself serialized; the pause data crosses to `GlosaAnnotation`
/// in-process.
public struct PausePoint: Sendable, Equatable {

  /// Character offset within the dialogue line text where the silence is
  /// placed. Measured in `unicodeScalars.count` of the notes-stripped prose,
  /// matching the convention established by the parsers (spec §6.4).
  public let offset: Int

  /// Target perceived silence duration. Inherited verbatim from the source
  /// `Pause`. Defaults to the named-attribute default (`.period`).
  public let length: PauseLength

  public init(offset: Int, length: PauseLength) {
    self.offset = offset
    self.length = length
  }
}

/// The result of compiling GLOSA annotations into per-line instruct strings.
///
/// Produced by `GlosaCompiler.compile()`, this struct contains:
/// - Per-line instruct strings keyed by dialogue line index.
///   Lines with no active directives have no entry (fallback to parenthetical).
/// - Diagnostics from validation and resolution.
/// - Provenance records tracing each instruct back to its source directives.
/// - Per-line breath points keyed by absolute dialogue-line index.
public struct CompilationResult: Sendable {

  /// Per-line instruct strings, keyed by dialogue line index.
  ///
  /// Lines with no active directives have no entry — a missing key
  /// means neutral delivery (fall back to parenthetical if present).
  public let instructs: [Int: String]

  /// Diagnostics produced during validation and compilation.
  ///
  /// Includes warnings about unclosed tags, missing attributes,
  /// structural issues, and informational messages.
  public let diagnostics: [GlosaDiagnostic]

  /// Provenance records for every line that received an instruct string.
  ///
  /// Each record traces the instruct back to its source SceneContext,
  /// Intent, and Constraint directives, enabling auditing and debugging.
  public let provenance: [InstructProvenance]

  /// Per-line breath points, keyed by **absolute dialogue-line index**
  /// within the screenplay (the same indexing space as `instructs`).
  ///
  /// Each value is a non-empty array of `BreathPoint`s sorted ascending by
  /// `offset`. Lines with no breaths are represented by **omitting the key**
  /// — `breathPoints[lineIndex] == nil` and the contract-equivalent
  /// `breathPoints[lineIndex] ?? []` both mean "no chunk hints for this
  /// line." Spec §7.4 permits either form; this implementation uses key
  /// omission so the dictionary stays minimal for the common case of
  /// breath-free screenplays.
  public let breathPoints: [Int: [BreathPoint]]

  /// Per-line pause points, keyed by **absolute dialogue-line index**
  /// within the screenplay (the same indexing space as `instructs`).
  ///
  /// Each value is a non-empty array of `PausePoint`s sorted ascending by
  /// `offset`. Lines with no pauses are represented by **omitting the key**
  /// — `pausePoints[lineIndex] == nil` and the contract-equivalent
  /// `pausePoints[lineIndex] ?? []` both mean "no audible silences for this
  /// line." This implementation uses key omission so the dictionary stays
  /// minimal for the common case of pause-free screenplays, mirroring
  /// `breathPoints`.
  public let pausePoints: [Int: [PausePoint]]

  /// Standalone audio-include events, in ascending `documentIndex` order.
  ///
  /// Unlike `breathPoints`/`pausePoints`, includes are not keyed by
  /// dialogue-line index — they are document-positional events carried straight
  /// through from `GlosaScore.includes`. Empty when the screenplay declares no
  /// `<include>` directives.
  public let includes: [Include]

  /// Standalone storyboard-shot events, in ascending `documentIndex` order.
  /// Mirrors `includes`; carried straight through from `GlosaScore.shots`.
  /// Empty when the screenplay declares no `<shot>` directives.
  public let shots: [Shot]

  public init(
    instructs: [Int: String] = [:],
    diagnostics: [GlosaDiagnostic] = [],
    provenance: [InstructProvenance] = [],
    breathPoints: [Int: [BreathPoint]] = [:],
    pausePoints: [Int: [PausePoint]] = [:],
    includes: [Include] = [],
    shots: [Shot] = []
  ) {
    self.instructs = instructs
    self.diagnostics = diagnostics
    self.provenance = provenance
    self.breathPoints = breathPoints
    self.pausePoints = pausePoints
    self.includes = includes
    self.shots = shots
  }
}
