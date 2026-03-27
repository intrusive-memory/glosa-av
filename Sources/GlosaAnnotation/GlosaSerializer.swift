import Foundation
import GlosaCore
import SwiftCompartido

/// Serializes a ``GlosaAnnotatedScreenplay`` back to Fountain or FDX format,
/// embedding GLOSA annotations in the appropriate format-specific notation.
///
/// ## Fountain Format
///
/// GLOSA directives are written as Fountain notes (`[[ ]]`), interleaved with
/// the screenplay elements. Each GLOSA tag occupies its own note block:
///
/// ```fountain
/// [[ <SceneContext location="..." time="..." ambience="..."> ]]
/// [[ <Constraint character="..." direction="..." ceiling="..."> ]]
/// [[ <Intent from="..." to="..." pace="..."> ]]
/// DIALOGUE LINE
/// [[ </Intent> ]]
/// [[ </SceneContext> ]]
/// ```
///
/// ## FDX Format
///
/// GLOSA directives are written as XML elements in the `glosa:` namespace,
/// embedded within the FDX `<Content>` structure:
///
/// ```xml
/// <glosa:SceneContext location="..." time="..." ambience="...">
///   <glosa:Constraint character="..." direction="..."/>
///   <glosa:Intent from="..." to="..." pace="...">
///     <Paragraph Type="Dialogue">...</Paragraph>
///   </glosa:Intent>
/// </glosa:SceneContext>
/// ```
public struct GlosaSerializer: Sendable {

    public init() {}

    // MARK: - Fountain Serialization

    /// Serialize an annotated screenplay to Fountain format with embedded GLOSA notes.
    ///
    /// Uses SwiftCompartido's ``FountainWriter`` for base screenplay content,
    /// then reconstructs the full document with GLOSA note blocks inserted
    /// at the correct positions relative to dialogue elements.
    ///
    /// - Parameter annotated: The annotated screenplay to serialize.
    /// - Returns: A Fountain-formatted string with GLOSA notes embedded.
    public func writeFountain(_ annotated: GlosaAnnotatedScreenplay) -> String {
        let score = annotated.score
        var output = ""

        // Write title page if present
        let titlePageContent = FountainWriter.titlePage(from: annotated.screenplay)
        if !titlePageContent.isEmpty {
            output += titlePageContent + "\n"
        }

        // Build a map of element indices to their scene/intent/constraint context
        // by walking the score and the screenplay elements simultaneously.
        let insertions = buildFountainInsertions(annotated: annotated, score: score)

        // Now write the body with GLOSA notes interleaved.
        for (elementIndex, element) in annotated.screenplay.elements.enumerated() {
            // Insert any GLOSA notes that should appear before this element.
            if let notes = insertions.before[elementIndex] {
                for note in notes {
                    output += "\n[[ \(note) ]]\n"
                }
            }

            // Write the element itself using the same logic as FountainWriter.
            output += writeFountainElement(element, screenplay: annotated.screenplay)

            // Insert any GLOSA notes that should appear after this element.
            if let notes = insertions.after[elementIndex] {
                for note in notes {
                    output += "\n[[ \(note) ]]\n"
                }
            }
        }

        return output.trimmingCharacters(in: .newlines)
    }

    // MARK: - FDX Serialization

    /// Serialize an annotated screenplay to FDX (Final Draft XML) format
    /// with embedded GLOSA namespace elements.
    ///
    /// The output is valid XML with a `glosa:` namespace declaration on
    /// the root `<FinalDraft>` element. Scoped Intents use opening/closing
    /// tags; marker Intents and Constraints use self-closing tags.
    ///
    /// - Parameter annotated: The annotated screenplay to serialize.
    /// - Returns: FDX XML data with GLOSA elements embedded.
    public func writeFDX(_ annotated: GlosaAnnotatedScreenplay) -> Data {
        let score = annotated.score
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\" ?>\n"
        xml += "<FinalDraft DocumentType=\"Script\" Template=\"No\" Version=\"4\""
        xml += " xmlns:glosa=\"https://intrusive-memory.productions/glosa\">\n"
        xml += "  <Content>\n"

        // Build FDX content with GLOSA elements interleaved.
        let insertions = buildFDXInsertions(annotated: annotated, score: score)

        for (elementIndex, element) in annotated.screenplay.elements.enumerated() {
            // Insert any GLOSA XML elements before this element.
            if let xmlBefore = insertions.before[elementIndex] {
                for line in xmlBefore {
                    xml += line
                }
            }

            // Write the paragraph element -- skip comment elements that are GLOSA notes.
            if element.elementType == .comment && isGlosaNote(element.elementText) {
                // Skip GLOSA comment elements -- they are regenerated from the score.
            } else {
                xml += fdxParagraphXML(for: element)
            }

            // Insert any GLOSA XML elements after this element.
            if let xmlAfter = insertions.after[elementIndex] {
                for line in xmlAfter {
                    xml += line
                }
            }
        }

        xml += "  </Content>\n"
        xml += writeFDXTitlePage(from: annotated.screenplay)
        xml += "</FinalDraft>\n"

        return Data(xml.utf8)
    }

