import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantQueryExecutionParityTests {
  @Test
  func upstreamInstaQLSimpleWhereAndDeepRelationFilters() async throws {
    let fixture = try await UpstreamInstantFixture.zeneca()

    var source = instaQLSource("Simple Query Without Where")
    var users = await fixture.query(InstantQueryPlan(id: "users.simple", namespace: "users"))
    expectParityEqual(users.compactMap { $0.string("handle") }.sorted(), ["alex", "joe", "nicolegf", "stopa"], source)

    source = instaQLSource("Simple Where")
    users = await fixture.query(
      InstantQueryPlan(
        id: "users.where.handle",
        namespace: "users",
        filters: [.equals(field: "handle", value: .string("joe"))]
      )
    )
    expectParityEqual(users.compactMap { $0.string("handle") }.sorted(), ["joe"], source)

    source = instaQLSource("Simple Where with multiple clauses")
    users = await fixture.query(
      InstantQueryPlan(
        id: "users.where.deep-and-handle",
        namespace: "users",
        filters: [
          .equals(field: "bookshelves.books.title", value: .string("The Count of Monte Cristo")),
          .equals(field: "handle", value: .string("stopa")),
        ]
      )
    )
    expectParityEqual(users.compactMap { $0.string("handle") }.sorted(), ["stopa"], source)

    users = await fixture.query(
      InstantQueryPlan(
        id: "users.where.deep-and-handle-empty",
        namespace: "users",
        filters: [
          .equals(field: "bookshelves.books.title", value: .string("Title nobody has")),
          .equals(field: "handle", value: .string("stopa")),
        ]
      )
    )
    expectParityEqual(users.compactMap { $0.string("handle") }.sorted(), [], source)

    source = instaQLSource("Where in")
    users = await fixture.query(
      InstantQueryPlan(
        id: "users.where.in",
        namespace: "users",
        filters: [.in(field: "handle", values: [.string("stopa"), .string("joe")])]
      )
    )
    expectParityEqual(users.compactMap { $0.string("handle") }.sorted(), ["joe", "stopa"], source)

    source = instaQLSource("Where %like%")
    users = await fixture.query(
      InstantQueryPlan(
        id: "users.where.like",
        namespace: "users",
        filters: [.like(field: "handle", pattern: "%o%")]
      )
    )
    expectParityEqual(users.compactMap { $0.string("handle") }.sorted(), ["joe", "nicolegf", "stopa"], source)

    source = instaQLSource("Where like equality")
    users = await fixture.query(
      InstantQueryPlan(
        id: "users.where.like-equality",
        namespace: "users",
        filters: [.like(field: "handle", pattern: "joe")]
      )
    )
    expectParityEqual(users.compactMap { $0.string("handle") }.sorted(), ["joe"], source)

    source = instaQLSource("Where startsWith deep")
    users = await fixture.query(
      InstantQueryPlan(
        id: "users.where.deep-like-suffix",
        namespace: "users",
        filters: [.like(field: "bookshelves.books.title", pattern: "%Monte Cristo")]
      )
    )
    expectParityEqual(users.compactMap { $0.string("handle") }.sorted(), ["nicolegf", "stopa"], source)

    source = instaQLSource("Where endsWith deep")
    users = await fixture.query(
      InstantQueryPlan(
        id: "users.where.deep-like-prefix",
        namespace: "users",
        filters: [.like(field: "bookshelves.books.title", pattern: "Anti%")]
      )
    )
    expectParityEqual(users.compactMap { $0.string("handle") }.sorted(), ["alex", "nicolegf", "stopa"], source)
  }

  @Test
  func upstreamInstaQLCompoundOrFilters() async throws {
    let fixture = try await UpstreamInstantFixture.zeneca()
    let source = instaQLSource("Where OR test.each")

    let cases: [(String, [InstantQueryFilter], [String])] = [
      (
        "multiple OR matches",
        [.or([.equals(field: "handle", value: .string("stopa")), .equals(field: "handle", value: .string("joe"))])],
        ["joe", "stopa"]
      ),
      (
        "mix of matching and non-matching",
        [
          .or([
            .equals(field: "handle", value: .string("nobody")),
            .equals(field: "handle", value: .string("stopa")),
            .equals(field: "handle", value: .string("everybody")),
          ])
        ],
        ["stopa"]
      ),
      (
        "with and",
        [
          .equals(field: "bookshelves.books.title", value: .string("The Count of Monte Cristo")),
          .or([.equals(field: "handle", value: .string("joe")), .equals(field: "handle", value: .string("stopa"))]),
        ],
        ["stopa"]
      ),
      (
        "with references",
        [
          .or([
            .equals(field: "handle", value: .string("joe")),
            .and([
              .equals(field: "handle", value: .string("stopa")),
              .equals(field: "bookshelves.books.title", value: .string("The Count of Monte Cristo")),
            ]),
          ])
        ],
        ["joe", "stopa"]
      ),
      (
        "with references in both `or` & `and` clauses, no matches",
        [
          .equals(field: "bookshelves.books.title", value: .string("Unknown")),
          .or([
            .equals(field: "handle", value: .string("joe")),
            .and([
              .equals(field: "handle", value: .string("stopa")),
              .equals(field: "bookshelves.books.title", value: .string("The Count of Monte Cristo")),
            ]),
          ]),
        ],
        []
      ),
      (
        "with references in both `or` & `and` clauses, with matches",
        [
          .equals(field: "bookshelves.books.title", value: .string("A Promised Land")),
          .or([
            .and([
              .equals(field: "handle", value: .string("stopa")),
              .equals(field: "bookshelves.books.title", value: .string("The Count of Monte Cristo")),
            ]),
            .equals(field: "handle", value: .string("joe")),
          ]),
        ],
        ["joe"]
      ),
      (
        "with nested ors",
        [
          .or([
            .or([.equals(field: "handle", value: .string("stopa"))]),
            .equals(field: "handle", value: .string("joe")),
          ])
        ],
        ["joe", "stopa"]
      ),
      (
        "with ands in ors",
        [
          .or([
            .or([
              .and([
                .or([
                  .equals(field: "handle", value: .string("stopa")),
                  .equals(field: "handle", value: .string("joe")),
                ]),
                .equals(field: "email", value: .string("stopa@instantdb.com")),
              ])
            ]),
            .equals(field: "handle", value: .string("joe")),
          ])
        ],
        ["joe", "stopa"]
      ),
      (
        "with ands in ors in ands",
        [
          .and([
            .or([.and([.equals(field: "handle", value: .string("stopa"))])]),
            .or([.and([.or([.equals(field: "handle", value: .string("stopa"))])])]),
          ])
        ],
        ["stopa"]
      ),
    ]

    for testCase in cases {
      let users = await fixture.query(
        InstantQueryPlan(
          id: "users.where.or.\(testCase.0)",
          namespace: "users",
          filters: testCase.1
        )
      )
      expectParityEqual(users.compactMap { $0.string("handle") }.sorted(), testCase.2, "\(source) \(testCase.0)")
    }
  }

  @Test
  func upstreamInstaQLForwardAndReverseAssociations() async throws {
    let fixture = try await UpstreamInstantFixture.zeneca()

    var source = instaQLSource("Get association")
    var users = await fixture.query(
      InstantQueryPlan(
        id: "users.include.bookshelves",
        namespace: "users",
        filters: [.equals(field: "handle", value: .string("alex"))],
        includes: [InstantQueryInclude("bookshelves")]
      )
    )
    expectParityEqual(
      users.map { [$0.string("handle") ?? "", $0.linkedStrings("bookshelves", field: "name").sorted().joined(separator: ",")] },
      [["alex", "Nonfiction,Short Stories"]],
      source
    )

    source = instaQLSource("Get reverse association")
    let bookshelves = await fixture.query(
      InstantQueryPlan(
        id: "bookshelves.include.users",
        namespace: "bookshelves",
        filters: [.equals(field: "name", value: .string("Short Stories"))],
        includes: [InstantQueryInclude("users", direction: .reverse)]
      )
    )
    expectParityEqual(
      bookshelves.map { [$0.string("name") ?? "", $0.linkedStrings("users", field: "handle").sorted().joined(separator: ",")] },
      [["Short Stories", "alex"]],
      source
    )

    source = instaQLSource("Get deep association")
    users = await fixture.query(
      InstantQueryPlan(
        id: "users.include.deep-bookshelves-books",
        namespace: "users",
        filters: [.equals(field: "handle", value: .string("alex"))],
        includes: [
          InstantQueryInclude(
            "bookshelves",
            query: InstantQueryIncludePlan(
              id: "bookshelves.with-books",
              namespace: "bookshelves",
              includes: [InstantQueryInclude("books")]
            )
          )
        ]
      )
    )
    expectParityEqual(
      users.flatMap { $0.links?["bookshelves"] ?? [] }
        .flatMap { $0.linkedStrings("books", field: "title") },
      [
        "\"Surely You're Joking, Mr. Feynman!\": Adventures of a Curious Character",
        "\"What Do You Care What Other People Think?\": Further Adventures of a Curious Character",
        "The Spy and the Traitor",
        "Antifragile",
        "Atomic Habits",
        "Catch and Kill",
        "The Paper Menagerie and Other Stories",
        "Stories of Your Life and Others",
        "Aesop's Fables",
      ],
      source
    )

    source = instaQLSource("Nested wheres")
    users = await fixture.query(
      InstantQueryPlan(
        id: "users.include.filtered-bookshelves",
        namespace: "users",
        filters: [.equals(field: "handle", value: .string("alex"))],
        includes: [
          InstantQueryInclude(
            "bookshelves",
            query: InstantQueryIncludePlan(
              id: "bookshelves.short-stories",
              namespace: "bookshelves",
              filters: [.equals(field: "name", value: .string("Short Stories"))],
              includes: [InstantQueryInclude("books")]
            )
          )
        ]
      )
    )
    expectParityEqual(
      users.flatMap { $0.links?["bookshelves"] ?? [] }
        .flatMap { $0.linkedStrings("books", field: "title") },
      [
        "The Paper Menagerie and Other Stories",
        "Stories of Your Life and Others",
        "Aesop's Fables",
      ],
      source
    )

    source = instaQLSource("multiple connections")
    let shelfConnections = await fixture.query(
      InstantQueryPlan(
        id: "bookshelves.include.books-and-users",
        namespace: "bookshelves",
        filters: [.equals(field: "name", value: .string("Short Stories"))],
        includes: [
          InstantQueryInclude("books"),
          InstantQueryInclude("users", direction: .reverse),
        ]
      )
    )
    expectParityEqual(
      shelfConnections.map {
        [
          $0.string("name") ?? "",
          $0.linkedStrings("users", field: "handle").sorted().joined(separator: ","),
          $0.linkedStrings("books", field: "title").sorted().joined(separator: "|"),
        ]
      },
      [
        [
          "Short Stories",
          "alex",
          "Aesop's Fables|Stories of Your Life and Others|The Paper Menagerie and Other Stories",
        ]
      ],
      source
    )
  }

  @Test
  func upstreamInstaQLRelationFiltersWorkWithIDsAndLinkFields() async throws {
    let fixture = try await UpstreamInstantFixture.zeneca()

    var source = instaQLSource("query forward references work with and without id")
    let bookshelf = try #require(
      await fixture.query(
        InstantQueryPlan(
          id: "bookshelves.where.users.handle",
          namespace: "bookshelves",
          filters: [.equals(field: "users.handle", value: .string("stopa"))]
        )
      ).first
    )

    let usersByBookshelfID = await fixture.query(
      InstantQueryPlan(
        id: "users.where.bookshelves.id",
        namespace: "users",
        filters: [.equals(field: "bookshelves.id", value: .string(bookshelf.id))]
      )
    )
    let usersByBookshelfLinkField = await fixture.query(
      InstantQueryPlan(
        id: "users.where.bookshelves.ref",
        namespace: "users",
        filters: [.equals(field: "bookshelves", value: .ref(bookshelf.id))]
      )
    )
    expectParityEqual(usersByBookshelfID.compactMap { $0.string("handle") }, ["stopa"], source)
    expectParityEqual(usersByBookshelfLinkField.compactMap { $0.string("handle") }, ["stopa"], source)

    source = instaQLSource("query reverse references work with and without id")
    let stopa = try #require(
      await fixture.query(
        InstantQueryPlan(
          id: "users.where.handle.stopa",
          namespace: "users",
          filters: [.equals(field: "handle", value: .string("stopa"))]
        )
      ).first
    )
    let stopaBookshelvesByHandle = await fixture.query(
      InstantQueryPlan(
        id: "bookshelves.where.users.handle.stopa",
        namespace: "bookshelves",
        filters: [.equals(field: "users.handle", value: .string("stopa"))]
      )
    )
    let stopaBookshelvesByID = await fixture.query(
      InstantQueryPlan(
        id: "bookshelves.where.users.id.stopa",
        namespace: "bookshelves",
        filters: [.equals(field: "users.id", value: .string(stopa.id))]
      )
    )
    let stopaBookshelvesByLinkField = await fixture.query(
      InstantQueryPlan(
        id: "bookshelves.where.users.ref.stopa",
        namespace: "bookshelves",
        filters: [.equals(field: "users", value: .ref(stopa.id))]
      )
    )

    expectParityEqual(stopaBookshelvesByHandle.count, 16, source)
    expectParityEqual(stopaBookshelvesByHandle.map(bookshelfProjection), stopaBookshelvesByID.map(bookshelfProjection), source)
    expectParityEqual(stopaBookshelvesByHandle.map(bookshelfProjection), stopaBookshelvesByLinkField.map(bookshelfProjection), source)
  }
}

