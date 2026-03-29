import GlosaAnnotation
import GlosaCore
import SwiftCompartido

/// A segment of a screenplay representing a single scene.
///
/// Each scene starts with a `sceneHeading` element and includes all
/// subsequent elements up to (but not including) the next scene heading
/// or the end of the document.
public struct SceneSegment: Sendable {

  /// The elements comprising this scene, starting with the scene heading.
  public let elements: [GuionElement]

  /// The scene heading text (convenience accessor for `elements[0].elementText`).
  public var headingText: String {
    elements.first?.elementText ?? ""
  }

  /// Creates a new scene segment.
  ///
  /// - Parameter elements: The elements in this scene, starting with the heading.
  public init(elements: [GuionElement]) {
    self.elements = elements
  }
}

/// Segments a parsed screenplay into individual scenes by scene heading boundaries.
///
/// The `SceneAnalyzer` identifies `sceneHeading` elements in a
/// ``SwiftCompartido/GuionParsedElementCollection`` and groups all elements
/// between consecutive headings into ``SceneSegment`` values.
///
/// Elements appearing before the first scene heading (e.g., title page
/// content, initial action lines) are collected into a leading segment
/// only if they exist -- that segment will have no scene heading.
///
/// ## Usage
///
/// ```swift
/// let screenplay = try await GuionParsedElementCollection(file: path)
/// let segments = SceneAnalyzer.segmentScenes(from: screenplay)
/// // Each segment starts with a sceneHeading element
/// ```
public enum SceneAnalyzer {

  /// Segments a parsed screenplay into scenes by `sceneHeading` boundaries.
  ///
  /// Each scene segment starts from a scene heading element and extends
  /// through to (but not including) the next scene heading or the end of
  /// the document.
  ///
  /// - Parameter screenplay: The parsed screenplay to segment.
  /// - Returns: An array of ``SceneSegment`` values, one per scene.
  ///   Elements before the first scene heading are discarded (they belong
  ///   to the title page / preamble, not a scene).
  public static func segmentScenes(
    from screenplay: GuionParsedElementCollection
  ) -> [SceneSegment] {
    var segments: [SceneSegment] = []
    var currentElements: [GuionElement] = []
    var inScene = false

    for element in screenplay.elements {
      if element.elementType == .sceneHeading {
        // If we were already accumulating a scene, close it
        if inScene && !currentElements.isEmpty {
          segments.append(SceneSegment(elements: currentElements))
        }
        // Start a new scene
        currentElements = [element]
        inScene = true
      } else if inScene {
        currentElements.append(element)
      }
      // Elements before the first sceneHeading are discarded
    }

    // Close the final scene
    if inScene && !currentElements.isEmpty {
      segments.append(SceneSegment(elements: currentElements))
    }

    return segments
  }
}
