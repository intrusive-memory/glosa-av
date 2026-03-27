/// The emotional trajectory and delivery pacing for a dialogue beat.
///
/// An `Intent` defines a gradient from one emotional state (`from`) to another (`to`)
/// across the affected dialogue lines. When **scoped** (with a closing tag), the arc
/// covers exactly the enclosed lines and gradient position is precise. When used as
/// a **marker** (no closing tag), the arc applies forward until the next `Intent`
/// or the enclosing `SceneContext` closes.
///
/// After a scoped `Intent` closes, delivery returns to neutral until the next
/// `Intent` appears. Intents do not nest.
public struct Intent: Sendable, Codable, Equatable {

    /// Starting emotional state (e.g., "calm", "frustrated", "guarded").
    public var from: String

    /// Target emotional state (e.g., "angry", "resigned", "vulnerable").
    public var to: String

    /// Delivery speed: "slow", "moderate", "fast", "accelerating", "decelerating".
    public var pace: String?

    /// Pause/gap between lines (e.g., "beat", "long pause", "immediate", "overlapping").
    public var spacing: String?

    /// Whether this intent is scoped (has a closing tag) or a forward-applying marker.
    public var scoped: Bool

    /// The number of dialogue lines enclosed by a scoped intent.
    /// `nil` for marker intents (line count unknown at declaration time).
    public var lineCount: Int?

    public init(
        from: String,
        to: String,
        pace: String? = nil,
        spacing: String? = nil,
        scoped: Bool = false,
        lineCount: Int? = nil
    ) {
        self.from = from
        self.to = to
        self.pace = pace
        self.spacing = spacing
        self.scoped = scoped
        self.lineCount = lineCount
    }
}
