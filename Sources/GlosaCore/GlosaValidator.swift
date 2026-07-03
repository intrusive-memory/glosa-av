import Foundation

/// Performs well-formedness checks on GLOSA annotations.
///
/// The validator examines raw note strings (or tag structures) and produces
/// `GlosaDiagnostic` messages for issues that may affect compilation or output quality.
///
/// Checks include:
/// - `SceneContext` must have a closing tag
/// - `Intent` nesting is forbidden (no Intent inside Intent)
/// - `Constraint` must have `character` and `direction` attributes
/// - `SceneContext` must have `location` and `time` attributes
/// - `<breath/>` elements: out-of-dialogue placement, duplicate offsets, missing-breath-on-long-line
public struct GlosaValidator: Sendable {

  public init() {}

  /// Validate an array of Fountain note strings for well-formedness.
  ///
  /// - Parameter notes: Array of note contents from `[[ ]]` blocks in document order.
  /// - Returns: Array of diagnostics describing any issues found.
  public func validate(notes: [String]) -> [GlosaDiagnostic] {
    var diagnostics: [GlosaDiagnostic] = []
    var sceneContextOpen = false
    var sceneContextOpenLine: Int?
    var intentOpen = false
    var intentOpenLine: Int?

    for (index, note) in notes.enumerated() {
      let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
      let lineNumber = index + 1

      // Check for SceneContext closing
      if trimmed.contains("</SceneContext>") {
        if !sceneContextOpen {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .warning,
              message: "Closing </SceneContext> without matching opening tag",
              line: lineNumber
            ))
        }
        sceneContextOpen = false
        sceneContextOpenLine = nil
        // SceneContext close also implicitly closes any open intent
        intentOpen = false
        intentOpenLine = nil
        continue
      }

