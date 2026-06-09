/// The top-level data model representing a complete set of GLOSA annotations
/// extracted from a screenplay.
///
/// A `GlosaScore` is a hierarchical structure: scenes contain intents, and
/// intents contain constraints and dialogue lines. This mirrors the nesting
/// rules of GLOSA — `SceneContext` is the outermost scope, `Intent` defines
/// emotional arcs within a scene, and `Constraint` governs per-character
/// behavioral limits within those arcs.
public struct GlosaScore: Sendable, Codable, Equatable {

  /// A scene entry bundling a `SceneContext` with its child intents.
  public struct SceneEntry: Sendable, Codable, Equatable {

    /// The scene's environmental context.
    public var context: SceneContext

    /// The intent entries within this scene.
    public var intents: [IntentEntry]

    public init(context: SceneContext, intents: [IntentEntry] = []) {
      self.context = context
      self.intents = intents
    }
  }

  /// An intent entry bundling an `Intent` with its child constraints and dialogue lines.
  public struct IntentEntry: Sendable, Codable, Equatable {

    /// The emotional trajectory for this beat.
    public var intent: Intent

    /// Per-character behavioral constraints active during this intent.
    public var constraints: [Constraint]

    /// The dialogue lines governed by this intent.
    public var dialogueLines: [String]

    public init(
      intent: Intent,
      constraints: [Constraint] = [],
      dialogueLines: [String] = []
    ) {
      self.intent = intent
      self.constraints = constraints
      self.dialogueLines = dialogueLines
    }
  }

  /// The scene entries comprising this score.
  public var scenes: [SceneEntry]

  /// Sub-utterance breath markers collected across the score.
  ///
  /// Each `Breath` carries a scene-local `dialogueLineIndex` and a
  /// `characterOffset` within that line's dialogue text. The compiler later
  /// projects these into absolute screenplay-line keys on
  /// `CompilationResult.breathPoints`.
  public var breaths: [Breath]

  /// Deliberate audible-silence markers collected across the score.
  ///
  /// Each `Pause` carries a scene-local `dialogueLineIndex` and a
  /// `characterOffset` within that line's dialogue text. The compiler later
  /// projects these into absolute screenplay-line keys on
  /// `CompilationResult.pausePoints`.
  public var pauses: [Pause]

  public init(
    scenes: [SceneEntry] = [],
    breaths: [Breath] = [],
    pauses: [Pause] = []
  ) {
    self.scenes = scenes
    self.breaths = breaths
    self.pauses = pauses
  }

  // MARK: - Codable

  private enum CodingKeys: String, CodingKey {
    case scenes
    case breaths
    case pauses
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // `scenes`/`breaths` decode gracefully when absent so previously encoded
    // scores still load; `pauses` follows the same pattern (added later).
    self.scenes = try container.decodeIfPresent([SceneEntry].self, forKey: .scenes) ?? []
    self.breaths = try container.decodeIfPresent([Breath].self, forKey: .breaths) ?? []
    self.pauses = try container.decodeIfPresent([Pause].self, forKey: .pauses) ?? []
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(scenes, forKey: .scenes)
    try container.encode(breaths, forKey: .breaths)
    try container.encode(pauses, forKey: .pauses)
  }
}
