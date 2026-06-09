import Foundation

/// Parses GLOSA annotations from Fountain note strings or FDX XML content
/// and produces a structured `GlosaScore`.
///
/// Two extraction modes are supported:
/// - **Fountain**: Regex-based parsing of GLOSA tags from `[[ ]]` note strings.
/// - **FDX**: `XMLParser`-based extraction of `glosa:` namespace elements from XML.
public struct GlosaParser: Sendable {

  public init() {}

  // MARK: - Fountain Extraction

  /// Parse GLOSA tags from an array of Fountain note contents (the text inside `[[ ]]` blocks).
  ///
  /// The notes must be in document order. Dialogue lines enclosed by scoped Intents
  /// should appear as separate note entries containing just the dialogue text, or
  /// they can be inferred from the structure. In practice, the parser expects
  /// interleaved note strings that contain GLOSA tags and dialogue content.
  ///
  /// - Parameter notes: Array of strings, each being the content of a `[[ ]]` note block,
  ///   or a dialogue line in document order.
  /// - Returns: A `GlosaScore` representing the parsed annotations.
  public func parseFountain(notes: [String]) -> GlosaScore {
    return parseFountainWithDiagnostics(notes: notes).score
  }

  /// Parse GLOSA tags from Fountain note strings, returning both the parsed
  /// score and any diagnostics emitted during parsing.
  ///
  /// Diagnostics are produced for malformed `<breath/>` inline notes
  /// (unknown `length` value, unknown `strength` value, malformed explicit
  /// time string), for `after=` substrings that fail to locate within the
  /// enclosing dialogue paragraph, and for `<breath/>` notes that appear
  /// outside any dialogue paragraph.
  ///
  /// The structural parsing — `<SceneContext>`, `<Intent>`, `<Constraint>`,
  /// and the dialogue accumulation rules — is identical to ``parseFountain(notes:)``.
  ///
  /// - Parameter notes: Array of strings, each being the content of a `[[ ]]`
  ///   note block, or a dialogue line in document order. Dialogue lines may
  ///   contain inline `[[<breath/>]]` notes; the breaths are extracted and
  ///   the `[[ ]]` markers stripped from the stored dialogue text.
  /// - Returns: A tuple containing the parsed `GlosaScore` (including its
  ///   `breaths` collection) and any breath-parsing diagnostics.
  public func parseFountainWithDiagnostics(
    notes: [String]
  ) -> (score: GlosaScore, diagnostics: [GlosaDiagnostic]) {
    var scenes: [GlosaScore.SceneEntry] = []
    var currentScene: SceneContext?
    var currentIntents: [GlosaScore.IntentEntry] = []
    var pendingConstraints: [Constraint] = []
    var currentIntentAttrs: Intent?
    var currentIntentConstraints: [Constraint] = []
    var currentIntentDialogue: [String] = []
    // Track constraints that were declared before any intent in a scene
    var sceneConstraints: [Constraint] = []

    // Breath-parsing state.
    var breaths: [Breath] = []
    // Pause-parsing state.
    var pauses: [Pause] = []
    var diagnostics: [GlosaDiagnostic] = []
    // Scene-local count of dialogue paragraphs already committed in the
    // current scene (across intents). Resets when the scene closes.
    var sceneDialogueLineCount: Int = 0
    // Zero-based index of the currently open scene in document order, or
    // `-1` when no `<SceneContext>` is open. Set to `scenes.count` at the
    // moment a SceneContext opens (after any prior scene has been
    // appended) so the index reflects where this scene will land in
    // `scenes`.
    var currentSceneIndex: Int = -1

    for (noteIndex, note) in notes.enumerated() {
      let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
      let lineNumber = noteIndex + 1

      // Check for closing tags first
      if trimmed.contains("</SceneContext>") {
        // Close any open intent as a MARKER (not scoped) since it was
        // not explicitly closed with </Intent>
        if let intentAttrs = currentIntentAttrs {
          let entry = makeIntentEntry(
            attrs: intentAttrs,
            constraints: currentIntentConstraints,
            dialogue: currentIntentDialogue,
            scoped: false
          )
          currentIntents.append(entry)
          currentIntentAttrs = nil
          currentIntentConstraints = []
          currentIntentDialogue = []
        }

        // Close scene
        if let scene = currentScene {
          scenes.append(
            GlosaScore.SceneEntry(
              context: scene,
              intents: currentIntents
            ))
        }
        currentScene = nil
        currentIntents = []
        pendingConstraints = []
        sceneConstraints = []
        sceneDialogueLineCount = 0
        currentSceneIndex = -1
        continue
      }

      if trimmed.contains("</Intent>") {
        // Close current scoped intent (explicit close = scoped)
        if let intentAttrs = currentIntentAttrs {
          let entry = makeIntentEntry(
            attrs: intentAttrs,
            constraints: currentIntentConstraints,
            dialogue: currentIntentDialogue,
            scoped: true
          )
          currentIntents.append(entry)
          currentIntentAttrs = nil
          currentIntentConstraints = []
          currentIntentDialogue = []
        }
        continue
      }

      // Check for opening SceneContext
      if let sceneContext = parseSceneContextTag(trimmed) {
        // Close any previous scene
        if let prevScene = currentScene {
          // Any open intent without explicit </Intent> is a marker
          if let intentAttrs = currentIntentAttrs {
            let entry = makeIntentEntry(
              attrs: intentAttrs,
              constraints: currentIntentConstraints,
              dialogue: currentIntentDialogue,
              scoped: false
            )
            currentIntents.append(entry)
            currentIntentAttrs = nil
            currentIntentConstraints = []
            currentIntentDialogue = []
          }
          scenes.append(
            GlosaScore.SceneEntry(
              context: prevScene,
              intents: currentIntents
            ))
          currentIntents = []
        }
        currentScene = sceneContext
        pendingConstraints = []
        sceneConstraints = []
        sceneDialogueLineCount = 0
        // `scenes` already contains every previously-closed scene at this
        // point, so its current length is the index this new scene will
        // occupy once it is appended.
        currentSceneIndex = scenes.count
        continue
      }

      // Check for Constraint
      if let constraint = parseConstraintTag(trimmed) {
        if currentIntentAttrs != nil {
          // Inside an intent scope
          currentIntentConstraints.append(constraint)
        } else {
          // Outside intent - these are scene-level constraints
          pendingConstraints.append(constraint)
          sceneConstraints.append(constraint)
        }
        continue
      }

      // Check for opening Intent
      if let intent = parseIntentTag(trimmed) {
        // Close any previous open intent as marker (superseded without explicit close)
        if let prevAttrs = currentIntentAttrs {
          let entry = makeIntentEntry(
            attrs: prevAttrs,
            constraints: currentIntentConstraints,
            dialogue: currentIntentDialogue,
            scoped: false
          )
          currentIntents.append(entry)
          currentIntentConstraints = []
          currentIntentDialogue = []
        }

        currentIntentAttrs = intent
        // Carry forward scene-level constraints into this intent
        currentIntentConstraints = pendingConstraints
        pendingConstraints = []
        continue
      }

      // If we reach here, this is a dialogue line (or non-tag content).
      // Inside an intent, scan for inline `[[<breath/>]]` notes, strip them
      // from the stored text, and emit `Breath` values whose offsets are
      // measured against the notes-stripped prose.
      if currentIntentAttrs != nil && !trimmed.isEmpty {
        // Strip breaths first, then pauses, off the same prose. Each pass
        // measures offsets against the text it receives; breaths are
        // stripped first so pause offsets are measured against the
        // breath-stripped prose (the canonical "prose the actor reads"
        // contains neither breath nor pause notes).
        let breathExtraction = extractBreaths(
          from: trimmed,
          sceneIndex: currentSceneIndex,
          dialogueLineIndex: sceneDialogueLineCount,
          line: lineNumber
        )
        let pauseExtraction = extractPauses(
          from: breathExtraction.strippedText,
          sceneIndex: currentSceneIndex,
          dialogueLineIndex: sceneDialogueLineCount,
          line: lineNumber
        )
        currentIntentDialogue.append(pauseExtraction.strippedText)
        breaths.append(contentsOf: breathExtraction.breaths)
        pauses.append(contentsOf: pauseExtraction.pauses)
        diagnostics.append(contentsOf: breathExtraction.diagnostics)
        diagnostics.append(contentsOf: pauseExtraction.diagnostics)
        sceneDialogueLineCount += 1
      } else if !trimmed.isEmpty && containsInlineBreathNote(trimmed) {
        // A `[[<breath/>]]` note appearing outside any dialogue paragraph
        // (e.g., between structural tags, or before any <Intent> has
        // opened). Per spec §4.3 the marker is ignored; emit one warning.
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message: "Breath note found outside any dialogue paragraph; ignoring",
            line: lineNumber
          ))
      } else if !trimmed.isEmpty && containsInlinePauseNote(trimmed) {
        // A `[[<pause/>]]` note appearing outside any dialogue paragraph.
        // The marker is ignored; emit one warning, mirroring breath.
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message: "Pause note found outside any dialogue paragraph; ignoring",
            line: lineNumber
          ))
      }
    }

    // Handle unclosed structures at end
    if let intentAttrs = currentIntentAttrs {
      let entry = makeIntentEntry(
        attrs: intentAttrs,
        constraints: currentIntentConstraints,
        dialogue: currentIntentDialogue,
        scoped: false  // No closing tag found = marker
      )
      currentIntents.append(entry)
    }

    if let scene = currentScene {
      scenes.append(
        GlosaScore.SceneEntry(
          context: scene,
          intents: currentIntents
        ))
    }

    return (GlosaScore(scenes: scenes, breaths: breaths, pauses: pauses), diagnostics)
  }

  /// Parse GLOSA tags from Fountain note strings where dialogue lines are provided
  /// separately as an interleaved stream.
  ///
  /// This is a convenience wrapper around `parseFountain(notes:)`. The `notes`
  /// array should contain both GLOSA tag strings and dialogue line strings,
  /// interleaved in document order. The `dialogueLines` parameter is available
  /// for callers that need character-name resolution but is not used for parsing
  /// structure.
  ///
  /// - Parameters:
  ///   - notes: Interleaved array of GLOSA tag strings and dialogue text in document order.
  ///   - dialogueLines: Dialogue lines with character names (reserved for future use).
  /// - Returns: A `GlosaScore` representing the parsed annotations.
  public func parseFountainWithDialogue(
    notes: [String],
    dialogueLines: [(character: String, text: String)]
  ) -> GlosaScore {
    return parseFountain(notes: notes)
  }

  // MARK: - FDX Extraction

  /// Parse GLOSA annotations from FDX (Final Draft XML) content.
  ///
  /// Uses `XMLParser` to extract `glosa:` namespace elements from the FDX document.
  ///
  /// - Parameter data: The XML content of the FDX file.
  /// - Returns: A `GlosaScore` representing the parsed annotations.
  public func parseFDX(data: Data) -> GlosaScore {
    return parseFDXWithDiagnostics(data: data).score
  }

  /// Parse GLOSA annotations from FDX content, returning both the parsed
  /// score and any diagnostics emitted during parsing.
  ///
  /// Diagnostics are produced for malformed `<glosa:breath/>` elements
  /// (unknown `length` value, unknown `strength` value, malformed explicit
  /// time string) and for `<glosa:breath/>` elements that appear outside
  /// any `<Paragraph Type="Dialogue">`. The structural parsing of
  /// `<glosa:SceneContext>`, `<glosa:Intent>`, and `<glosa:Constraint>` is
  /// identical to ``parseFDX(data:)``.
  ///
  /// - Parameter data: The XML content of the FDX file.
  /// - Returns: A tuple containing the parsed `GlosaScore` (including its
  ///   `breaths` collection) and any breath-parsing diagnostics.
  public func parseFDXWithDiagnostics(
    data: Data
  ) -> (score: GlosaScore, diagnostics: [GlosaDiagnostic]) {
    let delegate = FDXParserDelegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = true
    parser.shouldReportNamespacePrefixes = true
    parser.parse()
    return (delegate.buildScore(), delegate.diagnostics)
  }

  // MARK: - Private Helpers

  /// Parse a `<SceneContext ...>` tag and extract its attributes.
  private func parseSceneContextTag(_ text: String) -> SceneContext? {
    // Match <SceneContext with attributes
    guard text.contains("<SceneContext") && !text.contains("</SceneContext") else {
      return nil
    }

    let location = extractAttribute("location", from: text) ?? ""
    let time = extractAttribute("time", from: text) ?? ""
    let ambience = extractAttribute("ambience", from: text)

    guard !location.isEmpty, !time.isEmpty else { return nil }

    return SceneContext(location: location, time: time, ambience: ambience)
  }

  /// Parse a `<Constraint ...>` tag and extract its attributes.
  private func parseConstraintTag(_ text: String) -> Constraint? {
    guard text.contains("<Constraint") && !text.contains("</Constraint") else {
      return nil
    }

    let character = extractAttribute("character", from: text) ?? ""
    let direction = extractAttribute("direction", from: text) ?? ""

    guard !character.isEmpty, !direction.isEmpty else { return nil }

    let register = extractAttribute("register", from: text)
    let ceiling = extractAttribute("ceiling", from: text)

    return Constraint(
      character: character,
      direction: direction,
      register: register,
      ceiling: ceiling
    )
  }

  /// Parse an `<Intent ...>` tag and extract its attributes.
  private func parseIntentTag(_ text: String) -> Intent? {
    guard text.contains("<Intent") && !text.contains("</Intent") else {
      return nil
    }

    let from = extractAttribute("from", from: text) ?? ""
    let to = extractAttribute("to", from: text) ?? ""

    guard !from.isEmpty, !to.isEmpty else { return nil }

    let pace = extractAttribute("pace", from: text)
    let spacing = extractAttribute("spacing", from: text)

    return Intent(from: from, to: to, pace: pace, spacing: spacing)
  }

  /// Extract an XML/SGML attribute value from a tag string.
  ///
  /// Handles both `attr="value"` and `attr='value'` forms.
  private func extractAttribute(_ name: String, from text: String) -> String? {
    // Try double quotes first
    let doubleQuotePattern = name + #"="([^"]*)""#
    if let match = text.range(of: doubleQuotePattern, options: .regularExpression) {
      let fullMatch = String(text[match])
      // Extract the value between quotes
      if let openQuote = fullMatch.firstIndex(of: "\""),
        let closeQuote = fullMatch[fullMatch.index(after: openQuote)...].firstIndex(of: "\"")
      {
        return String(fullMatch[fullMatch.index(after: openQuote)..<closeQuote])
      }
    }

    // Try single quotes
    let singleQuotePattern = name + #"='([^']*)'"#
    if let match = text.range(of: singleQuotePattern, options: .regularExpression) {
      let fullMatch = String(text[match])
      if let openQuote = fullMatch.firstIndex(of: "'"),
        let closeQuote = fullMatch[fullMatch.index(after: openQuote)...].firstIndex(of: "'")
      {
        return String(fullMatch[fullMatch.index(after: openQuote)..<closeQuote])
      }
    }

    return nil
  }

  // MARK: - Breath Extraction (Fountain inline notes)

  /// Result of scanning a dialogue paragraph for inline `[[<breath/>]]` notes.
  ///
  /// - `strippedText`: the paragraph with every well-formed breath note
  ///   removed. Used as the canonical "prose the actor reads" — breath
  ///   offsets in `breaths` are measured against this string.
  /// - `breaths`: the breath markers discovered, in document order, each
  ///   carrying its `characterOffset` in the stripped prose.
  /// - `diagnostics`: warnings for malformed attribute values, unresolved
  ///   `after=` substrings, or other recoverable errors. The offending
  ///   breath is skipped but its `[[ ]]` markers are still stripped so the
  ///   remaining prose is contiguous.
  private struct BreathExtraction {
    var strippedText: String
    var breaths: [Breath]
    var diagnostics: [GlosaDiagnostic]
  }

  /// Regex that matches a complete `[[<breath …/>]]` inline note. The
  /// captured group is the inner `<breath …/>` substring (without the
  /// surrounding `[[ ]]`).
  ///
  /// Pattern: matches the literal `[[` opener, optional whitespace, a
  /// self-closing `<breath …/>` tag (the `\b` after `breath` rejects names
  /// like `breathy`), optional whitespace, and the `]]` closer. The
  /// `[^>]*` body permits any attributes — `length=…`, `strength=…`,
  /// `after=…` — and is validated afterwards by the attribute parsers.
  private static let inlineBreathPattern = #"\[\[\s*(<breath\b[^>]*/>)\s*\]\]"#

  /// Quick test: does this string contain any `[[<breath/>]]` inline note?
  /// Used to flag breath markers that escape into non-dialogue text.
  private func containsInlineBreathNote(_ text: String) -> Bool {
    return text.range(of: Self.inlineBreathPattern, options: .regularExpression) != nil
  }

  /// Regex that matches a complete `[[<pause …/>]]` inline note. Mirrors
  /// ``inlineBreathPattern``: the captured group is the inner `<pause …/>`
  /// substring (without the surrounding `[[ ]]`). The `\b` after `pause`
  /// rejects names like `pauses`; `[^>]*` permits any attributes (`length=…`).
  private static let inlinePausePattern = #"\[\[\s*(<pause\b[^>]*/>)\s*\]\]"#

  /// Quick test: does this string contain any `[[<pause/>]]` inline note?
  /// Used to flag pause markers that escape into non-dialogue text.
  private func containsInlinePauseNote(_ text: String) -> Bool {
    return text.range(of: Self.inlinePausePattern, options: .regularExpression) != nil
  }

  /// Scan a dialogue paragraph for inline `[[<breath/>]]` notes, returning
  /// the notes-stripped text together with the extracted `Breath` values
  /// and any diagnostics emitted along the way.
  ///
  /// Offsets are computed against the *stripped* prose — the bytes the
  /// actor would read if the inline notes were not present — which matches
  /// the contract downstream sorties (S4/S5/S6) rely on.
  ///
  /// - Parameters:
  ///   - text: The raw dialogue paragraph text, possibly containing one or
  ///     more `[[<breath/>]]` notes.
  ///   - sceneIndex: The zero-based index of the enclosing `<SceneContext>`
  ///     in document order, or `-1` if no scene is currently open.
  ///   - dialogueLineIndex: The scene-local index of this dialogue paragraph
  ///     (zero-based, counts across intents within the current scene).
  ///   - line: The 1-based note-array index this paragraph came from. Used
  ///     for diagnostic `line` numbers; not a screenplay line number.
  /// - Returns: A `BreathExtraction` describing the cleaned text, the
  ///   discovered breaths, and any diagnostics.
  private func extractBreaths(
    from text: String,
    sceneIndex: Int,
    dialogueLineIndex: Int,
    line: Int
  ) -> BreathExtraction {
    // Phase 1: find every inline `[[<breath/>]]` match in the raw text.
    // We iterate over NSRegularExpression matches so we can capture both
    // the outer `[[ ... ]]` range (to strip) and the inner `<breath .../>`
    // range (to parse attributes).
    let nsText = text as NSString
    guard
      let regex = try? NSRegularExpression(
        pattern: Self.inlineBreathPattern,
        options: []
      )
    else {
      // The pattern is a literal compile-time constant; this branch should
      // be unreachable in practice. Return text unchanged if it fails.
      return BreathExtraction(strippedText: text, breaths: [], diagnostics: [])
    }

    let matches = regex.matches(
      in: text,
      options: [],
      range: NSRange(location: 0, length: nsText.length)
    )

    // Phase 2: walk the matches left-to-right, building the stripped text
    // and recording each breath's offset in the stripped prose. We append
    // the gap before each match to the stripped buffer, then "skip" the
    // match — the next gap starts after the match's end in the raw text.
    var stripped = ""
    var breaths: [Breath] = []
    var diagnostics: [GlosaDiagnostic] = []

    // `pendingAfterBreaths` holds breaths whose `after="…"` substring must
    // be resolved against the *fully* stripped prose. We can't compute
    // their offsets until phase 1 has finished, because the substring may
    // reference text that follows a later inline-note removal.
    struct PendingAfterBreath {
      let substring: String
      let strength: BreathStrength
      let line: Int
    }
    var pendingAfterBreaths: [PendingAfterBreath] = []

    var rawCursor = 0
    for match in matches {
      let outerRange = match.range(at: 0)
      let innerRange = match.range(at: 1)
      // Append the slice from the last cursor up to this match.
      let gapRange = NSRange(
        location: rawCursor,
        length: outerRange.location - rawCursor
      )
      stripped += nsText.substring(with: gapRange)

      // The offset of this breath in the stripped prose is the current
      // length of the stripped buffer (Unicode-scalar count). Using
      // `unicodeScalars.count` here matches the convention the spec uses
      // for `characterOffset` (a count of Unicode scalars before the
      // breakpoint).
      let offset = stripped.unicodeScalars.count

      // Parse the inner `<breath …/>` content.
      let innerTag = nsText.substring(with: innerRange)
      let parse = parseBreathTag(innerTag, line: line)
      diagnostics.append(contentsOf: parse.diagnostics)

      switch parse.outcome {
      case .skip:
        break
      case .inline(let strength):
        breaths.append(
          Breath(
            sceneIndex: sceneIndex,
            dialogueLineIndex: dialogueLineIndex,
            characterOffset: offset,
            strength: strength
          )
        )
      case .after(let substring, let strength):
        pendingAfterBreaths.append(
          PendingAfterBreath(
            substring: substring,
            strength: strength,
            line: line
          )
        )
      }

      rawCursor = outerRange.location + outerRange.length
    }

    // Append the trailing tail of the raw text past the last match.
    if rawCursor < nsText.length {
      let tailRange = NSRange(location: rawCursor, length: nsText.length - rawCursor)
      stripped += nsText.substring(with: tailRange)
    }

    // Phase 3: resolve any `after="…"` breaths against the stripped prose.
    let strippedNS = stripped as NSString
    for pending in pendingAfterBreaths {
      let found = strippedNS.range(of: pending.substring)
      if found.location == NSNotFound {
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message:
              "Breath after=\"\(pending.substring)\" did not match any substring in the dialogue paragraph; ignoring",
            line: pending.line
          ))
        continue
      }
      // Convert NSString location+length (UTF-16 units) to a Unicode-scalar
      // offset by slicing the prefix and asking for its scalar count.
      let endLocation = found.location + found.length
      let prefix = strippedNS.substring(with: NSRange(location: 0, length: endLocation))
      let scalarOffset = prefix.unicodeScalars.count
      breaths.append(
        Breath(
          sceneIndex: sceneIndex,
          dialogueLineIndex: dialogueLineIndex,
          characterOffset: scalarOffset,
          strength: pending.strength
        )
      )
    }

    return BreathExtraction(
      strippedText: stripped,
      breaths: breaths,
      diagnostics: diagnostics
    )
  }

  /// Outcome of parsing a `<breath …/>` tag's attributes.
  ///
  /// - `inline`: a positional breath whose offset is taken from the
  ///   inline-note's location in the surrounding dialogue paragraph.
  /// - `after`: a substring-anchored breath. The substring is resolved
  ///   against the stripped prose after all inline notes have been
  ///   removed.
  /// - `skip`: the tag was malformed (bad `length`/`strength`/`after`
  ///   combo). A diagnostic has already been recorded.
  private enum BreathTagOutcome {
    case inline(strength: BreathStrength)
    case after(substring: String, strength: BreathStrength)
    case skip
  }

  /// Parse a `<breath …/>` self-closing tag's attributes (`strength`,
  /// `after`) into either an `inline` or `after` outcome.
  ///
  /// Per Decision D-1, `<breath>` no longer accepts `length`: it is a silent
  /// phrasing hint with no duration. If a `length` attribute is present it is
  /// ignored and a warning diagnostic is emitted directing the author to
  /// `<pause>` instead — the breath itself is still produced.
  ///
  /// Default per spec §4.2: `strength="medium"`. Invalid `strength`/`after`
  /// values produce a `skip` outcome plus a diagnostic.
  private func parseBreathTag(
    _ tag: String,
    line: Int
  ) -> (outcome: BreathTagOutcome, diagnostics: [GlosaDiagnostic]) {
    var diagnostics: [GlosaDiagnostic] = []

    // length is no longer valid on <breath> (D-1). If present, ignore it and
    // warn — but do NOT skip the breath; it still becomes a phrasing hint.
    if extractAttribute("length", from: tag) != nil {
      diagnostics.append(
        GlosaDiagnostic(
          severity: .warning,
          message: "`length` is not valid on `<breath>`; use `<pause>`",
          line: line
        ))
    }

    // strength
    let strength: BreathStrength
    if let raw = extractAttribute("strength", from: tag) {
      if let parsed = BreathStrength(rawValue: raw) {
        strength = parsed
      } else {
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message: "Breath has invalid strength=\"\(raw)\"; ignoring",
            line: line
          ))
        return (.skip, diagnostics)
      }
    } else {
      strength = .medium
    }

    // after (optional fallback positioning)
    if let after = extractAttribute("after", from: tag) {
      if after.isEmpty {
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message: "Breath has empty after=\"\"; ignoring",
            line: line
          ))
        return (.skip, diagnostics)
      }
      return (
        .after(substring: after, strength: strength),
        diagnostics
      )
    }

    return (.inline(strength: strength), diagnostics)
  }

  // MARK: - Pause Extraction (Fountain inline notes)

  /// Result of scanning a dialogue paragraph for inline `[[<pause/>]]` notes.
  /// Mirrors ``BreathExtraction``.
  ///
  /// - `strippedText`: the paragraph with every well-formed pause note
  ///   removed. Pause offsets in `pauses` are measured against this string.
  /// - `pauses`: the pause markers discovered, in document order, each
  ///   carrying its `characterOffset` in the stripped prose.
  /// - `diagnostics`: warnings for malformed attribute values or unresolved
  ///   `after=` substrings. The offending pause is skipped but its `[[ ]]`
  ///   markers are still stripped so the remaining prose is contiguous.
  private struct PauseExtraction {
    var strippedText: String
    var pauses: [Pause]
    var diagnostics: [GlosaDiagnostic]
  }

  /// Scan a dialogue paragraph for inline `[[<pause/>]]` notes, returning the
  /// notes-stripped text together with the extracted `Pause` values and any
  /// diagnostics. Mirrors ``extractBreaths(from:sceneIndex:dialogueLineIndex:line:)``;
  /// offsets are computed against the *stripped* prose.
  private func extractPauses(
    from text: String,
    sceneIndex: Int,
    dialogueLineIndex: Int,
    line: Int
  ) -> PauseExtraction {
    let nsText = text as NSString
    guard
      let regex = try? NSRegularExpression(
        pattern: Self.inlinePausePattern,
        options: []
      )
    else {
      // Literal compile-time constant; unreachable in practice.
      return PauseExtraction(strippedText: text, pauses: [], diagnostics: [])
    }

    let matches = regex.matches(
      in: text,
      options: [],
      range: NSRange(location: 0, length: nsText.length)
    )

    var stripped = ""
    var pauses: [Pause] = []
    var diagnostics: [GlosaDiagnostic] = []

    // Pauses whose `after="…"` substring must be resolved against the fully
    // stripped prose after phase 1 completes.
    struct PendingAfterPause {
      let substring: String
      let length: PauseLength
      let line: Int
    }
    var pendingAfterPauses: [PendingAfterPause] = []

    var rawCursor = 0
    for match in matches {
      let outerRange = match.range(at: 0)
      let innerRange = match.range(at: 1)
      let gapRange = NSRange(
        location: rawCursor,
        length: outerRange.location - rawCursor
      )
      stripped += nsText.substring(with: gapRange)

      let offset = stripped.unicodeScalars.count

      let innerTag = nsText.substring(with: innerRange)
      let parse = parsePauseTag(innerTag, line: line)
      diagnostics.append(contentsOf: parse.diagnostics)

      switch parse.outcome {
      case .skip:
        break
      case .inline(let length):
        pauses.append(
          Pause(
            sceneIndex: sceneIndex,
            dialogueLineIndex: dialogueLineIndex,
            characterOffset: offset,
            length: length
          )
        )
      case .after(let substring, let length):
        pendingAfterPauses.append(
          PendingAfterPause(
            substring: substring,
            length: length,
            line: line
          )
        )
      }

      rawCursor = outerRange.location + outerRange.length
    }

    if rawCursor < nsText.length {
      let tailRange = NSRange(location: rawCursor, length: nsText.length - rawCursor)
      stripped += nsText.substring(with: tailRange)
    }

    let strippedNS = stripped as NSString
    for pending in pendingAfterPauses {
      let found = strippedNS.range(of: pending.substring)
      if found.location == NSNotFound {
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message:
              "Pause after=\"\(pending.substring)\" did not match any substring in the dialogue paragraph; ignoring",
            line: pending.line
          ))
        continue
      }
      let endLocation = found.location + found.length
      let prefix = strippedNS.substring(with: NSRange(location: 0, length: endLocation))
      let scalarOffset = prefix.unicodeScalars.count
      pauses.append(
        Pause(
          sceneIndex: sceneIndex,
          dialogueLineIndex: dialogueLineIndex,
          characterOffset: scalarOffset,
          length: pending.length
        )
      )
    }

    return PauseExtraction(
      strippedText: stripped,
      pauses: pauses,
      diagnostics: diagnostics
    )
  }

  /// Outcome of parsing a `<pause …/>` tag's attributes. Mirrors
  /// ``BreathTagOutcome`` but carries a `PauseLength` instead of a strength.
  private enum PauseTagOutcome {
    case inline(length: PauseLength)
    case after(substring: String, length: PauseLength)
    case skip
  }

  /// Parse a `<pause …/>` self-closing tag's attributes (`length`, `after`)
  /// into either an `inline` or `after` outcome. Mirrors ``parseBreathTag``.
  ///
  /// `length` defaults to `.period` (the `Pause` model default). An
  /// unrecognized `length` value yields a `skip` outcome plus a warning
  /// diagnostic. `<pause>` has no `strength` — a pause is always honored.
  private func parsePauseTag(
    _ tag: String,
    line: Int
  ) -> (outcome: PauseTagOutcome, diagnostics: [GlosaDiagnostic]) {
    var diagnostics: [GlosaDiagnostic] = []

    // length
    let length: PauseLength
    if let raw = extractAttribute("length", from: tag) {
      if let parsed = parseLengthAttribute(raw) {
        length = parsed
      } else {
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message: "Pause has invalid length=\"\(raw)\"; ignoring",
            line: line
          ))
        return (.skip, diagnostics)
      }
    } else {
      length = .period
    }

    // after (optional fallback positioning)
    if let after = extractAttribute("after", from: tag) {
      if after.isEmpty {
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message: "Pause has empty after=\"\"; ignoring",
            line: line
          ))
        return (.skip, diagnostics)
      }
      return (.after(substring: after, length: length), diagnostics)
    }

    return (.inline(length: length), diagnostics)
  }

  /// Convert a raw `length` attribute value into a `PauseLength`. Returns
  /// `nil` for unrecognized tokens.
  ///
  /// Recognized named values (spec §4.2): `comma`, `semicolon`, `period`,
  /// `em-dash`, `beat`. Explicit-duration tokens of the form `<n>ms`
  /// (integer milliseconds) or `<n>s` (decimal seconds) are accepted as
  /// `.explicit(TimeInterval)`. The seconds form mirrors the encoder in
  /// `PauseLength.encode(to:)` — the milliseconds path uses integer
  /// division by 1000.0 so `350ms` round-trips bit-exactly with
  /// `.explicit(0.35)` per methodology rule 5.
  ///
  /// Promoted from `private` to `fileprivate` so the FDX parser delegate
  /// can reuse the same length-attribute mapping rules as the Fountain
  /// inline-note path.
  fileprivate func parseLengthAttribute(_ raw: String) -> PauseLength? {
    switch raw {
    case "comma": return .comma
    case "semicolon": return .semicolon
    case "period": return .period
    case "em-dash": return .emDash
    case "beat": return .beat
    default:
      // Try explicit duration: <n>ms or <n>s
      if raw.hasSuffix("ms") {
        let value = String(raw.dropLast(2))
        if !value.isEmpty, let ms = Int(value), ms >= 0 {
          return .explicit(TimeInterval(ms) / 1000.0)
        }
        return nil
      }
      if raw.hasSuffix("s") {
        let value = String(raw.dropLast(1))
        if !value.isEmpty, let seconds = Double(value), seconds >= 0 {
          return .explicit(seconds)
        }
        return nil
      }
      return nil
    }
  }

  /// Build an IntentEntry from accumulated parsing state.
  private func makeIntentEntry(
    attrs: Intent,
    constraints: [Constraint],
    dialogue: [String],
    scoped: Bool
  ) -> GlosaScore.IntentEntry {
    var intent = attrs
    intent.scoped = scoped
    intent.lineCount = scoped ? dialogue.count : nil
    return GlosaScore.IntentEntry(
      intent: intent,
      constraints: constraints,
      dialogueLines: dialogue
    )
  }
}

