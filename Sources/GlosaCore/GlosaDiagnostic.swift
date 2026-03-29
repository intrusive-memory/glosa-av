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

  /// The severity of this diagnostic.
  public var severity: Severity

  /// A human-readable description of the issue.
  public var message: String

  /// The source line number where the issue was detected, if applicable.
  public var line: Int?

  public init(severity: Severity, message: String, line: Int? = nil) {
    self.severity = severity
    self.message = message
    self.line = line
  }
}
