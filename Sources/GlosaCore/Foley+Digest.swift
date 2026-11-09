import Foundation

#if canImport(CryptoKit)
  import CryptoKit
#else
  import Crypto
#endif

// MARK: - Render digest

extension Foley {

  /// Keys of the schema object that never enter the digest preimage: they do
  /// not change the generated take. They only place the take in the mix
  /// (`offset`, `gain`, `fadeIn`, `fadeOut`) or name where it lives
  /// (`output`).
  static let digestExcludedKeys: Set<String> = [
    "offset", "gain", "fadeIn", "fadeOut", "output",
  ]

  /// The digest preimage: `schemaJSON()` without `digestExcludedKeys`, with
  /// `seed` forced to a decimal string. Exclusion is by top-level key only.
  /// `documentIndex` is never part of the schema object. Unknown keys are
  /// included.
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

  /// Lowercase hex SHA-256 of the RFC 8785 (JCS) canonical JSON of this
  /// effect's schema object over `prompt`, `seed`, `take`, `steps`, `cfg`,
  /// `model` and every unknown key — the same construction as
  /// `Ambience.renderDigest`. `offset`, `gain`, `fadeIn`, `fadeOut`, `output`
  /// and `documentIndex` are excluded: changing them re-mixes, never
  /// re-generates.
  ///
  /// The preimage holds the keys **as written**: an omitted `take` or `model`
  /// is absent, not replaced by its effective default. `seed` enters as a
  /// decimal **string**.
  public var renderDigest: String {
    let canonical = GlosaJCS.canonicalString(renderDigestObject())
    let hash = SHA256.hash(data: Data(canonical.utf8))
    return hash.map { String(format: "%02x", $0) }.joined()
  }
}
