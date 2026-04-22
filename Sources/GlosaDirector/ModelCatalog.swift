import Foundation
import SwiftAcervo

/// Central catalogue of LLM components GLOSA knows how to download.
///
/// All models that the Stage Director may use must be declared here and
/// registered with `SwiftAcervo`'s component registry. Unregistered model ids
/// passed via `--model` are rejected at runtime so that every model GLOSA can
/// download has a known repo, file list, and (eventually) checksum set.
public enum ModelCatalog {

  /// The default LLM model id used by ``StageDirector``.
  ///
  /// Qwen2.5-3B-Instruct (4-bit MLX) was chosen over larger code-tuned models
  /// because GLOSA annotation is a structured-extraction task on short scenes:
  /// the 32K context window comfortably fits the system prompt + glossary +
  /// few-shot examples + scene text, and the Qwen2.5 instruct family handles
  /// JSON-mode output tightly. Download footprint is ~1.9 GB.
  public static let defaultModelId = "mlx-community/Qwen2.5-3B-Instruct-4bit"

  /// All component descriptors GLOSA knows about.
  ///
  /// File sizes and SHA-256 checksums are intentionally omitted at this stage;
  /// they will be populated once the CDN upload pipeline (see
  /// SwiftAcervo's ACERVO_CDN_UPLOAD_PATTERN) is wired up and the canonical
  /// manifest is published.
  public static let descriptors: [ComponentDescriptor] = [
    ComponentDescriptor(
      id: defaultModelId,
      type: .languageModel,
      displayName: "Qwen2.5 3B Instruct (4-bit MLX)",
      repoId: defaultModelId,
      files: [
        ComponentFile(relativePath: "config.json"),
        ComponentFile(relativePath: "tokenizer.json"),
        ComponentFile(relativePath: "tokenizer_config.json"),
        ComponentFile(relativePath: "model.safetensors"),
      ],
      estimatedSizeBytes: 0,
      minimumMemoryBytes: 0
    )
  ]

  /// Register every catalogue descriptor with `SwiftAcervo`.
  ///
  /// Idempotent — re-registering the same id updates the existing entry.
  /// Safe to call from multiple call sites.
  public static func registerAll() {
    Acervo.register(descriptors)
  }

  /// Ensure a registered model is downloaded and ready for inference.
  ///
  /// - Parameters:
  ///   - modelId: The model id to ensure. Must be registered in ``descriptors``.
  ///   - progress: Optional callback invoked with download progress.
  /// - Throws: ``ModelCatalogError/unregisteredModel(_:)`` if the id was not
  ///   declared in ``descriptors``; otherwise any error thrown by SwiftAcervo
  ///   while verifying or downloading the component.
  public static func ensureModelReady(
    _ modelId: String,
    progress: (@Sendable (AcervoDownloadProgress) -> Void)? = nil
  ) async throws {
    registerAll()
    guard Acervo.component(modelId) != nil else {
      throw ModelCatalogError.unregisteredModel(modelId)
    }
    try await Acervo.ensureComponentReady(modelId, progress: progress)
  }
}

/// Errors raised by ``ModelCatalog``.
public enum ModelCatalogError: Error, CustomStringConvertible, LocalizedError {
  /// A model id was requested that is not declared in ``ModelCatalog/descriptors``.
  case unregisteredModel(String)

  public var description: String {
    switch self {
    case .unregisteredModel(let id):
      let known = ModelCatalog.descriptors.map(\.id).joined(separator: ", ")
      return """
        Model '\(id)' is not registered with the GLOSA model catalog.
        Add a ComponentDescriptor for it to ModelCatalog.descriptors before use.
        Registered models: \(known)
        """
    }
  }

  public var errorDescription: String? { description }
}

// MARK: - Availability Checker Abstraction

/// Abstraction for the "ensure this model is on disk" step.
///
/// The default implementation calls ``ModelCatalog/ensureModelReady(_:progress:)``.
/// Tests inject ``SkipModelCheck`` to bypass downloads when using mock providers.
public protocol ModelAvailabilityChecker: Sendable {
  func ensureModelReady(
    _ modelId: String,
    progress: (@Sendable (AcervoDownloadProgress) -> Void)?
  ) async throws
}

/// Production checker that delegates to ``ModelCatalog``.
public struct AcervoModelChecker: ModelAvailabilityChecker {
  public init() {}

  public func ensureModelReady(
    _ modelId: String,
    progress: (@Sendable (AcervoDownloadProgress) -> Void)?
  ) async throws {
    try await ModelCatalog.ensureModelReady(modelId, progress: progress)
  }
}

/// Test checker that performs no I/O — assumes the model is already available.
public struct SkipModelCheck: ModelAvailabilityChecker {
  public init() {}

  public func ensureModelReady(
    _ modelId: String,
    progress: (@Sendable (AcervoDownloadProgress) -> Void)?
  ) async throws {}
}
