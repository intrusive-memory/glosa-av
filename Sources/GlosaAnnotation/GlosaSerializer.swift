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
    // We zip screenplay.elements with annotatedElements so we have access to
    // breathPoints when emitting dialogue lines.
    for (elementIndex, annotatedElement) in annotated.annotatedElements.enumerated() {
      let element = annotatedElement.element

      // Insert any GLOSA notes that should appear before this element.
      if let notes = insertions.before[elementIndex] {
        for note in notes {
          output += "\n[[ \(note) ]]\n"
        }
      }

      // Write the element itself using the same logic as FountainWriter,
      // injecting breath inline notes into dialogue lines that carry breath points.
      output += writeFountainElement(
        annotatedElement,
        screenplay: annotated.screenplay
      )

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

  /// Serializes an annotated screenplay to FDX (Final Draft XML) format
  /// with embedded GLOSA namespace elements.
  ///
  /// The `glosa:` XML namespace is declared on the root `<FinalDraft>`
  /// element **only** when at least one `glosa:` element (SceneContext,
  /// Intent, Constraint, `<glosa:breath/>`, or `<glosa:pause/>`) appears
  /// in the document. When no GLOSA elements are present the namespace
  /// declaration is omitted, keeping the output minimal for
  /// annotation-free screenplays.
  ///
  /// Scoped Intents use opening/closing tags; marker Intents and
  /// Constraints use self-closing tags. Dialogue paragraphs that carry
  /// breath or pause points emit interleaved `<glosa:breath/>` and/or
  /// `<glosa:pause/>` self-closing elements between `<Text>` runs
  /// (spec §5.2).
  ///
  /// - Parameter annotated: The annotated screenplay to serialize.
  /// - Returns: FDX XML data with GLOSA elements embedded.
  public func writeFDX(_ annotated: GlosaAnnotatedScreenplay) -> Data {
    let score = annotated.score

    // Determine whether any glosa: element will appear in the output.
    // If so, the namespace declaration is required; otherwise it is
    // omitted to keep the document minimal.
    let hasGlosaElements =
      !score.scenes.isEmpty
      || annotated.annotatedElements.contains { !$0.breathPoints.isEmpty }
      || annotated.annotatedElements.contains { !$0.pausePoints.isEmpty }

    var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\" ?>\n"
    xml += "<FinalDraft DocumentType=\"Script\" Template=\"No\" Version=\"4\""
    if hasGlosaElements {
      xml += " xmlns:glosa=\"https://intrusive-memory.productions/glosa\""
    }
    xml += ">\n"
    xml += "  <Content>\n"

    // Build a lookup from screenplay-element index to annotated element so
    // that the dialogue paragraph writer can access breathPoints.
    var annotatedByIndex: [Int: GlosaAnnotatedElement] = [:]
    for (elementIndex, annotatedElement) in annotated.annotatedElements.enumerated() {
      annotatedByIndex[elementIndex] = annotatedElement
    }

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
        let annotatedElement = annotatedByIndex[elementIndex]
        xml += fdxParagraphXML(for: element, annotatedElement: annotatedElement)
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
        dialoguePointer < dialogueElementIndices.count
      {
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
        || elements[idx].elementType == .synopsis
      {
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
        dialoguePointer < dialogueElementIndices.count
      {
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
    var tag =
      "<Constraint character=\"\(constraint.character)\" direction=\"\(constraint.direction)\""
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
    var xml =
      "    <glosa:SceneContext location=\"\(escapeXML(ctx.location))\" time=\"\(escapeXML(ctx.time))\""
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
    var xml =
      "    <glosa:Constraint character=\"\(escapeXML(constraint.character))\" direction=\"\(escapeXML(constraint.direction))\""
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
          xml +=
            "      <Paragraph Alignment=\"Center\" FirstIndent=\"0.00\" Leading=\"Regular\" LeftIndent=\"1.00\" RightIndent=\"7.50\" SpaceBefore=\"0\" Spacing=\"1\" StartsNewPage=\"No\">\n"
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

  /// Write a single annotated screenplay element in Fountain format.
  ///
  /// For dialogue elements that carry `breathPoints`, this method injects
  /// `[[<breath …/>]]` inline notes at the correct character offsets within
  /// the dialogue prose before emitting the line. The offsets are measured
  /// against the notes-stripped prose (the coordinate system produced by the
  /// parser), so the injected notes are the true inverse of the parse step.
  ///
  /// All other element types are serialized identically to the plain
  /// `GuionElement` path — breath injection is dialogue-only.
  private func writeFountainElement(
    _ annotatedElement: GlosaAnnotatedElement,
    screenplay: GuionParsedElementCollection
  ) -> String {
    let element = annotatedElement.element

    // Skip empty elements (except page breaks).
    let trimmedText = element.elementText.trimmingCharacters(in: .whitespacesAndNewlines)
    if (trimmedText.isEmpty || element.elementText.isEmpty)
      && element.elementType != .pageBreak
    {
      return ""
    }

    // Skip comment elements that are GLOSA notes (they are regenerated from the score).
    if element.elementType == .comment && isGlosaNote(element.elementText) {
      return ""
    }

    var textToWrite = ""

    switch element.elementType {
    case .dialogue:
      // Inject [[<breath …/>]] and [[<pause …/>]] inline notes at the correct
      // offsets when the annotated element carries breath or pause points.
      let breathPoints = annotatedElement.breathPoints
      let pausePoints = annotatedElement.pausePoints
      if breathPoints.isEmpty && pausePoints.isEmpty {
        textToWrite = element.elementText
      } else {
        // Inject breath notes first, then pause notes. Because injection
        // works in reverse offset order, the combined result is correct as
        // long as co-located breaths have already been collapsed by the
        // compiler (guaranteed by the Sortie 3 same-offset collapse).
        var text = element.elementText
        if !breathPoints.isEmpty {
          text = injectBreathNotes(into: text, breathPoints: breathPoints)
        }
        if !pausePoints.isEmpty {
          text = injectPauseNotes(into: text, pausePoints: pausePoints)
        }
        textToWrite = text
      }
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
      let text =
        element.elementText.hasPrefix(" ")
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
      || element.elementType == .comment
    {
      return "\(textToWrite)\n"
    } else {
      return "\n\(textToWrite)\n"
    }
  }

  // MARK: - Breath Inline Note Injection (Fountain)

  /// Inject `[[<breath …/>]]` inline notes into a dialogue prose string at the
  /// character offsets specified by `breathPoints`.
  ///
  /// The `breathPoints` array must be sorted ascending by `offset`; the
  /// compiler guarantees this. Injection is performed in *reverse* offset
  /// order so that earlier character positions are not shifted by later
  /// insertions.
  ///
  /// Offsets are measured in `unicodeScalars.count` of the notes-stripped
  /// prose — exactly the coordinate system the parser used when it extracted
  /// the breath positions — so this method is the true inverse of
  /// `GlosaParser.extractBreaths(from:dialogueLineIndex:line:)`.
  ///
  /// - Parameters:
  ///   - prose: The notes-stripped dialogue text to annotate.
  ///   - breathPoints: The sorted (ascending) breath points to inject.
  /// - Returns: The prose with `[[<breath …/>]]` notes inserted.
  private func injectBreathNotes(into prose: String, breathPoints: [BreathPoint]) -> String {
    // Walk in reverse order so earlier offsets are not displaced by
    // insertions at higher offsets.
    var scalars = Array(prose.unicodeScalars)
    for breathPoint in breathPoints.reversed() {
      let offset = breathPoint.offset
      // Guard against out-of-range offsets (defensive; valid data from the
      // compiler should never exceed the prose length).
      guard offset >= 0, offset <= scalars.count else { continue }
      let tag = breathNoteTag(for: breathPoint)
      let tagScalars = tag.unicodeScalars
      scalars.insert(contentsOf: tagScalars, at: offset)
    }
    return String(String.UnicodeScalarView(scalars))
  }

  /// Produce the canonical `[[<breath …/>]]` inline-note string for a single
  /// `BreathPoint`.
  ///
  /// Canonical attribute rules (spec §4.2 and methodology rule 6):
  /// - `strength` attribute is omitted when the value is `.medium` (the
  ///   default). When non-default it is the sole attribute.
  /// - `length` is **never** emitted — duration moved to `Pause`/`PausePoint`
  ///   in Sortie 1; `<breath>` is now a phrasing-only element with no
  ///   silence duration.
  /// - Bare form: `[[<breath/>]]`. Non-default strength: `[[<breath strength="…"/>]]`.
  ///
  /// - Parameter breathPoint: The breath point to format.
  /// - Returns: The canonical `[[<breath …/>]]` string.
  private func breathNoteTag(for breathPoint: BreathPoint) -> String {
    var attributes = ""

    // strength attribute — omit when default (.medium).
    if breathPoint.strength != .medium {
      attributes += " strength=\"\(breathPoint.strength.rawValue)\""
    }

    return "[[<breath\(attributes)/>]]"
  }

  // MARK: - Pause Inline Note Injection (Fountain)

  /// Inject `[[<pause …/>]]` inline notes into a dialogue prose string at the
  /// character offsets specified by `pausePoints`.
  ///
  /// The `pausePoints` array must be sorted ascending by `offset`; the
  /// compiler guarantees this. Injection is performed in *reverse* offset
  /// order so that earlier character positions are not shifted by later
  /// insertions.
  ///
  /// Offsets are measured in `unicodeScalars.count` of the notes-stripped
  /// prose — exactly the coordinate system the parser used when it extracted
  /// the pause positions — so this method is the true inverse of
  /// `GlosaParser.extractPauses(from:dialogueLineIndex:line:)`.
  ///
  /// - Parameters:
  ///   - prose: The notes-stripped dialogue text to annotate.
  ///   - pausePoints: The sorted (ascending) pause points to inject.
  /// - Returns: The prose with `[[<pause …/>]]` notes inserted.
  private func injectPauseNotes(into prose: String, pausePoints: [PausePoint]) -> String {
    // Walk in reverse order so earlier offsets are not displaced by
    // insertions at higher offsets.
    var scalars = Array(prose.unicodeScalars)
    for pausePoint in pausePoints.reversed() {
      let offset = pausePoint.offset
      // Guard against out-of-range offsets (defensive; valid data from the
      // compiler should never exceed the prose length).
      guard offset >= 0, offset <= scalars.count else { continue }
      let tag = pauseNoteTag(for: pausePoint)
      let tagScalars = tag.unicodeScalars
      scalars.insert(contentsOf: tagScalars, at: offset)
    }
    return String(String.UnicodeScalarView(scalars))
  }

  /// Produce the canonical `[[<pause …/>]]` inline-note string for a single
  /// `PausePoint`.
  ///
  /// Canonical attribute rules (spec §4.2 and methodology rule 6):
  /// - `length` attribute is omitted when the value is `.period`
  ///   (the default for pause).
  /// - `.explicit(TimeInterval)` serializes as `length="<ms>ms"` using
  ///   `Int((seconds * 1000).rounded())` per methodology rule 5. Truncation
  ///   is never used so `0.35 → "350ms"` is exact.
  /// - No inner whitespace in `<pause/>` when bare: either `[[<pause/>]]`
  ///   (default length omitted) or `[[<pause length="…"/>]]`.
  ///
  /// - Parameter pausePoint: The pause point to format.
  /// - Returns: The canonical `[[<pause …/>]]` string.
  private func pauseNoteTag(for pausePoint: PausePoint) -> String {
    var attributes = ""

    // length attribute — omit when default (.period).
    if pausePoint.length != .period {
      attributes += " length=\"\(fountainLengthAttribute(pausePoint.length))\""
    }

    return "[[<pause\(attributes)/>]]"
  }

  /// Convert a `PauseLength` to its Fountain attribute-value string.
  ///
  /// Named cases map to the wire tokens the parser recognizes (see
  /// `GlosaParser.parseLengthAttribute(_:)`). The `.explicit` case uses
  /// integer milliseconds rounded via `.rounded()` — never truncated —
  /// so the round-trip `.explicit(0.35) → "350ms" → .explicit(0.35)` is
  /// preserved per methodology rule 5.
  private func fountainLengthAttribute(_ length: PauseLength) -> String {
    switch length {
    case .comma: return "comma"
    case .semicolon: return "semicolon"
    case .period: return "period"
    case .emDash: return "em-dash"
    case .beat: return "beat"
    case .explicit(let seconds):
      let ms = Int((seconds * 1000).rounded())
      return "\(ms)ms"
    }
  }

  // MARK: - FDX Paragraph Writing

  /// Write a single element as an FDX Paragraph XML element.
  ///
  /// When `annotatedElement` is provided and the element is a dialogue
  /// paragraph with non-empty `breathPoints`, the prose is split into
  /// `<Text>` runs separated by `<glosa:breath/>` self-closing elements
  /// (spec §5.2). Whitespace that precedes each break in the prose is
  /// placed **after** the breath element in the following `<Text>` run
  /// (the S3 forward-hint) so that the FDX parser's cumulative-scalar
  /// offset arithmetic produces the same offsets as the Fountain path.
  ///
  /// All other element types are serialized as a single `<Text>` run.
  private func fdxParagraphXML(
    for element: GuionElement,
    annotatedElement: GlosaAnnotatedElement? = nil
  ) -> String {
    // Skip empty elements (except page breaks).
    let trimmedText = element.elementText.trimmingCharacters(in: .whitespacesAndNewlines)
    if (trimmedText.isEmpty || element.elementText.isEmpty)
      && element.elementType != .pageBreak
    {
      return ""
    }

    var paragraph = "    <Paragraph Type=\"\(escapeXML(element.elementType.description))\">\n"

    if let sceneNumber = element.sceneNumber, element.elementType == .sceneHeading {
      paragraph += "      <SceneProperties Number=\"\(escapeXML(sceneNumber))\"/>\n"
    }

    // For dialogue paragraphs with breath or pause points, emit interleaved
    // <Text>/<glosa:breath/>/<glosa:pause/> runs; otherwise emit a single
    // <Text> run.
    if element.elementType == .dialogue,
      let annotated = annotatedElement,
      !annotated.breathPoints.isEmpty || !annotated.pausePoints.isEmpty
    {
      paragraph += fdxDialogueBreathAndPauseRuns(
        prose: element.elementText,
        breathPoints: annotated.breathPoints,
        pausePoints: annotated.pausePoints
      )
    } else {
      let text = escapeXML(element.elementText)
      paragraph += "      <Text>\(text)</Text>\n"
    }

    paragraph += "    </Paragraph>\n"
    return paragraph
  }

  /// A unified marker used to walk breath and pause points together in
  /// offset order when building interleaved FDX `<Text>` runs.
  private enum FDXMarker {
    case breath(BreathPoint)
    case pause(PausePoint)

    var offset: Int {
      switch self {
      case .breath(let bp): return bp.offset
      case .pause(let pp): return pp.offset
      }
    }
  }

  /// Emit interleaved `<Text>`, `<glosa:breath/>`, and `<glosa:pause/>`
  /// children for a dialogue paragraph that carries breath and/or pause points.
  ///
  /// The prose is sliced at each point's offset (measured in Unicode
  /// scalars). The trailing text of each slice is placed in the
  /// **following** `<Text>` run so that the FDX parser's cumulative offset
  /// (sum of preceding `<Text>` runs) equals the Fountain inline-note offset.
  ///
  /// Breath and pause markers are merged and sorted ascending by offset so
  /// the slice walk is a single left-to-right pass. The compiler's same-offset
  /// collapse guarantees no breath and pause share the same offset.
  ///
  /// - Parameters:
  ///   - prose: The notes-stripped dialogue text.
  ///   - breathPoints: Breath points sorted ascending by offset.
  ///   - pausePoints: Pause points sorted ascending by offset.
  /// - Returns: An XML fragment (indented 6 spaces) ready for insertion
  ///   inside the `<Paragraph>` element.
  private func fdxDialogueBreathAndPauseRuns(
    prose: String,
    breathPoints: [BreathPoint],
    pausePoints: [PausePoint]
  ) -> String {
    // Merge and sort ascending by offset.
    var markers: [FDXMarker] = breathPoints.map { .breath($0) } + pausePoints.map { .pause($0) }
    markers.sort { $0.offset < $1.offset }

    var result = ""
    let scalars = Array(prose.unicodeScalars)
    var cursor = 0  // index into `scalars`

    for marker in markers {
      let offset = marker.offset
      // Clamp to valid range (defensive; compiler-supplied data should be valid).
      let clampedOffset = min(max(offset, cursor), scalars.count)

      // Text run: scalars[cursor ..< clampedOffset].
      let runScalars = scalars[cursor..<clampedOffset]
      let runText = String(String.UnicodeScalarView(runScalars))
      result += "      <Text>\(escapeXML(runText))</Text>\n"

      // Emit the appropriate GLOSA element.
      switch marker {
      case .breath(let bp):
        result += "      \(fdxBreathElement(bp))\n"
      case .pause(let pp):
        result += "      \(fdxPauseElement(pp))\n"
      }

      cursor = clampedOffset
    }

    // Final text run: scalars[cursor...] (everything after the last marker).
    let tailScalars = scalars[cursor...]
    let tailText = String(String.UnicodeScalarView(tailScalars))
    result += "      <Text>\(escapeXML(tailText))</Text>\n"

    return result
  }

  /// Produce a `<glosa:breath…/>` self-closing element string for a single
  /// `BreathPoint`.
  ///
  /// Default-omission rules (spec §4.2, methodology rule 6):
  /// - `strength` is omitted when the value is `.medium` (the default).
  /// - `length` is no longer a `BreathPoint` attribute (duration moved to
  ///   `Pause` in Sortie 1); this element never emits `length`.
  private func fdxBreathElement(_ breathPoint: BreathPoint) -> String {
    var attributes = ""

    // strength — omit when default (.medium).
    if breathPoint.strength != .medium {
      attributes += " strength=\"\(breathPoint.strength.rawValue)\""
    }

    return "<glosa:breath\(attributes)/>"
  }

  /// Produce a `<glosa:pause…/>` self-closing element string for a single
  /// `PausePoint`.
  ///
  /// Default-omission rules (spec §4.2, methodology rule 6):
  /// - `length` is omitted when the value is `.period` (the default for pause).
  /// - `.explicit(TimeInterval)` serializes as `length="<ms>ms"` using
  ///   `Int((seconds * 1000).rounded())` per methodology rule 5.
  private func fdxPauseElement(_ pausePoint: PausePoint) -> String {
    var attributes = ""

    // length — omit when default (.period).
    if pausePoint.length != .period {
      attributes += " length=\"\(fountainLengthAttribute(pausePoint.length))\""
    }

    return "<glosa:pause\(attributes)/>"
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
