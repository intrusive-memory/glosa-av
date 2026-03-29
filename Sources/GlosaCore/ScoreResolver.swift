/// A stateful iterator that walks through a `GlosaScore` and resolves
/// the active directives for each dialogue line.
///
/// The resolver tracks:
/// - The current `SceneContext` (set by `<SceneContext>`, cleared by `</SceneContext>`).
/// - The active `Intent` with computed arc position (set by `<Intent>`, cleared by `</Intent>` or scope end).
/// - A per-character `Constraint` map (each character's constraint is independent;
///   all expire when the enclosing `SceneContext` closes).
///
/// ## Gradient Calculation
///
/// **Scoped Intents** (`scoped == true`, `lineCount` known):
/// ```
/// arcPosition = Float(lineIndex) / Float(totalLines - 1)
/// ```
/// Line 0 = 0.0 (pure `from`), last line = 1.0 (pure `to`).
/// Single-line intents always produce `arcPosition = 0.0`.
///
/// **Marker Intents** (`scoped == false`, `lineCount == nil`):
/// Linear interpolation against the total dialogue lines collected under that
/// marker intent. If the total is known (from the parsed score), the formula
/// is the same as scoped. If unknown, a steady 0.5 blend is used.
///
/// ## Neutral Delivery
///
/// After a scoped `</Intent>` closes, `ResolvedDirectives.intent` is `nil`
/// until the next `<Intent>` appears. Dialogue lines in this gap receive
/// neutral delivery (no emotional arc).
///
/// ## Per-Character Constraints
///
/// Each `<Constraint character="X">` replaces only character X's previous
/// constraint. Multiple characters' constraints coexist independently.
/// All constraints expire when their enclosing `SceneContext` closes.
public struct ScoreResolver: Sendable {

  public init() {}

  /// Resolve the active directives for every dialogue line in a `GlosaScore`.
  ///
  /// The returned array has one `ResolvedDirectives` per dialogue line,
  /// in the same document order that dialogue lines appear within the score.
  /// The companion `characterNames` array provides the character name for
  /// each line, enabling per-character constraint lookup.
  ///
  /// - Parameters:
  ///   - score: The parsed GLOSA score to resolve.
  ///   - characterNames: An array of character names corresponding to each
  ///     dialogue line in document order. If provided, constraints are looked
  ///     up per-character. If `nil`, constraints are not resolved.
  /// - Returns: An array of `ResolvedDirectives`, one per dialogue line.
  public func resolve(
    score: GlosaScore,
    characterNames: [String]? = nil
  ) -> [ResolvedDirectives] {
    var results: [ResolvedDirectives] = []
    var globalLineIndex = 0

    for scene in score.scenes {
      let sceneContext = scene.context
      var constraintMap: [String: Constraint] = [:]

      // Track intents and the neutral gaps between them.
      // The GlosaScore structure groups dialogue under IntentEntries,
      // but neutral lines (between intents) are NOT captured in the score.
      // So we iterate intent entries and resolve their dialogue lines.
      // Neutral gaps must be handled by the caller who knows about
      // lines that fall outside any intent.

      for intentEntry in scene.intents {
        let intent = intentEntry.intent
        let totalLines = intentEntry.dialogueLines.count

        // Accumulate constraints from this intent entry.
        // Each constraint replaces only its character's previous one.
        for constraint in intentEntry.constraints {
          constraintMap[constraint.character] = constraint
        }

        // Resolve each dialogue line under this intent.
        for (lineIndex, _) in intentEntry.dialogueLines.enumerated() {
          let arcPosition = computeArcPosition(
            intent: intent,
            lineIndex: lineIndex,
            totalLines: totalLines
          )

          let resolvedIntent = ResolvedIntent(
            intent: intent,
            arcPosition: arcPosition
          )

          // Look up constraint for this line's character.
          let constraint: Constraint?
          if let names = characterNames, globalLineIndex < names.count {
            let characterName = names[globalLineIndex]
            constraint = constraintMap[characterName]
          } else {
            constraint = nil
          }

          results.append(
            ResolvedDirectives(
              sceneContext: sceneContext,
              intent: resolvedIntent,
              constraint: constraint
            ))

          globalLineIndex += 1
        }
      }
    }

    return results
  }

