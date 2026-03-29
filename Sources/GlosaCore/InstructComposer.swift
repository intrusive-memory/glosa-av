/// Template-based composition that turns `ResolvedDirectives` into a
/// natural-language instruct string suitable for Qwen3-TTS ChatML instruct format.
///
/// The instruct string is assembled from three components (each included only if active):
///
/// 1. **SceneContext** environment sentence:
///    `"{time} in {location}[, {ambience}]."`
///
/// 2. **Intent** emotional arc sentence with gradient descriptor:
///    `"{arc description}, {pace} pace."`
///
/// 3. **Constraint** behavioral limits sentence:
///    `"{direction}. [Register: {register}.] [Ceiling: {ceiling}.]"`
///
/// When no directives are active, `compose` returns `nil` — the line falls
/// back to parenthetical or neutral delivery.
public struct InstructComposer: Sendable {

  public init() {}

  /// Compose a natural-language instruct string from resolved directives.
  ///
  /// - Parameter directives: The active directives for a single dialogue line.
  /// - Returns: A composed instruct string, or `nil` if no directives are active.
  public func compose(_ directives: ResolvedDirectives) -> String? {
    var components: [String] = []

    // 1. SceneContext environment sentence
    if let scene = directives.sceneContext {
      components.append(composeSceneContext(scene))
    }

    // 2. Intent emotional arc sentence
    if let resolved = directives.intent {
      components.append(composeIntent(resolved))
    }

    // 3. Constraint behavioral limits sentence
    if let constraint = directives.constraint {
      components.append(composeConstraint(constraint))
    }

    guard !components.isEmpty else { return nil }

    return components.joined(separator: " ")
  }

  // MARK: - SceneContext Composition

  /// Compose the environment sentence from a SceneContext.
  ///
  /// Format: `"{time} in {location}[, {ambience}]."`
  private func composeSceneContext(_ scene: SceneContext) -> String {
    var sentence = "\(capitalizeFirst(scene.time)) in \(scene.location)"
    if let ambience = scene.ambience, !ambience.isEmpty {
      sentence += ", \(ambience)"
    }
    sentence += "."
    return sentence
  }

  // MARK: - Intent Arc Composition

  /// Compose the emotional arc sentence from a ResolvedIntent.
  ///
  /// Format: `"{arc description}, {pace} pace."`
  private func composeIntent(_ resolved: ResolvedIntent) -> String {
    let intent = resolved.intent
    let position = resolved.arcPosition
    let arcDescription = describeArc(
      from: intent.from,
      to: intent.to,
      position: position
    )

    var sentence = arcDescription
    if let pace = intent.pace, !pace.isEmpty {
      sentence += ", \(pace) pace"
    }
    sentence += "."
    return sentence
  }

  /// Generate a natural-language arc description based on gradient position.
  ///
  /// The description varies by position band:
  /// - 0-10%:   "{from}, very early in arc toward {to}"
  /// - 11-25%:  "{from}, early in arc toward {to}"
  /// - 26-40%:  "Shifting from {from} toward {to}"
  /// - 41-49%:  "Nearing midpoint between {from} and {to}"
  /// - 50%:     "Midway between {from} and {to}"
  /// - 51-60%:  "Past midpoint, shifting toward {to}"
  /// - 61-75%:  "Well into the arc from {from} toward {to}"
  /// - 76-85%:  "Approaching {to} from {from}"
  /// - 86-90%:  "Nearing {to}"
  /// - 91-99%:  "Almost at {to}"
  /// - 100%:    "Arrived at {to}"
  private func describeArc(from: String, to: String, position: Float) -> String {
    let pct = Int((position * 100).rounded())

    switch pct {
    case 0...10:
      return "\(capitalizeFirst(from)), very early in arc toward \(to)"
    case 11...25:
      return "\(capitalizeFirst(from)), early in arc toward \(to)"
    case 26...35:
      return "Shifting from \(from) toward \(to)"
    case 36...40:
      return "Moving from \(from) toward \(to)"
    case 41...49:
      return "Nearing midpoint between \(from) and \(to)"
    case 50:
      return "Midway between \(from) and \(to)"
    case 51...60:
      return "Past midpoint, shifting toward \(to)"
    case 61...75:
      return "Well into the arc from \(from) toward \(to)"
    case 76...85:
      return "Approaching \(to) from \(from)"
    case 86...90:
      return "Nearing \(to)"
    case 91...99:
      return "Almost at \(to)"
    case 100...:
      return "Arrived at \(to)"
    default:
      return "Midway between \(from) and \(to)"
    }
  }

  // MARK: - Constraint Composition

  /// Compose the behavioral limits sentence from a Constraint.
  ///
  /// Format: `"{direction}. [Register: {register}.] [Ceiling: {ceiling}.]"`
  private func composeConstraint(_ constraint: Constraint) -> String {
    var parts: [String] = []

    parts.append("\(capitalizeFirst(constraint.direction)).")

    if let register = constraint.register, !register.isEmpty {
      parts.append("Register: \(register).")
    }
    if let ceiling = constraint.ceiling, !ceiling.isEmpty {
      parts.append("Ceiling: \(ceiling).")
    }

    return parts.joined(separator: " ")
  }

  // MARK: - Helpers

  /// Capitalize the first character of a string while preserving the rest.
  private func capitalizeFirst(_ string: String) -> String {
    guard let first = string.first else { return string }
    return first.uppercased() + string.dropFirst()
  }
}
