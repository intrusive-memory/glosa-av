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
                    diagnostics.append(GlosaDiagnostic(
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
                    diagnostics.append(GlosaDiagnostic(
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
                    diagnostics.append(GlosaDiagnostic(
                        severity: .warning,
                        message: "Opening <SceneContext> while previous SceneContext is still open (unclosed at line \(sceneContextOpenLine ?? 0))",
                        line: lineNumber
                    ))
                }
                sceneContextOpen = true
                sceneContextOpenLine = lineNumber

                // Validate required attributes
                if !hasAttribute("location", in: trimmed) {
                    diagnostics.append(GlosaDiagnostic(
                        severity: .warning,
                        message: "SceneContext missing required attribute 'location'",
                        line: lineNumber
                    ))
                }
                if !hasAttribute("time", in: trimmed) {
                    diagnostics.append(GlosaDiagnostic(
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
                    diagnostics.append(GlosaDiagnostic(
                        severity: .warning,
                        message: "Constraint missing required attribute 'character'",
                        line: lineNumber
                    ))
                }
                if !hasAttribute("direction", in: trimmed) {
                    diagnostics.append(GlosaDiagnostic(
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
                    diagnostics.append(GlosaDiagnostic(
                        severity: .warning,
                        message: "Nested Intent detected: <Intent> opened at line \(intentOpenLine ?? 0) was not closed before this <Intent>",
                        line: lineNumber
                    ))
                }
                intentOpen = true
                intentOpenLine = lineNumber

                // Validate required attributes
                if !hasAttribute("from", in: trimmed) {
                    diagnostics.append(GlosaDiagnostic(
                        severity: .warning,
                        message: "Intent missing required attribute 'from'",
                        line: lineNumber
                    ))
                }
                if !hasAttribute("to", in: trimmed) {
                    diagnostics.append(GlosaDiagnostic(
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
            diagnostics.append(GlosaDiagnostic(
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
                diagnostics.append(GlosaDiagnostic(
                    severity: .warning,
                    message: "Scene \(sceneIndex + 1): SceneContext has empty 'location'",
                    line: nil
                ))
            }
            if scene.context.time.isEmpty {
                diagnostics.append(GlosaDiagnostic(
                    severity: .warning,
                    message: "Scene \(sceneIndex + 1): SceneContext has empty 'time'",
                    line: nil
                ))
            }

            for (intentIndex, entry) in scene.intents.enumerated() {
                // Check Intent required attributes
                if entry.intent.from.isEmpty {
                    diagnostics.append(GlosaDiagnostic(
                        severity: .warning,
                        message: "Scene \(sceneIndex + 1), Intent \(intentIndex + 1): empty 'from' attribute",
                        line: nil
                    ))
                }
                if entry.intent.to.isEmpty {
                    diagnostics.append(GlosaDiagnostic(
                        severity: .warning,
                        message: "Scene \(sceneIndex + 1), Intent \(intentIndex + 1): empty 'to' attribute",
                        line: nil
                    ))
                }

                // Check Constraints
                for constraint in entry.constraints {
                    if constraint.character.isEmpty {
                        diagnostics.append(GlosaDiagnostic(
                            severity: .warning,
                            message: "Scene \(sceneIndex + 1), Intent \(intentIndex + 1): Constraint has empty 'character'",
                            line: nil
                        ))
                    }
                    if constraint.direction.isEmpty {
                        diagnostics.append(GlosaDiagnostic(
                            severity: .warning,
                            message: "Scene \(sceneIndex + 1), Intent \(intentIndex + 1): Constraint has empty 'direction'",
                            line: nil
                        ))
                    }
                }

                // Check scoped intent line count consistency
                if entry.intent.scoped, let lineCount = entry.intent.lineCount {
                    if lineCount != entry.dialogueLines.count {
                        diagnostics.append(GlosaDiagnostic(
                            severity: .warning,
                            message: "Scene \(sceneIndex + 1), Intent \(intentIndex + 1): lineCount (\(lineCount)) does not match dialogueLines count (\(entry.dialogueLines.count))",
                            line: nil
                        ))
                    }
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
}
