/// The result of compiling GLOSA annotations into per-line instruct strings.
///
/// Produced by `GlosaCompiler.compile()`, this struct contains:
/// - Per-line instruct strings keyed by dialogue line index.
///   Lines with no active directives have no entry (fallback to parenthetical).
/// - Diagnostics from validation and resolution.
/// - Provenance records tracing each instruct back to its source directives.
public struct CompilationResult: Sendable {

    /// Per-line instruct strings, keyed by dialogue line index.
    ///
    /// Lines with no active directives have no entry — a missing key
    /// means neutral delivery (fall back to parenthetical if present).
    public let instructs: [Int: String]

    /// Diagnostics produced during validation and compilation.
    ///
    /// Includes warnings about unclosed tags, missing attributes,
    /// structural issues, and informational messages.
    public let diagnostics: [GlosaDiagnostic]

    /// Provenance records for every line that received an instruct string.
    ///
    /// Each record traces the instruct back to its source SceneContext,
    /// Intent, and Constraint directives, enabling auditing and debugging.
    public let provenance: [InstructProvenance]

    public init(
        instructs: [Int: String] = [:],
        diagnostics: [GlosaDiagnostic] = [],
        provenance: [InstructProvenance] = []
    ) {
        self.instructs = instructs
        self.diagnostics = diagnostics
        self.provenance = provenance
    }
}
