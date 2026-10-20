import Foundation

/// Locates standalone `[[ … ]]` notes in a Fountain document.
///
/// GlosaCore otherwise receives note texts from its callers; this finds them in
/// raw document text, for ``GlosaMigration`` and for tests. It does not replace
/// a caller's own extraction.
public enum GlosaFountainNotes {

  /// The standalone notes of `fountainText`, in document order.
  ///
  /// A note is standalone when it forms its own block (notation 2.0 D-6):
  /// - the opening `[[` is the first non-whitespace on its line;
  /// - the closing `]]` is the last non-whitespace on its line;
  /// - it may span lines but contains no blank line (a whitespace-only line);
  /// - a blank line, or the start / end of the document, precedes and follows it;
  /// - the inner content contains no `]]` (so `[[ a ]] and [[ b ]]` is not one note).
  ///
  /// A note inside an action or dialogue line is not returned. Line endings
  /// `\n`, `\r\n` and `\r` all count.
  ///
  /// - Returns: for each note, `range` covering `[[` through `]]`, and `text`,
  ///   the content between the brackets with surrounding whitespace trimmed.
  public static func standaloneNotes(
    in fountainText: String
  ) -> [(range: Range<String.Index>, text: String)] {
    var notes: [(range: Range<String.Index>, text: String)] = []

    // A block is a run of consecutive non-blank lines.
    var blockStart: String.Index?
    var blockEnd: String.Index?  // end of the last non-blank line's content
    var index = fountainText.startIndex

    func flush() {
      if let start = blockStart, let end = blockEnd,
        let note = note(in: start..<end, of: fountainText)
      {
        notes.append(note)
      }
      blockStart = nil
      blockEnd = nil
    }

    while index < fountainText.endIndex {
      var contentEnd = index
      while contentEnd < fountainText.endIndex, !fountainText[contentEnd].isNewline {
        contentEnd = fountainText.index(after: contentEnd)
      }
      let next =
        contentEnd < fountainText.endIndex
        ? fountainText.index(after: contentEnd) : contentEnd
      let line = fountainText[index..<contentEnd]
      if line.allSatisfy({ $0.isWhitespace }) {
        flush()
      } else {
        if blockStart == nil { blockStart = index }
        blockEnd = contentEnd
      }
      index = next
    }
    flush()
    return notes
  }

  /// The note a block forms, or `nil` when the block is not exactly one `[[ … ]]`.
  private static func note(
    in block: Range<String.Index>, of text: String
  ) -> (range: Range<String.Index>, text: String)? {
    var start = block.lowerBound
    var end = block.upperBound
    while start < end, text[start].isWhitespace { start = text.index(after: start) }
    while start < end {
      let before = text.index(before: end)
      if text[before].isWhitespace { end = before } else { break }
    }
    let note = text[start..<end]
    guard note.hasPrefix("[["), note.hasSuffix("]]"), note.count >= 4 else { return nil }
    let inner = text[text.index(start, offsetBy: 2)..<text.index(end, offsetBy: -2)]
    guard !inner.contains("]]") else { return nil }
    let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
    return (start..<end, trimmed)
  }
}
