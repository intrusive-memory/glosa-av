import Foundation
import Testing

@testable import GlosaCore

/// Equivalence tests for `GlosaInlineNotes` — the single source of truth for
/// `[[ … ]]` inline-note stripping (Sortie 1 / FR1, AC1).
///
/// The central invariant: the prose `GlosaParser` stores for a dialogue
/// paragraph (its notes-stripped canonical buffer) is byte-identical to
/// `GlosaInlineNotes.split(raw).stripped` for the same input. The parser routes
/// its stripping through `GlosaInlineNotes.scan`, so these tests prove the two
/// public surfaces (the parser's stored dialogue and `split`/`strip`) agree
/// across plain prose, single breath, single pause, interleaved breath+pause,
/// and an emoji/combining-mark fixture.
///
/// Fixtures use paragraphs with no leading/trailing whitespace so the parser's
/// internal trim is a no-op, making `raw` the exact input both sides strip.
@Suite("GlosaInlineNotes parser equivalence")
struct GlosaInlineNotesTests {

  let parser = GlosaParser()

  // MARK: - Helpers

  /// Runs `raw` through `GlosaParser` as the sole dialogue line of one
  /// `<SceneContext>`/`<Intent>` and returns the stripped prose the parser
  /// stored (`IntentEntry.dialogueLines[0]`), or `nil` if no dialogue line was
  /// produced (e.g. an input that strips to empty).
  func parserStripped(_ raw: String) -> String? {
    let notes: [String] = [
      #"<SceneContext location="x" time="y">"#,
      #"<Intent from="a" to="b" pace="moderate">"#,
      raw,
      "</Intent>",
      "</SceneContext>",
    ]
    let score = parser.parseFountain(notes: notes)
    return score.scenes.first?.intents.first?.dialogueLines.first
  }

  /// Asserts the parser's stored stripped prose equals
  /// `GlosaInlineNotes.split(raw).stripped` for `raw`.
  func expectEquivalent(_ raw: String) {
    let viaSplit = GlosaInlineNotes.split(raw).stripped
    // `strip` and `split.stripped` are the same buffer.
    #expect(GlosaInlineNotes.strip(raw) == viaSplit)

    // The parser only stores non-empty lines; all AC1 fixtures carry prose, so
    // a nil here is itself a failure (the `== viaSplit` check below fails).
    let viaParser = parserStripped(raw)
    #expect(viaParser == viaSplit)
  }

  // MARK: - AC1 fixture: plain prose (no notes)

  @Test("Plain prose: parser-stripped == split.stripped")
  func plainProse() {
    expectEquivalent("The quiet word she never said aloud.")
  }

  // MARK: - AC1 fixture: single [[<breath/>]]

  @Test("Single breath note: parser-stripped == split.stripped")
  func singleBreath() {
    expectEquivalent("Bishop is freighted:[[<breath strength=\"strong\"/>]] authority and rigor.")
  }

  // MARK: - AC1 fixture: single [[<pause/>]]

  @Test("Single pause note: parser-stripped == split.stripped")
  func singlePause() {
    expectEquivalent("She waited[[<pause length=\"400ms\"/>]] then spoke at last.")
  }

  // MARK: - AC1 fixture: interleaved breath + pause

  @Test("Interleaved breath+pause: parser-stripped == split.stripped")
  func interleavedBreathPause() {
    expectEquivalent(
      "First clause,[[<breath/>]] second clause[[<pause/>]] and then the third clause,"
        + "[[<breath strength=\"weak\"/>]] closing it out."
    )
  }

  // MARK: - AC1 fixture: emoji / combining marks around notes

  @Test("Emoji + combining marks around notes: parser-stripped == split.stripped")
  func emojiAndCombiningMarks() {
    // Family ZWJ emoji (multi-scalar grapheme), a combining-acute café, and a
    // flag (regional-indicator pair) straddling breath and pause notes — the
    // scalar-count offset convention must survive these.
    expectEquivalent(
      "Café\u{0301} crowd 👩‍👩‍👧‍👦[[<breath/>]] cheered 🇫🇷[[<pause length=\"250ms\"/>]] for résumé\u{0301}s."
    )
  }

  // MARK: - split notes payload

  @Test("split() returns the inner tags of each removed note in order")
  func splitReturnsInnerTags() {
    let raw =
      "A[[<breath strength=\"weak\"/>]]B[[<pause length=\"400ms\"/>]]C"
    let result = GlosaInlineNotes.split(raw)
    #expect(result.stripped == "ABC")
    #expect(result.notes == ["<breath strength=\"weak\"/>", "<pause length=\"400ms\"/>"])
  }
}
