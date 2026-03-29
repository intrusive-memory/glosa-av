import Foundation

/// Parses GLOSA annotations from Fountain note strings or FDX XML content
/// and produces a structured `GlosaScore`.
///
/// Two extraction modes are supported:
/// - **Fountain**: Regex-based parsing of GLOSA tags from `[[ ]]` note strings.
/// - **FDX**: `XMLParser`-based extraction of `glosa:` namespace elements from XML.
public struct GlosaParser: Sendable {

    public init() {}

    // MARK: - Fountain Extraction

    /// Parse GLOSA tags from an array of Fountain note contents (the text inside `[[ ]]` blocks).
    ///
    /// The notes must be in document order. Dialogue lines enclosed by scoped Intents
    /// should appear as separate note entries containing just the dialogue text, or
    /// they can be inferred from the structure. In practice, the parser expects
    /// interleaved note strings that contain GLOSA tags and dialogue content.
    ///
    /// - Parameter notes: Array of strings, each being the content of a `[[ ]]` note block,
    ///   or a dialogue line in document order.
    /// - Returns: A `GlosaScore` representing the parsed annotations.
    public func parseFountain(notes: [String]) -> GlosaScore {
        var scenes: [GlosaScore.SceneEntry] = []
        var currentScene: SceneContext?
        var currentIntents: [GlosaScore.IntentEntry] = []
        var pendingConstraints: [Constraint] = []
        var currentIntentAttrs: Intent?
        var currentIntentConstraints: [Constraint] = []
        var currentIntentDialogue: [String] = []
        // Track constraints that were declared before any intent in a scene
        var sceneConstraints: [Constraint] = []

        for note in notes {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for closing tags first
            if trimmed.contains("</SceneContext>") {
                // Close any open intent as a MARKER (not scoped) since it was
                // not explicitly closed with </Intent>
                if let intentAttrs = currentIntentAttrs {
                    let entry = makeIntentEntry(
                        attrs: intentAttrs,
                        constraints: currentIntentConstraints,
                        dialogue: currentIntentDialogue,
                        scoped: false
                    )
                    currentIntents.append(entry)
                    currentIntentAttrs = nil
                    currentIntentConstraints = []
                    currentIntentDialogue = []
                }

                // Close scene
                if let scene = currentScene {
                    scenes.append(GlosaScore.SceneEntry(
                        context: scene,
                        intents: currentIntents
                    ))
                }
                currentScene = nil
                currentIntents = []
                pendingConstraints = []
                sceneConstraints = []
                continue
            }

            if trimmed.contains("</Intent>") {
                // Close current scoped intent (explicit close = scoped)
                if let intentAttrs = currentIntentAttrs {
                    let entry = makeIntentEntry(
                        attrs: intentAttrs,
                        constraints: currentIntentConstraints,
                        dialogue: currentIntentDialogue,
                        scoped: true
                    )
                    currentIntents.append(entry)
                    currentIntentAttrs = nil
                    currentIntentConstraints = []
                    currentIntentDialogue = []
                }
                continue
            }

            // Check for opening SceneContext
            if let sceneContext = parseSceneContextTag(trimmed) {
                // Close any previous scene
                if let prevScene = currentScene {
                    // Any open intent without explicit </Intent> is a marker
                    if let intentAttrs = currentIntentAttrs {
                        let entry = makeIntentEntry(
                            attrs: intentAttrs,
                            constraints: currentIntentConstraints,
                            dialogue: currentIntentDialogue,
                            scoped: false
                        )
                        currentIntents.append(entry)
                        currentIntentAttrs = nil
                        currentIntentConstraints = []
                        currentIntentDialogue = []
                    }
                    scenes.append(GlosaScore.SceneEntry(
                        context: prevScene,
                        intents: currentIntents
                    ))
                    currentIntents = []
                }
                currentScene = sceneContext
                pendingConstraints = []
                sceneConstraints = []
                continue
            }

            // Check for Constraint
            if let constraint = parseConstraintTag(trimmed) {
                if currentIntentAttrs != nil {
                    // Inside an intent scope
                    currentIntentConstraints.append(constraint)
                } else {
                    // Outside intent - these are scene-level constraints
                    pendingConstraints.append(constraint)
                    sceneConstraints.append(constraint)
                }
                continue
            }

            // Check for opening Intent
            if let intent = parseIntentTag(trimmed) {
                // Close any previous open intent as marker (superseded without explicit close)
                if let prevAttrs = currentIntentAttrs {
                    let entry = makeIntentEntry(
                        attrs: prevAttrs,
                        constraints: currentIntentConstraints,
                        dialogue: currentIntentDialogue,
                        scoped: false
                    )
                    currentIntents.append(entry)
                    currentIntentConstraints = []
                    currentIntentDialogue = []
                }

                currentIntentAttrs = intent
                // Carry forward scene-level constraints into this intent
                currentIntentConstraints = pendingConstraints
                pendingConstraints = []
                continue
            }

            // If we reach here, this is a dialogue line (or non-tag content)
            // Only add as dialogue if we're inside an intent
            if currentIntentAttrs != nil && !trimmed.isEmpty {
                currentIntentDialogue.append(trimmed)
            }
        }

        // Handle unclosed structures at end
        if let intentAttrs = currentIntentAttrs {
            let entry = makeIntentEntry(
                attrs: intentAttrs,
                constraints: currentIntentConstraints,
                dialogue: currentIntentDialogue,
                scoped: false // No closing tag found = marker
            )
            currentIntents.append(entry)
        }

        if let scene = currentScene {
            scenes.append(GlosaScore.SceneEntry(
                context: scene,
                intents: currentIntents
            ))
        }

        return GlosaScore(scenes: scenes)
    }

