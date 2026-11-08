/// A directive that starts (or stops) an ambient bed: a generated atmosphere
/// take that a downstream tool loops under the dialogue.
///
/// `Ambience` is a **standalone block event** (see `Include` for the archetype
/// discussion): it has no per-line delivery semantics and no character offset.
/// It is authored as its own notation 2.0 `[[ {"ambience": {…}} ]]` Fountain
/// note and may appear anywhere in document order. There is no notation 1.0
/// tag form.
///
/// GlosaCore only **parses and carries** these values; it does not generate
/// audio and does not depend on the generator. `model` is stored as a raw
/// string so this leaf stays decoupled from the generator's vocabulary.
///
/// ## Generation keys and mix-time keys
///
/// `prompt`, `seed`, `take`, `steps`, `cfg` and `model` (plus unknown keys)
/// decide the generated take and enter `renderDigest`. `length`, `gain`,
/// `fadeIn`, `fadeOut`, `crossfade`, `output` and `stop` only decide how the
/// take is placed in the mix: changing them re-mixes, never re-generates.
///
/// ## `stop`
///
/// An ambience with `stop == true` ends the running bed and carries no other
/// keys.
public struct Ambience: Sendable, Codable, Equatable {

  /// The generator used when `model` is not written.
  public static let defaultModel = "stable-audio-3-small-sfx"

  /// Take length in seconds used when `take` is not written.
  public static let defaultTake: Double = 30

  /// Bed span used when `length` is not written.
  public static let defaultLength: AmbienceLength = .scene

  /// Mix gain in dB used when `gain` is not written.
  public static let defaultGain: Double = 0

  /// Fade-in in seconds used when `fadeIn` is not written.
  public static let defaultFadeIn: Double = 1

  /// Fade-out in seconds used when `fadeOut` is not written.
  public static let defaultFadeOut: Double = 2

  /// Loop-seam crossfade in seconds used when `crossfade` is not written.
  public static let defaultCrossfade: Double = 2

  /// Zero-based position of this directive in the document-order note stream.
  /// See `Include.documentIndex` for the full semantics.
  public var documentIndex: Int

  /// Text prompt for the generator. Required unless `stop` is set (the
  /// validator, not this type, enforces that).
  public var prompt: String?

  /// Generation seed. `nil` until the author (or a render write-back) sets it.
  public var seed: UInt32?

  /// Length in seconds of the generated take before looping (1–120).
  public var take: Double?

  /// Sampler steps. `nil` means the generator's default.
  public var steps: Int?

  /// Guidance scale. `nil` means the generator's default.
  public var cfg: Double?

  /// Generator id, e.g. `stable-audio-3-small-sfx`. Stored raw.
  public var model: String?

  /// How long the bed plays. Mix-time only.
  public var length: AmbienceLength?

  /// Mix gain in dB. Mix-time only.
  public var gain: Double?

  /// Fade at bed start, in seconds. Mix-time only.
  public var fadeIn: Double?

  /// Fade at bed end, in seconds. Mix-time only.
  public var fadeOut: Double?

  /// Loop-seam crossfade, in seconds. Mix-time only.
  public var crossfade: Double?

  /// Path of the take WAV. Assigned on first render; not part of the digest.
  public var output: String?

  /// `true` when this note ends the running bed. Written only when `true`.
  public var stop: Bool

  /// Keys the author wrote that are not known `ambience` keys, in the order
  /// read, as raw JSON values. Empty when there are none. Carried so a note
  /// round-trips unchanged; GlosaCore never interprets them. They enter
  /// `renderDigest`.
  ///
  /// The synthesized `Codable` conformance (in-process persistence) stores
  /// these under an `extraAttributes` field. That form is **not** the schema
  /// form — see `schemaJSON()` / `init(schemaJSON:documentIndex:)`, which put
  /// unknown keys at the top level.
  public var extraAttributes: [GlosaJSONMember]

