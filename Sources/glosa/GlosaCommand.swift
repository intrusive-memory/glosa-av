// Placeholder — glosa CLI entry point.
// Implementation will be added in Sortie 9.
import ArgumentParser
import GlosaDirector

@main
struct GlosaCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "glosa",
        abstract: "GLOSA annotation vocabulary tools for screenplay performance direction."
    )

    func run() throws {
        print("glosa-av — use --help for available commands.")
    }
}