    /// Parse GLOSA tags from Fountain note strings where dialogue lines are provided
    /// separately as an interleaved stream.
    ///
    /// This is a convenience wrapper around `parseFountain(notes:)`. The `notes`
    /// array should contain both GLOSA tag strings and dialogue line strings,
    /// interleaved in document order. The `dialogueLines` parameter is available
    /// for callers that need character-name resolution but is not used for parsing
    /// structure.
    ///
    /// - Parameters:
    ///   - notes: Interleaved array of GLOSA tag strings and dialogue text in document order.
    ///   - dialogueLines: Dialogue lines with character names (reserved for future use).
    /// - Returns: A `GlosaScore` representing the parsed annotations.
    public func parseFountainWithDialogue(
        notes: [String],
        dialogueLines: [(character: String, text: String)]
    ) -> GlosaScore {
        return parseFountain(notes: notes)
    }

    // MARK: - FDX Extraction

    /// Parse GLOSA annotations from FDX (Final Draft XML) content.
    ///
    /// Uses `XMLParser` to extract `glosa:` namespace elements from the FDX document.
    ///
    /// - Parameter data: The XML content of the FDX file.
    /// - Returns: A `GlosaScore` representing the parsed annotations.
    public func parseFDX(data: Data) -> GlosaScore {
        let delegate = FDXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.parse()
        return delegate.buildScore()
    }

    // MARK: - Private Helpers

    /// Parse a `<SceneContext ...>` tag and extract its attributes.
    private func parseSceneContextTag(_ text: String) -> SceneContext? {
        // Match <SceneContext with attributes
        guard text.contains("<SceneContext") && !text.contains("</SceneContext") else {
            return nil
        }

        let location = extractAttribute("location", from: text) ?? ""
        let time = extractAttribute("time", from: text) ?? ""
        let ambience = extractAttribute("ambience", from: text)

        guard !location.isEmpty, !time.isEmpty else { return nil }

        return SceneContext(location: location, time: time, ambience: ambience)
    }

    /// Parse a `<Constraint ...>` tag and extract its attributes.
    private func parseConstraintTag(_ text: String) -> Constraint? {
        guard text.contains("<Constraint") && !text.contains("</Constraint") else {
            return nil
        }

        let character = extractAttribute("character", from: text) ?? ""
        let direction = extractAttribute("direction", from: text) ?? ""

        guard !character.isEmpty, !direction.isEmpty else { return nil }

        let register = extractAttribute("register", from: text)
        let ceiling = extractAttribute("ceiling", from: text)

        return Constraint(
            character: character,
            direction: direction,
            register: register,
            ceiling: ceiling
        )
    }

    /// Parse an `<Intent ...>` tag and extract its attributes.
    private func parseIntentTag(_ text: String) -> Intent? {
        guard text.contains("<Intent") && !text.contains("</Intent") else {
            return nil
        }

        let from = extractAttribute("from", from: text) ?? ""
        let to = extractAttribute("to", from: text) ?? ""

        guard !from.isEmpty, !to.isEmpty else { return nil }

        let pace = extractAttribute("pace", from: text)
        let spacing = extractAttribute("spacing", from: text)

        return Intent(from: from, to: to, pace: pace, spacing: spacing)
    }