// MARK: - FDX XMLParser Delegate

/// XMLParser delegate that extracts `glosa:` namespace elements from FDX XML.
private final class FDXParserDelegate: NSObject, XMLParserDelegate {

  private static let glosaNamespace = "https://intrusive-memory.productions/glosa"

  // Parsing state
  private var scenes: [GlosaScore.SceneEntry] = []
  private var currentScene: SceneContext?
  private var currentIntents: [GlosaScore.IntentEntry] = []
  private var pendingConstraints: [Constraint] = []
  private var currentIntentAttrs: Intent?
  private var currentIntentConstraints: [Constraint] = []
  private var currentIntentDialogue: [String] = []
  /// Tracks whether the current intent was opened via didStartElement.
  /// When didEndElement is called for Intent, it's either:
  /// - Self-closing (no dialogue) = marker
  /// - Scoped (has dialogue) = scoped
  private var intentOpenedViaStartElement = false

  // FDX paragraph tracking
  private var currentParagraphType: String?
  /// Accumulates all character data from every `<Text>` child within the
  /// current `<Paragraph>`. Reset on `<Paragraph>` start — *not* on
  /// `<Text>` start — so paragraphs with multiple style runs do not lose
  /// text. This is also the buffer whose `unicodeScalars.count` provides
  /// the `characterOffset` for any `<glosa:breath/>` start event fired
  /// between sibling `<Text>` runs (spec §5.2).
  private var currentText = ""
  private var isCollectingText = false
  private var lastCharacterName: String?

