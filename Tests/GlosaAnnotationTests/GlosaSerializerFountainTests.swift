import Foundation
import GlosaAnnotation
import GlosaCore
import SwiftCompartido
import Testing

@Suite("GlosaSerializer Fountain Tests")
struct GlosaSerializerFountainTests {

  // MARK: - Test Data

  /// A Fountain screenplay with GLOSA annotations matching Example 1 from EXAMPLES.md
  /// (simplified for testing).
  private let annotatedFountainText = """
    [[ <SceneContext location="steam room" time="morning" ambience="hissing steam, echoing tile"> ]]

    [[ <Constraint character="BERNARD" direction="nervous amateur, out of his depth" ceiling="moderate"> ]]
    [[ <Constraint character="KILLIAN" direction="clinical detachment, calm and methodical" ceiling="subdued"> ]]

    INT. STEAM ROOM - DAY

    BERNARD and KILLIAN sit in a steam room.

    [[ <Intent from="conspiratorial calm" to="grim resolve" pace="slow"> ]]

    BERNARD
    Have you thought about how I'm going to do it?

    KILLIAN
    I can't think about anything else.

    BERNARD
    And?

    KILLIAN
    Insulin. You need to give him a mega dose of the fast acting stuff.

    [[ </Intent> ]]

    [[ <Intent from="absurd" to="darkly comic" pace="moderate"> ]]

    KILLIAN
    Slutty shorts.

    BERNARD
    Slutty... Shorts?

    [[ </Intent> ]]

    [[ </SceneContext> ]]
    """

  // MARK: - Round-Trip Tests

  @Test("Fountain round-trip: parse -> compile -> serialize -> parse produces identical GlosaScore")
  func fountainRoundTrip() throws {
    // Step 1: Parse the Fountain text into a screenplay.
    let screenplay = try GuionParsedElementCollection(string: annotatedFountainText)

    // Step 2: Extract GLOSA notes and dialogue lines from the parsed screenplay.
    let (notes, dialogueLines) = extractNotesAndDialogue(from: screenplay)

    // Step 3: Compile the GLOSA annotations.
    let compiler = GlosaCompiler()
    let compilationResult = try compiler.compile(
      fountainNotes: notes,
      dialogueLines: dialogueLines
    )

    // Step 4: Parse the score from the notes (for embedding in annotated screenplay).
    let parser = GlosaParser()
    let originalScore = parser.parseFountain(notes: notes)

    // Step 5: Build the annotated screenplay.
    let annotated = GlosaAnnotatedScreenplay.build(
      from: screenplay,
      compilationResult: compilationResult,
      score: originalScore
    )

    // Step 6: Serialize back to Fountain.
    let serializer = GlosaSerializer()
    let serializedFountain = serializer.writeFountain(annotated)

    // Step 7: Parse the serialized output again.
    let reparsed = try GuionParsedElementCollection(string: serializedFountain)
    let (reparsedNotes, reparsedDialogue) = extractNotesAndDialogue(from: reparsed)

    // Step 8: Compile the reparsed annotations.
    let reparsedResult = try compiler.compile(
      fountainNotes: reparsedNotes,
      dialogueLines: reparsedDialogue
    )

    // Step 9: Parse the reparsed score.
    let reparsedScore = parser.parseFountain(notes: reparsedNotes)

    // Verify the scores are structurally identical.
    #expect(
      originalScore.scenes.count == reparsedScore.scenes.count,
      "Scene count mismatch: original \(originalScore.scenes.count) vs reparsed \(reparsedScore.scenes.count)"
    )

