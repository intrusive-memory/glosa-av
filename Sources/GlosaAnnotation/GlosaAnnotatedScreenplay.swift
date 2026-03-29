import GlosaCore
import SwiftCompartido

/// A fully annotated screenplay combining parsed elements with their
/// GLOSA directives, instruct strings, diagnostics, and provenance.
///
/// Produced by ``GlosaAnnotatedScreenplay/build(from:compilationResult:)``
/// which maps a ``SwiftCompartido/GuionParsedElementCollection`` and a
/// ``GlosaCore/CompilationResult`` into a single annotated representation.
///
/// Each element in ``annotatedElements`` corresponds 1:1 with the elements
/// in the source ``screenplay``. Dialogue elements carry their compiled
/// instruct and resolved directives; all other elements have `nil` for both.
public struct GlosaAnnotatedScreenplay: Sendable {

  /// The source parsed screenplay.
  public let screenplay: GuionParsedElementCollection

  /// The annotated elements, one per element in the source screenplay.
  ///
  /// Order matches ``screenplay.elements`` exactly.
  public let annotatedElements: [GlosaAnnotatedElement]

  /// The GLOSA score extracted during compilation.
  public let score: GlosaScore

  /// Diagnostics produced during parsing, validation, and compilation.
  public let diagnostics: [GlosaDiagnostic]

  /// Provenance records tracing each instruct back to its source directives.
  public let provenance: [InstructProvenance]

  /// Creates a new annotated screenplay.
  ///
  /// - Parameters:
  ///   - screenplay: The source parsed screenplay.
  ///   - annotatedElements: The annotated element array.
  ///   - score: The GLOSA score.
  ///   - diagnostics: Compilation diagnostics.
  ///   - provenance: Instruct provenance records.
  public init(
    screenplay: GuionParsedElementCollection,
    annotatedElements: [GlosaAnnotatedElement],
    score: GlosaScore,
    diagnostics: [GlosaDiagnostic],
    provenance: [InstructProvenance]
  ) {
    self.screenplay = screenplay
    self.annotatedElements = annotatedElements
    self.score = score
    self.diagnostics = diagnostics
    self.provenance = provenance
  }

  // MARK: - Builder / Factory

  /// Builds a ``GlosaAnnotatedScreenplay`` by mapping dialogue elements in
  /// the parsed screenplay to their corresponding instructs from a
  /// ``CompilationResult``.
  ///
  /// The mapping works by walking the screenplay elements in order and
  /// maintaining a running dialogue index. Each time a `.dialogue` element
  /// is encountered, the dialogue index is incremented and used to look up
  /// the instruct and provenance from the compilation result. Non-dialogue
  /// elements receive `nil` directives and `nil` instruct.
  ///
  /// - Parameters:
  ///   - screenplay: The parsed screenplay with elements to annotate.
  ///   - compilationResult: The result of compiling GLOSA annotations,
  ///     containing per-dialogue-line instructs keyed by dialogue index.
  /// - Returns: A fully annotated screenplay.
  public static func build(
    from screenplay: GuionParsedElementCollection,
    compilationResult: CompilationResult
  ) -> GlosaAnnotatedScreenplay {
    // Build a lookup from dialogue line index to provenance for
    // extracting resolved directives.
    let provenanceByIndex: [Int: InstructProvenance] = Dictionary(
      compilationResult.provenance.map { ($0.lineIndex, $0) },
      uniquingKeysWith: { first, _ in first }
    )

    var annotatedElements: [GlosaAnnotatedElement] = []
    var dialogueIndex = 0

    for element in screenplay.elements {
      if element.elementType == .dialogue {
        let instruct = compilationResult.instructs[dialogueIndex]

        // Reconstruct ResolvedDirectives from provenance if available
        let directives: ResolvedDirectives?
        if let prov = provenanceByIndex[dialogueIndex] {
          directives = ResolvedDirectives(
            sceneContext: prov.sceneContext,
            intent: prov.intent,
            constraint: prov.constraint
          )
        } else if instruct != nil {
          // Instruct exists but no provenance — unlikely but handle gracefully
          directives = nil
        } else {
          directives = nil
        }

        annotatedElements.append(
          GlosaAnnotatedElement(
            element: element,
            directives: directives,
            instruct: instruct
          ))
        dialogueIndex += 1
      } else {
        annotatedElements.append(GlosaAnnotatedElement(element: element))
      }
    }

    // Extract score by re-parsing — or pass it through.
    // Since CompilationResult doesn't carry the score, we create an
    // empty one here. Callers who need the full score should compile
    // separately and inject it.
    let score = GlosaScore()

    return GlosaAnnotatedScreenplay(
      screenplay: screenplay,
      annotatedElements: annotatedElements,
      score: score,
      diagnostics: compilationResult.diagnostics,
      provenance: compilationResult.provenance
    )
  }

  /// Builds a ``GlosaAnnotatedScreenplay`` with an explicit score.
  ///
  /// Use this overload when you have access to the ``GlosaScore`` from
  /// a prior parsing step and want to include it in the annotated result.
  ///
  /// - Parameters:
  ///   - screenplay: The parsed screenplay with elements to annotate.
  ///   - compilationResult: The compiled instructs and diagnostics.
  ///   - score: The GLOSA score extracted during parsing.
  /// - Returns: A fully annotated screenplay with the provided score.
  public static func build(
    from screenplay: GuionParsedElementCollection,
    compilationResult: CompilationResult,
    score: GlosaScore
  ) -> GlosaAnnotatedScreenplay {
    let base = build(from: screenplay, compilationResult: compilationResult)
    return GlosaAnnotatedScreenplay(
      screenplay: base.screenplay,
      annotatedElements: base.annotatedElements,
      score: score,
      diagnostics: base.diagnostics,
      provenance: base.provenance
    )
  }
}
