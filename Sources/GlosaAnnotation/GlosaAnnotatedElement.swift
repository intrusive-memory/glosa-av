import GlosaCore
import SwiftCompartido

/// A screenplay element annotated with its resolved GLOSA directives and
/// compiled instruct string.
///
/// Wraps a ``SwiftCompartido/GuionElement`` together with the active
/// ``GlosaCore/ResolvedDirectives`` and the natural-language instruct
/// string produced by the GLOSA compiler for that element's position
/// in the screenplay.
///
/// For non-dialogue elements (action, scene headings, transitions, etc.)
/// or dialogue elements that fall in a neutral gap (no active GLOSA
/// directives), both `directives` and `instruct` are `nil`.
public struct GlosaAnnotatedElement: Sendable {

    /// The underlying screenplay element.
    public let element: GuionElement

    /// The resolved GLOSA directives active at this element's position,
    /// or `nil` if the element is non-dialogue or has no active directives.
    public let directives: ResolvedDirectives?

    /// The compiled natural-language instruct string for this element,
    /// or `nil` if the element is non-dialogue or has no active directives.
    public let instruct: String?

    /// Creates a new annotated element.
    ///
    /// - Parameters:
    ///   - element: The screenplay element being annotated.
    ///   - directives: The resolved GLOSA directives, or `nil`.
    ///   - instruct: The compiled instruct string, or `nil`.
    public init(
        element: GuionElement,
        directives: ResolvedDirectives? = nil,
        instruct: String? = nil
    ) {
        self.element = element
        self.directives = directives
        self.instruct = instruct
    }
}
