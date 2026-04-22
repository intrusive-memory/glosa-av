import ArgumentParser
import Foundation
import GlosaAnnotation
import GlosaCore
import GlosaDirector
import SwiftCompartido

/// `glosa score <file> [-o <output>]`
///
/// Parses an un-annotated screenplay, runs LLM analysis via ``StageDirector``,
/// and writes the scored version to disk with GLOSA directives embedded.
///
/// ## Output path
///
/// When `--output` is omitted the output file is placed next to the input with
/// `_scored` appended to the basename, e.g. `my_script.fountain` →
/// `my_script_scored.fountain`.
///
/// ## Format selection
///
/// By default the output format mirrors the input file extension.  Use
/// `--format fountain` or `--format fdx` to override.
struct ScoreCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "score",
    abstract: "Annotate an un-scored screenplay with GLOSA directives via LLM analysis.",
    discussion: """
      Parses the input screenplay, calls the Stage Director LLM to produce
      scene-level GLOSA annotations, and writes the scored result to disk.
      """
  )

  // MARK: - Arguments & Options

  /// The screenplay file to score.
  @Argument(
    help: ArgumentHelp(
      "The screenplay file to score (Fountain or FDX).",
      valueName: "file"
    )
  )
  var file: String

  /// Optional output file path.
  @Option(
    name: [.customShort("o"), .long],
    help: ArgumentHelp(
      "Output file path. Defaults to <basename>_scored.<ext>.",
      valueName: "output"
    )
  )
  var output: String?

  /// Shared options (model, glossary, format).
  @OptionGroup var shared: SharedOptions

  // MARK: - Run

  mutating func run() async throws {
    // 1. Parse the input screenplay.
    let inputURL = URL(fileURLWithPath: file)
    let screenplay = try await GuionParsedElementCollection(file: file)

    // 2. Resolve the vocabulary glossary (if a custom path was supplied).
    let glossary: VocabularyGlossary?
    if let glossaryPath = shared.glossary {
      glossary = try VocabularyGlossary.load(from: URL(fileURLWithPath: glossaryPath))
    } else {
      glossary = try? VocabularyGlossary.loadDefault()
    }

    // 3. Run the Stage Director to annotate the screenplay.
    let director = StageDirector()
    let reporter = DownloadProgressReporter(
      label: "Downloading \(shared.model ?? StageDirector.defaultModel): ",
      quiet: shared.quiet
    )
    let annotated = try await director.annotate(
      screenplay,
      model: shared.model,
      glossary: glossary,
      progress: reporter.callback
    )
    reporter.finish()

    // 4. Determine output URL.
    let outputURL = resolveOutputURL(inputURL: inputURL, formatOverride: shared.format)

    // 5. Serialize the annotated screenplay.
    let serializer = GlosaSerializer()
    try serializer.write(annotated, to: outputURL)

    print("Scored screenplay written to: \(outputURL.path)")

    // Print any diagnostics.
    for diagnostic in annotated.diagnostics {
      let prefix = diagnostic.severity == .warning ? "Warning" : "Info"
      let location = diagnostic.line.map { " (line \($0))" } ?? ""
      fputs("\(prefix)\(location): \(diagnostic.message)\n", stderr)
    }
  }

  // MARK: - Helpers

  /// Resolve the output URL from the input URL, an optional explicit output path,
  /// and an optional format override.
  private func resolveOutputURL(inputURL: URL, formatOverride: String?) -> URL {
    if let output {
      return URL(fileURLWithPath: output)
    }

    // Default: same directory, <basename>_scored.<ext>
    let ext = resolvedExtension(for: inputURL, formatOverride: formatOverride)
    let baseName = inputURL.deletingPathExtension().lastPathComponent
    let directory = inputURL.deletingLastPathComponent()
    return
      directory
      .appendingPathComponent("\(baseName)_scored")
      .appendingPathExtension(ext)
  }

  /// Determine the output file extension from the input and any format override.
  private func resolvedExtension(for inputURL: URL, formatOverride: String?) -> String {
    if let override = formatOverride?.lowercased() {
      switch override {
      case "fountain": return "fountain"
      case "fdx": return "fdx"
      default: break
      }
    }
    let inputExt = inputURL.pathExtension.lowercased()
    return inputExt.isEmpty ? "fountain" : inputExt
  }
}
