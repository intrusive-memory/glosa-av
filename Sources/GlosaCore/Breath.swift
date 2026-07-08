import Foundation

/// Target perceived silence duration for a `Pause`.
///
/// `PauseLength` is the duration type owned by `<pause>` — the deliberate,
/// audible silence element. Named cases are punctuation-mapped presets so
/// writers can reason about pause length without committing to exact
/// millisecond values. The concrete millisecond calibration of each preset
/// lives downstream (SwiftVoxAlta); this type only commits to the relative
/// ordering `comma < semicolon < period < emDash < beat`.
///
/// The `explicit` case carries an exact `TimeInterval` in seconds, sourced
/// from author-provided attributes such as `length="350ms"` or `length="0.4s"`.
/// Its value is always *authored data*, never a measurement from a clock.
public enum PauseLength: Sendable, Equatable, Codable {
  /// Default — ~150 ms perceived pause, the gap a comma would produce.
  case comma

  /// ~250 ms perceived pause.
  case semicolon

  /// ~400 ms perceived pause.
  case period

  /// ~600 ms perceived pause.
  case emDash

  /// ~1000 ms perceived pause.
  case beat

  /// Exact pause duration in seconds. Sourced from `length="<n>ms"` or
  /// `length="<n>s"` author attributes; never measured from a clock.
  case explicit(TimeInterval)

  // MARK: - Codable

  /// Canonical string encoding for each named case. The wire-format token
  /// `em-dash` mirrors the attribute value the writer types in Fountain/FDX.
  private enum Token: String {
    case comma
    case semicolon
    case period
    case emDash = "em-dash"
    case beat
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)

    if let token = Token(rawValue: raw) {
      switch token {
      case .comma: self = .comma
      case .semicolon: self = .semicolon
      case .period: self = .period
      case .emDash: self = .emDash
      case .beat: self = .beat
      }
      return
    }

    if let seconds = Self.parseExplicit(raw) {
      self = .explicit(seconds)
      return
    }

    throw DecodingError.dataCorruptedError(
      in: container,
      debugDescription: "Unrecognized PauseLength value: \(raw)"
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .comma:
      try container.encode(Token.comma.rawValue)
    case .semicolon:
      try container.encode(Token.semicolon.rawValue)
    case .period:
      try container.encode(Token.period.rawValue)
    case .emDash:
      try container.encode(Token.emDash.rawValue)
    case .beat:
      try container.encode(Token.beat.rawValue)
    case .explicit(let seconds):
      // Canonical form: integer milliseconds with `ms` suffix.
      // `.rounded()` (not truncation) is required so 0.35 → "350ms"
      // survives IEEE-754: 0.35 is stored as 0.349999…, and truncating
      // would emit "349ms". Round-trip is `0.35 ↔ "350ms"`.
      let ms = Int((seconds * 1000).rounded())
      try container.encode("\(ms)ms")
    }
  }

  /// Parses an explicit-duration token of the form `<n>ms` or `<n>s` (decimal
  /// allowed for seconds) into a `TimeInterval` in seconds. Returns `nil` if
  /// the token does not match either form.
  private static func parseExplicit(_ raw: String) -> TimeInterval? {
    if raw.hasSuffix("ms") {
      let value = String(raw.dropLast(2))
      if let ms = Int(value) {
        // Dividing an integer ms count by 1000.0 yields the closest-double
        // representation deterministically — `350 / 1000.0 == 0.35` in
        // IEEE-754, which is exactly what `.explicit(0.35)` stores.
        return TimeInterval(ms) / 1000.0
      }
      return nil
    }
    if raw.hasSuffix("s") {
      let value = String(raw.dropLast(1))
      if let seconds = Double(value) {
        return seconds
      }
      return nil
    }
    return nil
  }
}

/// Chunker priority for a breath point, used downstream to trade competing
/// candidate breakpoints against the chunker's character-budget heuristics.
/// Orthogonal to `PauseLength`.
public enum BreathStrength: String, Sendable, Equatable, Codable {
  /// Only chunk here if necessary to fit the budget.
  case weak

  /// Default — chunk here when the run exceeds the budget.
  case medium

  /// Always chunk here regardless of budget.
  case strong
}

/// A single sub-utterance break point inside a dialogue line.
///
/// `Breath` is a positional marker carrying the information the downstream
/// chunker needs to split a long or structurally tangled line into multiple
/// utterances before sending it to a TTS model. It does **not** model audible
/// breath or vocalization; that is a separate axis reserved for future work.
public struct Breath: Sendable, Equatable, Codable {

  /// Index of the enclosing scene (zero-based, in document order). `-1`
  /// represents a breath emitted while no `<SceneContext>` was open —
  /// pathological input that the compiler silently drops.
  public var sceneIndex: Int

  /// Index of the dialogue line within its enclosing scene that this breath
  /// applies to. Scene-local; the compiler maps `(sceneIndex,
  /// dialogueLineIndex)` to an absolute screenplay line index in
  /// `CompilationResult.breathPoints`.
  public var dialogueLineIndex: Int

  /// Character offset within the dialogue line text where the break is
  /// placed. `0` means before the first character; `line.count` means after
  /// the last character (invalid — the validator emits a diagnostic).
  public var characterOffset: Int

  /// Chunker priority. Defaults to `.medium`.
  public var strength: BreathStrength

  /// Freeform audio-intent prompt carried verbatim for the downstream audio
  /// model (the universal `prompt="…"` attribute). GlosaCore never interprets
  /// it — it is transported to the consumer, which forwards it to the audio LLM.
  /// `nil` when no `prompt` attribute was authored.
  public var prompt: String?

  public init(
    sceneIndex: Int,
    dialogueLineIndex: Int,
    characterOffset: Int,
    strength: BreathStrength = .medium,
    prompt: String? = nil
  ) {
    self.sceneIndex = sceneIndex
    self.dialogueLineIndex = dialogueLineIndex
    self.characterOffset = characterOffset
    self.strength = strength
    self.prompt = prompt
  }
}
