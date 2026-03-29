import ArgumentParser
import Foundation
import GlosaDirector

/// `glosa glossary list|add|remove`
///
/// Manages the GLOSA vocabulary glossary. Supports listing current contents,
/// adding new terms to a category, and removing existing terms.
///
/// ## Usage
///
/// ```
/// glosa glossary list [--glossary <path>]
/// glosa glossary add <term> --category emotions|directions|paceTerms|registerTerms|ceilingTerms [--glossary <path>]
/// glosa glossary remove <term> [--glossary <path>]
/// ```
///
/// When `--glossary` is omitted, the default bundled glossary is used as the
/// read source. Mutations (`add`, `remove`) require `--glossary` to specify
/// the writable output path; if omitted, they print the modified glossary to
/// stdout instead of persisting it.
struct GlossaryCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "glossary",
    abstract: "Manage the GLOSA vocabulary glossary.",
    discussion: """
      List, add, or remove terms from the vocabulary glossary used to guide
      the Stage Director LLM toward effective TTS vocabulary.
      """,
    subcommands: [
      ListCommand.self,
      AddCommand.self,
      RemoveCommand.self,
    ],
    defaultSubcommand: ListCommand.self
  )
}

// MARK: - List

/// `glosa glossary list`
///
/// Prints all glossary terms to stdout, grouped by category.
struct ListCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "Print the current glossary contents to stdout."
  )

  /// Optional path to a custom glossary JSON file.
  @Option(
    name: .long,
    help: ArgumentHelp(
      "Path to a custom glossary JSON file.",
      valueName: "path"
    )
  )
  var glossary: String?

  mutating func run() async throws {
    let g = try loadGlossary(from: glossary)
    printGlossary(g)
  }
}

// MARK: - Add

/// `glosa glossary add <term> --category <category>`
///
/// Adds a term to the specified category. Duplicate terms are silently ignored.
struct AddCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "add",
    abstract: "Add a term to the glossary."
  )

  /// The term to add.
  @Argument(
    help: ArgumentHelp(
      "The term to add to the glossary.",
      valueName: "term"
    )
  )
  var term: String

  /// The category to add the term to.
  @Option(
    name: .long,
    help: ArgumentHelp(
      "The category to add the term to: emotions, directions, paceTerms, registerTerms, ceilingTerms.",
      valueName: "category"
    )
  )
  var category: String

  /// Optional path to a custom glossary JSON file. When supplied, the
  /// modified glossary is saved back to this path.
  @Option(
    name: .long,
    help: ArgumentHelp(
      "Path to a custom glossary JSON file to read from and write to.",
      valueName: "path"
    )
  )
  var glossaryPath: String?

  mutating func run() async throws {
    guard let cat = VocabularyGlossary.Category(rawValue: category) else {
      let valid = VocabularyGlossary.Category.allCases.map(\.rawValue).joined(separator: ", ")
      throw ValidationError("Unknown category '\(category)'. Valid categories: \(valid)")
    }

    var g = try loadGlossary(from: glossaryPath)
    g.add(term: term, category: cat)

    if let path = glossaryPath {
      let url = URL(fileURLWithPath: path)
      try g.save(to: url)
      print("Term '\(term)' added to \(category) and saved to \(path).")
    } else {
      // No path provided — print the modified glossary to stdout.
      printGlossary(g)
    }
  }
}

// MARK: - Remove

/// `glosa glossary remove <term>`
///
/// Removes a term from the glossary (searched across all categories).
struct RemoveCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remove",
    abstract: "Remove a term from the glossary."
  )

  /// The term to remove.
  @Argument(
    help: ArgumentHelp(
      "The term to remove from the glossary.",
      valueName: "term"
    )
  )
  var term: String

  /// Optional path to a custom glossary JSON file. When supplied, the
  /// modified glossary is saved back to this path.
  @Option(
    name: .long,
    help: ArgumentHelp(
      "Path to a custom glossary JSON file to read from and write to.",
      valueName: "path"
    )
  )
  var glossaryPath: String?

  mutating func run() async throws {
    var g = try loadGlossary(from: glossaryPath)
    g.remove(term: term)

    if let path = glossaryPath {
      let url = URL(fileURLWithPath: path)
      try g.save(to: url)
      print("Term '\(term)' removed and glossary saved to \(path).")
    } else {
      // No path provided — print the modified glossary to stdout.
      printGlossary(g)
    }
  }
}

// MARK: - Shared helpers

/// Load the glossary from a file path, or fall back to the bundled default.
private func loadGlossary(from path: String?) throws -> VocabularyGlossary {
  if let path {
    return try VocabularyGlossary.load(from: URL(fileURLWithPath: path))
  }
  return try VocabularyGlossary.loadDefault()
}

/// Print all glossary contents to stdout, grouped by category.
private func printGlossary(_ glossary: VocabularyGlossary) {
  print("=== GLOSA Vocabulary Glossary ===\n")

  print("Emotions (\(glossary.emotions.count)):")
  for term in glossary.emotions { print("  \(term)") }

  print("\nDirections (\(glossary.directions.count)):")
  for term in glossary.directions { print("  \(term)") }

  print("\nPace Terms (\(glossary.paceTerms.count)):")
  for term in glossary.paceTerms { print("  \(term)") }

  print("\nRegister Terms (\(glossary.registerTerms.count)):")
  for term in glossary.registerTerms { print("  \(term)") }

  print("\nCeiling Terms (\(glossary.ceilingTerms.count)):")
  for term in glossary.ceilingTerms { print("  \(term)") }
}
