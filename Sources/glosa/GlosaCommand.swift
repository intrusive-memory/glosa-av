import ArgumentParser
import GlosaDirector

/// Shared options available to all glosa subcommands.
///
/// Include this group in each subcommand with `@OptionGroup var shared: SharedOptions`.
struct SharedOptions: ParsableArguments {

  /// Override the LLM model used during scoring.
  @Option(
    name: .long,
    help: ArgumentHelp(
      "LLM model identifier to use for annotation inference.",
      valueName: "id"
    )
  )
  var model: String?

  /// Path to a custom vocabulary glossary JSON file.
  @Option(
    name: .long,
    help: ArgumentHelp(
      "Path to a custom vocabulary glossary JSON file.",
      valueName: "path"
    )
  )
  var glossary: String?

  /// Output format override (fountain or fdx).
  @Option(
    name: .long,
    help: ArgumentHelp(
      "Output format override: fountain or fdx.",
      valueName: "fountain|fdx"
    )
  )
  var format: String?
}

/// Root command for the glosa CLI.
///
/// Provides subcommands for working with GLOSA-annotated screenplays:
///
/// - `score`:    Analyze an un-annotated screenplay via LLM and write the scored version.
/// - `compile`:  Compile an already-scored screenplay and print instruct strings per line.
/// - `preview`:  Debug view — print resolved directives and composed instruct per line.
/// - `compare`:  Diff template-compiled vs LLM-annotated instruct strings line by line.
/// - `glossary`: Manage the GLOSA vocabulary glossary (list, add, remove).
@main
struct GlosaCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "glosa",
    abstract: "GLOSA annotation vocabulary tools for screenplay performance direction.",
    discussion: """
      glosa annotates screenplays with GLOSA performance directives and compiles them
      into natural-language instruct strings for TTS (text-to-speech) systems.
      """,
    subcommands: [
      ScoreCommand.self,
      CompileCommand.self,
      PreviewCommand.self,
      CompareCommand.self,
      GlossaryCommand.self,
    ]
  )
}