private let upstreamInstaQLTestSource =
  "upstream/instant/client/packages/core/__tests__/src/instaql.test.ts"

private func instaQLSource(_ testName: String) -> String {
  "\(upstreamInstaQLTestSource) \(testName)"
}

private func expectParityEqual<Value: Equatable>(
  _ actual: Value,
  _ expected: Value,
  _ source: String
) {
  #expect(
    actual == expected,
    """
    \(source)
    Actual: \(String(describing: actual))
    Expected: \(String(describing: expected))
    """
  )
}

private func bookshelfProjection(_ snapshot: InstantEntitySnapshot) -> [String] {
  [
    snapshot.id,
    snapshot.string("name") ?? "",
    snapshot.string("desc") ?? "",
    snapshot.valueDescription("order") ?? "",
  ]
}

private struct UpstreamInstantFixture {
  var store: InstantStore

  static func zeneca() async throws -> Self {
    try await Self.loadFixture(named: "zeneca")
  }

  func query(_ plan: InstantQueryPlan) async -> [InstantEntitySnapshot] {
    await store.materialize(plan)
  }

  private static func loadFixture(named name: String) async throws -> Self {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("upstream/instant/client/packages/core/__tests__/src/data")
      .appendingPathComponent(name)
    let attrsData = try Data(contentsOf: directory.appendingPathComponent("attrs.json"))
    let triplesData = try Data(contentsOf: directory.appendingPathComponent("triples.json"))
    let rawTriples = try #require(
      JSONSerialization.jsonObject(with: triplesData) as? [[Any]],
      "Expected upstream \(name) triples fixture to be an array."
    )
    let rawAttributes = try rawAttributeObjects(from: attrsData)
    let rawValuesByAttributeID = Dictionary(grouping: rawTriples) { rawTriple in
      rawTriple[safe: 1] as? String ?? ""
    }
    .mapValues { triples in triples.compactMap { $0[safe: 2] } }
    let attributes = try rawAttributes.map {
      try instantAttribute(from: $0, rawValues: rawValuesByAttributeID)
    }
    let attributesByID = Dictionary(uniqueKeysWithValues: attributes.map { ($0.id, $0) })
    let triples = try rawTriples.map {
      try instantTriple(from: $0, attributesByID: attributesByID)
    }
    return Self(store: InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes, triples: triples)))
  }

  private static func rawAttributeObjects(from data: Data) throws -> [[String: Any]] {
    let object = try JSONSerialization.jsonObject(with: data)
    if let array = object as? [[String: Any]] {
      return array.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
    }
    let dictionary = try #require(
      object as? [String: Any],
      "Expected upstream attrs fixture to be an array or object."
    )
    return dictionary.values
      .compactMap { $0 as? [String: Any] }
      .sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
  }

  private static func instantAttribute(
    from raw: [String: Any],
    rawValues: [String: [Any]]
  ) throws -> InstantAttribute {
    let id = try #require(raw["id"] as? String)
    let forwardIdentity = try identity(raw["forward-identity"])
    let reverseIdentity = try optionalIdentity(raw["reverse-identity"])
    let isRef = (raw["value-type"] as? String) == "ref"
    let name = forwardIdentity.name
    let namespace = forwardIdentity.namespace
    return InstantAttribute(
      id: id,
      namespace: namespace,
      name: name,
      valueType: isRef ? .ref : inferredValueType(rawValues[id] ?? []),
      isRequired: false,
      cardinality: (raw["cardinality"] as? String) == "many" ? .many : .one,
      isIndexed: raw["index?"] as? Bool ?? false,
      isUnique: raw["unique?"] as? Bool ?? false,
      forwardIdentity: "\(namespace)/\(name)",
      reverseIdentity: reverseIdentity.map { "\($0.namespace)/\($0.name)" },
      primaryKey: name == "id",
      linkNamespace: isRef ? reverseIdentity?.namespace : nil
    )
  }

  private static func identity(_ value: Any?) throws -> (namespace: String, name: String) {
    let values = try #require(value as? [Any])
    return (
      namespace: try #require(values[safe: 1] as? String),
      name: try #require(values[safe: 2] as? String)
    )
  }

  private static func optionalIdentity(_ value: Any?) throws -> (namespace: String, name: String)? {
    guard value != nil else { return nil }
    return try identity(value)
  }

  private static func inferredValueType(_ values: [Any]) -> InstantValueType {
    let values = values.filter { !($0 is NSNull) }
    if values.isEmpty { return .string }
    if values.contains(where: { $0 is [Any] || $0 is [String: Any] }) {
      return .json
    }
    if values.contains(where: { ($0 as? String) != nil }) {
      return .string
    }
    if values.allSatisfy({ ($0 as? NSNumber).map(isBooleanNumber) == true }) {
      return .boolean
    }
    if values.allSatisfy({ ($0 as? NSNumber).map { !isBooleanNumber($0) } == true }) {
      return .number
    }
    return .json
  }

  private static func instantTriple(
    from raw: [Any],
    attributesByID: [String: InstantAttribute]
  ) throws -> InstantTriple {
    let entityID = try #require(raw[safe: 0] as? String)
    let attributeID = try #require(raw[safe: 1] as? String)
    let attribute = attributesByID[attributeID]
    let value = try instantValue(raw[safe: 2] as Any, attribute: attribute)
    let txTime = (raw[safe: 3] as? NSNumber).map { Int64(truncating: $0) } ?? 0
    return InstantTriple(
      entityID: entityID,
      attributeID: attributeID,
      value: value,
      txID: "upstream-fixture",
      txTime: InstantTimestamp(milliseconds: txTime)
    )
  }

  private static func instantValue(_ value: Any, attribute: InstantAttribute?) throws -> InstantValue {
    if value is NSNull {
      return .null
    }
    if attribute?.valueType == .ref {
      return .ref(try #require(value as? String))
    }
    if let number = value as? NSNumber {
      if isBooleanNumber(number) {
        return .bool(number.boolValue)
      }
      return .number(number.doubleValue)
    }
    if let string = value as? String {
      return .string(string)
    }
    if let array = value as? [Any] {
      return .json(.array(try array.map(jsonValue)))
    }
    if let dictionary = value as? [String: Any] {
      return .json(.object(try dictionary.mapValues(jsonValue)))
    }
    throw InstantError(
      code: .validationFailed,
      operation: "load upstream fixture",
      message: "Unsupported upstream fixture value '\(value)'.",
      recovery: "Extend the parity fixture loader to decode this JSON shape."
    )
  }

  private static func jsonValue(_ value: Any) throws -> JSONValue {
    if value is NSNull {
      return .null
    }
    if let number = value as? NSNumber {
      if isBooleanNumber(number) {
        return .bool(number.boolValue)
      }
      return .number(number.doubleValue)
    }
    if let string = value as? String {
      return .string(string)
    }
    if let array = value as? [Any] {
      return .array(try array.map(jsonValue))
    }
    if let dictionary = value as? [String: Any] {
      return .object(try dictionary.mapValues(jsonValue))
    }
    throw InstantError(
      code: .validationFailed,
      operation: "load upstream fixture",
      message: "Unsupported upstream fixture JSON value '\(value)'.",
      recovery: "Extend the parity fixture loader to decode this JSON shape."
    )
  }
}

private extension InstantEntitySnapshot {
  func string(_ field: String) -> String? {
    guard case let .string(value) = values[field]?.first else { return nil }
    return value
  }

  func valueDescription(_ field: String) -> String? {
    values[field]?.first.map(String.init(describing:))
  }

  func linkedStrings(_ relation: String, field: String) -> [String] {
    links?[relation]?.compactMap { linked in
      guard case let .string(value) = linked.values[field]?.first else { return nil }
      return value
    } ?? []
  }
}

private extension InstantLinkedEntitySnapshot {
  func linkedStrings(_ relation: String, field: String) -> [String] {
    links?[relation]?.compactMap { linked in
      guard case let .string(value) = linked.values[field]?.first else { return nil }
      return value
    } ?? []
  }
}

private extension InstantMaterializedValue {
  var first: InstantValue? {
    values.first
  }
}

private extension Collection {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

private func isBooleanNumber(_ number: NSNumber) -> Bool {
  CFGetTypeID(number) == CFBooleanGetTypeID()
}
