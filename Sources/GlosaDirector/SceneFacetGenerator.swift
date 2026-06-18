import Foundation
import SwiftBruja

/// A backend-agnostic primitive for one LLM round-trip.
///
/// The lowest-level requirement is `generateText` — raw text in, raw text out —
/// because small on-device models are unreliable at strict structured decoding,
/// and the PHRASING passes parse their flat-integer answers leniently from the
/// text. A convenience `generate(_:…)` decodes JSON for callers that want a
/// typed result; the Foundation Models backend will override it to use guided
/// `@Generable` decoding.
public protocol SceneFacetGenerator: Sendable {

  /// Run one generation and return the model's raw text.
  ///
  /// - Parameters:
  ///   - instructions: System-level instructions for *this pass only*.
  ///   - userPrompt: The scene/line payload to annotate.
  ///   - maxTokens: Output cap. Keep small for short answers to bound runaway
  ///     generation; `nil` uses the backend default.
  ///   - model: Backend model identifier.
  func generateText(
    instructions: String,
    userPrompt: String,
    maxTokens: Int?,
    model: String
  ) async throws -> String
}

extension SceneFacetGenerator {

  /// Convenience: generate then JSON-decode into a typed schema. Strict — use
  /// only where the model is trusted to emit clean JSON (or a guided backend
  /// enforces it).
  public func generate<Output: Codable & Sendable>(
    _ outputType: Output.Type,
    instructions: String,
    userPrompt: String,
    model: String
  ) async throws -> Output {
    let text = try await generateText(
      instructions: instructions,
      userPrompt: userPrompt,
      maxTokens: nil,
      model: model
    )
    return try JSONDecoder().decode(Output.self, from: Data(text.utf8))
  }
}

/// `SceneFacetGenerator` backed by SwiftBruja on-device inference.
///
/// The default backend while the pass architecture is proven. The Foundation
/// Models backend (`FoundationModelsFacetGenerator`) will be a drop-in
/// replacement implementing the same protocol.
public struct BrujaFacetGenerator: SceneFacetGenerator {

  /// Sampling temperature. Defaults to `0.3` to preserve the Stage Director's
  /// historically low-temperature behavior.
  public let temperature: Float

  public init(temperature: Float = 0.3) {
    self.temperature = temperature
  }

  public func generateText(
    instructions: String,
    userPrompt: String,
    maxTokens: Int?,
    model: String
  ) async throws -> String {
    try await Bruja.query(
      userPrompt,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      system: instructions
    )
  }
}

/// A test double that returns canned text and counts calls.
///
/// The responder is handed the pass instructions and the user prompt and must
/// return the model's raw text. The `callCount` spy supports asserting that,
/// e.g., a scene with no breath candidates makes **zero** model calls.
public final class MockFacetGenerator: SceneFacetGenerator, @unchecked Sendable {

  /// Produces the raw text for a generation.
  public typealias Responder =
    @Sendable (
      _ instructions: String,
      _ userPrompt: String
    ) throws -> String

  private let responder: Responder
  private let lock = NSLock()
  private var _callCount = 0

  /// Number of `generateText` calls made so far.
  public var callCount: Int {
    withLock { _callCount }
  }

  public init(responder: @escaping Responder) {
    self.responder = responder
  }

  public func generateText(
    instructions: String,
    userPrompt: String,
    maxTokens: Int?,
    model: String
  ) async throws -> String {
    withLock { _callCount += 1 }
    return try responder(instructions, userPrompt)
  }

  /// Scoped lock helper — keeps `NSLock.unlock()` out of the async context,
  /// where it is unavailable.
  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
