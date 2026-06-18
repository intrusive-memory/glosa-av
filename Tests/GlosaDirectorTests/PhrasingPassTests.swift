import Foundation
import GlosaCore
import SwiftCompartido
import Testing

@testable import GlosaDirector

/// Tests for the PHRASING pass — word-count gate, rewrite validation, and
/// offset derivation. All inference is mocked; no real model runs.
struct PhrasingPassTests {

  // A long, irregularly phrased line, well over the word-count gate.
  static let longLine = """
    Bishop is freighted with authority and patriarchy and a long history of \
    institutional cover-ups and a deeply entrenched anti-queer theology, and \
    frankly I am exhausted by all of it and everything it stands for.
    """

  /// Builds a one-scene segment: a heading then the given (character, line) pairs.
  static func scene(_ lines: [(String, String)]) -> SceneSegment {
    var elements: [GuionElement] = [
      GuionElement(elementType: .sceneHeading, elementText: "INT. CHURCH - NIGHT")
    ]
    for (character, dialogue) in lines {
      elements.append(GuionElement(elementType: .character, elementText: character))
      elements.append(GuionElement(elementType: .dialogue, elementText: dialogue))
    }
    return SceneSegment(elements: elements)
  }

  /// A generator that rewrites each requested line via `transform`.
  static func generator(
    _ transform: @escaping @Sendable (String) -> String
  ) -> MockFacetGenerator {
    MockFacetGenerator { _, userPrompt in
      let prefix = "Line:\n"
      let text =
        userPrompt.hasPrefix(prefix) ? String(userPrompt.dropFirst(prefix.count)) : userPrompt
      return transform(text)
    }
  }

  // MARK: - Word-count gate

  @Test("Short lines are below the word-count gate")
  func shortLinesRejected() {
    #expect(!PhrasingPass.isCandidate("I noticed."))
    #expect(!PhrasingPass.isCandidate("Yeah."))
    #expect(!PhrasingPass.isCandidate("Have you thought about how I'm going to do it?"))
  }

  @Test("A long line clears the word-count gate")
  func longLineAccepted() {
    #expect(PhrasingPass.isCandidate(Self.longLine))
    #expect(PhrasingPass.wordCount(Self.longLine) >= PhrasingPass.minWordCount)
  }

  // MARK: - Zero-candidate scene makes zero model calls

  @Test("A scene with only short lines makes no model calls")
  func zeroCandidatesZeroCalls() async throws {
    let gen = MockFacetGenerator { _, _ in
      Issue.record("Generator must not be called for sub-threshold lines")
      return ""
    }
    let delta = try await PhrasingPass().annotate(
      scene: Self.scene([("ALICE", "I noticed."), ("BOB", "Yeah.")]),
      sceneIndex: 0,
      using: gen,
      model: "test"
    )
    #expect(delta == .breaths([]))
    #expect(gen.callCount == 0)
  }

  // MARK: - Rewrite → validated offsets

  @Test("An inserted marker becomes a breath at the word boundary")
  func markerBecomesBreath() async throws {
    // Insert a marker before "authority" (starts at offset 25 in the line).
    let gen = Self.generator { line in
      line.replacingOccurrences(of: "authority", with: "<breath> authority")
    }
    let delta = try await PhrasingPass().annotate(
      scene: Self.scene([("BISHOP", Self.longLine), ("ALICE", "I noticed.")]),
      sceneIndex: 0,
      using: gen,
      model: "test"
    )
    #expect(
      delta
        == .breaths([
          BreathAnnotation(dialogueLineIndex: 0, characterOffset: 25, strength: nil)
        ]))
    // Only the long line is over the gate, so exactly one call.
    #expect(gen.callCount == 1)
  }

  @Test("A rewrite that alters the words is rejected")
  func alteredRewriteRejected() async throws {
    // Prepend a word the original never had → validation fails.
    let gen = Self.generator { "EXTRA <breath> " + $0 }
    let delta = try await PhrasingPass().annotate(
      scene: Self.scene([("BISHOP", Self.longLine)]),
      sceneIndex: 0,
      using: gen,
      model: "test"
    )
    #expect(delta == .breaths([]))
    #expect(gen.callCount == 1)
  }

  @Test("A marker at the line start is dropped")
  func markerAtStartDropped() async throws {
    let gen = Self.generator { "<breath> " + $0 }
    let delta = try await PhrasingPass().annotate(
      scene: Self.scene([("BISHOP", Self.longLine)]),
      sceneIndex: 0,
      using: gen,
      model: "test"
    )
    #expect(delta == .breaths([]))
  }

  @Test("An unchanged rewrite yields no breaths but still costs the call")
  func unchangedRewriteNoBreaths() async throws {
    let gen = Self.generator { $0 }  // model returns the line untouched
    let delta = try await PhrasingPass().annotate(
      scene: Self.scene([("BISHOP", Self.longLine)]),
      sceneIndex: 0,
      using: gen,
      model: "test"
    )
    #expect(delta == .breaths([]))
    #expect(gen.callCount == 1)
  }
}
