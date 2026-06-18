import Foundation

/// One facet of a scene's GLOSA annotation, produced by a single pass.
///
/// A pass contributes exactly one case. The orchestrator merges deltas from
/// every pass into a single `SceneAnnotation` before validation. New facets
/// (intents, constraints, scene context, pauses) add cases here as their
/// commands are implemented.
public enum SceneAnnotationDelta: Sendable, Equatable {
  /// `<breath>` phrasing seams for the scene's dialogue lines. Indices are
  /// scene-local dialogue-line indices.
  case breaths([BreathAnnotation])
}

/// A single focused annotation command run over one scene.
///
/// Each conformer does **one** thing — the PHRASING pass adds `<breath>` tags,
/// future passes add scene context, intents, constraints, or pauses. An
/// orchestrator runs an ordered list of passes and merges their deltas.
public protocol ScreenplayPass: Sendable {

  /// Stable identifier, also the CLI subcommand name (e.g. `"phrasing"`).
  var name: String { get }

  /// Annotate one scene and return this pass's single facet.
  ///
  /// - Parameters:
  ///   - scene: The scene segment (starts at its scene heading).
  ///   - sceneIndex: Zero-based scene index in document order.
  ///   - generator: The inference backend.
  ///   - model: Backend model identifier.
  /// - Returns: The delta this pass contributes for the scene.
  func annotate(
    scene: SceneSegment,
    sceneIndex: Int,
    using generator: SceneFacetGenerator,
    model: String
  ) async throws -> SceneAnnotationDelta
}
