/// Provenance record tracing a compiled instruct string back to its
/// source directives.
///
/// Each `InstructProvenance` records the dialogue line index, the
/// speaking character, the active directives that contributed to the
/// instruct, and the final composed instruct string. This enables
/// auditing, debugging, and round-trip verification of the compilation
/// pipeline.
public struct InstructProvenance: Sendable, Codable {

  /// The zero-based index of the dialogue line in document order.
  public var lineIndex: Int

  /// The character name speaking this dialogue line.
  public var characterName: String

  /// The active scene context at this line, if any.
  public var sceneContext: SceneContext?

  /// The active resolved intent (with arc position) at this line, if any.
  public var intent: ResolvedIntent?

  /// The active constraint for this character at this line, if any.
  public var constraint: Constraint?

  /// The final composed instruct string for this line.
  public var composedInstruct: String

  public init(
    lineIndex: Int,
    characterName: String,
    sceneContext: SceneContext? = nil,
    intent: ResolvedIntent? = nil,
    constraint: Constraint? = nil,
    composedInstruct: String
  ) {
    self.lineIndex = lineIndex
    self.characterName = characterName
    self.sceneContext = sceneContext
    self.intent = intent
    self.constraint = constraint
    self.composedInstruct = composedInstruct
  }
}
