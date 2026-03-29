/// The top-level public API for compiling GLOSA annotations into
/// per-line natural-language instruct strings.
///
/// Chains the full pipeline: GlosaParser -> GlosaValidator -> ScoreResolver -> InstructComposer.
///
/// ```swift
/// let compiler = GlosaCompiler()
/// let result = try compiler.compile(
///     fountainNotes: notes,
///     dialogueLines: lines
/// )
/// // result.instructs[0] -> "Late night in the study, ..."
/// ```
///
/// ## Fallback Behavior
///
/// When `fountainNotes` is empty, returns a `CompilationResult` with an
/// empty `instructs` dictionary, zero diagnostics, and no provenance.
public struct GlosaCompiler: Sendable {

  public init() {}

  /// Compile scored Fountain notes into per-line instruct strings.
  ///
  /// - Parameters:
  ///   - fountainNotes: Array of note strings extracted from `[[ ]]` blocks, in document order.
  ///     May include both GLOSA tags and dialogue text interleaved.
  ///   - dialogueLines: Array of (characterName, text) tuples for all dialogue
  ///     lines in the screenplay, in document order. Includes lines in neutral
  ///     gaps between intents.
  /// - Returns: A `CompilationResult` with per-line instructs, diagnostics, and provenance.
  /// - Throws: Does not currently throw, but the signature allows for future error conditions.
  public func compile(
    fountainNotes: [String],
    dialogueLines: [(character: String, text: String)]
  ) throws -> CompilationResult {
    // Fallback: empty notes -> empty result
    guard !fountainNotes.isEmpty else {
      return CompilationResult()
    }

    let parser = GlosaParser()
    let validator = GlosaValidator()
    let resolver = ScoreResolver()
    let composer = InstructComposer()

    // Step 1: Parse
    let score = parser.parseFountain(notes: fountainNotes)

    // Step 2: Validate (collect diagnostics)
    var diagnostics: [GlosaDiagnostic] = []
    diagnostics.append(contentsOf: validator.validate(notes: fountainNotes))
    diagnostics.append(contentsOf: validator.validate(score: score))

    // Step 3: Resolve directives for each dialogue line
    let dialogueTexts = dialogueLines.map(\.text)
    let characterNames = dialogueLines.map(\.character)
    let resolved = resolver.resolveFlat(
      score: score,
      dialogueLines: dialogueTexts,
      characterNames: characterNames
    )

    // Step 4: Compose instruct strings and build provenance
    var instructs: [Int: String] = [:]
    var provenance: [InstructProvenance] = []

    for (index, directives) in resolved.enumerated() {
      guard let instruct = composer.compose(directives) else {
        continue
      }

      instructs[index] = instruct

      let characterName = index < characterNames.count ? characterNames[index] : ""
      provenance.append(
        InstructProvenance(
          lineIndex: index,
          characterName: characterName,
          sceneContext: directives.sceneContext,
          intent: directives.intent,
          constraint: directives.constraint,
          composedInstruct: instruct
        ))
    }

    return CompilationResult(
      instructs: instructs,
      diagnostics: diagnostics,
      provenance: provenance
    )
  }
}