      // Check for Intent closing
      if trimmed.contains("</Intent>") {
        if !intentOpen {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .warning,
              message: "Closing </Intent> without matching opening tag",
              line: lineNumber
            ))
        }
        intentOpen = false
        intentOpenLine = nil
        continue
      }

      // Check for SceneContext opening
      if trimmed.contains("<SceneContext") && !trimmed.contains("</SceneContext") {
        if sceneContextOpen {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .warning,
              message:
                "Opening <SceneContext> while previous SceneContext is still open (unclosed at line \(sceneContextOpenLine ?? 0))",
              line: lineNumber
            ))
        }
        sceneContextOpen = true
        sceneContextOpenLine = lineNumber

        // Validate required attributes
        if !hasAttribute("location", in: trimmed) {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .warning,
              message: "SceneContext missing required attribute 'location'",
              line: lineNumber
            ))
        }
        if !hasAttribute("time", in: trimmed) {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .warning,
              message: "SceneContext missing required attribute 'time'",
              line: lineNumber
            ))
        }
        continue
      }

      // Check for Constraint
      if trimmed.contains("<Constraint") && !trimmed.contains("</Constraint") {
        // Validate required attributes
        if !hasAttribute("character", in: trimmed) {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .warning,
              message: "Constraint missing required attribute 'character'",
              line: lineNumber
            ))
        }
        if !hasAttribute("direction", in: trimmed) {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .warning,
              message: "Constraint missing required attribute 'direction'",
              line: lineNumber
            ))
        }
        continue
      }

      // Check for Intent opening
      if trimmed.contains("<Intent") && !trimmed.contains("</Intent") {
        // Check for nesting
        if intentOpen {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .warning,
              message:
                "Nested Intent detected: <Intent> opened at line \(intentOpenLine ?? 0) was not closed before this <Intent>",
              line: lineNumber
            ))
        }
        intentOpen = true
        intentOpenLine = lineNumber

        // Validate required attributes
        if !hasAttribute("from", in: trimmed) {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .warning,
              message: "Intent missing required attribute 'from'",
              line: lineNumber
            ))
        }
        if !hasAttribute("to", in: trimmed) {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .warning,
              message: "Intent missing required attribute 'to'",
              line: lineNumber
            ))
        }
        continue
      }
    }

    // Check for unclosed SceneContext at end of input
    if sceneContextOpen {
      diagnostics.append(
        GlosaDiagnostic(
          severity: .warning,
          message: "Unclosed SceneContext (opened at line \(sceneContextOpenLine ?? 0))",
          line: nil
        ))
    }

    return diagnostics
  }

  /// Validate a parsed `GlosaScore` for structural correctness.
  ///
  /// This validates the already-parsed score structure rather than raw text.
  ///
  /// - Parameter score: The parsed score to validate.
  /// - Returns: Array of diagnostics describing any issues found.
  public func validate(score: GlosaScore) -> [GlosaDiagnostic] {
    var diagnostics: [GlosaDiagnostic] = []

    for (sceneIndex, scene) in score.scenes.enumerated() {
      // Check SceneContext required attributes
      if scene.context.location.isEmpty {
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message: "Scene \(sceneIndex + 1): SceneContext has empty 'location'",
            line: nil
          ))
      }
      if scene.context.time.isEmpty {
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message: "Scene \(sceneIndex + 1): SceneContext has empty 'time'",
            line: nil
          ))
      }

      for (intentIndex, entry) in scene.intents.enumerated() {
        // Check Intent required attributes
        if entry.intent.from.isEmpty {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .warning,
              message: "Scene \(sceneIndex + 1), Intent \(intentIndex + 1): empty 'from' attribute",
              line: nil
            ))
        }
        if entry.intent.to.isEmpty {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .warning,
              message: "Scene \(sceneIndex + 1), Intent \(intentIndex + 1): empty 'to' attribute",
              line: nil
            ))
        }

        // Check Constraints
        for constraint in entry.constraints {
          if constraint.character.isEmpty {
            diagnostics.append(
              GlosaDiagnostic(
                severity: .warning,
                message:
                  "Scene \(sceneIndex + 1), Intent \(intentIndex + 1): Constraint has empty 'character'",
                line: nil
              ))
          }
          if constraint.direction.isEmpty {
            diagnostics.append(
              GlosaDiagnostic(
                severity: .warning,
                message:
                  "Scene \(sceneIndex + 1), Intent \(intentIndex + 1): Constraint has empty 'direction'",
                line: nil
              ))
          }
        }

        // Check scoped intent line count consistency
        if entry.intent.scoped, let lineCount = entry.intent.lineCount {
          if lineCount != entry.dialogueLines.count {
            diagnostics.append(
              GlosaDiagnostic(
                severity: .warning,
                message:
                  "Scene \(sceneIndex + 1), Intent \(intentIndex + 1): lineCount (\(lineCount)) does not match dialogueLines count (\(entry.dialogueLines.count))",
                line: nil
              ))
          }
        }
      }
    }

    // ── Standalone block events: <include> / <shot> ───────────────────────
    // These are document-positional and carry no scene/line ownership, so they
    // are validated as flat lists. Checks are advisory (warnings): the value is
    // always carried through — model/aspect are not hard-coupled to Vinetas's
    // enums, so unknown values warn rather than fail.
    for include in score.includes {
      if include.src.isEmpty {
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message:
              "<include> at document index \(include.documentIndex) is missing required attribute 'src'",
            line: nil,
            code: .includeMissingSrc
          ))
      }
    }

    for shot in score.shots {
      if shot.prompt.isEmpty {
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message:
              "<shot> at document index \(shot.documentIndex) is missing required attribute 'prompt'",
            line: nil,
            code: .shotMissingPrompt
          ))
      }
      if let model = shot.model, !Self.knownShotModels.contains(model) {
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message:
              "<shot> at document index \(shot.documentIndex) has unrecognized model=\"\(model)\" "
              + "(expected one of \(Self.knownShotModels.sorted().joined(separator: ", "))); "
              + "carrying it through unchanged",
            line: nil,
            code: .shotUnknownModel
          ))
      }
      if let aspect = shot.aspect, !Self.knownShotAspects.contains(aspect) {
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message:
              "<shot> at document index \(shot.documentIndex) has unrecognized aspect=\"\(aspect)\" "
              + "(expected one of \(Self.knownShotAspects.sorted().joined(separator: ", "))); "
              + "carrying it through unchanged",
            line: nil,
            code: .shotUnknownAspect
          ))
      }
    }

    return diagnostics
  }

  /// Model variants the Vinetas CLI recognizes (`--model`). Used only for
  /// advisory `<shot>` validation; values outside this set are still carried
  /// through unchanged.
  private static let knownShotModels: Set<String> = ["klein4b", "klein9b", "pixart-sigma"]

  /// Aspect-ratio presets the Vinetas CLI recognizes (`--aspect`). Advisory
  /// only, as with `knownShotModels`.
  private static let knownShotAspects: Set<String> = [
    "square", "wide", "ultrawide", "portrait", "panel", "strip",
  ]

  // MARK: - Breath Validation

  /// Validate breath annotations in a parsed `GlosaScore`, surfacing three
  /// categories of diagnostic (spec §7.7):
  ///
  /// 1. **Warning** — a `<breath/>` marker was found outside any dialogue line.
  ///    Because the parser already discards such breaths, the validator wraps
  ///    any such parser diagnostics (those whose message contains the canonical
  ///    "outside any dialogue paragraph" substring) and re-emits them with the
  ///    `.breathOutsideDialogue` code so downstream tools can filter by code.
  ///
  /// 2. **Warning** — two `<breath/>` markers on the same dialogue line share
  ///    an identical `characterOffset`. Checked within each scene separately
  ///    so breaths in different scenes that happen to share the same
  ///    scene-local `dialogueLineIndex` are never flagged as duplicates.
  ///
  /// 3. **Info** — a dialogue line satisfies at least one of spec §6.1's trigger
  ///    conditions but carries zero breath annotations. The 180-character
  ///    threshold is always checked; optional additional checks cover the
  ///    colon-list pattern (single sentence with a colon followed by a list)
  ///    and polysyndetic conjunctions (three or more clauses joined by `and`,
  ///    `but`, `or`, `so`, or `yet`).
  ///
  /// - Parameters:
  ///   - score: The parsed score whose `breaths` and `scenes` are inspected.
  ///   - parserDiagnostics: Diagnostics emitted during parsing. Used to wrap
  ///     any out-of-dialogue warnings the parser already produced.
  /// - Returns: Array of breath-specific diagnostics.
  public func validateBreaths(
    score: GlosaScore,
    parserDiagnostics: [GlosaDiagnostic] = []
  ) -> [GlosaDiagnostic] {
    var diagnostics: [GlosaDiagnostic] = []

    // ── Diagnostic 1: out-of-dialogue breaths ──────────────────────────────
    // The parser already drops these and emits a warning. Wrap those warnings
    // with the machine-readable code so callers can filter by code.
    for parserDiag in parserDiagnostics
    where parserDiag.severity == .warning
      && parserDiag.message.contains("outside any dialogue paragraph")
    {
      diagnostics.append(
        GlosaDiagnostic(
          severity: .warning,
          message: parserDiag.message,
          line: parserDiag.line,
          code: .breathOutsideDialogue
        ))
    }

    // ── Partition breaths per scene ────────────────────────────────────────
    // Each `Breath` carries its own `sceneIndex` (populated by the parsers),
    // so partitioning is a direct group-by — no document-order cursor or
    // structural heuristic. Breaths whose `sceneIndex` falls outside the
    // parsed scene tree (e.g. emitted before any `<SceneContext>` opened)
    // are dropped here.
    let breathsByScene = Dictionary(grouping: score.breaths, by: \.sceneIndex)
    let perSceneBreaths: [[Breath]] = (0..<score.scenes.count).map {
      breathsByScene[$0] ?? []
    }

    // ── Diagnostic 2: duplicate offsets ───────────────────────────────────
    for sceneBreaths in perSceneBreaths {
      var seen = Set<BreathKey>()
      for breath in sceneBreaths {
        let key = BreathKey(
          dialogueLineIndex: breath.dialogueLineIndex,
          characterOffset: breath.characterOffset
        )
        if seen.contains(key) {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .warning,
              message:
                "Duplicate <breath/> at (dialogueLineIndex: \(breath.dialogueLineIndex), "
                + "characterOffset: \(breath.characterOffset)) on the same dialogue line",
              line: nil,
              code: .breathDuplicateOffset
            ))
        } else {
          seen.insert(key)
        }
      }
    }

    // ── Diagnostic 3: long-line-no-breath (info) ───────────────────────────
    // Walk every dialogue line in the score using the per-scene breath
    // partition constructed above so that scene-local `dialogueLineIndex`
    // values are compared within the correct scene boundary.
    for (sceneIndex, scene) in score.scenes.enumerated() {
      let sceneLines = scene.intents.flatMap(\.dialogueLines)
      let sceneBreaths = perSceneBreaths[sceneIndex]

      for (localIndex, lineText) in sceneLines.enumerated() {
        guard lineTriggersBreathCondition(lineText) else { continue }

        let hasBreath = sceneBreaths.contains { $0.dialogueLineIndex == localIndex }
        if !hasBreath {
          diagnostics.append(
            GlosaDiagnostic(
              severity: .info,
              message:
                "Dialogue line satisfies §6.1 trigger conditions but has no <breath/> annotations: "
                + "\"\(lineText.prefix(60))\(lineText.count > 60 ? "…" : "")\"",
              line: nil,
              code: .breathMissingOnLongLine
            ))
        }
      }
    }

    return diagnostics
  }

  // MARK: - Private Helpers

  /// Check if a tag string contains a specific attribute with a non-empty value.
  private func hasAttribute(_ name: String, in text: String) -> Bool {
    // Check for name="..." or name='...'
    let doubleQuotePattern = name + #"="[^"]+""#
    let singleQuotePattern = name + #"='[^']+'"#

    return text.range(of: doubleQuotePattern, options: .regularExpression) != nil
      || text.range(of: singleQuotePattern, options: .regularExpression) != nil
  }

  /// Returns `true` if `line` satisfies any of spec §6.1's trigger conditions:
  ///
  /// 1. Length exceeds 180 characters (the primary threshold).
  /// 2. Single sentence (no internal `.`, `?`, `!`) longer than 120 characters
  ///    AND contains a colon followed by a list (colon-list pattern).
  /// 3. Single sentence longer than 120 characters AND contains three or more
  ///    coordinating conjunctions (`and`, `but`, `or`, `so`, `yet`) —
  ///    the polysyndetic conjunction pattern.
  private func lineTriggersBreathCondition(_ line: String) -> Bool {
    // Trigger 1: raw character count > 180.
    if line.count > 180 {
      return true
    }

    // Only proceed with the single-sentence checks if the line is ≥ 120 chars.
    guard line.count >= 120 else { return false }

    // Single-sentence: no internal sentence-terminating punctuation.
    let isSingleSentence =
      !line.contains(".") && !line.contains("?") && !line.contains("!")

    guard isSingleSentence else { return false }

    // Trigger 2: colon-list pattern — a colon followed by a comma-separated list.
    if line.contains(":") {
      let afterColon =
        line.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init)
        ?? ""
      if afterColon.contains(",") {
        return true
      }
    }

    // Trigger 3: polysyndetic — three or more coordinating conjunctions.
    let conjunctions = ["and", "but", "or", "so", "yet"]
    let lowerLine = line.lowercased()
    let conjunctionCount = conjunctions.reduce(0) { count, conj in
      // Match whole-word occurrences using simple whitespace-bounded check.
      let pattern = "\\b\(conj)\\b"
      let matchCount =
        (try? NSRegularExpression(pattern: pattern, options: []))
        .flatMap { regex in
          let range = NSRange(lowerLine.startIndex..., in: lowerLine)
          return regex.numberOfMatches(in: lowerLine, range: range)
        } ?? 0
      return count + matchCount
    }
    if conjunctionCount >= 3 {
      return true
    }

    return false
  }
}

/// Hashable key for identifying a breath position within a scene.
private struct BreathKey: Hashable {
  let dialogueLineIndex: Int
  let characterOffset: Int
}
