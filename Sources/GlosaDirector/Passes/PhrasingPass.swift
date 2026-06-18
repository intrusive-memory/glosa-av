import Foundation
import GlosaAnnotation
import GlosaCore
import SwiftCompartido

/// PHRASING — the first pass command.
///
/// Breaks up long, irregularly phrased dialogue lines with `<breath>` seams.
/// The selection is a free, deterministic word-count gate (no model call): any
/// dialogue line over ``minWordCount`` words gets one phrasing pass. The model's
/// only job is to **rewrite that line with `<breath>` markers inserted inline** —
/// editing text, which it does well — rather than emitting character offsets,
/// which it does badly. We then validate the rewrite word-for-word against the
/// original and derive the offsets ourselves, so a miscount or a paraphrase can
/// never corrupt the line; it is simply rejected and left untouched.
///
/// The mapping is direct: each `<breath>` attaches to the exact `GuionElement`
/// it was placed in. No scene segmentation, no scene-local indices.
///
/// This pass owns the `<breath>` facet exclusively; no other pass emits breaths.
public struct PhrasingPass: ScreenplayPass {

  public let name = "phrasing"

  /// Dialogue lines with at least this many words get a phrasing pass. Lines
  /// shorter than this are structurally too simple to need breath seams, so
  /// they never reach the model. Tunable (see TODO Phase D).
  public static let minWordCount = 24

  public init() {}

  // MARK: - ScreenplayPass

  public func annotate(
    scene: SceneSegment,
    sceneIndex: Int,
    using generator: SceneFacetGenerator,
    model: String
  ) async throws -> SceneAnnotationDelta {
    // Scene-oriented entry point for the orchestrator. Reuses the same per-line
    // work as the whole-screenplay path; the only difference is that breaths are
    // keyed by scene-local dialogue index for the merged `SceneAnnotation`.
    let dialogue = StageDirector.extractDialogueInfo(from: scene.elements)
    var breaths: [BreathAnnotation] = []
    for (index, info) in dialogue.enumerated() {
      for offset in await placeBreaths(in: info.text, using: generator, model: model) {
        breaths.append(
          BreathAnnotation(dialogueLineIndex: index, characterOffset: offset, strength: nil))
      }
    }
    return .breaths(breaths)
  }

  // MARK: - Per-line work (the one code path)

  /// Place breath seams in a single dialogue line and return their character
  /// offsets. Returns `[]` when the line is too short to bother (no model call),
  /// when the model leaves it unchanged, when the rewrite fails validation, or
  /// when the call throws — every non-success path is a safe no-op for that line.
  func placeBreaths(
    in text: String,
    using generator: SceneFacetGenerator,
    model: String
  ) async -> [Int] {
    guard Self.isCandidate(text) else { return [] }
    do {
      let rewrite = try await generator.generateText(
        instructions: BreathPassPrompts.fixInstructions,
        userPrompt: BreathPassPrompts.fixUserPrompt(text: text),
        maxTokens: min(1024, text.count + 64),
        model: model
      )
      guard let rawOffsets = Self.breathOffsets(fromRewrite: rewrite, original: text) else {
        return []
      }
      return Self.sanitizeOffsets(rawOffsets, text: text)
    } catch {
      return []
    }
  }

  // MARK: - Word-count gate

  /// Whether a dialogue line is long enough to warrant a phrasing pass.
  static func isCandidate(_ line: String) -> Bool {
    wordCount(line) >= minWordCount
  }

  /// Count whitespace-separated words.
  static func wordCount(_ line: String) -> Int {
    line.split(whereSeparator: { $0.isWhitespace }).count
  }

  // MARK: - Rewrite validation → offsets

  /// Validate a model rewrite **word for word** against the original line and
  /// return the character offsets (word starts) where `<breath>` markers were
  /// inserted. Returns `nil` if the rewrite altered, added, dropped, or
  /// reordered any word — in which case the line is left untouched.
  ///
  /// This is what makes editing text safe: the model can only *insert markers*;
  /// any actual change to the words is detected here and rejected, and the
  /// offsets we hand downstream are computed by us, never guessed by the model.
  static func breathOffsets(fromRewrite rewrite: String, original: String) -> [Int]? {
    // A sentinel no screenplay text will contain, so the marker tokenizes apart
    // from surrounding words regardless of the spacing the model used.
    let sentinel = "\u{1}"
    var normalized = rewrite
    for variant in ["[[<breath/>]]", "[[<breath />]]", "<breath/>", "<breath />", "<breath>"] {
      normalized = normalized.replacingOccurrences(of: variant, with: " \(sentinel) ")
    }
    let tokens = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)

    // Original words with their start offsets.
    let chars = Array(original)
    var words: [(text: String, start: Int)] = []
    var i = 0
    while i < chars.count {
      if chars[i].isWhitespace {
        i += 1
        continue
      }
      let start = i
      var word = ""
      while i < chars.count, !chars[i].isWhitespace {
        word.append(chars[i])
        i += 1
      }
      words.append((word, start))
    }

    var offsets: [Int] = []
    var wordIndex = 0
    for token in tokens {
      if token == sentinel {
        // Seam before the upcoming word (or at the line's end).
        offsets.append(wordIndex < words.count ? words[wordIndex].start : chars.count)
      } else {
        guard wordIndex < words.count, words[wordIndex].text == token else { return nil }
        wordIndex += 1
      }
    }
    // Every original word must have been accounted for, in order.
    guard wordIndex == words.count else { return nil }
    return offsets
  }

  /// Clean derived offsets: drop those inside the line's edge margin,
  /// de-duplicate, sort, enforce a minimum gap, and cap the count.
  static func sanitizeOffsets(
    _ offsets: [Int],
    text: String,
    minEdge: Int = 10,
    minGap: Int = 30,
    cap: Int = 8
  ) -> [Int] {
    let length = text.count
    let interior = offsets.filter { $0 >= minEdge && $0 <= length - minEdge }
    var kept: [Int] = []
    for offset in Set(interior).sorted() {
      if let last = kept.last, offset - last < minGap { continue }
      kept.append(offset)
      if kept.count >= cap { break }
    }
    return kept
  }

  // MARK: - Whole-screenplay convenience

  /// Run PHRASING over an entire screenplay and produce a breaths-only annotated
  /// screenplay, ready to serialize. Used by the standalone `glosa phrasing`
  /// command. Walks the parsed elements directly and attaches breath points to
  /// each dialogue element — the element *is* the mapping.
  public func annotateScreenplay(
    _ screenplay: GuionParsedElementCollection,
    using generator: SceneFacetGenerator,
    model: String
  ) async throws -> GlosaAnnotatedScreenplay {
    var annotatedElements: [GlosaAnnotatedElement] = []
    for element in screenplay.elements {
      if element.elementType == .dialogue {
        let offsets = await placeBreaths(in: element.elementText, using: generator, model: model)
        let points = offsets.map { BreathPoint(offset: $0, strength: .medium) }
        annotatedElements.append(GlosaAnnotatedElement(element: element, breathPoints: points))
      } else {
        annotatedElements.append(GlosaAnnotatedElement(element: element))
      }
    }

    return GlosaAnnotatedScreenplay(
      screenplay: screenplay,
      annotatedElements: annotatedElements,
      score: GlosaScore(),
      diagnostics: [],
      provenance: []
    )
  }
}
