import GlosaAnnotation
import GlosaCore
import Testing

/// Tests for `BreathRenderer.renderBreathBlock(for:)`.
///
/// This test suite drives the pure rendering helper directly — no CLI process,
/// no filesystem, no LLM. The Bishop fixture is the same canonical fixture
/// used by `BreathBridgeTests`, `BreathCompilerTests`, and
/// `BreathParserFountainTests`.
///
/// ## Methodology (OPERATION CLEAVING BREATH)
///
/// - **Deterministic**: no `Date()`, no `UUID()`, no random seeds.
/// - **Hermetic**: no network, no filesystem, no shared mutable state.
/// - **Untimed**: no `Thread.sleep`, no `XCTestExpectation`.
///
/// ## Format (post OPERATION CLEAVING BREATH)
///
/// `BreathPoint` no longer carries `length`; duration moved to `PausePoint`.
/// The rendered format is now:
/// ```
/// breaths: at <offset> (<strength>)
///          at <offset> (<strength>)
/// ```
@Suite("BreathRenderer — renderBreathBlock(for:)")
struct BreathRenderTests {

  // MARK: - Bishop fixture

  /// The three Bishop breath points from spec §6.4, sorted ascending by offset.
  /// `length` is no longer a `BreathPoint` attribute; only `strength` is rendered.
  private let bishopPoints: [BreathPoint] = [
    BreathPoint(offset: 20, strength: .strong),
    BreathPoint(offset: 31, strength: .medium),
    BreathPoint(offset: 43, strength: .medium),
  ]

  // MARK: - Test 1: Bishop fixture produces three breath lines

  @Test("Bishop fixture produces three breath lines at offsets 20, 31, 43")
  func bishopFixtureProducesThreeBreathLines() {
    let result = BreathRenderer.renderBreathBlock(for: bishopPoints)

    guard let block = result else {
      Issue.record("Expected non-nil breath block for non-empty breathPoints")
      return
    }

    let lines = block.components(separatedBy: "\n")
    #expect(lines.count == 3)

    // Exact snapshot: strength only, no length token.
    #expect(lines[0] == "breaths: at 20 (strong)")
    #expect(lines[1] == "         at 31 (medium)")
    #expect(lines[2] == "         at 43 (medium)")
  }

  // MARK: - Test 2: at-offset values in order

  @Test("Rendered output contains at 20, at 31, at 43 in that order")
  func renderedBlockContainsOffsets20_31_43InOrder() {
    guard let block = BreathRenderer.renderBreathBlock(for: bishopPoints) else {
      Issue.record("Expected non-nil block")
      return
    }

    let pos20 = block.range(of: "at 20")
    let pos31 = block.range(of: "at 31")
    let pos43 = block.range(of: "at 43")

    #expect(pos20 != nil)
    #expect(pos31 != nil)
    #expect(pos43 != nil)

    if let r20 = pos20, let r31 = pos31, let r43 = pos43 {
      #expect(r20.lowerBound < r31.lowerBound)
      #expect(r31.lowerBound < r43.lowerBound)
    }
  }

  // MARK: - Test 3: empty input returns nil

  @Test("Empty breathPoints returns nil (no breaths: section emitted)")
  func emptyBreathPointsReturnsNil() {
    let result = BreathRenderer.renderBreathBlock(for: [])
    #expect(result == nil)
  }

  // MARK: - Test 4: single breath point

  @Test("Single breath point renders on one line")
  func singleBreathPointRendersOnOneLine() {
    let points = [BreathPoint(offset: 10, strength: .strong)]
    guard let block = BreathRenderer.renderBreathBlock(for: points) else {
      Issue.record("Expected non-nil block")
      return
    }

    let lines = block.components(separatedBy: "\n")
    #expect(lines.count == 1)
    #expect(lines[0] == "breaths: at 10 (strong)")
  }

  // MARK: - Test 5: default strength (medium)

  @Test("Default strength renders as 'medium'")
  func defaultStrengthRendersMedium() {
    let points = [BreathPoint(offset: 5, strength: .medium)]
    guard let block = BreathRenderer.renderBreathBlock(for: points) else {
      Issue.record("Expected non-nil block")
      return
    }

    #expect(block == "breaths: at 5 (medium)")
  }

  // MARK: - Test 6: weak strength

  @Test("Weak strength renders as 'weak'")
  func weakStrengthRendersWeak() {
    let points = [BreathPoint(offset: 7, strength: .weak)]
    guard let block = BreathRenderer.renderBreathBlock(for: points) else {
      Issue.record("Expected non-nil block")
      return
    }

    #expect(block == "breaths: at 7 (weak)")
  }

  // MARK: - Test 7: no-breaths produces no 'breaths:' substring

  @Test("No-breaths input produces no 'breaths:' output")
  func noBreathsProducesNoBreathsSubstring() {
    let result = BreathRenderer.renderBreathBlock(for: [])
    #expect(result == nil)
    let rendered = result ?? ""
    #expect(!rendered.contains("breaths:"))
  }

  // MARK: - Test 8: indentation alignment

  @Test("Continuation lines are indented with exactly 9 spaces")
  func continuationLinesHaveNineSpaceIndent() {
    let points = [
      BreathPoint(offset: 1, strength: .medium),
      BreathPoint(offset: 2, strength: .medium),
    ]
    guard let block = BreathRenderer.renderBreathBlock(for: points) else {
      Issue.record("Expected non-nil block")
      return
    }

    let lines = block.components(separatedBy: "\n")
    #expect(lines.count == 2)

    // First line starts with the label prefix.
    #expect(lines[0].hasPrefix("breaths: at "))

    // Continuation line starts with exactly 9 spaces.
    #expect(lines[1].hasPrefix("         at "))
    // Confirm the 10th character is 'a' (start of "at"), not a space.
    let chars = Array(lines[1])
    #expect(chars.count > 9)
    #expect(chars[9] == "a")
  }
}
