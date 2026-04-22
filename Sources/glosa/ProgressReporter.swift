import Darwin
import Foundation
import Progress
import SwiftAcervo

/// Renders SwiftAcervo download progress to stdout using the same TUI pattern
/// as `acervo`'s own CLI.
///
/// `ProgressBar` from `Progress.swift` is a struct with mutating `next()` /
/// `setValue(_:)`; this class owns one and serialises updates through a lock
/// so it is safe to pass into actor-isolated methods as `@unchecked Sendable`.
///
/// Behaviour:
/// - When `quiet == true`, every call is a no-op.
/// - When stdout is not a TTY, no bar is constructed (so CI logs do not get
///   spammed with ANSI escapes).
/// - Otherwise the bar is created lazily on the first progress update so that
///   no bar is drawn for already-cached models (where no progress fires).
final class DownloadProgressReporter: @unchecked Sendable {

  /// Resolution of the underlying bar — 0...totalTicks corresponds to 0...100%.
  private static let totalTicks = 1000

  private let lock = NSLock()
  private let label: String
  private let quiet: Bool
  private let isTTY: Bool
  private var bar: ProgressBar?
  private var lastTicks = 0

  init(label: String, quiet: Bool) {
    self.label = label
    self.quiet = quiet
    self.isTTY = isatty(fileno(stdout)) != 0
  }

  /// Apply a SwiftAcervo progress event to the bar.
  func update(_ progress: AcervoDownloadProgress) {
    guard !quiet, isTTY else { return }

    lock.lock()
    defer { lock.unlock() }

    if bar == nil {
      let elements: [ProgressElementType] = [
        ProgressString(string: label),
        ProgressBarLine(),
        ProgressPercent(),
        ProgressTimeEstimates(),
      ]
      bar = ProgressBar(count: Self.totalTicks, configuration: elements)
    }

    let target = min(
      Self.totalTicks,
      max(0, Int((progress.overallProgress * Double(Self.totalTicks)).rounded()))
    )
    guard target > lastTicks else { return }
    bar?.setValue(target)
    lastTicks = target
  }

  /// Drive the bar to 100% so the final line is rendered cleanly. No-op if no
  /// bar was ever drawn (e.g. quiet mode or already-cached model).
  func finish() {
    guard !quiet, isTTY else { return }

    lock.lock()
    defer { lock.unlock() }

    guard bar != nil, lastTicks < Self.totalTicks else { return }
    bar?.setValue(Self.totalTicks)
    lastTicks = Self.totalTicks
  }

  /// Sendable closure suitable for passing as the `progress:` argument on
  /// SwiftAcervo / `StageDirector` APIs.
  var callback: @Sendable (AcervoDownloadProgress) -> Void {
    { [self] progress in self.update(progress) }
  }
}