    /// Extract an XML/SGML attribute value from a tag string.
    ///
    /// Handles both `attr="value"` and `attr='value'` forms.
    private func extractAttribute(_ name: String, from text: String) -> String? {
        // Try double quotes first
        let doubleQuotePattern = name + #"="([^"]*)""#
        if let match = text.range(of: doubleQuotePattern, options: .regularExpression) {
            let fullMatch = String(text[match])
            // Extract the value between quotes
            if let openQuote = fullMatch.firstIndex(of: "\""),
               let closeQuote = fullMatch[fullMatch.index(after: openQuote)...].firstIndex(of: "\"") {
                return String(fullMatch[fullMatch.index(after: openQuote)..<closeQuote])
            }
        }

        // Try single quotes
        let singleQuotePattern = name + #"='([^']*)'"#
        if let match = text.range(of: singleQuotePattern, options: .regularExpression) {
            let fullMatch = String(text[match])
            if let openQuote = fullMatch.firstIndex(of: "'"),
               let closeQuote = fullMatch[fullMatch.index(after: openQuote)...].firstIndex(of: "'") {
                return String(fullMatch[fullMatch.index(after: openQuote)..<closeQuote])
            }
        }

        return nil
    }

    /// Build an IntentEntry from accumulated parsing state.
    private func makeIntentEntry(
        attrs: Intent,
        constraints: [Constraint],
        dialogue: [String],
        scoped: Bool
    ) -> GlosaScore.IntentEntry {
        var intent = attrs
        intent.scoped = scoped
        intent.lineCount = scoped ? dialogue.count : nil
        return GlosaScore.IntentEntry(
            intent: intent,
            constraints: constraints,
            dialogueLines: dialogue
        )
    }
}

// MARK: - FDX XMLParser Delegate

/// XMLParser delegate that extracts `glosa:` namespace elements from FDX XML.
private final class FDXParserDelegate: NSObject, XMLParserDelegate {

    private static let glosaNamespace = "https://intrusive-memory.productions/glosa"

    // Parsing state
    private var scenes: [GlosaScore.SceneEntry] = []
    private var currentScene: SceneContext?
    private var currentIntents: [GlosaScore.IntentEntry] = []
    private var pendingConstraints: [Constraint] = []
    private var currentIntentAttrs: Intent?
    private var currentIntentConstraints: [Constraint] = []
    private var currentIntentDialogue: [String] = []
    /// Tracks whether the current intent was opened via didStartElement.
    /// When didEndElement is called for Intent, it's either:
    /// - Self-closing (no dialogue) = marker
    /// - Scoped (has dialogue) = scoped
    private var intentOpenedViaStartElement = false

    // FDX paragraph tracking
    private var currentParagraphType: String?
    private var currentText = ""
    private var isCollectingText = false
    private var lastCharacterName: String?

