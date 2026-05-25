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
  /// Descriptors are intentionally un-hydrated here: the file list is omitted
  /// and `Acervo.ensureComponentReady` hydrates from the published CDN
  /// manifest before downloading. This avoids the brittleness of a hard-coded
  /// file list (which would silently miss new shards as the upstream MLX
  /// publication evolves). See `SwiftAcervo/Docs/USAGE-library.md` §13.
  public static let descriptors: [ComponentDescriptor] = [
    ComponentDescriptor(
      id: defaultModelId,
      type: .languageModel,
      displayName: "Qwen2.5 3B Instruct (4-bit MLX)",
      repoId: defaultModelId,
      minimumMemoryBytes: 0,
      metadata: [:]
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
    do {
      try await Acervo.ensureComponentReady(modelId, progress: progress)
    } catch let error as AcervoError {
      switch error {
      case .offlineModeActive:
        throw ModelCatalogError.offlineModeRequiresLocalModel(modelId)
      case .integrityCheckFailed(let file, _, _):
        throw ModelCatalogError.integrityFailure(modelId: modelId, file: file)
      case .componentNotHydrated, .componentNotDownloaded:
        // These should never escape `ensureComponentReady`; if they do, the
        // bug is in SwiftAcervo, not GLOSA. Re-throw verbatim so the upstream
        // error surface remains intact for diagnosis.
        throw error
      default:
        throw error
      }
    }
  }
}

/// Errors raised by ``ModelCatalog``.
public enum ModelCatalogError: Error, CustomStringConvertible, LocalizedError {
  /// A model id was requested that is not declared in ``ModelCatalog/descriptors``.
  case unregisteredModel(String)

  /// `ACERVO_OFFLINE=1` is set and the requested model is not already on disk.
  case offlineModeRequiresLocalModel(String)

  /// A locally-cached file failed SHA-256 verification against the published
  /// manifest. Includes the model id and the specific file that mismatched so
  /// the user can take targeted recovery action (delete and redownload).
  case integrityFailure(modelId: String, file: String)

  public var description: String {
    switch self {
    case .unregisteredModel(let id):
      let known = ModelCatalog.descriptors.map(\.id).joined(separator: ", ")
      return """
        Model '\(id)' is not registered with the GLOSA model catalog.
        Add a ComponentDescriptor for it to ModelCatalog.descriptors before use.
        Registered models: \(known)
        """
    case .offlineModeRequiresLocalModel(let id):
      return """
        ACERVO_OFFLINE=1 is set, but '\(id)' is not present in the shared \
        models directory. Either unset ACERVO_OFFLINE and rerun to download, \
        or run once with network access to populate the cache.
        """
    case .integrityFailure(let modelId, let file):
      return """
        Local model file failed SHA-256 verification: '\(file)' (model: \(modelId)).
        The cached copy is corrupt or out-of-date relative to the published manifest.
        Recover by deleting the model directory and rerunning to redownload, \
        e.g.: rm -rf "~/Library/Group Containers/group.intrusive-memory.models/\(modelId)"
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
