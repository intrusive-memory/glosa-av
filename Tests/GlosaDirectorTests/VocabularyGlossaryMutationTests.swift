import Foundation
import Testing

@testable import GlosaDirector

/// Tests for ``VocabularyGlossary`` mutation methods: add, remove, and save/reload.
@Suite("VocabularyGlossary Mutation Tests")
struct VocabularyGlossaryMutationTests {

  // MARK: - Helpers

  /// A minimal glossary for test setup.
  func makeGlossary() -> VocabularyGlossary {
    VocabularyGlossary(
      emotions: ["calm", "curious", "frustrated"],
      directions: ["thinking aloud, halting delivery", "quiet authority"],
      paceTerms: ["slow", "moderate", "fast"],
      registerTerms: ["low", "mid", "high"],
      ceilingTerms: ["subdued", "moderate", "intense", "explosive"]
    )
  }

  // MARK: - Add Tests

  @Test("add: new emotion term appears in glossary and increments count")
  func addNewEmotionTerm() throws {
    var glossary = makeGlossary()
    let countBefore = glossary.emotions.count
    glossary.add(term: "elated", category: .emotions)
    #expect(glossary.emotions.contains("elated"))
    #expect(glossary.emotions.count == countBefore + 1)
  }

  @Test("add: new direction term appears in glossary and increments count")
  func addNewDirectionTerm() throws {
    var glossary = makeGlossary()
    let countBefore = glossary.directions.count
    glossary.add(term: "voice cracking with emotion held in check", category: .directions)
    #expect(glossary.directions.contains("voice cracking with emotion held in check"))
    #expect(glossary.directions.count == countBefore + 1)
  }

  @Test("add: new paceTerm appears and increments count")
  func addNewPaceTerm() throws {
    var glossary = makeGlossary()
    let countBefore = glossary.paceTerms.count
    glossary.add(term: "accelerating", category: .paceTerms)
    #expect(glossary.paceTerms.contains("accelerating"))
    #expect(glossary.paceTerms.count == countBefore + 1)
  }

  @Test("add: new registerTerm appears and increments count")
  func addNewRegisterTerm() throws {
    var glossary = makeGlossary()
    let countBefore = glossary.registerTerms.count
    glossary.add(term: "ultra-high", category: .registerTerms)
    #expect(glossary.registerTerms.contains("ultra-high"))
    #expect(glossary.registerTerms.count == countBefore + 1)
  }

  @Test("add: new ceilingTerm appears and increments count")
  func addNewCeilingTerm() throws {
    var glossary = makeGlossary()
    let countBefore = glossary.ceilingTerms.count
    glossary.add(term: "volcanic", category: .ceilingTerms)
    #expect(glossary.ceilingTerms.contains("volcanic"))
    #expect(glossary.ceilingTerms.count == countBefore + 1)
  }

  // MARK: - Duplicate Tests

