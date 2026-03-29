import Foundation
import GlosaAnnotation
import GlosaCore
import SwiftBruja
import SwiftCompartido

/// Protocol abstracting the LLM query interface for testability.
///
/// The real implementation calls ``SwiftBruja/Bruja`` for on-device inference.
/// Tests inject a mock that returns predetermined ``SceneAnnotation`` values.
public protocol SceneAnnotationProvider: Sendable {
    /// Query the LLM to annotate a scene.
    ///
    /// - Parameters:
    ///   - sceneText: The readable scene text.
    ///   - dialogueLineCount: Number of dialogue lines in the scene.
    ///   - systemPrompt: The system prompt with GLOSA spec and glossary.
    ///   - model: The model identifier or path.
    /// - Returns: A ``SceneAnnotation`` decoded from the LLM response.
    func annotateScene(
        sceneText: String,
        dialogueLineCount: Int,
        systemPrompt: String,
        model: String
    ) async throws -> SceneAnnotation
}

/// Default implementation using SwiftBruja for real LLM inference.
public struct BrujaAnnotationProvider: SceneAnnotationProvider {
    public init() {}

    public func annotateScene(
        sceneText: String,
        dialogueLineCount: Int,
        systemPrompt: String,
        model: String
    ) async throws -> SceneAnnotation {
        let userPrompt = Prompts.userPrompt(
            sceneText: sceneText,
            dialogueLineCount: dialogueLineCount
        )

        return try await Bruja.query(
            userPrompt,
            as: SceneAnnotation.self,
            model: model,
            temperature: 0.3,
            system: systemPrompt
        )
    }
}

/// Analyzes raw screenplays and produces GLOSA annotations via LLM inference.
///
/// The Stage Director operates on SwiftCompartido's parsed element model.
/// For each scene it:
/// 1. Builds readable scene text from elements.
/// 2. Calls the LLM with GLOSA spec + few-shot examples + scene text.
/// 3. Validates the response via ``GlosaValidator`` rules.
/// 4. Maps the ``SceneAnnotation`` onto ``GuionElement`` indices to produce
///    ``GlosaAnnotatedElement`` values with instruct strings.
///
/// ## Testability
///
/// The LLM call is abstracted behind ``SceneAnnotationProvider``. Inject a
/// mock provider for deterministic testing without a real model.
///
/// ```swift
/// let director = StageDirector(provider: MockAnnotationProvider())
/// let result = try await director.annotate(screenplay)
/// ```
public struct StageDirector: Sendable {

    /// The default model for LLM inference.
    public static let defaultModel = "mlx-community/Qwen3-Coder-Next-4bit"

    /// The LLM provider.
    private let provider: SceneAnnotationProvider

    /// Creates a Stage Director with a custom annotation provider.
    ///
    /// - Parameter provider: The provider to use for LLM queries. Defaults to
    ///   ``BrujaAnnotationProvider`` for real inference.
    public init(provider: SceneAnnotationProvider = BrujaAnnotationProvider()) {
        self.provider = provider
    }

