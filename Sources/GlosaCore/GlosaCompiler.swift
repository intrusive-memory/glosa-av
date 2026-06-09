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
    var breathPoints = Self.mapBreathsToAbsoluteLines(
      score: score,
      dialogueLines: dialogueTexts
    )

    // Step 6: Project parsed pauses (scene-local indices) into
    // absolute-line-keyed `PausePoint`s, using the identical projection as
    // breaths.
    let pausePoints = Self.mapPausesToAbsoluteLines(
      score: score,
      dialogueLines: dialogueTexts
    )

    // Step 7: Same-offset collapse (Decision 4). A `<pause/>` always forces a
    // chunk seam at its offset; a co-located `<breath/>` at the exact same
    // `(line, offset)` is redundant. Drop such breaths so there is exactly
    // one chunk seam per offset (the pause wins), and emit an INFO diagnostic
    // for each collapse.
    for (line, pts) in pausePoints {
      let pauseOffsets = Set(pts.map(\.offset))
      guard let breaths = breathPoints[line] else { continue }
      let survivors = breaths.filter { !pauseOffsets.contains($0.offset) }
      let dropped = breaths.count - survivors.count
      if dropped > 0 {
        for breath in breaths where pauseOffsets.contains(breath.offset) {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .info,
              message:
                "<breath/> at line \(line) offset \(breath.offset) coincides with a <pause/>; "
                + "collapsing to a single chunk seam (the pause wins).",
              line: line,
              code: .breathCollapsedByPause
            ))
        }
      }
      if survivors.isEmpty {
        breathPoints[line] = nil
      } else {
        breathPoints[line] = survivors
      }
    }

    return CompilationResult(
      instructs: instructs,
      diagnostics: diagnostics,
      provenance: provenance,
      breathPoints: breathPoints,
      pausePoints: pausePoints
    )
  }

  /// Map every `Breath` in the score to an absolute dialogue-line index,
  /// projecting `(sceneIndex, dialogueLineIndex)` onto the flat
  /// `dialogueLines` array supplied by the caller.
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
  /// **Phase 2 — direct lookup.** Each breath carries its own
  /// `sceneIndex` (populated by the parsers), so projecting it to an
  /// absolute index is a direct table lookup —
  /// `sceneAbsoluteIndices[breath.sceneIndex][breath.dialogueLineIndex]`
  /// — with bounds checks for defensive skipping. No scene-disambiguation
  /// heuristic is required.
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

    // Phase 1 — per-scene absolute-index tables.
    var sceneAbsoluteIndices: [[Int]] = []
    var linePointer = 0

    for scene in score.scenes {
      var sceneTable: [Int] = []
      for intentEntry in scene.intents {
        for intentDialogueLine in intentEntry.dialogueLines {
          var matched = false
          while linePointer < dialogueLines.count {
            if dialogueLines[linePointer] == intentDialogueLine {
              sceneTable.append(linePointer)
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
          }
        }
      }
      sceneAbsoluteIndices.append(sceneTable)
    }

    // Phase 2 — direct lookup using each breath's scene tag.
    var result: [Int: [BreathPoint]] = [:]

    for breath in score.breaths {
      guard
        breath.sceneIndex >= 0,
        breath.sceneIndex < sceneAbsoluteIndices.count
      else {
        // Breath emitted without an enclosing scene, or scene tag points
        // past the end of the parsed scene tree. Drop it silently —
        // there is no absolute line to key against.
        continue
      }
      let table = sceneAbsoluteIndices[breath.sceneIndex]
      guard
        breath.dialogueLineIndex >= 0,
        breath.dialogueLineIndex < table.count
      else { continue }

      let absoluteIndex = table[breath.dialogueLineIndex]
      guard absoluteIndex >= 0 else {
        // Caller's flat stream lacked the target dialogue line.
        continue
      }

      let point = BreathPoint(
        offset: breath.characterOffset,
        strength: breath.strength
      )
      result[absoluteIndex, default: []].append(point)
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

  /// Map every `Pause` in the score to an absolute dialogue-line index,
  /// projecting `(sceneIndex, dialogueLineIndex)` onto the flat
  /// `dialogueLines` array supplied by the caller.
  ///
  /// This is the pause-side mirror of `mapBreathsToAbsoluteLines()` and uses
  /// the identical two-phase projection:
  ///
  /// **Phase 1 — per-scene absolute-index tables.** For each scene, walk the
  /// in-intent dialogue paragraphs and match each one against the caller's
  /// flat `dialogueLines` stream by string equality, advancing past
  /// neutral-gap entries the score does not capture. The result is
  /// `sceneAbsoluteIndices[k][j]` — the absolute index of the j-th in-intent
  /// dialogue paragraph in scene k.
  ///
  /// **Phase 2 — direct lookup.** Each pause carries its own `sceneIndex`, so
  /// projecting it to an absolute index is a direct table lookup with bounds
  /// checks for defensive skipping.
  ///
  /// Lines with no pauses are **omitted** from the returned dictionary so the
  /// dictionary stays minimal for pause-free screenplays, mirroring
  /// `mapBreathsToAbsoluteLines()`.
  internal static func mapPausesToAbsoluteLines(
    score: GlosaScore,
    dialogueLines: [String]
  ) -> [Int: [PausePoint]] {
    guard !score.pauses.isEmpty else { return [:] }

    // Phase 1 — per-scene absolute-index tables.
    var sceneAbsoluteIndices: [[Int]] = []
    var linePointer = 0

    for scene in score.scenes {
      var sceneTable: [Int] = []
      for intentEntry in scene.intents {
        for intentDialogueLine in intentEntry.dialogueLines {
          var matched = false
          while linePointer < dialogueLines.count {
            if dialogueLines[linePointer] == intentDialogueLine {
              sceneTable.append(linePointer)
              linePointer += 1
              matched = true
              break
            }
            linePointer += 1
          }
          if !matched {
            // Caller's flat stream lacks this line — record a sentinel
            // so any pause that would land here is silently skipped.
            sceneTable.append(-1)
          }
        }
      }
      sceneAbsoluteIndices.append(sceneTable)
    }

    // Phase 2 — direct lookup using each pause's scene tag.
    var result: [Int: [PausePoint]] = [:]

    for pause in score.pauses {
      guard
        pause.sceneIndex >= 0,
        pause.sceneIndex < sceneAbsoluteIndices.count
      else {
        // Pause emitted without an enclosing scene, or scene tag points past
        // the end of the parsed scene tree. Drop it silently — there is no
        // absolute line to key against.
        continue
      }
      let table = sceneAbsoluteIndices[pause.sceneIndex]
      guard
        pause.dialogueLineIndex >= 0,
        pause.dialogueLineIndex < table.count
      else { continue }

      let absoluteIndex = table[pause.dialogueLineIndex]
      guard absoluteIndex >= 0 else {
        // Caller's flat stream lacked the target dialogue line.
        continue
      }

      let point = PausePoint(
        offset: pause.characterOffset,
        length: pause.length
      )
      result[absoluteIndex, default: []].append(point)
    }

    // Sort each per-line array ascending by offset for deterministic output,
    // mirroring `mapBreathsToAbsoluteLines()`.
    for (key, points) in result {
      result[key] = points.sorted { $0.offset < $1.offset }
    }

    return result
  }
}