  @Test("add: adding an existing emotion term is a no-op (count unchanged)")
  func addDuplicateEmotionIsNoOp() throws {
    var glossary = makeGlossary()
    let countBefore = glossary.emotions.count
    // "calm" already exists in makeGlossary().
    glossary.add(term: "calm", category: .emotions)
    #expect(glossary.emotions.count == countBefore, "Duplicate add should not change count")
    #expect(
      glossary.emotions.filter { $0 == "calm" }.count == 1, "Should still have exactly one 'calm'")
  }

  @Test("add: adding an existing direction term is a no-op (count unchanged)")
  func addDuplicateDirectionIsNoOp() throws {
    var glossary = makeGlossary()
    let countBefore = glossary.directions.count
    glossary.add(term: "quiet authority", category: .directions)
    #expect(glossary.directions.count == countBefore, "Duplicate add should not change count")
  }

  // MARK: - Remove Tests

  @Test("remove: existing emotion term is removed and count decrements")
  func removeExistingEmotionTerm() throws {
    var glossary = makeGlossary()
    let countBefore = glossary.emotions.count
    glossary.remove(term: "calm")
    #expect(!glossary.emotions.contains("calm"))
    #expect(glossary.emotions.count == countBefore - 1)
  }

  @Test("remove: existing direction term is removed and count decrements")
  func removeExistingDirectionTerm() throws {
    var glossary = makeGlossary()
    let countBefore = glossary.directions.count
    glossary.remove(term: "quiet authority")
    #expect(!glossary.directions.contains("quiet authority"))
    #expect(glossary.directions.count == countBefore - 1)
  }

  @Test("remove: term not present is a no-op (count unchanged)")
  func removeNonExistentTermIsNoOp() throws {
    var glossary = makeGlossary()
    let emotionsBefore = glossary.emotions.count
    let directionsBefore = glossary.directions.count
    glossary.remove(term: "term-that-does-not-exist-xyz")
    #expect(glossary.emotions.count == emotionsBefore)
    #expect(glossary.directions.count == directionsBefore)
  }

  @Test("remove: term is searched across all categories")
  func removeCrossCategory() throws {
    // "moderate" appears in both paceTerms and ceilingTerms in many glossaries,
    // but in our test glossary it appears only in paceTerms.
    var glossary = makeGlossary()
    let paceBefore = glossary.paceTerms.count
    glossary.remove(term: "moderate")
    #expect(!glossary.paceTerms.contains("moderate"))
    #expect(glossary.paceTerms.count == paceBefore - 1)
  }

  // MARK: - Save / Reload Tests

  @Test("save: glossary persists to disk and reloads identically")
  func saveAndReload() throws {
    var glossary = makeGlossary()
    // Mutate before saving.
    glossary.add(term: "triumphant", category: .emotions)
    glossary.add(term: "whispered urgency", category: .directions)
    glossary.remove(term: "curious")

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("test-glossary-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    try glossary.save(to: tempURL)

    // Verify file was written.
    #expect(FileManager.default.fileExists(atPath: tempURL.path), "File should exist after save")

    // Reload and compare.
    let reloaded = try VocabularyGlossary.load(from: tempURL)
    #expect(reloaded == glossary, "Reloaded glossary should equal the saved one")
  }

  @Test("save: emotions and directions round-trip correctly")
  func saveRoundTripContents() throws {
    var glossary = makeGlossary()
    glossary.add(term: "bitter amusement", category: .emotions)
    glossary.add(term: "barely contained rage underneath calm surface", category: .directions)

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("test-glossary-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    try glossary.save(to: tempURL)
    let reloaded = try VocabularyGlossary.load(from: tempURL)

    #expect(reloaded.emotions.contains("bitter amusement"))
    #expect(reloaded.directions.contains("barely contained rage underneath calm surface"))
    #expect(reloaded.paceTerms == glossary.paceTerms)
    #expect(reloaded.registerTerms == glossary.registerTerms)
    #expect(reloaded.ceilingTerms == glossary.ceilingTerms)
  }

  // MARK: - Default Glossary Tests

  @Test("loadDefault: bundled glossary loads and has expected content")
  func loadDefaultGlossaryHasContent() throws {
    let glossary = try VocabularyGlossary.loadDefault()
    #expect(glossary.emotions.count > 0, "Default glossary should have emotion terms")
    #expect(glossary.directions.count > 0, "Default glossary should have direction phrases")
    #expect(glossary.paceTerms.count > 0, "Default glossary should have pace terms")
    #expect(glossary.registerTerms.count > 0, "Default glossary should have register terms")
    #expect(glossary.ceilingTerms.count > 0, "Default glossary should have ceiling terms")
  }

  @Test("loadDefault: default glossary contains known terms")
  func loadDefaultGlossaryContainsKnownTerms() throws {
    let glossary = try VocabularyGlossary.loadDefault()
    // Verify a selection of known terms from glossary.json.
    #expect(glossary.emotions.contains("calm"))
    #expect(glossary.emotions.contains("curious"))
    #expect(glossary.directions.contains("thinking aloud, halting delivery"))
    #expect(glossary.paceTerms.contains("slow"))
    #expect(glossary.paceTerms.contains("moderate"))
    #expect(glossary.registerTerms.contains("low"))
    #expect(glossary.ceilingTerms.contains("subdued"))
    #expect(glossary.ceilingTerms.contains("explosive"))
  }
}