    /// Annotate a screenplay with GLOSA directives via LLM analysis.
    ///
    /// For each scene in the screenplay, the director:
    /// 1. Extracts dialogue lines and builds readable scene text.
    /// 2. Queries the LLM for a ``SceneAnnotation``.
    /// 3. Validates and corrects the annotation.
    /// 4. Maps the annotation onto screenplay element indices.
    /// 5. Composes instruct strings for each dialogue line.
    ///
    /// - Parameters:
    ///   - screenplay: The parsed screenplay to annotate.
    ///   - model: The LLM model identifier. If `nil`, uses ``defaultModel``.
    ///   - glossary: The vocabulary glossary to inject into the LLM prompt.
    ///     If `nil`, uses the default bundled glossary.
    /// - Returns: A fully annotated screenplay with instruct strings.
    /// - Throws: If the LLM query fails or the screenplay cannot be processed.
    public func annotate(
        _ screenplay: GuionParsedElementCollection,
        model: String? = nil,
        glossary: VocabularyGlossary? = nil
    ) async throws -> GlosaAnnotatedScreenplay {
        let resolvedModel = model ?? Self.defaultModel

        let resolvedGlossary: VocabularyGlossary?
        if let glossary {
            resolvedGlossary = glossary
        } else {
            resolvedGlossary = try? VocabularyGlossary.loadDefault()
        }

        let systemPrompt = Prompts.systemPrompt(glossary: resolvedGlossary)

        let segments = SceneAnalyzer.segmentScenes(from: screenplay)

        var allAnnotatedElements: [GlosaAnnotatedElement] = []
        var allDiagnostics: [GlosaDiagnostic] = []
        var allProvenance: [InstructProvenance] = []
        var allSceneEntries: [GlosaScore.SceneEntry] = []
        var globalDialogueIndex = 0

        // Process elements before the first scene heading (preamble)
        let firstSceneHeadingIndex = screenplay.elements.firstIndex {
            $0.elementType == .sceneHeading
        }
        if let idx = firstSceneHeadingIndex, idx > 0 {
            for i in 0..<idx {
                let element = screenplay.elements[i]
                allAnnotatedElements.append(GlosaAnnotatedElement(element: element))
                if element.elementType == .dialogue {
                    globalDialogueIndex += 1
                }
            }
        }

        // Process each scene
        for segment in segments {
            let sceneText = buildSceneText(from: segment.elements)
            let dialogueElements = Self.extractDialogueInfo(from: segment.elements)
            let dialogueCount = dialogueElements.count

            guard dialogueCount > 0 else {
                // Scene with no dialogue — just pass elements through
                for element in segment.elements {
                    allAnnotatedElements.append(GlosaAnnotatedElement(element: element))
                }
                continue
            }

            // Query the LLM
            let rawAnnotation = try await provider.annotateScene(
                sceneText: sceneText,
                dialogueLineCount: dialogueCount,
                systemPrompt: systemPrompt,
                model: resolvedModel
            )

            // Validate and correct
            let (annotation, diagnostics) = validateAndCorrect(
                rawAnnotation,
                dialogueCount: dialogueCount
            )
            allDiagnostics.append(contentsOf: diagnostics)

            // Convert SceneAnnotation to GlosaScore components for the composer
            let sceneContext = SceneContext(
                location: annotation.sceneContext.location,
                time: annotation.sceneContext.time,
                ambience: annotation.sceneContext.ambience
            )

            // Build constraint map
            var constraintMap: [String: Constraint] = [:]
            for ca in annotation.constraints {
                constraintMap[ca.character] = Constraint(
                    character: ca.character,
                    direction: ca.direction,
                    register: ca.register,
                    ceiling: ca.ceiling
                )
            }

            // Build intent lookup: for each dialogue line index, find its intent
            let intentLookup = Self.buildIntentLookup(
                intents: annotation.intents,
                dialogueCount: dialogueCount
            )

            // Map annotation onto elements
            let composer = InstructComposer()
            var dialogueIndexInScene = 0
            var sceneIntentEntries: [GlosaScore.IntentEntry] = []

            // Build IntentEntries for the GlosaScore
            for intentAnnotation in annotation.intents {
                let intent = Intent(
                    from: intentAnnotation.from,
                    to: intentAnnotation.to,
                    pace: intentAnnotation.pace,
                    spacing: intentAnnotation.spacing,
                    scoped: intentAnnotation.scoped,
                    lineCount: intentAnnotation.endLine - intentAnnotation.startLine + 1
                )

                let constraints = annotation.constraints.map { ca in
                    Constraint(
                        character: ca.character,
                        direction: ca.direction,
                        register: ca.register,
                        ceiling: ca.ceiling
                    )
                }

                let lineRange = intentAnnotation.startLine...intentAnnotation.endLine
                let dialogueTexts = lineRange.compactMap { idx -> String? in
                    guard idx < dialogueElements.count else { return nil }
                    return dialogueElements[idx].text
                }

                sceneIntentEntries.append(GlosaScore.IntentEntry(
                    intent: intent,
                    constraints: constraints,
                    dialogueLines: dialogueTexts
                ))
            }

            allSceneEntries.append(GlosaScore.SceneEntry(
                context: sceneContext,
                intents: sceneIntentEntries
            ))

            for element in segment.elements {
                if element.elementType == .dialogue {
                    let characterName = Self.findCharacterName(
                        forDialogueAt: dialogueIndexInScene,
                        dialogueInfo: dialogueElements
                    )

                    // Look up the intent for this dialogue line
                    let intentInfo = intentLookup[dialogueIndexInScene]

                    let resolvedDirectives: ResolvedDirectives
                    let constraint = constraintMap[characterName]

                    if let intentInfo {
                        let resolvedIntent = ResolvedIntent(
                            intent: Intent(
                                from: intentInfo.intent.from,
                                to: intentInfo.intent.to,
                                pace: intentInfo.intent.pace,
                                spacing: intentInfo.intent.spacing,
                                scoped: intentInfo.intent.scoped,
                                lineCount: intentInfo.intent.endLine - intentInfo.intent.startLine + 1
                            ),
                            arcPosition: intentInfo.arcPosition
                        )
                        resolvedDirectives = ResolvedDirectives(
                            sceneContext: sceneContext,
                            intent: resolvedIntent,
                            constraint: constraint
                        )
                    } else {
                        // Neutral delivery — still has scene context and constraint
                        resolvedDirectives = ResolvedDirectives(
                            sceneContext: sceneContext,
                            intent: nil,
                            constraint: constraint
                        )
                    }

                    let instruct = composer.compose(resolvedDirectives)

                    allAnnotatedElements.append(GlosaAnnotatedElement(
                        element: element,
                        directives: resolvedDirectives,
                        instruct: instruct
                    ))

                    if let instruct {
                        allProvenance.append(InstructProvenance(
                            lineIndex: globalDialogueIndex,
                            characterName: characterName,
                            sceneContext: resolvedDirectives.sceneContext,
                            intent: resolvedDirectives.intent,
                            constraint: resolvedDirectives.constraint,
                            composedInstruct: instruct
                        ))
                    }

                    dialogueIndexInScene += 1
                    globalDialogueIndex += 1
                } else {
                    allAnnotatedElements.append(GlosaAnnotatedElement(element: element))
                }
            }
        }

        let score = GlosaScore(scenes: allSceneEntries)

        return GlosaAnnotatedScreenplay(
            screenplay: screenplay,
            annotatedElements: allAnnotatedElements,
            score: score,
            diagnostics: allDiagnostics,
            provenance: allProvenance
        )
    }

