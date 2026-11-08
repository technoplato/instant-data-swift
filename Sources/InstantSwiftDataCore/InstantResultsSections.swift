// History:
// - 2026-11-08: created (ADR 0015 L3, #2005): rows grouped into named sections once per emission, the counterpart of
//   SQLiteData's `ResultsSectionCollection`, so a view never groups in its body and nothing keeps a grouping in sync.

/// A collection of rows grouped into sections, the counterpart of SQLiteData's `ResultsSectionCollection`
/// (ADR 0015 L3).
///
/// You do not create one directly. A fetch request groups its rows with `InstantFetchRequest.sectioned(by:)`, and a
/// `@Fetch` property observes the result, regrouped once each time the rows change:
///
/// ```swift
/// ForEach(sections) { section in
///   Section(section.name) {
///     ForEach(section) { row in Text(row.title) }
///   }
/// }
/// ```
public struct InstantResultsSectionCollection<Element, SectionName: Hashable> {
  private var sections: [InstantResultsSection<Element, SectionName>]
  private var indexByName: [SectionName: Int]

  /// Creates an empty collection of sections.
  public init() {
    self.sections = []
    self.indexByName = [:]
  }

  /// Groups `elements` by `sectionName`, in the order each section's first element appears; each section keeps its
  /// elements' order.
  package init(grouping elements: some Sequence<Element>, by sectionName: (Element) -> SectionName) {
    var sections: [InstantResultsSection<Element, SectionName>] = []
    var indexByName: [SectionName: Int] = [:]
    for element in elements.prefix(0) {  // red: grouping is not written yet
      let name = sectionName(element)
      if let index = indexByName[name] {
        sections[index].elements.append(element)
      } else {
        indexByName[name] = sections.count
        sections.append(InstantResultsSection(name: name, elements: [element]))
      }
    }
    self.sections = sections
    self.indexByName = indexByName
  }

  /// The names of each section in the collection, in the order the sections appear.
  public var sectionNames: [SectionName] {
    sections.map(\.name)
  }

  /// Returns the section with the given name, or `nil` if no such section exists.
  public subscript(sectionName name: SectionName) -> InstantResultsSection<Element, SectionName>? {
    indexByName[name].map { sections[$0] }
  }

  /// Returns whether or not the collection contains a section with the given name.
  public func contains(sectionName name: SectionName) -> Bool {
    indexByName[name] != nil
  }

  /// Returns the position of the section with the given name, or `nil` if no such section exists.
  public func index(ofSectionNamed name: SectionName) -> Int? {
    indexByName[name]
  }
}

extension InstantResultsSectionCollection where SectionName: Comparable {
  package func sortedByName(_ order: InstantQuerySortDirection) -> Self {
    var sorted = self
    switch order {
    case .ascending:
      sorted.sections.sort { $0.name < $1.name }
    case .descending:
      sorted.sections.sort { $0.name > $1.name }
    }
    sorted.indexByName = Dictionary(
      uniqueKeysWithValues: sorted.sections.enumerated().map { ($0.element.name, $0.offset) }
    )
    return sorted
  }
}

extension InstantResultsSectionCollection: RandomAccessCollection {
  public var startIndex: Int { sections.startIndex }
  public var endIndex: Int { sections.endIndex }
  public subscript(position: Int) -> InstantResultsSection<Element, SectionName> { sections[position] }
}

extension InstantResultsSectionCollection: Sendable where Element: Sendable, SectionName: Sendable {}

extension InstantResultsSectionCollection: Equatable where Element: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.sections == rhs.sections
  }
}

/// The rows of one section, identified by the section's name (ADR 0015 L3). See ``InstantResultsSectionCollection``.
public struct InstantResultsSection<Element, SectionName: Hashable>: Identifiable {
  /// The name of the section: the value every element in it shares.
  public let name: SectionName
  var elements: [Element]

  init(name: SectionName, elements: [Element]) {
    self.name = name
    self.elements = elements
  }

  /// The identity of the section, equivalent to its ``name``.
  public var id: SectionName { name }
}

extension InstantResultsSection: RandomAccessCollection {
  public var startIndex: Int { elements.startIndex }
  public var endIndex: Int { elements.endIndex }
  public subscript(position: Int) -> Element { elements[position] }
}

extension InstantResultsSection: Sendable where Element: Sendable, SectionName: Sendable {}

extension InstantResultsSection: Equatable where Element: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.name == rhs.name && lhs.elements == rhs.elements
  }
}
