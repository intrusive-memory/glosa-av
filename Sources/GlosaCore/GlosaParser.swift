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
    // Standalone block-event state. Each carries its own document-order index;
    // unlike breaths/pauses they are not anchored to dialogue lines.
    var includes: [Include] = []
    var shots: [Shot] = []
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

      // Standalone block events: `<include/>` and `<shot/>`. These are
      // document-positional (keyed by `noteIndex`), open no scope, and may
      // appear anywhere — including before any `<SceneContext>`. Match them
      // before the dialogue fallthrough so they are never mistaken for prose.
      if let include = parseIncludeTag(trimmed, documentIndex: noteIndex) {
        includes.append(include)
        continue
      }

      if let shot = parseShotTag(trimmed, documentIndex: noteIndex) {
        shots.append(shot)
        continue
      }

      // If we reach here, this is a dialogue line (or non-tag content).
      // Inside an intent, scan for inline `[[<breath/>]]` notes, strip them
      // from the stored text, and emit `Breath` values whose offsets are
      // measured against the notes-stripped prose.
      if currentIntentAttrs != nil && !trimmed.isEmpty {
        // Strip breath AND pause notes in a single combined pass so BOTH
        // marker kinds record their `characterOffset` against the same
        // fully-stripped canonical prose (the bytes the actor reads with
        // neither breath nor pause notes present). A two-pass design that
        // stripped breaths off prose still containing pause notes would
        // inflate any breath following a pause marker by that note's literal
        // length; the combined pass keeps breath and pause offsets symmetric.
        let extraction = extractInlineNotes(
          from: trimmed,
          sceneIndex: currentSceneIndex,
          dialogueLineIndex: sceneDialogueLineCount,
          line: lineNumber
        )
        currentIntentDialogue.append(extraction.strippedText)
        breaths.append(contentsOf: extraction.breaths)
        pauses.append(contentsOf: extraction.pauses)
        diagnostics.append(contentsOf: extraction.diagnostics)
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

    return (
      GlosaScore(
        scenes: scenes,
        breaths: breaths,
        pauses: pauses,
        includes: includes,
        shots: shots
      ),
      diagnostics
    )
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

    return SceneContext(
      location: location,
      time: time,
      ambience: ambience,
      prompt: extractAttribute("prompt", from: text)
    )
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
      ceiling: ceiling,
      prompt: extractAttribute("prompt", from: text)
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

    return Intent(
      from: from,
      to: to,
      pace: pace,
      spacing: spacing,
      prompt: extractAttribute("prompt", from: text)
    )
  }

  /// Parse an `<include …/>` standalone block tag into an `Include`.
  ///
  /// Returns `nil` for any note that is not an `<include>` tag. A note that *is*
  /// an `<include>` but lacks a `src` is still returned (with an empty `src`)
  /// so the validator can surface a precise diagnostic rather than the tag
  /// being silently mistaken for dialogue. Malformed numeric attributes coerce
  /// to `nil` (lenient parse).
  private func parseIncludeTag(_ text: String, documentIndex: Int) -> Include? {
    guard text.contains("<include") && !text.contains("</include") else {
      return nil
    }

    let mode = extractAttribute("mode", from: text).flatMap(IncludeMode.init(rawValue:))

    return Include(
      documentIndex: documentIndex,
      src: extractAttribute("src", from: text) ?? "",
      gain: doubleAttribute("gain", from: text),
      mode: mode,
      fadeIn: doubleAttribute("fadeIn", from: text),
      fadeOut: doubleAttribute("fadeOut", from: text),
      prompt: extractAttribute("prompt", from: text)
    )
  }

  /// Parse a `<shot …/>` standalone block tag into a `Shot`.
  ///
  /// Returns `nil` for any note that is not a `<shot>` tag. A `<shot>` missing
  /// its `prompt` is still returned (with an empty `prompt`) so the validator
  /// can report it. `model`/`aspect` are carried as raw strings; numeric and
  /// boolean attributes coerce leniently (a malformed value becomes `nil`).
  private func parseShotTag(_ text: String, documentIndex: Int) -> Shot? {
    guard text.contains("<shot") && !text.contains("</shot") else {
      return nil
    }

    return Shot(
      documentIndex: documentIndex,
      prompt: extractAttribute("prompt", from: text) ?? "",
      style: extractAttribute("style", from: text),
      model: extractAttribute("model", from: text),
      aspect: extractAttribute("aspect", from: text),
      width: intAttribute("width", from: text),
      height: intAttribute("height", from: text),
      steps: intAttribute("steps", from: text),
      guidance: doubleAttribute("guidance", from: text),
      seed: uint64Attribute("seed", from: text),
      negative: extractAttribute("negative", from: text),
      lora: extractAttribute("lora", from: text),
      loraScale: doubleAttribute("loraScale", from: text),
      output: extractAttribute("output", from: text),
      preview: boolAttribute("preview", from: text),
      telemetry: boolAttribute("telemetry", from: text)
    )
  }

  /// Extract an attribute and coerce it to `Int`. Returns `nil` when absent or
  /// not a valid integer (lenient parse).
  private func intAttribute(_ name: String, from text: String) -> Int? {
    extractAttribute(name, from: text).flatMap { Int($0) }
  }

  /// Extract an attribute and coerce it to `Double`. Returns `nil` when absent
  /// or not a valid number (lenient parse).
  private func doubleAttribute(_ name: String, from text: String) -> Double? {
    extractAttribute(name, from: text).flatMap { Double($0) }
  }

  /// Extract an attribute and coerce it to `UInt64`. Returns `nil` when absent
  /// or not a valid unsigned integer (lenient parse).
  private func uint64Attribute(_ name: String, from text: String) -> UInt64? {
    extractAttribute(name, from: text).flatMap { UInt64($0) }
  }

  /// Extract a boolean attribute. Recognizes `true`/`false`/`yes`/`no`/`1`/`0`
  /// (case-insensitive). Returns `nil` when absent or unrecognized.
  private func boolAttribute(_ name: String, from text: String) -> Bool? {
    guard let raw = extractAttribute(name, from: text)?.lowercased() else { return nil }
    switch raw {
    case "true", "yes", "1": return true
    case "false", "no", "0": return false
    default: return nil
    }
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

  // MARK: - Inline-Note Extraction (Fountain inline notes)

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

  /// Result of scanning a dialogue paragraph for inline `[[<breath/>]]` AND
  /// `[[<pause/>]]` notes in a single combined pass.
  ///
  /// - `strippedText`: the canonical "prose the actor reads" — the paragraph
  ///   with every well-formed breath *and* pause note removed.
  /// - `breaths` / `pauses`: the markers discovered, in document order, each
  ///   carrying its `characterOffset` measured against the SAME fully-stripped
  ///   prose. Because both kinds are stripped before any offset is recorded,
  ///   breath and pause offsets are symmetric and directly comparable (a
  ///   prerequisite for the compiler's same-offset breath/pause collapse).
  /// - `diagnostics`: warnings for malformed attribute values or unresolved
  ///   `after=` substrings from either tag kind.
  private struct InlineNoteExtraction {
    var strippedText: String
    var breaths: [Breath]
    var pauses: [Pause]
    var diagnostics: [GlosaDiagnostic]
  }

  /// Scan a dialogue paragraph for inline `[[<breath/>]]` and `[[<pause/>]]`
  /// notes in ONE left-to-right pass, returning the notes-stripped canonical
  /// prose together with the extracted `Breath`/`Pause` values and any
  /// diagnostics.
  ///
  /// This replaces the previous two-pass (`extractBreaths` then
  /// `extractPauses`) design, which measured breath offsets against text that
  /// still contained pause notes — inflating any breath that followed a pause
  /// marker on the same line by the literal length of the pause note. By
  /// building a single stripped buffer and recording each marker's offset as
  /// the current stripped-buffer scalar count, BOTH breath and pause offsets
  /// are canonical (measured against fully-stripped prose). The `after="…"`
  /// fallback for both tag kinds is resolved against the same fully-stripped
  /// prose after the walk completes.
  ///
  /// - Parameters:
  ///   - text: The raw dialogue paragraph, possibly containing breath and/or
  ///     pause notes interleaved with prose.
  ///   - sceneIndex: Zero-based index of the enclosing `<SceneContext>`.
  ///   - dialogueLineIndex: Scene-local index of this dialogue paragraph.
  ///   - line: 1-based note-array index, used for diagnostic `line` numbers.
  private func extractInlineNotes(
    from text: String,
    sceneIndex: Int,
    dialogueLineIndex: Int,
    line: Int
  ) -> InlineNoteExtraction {
    let nsText = text as NSString

    // Route the canonical notes-stripping through the single source of truth
    // (`GlosaInlineNotes.scan`). `result.stripped` is the canonical buffer this
    // method returns as `strippedText`; reusing the same scan's `matches` for
    // offsets/attributes guarantees the buffer is byte-identical to
    // `GlosaInlineNotes.split(text).stripped` and avoids a duplicate regex.
    let scan = GlosaInlineNotes.scan(text)

    var breaths: [Breath] = []
    var pauses: [Pause] = []
    var diagnostics: [GlosaDiagnostic] = []

    // `after="…"` markers whose offset must be resolved against the fully
    // stripped prose after the walk completes.
    struct PendingAfterBreath {
      let substring: String
      let strength: BreathStrength
      let line: Int
      let prompt: String?
    }
    struct PendingAfterPause {
      let substring: String
      let length: PauseLength
      let line: Int
      let prompt: String?
    }
    var pendingAfterBreaths: [PendingAfterBreath] = []
    var pendingAfterPauses: [PendingAfterPause] = []

    // Re-accumulate the gap prefix per match to recover each marker's offset in
    // the canonical (fully-stripped) prose. This mirrors the scan's own gap
    // accumulation exactly: for each match we append the prose gap *before* it,
    // then read the running scalar count — identical to the previous inline
    // walk, but driven by `GlosaInlineNotes`' shared scan.
    var strippedPrefix = ""
    var rawCursor = 0
    for noteMatch in scan.matches {
      let outerRange = noteMatch.outerRange
      // Append the prose gap before this match to the running prefix.
      let gapRange = NSRange(
        location: rawCursor,
        length: outerRange.location - rawCursor
      )
      strippedPrefix += nsText.substring(with: gapRange)

      // Offset of this marker in the canonical (fully-stripped) prose.
      let offset = strippedPrefix.unicodeScalars.count

      let innerTag = noteMatch.innerTag
      // Dispatch by tag kind. The leading `<breath`/`<pause` discriminates.
      if innerTag.hasPrefix("<breath") {
        let parse = parseBreathTag(innerTag, line: line)
        diagnostics.append(contentsOf: parse.diagnostics)
        switch parse.outcome {
        case .skip:
          break
        case .inline(let strength, let prompt):
          breaths.append(
            Breath(
              sceneIndex: sceneIndex,
              dialogueLineIndex: dialogueLineIndex,
              characterOffset: offset,
              strength: strength,
              prompt: prompt
            ))
        case .after(let substring, let strength, let prompt):
          pendingAfterBreaths.append(
            PendingAfterBreath(
              substring: substring, strength: strength, line: line, prompt: prompt))
        }
      } else {
        let parse = parsePauseTag(innerTag, line: line)
        diagnostics.append(contentsOf: parse.diagnostics)
        switch parse.outcome {
        case .skip:
          break
        case .inline(let length, let prompt):
          pauses.append(
            Pause(
              sceneIndex: sceneIndex,
              dialogueLineIndex: dialogueLineIndex,
              characterOffset: offset,
              length: length,
              prompt: prompt
            ))
        case .after(let substring, let length, let prompt):
          pendingAfterPauses.append(
            PendingAfterPause(
              substring: substring, length: length, line: line, prompt: prompt))
        }
      }

      rawCursor = outerRange.location + outerRange.length
    }

    // The canonical fully-stripped prose is owned by `GlosaInlineNotes.scan`
    // (gaps + trailing tail). `strippedPrefix` above only reconstructs the
    // per-marker offset prefixes; the buffer returned/used below is the shared
    // scan's, keeping it byte-identical to `GlosaInlineNotes.split`.
    let stripped = scan.stripped

    // Resolve `after="…"` markers against the fully-stripped prose.
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
      let endLocation = found.location + found.length
      let prefix = strippedNS.substring(with: NSRange(location: 0, length: endLocation))
      breaths.append(
        Breath(
          sceneIndex: sceneIndex,
          dialogueLineIndex: dialogueLineIndex,
          characterOffset: prefix.unicodeScalars.count,
          strength: pending.strength,
          prompt: pending.prompt
        ))
    }
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
      pauses.append(
        Pause(
          sceneIndex: sceneIndex,
          dialogueLineIndex: dialogueLineIndex,
          characterOffset: prefix.unicodeScalars.count,
          length: pending.length,
          prompt: pending.prompt
        ))
    }

    return InlineNoteExtraction(
      strippedText: stripped,
      breaths: breaths,
      pauses: pauses,
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
    case inline(strength: BreathStrength, prompt: String?)
    case after(substring: String, strength: BreathStrength, prompt: String?)
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

    // Universal audio-intent prompt (transported verbatim, never interpreted).
    let prompt = extractAttribute("prompt", from: tag)

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
        .after(substring: after, strength: strength, prompt: prompt),
        diagnostics
      )
    }

    return (.inline(strength: strength, prompt: prompt), diagnostics)
  }

  // MARK: - Pause Tag Parsing (Fountain inline notes)

  /// Outcome of parsing a `<pause …/>` tag's attributes. Mirrors
  /// ``BreathTagOutcome`` but carries a `PauseLength` instead of a strength.
  private enum PauseTagOutcome {
    case inline(length: PauseLength, prompt: String?)
    case after(substring: String, length: PauseLength, prompt: String?)
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

    // Universal audio-intent prompt (transported verbatim, never interpreted).
    let prompt = extractAttribute("prompt", from: tag)

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
      return (.after(substring: after, length: length, prompt: prompt), diagnostics)
    }

    return (.inline(length: length, prompt: prompt), diagnostics)
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
  /// Standalone audio-include events, in document order.
  private var includes: [Include] = []
  /// Standalone storyboard-shot events, in document order.
  private var shots: [Shot] = []
  /// Monotonically-increasing appearance counter assigned as `documentIndex`
  /// to each standalone block event (`<glosa:include>` / `<glosa:shot>`) so the
  /// FDX path mirrors the Fountain path's document-order keying.
  private var blockEventCounter = 0
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

    return GlosaScore(
      scenes: scenes,
      breaths: breaths,
      pauses: pauses,
      includes: includes,
      shots: shots
    )
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
        currentScene = SceneContext(
          location: location,
          time: time,
          ambience: ambience,
          prompt: attributeDict["prompt"]
        )
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

        currentIntentAttrs = Intent(
          from: from,
          to: to,
          pace: pace,
          spacing: spacing,
          prompt: attributeDict["prompt"]
        )
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
          ceiling: ceiling,
          prompt: attributeDict["prompt"]
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

      case "include":
        handleIncludeStart(attributes: attributeDict)

      case "shot":
        handleShotStart(attributes: attributeDict)

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
        strength: strength,
        prompt: attributes["prompt"]
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
        length: length,
        prompt: attributes["prompt"]
      )
    )
  }

  /// Handle a `<glosa:include/>` standalone element. Unlike breath/pause this is
  /// a document-positional block event with no scope or dialogue-offset
  /// requirement, so it is accepted anywhere. Its `documentIndex` is the next
  /// appearance counter value; malformed numeric attributes coerce to `nil`.
  private func handleIncludeStart(attributes: [String: String]) {
    let include = Include(
      documentIndex: blockEventCounter,
      src: attributes["src"] ?? "",
      gain: Self.double(attributes["gain"]),
      mode: attributes["mode"].flatMap(IncludeMode.init(rawValue:)),
      fadeIn: Self.double(attributes["fadeIn"]),
      fadeOut: Self.double(attributes["fadeOut"]),
      prompt: attributes["prompt"]
    )
    includes.append(include)
    blockEventCounter += 1
  }

  /// Handle a `<glosa:shot/>` standalone element. Mirrors
  /// ``handleIncludeStart(attributes:)``: a document-positional block event,
  /// accepted anywhere, with lenient numeric/boolean coercion.
  private func handleShotStart(attributes: [String: String]) {
    let shot = Shot(
      documentIndex: blockEventCounter,
      prompt: attributes["prompt"] ?? "",
      style: attributes["style"],
      model: attributes["model"],
      aspect: attributes["aspect"],
      width: Self.int(attributes["width"]),
      height: Self.int(attributes["height"]),
      steps: Self.int(attributes["steps"]),
      guidance: Self.double(attributes["guidance"]),
      seed: Self.uint64(attributes["seed"]),
      negative: attributes["negative"],
      lora: attributes["lora"],
      loraScale: Self.double(attributes["loraScale"]),
      output: attributes["output"],
      preview: Self.bool(attributes["preview"]),
      telemetry: Self.bool(attributes["telemetry"])
    )
    shots.append(shot)
    blockEventCounter += 1
  }

  /// Lenient `Int` coercion for FDX attribute values.
  private static func int(_ raw: String?) -> Int? { raw.flatMap { Int($0) } }
  /// Lenient `Double` coercion for FDX attribute values.
  private static func double(_ raw: String?) -> Double? { raw.flatMap { Double($0) } }
  /// Lenient `UInt64` coercion for FDX attribute values.
  private static func uint64(_ raw: String?) -> UInt64? { raw.flatMap { UInt64($0) } }
  /// Lenient `Bool` coercion accepting `true`/`false`/`yes`/`no`/`1`/`0`.
  private static func bool(_ raw: String?) -> Bool? {
    switch raw?.lowercased() {
    case "true", "yes", "1": return true
    case "false", "no", "0": return false
    default: return nil
    }
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
                strength: breath.strength,
                prompt: breath.prompt
              )
            )
          }
          for pause in pendingParagraphPauses {
            pauses.append(
              Pause(
                sceneIndex: pause.sceneIndex,
                dialogueLineIndex: lineIndex,
                characterOffset: pause.characterOffset,
                length: pause.length,
                prompt: pause.prompt
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
