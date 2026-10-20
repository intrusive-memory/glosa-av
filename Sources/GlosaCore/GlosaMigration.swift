import Foundation

/// Migrates notation 1.0 block directives to notation 2.0.
public enum GlosaMigration {

  /// A notation 1.0 `<shot …/>` or `<include …/>` tag. Quoted attribute values
  /// may contain `>`.
  private static let tagPattern = #"<(?:shot|include)\b(?:"[^"]*"|'[^']*'|[^>"'])*/>"#
  private static let anyDirectivePattern = #"<(?:shot|include)\b"#

  /// Rewrites each standalone 1.0 `<shot …/>` / `<include …/>` note to its
  /// notation 2.0 serialization (`Shot.serialize()` / `Include.serialize()`).
  ///
  /// Only a standalone note (see ``GlosaFountainNotes/standaloneNotes(in:)``)
  /// whose entire content is exactly one such tag is migrated. A 1.0 block
  /// directive anywhere else (inside an action or dialogue line, or in a
  /// standalone note that mixes it with other content) is left alone and
  /// counted in `skipped`. Every byte outside the replaced ranges is
  /// identical; performance directives and 2.0 notes are untouched, so the
  /// function is idempotent. Replacement notes use the line ending of the
  /// note's first line (`\r\n` or `\n`).
  ///
  /// - Returns: the new text, the number of notes rewritten, and the number of
  ///   1.0 block directives left in place.
  public static func migrateBlockDirectives(
    in fountainText: String
  ) -> (text: String, migrated: Int, skipped: Int) {
    let parser = GlosaParser()
    var output = ""
    var cursor = fountainText.startIndex
    var migrated = 0
    var skipped = 0

    func countSkipped(in slice: Substring) {
      skipped += slice.ranges(ofPattern: anyDirectivePattern)
    }

    for note in GlosaFountainNotes.standaloneNotes(in: fountainText) {
      let replacement = replacement(for: note.text, parser: parser)
      // 2.0 JSON notes are opaque: never rewritten, never counted (a prompt
      // may legitimately mention `<shot`).
      guard replacement != nil || note.text.hasPrefix("{") else { continue }
      countSkipped(in: fountainText[cursor..<note.range.lowerBound])
      output += fountainText[cursor..<note.range.lowerBound]
      if let replacement {
        let crlf =
          fountainText[note.range].contains("\r\n") || lineEndsCRLF(note.range, fountainText)
        output += crlf ? replacement.replacingOccurrences(of: "\n", with: "\r\n") : replacement
        migrated += 1
      } else {
        output += fountainText[note.range]
      }
      cursor = note.range.upperBound
    }
    countSkipped(in: fountainText[cursor...])
    output += fountainText[cursor...]
    return (output, migrated, skipped)
  }

  /// The 2.0 note for `text` when it is exactly one 1.0 tag, else `nil`.
  private static func replacement(for text: String, parser: GlosaParser) -> String? {
    guard text.range(of: "^" + tagPattern + "$", options: .regularExpression) != nil else {
      return nil
    }
    let score = parser.parseFountain(notes: [text])
    if let shot = score.shots.first { return shot.serialize() }
    if let include = score.includes.first { return include.serialize() }
    return nil
  }

  /// Whether the line holding the note's opening `[[` ends with `\r\n`.
  private static func lineEndsCRLF(_ range: Range<String.Index>, _ text: String) -> Bool {
    var index = range.upperBound
    while index < text.endIndex {
      if text[index].isNewline { return text[index] == "\r\n" }
      index = text.index(after: index)
    }
    return false
  }
}

extension Substring {
  /// The number of non-overlapping regular-expression matches.
  fileprivate func ranges(ofPattern pattern: String) -> Int {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
    let string = String(self)
    return regex.numberOfMatches(
      in: string, range: NSRange(string.startIndex..<string.endIndex, in: string))
  }
}
