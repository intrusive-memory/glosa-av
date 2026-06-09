import Testing

@testable import GlosaDirector

/// Tests that the Stage Director system prompt carries a distinct pause section
/// and that the breath section is now length-free (OPERATION CLEAVING BREATH,
/// Sortie 9, mirroring the post-S5 prompt reality).
///
/// These complement `BreathPromptTests` (already updated by S8-continuation) and
/// use distinct test names to avoid collisions.
@Suite("Pause Prompt Tests")
struct PausePromptTests {

  private let prompt = Prompts.systemPrompt(glossary: nil)

  // MARK: - Pause section is present and assembled into the prompt

  @Test("Assembled prompt contains the Pause Placement section heading")
  func promptContainsPausePlacementHeading() {
    #expect(prompt.contains("Pause Placement"))
    #expect(prompt.contains(Prompts.pausePlacementSection))
  }

  @Test("Pause section describes the audible-silence semantics")
  func pauseSectionDescribesAudibleSilence() {
    let section = Prompts.pausePlacementSection
    #expect(section.contains("AUDIBLE"))
    #expect(section.contains("always forces a chunk seam"))
  }

  // MARK: - Pause section owns the colon-before-list trigger

  @Test("Pause section owns the colon-before-list trigger")
  func pauseSectionOwnsColonBeforeList() {
    let section = Prompts.pausePlacementSection
    #expect(section.contains("Colon before a list or enumeration"))
  }

  // MARK: - Pause section documents length choices

  @Test("Pause section documents the length presets (comma..beat) and explicit values")
  func pauseSectionDocumentsLengths() {
    let section = Prompts.pausePlacementSection
    #expect(section.contains("Which `length` to choose"))
    #expect(section.contains("comma"))
    #expect(section.contains("semicolon"))
    #expect(section.contains("period"))
    #expect(section.contains("em-dash"))
    #expect(section.contains("beat"))
  }

  // MARK: - Bishop pause few-shot: colon → period pause at offset 20

  @Test("Pause section's Bishop few-shot maps the colon to a period pause at offset 20")
  func pauseSectionBishopFewShot() {
    let section = Prompts.pausePlacementSection
    #expect(
      section.contains(
        "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."
      ))
    #expect(section.contains("\"characterOffset\": 20"))
    #expect(section.contains("\"length\": \"period\""))
  }

  @Test("Pause section has a negative few-shot that yields an empty pauses array")
  func pauseSectionNegativeFewShot() {
    let section = Prompts.pausePlacementSection
    #expect(section.contains("I noticed."))
    #expect(section.contains("[]"))
  }

  // MARK: - Breath section is now length-free

  @Test("Breath section contains no length attribute guidance")
  func breathSectionIsLengthFree() {
    let section = Prompts.breathPlacementSection
    // The breath section must not instruct the LLM to set a `length` on a breath.
    #expect(!section.contains("\"length\":"))
    #expect(!section.contains("length=\""))
    // It explicitly states breaths carry no length.
    #expect(section.contains("Breaths carry no `length`"))
  }

  @Test("Breath section defers the colon-before-list deliberate stop to a pause")
  func breathSectionDefersColonToPause() {
    let section = Prompts.breathPlacementSection
    #expect(section.contains("`<pause>`"))
  }
}