    for (sceneIdx, (origScene, reparsedScene)) in zip(originalScore.scenes, reparsedScore.scenes)
      .enumerated()
    {
      // Verify SceneContext.
      #expect(
        origScene.context.location == reparsedScene.context.location,
        "Scene \(sceneIdx): location mismatch")
      #expect(
        origScene.context.time == reparsedScene.context.time,
        "Scene \(sceneIdx): time mismatch")
      #expect(
        origScene.context.ambience == reparsedScene.context.ambience,
        "Scene \(sceneIdx): ambience mismatch")

      // Verify Intents.
      #expect(
        origScene.intents.count == reparsedScene.intents.count,
        "Scene \(sceneIdx): intent count mismatch: original \(origScene.intents.count) vs reparsed \(reparsedScene.intents.count)"
      )

      for (intentIdx, (origIntent, reparsedIntent)) in zip(origScene.intents, reparsedScene.intents)
        .enumerated()
      {
        #expect(
          origIntent.intent.from == reparsedIntent.intent.from,
          "Scene \(sceneIdx), Intent \(intentIdx): 'from' mismatch")
        #expect(
          origIntent.intent.to == reparsedIntent.intent.to,
          "Scene \(sceneIdx), Intent \(intentIdx): 'to' mismatch")
        #expect(
          origIntent.intent.pace == reparsedIntent.intent.pace,
          "Scene \(sceneIdx), Intent \(intentIdx): 'pace' mismatch")
        #expect(
          origIntent.intent.scoped == reparsedIntent.intent.scoped,
          "Scene \(sceneIdx), Intent \(intentIdx): 'scoped' mismatch")
        #expect(
          origIntent.dialogueLines.count == reparsedIntent.dialogueLines.count,
          "Scene \(sceneIdx), Intent \(intentIdx): dialogue count mismatch")
      }
    }

    // Verify instruct strings are identical.
    #expect(
      compilationResult.instructs.count == reparsedResult.instructs.count,
      "Instruct count mismatch: original \(compilationResult.instructs.count) vs reparsed \(reparsedResult.instructs.count)"
    )

    for (key, originalInstruct) in compilationResult.instructs {
      let reparsedInstruct = reparsedResult.instructs[key]
      #expect(
        originalInstruct == reparsedInstruct,
        "Instruct mismatch at line \(key)")
    }
  }

  @Test("Serialized Fountain output is valid Fountain (removing [[ ]] produces clean screenplay)")
  func serializedFountainIsValid() throws {
    let screenplay = try GuionParsedElementCollection(string: annotatedFountainText)
    let (notes, dialogueLines) = extractNotesAndDialogue(from: screenplay)

    let compiler = GlosaCompiler()
    let compilationResult = try compiler.compile(
      fountainNotes: notes,
      dialogueLines: dialogueLines
    )

    let parser = GlosaParser()
    let score = parser.parseFountain(notes: notes)

    let annotated = GlosaAnnotatedScreenplay.build(
      from: screenplay,
      compilationResult: compilationResult,
      score: score
    )

    let serializer = GlosaSerializer()
    let serializedFountain = serializer.writeFountain(annotated)

    // Remove all [[ ... ]] blocks to produce a clean screenplay.
    let cleanFountain = removeNoteBlocks(from: serializedFountain)

    // Parse the clean Fountain -- it should parse without issues.
    let cleanScreenplay = try GuionParsedElementCollection(string: cleanFountain)

    // The clean screenplay should have the same dialogue elements.
    let cleanDialogue = cleanScreenplay.elements.filter { $0.elementType == .dialogue }
    let originalDialogue = screenplay.elements.filter { $0.elementType == .dialogue }

    #expect(
      cleanDialogue.count == originalDialogue.count,
      "Dialogue count mismatch after removing notes: clean \(cleanDialogue.count) vs original \(originalDialogue.count)"
    )

    for (orig, clean) in zip(originalDialogue, cleanDialogue) {
      #expect(orig.elementText == clean.elementText)
    }
  }

  @Test("Serialized Fountain contains all GLOSA tags from score")
  func serializedFountainContainsAllGlosaTags() throws {
    let screenplay = try GuionParsedElementCollection(string: annotatedFountainText)
    let (notes, dialogueLines) = extractNotesAndDialogue(from: screenplay)

    let compiler = GlosaCompiler()
    let compilationResult = try compiler.compile(
      fountainNotes: notes,
      dialogueLines: dialogueLines
    )

    let parser = GlosaParser()
    let score = parser.parseFountain(notes: notes)

    let annotated = GlosaAnnotatedScreenplay.build(
      from: screenplay,
      compilationResult: compilationResult,
      score: score
    )

    let serializer = GlosaSerializer()
    let output = serializer.writeFountain(annotated)

    // Verify that the output contains the expected GLOSA note blocks.
    #expect(output.contains("[[ <SceneContext"))
    #expect(output.contains("[[ </SceneContext> ]]"))
    #expect(output.contains("[[ <Intent"))
    #expect(output.contains("[[ </Intent> ]]"))
    #expect(output.contains("[[ <Constraint"))

    // Verify specific attribute values are present.
    #expect(output.contains("location=\"steam room\""))
    #expect(output.contains("time=\"morning\""))
    #expect(output.contains("ambience=\"hissing steam, echoing tile\""))
    #expect(output.contains("from=\"conspiratorial calm\""))
    #expect(output.contains("to=\"grim resolve\""))
    #expect(output.contains("pace=\"slow\""))
    #expect(output.contains("character=\"BERNARD\""))
    #expect(output.contains("character=\"KILLIAN\""))
  }

  @Test("write() to .fountain file on disk")
  func writeToFountainFile() throws {
    let screenplay = try GuionParsedElementCollection(string: annotatedFountainText)
    let (notes, dialogueLines) = extractNotesAndDialogue(from: screenplay)

    let compiler = GlosaCompiler()
    let compilationResult = try compiler.compile(
      fountainNotes: notes,
      dialogueLines: dialogueLines
    )

    let parser = GlosaParser()
    let score = parser.parseFountain(notes: notes)

    let annotated = GlosaAnnotatedScreenplay.build(
      from: screenplay,
      compilationResult: compilationResult,
      score: score
    )

    let serializer = GlosaSerializer()
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("test_serialized.fountain")

    try serializer.write(annotated, to: tempURL)

    // Read it back.
    let contents = try String(contentsOf: tempURL, encoding: .utf8)
    #expect(contents.contains("[[ <SceneContext"))
    #expect(contents.contains("BERNARD"))
    #expect(contents.contains("KILLIAN"))

    // Clean up.
    try? FileManager.default.removeItem(at: tempURL)
  }

  @Test("write() throws for unsupported format")
  func writeThrowsForUnsupportedFormat() throws {
    let elements = [GuionElement(elementType: .action, elementText: "Test")]
    let screenplay = GuionParsedElementCollection(elements: elements)
    let annotated = GlosaAnnotatedScreenplay(
      screenplay: screenplay,
      annotatedElements: [],
      score: GlosaScore(),
      diagnostics: [],
      provenance: []
    )

    let serializer = GlosaSerializer()
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("test.txt")

    #expect(throws: GlosaSerializer.SerializerError.self) {
      try serializer.write(annotated, to: tempURL)
    }
  }

  @Test("Empty score produces Fountain output with no GLOSA notes")
  func emptyScoreProducesNoNotes() {
    let elements: [GuionElement] = [
      GuionElement(elementType: .sceneHeading, elementText: "INT. OFFICE - DAY"),
      GuionElement(elementType: .character, elementText: "JOHN"),
      GuionElement(elementType: .dialogue, elementText: "Hello."),
    ]
    let screenplay = GuionParsedElementCollection(elements: elements)
    let annotated = GlosaAnnotatedScreenplay(
      screenplay: screenplay,
      annotatedElements: elements.map { GlosaAnnotatedElement(element: $0) },
      score: GlosaScore(),
      diagnostics: [],
      provenance: []
    )

    let serializer = GlosaSerializer()
    let output = serializer.writeFountain(annotated)

    #expect(!output.contains("[[ <SceneContext"))
    #expect(!output.contains("[[ <Intent"))
    #expect(!output.contains("[[ <Constraint"))
    #expect(output.contains("INT. OFFICE - DAY"))
    #expect(output.contains("JOHN"))
    #expect(output.contains("Hello."))
  }

  // MARK: - Helpers

  /// Extract GLOSA note strings and dialogue lines from a parsed screenplay.
  private func extractNotesAndDialogue(
    from screenplay: GuionParsedElementCollection
  ) -> (notes: [String], dialogueLines: [(character: String, text: String)]) {
    var notes: [String] = []
    var dialogueLines: [(character: String, text: String)] = []
    var lastCharacterName = ""

    for element in screenplay.elements {
      switch element.elementType {
      case .comment:
        // Comment elements contain note text (without the [[ ]] wrappers).
        let trimmed = element.elementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          notes.append(trimmed)
        }
      case .character:
        lastCharacterName = element.elementText
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .replacingOccurrences(of: " ^", with: "")
      case .dialogue:
        dialogueLines.append((character: lastCharacterName, text: element.elementText))
        // Also add to notes for the parser to track dialogue within intents.
        notes.append(element.elementText)
      default:
        break
      }
    }

    return (notes, dialogueLines)
  }

  /// Remove all `[[ ... ]]` note blocks from a Fountain string.
  private func removeNoteBlocks(from text: String) -> String {
    // Remove [[ ... ]] blocks (including multi-line).
    var result = text
    let pattern = #"\[\[.*?\]\]"#
    if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) {
      let nsString = result as NSString
      result = regex.stringByReplacingMatches(
        in: result,
        options: [],
        range: NSRange(location: 0, length: nsString.length),
        withTemplate: ""
      )
    }
    // Clean up excess blank lines.
    while result.contains("\n\n\n") {
      result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }
    return result
  }
}