    // MARK: - File Writing

    /// Write an annotated screenplay to disk, detecting format from the file extension.
    ///
    /// - `.fountain` extension writes Fountain format.
    /// - `.fdx` extension writes FDX (Final Draft XML) format.
    ///
    /// - Parameters:
    ///   - annotated: The annotated screenplay to write.
    ///   - url: The destination file URL.
    /// - Throws: An error if the file extension is unsupported or the write fails.
    public func write(_ annotated: GlosaAnnotatedScreenplay, to url: URL) throws {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "fountain":
            let content = writeFountain(annotated)
            try content.write(to: url, atomically: true, encoding: .utf8)
        case "fdx":
            let data = writeFDX(annotated)
            try data.write(to: url)
        default:
            throw SerializerError.unsupportedFormat(ext)
        }
    }

    /// Errors that can occur during serialization.
    public enum SerializerError: Error, CustomStringConvertible {
        case unsupportedFormat(String)

        public var description: String {
            switch self {
            case .unsupportedFormat(let ext):
                return "Unsupported file format: .\(ext). Supported formats: .fountain, .fdx"
            }
        }
    }

    // MARK: - Fountain Insertion Building

    /// Insertions to be placed before/after specific element indices in the Fountain output.
    private struct FountainInsertions {
        /// Note strings to insert before a given element index.
        var before: [Int: [String]] = [:]
        /// Note strings to insert after a given element index.
        var after: [Int: [String]] = [:]
    }

    /// Walk the score and screenplay elements to determine where GLOSA notes
    /// should be inserted in the Fountain output.
    private func buildFountainInsertions(
        annotated: GlosaAnnotatedScreenplay,
        score: GlosaScore
    ) -> FountainInsertions {
        var insertions = FountainInsertions()
        let elements = annotated.screenplay.elements

        // Build a mapping from dialogue text to element indices.
        // We need to track which dialogue elements belong to which scene/intent.
        var dialogueElementIndices: [Int] = []
        for (i, el) in elements.enumerated() {
            if el.elementType == .dialogue {
                dialogueElementIndices.append(i)
            }
        }

        var dialoguePointer = 0

        for scene in score.scenes {
            guard dialoguePointer < dialogueElementIndices.count || !scene.intents.isEmpty else {
                continue
            }

            // Find the first dialogue element in this scene to place the SceneContext before it.
            // We want to place SceneContext and scene-level Constraints before the first
            // screenplay element that is relevant (scene heading or first character/dialogue).
            let sceneStartElementIndex: Int
            if !scene.intents.isEmpty,
               let firstIntent = scene.intents.first,
               !firstIntent.dialogueLines.isEmpty,
               dialoguePointer < dialogueElementIndices.count {
                // Place before the Character element preceding the first dialogue.
                let firstDialogueIdx = dialogueElementIndices[dialoguePointer]
                sceneStartElementIndex = findCharacterElementBefore(
                    dialogueIndex: firstDialogueIdx,
                    elements: elements
                )
            } else {
                // No dialogue -- place at the start.
                sceneStartElementIndex = 0
            }

            // Also look for a scene heading before the first dialogue.
            let sceneHeadingIndex = findSceneHeadingBefore(
                elementIndex: sceneStartElementIndex,
                elements: elements
            )

            let sceneContextInsertIndex = sceneHeadingIndex ?? sceneStartElementIndex

            // Insert SceneContext note before the scene heading (or first element).
            appendInsertion(
                &insertions.before,
                index: sceneContextInsertIndex,
                note: formatSceneContextOpenTag(scene.context)
            )

            // Collect scene-level constraints (from the first intent entry).
            // Scene-level constraints are those that appear before the first intent.
            var sceneLevelConstraints: [Constraint] = []
            if let firstIntent = scene.intents.first {
                sceneLevelConstraints = firstIntent.constraints
            }

            // Insert scene-level constraints before the scene heading.
            for constraint in sceneLevelConstraints {
                appendInsertion(
                    &insertions.before,
                    index: sceneContextInsertIndex,
                    note: formatConstraintTag(constraint)
                )
            }

            // Track the last element index in this scene for placing closing tags.
            var lastElementInScene = sceneContextInsertIndex

            for (intentIndex, intentEntry) in scene.intents.enumerated() {
                let totalDialogueInIntent = intentEntry.dialogueLines.count
                guard totalDialogueInIntent > 0 else { continue }

                // Find the first dialogue element for this intent.
                guard dialoguePointer < dialogueElementIndices.count else { break }
                let firstDialogueElementIdx = dialogueElementIndices[dialoguePointer]

                // Place Intent opening tag before the Character element preceding first dialogue.
                let intentInsertIndex = findCharacterElementBefore(
                    dialogueIndex: firstDialogueElementIdx,
                    elements: elements
                )

                // Insert mid-intent constraints (those not already emitted as scene-level).
                if intentIndex > 0 {
                    for constraint in intentEntry.constraints {
                        // Only emit if this wasn't already emitted as a scene-level constraint.
                        if !sceneLevelConstraints.contains(constraint) {
                            appendInsertion(
                                &insertions.before,
                                index: intentInsertIndex,
                                note: formatConstraintTag(constraint)
                            )
                        }
                    }
                }

                appendInsertion(
                    &insertions.before,
                    index: intentInsertIndex,
                    note: formatIntentOpenTag(intentEntry.intent)
                )

                // Advance through dialogue lines in this intent.
                let lastDialoguePointer = dialoguePointer + totalDialogueInIntent - 1
                if lastDialoguePointer < dialogueElementIndices.count {
                    lastElementInScene = dialogueElementIndices[lastDialoguePointer]
                }
                dialoguePointer += totalDialogueInIntent

                // Place Intent closing tag after the last dialogue in this intent.
                if intentEntry.intent.scoped {
                    let lastDialogueIdx = dialogueElementIndices[dialoguePointer - 1]
                    appendInsertion(
                        &insertions.after,
                        index: lastDialogueIdx,
                        note: "</Intent>"
                    )
                }
            }

            // Place SceneContext closing tag after the last element in the scene.
            appendInsertion(
                &insertions.after,
                index: lastElementInScene,
                note: "</SceneContext>"
            )
        }

        return insertions
    }

    /// Find the Character element that immediately precedes a dialogue element.
    private func findCharacterElementBefore(dialogueIndex: Int, elements: [GuionElement]) -> Int {
        // Walk backward from the dialogue element to find the preceding Character.
        var idx = dialogueIndex - 1
        while idx >= 0 {
            if elements[idx].elementType == .character {
                return idx
            }
            // Skip parentheticals between character and dialogue.
            if elements[idx].elementType == .parenthetical {
                idx -= 1
                continue
            }
            break
        }
        return dialogueIndex
    }

    /// Find the closest scene heading at or before the given element index.
    private func findSceneHeadingBefore(elementIndex: Int, elements: [GuionElement]) -> Int? {
        var idx = elementIndex - 1
        while idx >= 0 {
            if elements[idx].elementType == .sceneHeading {
                return idx
            }
            // Only look back through action and non-content elements.
            if elements[idx].elementType == .action
                || elements[idx].elementType == .comment
                || elements[idx].elementType == .synopsis {
                idx -= 1
                continue
            }
            break
        }
        return nil
    }

    // MARK: - FDX Insertion Building

    /// Insertions to be placed before/after specific element indices in the FDX output.
    private struct FDXInsertions {
        var before: [Int: [String]] = [:]
        var after: [Int: [String]] = [:]
    }

    /// Walk the score and screenplay elements to determine where GLOSA XML elements
    /// should be inserted in the FDX output.
    private func buildFDXInsertions(
        annotated: GlosaAnnotatedScreenplay,
        score: GlosaScore
    ) -> FDXInsertions {
        var insertions = FDXInsertions()
        let elements = annotated.screenplay.elements

        var dialogueElementIndices: [Int] = []
        for (i, el) in elements.enumerated() {
            if el.elementType == .dialogue {
                dialogueElementIndices.append(i)
            }
        }

        var dialoguePointer = 0

        for scene in score.scenes {
            guard dialoguePointer < dialogueElementIndices.count || !scene.intents.isEmpty else {
                continue
            }

            // Find placement for SceneContext.
            let sceneStartElementIndex: Int
            if !scene.intents.isEmpty,
               let firstIntent = scene.intents.first,
               !firstIntent.dialogueLines.isEmpty,
               dialoguePointer < dialogueElementIndices.count {
                let firstDialogueIdx = dialogueElementIndices[dialoguePointer]
                sceneStartElementIndex = findCharacterElementBefore(
                    dialogueIndex: firstDialogueIdx,
                    elements: elements
                )
            } else {
                sceneStartElementIndex = 0
            }

            let sceneHeadingIndex = findSceneHeadingBefore(
                elementIndex: sceneStartElementIndex,
                elements: elements
            )
            let sceneContextInsertIndex = sceneHeadingIndex ?? sceneStartElementIndex

            // SceneContext opening XML.
            appendInsertion(
                &insertions.before,
                index: sceneContextInsertIndex,
                note: formatFDXSceneContextOpen(scene.context)
            )

            // Scene-level constraints.
            var sceneLevelConstraints: [Constraint] = []
            if let firstIntent = scene.intents.first {
                sceneLevelConstraints = firstIntent.constraints
            }

            for constraint in sceneLevelConstraints {
                appendInsertion(
                    &insertions.before,
                    index: sceneContextInsertIndex,
                    note: formatFDXConstraint(constraint)
                )
            }

            var lastElementInScene = sceneContextInsertIndex

            for (intentIndex, intentEntry) in scene.intents.enumerated() {
                let totalDialogueInIntent = intentEntry.dialogueLines.count
                guard totalDialogueInIntent > 0 else { continue }
                guard dialoguePointer < dialogueElementIndices.count else { break }

                let firstDialogueElementIdx = dialogueElementIndices[dialoguePointer]
                let intentInsertIndex = findCharacterElementBefore(
                    dialogueIndex: firstDialogueElementIdx,
                    elements: elements
                )

                // Mid-intent constraints.
                if intentIndex > 0 {
                    for constraint in intentEntry.constraints {
                        if !sceneLevelConstraints.contains(constraint) {
                            appendInsertion(
                                &insertions.before,
                                index: intentInsertIndex,
                                note: formatFDXConstraint(constraint)
                            )
                        }
                    }
                }

                if intentEntry.intent.scoped {
                    // Scoped: opening tag.
                    appendInsertion(
                        &insertions.before,
                        index: intentInsertIndex,
                        note: formatFDXIntentOpen(intentEntry.intent)
                    )
                } else {
                    // Marker: self-closing tag.
                    appendInsertion(
                        &insertions.before,
                        index: intentInsertIndex,
                        note: formatFDXIntentSelfClosing(intentEntry.intent)
                    )
                }

                let lastDialoguePointer = dialoguePointer + totalDialogueInIntent - 1
                if lastDialoguePointer < dialogueElementIndices.count {
                    lastElementInScene = dialogueElementIndices[lastDialoguePointer]
                }
                dialoguePointer += totalDialogueInIntent

                // Closing tag for scoped intents.
                if intentEntry.intent.scoped {
                    let lastDialogueIdx = dialogueElementIndices[dialoguePointer - 1]
                    appendInsertion(
                        &insertions.after,
                        index: lastDialogueIdx,
                        note: "    </glosa:Intent>\n"
                    )
                }
            }

            // SceneContext closing XML.
            appendInsertion(
                &insertions.after,
                index: lastElementInScene,
                note: "    </glosa:SceneContext>\n"
            )
        }

        return insertions
    }

    // MARK: - Fountain Formatting Helpers

    /// Format a SceneContext opening tag for Fountain.
    private func formatSceneContextOpenTag(_ ctx: SceneContext) -> String {
        var tag = "<SceneContext location=\"\(ctx.location)\" time=\"\(ctx.time)\""
        if let ambience = ctx.ambience, !ambience.isEmpty {
            tag += " ambience=\"\(ambience)\""
        }
        tag += ">"
        return tag
    }

    /// Format an Intent opening tag for Fountain.
    private func formatIntentOpenTag(_ intent: Intent) -> String {
        var tag = "<Intent from=\"\(intent.from)\" to=\"\(intent.to)\""
        if let pace = intent.pace, !pace.isEmpty {
            tag += " pace=\"\(pace)\""
        }
        if let spacing = intent.spacing, !spacing.isEmpty {
            tag += " spacing=\"\(spacing)\""
        }
        tag += ">"
        return tag
    }

    /// Format a Constraint tag for Fountain.
    private func formatConstraintTag(_ constraint: Constraint) -> String {
        var tag = "<Constraint character=\"\(constraint.character)\" direction=\"\(constraint.direction)\""
        if let register = constraint.register, !register.isEmpty {
            tag += " register=\"\(register)\""
        }
        if let ceiling = constraint.ceiling, !ceiling.isEmpty {
            tag += " ceiling=\"\(ceiling)\""
        }
        tag += ">"
        return tag
    }

    // MARK: - FDX Formatting Helpers

    /// Format a SceneContext opening XML element for FDX.
    private func formatFDXSceneContextOpen(_ ctx: SceneContext) -> String {
        var xml = "    <glosa:SceneContext location=\"\(escapeXML(ctx.location))\" time=\"\(escapeXML(ctx.time))\""
        if let ambience = ctx.ambience, !ambience.isEmpty {
            xml += " ambience=\"\(escapeXML(ambience))\""
        }
        xml += ">\n"
        return xml
    }

    /// Format an Intent opening XML element for FDX (scoped).
    private func formatFDXIntentOpen(_ intent: Intent) -> String {
        var xml = "    <glosa:Intent from=\"\(escapeXML(intent.from))\" to=\"\(escapeXML(intent.to))\""
        if let pace = intent.pace, !pace.isEmpty {
            xml += " pace=\"\(escapeXML(pace))\""
        }
        if let spacing = intent.spacing, !spacing.isEmpty {
            xml += " spacing=\"\(escapeXML(spacing))\""
        }
        xml += ">\n"
        return xml
    }

    /// Format an Intent self-closing XML element for FDX (marker).
    private func formatFDXIntentSelfClosing(_ intent: Intent) -> String {
        var xml = "    <glosa:Intent from=\"\(escapeXML(intent.from))\" to=\"\(escapeXML(intent.to))\""
        if let pace = intent.pace, !pace.isEmpty {
            xml += " pace=\"\(escapeXML(pace))\""
        }
        if let spacing = intent.spacing, !spacing.isEmpty {
            xml += " spacing=\"\(escapeXML(spacing))\""
        }
        xml += "/>\n"
        return xml
    }

    /// Format a Constraint self-closing XML element for FDX.
    private func formatFDXConstraint(_ constraint: Constraint) -> String {
        var xml = "    <glosa:Constraint character=\"\(escapeXML(constraint.character))\" direction=\"\(escapeXML(constraint.direction))\""
        if let register = constraint.register, !register.isEmpty {
            xml += " register=\"\(escapeXML(register))\""
        }
        if let ceiling = constraint.ceiling, !ceiling.isEmpty {
            xml += " ceiling=\"\(escapeXML(ceiling))\""
        }
        xml += "/>\n"
        return xml
    }

    /// Write FDX title page from a screenplay.
    private func writeFDXTitlePage(from screenplay: GuionParsedElementCollection) -> String {
        guard !screenplay.titlePage.isEmpty else {
            return "  <TitlePage>\n    <Content/>\n  </TitlePage>\n"
        }

        var xml = "  <TitlePage>\n"
        xml += "    <Content>\n"

        for dictionary in screenplay.titlePage {
            for (_, values) in dictionary {
                for value in values {
                    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        continue
                    }
                    xml += "      <Paragraph Alignment=\"Center\" FirstIndent=\"0.00\" Leading=\"Regular\" LeftIndent=\"1.00\" RightIndent=\"7.50\" SpaceBefore=\"0\" Spacing=\"1\" StartsNewPage=\"No\">\n"
                    xml += "        <Text>\(escapeXML(value))</Text>\n"
                    xml += "      </Paragraph>\n"
                }
            }
        }

        xml += "    </Content>\n"
        xml += "  </TitlePage>\n"
        return xml
    }

    // MARK: - Fountain Element Writing

    /// Write a single screenplay element in Fountain format.
    /// Mirrors FountainWriter.body() logic for a single element.
    private func writeFountainElement(
        _ element: GuionElement,
        screenplay: GuionParsedElementCollection
    ) -> String {
        // Skip empty elements (except page breaks).
        let trimmedText = element.elementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmedText.isEmpty || element.elementText.isEmpty)
            && element.elementType != .pageBreak {
            return ""
        }

        // Skip comment elements that are GLOSA notes (they are regenerated from the score).
        if element.elementType == .comment && isGlosaNote(element.elementText) {
            return ""
        }

        var textToWrite = ""

        switch element.elementType {
        case .comment:
            textToWrite = "[[\(element.elementText)]]"
        case .boneyard:
            textToWrite = "/*\(element.elementText)*/"
        case .synopsis:
            textToWrite = "=\(element.elementText)"
        case .sceneHeading:
            textToWrite = element.elementText
            let testString = "\n\(element.elementText)\n"
            if !matchesFountainSceneHeader(testString) {
                textToWrite = ".\(textToWrite)"
            }
            if !screenplay.suppressSceneNumbers, let sceneNumber = element.sceneNumber {
                textToWrite = "\(textToWrite) #\(sceneNumber)#"
            }
        case .pageBreak:
            textToWrite = "===="
        case .sectionHeading(let level):
            let sectionDepthMarkup = String(repeating: "#", count: level)
            let text = element.elementText.hasPrefix(" ")
                ? String(element.elementText.dropFirst())
                : element.elementText
            textToWrite = "\(sectionDepthMarkup) \(text)"
        case .transition:
            if !matchesFountainTransition(element.elementText) {
                textToWrite = "> \(element.elementText)"
            } else {
                textToWrite = element.elementText
            }
        default:
            textToWrite = element.elementText
        }

        if element.isCentered {
            if textToWrite.hasSuffix(" ") {
                textToWrite = "> \(textToWrite)<"
            } else {
                textToWrite = "> \(textToWrite) <"
            }
        }

        if element.elementType == .character && element.isDualDialogue {
            textToWrite = "\(textToWrite) ^"
        }

        // Character elements need a blank line before them; dialogue/parenthetical/comment do not.
        if element.elementType == .dialogue
            || element.elementType == .parenthetical
            || element.elementType == .comment {
            return "\(textToWrite)\n"
        } else {
            return "\n\(textToWrite)\n"
        }
    }

    // MARK: - FDX Paragraph Writing

    /// Write a single element as an FDX Paragraph XML element.
    private func fdxParagraphXML(for element: GuionElement) -> String {
        // Skip empty elements (except page breaks).
        let trimmedText = element.elementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmedText.isEmpty || element.elementText.isEmpty)
            && element.elementType != .pageBreak {
            return ""
        }

        var paragraph = "    <Paragraph Type=\"\(escapeXML(element.elementType.description))\">\n"

        if let sceneNumber = element.sceneNumber, element.elementType == .sceneHeading {
            paragraph += "      <SceneProperties Number=\"\(escapeXML(sceneNumber))\"/>\n"
        }

        let text = escapeXML(element.elementText)
        paragraph += "      <Text>\(text)</Text>\n"
        paragraph += "    </Paragraph>\n"
        return paragraph
    }

    // MARK: - Utility Helpers

    /// Check if a comment element's text contains a GLOSA tag.
    private func isGlosaNote(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("<SceneContext")
            || trimmed.contains("</SceneContext>")
            || trimmed.contains("<Intent")
            || trimmed.contains("</Intent>")
            || trimmed.contains("<Constraint")
    }

    /// Escape special XML characters in a string.
    private func escapeXML(_ text: String) -> String {
        var escaped = text
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&apos;")
        return escaped
    }

    /// Append a note to an insertion dictionary.
    private func appendInsertion(
        _ dict: inout [Int: [String]],
        index: Int,
        note: String
    ) {
        dict[index, default: []].append(note)
    }

    /// Simple check for Fountain scene heading pattern.
    private func matchesFountainSceneHeader(_ text: String) -> Bool {
        let pattern = #"(?m)^(INT|EXT|EST|INT\./EXT|INT/EXT|I/E)[\.\s]"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Simple check for Fountain transition pattern.
    private func matchesFountainTransition(_ text: String) -> Bool {
        let pattern = #"^[A-Z\s]+TO:$"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
