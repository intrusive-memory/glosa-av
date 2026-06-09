import Foundation

/// A single deliberate, audible silence inside a dialogue line.
///
/// `Pause` is a positional marker carrying the information the downstream
/// chunker needs to insert a timed silence into an utterance. Unlike `Breath`
/// — which is a silent phrasing hint with no duration — a `Pause` always
/// models real audible silence and forces a chunk seam at its offset. It has
/// no `strength`: a pause is always honored, never traded against the
/// chunker's character-budget heuristics.
public struct Pause: Sendable, Equatable, Codable {

  /// Index of the enclosing scene (zero-based, in document order). `-1`
  /// represents a pause emitted while no `<SceneContext>` was open —
  /// pathological input that the compiler silently drops.
  public var sceneIndex: Int

  /// Index of the dialogue line within its enclosing scene that this pause
  /// applies to. Scene-local; the compiler maps `(sceneIndex,
  /// dialogueLineIndex)` to an absolute screenplay line index in
  /// `CompilationResult.pausePoints`.
  public var dialogueLineIndex: Int

  /// Character offset within the dialogue line text where the silence is
  /// placed. `0` means before the first character; `line.count` means after
  /// the last character (invalid — the validator emits a diagnostic).
  public var characterOffset: Int

  /// Target perceived silence duration. Defaults to `.period`.
  public var length: PauseLength

  public init(
    sceneIndex: Int,
    dialogueLineIndex: Int,
    characterOffset: Int,
    length: PauseLength = .period
  ) {
    self.sceneIndex = sceneIndex
    self.dialogueLineIndex = dialogueLineIndex
    self.characterOffset = characterOffset
    self.length = length
  }
}
