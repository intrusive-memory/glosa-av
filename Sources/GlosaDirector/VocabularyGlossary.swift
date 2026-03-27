import Foundation

/// A curated, evolving collection of direction terms that produce good TTS results.
///
/// The glossary is fed to the LLM as part of the Stage Director's system prompt,
/// biasing it toward vocabulary the TTS model responds to well. It ships with a
/// default set loaded from a bundled `glossary.json` resource and can be overridden
/// per-project via a file path.
///
/// ## Fixed vs. Open Vocabulary
///
/// - ``paceTerms``, ``registerTerms``, and ``ceilingTerms`` are **fixed** vocabularies
///   defined by the GLOSA spec.
/// - ``emotions`` and ``directions`` are **open** vocabularies that evolve through the
///   feedback loop as effective terms are discovered.
///
/// ## Usage
///
/// ```swift
/// // Load default glossary from bundle
/// let glossary = try VocabularyGlossary.loadDefault()
///
/// // Load from a project-specific override file
/// let custom = try VocabularyGlossary.load(from: URL(fileURLWithPath: "/path/to/glossary.json"))
/// ```
public struct VocabularyGlossary: Codable, Sendable, Equatable {

    /// The categories of vocabulary terms in the glossary.
    ///
    /// - `emotions`: Open vocabulary of emotion terms.
    /// - `directions`: Open vocabulary of direction phrases.
    /// - `paceTerms`: Fixed vocabulary: slow, moderate, fast, accelerating, decelerating.
    /// - `registerTerms`: Fixed vocabulary: low, mid, high.
    /// - `ceilingTerms`: Fixed vocabulary: subdued, moderate, intense, explosive.
    public enum Category: String, Codable, Sendable, CaseIterable {
        case emotions
        case directions
        case paceTerms
        case registerTerms
        case ceilingTerms
    }

    /// Emotion terms known to produce good TTS results.
    ///
    /// Open vocabulary. Examples: "guarded", "vulnerable", "conspiratorial calm",
    /// "grim resolve", "cautious optimism".
    public var emotions: [String]

    /// Direction phrases known to produce good TTS results.
    ///
    /// Open vocabulary. Examples: "bracing, matter-of-fact to keep distance",
    /// "dam breaking, voice thinning", "thinking aloud, halting delivery".
    public var directions: [String]

    /// Pace terms. Fixed vocabulary: slow, moderate, fast, accelerating, decelerating.
    public var paceTerms: [String]

    /// Register terms. Fixed vocabulary: low, mid, high.
    public var registerTerms: [String]

    /// Ceiling terms. Fixed vocabulary: subdued, moderate, intense, explosive.
    public var ceilingTerms: [String]

    public init(
        emotions: [String],
        directions: [String],
        paceTerms: [String],
        registerTerms: [String],
        ceilingTerms: [String]
    ) {
        self.emotions = emotions
        self.directions = directions
        self.paceTerms = paceTerms
        self.registerTerms = registerTerms
        self.ceilingTerms = ceilingTerms
    }

    // MARK: - Loading

    /// Loads the default glossary from the bundled `glossary.json` resource.
    ///
    /// - Throws: If the resource cannot be found or decoded.
    /// - Returns: A `VocabularyGlossary` populated from the bundle.
    public static func loadDefault() throws -> VocabularyGlossary {
        guard let url = Bundle.module.url(forResource: "glossary", withExtension: "json") else {
            throw VocabularyGlossaryError.resourceNotFound("glossary.json")
        }
        return try load(from: url)
    }

    /// Loads a glossary from a JSON file at the given URL.
    ///
    /// Use this to override the default glossary with a project-specific one.
    ///
    /// - Parameter url: The file URL of the JSON glossary.
    /// - Throws: If the file cannot be read or decoded.
    /// - Returns: A `VocabularyGlossary` populated from the file.
    public static func load(from url: URL) throws -> VocabularyGlossary {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(VocabularyGlossary.self, from: data)
    }

    // MARK: - Mutation

    /// Adds a term to the specified category.
    ///
    /// If the term already exists in the category, this is a no-op (no duplicates allowed).
    ///
    /// - Parameters:
    ///   - term: The term to add.
    ///   - category: The category to add the term to.
    public mutating func add(term: String, category: Category) {
        switch category {
        case .emotions:
            guard !emotions.contains(term) else { return }
            emotions.append(term)
        case .directions:
            guard !directions.contains(term) else { return }
            directions.append(term)
        case .paceTerms:
            guard !paceTerms.contains(term) else { return }
            paceTerms.append(term)
        case .registerTerms:
            guard !registerTerms.contains(term) else { return }
            registerTerms.append(term)
        case .ceilingTerms:
            guard !ceilingTerms.contains(term) else { return }
            ceilingTerms.append(term)
        }
    }

    /// Removes a term from the glossary, searching all categories.
    ///
    /// If the term does not exist in any category, this is a no-op.
    ///
    /// - Parameter term: The term to remove.
    public mutating func remove(term: String) {
        emotions.removeAll { $0 == term }
        directions.removeAll { $0 == term }
        paceTerms.removeAll { $0 == term }
        registerTerms.removeAll { $0 == term }
        ceilingTerms.removeAll { $0 == term }
    }

    // MARK: - Persistence

    /// Saves the glossary to a JSON file at the given URL.
    ///
    /// - Parameter url: The file URL to write to.
    /// - Throws: If the file cannot be encoded or written.
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}

/// Errors that can occur when loading a ``VocabularyGlossary``.
public enum VocabularyGlossaryError: Error, Sendable {
    /// The requested resource file was not found in the bundle.
    case resourceNotFound(String)
}
