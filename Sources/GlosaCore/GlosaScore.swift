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

    public init(scenes: [SceneEntry] = []) {
        self.scenes = scenes
    }
}
