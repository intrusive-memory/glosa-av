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
/// ## Methodology (OPERATION SIGHING SCRIBE)
///
/// - **Deterministic**: no `Date()`, no `UUID()`, no random seeds. Input
///   arrays are constructed in ascending-offset order to match the compiler
///   contract; no dictionary-iteration order dependence.
/// - **Hermetic**: no network, no filesystem, no shared mutable state.
/// - **Untimed**: no `Thread.sleep`, no `XCTestExpectation`, no `measure {}`.
///
/// ## Format spec §9
///
/// ```
/// breaths: at <offset> (<length>, <strength>)
///          at <offset> (<length>, <strength>)
/// ```
///
/// - Label `"breaths: "` = 9 characters.
/// - Continuation lines indented with 9 spaces so `at` aligns under the
///   first `at`.
@Suite("BreathRenderer — renderBreathBlock(for:)")
struct BreathRenderTests {

  // MARK: - Bishop fixture

  /// The three Bishop breath points from spec §6.4, sorted ascending
  /// by offset (compiler contract: offset 20, 31, 43).
  private let bishopPoints: [BreathPoint] = [
    BreathPoint(offset: 20, length: .period, strength: .strong),
    BreathPoint(offset: 31, length: .comma, strength: .medium),
    BreathPoint(offset: 43, length: .comma, strength: .medium),
  ]

  // MARK: - Test 1: Bishop fixture produces three breath lines

  /// Rendering the Bishop fixture must produce exactly three lines whose
  /// `at <offset>` values are 20, 31, 43 in that order.
  ///
  /// The snapshot is deliberately tight (methodology rule 7): any drift in
  /// the label, indentation, or token spelling fails CI by design.
  @Test("Bishop fixture produces three breath lines at offsets 20, 31, 43")
  func bishopFixtureProducesThreeBreathLines() {
    let result = BreathRenderer.renderBreathBlock(for: bishopPoints)

    // Must be non-nil (non-empty input).
    guard let block = result else {
      Issue.record("Expected non-nil breath block for non-empty breathPoints")
      return
    }

    let lines = block.components(separatedBy: "\n")
    #expect(lines.count == 3)

    // Exact snapshot — byte-precise per methodology rule 7.
    #expect(lines[0] == "breaths: at 20 (period, strong)")
    #expect(lines[1] == "         at 31 (comma, medium)")
    #expect(lines[2] == "         at 43 (comma, medium)")
  }

  // MARK: - Test 2: at-offset values in order

  /// The `at <offset>` values in the rendered output must be 20, 31, 43
  /// in that order — an explicit ordered assertion per exit criteria.
  @Test("Rendered output contains at 20, at 31, at 43 in that order")
  func renderedBlockContainsOffsets20_31_43InOrder() {
    guard let block = BreathRenderer.renderBreathBlock(for: bishopPoints) else {
      Issue.record("Expected non-nil block")
      return
    }

    // Verify each offset appears and in ascending order by checking
    // their positions in the rendered string.
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

  /// Rendering an empty `breathPoints` array must return `nil` so callers
  /// can suppress the `breaths:` section entirely.
  @Test("Empty breathPoints returns nil (no breaths: section emitted)")
  func emptyBreathPointsReturnsNil() {
    let result = BreathRenderer.renderBreathBlock(for: [])
    #expect(result == nil)
  }

  // MARK: - Test 4: single breath point

  /// A single breath point with non-default length and strength is
  /// rendered on exactly one line starting with `"breaths: "`.
  @Test("Single breath point renders on one line")
  func singleBreathPointRendersOnOneLine() {
    let points = [BreathPoint(offset: 10, length: .period, strength: .strong)]
    guard let block = BreathRenderer.renderBreathBlock(for: points) else {
      Issue.record("Expected non-nil block")
      return
    }

    let lines = block.components(separatedBy: "\n")
    #expect(lines.count == 1)
    #expect(lines[0] == "breaths: at 10 (period, strong)")
  }

  // MARK: - Test 5: default tokens (comma / medium)

  /// A bare breath point with default length `.comma` and strength `.medium`
  /// renders those tokens by name (not empty strings or omitted).
  @Test("Default length/strength tokens render as 'comma' and 'medium'")
  func defaultTokensRenderAsCommaAndMedium() {
    let points = [BreathPoint(offset: 5, length: .comma, strength: .medium)]
    guard let block = BreathRenderer.renderBreathBlock(for: points) else {
      Issue.record("Expected non-nil block")
      return
    }

    #expect(block == "breaths: at 5 (comma, medium)")
  }

  // MARK: - Test 6: explicit duration token

  /// A breath point with `.explicit(0.35)` renders as `"350ms"` — the
  /// `.rounded()` rule from methodology §5 must be observed.
  @Test("Explicit duration 0.35s renders as '350ms'")
  func explicitDurationRoundsToMs() {
    let points = [BreathPoint(offset: 7, length: .explicit(0.35), strength: .weak)]
    guard let block = BreathRenderer.renderBreathBlock(for: points) else {
      Issue.record("Expected non-nil block")
      return
    }

    #expect(block == "breaths: at 7 (350ms, weak)")
  }

  // MARK: - Test 7: em-dash token

  /// `BreathLength.emDash` renders as `"em-dash"` (hyphenated wire token).
  @Test("BreathLength.emDash renders as 'em-dash'")
  func emDashToken() {
    let points = [BreathPoint(offset: 15, length: .emDash, strength: .strong)]
    guard let block = BreathRenderer.renderBreathBlock(for: points) else {
      Issue.record("Expected non-nil block")
      return
    }

    #expect(block == "breaths: at 15 (em-dash, strong)")
  }

  // MARK: - Test 8: no-breaths screenplay produces no 'breaths:' substring

  /// When a screenplay has no breath annotations, `renderBreathBlock(for:[])`
  /// returns `nil` — so no `"breaths:"` substring can appear in the output.
  /// This test exercises the nil-return contract explicitly.
  @Test("No-breaths input produces no 'breaths:' output")
  func noBreathsProducesNoBreathsSubstring() {
    let result = BreathRenderer.renderBreathBlock(for: [])
    // nil means the caller suppresses the entire section.
    #expect(result == nil)
    // For belt-and-suspenders: unwrapping nil gives empty string, which
    // also contains no "breaths:" substring.
    let rendered = result ?? ""
    #expect(!rendered.contains("breaths:"))
  }

  // MARK: - Test 9: indentation alignment

  /// Continuation lines must be indented with exactly 9 spaces so `at`
  /// aligns under the `at` on the first line. The label `"breaths: "` is
  /// exactly 9 characters, so the continuation indent is also 9 spaces.
  @Test("Continuation lines are indented with exactly 9 spaces")
  func continuationLinesHaveNineSpaceIndent() {
    let points = [
      BreathPoint(offset: 1, length: .comma, strength: .medium),
      BreathPoint(offset: 2, length: .comma, strength: .medium),
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
