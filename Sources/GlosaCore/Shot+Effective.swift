// MARK: - Fold: effective shots

extension Shot {

  /// The shot as it renders once the promptless defaults shots before it are
  /// folded in (REQ § 2.4).
  ///
  /// `defaults` are the promptless shots that precede this one, in document
  /// order. The fold starts from an empty accumulator; each defaults shot, in
  /// turn, replaces the accumulated value of every key it sets. Then this
  /// shot's own keys replace the accumulated value of every key it sets, so
  /// its own keys always win.
  ///
  /// - `caption` and `output` are **never inherited**: the result carries this
  ///   shot's own values (or `nil`). An inherited `output` would make every
  ///   later panel overwrite one file.
  /// - `prompt` and `documentIndex` are this shot's own.
  /// - `extraAttributes` fold per key like any known key. Order: keys appear
  ///   in the order first seen across `defaults` then this shot; a later value
  ///   for a key already present replaces it in place.
  ///
  /// A known key holding `nil` sets nothing; an extra attribute whose value is
  /// JSON `null` is a value and replaces like any other.
  public func effective(given defaults: [Shot]) -> Shot {
    var result = Shot(
      documentIndex: documentIndex, prompt: prompt, caption: caption, output: output)
    for layer in defaults + [self] {
      result.absorb(layer)
    }
    return result
  }

  /// Replaces each value `layer` sets, except `prompt`, `caption`, `output`
  /// and `documentIndex`.
  private mutating func absorb(_ layer: Shot) {
    if let v = layer.style { style = v }
    if let v = layer.model { model = v }
    if let v = layer.aspect { aspect = v }
    if let v = layer.width { width = v }
    if let v = layer.height { height = v }
    if let v = layer.steps { steps = v }
    if let v = layer.guidance { guidance = v }
    if let v = layer.seed { seed = v }
    if let v = layer.negative { negative = v }
    if let v = layer.lora { lora = v }
    if let v = layer.loraScale { loraScale = v }
    if let v = layer.preview { preview = v }
    if let v = layer.telemetry { telemetry = v }
    if let v = layer.ref { ref = v }
    if let v = layer.character { character = v }
    for extra in layer.extraAttributes {
      if let index = extraAttributes.firstIndex(where: { $0.key == extra.key }) {
        extraAttributes[index] = extra
      } else {
        extraAttributes.append(extra)
      }
    }
  }
}

extension GlosaScore {

  /// Every panel shot (non-empty `prompt`) in document order, each already
  /// folded with `Shot.effective(given:)` over all promptless shots that
  /// precede it in document order (by `documentIndex`).
  ///
  /// Defaults shots (empty `prompt`) render nothing and are not returned.
  public var effectiveShots: [Shot] {
    let ordered = shots.enumerated()
      .sorted { ($0.element.documentIndex, $0.offset) < ($1.element.documentIndex, $1.offset) }
      .map(\.element)
    var defaults: [Shot] = []
    var panels: [Shot] = []
    for shot in ordered {
      if shot.prompt.isEmpty {
        defaults.append(shot)
      } else {
        panels.append(shot.effective(given: defaults))
      }
    }
    return panels
  }
}
