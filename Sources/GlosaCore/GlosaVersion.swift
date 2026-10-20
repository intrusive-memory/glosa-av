/// The current version of the glosa-av package.
public enum GlosaVersion {
  public static let version = "0.8.1-dev"

  /// The GLOSA notation version this package reads and writes (JSON block
  /// directives such as `[[ {"shot": {…}} ]]`). Independent of the package
  /// `version`.
  public static let notation = "2.0"
}
