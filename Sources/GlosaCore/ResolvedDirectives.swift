/// An `Intent` with its resolved arc position within a gradient.
///
/// Wraps a base `Intent` with the computed `arcPosition` that represents
/// how far through the `from -> to` emotional trajectory the current
/// dialogue line sits. 0.0 = pure `from`, 1.0 = pure `to`.
public struct ResolvedIntent: Sendable, Equatable, Codable {

    /// The underlying intent defining the emotional arc.
    public var intent: Intent

    /// Gradient progress through the `from -> to` arc.
    ///
    /// - `0.0`: Pure `from` (beginning of arc).
    /// - `1.0`: Pure `to` (end of arc).
    /// - `0.5`: Midpoint blend (used as fallback for marker intents
    ///   when remaining line count is unknown).
    ///
    /// For **scoped** intents, this is precise:
    /// `Float(lineIndex) / Float(totalLines - 1)`.
    ///
    /// For **marker** intents, this is an approximation via linear
    /// interpolation against remaining lines in scope.
    public var arcPosition: Float

    public init(intent: Intent, arcPosition: Float) {
        self.intent = intent
        self.arcPosition = arcPosition
    }
}

/// The resolved set of active GLOSA directives for a single dialogue line.
///
/// Produced by `ScoreResolver` as it walks through a `GlosaScore`.
/// Each field is `nil` when no corresponding directive is active at
/// that point in the score (e.g., between `</Intent>` and the next
/// `<Intent>`, the `intent` field is `nil` -- neutral delivery).
public struct ResolvedDirectives: Sendable, Equatable, Codable {

    /// The active scene environment, or `nil` if no `SceneContext` is in scope.
    public var sceneContext: SceneContext?

    /// The active emotional trajectory with arc position, or `nil` for neutral delivery.
    public var intent: ResolvedIntent?

    /// The active behavioral constraint for this line's character, or `nil` if none.
    public var constraint: Constraint?

    public init(
        sceneContext: SceneContext? = nil,
        intent: ResolvedIntent? = nil,
        constraint: Constraint? = nil
    ) {
        self.sceneContext = sceneContext
        self.intent = intent
        self.constraint = constraint
    }
}
