import ArgumentParser
import Foundation
import GlosaAnnotation
import GlosaCore
import GlosaDirector
import SwiftCompartido

/// `glosa compile <file>`
///
/// Parses a screenplay that already contains GLOSA annotations, runs the
/// ``GlosaCompiler`` pipeline, and prints an instruct table to stdout.
///
/// ## Output Format
///
/// Each line of dialogue that has an active GLOSA instruct is printed as:
///
/// ```
/// [line]  CHARACTER  <instruct string>
/// ```
///
/// Lines with no active directives are listed with a `—` placeholder.
struct CompileCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compile",
        abstract: "Compile GLOSA annotations in a scored screenplay to instruct strings.",
        discussion: """
            Reads a screenplay that already contains GLOSA directives (produced by
            `glosa score`), runs the compiler pipeline, and prints a table mapping
            each dialogue line index to its character name and instruct string.
            """
    )

    // MARK: - Arguments & Options

    /// The screenplay file to compile (must already contain GLOSA annotations).
    @Argument(
        help: ArgumentHelp(
            "The scored screenplay file to compile (Fountain or FDX).",
            valueName: "file"
        )
    )
    var file: String

    /// Shared options (model, glossary, format — model and glossary unused here).
    @OptionGroup var shared: SharedOptions

    // MARK: - Run

    mutating func run() throws {
        // 1. Parse the input screenplay.
        let screenplay = try GuionParsedElementCollection(file: file)

        // 2. Extract GLOSA notes and dialogue lines from elements.
        let (notes, dialogueLines) = extractNotesAndDialogue(from: screenplay)

        // 3. Compile.
        let compiler = GlosaCompiler()
        let result = try compiler.compile(fountainNotes: notes, dialogueLines: dialogueLines)

        // 4. Print any diagnostics to stderr.
        for diagnostic in result.diagnostics {
            let prefix = diagnostic.severity == .warning ? "Warning" : "Info"
            let location = diagnostic.line.map { " (line \($0))" } ?? ""
            fputs("\(prefix)\(location): \(diagnostic.message)\n", stderr)
        }

        // 5. Print instruct table.
        if dialogueLines.isEmpty {
            print("No dialogue lines found in \(file).")
            return
        }

        // Column widths
        let lineWidth = max(5, "\(dialogueLines.count - 1)".count)
        let charWidth = dialogueLines.map(\.character.count).max().flatMap { max($0, 9) } ?? 9

        let header = padRight("LINE", lineWidth) + "  "
            + padRight("CHARACTER", charWidth) + "  INSTRUCT"
        print(header)
        print(String(repeating: "─", count: header.count))

        for (index, line) in dialogueLines.enumerated() {
            let instruct = result.instructs[index] ?? "—"
            let lineCol = padLeft("\(index)", lineWidth)
            let charCol = padRight(line.character, charWidth)
            print("\(lineCol)  \(charCol)  \(instruct)")
        }
    }
}

// MARK: - Shared Extraction Helpers

/// Extract GLOSA note strings and dialogue lines from a parsed screenplay.
///
/// This mirrors the extraction logic used by the test suite and the Preview command.
func extractNotesAndDialogue(
    from screenplay: GuionParsedElementCollection
) -> (notes: [String], dialogueLines: [(character: String, text: String)]) {
    var notes: [String] = []
    var dialogueLines: [(character: String, text: String)] = []
    var lastCharacterName = ""

    for element in screenplay.elements {
        switch element.elementType {
        case .comment:
            // Comment elements hold the text of `[[ ... ]]` notes (without the brackets).
            let trimmed = element.elementText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                notes.append(trimmed)
            }
        case .character:
            lastCharacterName = element.elementText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ^", with: "")
        case .dialogue:
            dialogueLines.append((character: lastCharacterName, text: element.elementText))
            // Append the dialogue text to notes so the parser can track dialogue
            // lines within intent ranges.
            notes.append(element.elementText)
        default:
            break
        }
    }

    return (notes, dialogueLines)
}

// MARK: - Formatting Helpers

/// Right-pad a string to a minimum width.
func padRight(_ s: String, _ width: Int) -> String {
    guard s.count < width else { return s }
    return s + String(repeating: " ", count: width - s.count)
}

/// Left-pad a string to a minimum width.
func padLeft(_ s: String, _ width: Int) -> String {
    guard s.count < width else { return s }
    return String(repeating: " ", count: width - s.count) + s
}
