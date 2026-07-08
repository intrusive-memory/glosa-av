/// The physical and atmospheric environment for a scene or beat.
///
/// Establishes location, time of day, and optional ambient sound.
/// All dialogue within a `SceneContext` scope inherits this environment.
public struct SceneContext: Sendable, Codable, Equatable {

  /// Physical setting (e.g., "cramped office", "open field at night").
  public var location: String

  /// Time of day or temporal context (e.g., "late night", "early morning", "dusk").
  public var time: String

  /// Background audio or environmental sound (e.g., "rain on windows", "distant traffic").
  public var ambience: String?

  /// Freeform audio-intent prompt carried verbatim for the downstream audio
  /// model (the universal `prompt="…"` attribute). GlosaCore never interprets
  /// it — it is transported to the consumer, which forwards it to the audio LLM.
  /// `nil` when no `prompt` attribute was authored.
  public var prompt: String?

  public init(location: String, time: String, ambience: String? = nil, prompt: String? = nil) {
    self.location = location
    self.time = time
    self.ambience = ambience
    self.prompt = prompt
  }
}
