import ArgumentParser
import Foundation
import GlosaAnnotation
import GlosaCore
import GlosaDirector
import SwiftCompartido

/// `glosa compare <file>`
///
/// Compiles a screenplay twice — once via the template/compiler path and once
/// via the LLM path — and diffs the instruct output line by line.
///
/// ## Output Format
///
/// ```
/// LINE  CHARACTER    MATCH  TEMPLATE INSTRUCT                    LLM INSTRUCT
/// ──────────────────────────────────────────────────────────────────────────────
///    0  BERNARD      match  Late night in the study…             Late night in…
///    1  KILLIAN      differ Tense office atmosphere…             Steam room morning…
/// ```
///
/// Lines that have no instruct in either path are omitted unless both paths
/// agree (both nil → match, one nil → differ).
struct CompareCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "compare",
    abstract: "Compare template-compiled vs LLM-annotated instruct strings line by line.",
    discussion: """
      Compiles a scored screenplay twice: once using the GLOSA template compiler
      (fast, deterministic) and once using StageDirector's LLM annotation path
      (slower, model-dependent). Prints a diff table showing where the two paths
      agree or diverge. Useful for provenance review and quality auditing.
      """
  )

  // MARK: - Arguments & Options

  /// The screenplay file to compare (must already contain GLOSA annotations for the
  /// template path; the LLM path treats the screenplay as unannotated).
  @Argument(
    help: ArgumentHelp(
      "The scored screenplay file to compare (Fountain or FDX).",
      valueName: "file"
    )
  )
  var file: String

  /// Shared options (model, glossary, format).
  @OptionGroup var shared: SharedOptions

  // MARK: - Run

  mutating func run() async throws {
    // 1. Parse the input screenplay.
    let screenplay = try await GuionParsedElementCollection(file: file)

    // 2. Template path: extract notes + dialogue, run GlosaCompiler.
    let (notes, dialogueLines) = extractNotesAndDialogue(from: screenplay)
    let compiler = GlosaCompiler()
    let templateResult = try compiler.compile(fountainNotes: notes, dialogueLines: dialogueLines)

    // Print template-path diagnostics to stderr.
    for diagnostic in templateResult.diagnostics {
      let prefix = diagnostic.severity == .warning ? "Warning" : "Info"
      let location = diagnostic.line.map { " (line \($0))" } ?? ""
      fputs("Template\(prefix)\(location): \(diagnostic.message)\n", stderr)
    }

    // 3. LLM path: run StageDirector.annotate().
    let glossary: VocabularyGlossary? = try {
      guard let path = shared.glossary else { return nil }
      return try VocabularyGlossary.load(from: URL(fileURLWithPath: path))
    }()

    let director = StageDirector()
    let reporter = DownloadProgressReporter(
      label: "Downloading \(shared.model ?? StageDirector.defaultModel): ",
      quiet: shared.quiet
    )
    let llmAnnotated = try await director.annotate(
      screenplay,
      model: shared.model,
      glossary: glossary,
      progress: reporter.callback
    )
    reporter.finish()

    // Build LLM instruct lookup: dialogue line index → instruct string.
    // We walk annotated elements, counting dialogue elements in order.
    var llmInstructs: [Int: String] = [:]
    var llmDialogueIndex = 0
    for annotated in llmAnnotated.annotatedElements {
      if annotated.element.elementType == .dialogue {
        if let instruct = annotated.instruct {
          llmInstructs[llmDialogueIndex] = instruct
        }
        llmDialogueIndex += 1
      }
    }

    // 4. Print the diff table.
    if dialogueLines.isEmpty {
      print("No dialogue lines found in \(file).")
      return
    }

    printDiffTable(
      dialogueLines: dialogueLines,
      templateInstructs: templateResult.instructs,
      llmInstructs: llmInstructs
    )

    // 5. Summary footer.
    let matchCount = dialogueLines.indices.filter { idx in
      templateResult.instructs[idx] == llmInstructs[idx]
    }.count
    let differCount = dialogueLines.count - matchCount
    print("")
    print("Total: \(dialogueLines.count) lines — \(matchCount) match, \(differCount) differ")
  }
}

// MARK: - Diff Table Printing

/// Print the comparison table to stdout.
func printDiffTable(
  dialogueLines: [(character: String, text: String)],
  templateInstructs: [Int: String],
  llmInstructs: [Int: String]
) {
  // Column widths.
  let lineWidth = max(4, "\(dialogueLines.count - 1)".count)
  let charWidth = max(9, dialogueLines.map(\.character.count).max() ?? 9)
  let matchWidth = 6  // "match " or "differ"

  // Truncate instruct strings to a reasonable display width.
  let instructDisplayWidth = 40

  let header =
    padLeft("LINE", lineWidth) + "  "
    + padRight("CHARACTER", charWidth) + "  "
    + padRight("MATCH", matchWidth) + "  "
    + padRight("TEMPLATE INSTRUCT", instructDisplayWidth) + "  "
    + "LLM INSTRUCT"
  print(header)
  print(String(repeating: "─", count: header.count + instructDisplayWidth))

  for (index, line) in dialogueLines.enumerated() {
    let templateInstruct = templateInstructs[index]
    let llmInstruct = llmInstructs[index]

    let matchLabel = (templateInstruct == llmInstruct) ? "match" : "differ"

    let templateDisplay = truncate(templateInstruct ?? "—", to: instructDisplayWidth)
    let llmDisplay = truncate(llmInstruct ?? "—", to: instructDisplayWidth)

    let lineCol = padLeft("\(index)", lineWidth)
    let charCol = padRight(line.character, charWidth)
    let matchCol = padRight(matchLabel, matchWidth)
    let templateCol = padRight(templateDisplay, instructDisplayWidth)

    print("\(lineCol)  \(charCol)  \(matchCol)  \(templateCol)  \(llmDisplay)")
  }
}

/// Truncate a string with an ellipsis if it exceeds the given width.
func truncate(_ s: String, to width: Int) -> String {
  guard s.count > width else { return s }
  return String(s.prefix(width - 1)) + "…"
}