  // Breath-parsing state.
  /// All breaths discovered across the document, in document order.
  private var breaths: [Breath] = []
  /// Breaths discovered inside the current `<Paragraph>`, awaiting commit
  /// with the paragraph's scene-local `dialogueLineIndex` at paragraph end.
  /// Each entry's `dialogueLineIndex` is filled in at commit time.
  private var pendingParagraphBreaths: [Breath] = []
  /// All pauses discovered across the document, in document order.
  private var pauses: [Pause] = []
  /// Pauses discovered inside the current `<Paragraph>`, awaiting commit with
  /// the paragraph's scene-local `dialogueLineIndex` at paragraph end.
  private var pendingParagraphPauses: [Pause] = []
  /// Scene-local count of dialogue paragraphs already committed in the
  /// current scene. Resets when a new scene opens. Mirrors the Fountain
  /// path's semantics so the same Bishop fixture in FDX form yields the
  /// same `dialogueLineIndex` values as the Fountain equivalent.
  private var sceneDialogueLineCount: Int = 0
  /// Zero-based index of the currently open scene in document order, or
  /// `-1` when no `<glosa:SceneContext>` is open. Set to `scenes.count`
  /// at the moment a SceneContext opens so the index reflects where this
  /// scene will land in `scenes`.
  private var currentSceneIndex: Int = -1
  /// Helper reused for `length` attribute parsing. The struct has no
  /// state, so a single shared instance is safe and Sendable.
  private let parserHelper = GlosaParser()

