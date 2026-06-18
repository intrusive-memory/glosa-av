import Foundation

/// The single source of truth for stripping `[[ … ]]` inline GLOSA notes
/// (`[[<breath …/>]]` and `[[<pause …/>]]`) out of a dialogue paragraph,
/// leaving the canonical "prose the actor reads."
///
/// Every component that needs the notes-stripped form of a dialogue line — the
/// parser's canonical offset buffer, the CLI's pre-compile stripper, and any
/// downstream consumer — MUST route through this enum rather than re-deriving
/// the regex. Keeping one implementation guarantees that offsets recorded by
/// `GlosaParser` index into a buffer byte-identical to what a consumer obtains
/// from ``strip(_:)`` / ``split(_:)``.
///
/// ## Offset convention
///
/// Offsets that `GlosaParser` records against the stripped prose (e.g.
/// `Breath.characterOffset`, `Pause.characterOffset`) are
/// `String.unicodeScalars.count` indices into the `stripped` string this enum
/// produces — *not* `Character`/grapheme indices and *not* UTF-16/`NSString`
/// lengths. An offset of `n` denotes the boundary after the `n`-th Unicode
/// scalar of `stripped`. To recover the prose before such a marker, slice
/// `stripped.unicodeScalars.prefix(n)`. This matters for emoji and combining
/// marks, where one grapheme spans multiple scalars.
public enum GlosaInlineNotes {

  /// Regex matching a complete `[[<breath …/>]]` OR `[[<pause …/>]]` inline
  /// note in a single pass. Capture group 1 is the inner `<breath …/>` /
  /// `<pause …/>` substring (without the surrounding `[[ ]]`). This is the
  /// canonical pattern; `GlosaParser` consumes the same compiled regex via
  /// ``scan(_:)`` so the parser and ``split(_:)`` can never diverge.
  static let inlineNotePattern = #"\[\[\s*(<(?:breath|pause)\b[^>]*/>)\s*\]\]"#

  /// Compiled form of ``inlineNotePattern``. The pattern is a compile-time
  /// constant, so compilation cannot fail in practice; should it somehow fail,
  /// ``scan(_:)`` treats the input as note-free (no matches), which yields the
  /// input unchanged from ``strip(_:)`` / ``split(_:)``.
  static let inlineNoteRegex: NSRegularExpression? = try? NSRegularExpression(
    pattern: inlineNotePattern,
    options: []
  )

  /// One matched inline note plus the prose gap that preceded it.
  ///
  /// `GlosaParser` reuses these to record per-marker offsets and parse tag
  /// attributes without re-running the regex, ensuring its canonical buffer is
  /// identical to ``split(_:)``'s `stripped`.
  struct InlineNoteMatch {
    /// `NSString` range of the full `[[ … ]]` note in the original `dialogue`.
    let outerRange: NSRange
    /// The inner `<breath …/>` / `<pause …/>` substring (capture group 1).
    let innerTag: String
  }

  /// Result of a single combined left-to-right scan of `dialogue`.
  struct ScanResult {
    /// The canonical notes-stripped prose: `dialogue` with every well-formed
    /// breath *and* pause note removed. Byte-identical to ``strip(_:)``'s
    /// return value and ``split(_:)``'s `stripped`.
    let stripped: String
    /// The matched notes in document order.
    let matches: [InlineNoteMatch]
  }

  /// The single canonical scan. Walks the combined breath/pause pattern
  /// left-to-right, accumulating the prose gap before each match plus the
  /// trailing tail into `stripped`, and collecting each match's outer range
  /// and inner tag.
  ///
  /// Both ``strip(_:)``/``split(_:)`` and `GlosaParser.extractInlineNotes`
  /// build their stripped buffer from this one routine, so they cannot drift.
  static func scan(_ dialogue: String) -> ScanResult {
    let nsText = dialogue as NSString
    guard let regex = inlineNoteRegex else {
      // Unreachable in practice (literal compile-time pattern). Treat the
      // input as note-free, returning it unchanged.
      return ScanResult(stripped: dialogue, matches: [])
    }

    let regexMatches = regex.matches(
      in: dialogue,
      options: [],
      range: NSRange(location: 0, length: nsText.length)
    )

    var stripped = ""
    var matches: [InlineNoteMatch] = []
    var rawCursor = 0

    for match in regexMatches {
      let outerRange = match.range(at: 0)
      let innerRange = match.range(at: 1)

      // Append the prose gap before this match to the stripped buffer.
      let gapRange = NSRange(
        location: rawCursor,
        length: outerRange.location - rawCursor
      )
      stripped += nsText.substring(with: gapRange)

      matches.append(
        InlineNoteMatch(
          outerRange: outerRange,
          innerTag: nsText.substring(with: innerRange)
        ))

      rawCursor = outerRange.location + outerRange.length
    }

    // Append the trailing tail past the last match.
    if rawCursor < nsText.length {
      let tailRange = NSRange(location: rawCursor, length: nsText.length - rawCursor)
      stripped += nsText.substring(with: tailRange)
    }

    return ScanResult(stripped: stripped, matches: matches)
  }

  /// Returns `dialogue` with every well-formed `[[<breath …/>]]` and
  /// `[[<pause …/>]]` inline note removed, leaving the canonical prose the
  /// actor reads.
  ///
  /// This is the same buffer `GlosaParser` measures offsets against. See the
  /// type-level **Offset convention** discussion: those offsets are
  /// `unicodeScalars.count` indices into this string.
  ///
  /// - Parameter dialogue: A raw dialogue paragraph, possibly containing breath
  ///   and/or pause notes interleaved with prose.
  /// - Returns: The notes-stripped prose.
  public static func strip(_ dialogue: String) -> String {
    scan(dialogue).stripped
  }

  /// Returns the notes-stripped prose together with the inner tag text of each
  /// removed note, in document order.
  ///
  /// `stripped` is identical to ``strip(_:)``. `notes` contains the inner
  /// `<breath …/>` / `<pause …/>` substring of each removed note (the text
  /// between `[[` and `]]`, trimmed of the surrounding brackets and whitespace
  /// the pattern absorbs), in the order they appeared.
  ///
  /// Offsets that `GlosaParser` records (e.g. `Breath.characterOffset`) are
  /// `unicodeScalars.count` indices into `stripped`; see the type-level
  /// **Offset convention** discussion.
  ///
  /// - Parameter dialogue: A raw dialogue paragraph, possibly containing breath
  ///   and/or pause notes interleaved with prose.
  /// - Returns: A tuple of the stripped prose and the inner tags of each note.
  public static func split(_ dialogue: String) -> (stripped: String, notes: [String]) {
    let result = scan(dialogue)
    return (result.stripped, result.matches.map(\.innerTag))
  }
}
