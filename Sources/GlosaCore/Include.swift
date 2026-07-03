/// A directive marking an external audio file to fold into the mixdown at this
/// point in the screenplay.
///
/// `Include` is a **standalone block event**: unlike scope directives
/// (`SceneContext`/`Intent`/`Constraint`) it carries no per-line delivery
/// semantics, and unlike point directives (`Breath`/`Pause`) it carries no
/// character offset inside a dialogue line. It is authored as its own
/// `[[<include …/>]]` Fountain note (or `<glosa:include/>` FDX element) and may
/// appear anywhere in document order — in an action line, between dialogue, or
/// before any `<SceneContext>` opens (e.g. an opening music sting).
///
/// GlosaCore only **parses and carries** this directive. The actual mixdown
/// that pulls the referenced file in happens downstream (Produciesta); this
/// leaf never touches audio.
public struct Include: Sendable, Codable, Equatable {

  /// Zero-based position of this directive in the document-order note stream
  /// (the same coordinate the parser uses for diagnostic line numbers, where
  /// `lineNumber == documentIndex + 1`). This is the ordering key consumers use
  /// to interleave includes with dialogue and shots; it is always available and
  /// never dropped, even for includes that appear outside any scene.
  public var documentIndex: Int

  /// Path to the audio file to include. Required.
  public var src: String

  /// Mix gain to apply to the included audio, in the units the downstream mixer
  /// expects (e.g. dB or a 0–1 linear scale). `nil` leaves the default to the
  /// mixer.
  public var gain: Double?

  /// How the included audio combines with the surrounding mix. `nil` leaves the
  /// default to the mixer.
  public var mode: IncludeMode?

  /// Fade-in duration in seconds. `nil` for no explicit fade.
  public var fadeIn: Double?

  /// Fade-out duration in seconds. `nil` for no explicit fade.
  public var fadeOut: Double?

  public init(
    documentIndex: Int,
    src: String,
    gain: Double? = nil,
    mode: IncludeMode? = nil,
    fadeIn: Double? = nil,
    fadeOut: Double? = nil
  ) {
    self.documentIndex = documentIndex
    self.src = src
    self.gain = gain
    self.mode = mode
    self.fadeIn = fadeIn
    self.fadeOut = fadeOut
  }
}

/// How an `Include`'s audio combines with the surrounding mix.
public enum IncludeMode: String, Sendable, Codable, Equatable {
  /// Layer the audio over the existing mix at its document position.
  case overlay
  /// Treat the audio as a sustained background bed under the surrounding
  /// content.
  case bed
  /// Insert the audio as its own segment, played in sequence at this point.
  case sequential
}
