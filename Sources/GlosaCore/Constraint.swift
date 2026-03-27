/// Character-level behavioral direction for dialogue performance.
///
/// A `Constraint` sets the performative boundaries for a specific character's
/// dialogue — the *manner* of delivery regardless of emotional content. It applies
/// forward to all subsequent dialogue for the named character until replaced by
/// a new `Constraint` for that character, or until the enclosing `SceneContext` closes.
///
/// Multiple constraints for different characters coexist independently.
public struct Constraint: Sendable, Codable, Equatable {

    /// The character name this constraint applies to.
    public var character: String

    /// Natural-language performance direction (e.g., "angry but speaking softly on purpose").
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
