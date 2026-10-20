import Foundation

/// GlosaCore's resource bundle (the shipped `schemas/`).
///
/// A target that has its own resources gets its own `Bundle.module`, which
/// shadows this module's one even under `@testable import`; this accessor names
/// GlosaCore's bundle unambiguously.
enum GlosaResources {
  static var bundle: Bundle { .module }
}