    // MARK: - Scene Text Construction

    /// Build readable scene text from screenplay elements.
    ///
    /// Produces a text representation suitable for LLM consumption,
    /// preserving character names, dialogue, action lines, and scene headings.
    ///
    /// - Parameter elements: The elements of a single scene segment.
    /// - Returns: A formatted scene text string.
    public static func buildSceneText(from elements: [GuionElement]) -> String {
        var lines: [String] = []

        for element in elements {
            switch element.elementType {
            case .sceneHeading:
                lines.append(element.elementText)
                lines.append("")
            case .action:
                lines.append(element.elementText)
                lines.append("")
            case .character:
                lines.append(element.elementText)
            case .dialogue:
                lines.append(element.elementText)
                lines.append("")
            case .parenthetical:
                lines.append("(\(element.elementText))")
            case .transition:
                lines.append(element.elementText)
                lines.append("")
            default:
                break
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Instance method forwarding to the static implementation.
    func buildSceneText(from elements: [GuionElement]) -> String {
        Self.buildSceneText(from: elements)
    }

    // MARK: - Dialogue Extraction

    /// Information about a dialogue line within a scene.
    struct DialogueInfo {
        let character: String
        let text: String
        let elementIndex: Int
    }

    /// Extract dialogue lines with their character names and element indices.
    ///
    /// - Parameter elements: The elements of a single scene segment.
    /// - Returns: An array of ``DialogueInfo`` values in document order.
    static func extractDialogueInfo(from elements: [GuionElement]) -> [DialogueInfo] {
        var result: [DialogueInfo] = []
        var currentCharacter = ""

        for (index, element) in elements.enumerated() {
            switch element.elementType {
            case .character:
                currentCharacter = element.elementText
            case .dialogue:
                result.append(DialogueInfo(
                    character: currentCharacter,
                    text: element.elementText,
                    elementIndex: index
                ))
            default:
                break
            }
        }

        return result
    }

    /// Find the character name for a given dialogue index within a scene.
    ///
    /// - Parameters:
    ///   - dialogueIndex: Zero-based dialogue line index within the scene.
    ///   - dialogueInfo: The dialogue info array for the scene.
    /// - Returns: The character name, or an empty string if not found.
    static func findCharacterName(
        forDialogueAt dialogueIndex: Int,
        dialogueInfo: [DialogueInfo]
    ) -> String {
        guard dialogueIndex < dialogueInfo.count else { return "" }
        return dialogueInfo[dialogueIndex].character
    }

    // MARK: - Intent Lookup

    /// Information about an intent and its arc position for a specific dialogue line.
    struct IntentWithPosition {
        let intent: IntentAnnotation
        let arcPosition: Float
    }

    /// Build a lookup from dialogue line index to intent and arc position.
    ///
    /// - Parameters:
    ///   - intents: The intent annotations from the LLM response.
    ///   - dialogueCount: The total number of dialogue lines in the scene.
    /// - Returns: A dictionary mapping dialogue line index to intent info.
    static func buildIntentLookup(
        intents: [IntentAnnotation],
        dialogueCount: Int
    ) -> [Int: IntentWithPosition] {
        var lookup: [Int: IntentWithPosition] = [:]

        for intent in intents {
            let startLine = max(0, intent.startLine)
            let endLine = min(dialogueCount - 1, intent.endLine)
            let totalLines = endLine - startLine + 1

            guard totalLines > 0 else { continue }

            for lineIndex in startLine...endLine {
                let localIndex = lineIndex - startLine
                let arcPosition: Float
                if totalLines <= 1 {
                    arcPosition = 0.0
                } else {
                    arcPosition = Float(localIndex) / Float(totalLines - 1)
                }

                lookup[lineIndex] = IntentWithPosition(
                    intent: intent,
                    arcPosition: arcPosition
                )
            }
        }

        return lookup
    }

    // MARK: - Post-LLM Validation

    /// Validate and correct an LLM-generated SceneAnnotation.
    ///
    /// Checks for:
    /// - Out-of-range line indices (clamped to valid range).
    /// - Overlapping intent ranges (later intents win).
    /// - Nested intents (removed with diagnostic).
    /// - Missing required fields.
    ///
    /// - Parameters:
    ///   - annotation: The raw annotation from the LLM.
    ///   - dialogueCount: The total number of dialogue lines in the scene.
    /// - Returns: A tuple of (corrected annotation, diagnostics).
    public static func validateAndCorrect(
        _ annotation: SceneAnnotation,
        dialogueCount: Int
    ) -> (SceneAnnotation, [GlosaDiagnostic]) {
        var corrected = annotation
        var diagnostics: [GlosaDiagnostic] = []

        // Validate SceneContext required fields
        if corrected.sceneContext.location.isEmpty {
            diagnostics.append(GlosaDiagnostic(
                severity: .warning,
                message: "LLM produced empty SceneContext location",
                line: nil
            ))
        }
        if corrected.sceneContext.time.isEmpty {
            diagnostics.append(GlosaDiagnostic(
                severity: .warning,
                message: "LLM produced empty SceneContext time",
                line: nil
            ))
        }

        // Validate and clamp intent line ranges
        var validIntents: [IntentAnnotation] = []
        for (index, var intent) in corrected.intents.enumerated() {
            // Clamp to valid range
            let originalStart = intent.startLine
            let originalEnd = intent.endLine
            intent.startLine = max(0, min(intent.startLine, dialogueCount - 1))
            intent.endLine = max(intent.startLine, min(intent.endLine, dialogueCount - 1))

            if intent.startLine != originalStart || intent.endLine != originalEnd {
                diagnostics.append(GlosaDiagnostic(
                    severity: .warning,
                    message: "Intent \(index): line range [\(originalStart), \(originalEnd)] "
                        + "clamped to [\(intent.startLine), \(intent.endLine)] "
                        + "(scene has \(dialogueCount) dialogue lines)",
                    line: nil
                ))
            }

            // Check for required fields
            if intent.from.isEmpty {
                diagnostics.append(GlosaDiagnostic(
                    severity: .warning,
                    message: "Intent \(index): empty 'from' field",
                    line: nil
                ))
            }
            if intent.to.isEmpty {
                diagnostics.append(GlosaDiagnostic(
                    severity: .warning,
                    message: "Intent \(index): empty 'to' field",
                    line: nil
                ))
            }

            validIntents.append(intent)
        }

        // Check for nested/overlapping intents — remove later overlapping ones
        var occupiedLines = Set<Int>()
        var deduplicatedIntents: [IntentAnnotation] = []

        for (index, intent) in validIntents.enumerated() {
            let range = intent.startLine...intent.endLine
            let overlap = range.filter { occupiedLines.contains($0) }

            if !overlap.isEmpty {
                diagnostics.append(GlosaDiagnostic(
                    severity: .warning,
                    message: "Intent \(index) overlaps with a previous intent "
                        + "at lines \(overlap). Removing the overlapping intent.",
                    line: nil
                ))
                continue
            }

            for line in range {
                occupiedLines.insert(line)
            }
            deduplicatedIntents.append(intent)
        }

        corrected.intents = deduplicatedIntents

        // Validate constraints
        for (index, constraint) in corrected.constraints.enumerated() {
            if constraint.character.isEmpty {
                diagnostics.append(GlosaDiagnostic(
                    severity: .warning,
                    message: "Constraint \(index): empty 'character' field",
                    line: nil
                ))
            }
            if constraint.direction.isEmpty {
                diagnostics.append(GlosaDiagnostic(
                    severity: .warning,
                    message: "Constraint \(index): empty 'direction' field",
                    line: nil
                ))
            }
        }

        return (corrected, diagnostics)
    }

    /// Instance method forwarding to the static implementation.
    func validateAndCorrect(
        _ annotation: SceneAnnotation,
        dialogueCount: Int
    ) -> (SceneAnnotation, [GlosaDiagnostic]) {
        Self.validateAndCorrect(annotation, dialogueCount: dialogueCount)
    }
}
