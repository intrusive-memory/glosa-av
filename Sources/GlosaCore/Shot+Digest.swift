import CryptoKit
import Foundation

// MARK: - Render digest

extension Shot {

  /// Keys of the schema object that never enter the digest preimage: they do
  /// not change the rendered image.
  static let digestExcludedKeys: Set<String> = ["caption", "output", "preview", "telemetry"]

  /// The digest preimage: `schemaJSON()` without `caption`, `output`,
  /// `preview` and `telemetry`, with `seed` forced to a decimal string.
  /// `documentIndex` is never part of the schema object; an empty `prompt` is
  /// omitted, as in `schemaJSON()`. Unknown keys are included.
  func renderDigestObject() -> GlosaJSONValue {
    guard case .object(let members) = schemaJSON() else { return schemaJSON() }
    var kept: [GlosaJSONMember] = []
    for member in members where !Self.digestExcludedKeys.contains(member.key) {
      if member.key == "seed", let seed {
        kept.append(GlosaJSONMember(key: "seed", value: .string(String(seed))))
      } else {
        kept.append(member)
      }
    }
    return .object(kept)
  }

  /// Lowercase hex SHA-256 of the RFC 8785 (JCS) canonical JSON of this shot's
  /// schema object, excluding `caption`, `output`, `preview`, `telemetry` (and
  /// `documentIndex`, which the schema object never carries), including unknown
  /// keys (REQ § 2.6).
  ///
  /// `seed` enters the preimage as a decimal **string** whatever its size: JCS
  /// numbers are IEEE doubles, so a seed above 2^53 would otherwise lose
  /// precision and collide.
  ///
  /// Call it on an **effective** shot (`effective(given:)` or
  /// `GlosaScore.effectiveShots`); on a raw shot it ignores inherited defaults.
  ///
  /// The preimage is **frozen for notation 2.x**: changing it is a notation
  /// major.
  public var renderDigest: String {
    let canonical = GlosaJCS.canonicalString(renderDigestObject())
    let hash = SHA256.hash(data: Data(canonical.utf8))
    return hash.map { String(format: "%02x", $0) }.joined()
  }
}
