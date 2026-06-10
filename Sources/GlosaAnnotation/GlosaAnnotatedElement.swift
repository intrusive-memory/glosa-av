import GlosaCore
import SwiftCompartido

/// A screenplay element annotated with its resolved GLOSA directives,
/// compiled instruct string, sub-utterance breath points, and deliberate
/// audible-silence pause points.
///
/// Wraps a ``SwiftCompartido/GuionElement`` together with the active
/// ``GlosaCore/ResolvedDirectives``, the natural-language instruct
/// string produced by the GLOSA compiler for that element's position
/// in the screenplay, any ``GlosaCore/BreathPoint``s compiled for
/// that dialogue line, and any ``GlosaCore/PausePoint``s compiled for
/// that dialogue line.
///
/// For non-dialogue elements (action, scene headings, transitions, etc.)
/// or dialogue elements that fall in a neutral gap (no active GLOSA
/// directives), both `directives` and `instruct` are `nil`.
/// Non-dialogue elements always have empty `breathPoints` and `pausePoints`
/// arrays.
public struct GlosaAnnotatedElement: Sendable {

  /// The underlying screenplay element.
  public let element: GuionElement

  /// The resolved GLOSA directives active at this element's position,
  /// or `nil` if the element is non-dialogue or has no active directives.
  public let directives: ResolvedDirectives?

  /// The compiled natural-language instruct string for this element,
  /// or `nil` if the element is non-dialogue or has no active directives.
  public let instruct: String?

  /// Sub-utterance break points for this dialogue line, sorted ascending
  /// by `offset`.
  ///
  /// For dialogue elements, each entry identifies a position within the
  /// line's text where the downstream chunker may split the utterance
  /// before sending it to a TTS model. The array mirrors
  /// ``CompilationResult/breathPoints`` for the corresponding absolute
  /// dialogue-line index.
  ///
  /// Non-dialogue elements (scene headings, action lines, parentheticals,
  /// transitions, character cues) always carry an empty array. Dialogue
  /// elements with no breath annotations also carry an empty array.
  public let breathPoints: [BreathPoint]

  /// Deliberate audible-silence points for this dialogue line, sorted
  /// ascending by `offset`.
  ///
  /// For dialogue elements, each entry identifies a position within the
  /// line's text where the downstream TTS renderer must insert an audible
  /// silence of the specified `length`. The array mirrors
  /// ``CompilationResult/pausePoints`` for the corresponding absolute
  /// dialogue-line index.
  ///
  /// Non-dialogue elements (scene headings, action lines, parentheticals,
  /// transitions, character cues) always carry an empty array. Dialogue
  /// elements with no pause annotations also carry an empty array.
  public let pausePoints: [PausePoint]

  /// Creates a new annotated element.
  ///
  /// - Parameters:
  ///   - element: The screenplay element being annotated.
  ///   - directives: The resolved GLOSA directives, or `nil`.
  ///   - instruct: The compiled instruct string, or `nil`.
  ///   - breathPoints: Sub-utterance break points, sorted ascending by offset.
  ///     Defaults to `[]` for non-dialogue elements and dialogue lines with
  ///     no breath annotations.
  ///   - pausePoints: Deliberate audible-silence points, sorted ascending by
  ///     offset. Defaults to `[]` for non-dialogue elements and dialogue lines
  ///     with no pause annotations.
  public init(
    element: GuionElement,
    directives: ResolvedDirectives? = nil,
    instruct: String? = nil,
    breathPoints: [BreathPoint] = [],
    pausePoints: [PausePoint] = []
  ) {
    self.element = element
    self.directives = directives
    self.instruct = instruct
    self.breathPoints = breathPoints
    self.pausePoints = pausePoints
  }
}
