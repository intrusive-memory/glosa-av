import Foundation
import GlosaCore

/// Structured output representing a scene's GLOSA annotations.
///
/// This is the schema that SwiftBruja's `query(as:)` decodes the LLM's
/// structured response into. Each field maps directly to a GLOSA element
/// type, allowing the LLM to express dramatic analysis in a typed format
/// that the ``StageDirector`` can validate and map back onto screenplay
/// elements.
///
/// The LLM fills in emotion names, direction phrases, pace values, etc.
/// as plain strings -- it never generates raw SGML tags. The serializer
/// handles rendering these fields as GLOSA markup when writing back to
/// Fountain or FDX.
public struct SceneAnnotation: Sendable, Equatable {

  /// The scene's environmental context.
  public var sceneContext: SceneContextAnnotation

  /// The emotional trajectory annotations for beats within this scene.
  public var intents: [IntentAnnotation]

  /// Per-character behavioral constraint annotations.
  public var constraints: [ConstraintAnnotation]

  /// Sub-utterance break-point annotations for dialogue lines in this scene.
  ///
  /// Each entry identifies a character offset within a dialogue line where
  /// the downstream TTS chunker should split the line into a separate
  /// utterance. An empty array means no breath annotations were emitted for
  /// this scene.
  public var breaths: [BreathAnnotation]

  public init(
    sceneContext: SceneContextAnnotation,
    intents: [IntentAnnotation] = [],
    constraints: [ConstraintAnnotation] = [],
    breaths: [BreathAnnotation] = []
  ) {
    self.sceneContext = sceneContext
    self.intents = intents
    self.constraints = constraints
    self.breaths = breaths
  }
}

// MARK: - SceneAnnotation Codable

extension SceneAnnotation: Codable {
  private enum CodingKeys: String, CodingKey {
    case sceneContext
    case intents
    case constraints
    case breaths
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sceneContext = try container.decode(SceneContextAnnotation.self, forKey: .sceneContext)
    intents = try container.decode([IntentAnnotation].self, forKey: .intents)
    constraints = try container.decode([ConstraintAnnotation].self, forKey: .constraints)
    // `breaths` defaults to [] so that JSON produced before this field was
    // introduced (pre-Sortie-9) continues to decode without error.
    breaths = try container.decodeIfPresent([BreathAnnotation].self, forKey: .breaths) ?? []
  }
}

// MARK: - BreathAnnotation

/// A single sub-utterance break-point annotation emitted by the Stage Director.
///
/// The LLM emits one `BreathAnnotation` per `<breath/>` marker it decides to
/// place inside a dialogue line. The downstream serializer renders these as
/// inline `[[<breath/>]]` Fountain notes (or `<glosa:breath/>` FDX elements)
/// at the correct character offsets.
public struct BreathAnnotation: Sendable, Equatable, Codable {

  /// Index of the dialogue line (within the scene) this breath applies to.
  ///
  /// Zero-based. Counts only dialogue lines — action, headings, and
  /// parentheticals are not counted.
  public var dialogueLineIndex: Int

  /// Character offset within the dialogue line text where the break goes.
  ///
  /// `0` = before the first character; `line.count` = after the last
  /// character (invalid — the validator emits a diagnostic). The break is
  /// placed *between* the character at `offset - 1` and the character at
  /// `offset`, so the first chunk ends just before this position and the
  /// second chunk begins here.
  public var characterOffset: Int

  /// Target pause duration hint for the downstream TTS chunker.
  ///
  /// When `nil` the downstream consumer applies the default (`comma`).
  /// Named presets: `comma` (~150 ms), `semicolon` (~250 ms),
  /// `period` (~400 ms), `em-dash` (~600 ms), `beat` (~1000 ms).
  /// Explicit durations are encoded as `"350ms"` or `"0.4s"`.
  public var length: BreathLength?

  /// Chunker priority for this break point.
  ///
  /// When `nil` the downstream consumer applies the default (`medium`).
  /// `weak` — only chunk here if necessary to fit the budget;
  /// `medium` — chunk here when the run exceeds the budget;
  /// `strong` — always chunk here regardless of budget.
  public var strength: BreathStrength?

  public init(
    dialogueLineIndex: Int,
    characterOffset: Int,
    length: BreathLength? = nil,
    strength: BreathStrength? = nil
  ) {
    self.dialogueLineIndex = dialogueLineIndex
    self.characterOffset = characterOffset
    self.length = length
    self.strength = strength
  }
}

// MARK: - Sub-Annotations

/// Annotation for a scene's environmental context.
///
/// Maps to GLOSA's `<SceneContext>` element. The LLM infers location,
/// time, and ambience from the scene heading and action lines.
public struct SceneContextAnnotation: Sendable, Codable, Equatable {

  /// Physical setting (e.g., "cramped office", "open field at night").
  public var location: String

  /// Time of day or temporal context (e.g., "late night", "early morning").
  public var time: String

  /// Background audio or environmental sound, or `nil` if none suggested.
  public var ambience: String?

  public init(location: String, time: String, ambience: String? = nil) {
    self.location = location
    self.time = time
    self.ambience = ambience
  }
}

/// Annotation for an emotional trajectory within a scene.
///
/// Maps to GLOSA's `<Intent>` element. The LLM identifies emotional arcs
/// and specifies the line range they cover.
public struct IntentAnnotation: Sendable, Codable, Equatable {

  /// Starting emotional state.
  public var from: String

  /// Target emotional state.
  public var to: String

  /// Delivery speed (e.g., "slow", "moderate", "fast", "accelerating", "decelerating").
  public var pace: String?

  /// Pause/gap between lines (e.g., "beat", "long pause", "immediate", "overlapping").
  public var spacing: String?

  /// The dialogue line index (within this scene) where this intent begins.
  public var startLine: Int

  /// The dialogue line index (within this scene) where this intent ends (inclusive).
  public var endLine: Int

  /// Whether this intent is scoped (covers a precise range) or a marker.
  public var scoped: Bool

  public init(
    from: String,
    to: String,
    pace: String? = nil,
    spacing: String? = nil,
    startLine: Int,
    endLine: Int,
    scoped: Bool = true
  ) {
    self.from = from
    self.to = to
    self.pace = pace
    self.spacing = spacing
    self.startLine = startLine
    self.endLine = endLine
    self.scoped = scoped
  }
}

/// Annotation for a character's behavioral constraints.
///
/// Maps to GLOSA's `<Constraint>` element. The LLM assigns performance
/// direction for individual characters.
public struct ConstraintAnnotation: Sendable, Codable, Equatable {

  /// The character name this constraint applies to.
  public var character: String

  /// Natural-language performance direction.
  public var direction: String

  /// Vocal register: "low", "mid", "high".
  public var register: String?

  /// Emotional intensity ceiling: "subdued", "moderate", "intense", "explosive".
  public var ceiling: String?

  public init(
    character: String,
    direction: String,
    register: String? = nil,
    ceiling: String? = nil
  ) {
    self.character = character
    self.direction = direction
    self.register = register
    self.ceiling = ceiling
  }
}