  public init(
    documentIndex: Int,
    prompt: String? = nil,
    seed: UInt32? = nil,
    take: Double? = nil,
    steps: Int? = nil,
    cfg: Double? = nil,
    model: String? = nil,
    length: AmbienceLength? = nil,
    gain: Double? = nil,
    fadeIn: Double? = nil,
    fadeOut: Double? = nil,
    crossfade: Double? = nil,
    output: String? = nil,
    stop: Bool = false,
    extraAttributes: [GlosaJSONMember] = []
  ) {
    self.documentIndex = documentIndex
    self.prompt = prompt
    self.seed = seed
    self.take = take
    self.steps = steps
    self.cfg = cfg
    self.model = model
    self.length = length
    self.gain = gain
    self.fadeIn = fadeIn
    self.fadeOut = fadeOut
    self.crossfade = crossfade
    self.output = output
    self.stop = stop
    self.extraAttributes = extraAttributes
  }
}

// MARK: - Effective values

extension Ambience {

  /// `take`, or `defaultTake` (30 s) when not written.
  public var effectiveTake: Double { take ?? Self.defaultTake }

  /// `length`, or `defaultLength` (`.scene`) when not written.
  public var effectiveLength: AmbienceLength { length ?? Self.defaultLength }

  /// `gain`, or `defaultGain` (0 dB) when not written.
  public var effectiveGain: Double { gain ?? Self.defaultGain }

  /// `fadeIn`, or `defaultFadeIn` (1 s) when not written.
  public var effectiveFadeIn: Double { fadeIn ?? Self.defaultFadeIn }

  /// `fadeOut`, or `defaultFadeOut` (2 s) when not written.
  public var effectiveFadeOut: Double { fadeOut ?? Self.defaultFadeOut }

  /// `crossfade`, or `defaultCrossfade` (2 s) when not written.
  public var effectiveCrossfade: Double { crossfade ?? Self.defaultCrossfade }

  /// `model`, or `defaultModel` (`stable-audio-3-small-sfx`) when not written.
  public var effectiveModel: String { model ?? Self.defaultModel }
}

// MARK: - Codable (in-process persistence form)

extension Ambience {
  private enum CodingKeys: String, CodingKey {
    case documentIndex, prompt, seed, take, steps, cfg, model, length, gain
    case fadeIn, fadeOut, crossfade, output, stop, extraAttributes
  }

  /// Decodes the in-process persistence form. A missing `stop` decodes to
  /// `false` and a missing `extraAttributes` to `[]`.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      documentIndex: try c.decode(Int.self, forKey: .documentIndex),
      prompt: try c.decodeIfPresent(String.self, forKey: .prompt),
      seed: try c.decodeIfPresent(UInt32.self, forKey: .seed),
      take: try c.decodeIfPresent(Double.self, forKey: .take),
      steps: try c.decodeIfPresent(Int.self, forKey: .steps),
      cfg: try c.decodeIfPresent(Double.self, forKey: .cfg),
      model: try c.decodeIfPresent(String.self, forKey: .model),
      length: try c.decodeIfPresent(AmbienceLength.self, forKey: .length),
      gain: try c.decodeIfPresent(Double.self, forKey: .gain),
      fadeIn: try c.decodeIfPresent(Double.self, forKey: .fadeIn),
      fadeOut: try c.decodeIfPresent(Double.self, forKey: .fadeOut),
      crossfade: try c.decodeIfPresent(Double.self, forKey: .crossfade),
      output: try c.decodeIfPresent(String.self, forKey: .output),
      stop: try c.decodeIfPresent(Bool.self, forKey: .stop) ?? false,
      extraAttributes: try c.decodeIfPresent([GlosaJSONMember].self, forKey: .extraAttributes)
        ?? []
    )
  }
}

/// How long an `Ambience` bed plays (the `length` key).
public enum AmbienceLength: Sendable, Codable, Equatable {
  /// Until the next scene heading, the next `ambience` note, or a `stop` note.
  case scene
  /// Until the next `ambience` or `stop` note; crosses scene headings.
  case continuous
  /// The end of one take; no looping.
  case natural
  /// This many seconds, or the next `ambience`/`stop` note if sooner.
  case seconds(Double)

  /// The `length` string for the named cases; `nil` for `.seconds`.
  public var keyword: String? {
    switch self {
    case .scene: "scene"
    case .continuous: "continuous"
    case .natural: "natural"
    case .seconds: nil
    }
  }

  /// The named case for a `length` string, or `nil` when it is not one.
  public init?(keyword: String) {
    switch keyword {
    case "scene": self = .scene
    case "continuous": self = .continuous
    case "natural": self = .natural
    default: return nil
    }
  }
}