  /// Resolve directives for a flat sequence of dialogue lines, where some lines
  /// may fall in neutral gaps (outside any Intent scope).
  ///
  /// This method walks the score's structure and produces a `ResolvedDirectives`
  /// for every dialogue line in the `dialogueLines` array, including lines that
  /// fall between intents (which get `nil` intent -- neutral delivery).
  ///
  /// - Parameters:
  ///   - score: The parsed GLOSA score.
  ///   - dialogueLines: All dialogue lines in document order, including those
  ///     in neutral gaps between intents.
  ///   - characterNames: Character names corresponding to each dialogue line.
  /// - Returns: An array of `ResolvedDirectives`, one per dialogue line.
  public func resolveFlat(
    score: GlosaScore,
    dialogueLines: [String],
    characterNames: [String]
  ) -> [ResolvedDirectives] {
    var results: [ResolvedDirectives] = []
    var linePointer = 0

    for scene in score.scenes {
      let sceneContext = scene.context
      var constraintMap: [String: Constraint] = [:]

      // Apply any scene-level constraints that appear before the first intent.
      // These are found on the first intent entry's constraints if they were
      // carried forward by the parser.

      for intentEntry in scene.intents {
        let intent = intentEntry.intent
        let totalLines = intentEntry.dialogueLines.count

        // Accumulate constraints.
        for constraint in intentEntry.constraints {
          constraintMap[constraint.character] = constraint
        }

        // Match dialogue lines from the flat list to this intent's lines.
        for (intentLineIndex, intentDialogueLine) in intentEntry.dialogueLines.enumerated() {
          // Advance the line pointer through any neutral lines
          // (lines that don't match the current intent's dialogue).
          while linePointer < dialogueLines.count {
            let flatLine = dialogueLines[linePointer]
            if flatLine == intentDialogueLine {
              break
            }
            // This line is in a neutral gap.
            let characterName = characterNames[linePointer]
            let constraint = constraintMap[characterName]
            results.append(
              ResolvedDirectives(
                sceneContext: sceneContext,
                intent: nil,
                constraint: constraint
              ))
            linePointer += 1
          }

          guard linePointer < dialogueLines.count else { break }

          // This line matches the intent's dialogue line.
          let arcPosition = computeArcPosition(
            intent: intent,
            lineIndex: intentLineIndex,
            totalLines: totalLines
          )

          let resolvedIntent = ResolvedIntent(
            intent: intent,
            arcPosition: arcPosition
          )

          let characterName = characterNames[linePointer]
          let constraint = constraintMap[characterName]

          results.append(
            ResolvedDirectives(
              sceneContext: sceneContext,
              intent: resolvedIntent,
              constraint: constraint
            ))

          linePointer += 1
        }
      }

      // After all intents in a scene, any remaining lines before
      // the next scene are in the scene context but with no intent.
      // (SceneContext close resets everything -- handled by the next
      // scene iteration starting with a fresh constraintMap.)
    }

    // Any remaining lines after all scenes get nil for everything.
    while linePointer < dialogueLines.count {
      results.append(ResolvedDirectives())
      linePointer += 1
    }

    return results
  }

  // MARK: - Arc Position Calculation

  /// Compute the arc position for a dialogue line within an intent.
  ///
  /// - Parameters:
  ///   - intent: The intent defining the arc.
  ///   - lineIndex: Zero-based index of this line within the intent's dialogue.
  ///   - totalLines: Total number of dialogue lines in this intent.
  /// - Returns: A Float in [0.0, 1.0] representing gradient progress.
  private func computeArcPosition(
    intent: Intent,
    lineIndex: Int,
    totalLines: Int
  ) -> Float {
    if intent.scoped {
      // Scoped intent: precise gradient.
      return scopedArcPosition(lineIndex: lineIndex, totalLines: totalLines)
    } else {
      // Marker intent: use dialogue count if known, else steady 0.5.
      return markerArcPosition(
        lineIndex: lineIndex,
        totalLines: totalLines,
        lineCount: intent.lineCount
      )
    }
  }

  /// Precise gradient for scoped intents.
  ///
  /// `arcPosition = Float(lineIndex) / Float(totalLines - 1)`
  /// Single-line intents produce 0.0.
  private func scopedArcPosition(lineIndex: Int, totalLines: Int) -> Float {
    guard totalLines > 1 else { return 0.0 }
    return Float(lineIndex) / Float(totalLines - 1)
  }

  /// Approximate gradient for marker intents.
  ///
  /// If the total line count is known (from parsed dialogue), uses the same
  /// formula as scoped intents for linear interpolation.
  /// If unknown, returns a steady 0.5 blend.
  private func markerArcPosition(
    lineIndex: Int,
    totalLines: Int,
    lineCount: Int?
  ) -> Float {
    // For marker intents, we know the total dialogue lines collected
    // under this marker from the parser. Use linear interpolation.
    let effectiveTotal = lineCount ?? totalLines
    guard effectiveTotal > 1 else {
      // Single line or unknown: steady 0.5 blend.
      return totalLines > 1
        ? Float(lineIndex) / Float(totalLines - 1)
        : 0.5
    }
    return Float(lineIndex) / Float(effectiveTotal - 1)
  }
}
