import ArgumentParser
import Foundation
import GlosaAnnotation
import GlosaCore
import GlosaDirector
import SwiftCompartido

/// `glosa preview <file>`
///
/// Parses and compiles a scored screenplay, then prints a detailed human-readable
/// breakdown of the resolved directives for each dialogue line.
///
/// ## Output Format
///
/// For each dialogue line with active GLOSA directives:
///
/// ```
/// Line 3  ALEX
///   Scene:      INT. STUDY – NIGHT | ambience: quiet hum of electronics
///   Intent:     curious → frustrated (arc: 0.50, pace: moderate)
///   Constraint: Thinking aloud, halting delivery | ceiling: moderate
///   Instruct:   Late night in the study, quiet hum of electronics. ...
/// ```
///
/// Lines in neutral delivery gaps are listed with a brief `[neutral]` marker.
struct PreviewCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "preview",
    abstract: "Preview resolved GLOSA directives per dialogue line (debugging view).",
    discussion: """
      Parses and compiles a scored screenplay, then prints the active SceneContext,
      Intent (with arc position), Constraint, and composed instruct for every
      dialogue line. Useful for reviewing annotations before audio generation.
      """
  )

  // MARK: - Arguments & Options

  /// The scored screenplay file to preview.
  @Argument(
    help: ArgumentHelp(
      "The scored screenplay file to preview (Fountain or FDX).",
      valueName: "file"
    )
  )
  var file: String

  /// Shared options (model, glossary, format — unused in preview, present for API uniformity).
  @OptionGroup var shared: SharedOptions

  // MARK: - Run

  mutating func run() throws {
    // 1. Parse the screenplay.
    let screenplay = try GuionParsedElementCollection(file: file)

    // 2. Extract notes and dialogue lines.
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

    // 5. Build a provenance lookup by line index.
    let provenanceByIndex: [Int: InstructProvenance] = Dictionary(
      result.provenance.map { ($0.lineIndex, $0) },
      uniquingKeysWith: { first, _ in first }
    )

    // 6. Print preview for each dialogue line.
    if dialogueLines.isEmpty {
      print("No dialogue lines found in \(file).")
      return
    }

    print("GLOSA Preview: \(file)")
    print(String(repeating: "═", count: 60))

    for (index, line) in dialogueLines.enumerated() {
      print("")
      print("Line \(index)  \(line.character)")

      guard let prov = provenanceByIndex[index] else {
        print("  [neutral — no active GLOSA directives]")
        continue
      }

      // Scene context
      if let ctx = prov.sceneContext {
        var sceneDesc = "\(ctx.location) — \(ctx.time)"
        if let ambience = ctx.ambience, !ambience.isEmpty {
          sceneDesc += " | ambience: \(ambience)"
        }
        print("  Scene:      \(sceneDesc)")
      } else {
        print("  Scene:      [none]")
      }

      // Intent
      if let intentInfo = prov.intent {
        let intent = intentInfo.intent
        let arcPct = Int((intentInfo.arcPosition * 100).rounded())
        var intentDesc = "\(intent.from) → \(intent.to) (arc: \(arcPct)%"
        if let pace = intent.pace, !pace.isEmpty {
          intentDesc += ", pace: \(pace)"
        }
        if let spacing = intent.spacing, !spacing.isEmpty {
          intentDesc += ", spacing: \(spacing)"
        }
        intentDesc += ")"
        print("  Intent:     \(intentDesc)")
      } else {
        print("  Intent:     [neutral]")
      }

      // Constraint
      if let constraint = prov.constraint {
        var constraintDesc = "\(constraint.direction)"
        if let register = constraint.register, !register.isEmpty {
          constraintDesc += " | register: \(register)"
        }
        if let ceiling = constraint.ceiling, !ceiling.isEmpty {
          constraintDesc += " | ceiling: \(ceiling)"
        }
        print("  Constraint: \(constraintDesc)")
      } else {
        print("  Constraint: [none]")
      }

      // Composed instruct
      print("  Instruct:   \(prov.composedInstruct)")
    }

    print("")
    print(String(repeating: "═", count: 60))
    print("Total dialogue lines: \(dialogueLines.count)")
    print("Lines with instructs: \(result.instructs.count)")
  }
}