    func buildScore() -> GlosaScore {
        // Handle unclosed structures
        if let intentAttrs = currentIntentAttrs {
            let entry = makeIntentEntry(
                attrs: intentAttrs,
                constraints: currentIntentConstraints,
                dialogue: currentIntentDialogue,
                scoped: false
            )
            currentIntents.append(entry)
            currentIntentAttrs = nil
        }

        if let scene = currentScene {
            scenes.append(GlosaScore.SceneEntry(
                context: scene,
                intents: currentIntents
            ))
        }

        return GlosaScore(scenes: scenes)
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        if namespaceURI == Self.glosaNamespace || elementName.hasPrefix("glosa:") {
            switch localName {
            case "SceneContext":
                let location = attributeDict["location"] ?? ""
                let time = attributeDict["time"] ?? ""
                let ambience = attributeDict["ambience"]
                currentScene = SceneContext(location: location, time: time, ambience: ambience)
                currentIntents = []
                pendingConstraints = []

            case "Intent":
                let from = attributeDict["from"] ?? ""
                let to = attributeDict["to"] ?? ""
                let pace = attributeDict["pace"]
                let spacing = attributeDict["spacing"]

                // Close any previous open intent as marker (superseded)
                if let prevAttrs = currentIntentAttrs {
                    let entry = makeIntentEntry(
                        attrs: prevAttrs,
                        constraints: currentIntentConstraints,
                        dialogue: currentIntentDialogue,
                        scoped: false
                    )
                    currentIntents.append(entry)
                    currentIntentConstraints = []
                    currentIntentDialogue = []
                }

                currentIntentAttrs = Intent(from: from, to: to, pace: pace, spacing: spacing)
                currentIntentConstraints = pendingConstraints
                pendingConstraints = []
                intentOpenedViaStartElement = true

            case "Constraint":
                let character = attributeDict["character"] ?? ""
                let direction = attributeDict["direction"] ?? ""
                let register = attributeDict["register"]
                let ceiling = attributeDict["ceiling"]
                let constraint = Constraint(
                    character: character,
                    direction: direction,
                    register: register,
                    ceiling: ceiling
                )

                if currentIntentAttrs != nil {
                    currentIntentConstraints.append(constraint)
                } else {
                    pendingConstraints.append(constraint)
                }

            default:
                break
            }
        } else if elementName == "Paragraph" {
            currentParagraphType = attributeDict["Type"]
            currentText = ""
        } else if elementName == "Text" {
            isCollectingText = true
            currentText = ""
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        if namespaceURI == Self.glosaNamespace || elementName.hasPrefix("glosa:") {
            switch localName {
            case "SceneContext":
                // Close any open intent as marker (not explicitly closed with </Intent>)
                if let intentAttrs = currentIntentAttrs {
                    let entry = makeIntentEntry(
                        attrs: intentAttrs,
                        constraints: currentIntentConstraints,
                        dialogue: currentIntentDialogue,
                        scoped: false
                    )
                    currentIntents.append(entry)
                    currentIntentAttrs = nil
                    currentIntentConstraints = []
                    currentIntentDialogue = []
                    intentOpenedViaStartElement = false
                }

                if let scene = currentScene {
                    scenes.append(GlosaScore.SceneEntry(
                        context: scene,
                        intents: currentIntents
                    ))
                }
                currentScene = nil
                currentIntents = []
                pendingConstraints = []

            case "Intent":
                // didEndElement for Intent fires in two cases:
                // 1. Self-closing <glosa:Intent .../> -- marker intent, keep open for subsequent dialogue
                // 2. Explicit closing </glosa:Intent> -- scoped intent, close now
                //
                // We distinguish by checking whether dialogue was collected.
                // Self-closing tags have zero dialogue between start and end.
                if let intentAttrs = currentIntentAttrs {
                    if currentIntentDialogue.isEmpty {
                        // Self-closing tag: this is a MARKER intent.
                        // Keep currentIntentAttrs open so subsequent dialogue is collected.
                        // Don't close it here -- it will be closed by the next Intent open,
                        // SceneContext close, or buildScore().
                        break
                    }
                    // Scoped intent with dialogue: close it now
                    let entry = makeIntentEntry(
                        attrs: intentAttrs,
                        constraints: currentIntentConstraints,
                        dialogue: currentIntentDialogue,
                        scoped: true
                    )
                    currentIntents.append(entry)
                    currentIntentAttrs = nil
                    currentIntentConstraints = []
                    currentIntentDialogue = []
                    intentOpenedViaStartElement = false
                }

            default:
                break
            }
        } else if elementName == "Text" {
            isCollectingText = false
        } else if elementName == "Paragraph" {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let type = currentParagraphType {
                if type == "Character" {
                    lastCharacterName = text
                } else if type == "Dialogue" && currentIntentAttrs != nil {
                    currentIntentDialogue.append(text)
                }
            }
            currentParagraphType = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCollectingText {
            currentText += string
        }
    }

    // MARK: - FDX delegate also handles self-closing tags

    // In XMLParser, self-closing tags (<tag/>) trigger both didStartElement and
    // didEndElement in sequence. For self-closing <glosa:Intent/>, this means
    // didStartElement opens the intent, then didEndElement immediately closes it
    // as "scoped" with 0 dialogue lines. We need to detect this case.
    //
    // The fix: in didEndElement for Intent, if there are 0 dialogue lines and
    // the intent was just opened, treat it as a marker (self-closing).
    // Actually, for FDX, self-closing <glosa:Intent.../> is a MARKER intent.
    // The didStartElement already opened it, and didEndElement will close it
    // immediately. We handle this by checking dialogue count in makeIntentEntry.

    // MARK: - Private Helpers

    private func makeIntentEntry(
        attrs: Intent,
        constraints: [Constraint],
        dialogue: [String],
        scoped: Bool
    ) -> GlosaScore.IntentEntry {
        var intent = attrs
        // If the intent element had opening+closing tags but zero dialogue,
        // it's a self-closing marker in FDX.
        if scoped && dialogue.isEmpty {
            intent.scoped = false
            intent.lineCount = nil
        } else {
            intent.scoped = scoped
            intent.lineCount = scoped ? dialogue.count : nil
        }
        return GlosaScore.IntentEntry(
            intent: intent,
            constraints: constraints,
            dialogueLines: dialogue
        )
    }
}
