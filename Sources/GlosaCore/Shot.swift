/// A directive carrying a storyboard-panel prompt plus the full set of
/// `vinetas generate` options, to be piped to the Vinetas CLI by a downstream
/// tool.
///
/// `Shot` is a **standalone block event** (see `Include` for the archetype
/// discussion): it has no per-line delivery semantics and no character offset.
/// It is authored as its own `[[<shot …/>]]` Fountain note (or `<glosa:shot/>`
/// FDX element) and may appear anywhere in document order.
///
/// The attribute set mirrors the `vinetas generate` command
/// (`SwiftVinetas/Sources/VinetasCLICore/VinetasCLICore.swift`). GlosaCore only
/// **parses and carries** these values; it does not run the CLI and does not
/// depend on Vinetas. `model` and `aspect` are stored as raw strings rather
/// than mapped onto Vinetas's enums, so this leaf stays decoupled from the
/// CLI's exact vocabulary — the validator merely warns on unrecognized values.
///
/// ## Defaults convention: a `<shot>` with no `prompt`
///
/// By convention a `<shot>` whose `prompt` is empty **renders nothing**.
/// Instead, its other attributes (`style`, `model`, `aspect`, `seed`, `width`,
/// `steps`, …) become the **active defaults** for every subsequent `<shot>`
/// from that document position forward in the screenplay:
///
/// - A later `<shot>` **with** a `prompt` generates a panel, inheriting the
///   active defaults for any attribute it does not set itself — the shot's own
///   attributes win per-attribute.
/// - A later no-`prompt` `<shot>` updates the active defaults again going
///   forward (each attribute it names replaces that entry in the default set).
///
/// GlosaCore stays *parse-and-carry*: it emits every `<shot>` (defaults ones
/// included, recognizable by their empty `prompt`) in `documentIndex` order and
/// does **not** compute effective shots. The downstream Vinetas orchestrator is
/// responsible for folding the defaults into each rendered shot. Because an
/// empty `prompt` is meaningful here, the validator does **not** flag it (unlike
/// the universal audio-intent `prompt` on other directives).
public struct Shot: Sendable, Codable, Equatable {

  /// Zero-based position of this directive in the document-order note stream.
  /// See `Include.documentIndex` for the full semantics.
  public var documentIndex: Int

  /// Text description of the panel to generate (maps to the `generate` PROMPT
  /// argument). When **empty**, this `<shot>` renders nothing and instead sets
  /// the active generation defaults for subsequent shots — see the type-level
  /// "Defaults convention" discussion above.
  public var prompt: String

  /// Style prompt for a consistent look (maps to `--style`).
  public var style: String?

  /// Model variant, e.g. `klein4b`, `klein9b`, `pixart-sigma` (maps to
  /// `--model`). Stored raw; the validator warns on unrecognized values.
  public var model: String?

  /// Aspect-ratio preset, e.g. `square`, `wide`, `ultrawide`, `portrait`,
  /// `panel`, `strip` (maps to `--aspect`). Stored raw; the validator warns on
  /// unrecognized values.
  public var aspect: String?

  /// Output image width in pixels (maps to `--width`).
  public var width: Int?

  /// Output image height in pixels (maps to `--height`).
  public var height: Int?

  /// Number of inference steps (maps to `--steps`).
  public var steps: Int?

  /// Classifier-free guidance scale (maps to `--guidance`).
  public var guidance: Double?

  /// Random seed for reproducibility (maps to `--seed`).
  public var seed: UInt64?

  /// Negative prompt to steer away from unwanted characteristics (maps to
  /// `--negative`).
  public var negative: String?

  /// Path to a LoRA safetensors file (maps to `--lora`).
  public var lora: String?

  /// LoRA scale, 0.0–1.0 (maps to `--lora-scale`).
  public var loraScale: Double?

  /// Output file path (maps to `--output`).
  public var output: String?

  /// Fast preview mode (maps to the `--preview` flag).
  public var preview: Bool?

  /// Write a JSONL telemetry trace (maps to the `--telemetry` flag).
  public var telemetry: Bool?

  public init(
    documentIndex: Int,
    prompt: String,
    style: String? = nil,
    model: String? = nil,
    aspect: String? = nil,
    width: Int? = nil,
    height: Int? = nil,
    steps: Int? = nil,
    guidance: Double? = nil,
    seed: UInt64? = nil,
    negative: String? = nil,
    lora: String? = nil,
    loraScale: Double? = nil,
    output: String? = nil,
    preview: Bool? = nil,
    telemetry: Bool? = nil
  ) {
    self.documentIndex = documentIndex
    self.prompt = prompt
    self.style = style
    self.model = model
    self.aspect = aspect
    self.width = width
    self.height = height
    self.steps = steps
    self.guidance = guidance
    self.seed = seed
    self.negative = negative
    self.lora = lora
    self.loraScale = loraScale
    self.output = output
    self.preview = preview
    self.telemetry = telemetry
  }
}
