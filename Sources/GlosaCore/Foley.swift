/// A directive that places a generated one-shot sound effect — a door slam,
/// footsteps, a glass set down — on top of the ambient bed.
///
/// `Foley` is a **standalone block event** (see `Include` for the archetype
/// discussion): it has no per-line delivery semantics and no character offset.
/// It is authored as its own notation 2.0 `[[ {"foley": {…}} ]]` Fountain note
/// and may appear anywhere in document order. There is no notation 1.0 tag
/// form.
///
/// ## Foley versus ambience
///
/// An `Ambience` is a single looping bed: a new ambience note replaces the
/// running one, and a `stop` note ends it. A `Foley` is a **spot effect**: it
/// plays its generated take once, starting where its note sits in the timeline
/// (moved by `offset`), and then ends. Foley never loops, never spans a scene
/// and has no `stop`. Any number of foley effects may overlap each other and
/// the ambient bed.
///
/// GlosaCore only **parses and carries** these values; it does not generate
/// audio and does not depend on the generator. `model` is stored as a raw
/// string so this leaf stays decoupled from the generator's vocabulary.
///
/// ## Generation keys and mix-time keys
///
/// `prompt`, `seed`, `take`, `steps`, `cfg` and `model` (plus unknown keys)
/// decide the generated take and enter `renderDigest`. `offset`, `gain`,
/// `fadeIn`, `fadeOut` and `output` only decide how the take is placed in the
/// mix: changing them re-mixes, never re-generates.
public struct Foley: Sendable, Codable, Equatable {

  /// The generator used when `model` is not written.
  public static let defaultModel = Ambience.defaultModel

  /// Take length in seconds used when `take` is not written.
  public static let defaultTake: Double = 5

  /// Start offset in seconds used when `offset` is not written.
  public static let defaultOffset: Double = 0

  /// Mix gain in dB used when `gain` is not written.
  public static let defaultGain: Double = 0

  /// Fade-in in seconds used when `fadeIn` is not written. Zero, so a
  /// transient such as a door slam keeps its attack.
  public static let defaultFadeIn: Double = 0

  /// Fade-out in seconds used when `fadeOut` is not written.
  public static let defaultFadeOut: Double = 0

  /// Zero-based position of this directive in the document-order note stream.
  /// See `Include.documentIndex` for the full semantics.
  public var documentIndex: Int

  /// Text prompt for the generator. Required (the validator, not this type,
  /// enforces that).
  public var prompt: String?

  /// Generation seed. `nil` until the author (or a render write-back) sets it.
  public var seed: UInt32?

  /// Length in seconds of the generated take (1–120). The take plays once.
  public var take: Double?

  /// Sampler steps. `nil` means the generator's default.
  public var steps: Int?

  /// Guidance scale. `nil` means the generator's default.
  public var cfg: Double?

  /// Generator id, e.g. `stable-audio-3-small-sfx`. Stored raw.
  public var model: String?

  /// Seconds from the note's position in the timeline to the start of the
  /// effect. Negative starts it earlier. Mix-time only.
  public var offset: Double?

  /// Mix gain in dB. Mix-time only.
  public var gain: Double?

  /// Fade at the effect start, in seconds. Mix-time only.
  public var fadeIn: Double?

  /// Fade at the effect end, in seconds. Mix-time only.
  public var fadeOut: Double?

  /// Path of the take WAV. Assigned on first render; not part of the digest.
  public var output: String?

  /// Keys the author wrote that are not known `foley` keys, in the order read,
  /// as raw JSON values. Empty when there are none. Carried so a note
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
    offset: Double? = nil,
    gain: Double? = nil,
    fadeIn: Double? = nil,
    fadeOut: Double? = nil,
    output: String? = nil,
    extraAttributes: [GlosaJSONMember] = []
  ) {
    self.documentIndex = documentIndex
    self.prompt = prompt
    self.seed = seed
    self.take = take
    self.steps = steps
    self.cfg = cfg
    self.model = model
    self.offset = offset
    self.gain = gain
    self.fadeIn = fadeIn
    self.fadeOut = fadeOut
    self.output = output
    self.extraAttributes = extraAttributes
  }
}

// MARK: - Effective values

extension Foley {

  /// `take`, or `defaultTake` (5 s) when not written.
  public var effectiveTake: Double { take ?? Self.defaultTake }

  /// `offset`, or `defaultOffset` (0 s) when not written.
  public var effectiveOffset: Double { offset ?? Self.defaultOffset }

  /// `gain`, or `defaultGain` (0 dB) when not written.
  public var effectiveGain: Double { gain ?? Self.defaultGain }

  /// `fadeIn`, or `defaultFadeIn` (0 s) when not written.
  public var effectiveFadeIn: Double { fadeIn ?? Self.defaultFadeIn }

  /// `fadeOut`, or `defaultFadeOut` (0 s) when not written.
  public var effectiveFadeOut: Double { fadeOut ?? Self.defaultFadeOut }

  /// `model`, or `defaultModel` (`stable-audio-3-small-sfx`) when not written.
  public var effectiveModel: String { model ?? Self.defaultModel }
}

// MARK: - Codable (in-process persistence form)

extension Foley {
  private enum CodingKeys: String, CodingKey {
    case documentIndex, prompt, seed, take, steps, cfg, model, offset, gain
    case fadeIn, fadeOut, output, extraAttributes
  }

  /// Decodes the in-process persistence form. A missing `extraAttributes`
  /// decodes to `[]`.
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
      offset: try c.decodeIfPresent(Double.self, forKey: .offset),
      gain: try c.decodeIfPresent(Double.self, forKey: .gain),
      fadeIn: try c.decodeIfPresent(Double.self, forKey: .fadeIn),
      fadeOut: try c.decodeIfPresent(Double.self, forKey: .fadeOut),
      output: try c.decodeIfPresent(String.self, forKey: .output),
      extraAttributes: try c.decodeIfPresent([GlosaJSONMember].self, forKey: .extraAttributes)
        ?? []
    )
  }
}