  /// Diagnostics emitted during parsing (malformed breath attributes,
  /// breath markers outside dialogue paragraphs, etc.). Surfaced via
  /// `parseFDXWithDiagnostics(data:)`.
  var diagnostics: [GlosaDiagnostic] = []

  func buildScore() -> GlosaScore {
    // Handle unclosed structures
    if let intentAttrs = currentIntentAttrs {
      let entry = makeIntentEntry(
        attrs: intentAttrs,
        constraints: currentIntentConstraints,
        dialogue: currentIntentDialogue,
        scoped: false
      )
      currentIntents.append(entry)
      currentIntentAttrs = nil
    }

    if let scene = currentScene {
      scenes.append(
        GlosaScore.SceneEntry(
          context: scene,
          intents: currentIntents
        ))
    }

    return GlosaScore(scenes: scenes, breaths: breaths, pauses: pauses)
  }

  // MARK: - XMLParserDelegate

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String]
  ) {
    let localName = elementName.components(separatedBy: ":").last ?? elementName

    if namespaceURI == Self.glosaNamespace || elementName.hasPrefix("glosa:") {
      switch localName {
      case "SceneContext":
        let location = attributeDict["location"] ?? ""
        let time = attributeDict["time"] ?? ""
        let ambience = attributeDict["ambience"]
        currentScene = SceneContext(location: location, time: time, ambience: ambience)
        currentIntents = []
        pendingConstraints = []
        // New scene: reset the scene-local dialogue counter so the first
        // dialogue paragraph in this scene is `dialogueLineIndex 0`.
        sceneDialogueLineCount = 0
        // `scenes` already contains every previously-closed scene at this
        // point, so its current length is the index this new scene will
        // occupy once it is appended.
        currentSceneIndex = scenes.count

      case "Intent":
        let from = attributeDict["from"] ?? ""
        let to = attributeDict["to"] ?? ""
        let pace = attributeDict["pace"]
        let spacing = attributeDict["spacing"]

        // Close any previous open intent as marker (superseded)
        if let prevAttrs = currentIntentAttrs {
          let entry = makeIntentEntry(
            attrs: prevAttrs,
            constraints: currentIntentConstraints,
            dialogue: currentIntentDialogue,
            scoped: false
          )
          currentIntents.append(entry)
          currentIntentConstraints = []
          currentIntentDialogue = []
        }

        currentIntentAttrs = Intent(from: from, to: to, pace: pace, spacing: spacing)
        currentIntentConstraints = pendingConstraints
        pendingConstraints = []
        intentOpenedViaStartElement = true

      case "Constraint":
        let character = attributeDict["character"] ?? ""
        let direction = attributeDict["direction"] ?? ""
        let register = attributeDict["register"]
        let ceiling = attributeDict["ceiling"]
        let constraint = Constraint(
          character: character,
          direction: direction,
          register: register,
          ceiling: ceiling
        )

        if currentIntentAttrs != nil {
          currentIntentConstraints.append(constraint)
        } else {
          pendingConstraints.append(constraint)
        }

      case "breath":
        handleBreathStart(attributes: attributeDict)

      case "pause":
        handlePauseStart(attributes: attributeDict)

      default:
        break
      }
    } else if elementName == "Paragraph" {
      currentParagraphType = attributeDict["Type"]
      // Reset accumulator at paragraph start. Per Q#3 scope expansion,
      // the `<Text>` start branch must NOT also reset — paragraphs may
      // have multiple style runs (and, per spec §5.2, runs interleaved
      // with `<glosa:breath/>` markers). Resetting per-`<Text>` would
      // drop every run except the last.
      currentText = ""
      pendingParagraphBreaths = []
    } else if elementName == "Text" {
      // Begin collecting characters but DO NOT reset `currentText`.
      // Multiple `<Text>` runs within one `<Paragraph>` must all
      // contribute to the same accumulator so breath offsets measured
      // off `currentText.unicodeScalars.count` reflect the cumulative
      // prose preceding the breath (spec §5.2).
      isCollectingText = true
    }
  }

  /// Handle a `<glosa:breath/>` self-closing element discovered during
  /// FDX parsing. Computes the character offset against `currentText`
  /// (the accumulated prose so far in the current paragraph), parses the
  /// `length` and `strength` attributes per spec §4.2, and stashes the
  /// breath into `pendingParagraphBreaths` for commit at paragraph end.
  ///
  /// A breath outside a `<Paragraph Type="Dialogue">` (or outside any
  /// open `<glosa:Intent>` scope) yields one warning diagnostic and zero
  /// breath records, matching the Fountain path's behavior per spec §4.3.
  /// Malformed `length` or `strength` attributes likewise yield a
  /// warning and skip the breath.
  private func handleBreathStart(attributes: [String: String]) {
    // Scope check: must be inside a Dialogue paragraph that is itself
    // inside an open Intent (matching the Fountain path's contract).
    guard currentParagraphType == "Dialogue", currentIntentAttrs != nil else {
      diagnostics.append(
        GlosaDiagnostic(
          severity: .warning,
          message: "Breath element found outside any dialogue paragraph; ignoring"
        ))
      return
    }

    // length is no longer valid on <breath> (D-1). If present, ignore it and
    // warn — but do NOT skip the breath; it still becomes a phrasing hint.
    if attributes["length"] != nil {
      diagnostics.append(
        GlosaDiagnostic(
          severity: .warning,
          message: "`length` is not valid on `<breath>`; use `<pause>`"
        ))
    }

    // strength attribute — defaults to .medium when absent.
    let strength: BreathStrength
    if let raw = attributes["strength"] {
      if let parsed = BreathStrength(rawValue: raw) {
        strength = parsed
      } else {
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message: "Breath has invalid strength=\"\(raw)\"; ignoring"
          ))
        return
      }
    } else {
      strength = .medium
    }

    // Offset is the Unicode-scalar count of prose accumulated so far in
    // the current paragraph. Matches the Fountain path's offset
    // semantics so the same Bishop dialogue line produces identical
    // offsets across both formats (spec §6.4: 20 / 31 / 43).
    //
    // dialogueLineIndex is filled in at paragraph commit time, where the
    // scene-local count is known.
    let offset = currentText.unicodeScalars.count
    pendingParagraphBreaths.append(
      Breath(
        sceneIndex: currentSceneIndex,
        dialogueLineIndex: -1,
        characterOffset: offset,
        strength: strength
      )
    )
  }

  /// Handle a `<glosa:pause/>` self-closing element discovered during FDX
  /// parsing. Mirrors ``handleBreathStart(attributes:)``: computes the
  /// character offset against `currentText`, parses the `length` attribute
  /// (defaulting to `.period`), and stashes the pause into
  /// `pendingParagraphPauses` for commit at paragraph end.
  ///
  /// A pause outside a `<Paragraph Type="Dialogue">` (or outside any open
  /// `<glosa:Intent>` scope) yields one warning diagnostic and zero pause
  /// records. An unrecognized `length` value likewise yields a warning and
  /// skips the pause. `<pause>` has no `strength`.
  private func handlePauseStart(attributes: [String: String]) {
    guard currentParagraphType == "Dialogue", currentIntentAttrs != nil else {
      diagnostics.append(
        GlosaDiagnostic(
          severity: .warning,
          message: "Pause element found outside any dialogue paragraph; ignoring"
        ))
      return
    }

    // length attribute — defaults to .period when absent.
    let length: PauseLength
    if let raw = attributes["length"] {
      if let parsed = parserHelper.parseLengthAttribute(raw) {
        length = parsed
      } else {
        diagnostics.append(
          GlosaDiagnostic(
            severity: .warning,
            message: "Pause has invalid length=\"\(raw)\"; ignoring"
          ))
        return
      }
    } else {
      length = .period
    }

    let offset = currentText.unicodeScalars.count
    pendingParagraphPauses.append(
      Pause(
        sceneIndex: currentSceneIndex,
        dialogueLineIndex: -1,
        characterOffset: offset,
        length: length
      )
    )
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let localName = elementName.components(separatedBy: ":").last ?? elementName

    if namespaceURI == Self.glosaNamespace || elementName.hasPrefix("glosa:") {
      switch localName {
      case "SceneContext":
        // Close any open intent as marker (not explicitly closed with </Intent>)
        if let intentAttrs = currentIntentAttrs {
          let entry = makeIntentEntry(
            attrs: intentAttrs,
            constraints: currentIntentConstraints,
            dialogue: currentIntentDialogue,
            scoped: false
          )
          currentIntents.append(entry)
          currentIntentAttrs = nil
          currentIntentConstraints = []
          currentIntentDialogue = []
          intentOpenedViaStartElement = false
        }

        if let scene = currentScene {
          scenes.append(
            GlosaScore.SceneEntry(
              context: scene,
              intents: currentIntents
            ))
        }
        currentScene = nil
        currentIntents = []
        pendingConstraints = []
        // Scene boundary: scene-local dialogue counter resets so the
        // next scene's first dialogue paragraph is `dialogueLineIndex 0`.
        sceneDialogueLineCount = 0
        currentSceneIndex = -1

      case "Intent":
        // didEndElement for Intent fires in two cases:
        // 1. Self-closing <glosa:Intent .../> -- marker intent, keep open for subsequent dialogue
        // 2. Explicit closing </glosa:Intent> -- scoped intent, close now
        //
        // We distinguish by checking whether dialogue was collected.
        // Self-closing tags have zero dialogue between start and end.
        if let intentAttrs = currentIntentAttrs {
          if currentIntentDialogue.isEmpty {
            // Self-closing tag: this is a MARKER intent.
            // Keep currentIntentAttrs open so subsequent dialogue is collected.
            // Don't close it here -- it will be closed by the next Intent open,
            // SceneContext close, or buildScore().
            break
          }
          // Scoped intent with dialogue: close it now
          let entry = makeIntentEntry(
            attrs: intentAttrs,
            constraints: currentIntentConstraints,
            dialogue: currentIntentDialogue,
            scoped: true
          )
          currentIntents.append(entry)
          currentIntentAttrs = nil
          currentIntentConstraints = []
          currentIntentDialogue = []
          intentOpenedViaStartElement = false
        }

      default:
        break
      }
    } else if elementName == "Text" {
      isCollectingText = false
    } else if elementName == "Paragraph" {
      let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
      if let type = currentParagraphType {
        if type == "Character" {
          lastCharacterName = text
        } else if type == "Dialogue" && currentIntentAttrs != nil {
          currentIntentDialogue.append(text)
          // Commit any breaths accumulated during this dialogue
          // paragraph using the scene-local index, then advance the
          // counter so the next dialogue paragraph in this scene gets
          // the next index. Mirrors the Fountain path's bookkeeping.
          let lineIndex = sceneDialogueLineCount
          for breath in pendingParagraphBreaths {
            breaths.append(
              Breath(
                sceneIndex: breath.sceneIndex,
                dialogueLineIndex: lineIndex,
                characterOffset: breath.characterOffset,
                strength: breath.strength
              )
            )
          }
          for pause in pendingParagraphPauses {
            pauses.append(
              Pause(
                sceneIndex: pause.sceneIndex,
                dialogueLineIndex: lineIndex,
                characterOffset: pause.characterOffset,
                length: pause.length
              )
            )
          }
          sceneDialogueLineCount += 1
        } else if !pendingParagraphBreaths.isEmpty || !pendingParagraphPauses.isEmpty {
          // Pending breaths sit inside a non-dialogue paragraph (e.g.
          // `<Paragraph Type="Action">`). The breath element's
          // didStartElement handler should have rejected these already
          // — but if any slipped through (e.g. paragraph type changed
          // between start and end), emit one diagnostic per stray
          // breath and discard. Defensive code path; not expected to
          // fire under normal FDX.
          for _ in pendingParagraphBreaths {
            diagnostics.append(
              GlosaDiagnostic(
                severity: .warning,
                message: "Breath element found outside any dialogue paragraph; ignoring"
              ))
          }
          for _ in pendingParagraphPauses {
            diagnostics.append(
              GlosaDiagnostic(
                severity: .warning,
                message: "Pause element found outside any dialogue paragraph; ignoring"
              ))
          }
        }
      }
      pendingParagraphBreaths = []
      pendingParagraphPauses = []
      currentParagraphType = nil
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if isCollectingText {
      currentText += string
    }
  }

  // MARK: - FDX delegate also handles self-closing tags

  // In XMLParser, self-closing tags (<tag/>) trigger both didStartElement and
  // didEndElement in sequence. For self-closing <glosa:Intent/>, this means
  // didStartElement opens the intent, then didEndElement immediately closes it
  // as "scoped" with 0 dialogue lines. We need to detect this case.
  //
  // The fix: in didEndElement for Intent, if there are 0 dialogue lines and
  // the intent was just opened, treat it as a marker (self-closing).
  // Actually, for FDX, self-closing <glosa:Intent.../> is a MARKER intent.
  // The didStartElement already opened it, and didEndElement will close it
  // immediately. We handle this by checking dialogue count in makeIntentEntry.

  // MARK: - Private Helpers

  private func makeIntentEntry(
    attrs: Intent,
    constraints: [Constraint],
    dialogue: [String],
    scoped: Bool
  ) -> GlosaScore.IntentEntry {
    var intent = attrs
    // If the intent element had opening+closing tags but zero dialogue,
    // it's a self-closing marker in FDX.
    if scoped && dialogue.isEmpty {
      intent.scoped = false
      intent.lineCount = nil
    } else {
      intent.scoped = scoped
      intent.lineCount = scoped ? dialogue.count : nil
    }
    return GlosaScore.IntentEntry(
      intent: intent,
      constraints: constraints,
      dialogueLines: dialogue
    )
  }
}
