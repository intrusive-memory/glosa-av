import GlosaCore

/// Pure rendering helpers for surfacing `BreathPoint` data in CLI output.
///
/// These functions are pure — they take value types and return `String` values
/// with no side effects, no I/O, and no shared mutable state. `PreviewCommand`
/// calls `renderBreathBlock(for:)` and inserts the result into its output.
/// Tests exercise the helpers directly inside `GlosaAnnotationTests`.
///
/// ## Format spec §9
///
/// ```
/// breaths: at <offset> (<length>, <strength>)
///          at <offset> (<length>, <strength>)
/// ```
///
/// - The label `"breaths: "` is nine characters (`b r e a t h s : SPACE`).
/// - Continuation lines are indented with nine spaces so `at` aligns under
///   the `at` on the first line.
/// - `<length>` uses the same wire-format token the parser and serializer use
///   (`comma`, `semicolon`, `period`, `em-dash`, `beat`, `<N>ms`).
/// - `<strength>` uses the raw value of `BreathStrength` (`weak`, `medium`,
///   `strong`).
public enum BreathRenderer {

  // MARK: - Public API

  /// Renders a formatted breath block for the given breath points.
  ///
  /// Returns `nil` when `breathPoints` is empty so callers can suppress
  /// the section entirely with a simple `if let` check.
  ///
  /// - Parameter breathPoints: The breath points to render, expected to be
  ///   sorted ascending by `offset` (the compiler guarantees this ordering).
  /// - Returns: A multi-line string beginning with `"breaths: at …"`, or
  ///   `nil` when the array is empty.
  public static func renderBreathBlock(for breathPoints: [BreathPoint]) -> String? {
    guard !breathPoints.isEmpty else { return nil }

    let prefix = "breaths: "  // 9 characters
    let continuation = "         "  // 9 spaces

    var lines: [String] = []
    for (index, point) in breathPoints.enumerated() {
      // NOTE (Sortie 1, CLEAVING BREATH): `BreathPoint.length` was removed when
      // duration moved to `Pause`. Length is no longer rendered for breaths;
      // Sortie 7 reworks CLI output to surface pauses separately.
      let strengthToken = point.strength.rawValue
      let atClause = "at \(point.offset) (\(strengthToken))"
      if index == 0 {
        lines.append("\(prefix)\(atClause)")
      } else {
        lines.append("\(continuation)\(atClause)")
      }
    }

    return lines.joined(separator: "\n")
  }

  // MARK: - Internal helpers

  /// Converts a `PauseLength` to its wire-format display token.
  ///
  /// The tokens match the attribute values accepted by the Fountain and FDX
  /// parsers (and emitted by `GlosaSerializer`): `comma`, `semicolon`,
  /// `period`, `em-dash`, `beat`, or `<N>ms` for explicit durations.
  static func breathLengthToken(_ length: PauseLength) -> String {
    switch length {
    case .comma: return "comma"
    case .semicolon: return "semicolon"
    case .period: return "period"
    case .emDash: return "em-dash"
    case .beat: return "beat"
    case .explicit(let seconds):
      let ms = Int((seconds * 1000).rounded())
      return "\(ms)ms"
    }
  }
}
