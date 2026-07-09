/// A diagnostic message produced during GLOSA parsing, validation, or compilation.
///
/// Diagnostics report well-formedness issues, structural warnings, and
/// informational messages without halting the pipeline. The severity level
/// indicates whether the issue may affect output quality.
public struct GlosaDiagnostic: Sendable, Codable, Equatable {

  /// The severity level of a diagnostic.
  public enum Severity: String, Sendable, Codable, Equatable {
    /// A potential issue that may affect output quality.
    case warning
    /// An informational message about the annotation structure.
    case info
  }

  /// Machine-readable diagnostic codes for programmatic filtering.
  ///
  /// Codes introduced by each work unit are grouped by prefix:
  /// - `breath*` — codes added by WU5 (Sortie 8) for breath-related diagnostics.
  public enum Code: String, Sendable, Codable, Equatable {
    /// A `<breath/>` marker was found outside any dialogue line. The parser
    /// already drops such breaths; the validator surfaces the warning so
    /// downstream tooling can report it without re-parsing.
    case breathOutsideDialogue

    /// Two `<breath/>` markers on the same dialogue line share the same
    /// `(dialogueLineIndex, characterOffset)` pair — i.e. they are
    /// positionally identical and one of them is redundant.
    case breathDuplicateOffset

    /// A dialogue line satisfies one or more of spec §6.1's trigger
    /// conditions (length > 180 characters, colon-list pattern, polysyndetic
    /// conjunctions) but carries zero breath annotations. This is advisory:
    /// the Stage Director may have missed a placement opportunity.
    case breathMissingOnLongLine

    /// A `<breath/>` shared an exact `(line, offset)` with a `<pause/>`. The
    /// compiler collapses the pair into a single chunk seam — the pause wins
    /// and the co-located breath is dropped (Decision 4). Informational: the
    /// breath was redundant since the pause already forces a seam there.
    case breathCollapsedByPause

    /// An `<include>` directive was declared without a (non-empty) `src`
    /// attribute. The directive is still carried through, but a downstream
    /// mixer has no file to include.
    case includeMissingSrc

    /// **No longer emitted.** A `<shot>` with an empty `prompt` used to warn,
    /// but by convention such a shot is a legal *defaults declaration* — it
    /// renders nothing and sets the active generation defaults for every
    /// subsequent `<shot>` from that document position forward (see `Shot`).
    /// The case is retained for source/ABI stability of `GlosaDiagnostic.Code`;
    /// the validator never produces it.
    case shotMissingPrompt

    /// A `<shot>` declared a `model` that is not one of the values the Vinetas
    /// CLI currently recognizes. Advisory only — the raw value is carried
    /// through unchanged so this leaf stays decoupled from the CLI's vocabulary.
    case shotUnknownModel

    /// A `<shot>` declared an `aspect` that is not one of the Vinetas CLI's
    /// known aspect-ratio presets. Advisory only — the raw value is carried
    /// through unchanged.
    case shotUnknownAspect

    /// A directive carried a universal `prompt` attribute that was present but
    /// empty or whitespace-only (e.g. `prompt=""`). The empty prompt is carried
    /// through unchanged, but an empty audio-intent prompt gives the downstream
    /// audio model nothing to act on — almost certainly an authoring mistake.
    /// Advisory only.
    case promptEmpty
  }

  /// The severity of this diagnostic.
  public var severity: Severity

  /// A human-readable description of the issue.
  public var message: String

  /// The source line number where the issue was detected, if applicable.
  public var line: Int?

  /// Machine-readable code for programmatic filtering. `nil` for diagnostics
  /// that pre-date the code registry (existing parser / validator diagnostics).
  public var code: Code?

  public init(severity: Severity, message: String, line: Int? = nil, code: Code? = nil) {
    self.severity = severity
    self.message = message
    self.line = line
    self.code = code
  }
}
