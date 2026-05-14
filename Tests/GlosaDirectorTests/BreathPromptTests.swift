import Testing

@testable import GlosaDirector

/// Tests that the Stage Director system prompt contains the required breath
/// placement guidance, trigger conditions, placement rules, prohibitions, and
/// few-shot examples defined in spec §6.1–§6.4.
struct BreathPromptTests {

  // MARK: - Rendered prompt fixture

  /// The rendered system prompt under test. Built once per test run from the
  /// static sections — no glossary injected so the output is deterministic.
  private let prompt = Prompts.systemPrompt(glossary: nil)

  // MARK: - Trigger condition: 180-character threshold

  @Test func promptContains180CharacterThreshold() {
    #expect(prompt.contains("180"))
  }

  // MARK: - Placement rule: colon-list priority

  @Test func promptContainsColonListRule() {
    #expect(prompt.contains("Always insert here if the colon-list pattern exists"))
  }

  // MARK: - Prohibition: minimum gap between breaths

  @Test func promptContainsMinimumGapProhibition() {
    #expect(prompt.contains("Closer than 30 characters"))
  }

  // MARK: - Positive few-shot: Bishop input

  @Test func promptContainsBishopFewShotInput() {
    #expect(
      prompt.contains(
        "Bishop is freighted: authority, patriarchy, a history of cover-ups and anti-queer theology."
      ))
  }

  // MARK: - Positive few-shot: Bishop expected output

  @Test func promptContainsBishopFewShotOutput() {
    // The three offsets from spec §6.4 must all appear in the expected output block.
    #expect(prompt.contains("\"characterOffset\": 20"))
    #expect(prompt.contains("\"characterOffset\": 31"))
    #expect(prompt.contains("\"characterOffset\": 43"))
  }

  // MARK: - Negative few-shot: "I noticed." input

  @Test func promptContainsNegativeFewShotInput() {
    #expect(prompt.contains("I noticed."))
  }

  // MARK: - Negative few-shot: empty breaths output

  @Test func promptContainsNegativeFewShotOutput() {
    // The negative example must demonstrate that a short sentence yields [].
    #expect(prompt.contains("[]"))
  }

  // MARK: - Breath placement section is present in the assembled prompt

  @Test func promptContainsBreathPlacementHeading() {
    #expect(prompt.contains("Breath Placement"))
  }

  // MARK: - Prohibitions section is present

  @Test func promptContainsProhibitionsSection() {
    #expect(prompt.contains("Inside a noun phrase"))
    #expect(prompt.contains("Inside a quoted string"))
  }
}
