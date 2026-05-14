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

    // Step 5: Project parsed breaths (scene-local indices) into
    // absolute-line-keyed `BreathPoint`s. The parsers emit `Breath` values
    // whose `dialogueLineIndex` counts in-intent dialogue paragraphs within
    // the enclosing scene; the compiler's contract is that
    // `breathPoints` is keyed by absolute dialogue-line index — the same
    // indexing space as `instructs` and the caller's `dialogueLines`
    // array, which interleaves in-intent and neutral-gap lines.
    let breathPoints = Self.mapBreathsToAbsoluteLines(
      score: score,
      dialogueLines: dialogueTexts
    )

    return CompilationResult(
      instructs: instructs,
      diagnostics: diagnostics,
      provenance: provenance,
      breathPoints: breathPoints
    )
  }

  /// Map every `Breath` in the score to an absolute dialogue-line index,
  /// projecting scene-local indices onto the flat `dialogueLines` array
  /// supplied by the caller.
  ///
  /// ## Mapping strategy
  ///
  /// The mapping proceeds in two phases:
  ///
  /// **Phase 1 — per-scene absolute-index tables.** For each scene, walk
  /// the in-intent dialogue paragraphs (`scene.intents.flatMap {
  /// $0.dialogueLines }`) and match each one against the caller's flat
  /// `dialogueLines` stream by string equality, advancing past
  /// neutral-gap entries that the score does not capture. This is the
  /// same matching algorithm `ScoreResolver.resolveFlat` uses, and the
  /// result is `sceneAbsoluteIndices[k][j]` — the absolute index of the
  /// j-th in-intent dialogue paragraph in scene k.
  ///
  /// **Phase 2 — assign each breath to a scene.** The parser emits
  /// breaths in document order, but `Breath.dialogueLineIndex` is
  /// scene-local and `Breath` itself carries no scene tag. To recover
  /// the scene, we walk breaths in document order and, for each, find
  /// the smallest scene cursor whose table has room for the breath's
  /// scene-local index AND whose corresponding dialogue line is long
  /// enough to host the breath's `characterOffset`. The offset
  /// bounds-check is the disambiguating signal: a scene whose dialogue
  /// line at index `j` is shorter than the breath's offset cannot be the
  /// breath's home scene, so we advance.
  ///
  /// This handles the common cases correctly:
  /// - Single-scene screenplay — the scene cursor stays at 0.
  /// - Bishop in scene 2 with a short prior dialogue line in scene 1 —
  ///   offset 20/31/43 don't fit the short line, advance to scene 2.
  /// - Scene with no breaths followed by scene with breaths — same
  ///   bounds-check skip-ahead applies.
  ///
  /// Known limitation: if scene K has dialogue line(s) AT scene-local
  /// index J that are long enough to host a breath's offset, but the
  /// breath in fact came from a later scene with an identically-indexed,
  /// long-enough line, the algorithm cannot distinguish the two. In
  /// practice this requires both scenes to have ≥ J+1 dialogue lines
  /// AND the J-th line of scene K to be at least `breath.characterOffset`
  /// scalars long; pathological for typical screenplays. If observed, the
  /// fix is upstream — `Breath` would need to carry a scene index.
  ///
  /// Lines with no breaths are **omitted** from the returned dictionary
  /// (spec §7.4 permits either omission or empty array; this
  /// implementation uses omission so the dictionary stays minimal for
  /// breath-free screenplays).
  internal static func mapBreathsToAbsoluteLines(
    score: GlosaScore,
    dialogueLines: [String]
  ) -> [Int: [BreathPoint]] {
    guard !score.breaths.isEmpty else { return [:] }

    // Phase 1 — per-scene absolute-index tables and corresponding dialogue
    // line text (kept side-by-side for the offset bounds-check below).
    var sceneAbsoluteIndices: [[Int]] = []
    var sceneDialogueTexts: [[String]] = []
    var linePointer = 0

    for scene in score.scenes {
      var sceneTable: [Int] = []
      var sceneTexts: [String] = []
      for intentEntry in scene.intents {
        for intentDialogueLine in intentEntry.dialogueLines {
          var matched = false
          while linePointer < dialogueLines.count {
            if dialogueLines[linePointer] == intentDialogueLine {
              sceneTable.append(linePointer)
              sceneTexts.append(intentDialogueLine)
              linePointer += 1
              matched = true
              break
            }
            linePointer += 1
          }
          if !matched {
            // Caller's flat stream lacks this line — record a sentinel
            // so any breath that would land here is silently skipped.
            sceneTable.append(-1)
            sceneTexts.append(intentDialogueLine)
          }
        }
      }
      sceneAbsoluteIndices.append(sceneTable)
      sceneDialogueTexts.append(sceneTexts)
    }

    // Phase 2 — assign each breath to a scene. The scene cursor only
    // moves forward (document order is preserved); within a scene we
    // also enforce monotonically-non-decreasing scene-local indices so a
    // breath that "looks back" must instead belong to a later scene.
    var result: [Int: [BreathPoint]] = [:]
    var sceneCursor = 0
    var lastIndexInScene: Int = -1

    for breath in score.breaths {
      // Advance the scene cursor until a scene is found whose dialogue
      // structure can host this breath. The check has two parts:
      //   (1) the scene has at least `dialogueLineIndex + 1` in-intent
      //       dialogue paragraphs, AND
      //   (2) the target paragraph is at least `characterOffset` Unicode
      //       scalars long (the offset can equal the length — that
      //       represents a marker after the final character), AND
      //   (3) the scene-local index is not a backward jump from the
      //       last consumed breath in the current scene.
      while sceneCursor < sceneAbsoluteIndices.count {
        let table = sceneAbsoluteIndices[sceneCursor]
        let texts = sceneDialogueTexts[sceneCursor]

        let inBounds =
          breath.dialogueLineIndex >= 0
          && breath.dialogueLineIndex < table.count
        let offsetFits: Bool = {
          guard inBounds else { return false }
          let lineLength =
            texts[breath.dialogueLineIndex].unicodeScalars.count
          return breath.characterOffset >= 0
            && breath.characterOffset <= lineLength
        }()
        let monotonic = breath.dialogueLineIndex >= lastIndexInScene

        if inBounds && offsetFits && monotonic {
          break
        }
        sceneCursor += 1
        lastIndexInScene = -1
      }
      guard sceneCursor < sceneAbsoluteIndices.count else { break }

      let absoluteIndex =
        sceneAbsoluteIndices[sceneCursor][breath.dialogueLineIndex]
      guard absoluteIndex >= 0 else {
        // Caller's flat stream lacked the target dialogue line. Skip
        // this breath; the dictionary will not key it.
        continue
      }

      let point = BreathPoint(
        offset: breath.characterOffset,
        length: breath.length,
        strength: breath.strength
      )
      result[absoluteIndex, default: []].append(point)
      lastIndexInScene = breath.dialogueLineIndex
    }

    // Sort each per-line array ascending by offset. Spec §7.4 (and
    // every downstream snapshot test in WU4/WU5/WU7) relies on this
    // ordering being deterministic regardless of how authors interleave
    // inline notes — though the parsers' regex scan happens to emit in
    // ascending order already for inline-note placement, an
    // `after="…"` fallback breath can land anywhere relative to the
    // inline-note breaths in the same line.
    for (key, points) in result {
      result[key] = points.sorted { $0.offset < $1.offset }
    }

    return result
  }
}
