import ArgumentParser
import Foundation
import GlosaAnnotation
import GlosaCore
import GlosaDirector
import SwiftCompartido

/// `glosa phrasing <file> [-o <output>]`
///
/// Runs only the PHRASING pass: finds long / irregularly phrased dialogue
/// lines and breaks them up with `<breath>` seams, then writes the result.
///
/// This is the standalone surface for iterating on PHRASING in isolation —
/// the orchestrator (`glosa score`) runs PHRASING as one step in a sequence.
struct PhrasingCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "phrasing",
    abstract: "Add <breath> phrasing seams to long / irregularly phrased dialogue lines.",
    discussion: """
      Runs the PHRASING pass over the screenplay: a heuristic pre-filter selects
      candidate dialogue lines, a find pass confirms which need seams, and a fix
      pass places <breath> markers. Only the breath facet is produced.
      """
  )

  @Argument(
    help: ArgumentHelp(
      "The screenplay file to phrase (Fountain or FDX).",
      valueName: "file"
    )
  )
  var file: String

  @Option(
    name: [.customShort("o"), .long],
    help: ArgumentHelp(
      "Output file path. Defaults to <basename>_phrased.<ext>.",
      valueName: "output"
    )
  )
  var output: String?

  @OptionGroup var shared: SharedOptions

  mutating func run() async throws {
    let inputURL = URL(fileURLWithPath: file)
    let screenplay = try await GuionParsedElementCollection(file: file)

    let generator = BrujaFacetGenerator()
    let model = shared.model ?? StageDirector.defaultModel

    let pass = PhrasingPass()
    let annotated = try await pass.annotateScreenplay(
      screenplay,
      using: generator,
      model: model
    )

    let outputURL = resolveOutputURL(inputURL: inputURL, formatOverride: shared.format)
    let serializer = GlosaSerializer()
    try serializer.write(annotated, to: outputURL)

    print("Phrased screenplay written to: \(outputURL.path)")

    for diagnostic in annotated.diagnostics {
      let prefix = diagnostic.severity == .warning ? "Warning" : "Info"
      let location = diagnostic.line.map { " (line \($0))" } ?? ""
      fputs("\(prefix)\(location): \(diagnostic.message)\n", stderr)
    }
  }

  // MARK: - Helpers

  private func resolveOutputURL(inputURL: URL, formatOverride: String?) -> URL {
    if let output {
      return URL(fileURLWithPath: output)
    }
    let ext = resolvedExtension(for: inputURL, formatOverride: formatOverride)
    let baseName = inputURL.deletingPathExtension().lastPathComponent
    let directory = inputURL.deletingLastPathComponent()
    return
      directory
      .appendingPathComponent("\(baseName)_phrased")
      .appendingPathExtension(ext)
  }

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
