import Foundation

/// Focused instructions for the PHRASING fix pass.
///
/// This is the breath half of the legacy monolithic system prompt
/// (`Prompts.breathPlacementSection`), reduced to the placement rules and
/// prohibitions. Selecting *which* lines to run is a deterministic word-count
/// gate (`PhrasingPass.isCandidate`), not a model call — so there is no longer a
/// separate "find" instruction. The slice is small enough to fit a ~4k on-device
/// window on its own.
enum BreathPassPrompts {

  /// System instructions for the fix pass — rewrite one line with markers.
  ///
  /// The model edits text (its strength) instead of emitting character offsets
  /// (its weakness). We validate the rewrite word-for-word and compute the
  /// offsets ourselves, so a miscount or a paraphrase cannot corrupt the line.
  static let fixInstructions = """
    You insert <breath> phrasing seams into ONE line of dialogue. A <breath> is a
    SILENT seam marking where the line may split into separate spoken chunks.

    Return the EXACT same line, word for word, with the marker <breath> inserted
    at each seam. Do NOT change, add, remove, reorder, or rephrase any word or
    punctuation — only insert <breath> markers.

    Place <breath> (highest priority first):
    1. After a semicolon.
    2. Before a coordinating conjunction (and / but / or / so / yet) that joins
       two clauses — after the comma if there is one.
    3. Between top-level list items, after the separating comma. Do NOT split
       inside a single list item even if it contains commas or "and".
    4. Before a long subordinate clause (which / that / because / although /
       when / while) when the clause before it is at least 60 characters.

    Do NOT insert a <breath>:
    - Between an adjective and the noun it modifies.
    - Between a verb and a short object.
    - Inside a quoted string.
    - At the very start or end of the line.

    If the line needs no seam, return it unchanged. Output ONLY the line text
    with any markers — no quotes, no JSON, no commentary.
    """

  /// Build the fix user prompt for one candidate line.
  static func fixUserPrompt(text: String) -> String {
    "Line:\n\(text)"
  }
}
