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

    source = instaQLSource("Simple Where has expected keys")
    let joe = try #require(users.first)
    expectParityEqual(
      joe.materializedScalarKeysIncludingID,
      ["createdAt", "email", "fullName", "handle", "id"],
      "\(source) adapted: Swift snapshots expose id separately from materialized values."
    )

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

    source = instaQLSource("Deep where")
    users = await fixture.query(
      InstantQueryPlan(
        id: "users.where.deep-exact",
        namespace: "users",
        filters: [.equals(field: "bookshelves.books.title", value: .string("Aesop's Fables"))]
      )
    )
    expectParityEqual(users.compactMap { $0.string("handle") }, ["alex"], source)
  }

  @Test
  func upstreamInstaQLLikeAndAndFilterEdges() async throws {
    let fixture = try await UpstreamInstantFixture.zeneca()

    var source = instaQLSource("like case sensitivity")
    func fullNames(matching filter: InstantQueryFilter) async -> [String] {
      await fixture.query(
        InstantQueryPlan(
          id: "users.where.full-name-pattern",
          namespace: "users",
          filters: [filter]
        )
      )
      .compactMap { $0.string("fullName") }
      .sorted()
    }
    expectParityEqual(await fullNames(matching: .like(field: "fullName", pattern: "%O%")), [], source)
    expectParityEqual(
      await fullNames(matching: .iLike(field: "fullName", pattern: "%O%")),
      ["Joe Averbukh", "Nicole"],
      source
    )
    expectParityEqual(await fullNames(matching: .like(field: "fullName", pattern: "%j%")), [], source)
    expectParityEqual(await fullNames(matching: .iLike(field: "fullName", pattern: "%j%")), ["Joe Averbukh"], source)

    source = instaQLSource("like special regex characters")
    let specialCharacters: [(Character, String)] = [
      ("(", "Stopa (The Hacker)"),
      (")", "The Hacker (Stopa)"),
      ("[", "Stopa [Hacker]"),
      ("]", "[Hacker] Stopa"),
      ("{", "Stopa {Hacker}"),
      ("}", "{Hacker} Stopa"),
      ("*", "Stopa * Hacker"),
      ("+", "Stopa + Hacker"),
      ("?", "Stopa? Yes!"),
      ("^", "Stopa ^ Hacker"),
      ("$", "Stopa $ Hacker"),
      ("|", "Stopa | Hacker"),
      ("\\", "Stopa \\ Hacker"),
      (".", "Mr. Stopa"),
    ]
    for (character, fullName) in specialCharacters {
      let renamed = try await fixture.replacingUserFullName(handle: "stopa", with: fullName)
      let matches = await renamed.query(
        InstantQueryPlan(
          id: "users.where.full-name-special-\(character)",
          namespace: "users",
          filters: [.like(field: "fullName", pattern: "%\(character)%")]
        )
      )
      expectParityEqual(matches.first?.string("fullName"), fullName, "\(source) \(character)")
    }

    source = instaQLSource("Where and")
    let users = await fixture.query(
      InstantQueryPlan(
        id: "users.where.and",
        namespace: "users",
        filters: [
          .and([
            .equals(field: "bookshelves.books.title", value: .string("The Count of Monte Cristo")),
            .equals(field: "bookshelves.books.title", value: .string("Antifragile")),
          ])
        ]
      )
    )
    expectParityEqual(users.compactMap { $0.string("handle") }.sorted(), ["nicolegf", "stopa"], source)
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

    source = instaQLSource("Nested wheres with OR queries")
    users = await fixture.query(
      InstantQueryPlan(
        id: "users.include.filtered-bookshelves-or",
        namespace: "users",
        filters: [.equals(field: "handle", value: .string("alex"))],
        includes: [
          InstantQueryInclude(
            "bookshelves",
            query: InstantQueryIncludePlan(
              id: "bookshelves.short-stories-or",
              namespace: "bookshelves",
              filters: [.or([.equals(field: "name", value: .string("Short Stories"))])],
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

    source = instaQLSource("Nested wheres with AND queries")
    users = await fixture.query(
      InstantQueryPlan(
        id: "users.include.filtered-bookshelves-and",
        namespace: "users",
        filters: [.equals(field: "handle", value: .string("alex"))],
        includes: [
          InstantQueryInclude(
            "bookshelves",
            query: InstantQueryIncludePlan(
              id: "bookshelves.short-stories-and",
              namespace: "bookshelves",
              filters: [
                .and([
                  .equals(field: "name", value: .string("Short Stories")),
                  .equals(field: "order", value: .number(0)),
                ])
              ],
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
  func upstreamInstaQLMissingNamespacesAndAttributes() async throws {
    let fixture = try await UpstreamInstantFixture.zeneca()

    var source = instaQLSource("Missing etype")
    var snapshots = await fixture.query(InstantQueryPlan(id: "moopy.missing", namespace: "moopy"))
    expectParityEqual(snapshots.count, 0, source)

    source = instaQLSource("Missing inner etype")
    snapshots = await fixture.query(
      InstantQueryPlan(
        id: "users.include.missing-inner",
        namespace: "users",
        filters: [.equals(field: "handle", value: .string("joe"))],
        includes: [InstantQueryInclude("moopy")]
      )
    )
    expectParityEqual(
      snapshots.map { [$0.string("handle") ?? "", String($0.linkedCount("moopy"))] },
      [["joe", "0"]],
      "\(source) adapted: strict runtime validation rejects undeclared include targets, while raw materialization treats them as empty."
    )

    source = instaQLSource("Missing filter attr")
    snapshots = await fixture.query(
      InstantQueryPlan(
        id: "users.where.missing-filter-attr",
        namespace: "users",
        filters: [.equals(field: "bookshelves.moopy", value: .string("joe"))]
      )
    )
    expectParityEqual(snapshots.count, 0, source)
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

  @Test
  func upstreamInstaQLNamespaceIsolationAndObjectValues() async throws {
    let fixture = try await UpstreamInstantFixture.zeneca()
    let stopa = try #require(
      await fixture.query(
        InstantQueryPlan(
          id: "users.where.handle.stopa.namespace",
          namespace: "users",
          filters: [.equals(field: "handle", value: .string("stopa"))]
        )
      ).first
    )

    var source = instaQLSource("objects are created by etype")
    let notUsersEmail = fixtureAttribute(namespace: "not_users", name: "email", valueType: .string)
    let notUsers = try await fixture.transacting(
      attributes: [notUsersEmail],
      operations: [
        .insert(
          InstantTriple(
            entityID: stopa.id,
            attributeID: notUsersEmail.id,
            value: .string("this-should-not-change-users-stopa@gmail.com"),
            txID: "upstream-fixture-not-users",
            txTime: InstantTimestamp(milliseconds: 9_000_000_000_100)
          )
        )
      ]
    )
    let unchangedStopa = try #require(
      await notUsers.query(
        InstantQueryPlan(
          id: "users.where.handle.stopa.after-not-users",
          namespace: "users",
          filters: [.equals(field: "handle", value: .string("stopa"))]
        )
      ).first
    )
    expectParityEqual(unchangedStopa.string("email"), "stopa@instantdb.com", source)

    source = instaQLSource("object values")
    let jsonField = fixtureAttribute(namespace: "users", name: "jsonField", valueType: .json)
    let otherJsonField = fixtureAttribute(namespace: "users", name: "otherJsonField", valueType: .json)
    let objectValues = try await fixture.transacting(
      attributes: [jsonField, otherJsonField],
      operations: [
        .insert(
          InstantTriple(
            entityID: stopa.id,
            attributeID: jsonField.id,
            value: .json(.object(["hello": .string("world")])),
            txID: "upstream-fixture-object-values",
            txTime: InstantTimestamp(milliseconds: 9_000_000_000_200)
          )
        ),
        .insert(
          InstantTriple(
            entityID: stopa.id,
            attributeID: otherJsonField.id,
            value: .json(.object(["world": .string("hello")])),
            txID: "upstream-fixture-object-values",
            txTime: InstantTimestamp(milliseconds: 9_000_000_000_200)
          )
        ),
      ]
    )
    let objectStopa = try #require(
      await objectValues.query(
        InstantQueryPlan(
          id: "users.where.handle.stopa.object-values",
          namespace: "users",
          filters: [.equals(field: "handle", value: .string("stopa"))]
        )
      ).first
    )
    expectParityEqual(
      objectStopa.values["jsonField"]?.first,
      .json(.object(["hello": .string("world")])),
      source
    )
  }

  @Test
  func upstreamInstaQLPaginationOrderingAndFields() async throws {
    let fixture = try await UpstreamInstantFixture.zeneca()

    var source = instaQLSource("pagination limit")
    var books = await fixture.query(
      InstantQueryPlan(id: "books.limit", namespace: "books", limit: 10)
    )
    expectParityEqual(books.count, 10, source)

    source = instaQLSource("pagination last")
    books = await fixture.query(
      InstantQueryPlan(id: "books.last", namespace: "books", last: 10)
    )
    expectParityEqual(books.count, 10, source)

    source = instaQLSource("pagination first")
    books = await fixture.query(
      InstantQueryPlan(id: "books.first", namespace: "books", first: 10)
    )
    expectParityEqual(books.count, 10, source)

    source = instaQLSource("arbitrary ordering")
    books = await fixture.query(
      InstantQueryPlan(
        id: "books.title-ascending",
        namespace: "books",
        order: InstantQueryOrder("title", .ascending),
        first: 10
      )
    )
    expectParityEqual(
      books.compactMap { $0.string("title") },
      [
        "\"Surely You're Joking, Mr. Feynman!\": Adventures of a Curious Character",
        "\"What Do You Care What Other People Think?\": Further Adventures of a Curious Character",
        "12 Rules for Life",
        "1984",
        "21 Lessons for the 21st Century",
        "A Conflict of Visions",
        "A Damsel in Distress",
        "A Guide to the Good Life",
        "A Hero Of Our Time",
        "A History of Private Life: From pagan Rome to Byzantium",
      ],
      source
    )

    source = instaQLSource("arbitrary ordering with dates")
    let field = fixtureAttribute(namespace: "tests", name: "field", valueType: .number)
    let date = fixtureAttribute(namespace: "tests", name: "date", valueType: .date)
    let num = fixtureAttribute(namespace: "tests", name: "num", valueType: .number)
    var dateOrderingOperations: [InstantTripleOperation] = []
    for value in (-5)..<5 {
      let triples = [
        testTriple("test-date-\(value)", field, .number(Double(value + 5)), value + 5),
        testTriple("test-date-\(value)", date, .number(Double(value)), value + 5),
        testTriple("test-date-\(value)", num, .number(Double(value)), value + 5),
      ]
      dateOrderingOperations.append(contentsOf: triples.map(InstantTripleOperation.insert))
    }
    let nullAndMissingOrderingTriples = [
      testTriple("00000000-0000-0000-0000-000000000000", field, .number(10), 10),
      testTriple("00000000-0000-0000-0000-000000000000", date, .null, 10),
      testTriple("00000000-0000-0000-0000-000000000000", num, .null, 10),
      testTriple("00000000-0000-0000-0000-000000000001", field, .number(11), 11),
      testTriple("00000000-0000-0000-0000-000000000002", field, .number(12), 12),
      testTriple("00000000-0000-0000-0000-000000000002", date, .null, 12),
      testTriple("00000000-0000-0000-0000-000000000002", num, .null, 12),
      testTriple("00000000-0000-0000-0000-000000000003", field, .number(13), 13),
    ]
    dateOrderingOperations.append(
      contentsOf: nullAndMissingOrderingTriples.map(InstantTripleOperation.insert)
    )
    let dateOrderingFixture = try await fixture.transacting(
      attributes: [field, date, num],
      operations: dateOrderingOperations
    )
    let orderingDescExpected = [
      "4", "3", "2", "1", "0", "-1", "-2", "-3", "-4", "-5",
      "undefined", "null", "undefined", "null",
    ]
    let orderingAscExpected = [
      "null", "undefined", "null", "undefined",
      "-5", "-4", "-3", "-2", "-1", "0", "1", "2", "3", "4",
    ]
    expectParityEqual(
      await dateOrderingFixture.query(
        InstantQueryPlan(id: "tests.date.desc", namespace: "tests", order: InstantQueryOrder("date", .descending))
      ).map { $0.orderingValueDescription("date") },
      orderingDescExpected,
      "\(source) date desc"
    )
    expectParityEqual(
      await dateOrderingFixture.query(
        InstantQueryPlan(id: "tests.num.desc", namespace: "tests", order: InstantQueryOrder("num", .descending))
      ).map { $0.orderingValueDescription("num") },
      orderingDescExpected,
      "\(source) number desc"
    )
    expectParityEqual(
      await dateOrderingFixture.query(
        InstantQueryPlan(id: "tests.date.asc", namespace: "tests", order: InstantQueryOrder("date", .ascending))
      ).map { $0.orderingValueDescription("date") },
      orderingAscExpected,
      "\(source) date asc"
    )
    expectParityEqual(
      await dateOrderingFixture.query(
        InstantQueryPlan(id: "tests.num.asc", namespace: "tests", order: InstantQueryOrder("num", .ascending))
      ).map { $0.orderingValueDescription("num") },
      orderingAscExpected,
      "\(source) number asc"
    )

    source = instaQLSource("arbitrary ordering with strings")
    let string = fixtureAttribute(namespace: "string_tests", name: "string", valueType: .string)
    let stringValues = ["10", "2", "a0", "Zz"]
    let stringOrderingFixture = try await fixture.transacting(
      attributes: [string],
      operations: stringValues.enumerated().map { index, value in
        .insert(testTriple("test-string-\(index)", string, .string(value), index))
      }
    )
    expectParityEqual(
      await stringOrderingFixture.query(
        InstantQueryPlan(
          id: "string-tests.asc",
          namespace: "string_tests",
          order: InstantQueryOrder("string", .ascending)
        )
      ).map { $0.string("string") ?? "<missing>" },
      stringValues,
      "\(source) asc"
    )
    expectParityEqual(
      await stringOrderingFixture.query(
        InstantQueryPlan(
          id: "string-tests.desc",
          namespace: "string_tests",
          order: InstantQueryOrder("string", .descending)
        )
      ).map { $0.string("string") ?? "<missing>" },
      Array(stringValues.reversed()),
      "\(source) desc"
    )

    let caseString = fixtureAttribute(namespace: "case_string_tests", name: "string", valueType: .string)
    let caseStringValues = ["a", "A", "b", "B"]
    let caseStringOrderingFixture = try await fixture.transacting(
      attributes: [caseString],
      operations: caseStringValues.enumerated().map { index, value in
        .insert(testTriple("test-case-string-\(index)", caseString, .string(value), index))
      }
    )
    expectParityEqual(
      await caseStringOrderingFixture.query(
        InstantQueryPlan(
          id: "case-string-tests.asc",
          namespace: "case_string_tests",
          order: InstantQueryOrder("string", .ascending)
        )
      ).map { $0.string("string") ?? "<missing>" },
      caseStringValues,
      "\(source) en-US case-only asc"
    )
    expectParityEqual(
      await caseStringOrderingFixture.query(
        InstantQueryPlan(
          id: "case-string-tests.desc",
          namespace: "case_string_tests",
          order: InstantQueryOrder("string", .descending)
        )
      ).map { $0.string("string") ?? "<missing>" },
      Array(caseStringValues.reversed()),
      "\(source) en-US case-only desc"
    )

    source = instaQLSource("fields")
    let users = await fixture.query(
      InstantQueryPlan(
        id: "users.fields.handle",
        namespace: "users",
        selectedFields: ["handle"]
      )
    )
    expectParityEqual(
      users.map { [$0.id, $0.string("handle") ?? "", $0.values.keys.sorted().joined(separator: ",")] },
      [
        ["ce942051-2d74-404a-9c7d-4aa3f2d54ae4", "joe", "handle"],
        ["ad45e100-777a-4de8-8978-aa13200a4824", "alex", "handle"],
        ["a55a5231-5c4d-4033-b859-7790c45c22d5", "stopa", "handle"],
        ["0f3d67fc-8b37-4b03-ac47-29fec4edc4f7", "nicolegf", "handle"],
      ],
      "\(source) top-level selected fields"
    )

    let alex = await fixture.query(
      InstantQueryPlan(
        id: "users.fields.handle.with-bookshelves",
        namespace: "users",
        filters: [.equals(field: "handle", value: .string("alex"))],
        selectedFields: ["handle"],
        includes: [
          InstantQueryInclude(
            "bookshelves",
            query: InstantQueryIncludePlan(
              id: "bookshelves.fields.name",
              namespace: "bookshelves",
              selectedFields: ["name"]
            )
          )
        ]
      )
    )
    expectParityEqual(
      alex.map {
        [
          $0.id,
          $0.values.keys.sorted().joined(separator: ","),
          ($0.links?["bookshelves"] ?? [])
            .map { "\($0.id):\($0.values.keys.sorted().joined(separator: ",")):\($0.string("name") ?? "")" }
            .sorted()
            .joined(separator: "|"),
        ]
      },
      [
        [
          "ad45e100-777a-4de8-8978-aa13200a4824",
          "handle",
          "4ad10e00-1353-437e-9fee-2a89eb53575d:name:Short Stories|8164fb78-6fa3-4aab-8b92-80e706bae93a:name:Nonfiction",
        ]
      ],
      "\(source) nested selected fields"
    )
  }

  @Test
  func upstreamInstaQLNullNotEqualsAndComparators() async throws {
    let fixture = try await UpstreamInstantFixture.zeneca()

    var source = instaQLSource("$isNull")
    let booksTitleIsNull = InstantQueryPlan(
      id: "books.where.title-is-null",
      namespace: "books",
      filters: [.isNull(field: "title")]
    )
    var books = await fixture.query(booksTitleIsNull)
    expectParityEqual(books.count, 0, source)

    let title = try #require(fixture.attribute(namespace: "books", name: "title"))
    let pageCount = try #require(fixture.attribute(namespace: "books", name: "pageCount"))
    let booksWithNulls = try await fixture.transacting(
      operations: [
        .insert(
          InstantTriple(
            entityID: "fixture-book-null-title",
            attributeID: title.id,
            value: .null,
            txID: "upstream-fixture-null-books",
            txTime: InstantTimestamp(milliseconds: 9_000_000_000_300)
          )
        ),
        .insert(
          InstantTriple(
            entityID: "fixture-book-missing-title",
            attributeID: pageCount.id,
            value: .number(20),
            txID: "upstream-fixture-null-books",
            txTime: InstantTimestamp(milliseconds: 9_000_000_000_301)
          )
        ),
      ]
    )
    books = await booksWithNulls.query(booksTitleIsNull)
    expectParityEqual(books.map { $0.values["title"]?.first }, [.null, nil], source)

    source = instaQLSource("$isNull with relations")
    let usersWithoutShelves = InstantQueryPlan(
      id: "users.where.bookshelves-is-null",
      namespace: "users",
      filters: [.isNull(field: "bookshelves")]
    )
    var users = await fixture.query(usersWithoutShelves)
    expectParityEqual(users.count, 0, source)
    let handle = try #require(fixture.attribute(namespace: "users", name: "handle"))
    let usersWithLonelyUser = try await fixture.transacting(
      operations: [
        .insert(
          InstantTriple(
            entityID: "fixture-user-dww",
            attributeID: handle.id,
            value: .string("dww"),
            txID: "upstream-fixture-null-relations",
            txTime: InstantTimestamp(milliseconds: 9_000_000_000_302)
          )
        )
      ]
    )
    users = await usersWithLonelyUser.query(usersWithoutShelves)
    expectParityEqual(users.map { $0.string("handle") ?? "<missing>" }, ["dww"], source)

    let monteCristo = try #require(
      await fixture.query(
        InstantQueryPlan(
          id: "books.where.title.monte-cristo",
          namespace: "books",
          filters: [.equals(field: "title", value: .string("The Count of Monte Cristo"))]
        )
      ).first
    )
    let usersWithBook = await fixture.query(
      InstantQueryPlan(
        id: "users.where.bookshelves.books.title.monte-cristo",
        namespace: "users",
        filters: [.equals(field: "bookshelves.books.title", value: .string("The Count of Monte Cristo"))]
      )
    )
    let usersWithNullTitleBook = try await usersWithLonelyUser.transacting(
      operations: [
        .merge(
          InstantTriple(
            entityID: monteCristo.id,
            attributeID: title.id,
            value: .null,
            txID: "upstream-fixture-null-relations",
            txTime: InstantTimestamp(milliseconds: 9_000_000_000_303)
          )
        )
      ]
    )
    users = await usersWithNullTitleBook.query(
      InstantQueryPlan(
        id: "users.where.bookshelves.books.title-is-null",
        namespace: "users",
        filters: [.isNull(field: "bookshelves.books.title")]
      )
    )
    expectParityEqual(
      users.map { $0.string("handle") ?? "<missing>" },
      usersWithBook.map { $0.string("handle") ?? "<missing>" } + ["dww"],
      source
    )

    source = instaQLSource("$isNull with reverse relations")
    let shelvesWithoutUsers = InstantQueryPlan(
      id: "bookshelves.where.users-id-is-null",
      namespace: "bookshelves",
      filters: [.isNull(field: "users.id")],
      includes: [InstantQueryInclude("users", direction: .reverse)]
    )
    var bookshelves = await fixture.query(shelvesWithoutUsers)
    expectParityEqual(bookshelves.count, 0, source)
    let shelfName = try #require(fixture.attribute(namespace: "bookshelves", name: "name"))
    let lonelyShelfFixture = try await fixture.transacting(
      operations: [
        .insert(
          InstantTriple(
            entityID: "fixture-lonely-shelf",
            attributeID: shelfName.id,
            value: .string("Lonely shelf"),
            txID: "upstream-fixture-null-reverse-relations",
            txTime: InstantTimestamp(milliseconds: 9_000_000_000_304)
          )
        )
      ]
    )
    bookshelves = await lonelyShelfFixture.query(shelvesWithoutUsers)
    expectParityEqual(bookshelves.map { $0.string("name") ?? "<missing>" }, ["Lonely shelf"], source)

    source = instaQLSource("$not and $ne")
    let val = fixtureAttribute(namespace: "tests", name: "val", valueType: .string)
    let undefinedVal = fixtureAttribute(namespace: "tests", name: "undefinedVal", valueType: .string)
    let notEqualsFixture = try await fixture.transacting(
      attributes: [val, undefinedVal],
      operations: [
        testTriple("test-ne-a", val, .string("a"), 0),
        testTriple("test-ne-b", val, .string("b"), 1),
        testTriple("test-ne-c", val, .string("c"), 2),
        testTriple("test-ne-null", val, .null, 3),
        testTriple("test-ne-missing", undefinedVal, .string("d"), 4),
      ].map(InstantTripleOperation.insert)
    )
    let notEquals = await notEqualsFixture.query(
      InstantQueryPlan(
        id: "tests.where.val-ne-a",
        namespace: "tests",
        filters: [.notEquals(field: "val", value: .string("a"))]
      )
    )
    expectParityEqual(
      notEquals.map { $0.values["val"]?.first },
      [.string("b"), .string("c"), .null, nil],
      "\(source) adapted: Swift represents both upstream $not and $ne with InstantQueryFilter.notEquals."
    )

    source = instaQLSource("comparators")
    let string = fixtureAttribute(namespace: "comparators", name: "string", valueType: .string)
    let number = fixtureAttribute(namespace: "comparators", name: "number", valueType: .number)
    let date = fixtureAttribute(namespace: "comparators", name: "date", valueType: .date)
    let boolean = fixtureAttribute(namespace: "comparators", name: "boolean", valueType: .boolean)
    let comparators = try await fixture.transacting(
      attributes: [string, number, date, boolean],
      operations: (0..<5).flatMap { value in
        [
          testTriple("test-comparator-\(value)", string, .string("\(value)"), value),
          testTriple("test-comparator-\(value)", number, .number(Double(value)), value),
          testTriple(
            "test-comparator-\(value)",
            date,
            .date(Date(timeIntervalSince1970: Double(value))),
            value
          ),
          testTriple("test-comparator-\(value)", boolean, .bool(value.isMultiple(of: 2)), value),
        ].map(InstantTripleOperation.insert)
      }
    )

    func values(
      _ field: String,
      _ filter: InstantQueryFilter
    ) async -> [InstantValue?] {
      await comparators.query(
        InstantQueryPlan(
          id: "comparators.\(field)",
          namespace: "comparators",
          filters: [filter]
        )
      )
      .map { $0.values[field]?.first }
    }

    expectParityEqual(await values("string", .greaterThan(field: "string", value: .string("2"))), [.string("3"), .string("4")], source)
    expectParityEqual(await values("string", .greaterThanOrEqual(field: "string", value: .string("2"))), [.string("2"), .string("3"), .string("4")], source)
    expectParityEqual(await values("string", .lessThan(field: "string", value: .string("2"))), [.string("0"), .string("1")], source)
    expectParityEqual(await values("string", .lessThanOrEqual(field: "string", value: .string("2"))), [.string("0"), .string("1"), .string("2")], source)

    expectParityEqual(await values("number", .greaterThan(field: "number", value: .number(2))), [.number(3), .number(4)], source)
    expectParityEqual(await values("number", .greaterThanOrEqual(field: "number", value: .number(2))), [.number(2), .number(3), .number(4)], source)
    expectParityEqual(await values("number", .lessThan(field: "number", value: .number(2))), [.number(0), .number(1)], source)
    expectParityEqual(await values("number", .lessThanOrEqual(field: "number", value: .number(2))), [.number(0), .number(1), .number(2)], source)

    expectParityEqual(
      await values("date", .greaterThan(field: "date", value: .date(Date(timeIntervalSince1970: 2)))),
      [.date(Date(timeIntervalSince1970: 3)), .date(Date(timeIntervalSince1970: 4))],
      source
    )
    expectParityEqual(
      await values("date", .greaterThanOrEqual(field: "date", value: .date(Date(timeIntervalSince1970: 2)))),
      [.date(Date(timeIntervalSince1970: 2)), .date(Date(timeIntervalSince1970: 3)), .date(Date(timeIntervalSince1970: 4))],
      source
    )
    expectParityEqual(
      await values("date", .lessThan(field: "date", value: .date(Date(timeIntervalSince1970: 2)))),
      [.date(Date(timeIntervalSince1970: 0)), .date(Date(timeIntervalSince1970: 1))],
      source
    )
    expectParityEqual(
      await values("date", .lessThanOrEqual(field: "date", value: .date(Date(timeIntervalSince1970: 2)))),
      [.date(Date(timeIntervalSince1970: 0)), .date(Date(timeIntervalSince1970: 1)), .date(Date(timeIntervalSince1970: 2))],
      source
    )
    expectParityEqual(
      await values("date", .lessThan(field: "date", value: .string("2026-01-01T00:00:00.000Z"))),
      [
        .date(Date(timeIntervalSince1970: 0)),
        .date(Date(timeIntervalSince1970: 1)),
        .date(Date(timeIntervalSince1970: 2)),
        .date(Date(timeIntervalSince1970: 3)),
        .date(Date(timeIntervalSince1970: 4)),
      ],
      "\(source) accepts string dates"
    )
    expectParityEqual(
      await values("date", .greaterThan(field: "date", value: .string("2026-01-01T00:00:00.000Z"))),
      [],
      "\(source) accepts string dates"
    )

    expectParityEqual(await values("boolean", .greaterThan(field: "boolean", value: .bool(true))), [], source)
    expectParityEqual(await values("boolean", .greaterThanOrEqual(field: "boolean", value: .bool(true))), [.bool(true), .bool(true), .bool(true)], source)
    expectParityEqual(await values("boolean", .lessThan(field: "boolean", value: .bool(true))), [.bool(false), .bool(false)], source)
    expectParityEqual(await values("boolean", .lessThanOrEqual(field: "boolean", value: .bool(true))), [.bool(true), .bool(false), .bool(true), .bool(false), .bool(true)], source)
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
  var attributes: [InstantAttribute]

  static func zeneca() async throws -> Self {
    try await Self.loadFixture(named: "zeneca")
  }

  func query(_ plan: InstantQueryPlan) async -> [InstantEntitySnapshot] {
    await store.materialize(plan)
  }

  func attribute(namespace: String, name: String) -> InstantAttribute? {
    attributes.first { $0.namespace == namespace && $0.name == name }
  }

  func transacting(
    attributes extraAttributes: [InstantAttribute] = [],
    operations: [InstantTripleOperation]
  ) async throws -> Self {
    let snapshot = await store.snapshot()
    let mergedAttributes = mergeAttributes(self.attributes, extraAttributes)
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: mergedAttributes,
        triples: snapshot.triples
      )
    )
    _ = try await store.prepare(
      InstantStoreTransaction(
        id: "upstream-fixture-transaction-\(abs(operations.hashValue))",
        operations: operations
      )
    )
    return Self(store: store, attributes: mergedAttributes)
  }

  func replacingUserFullName(handle: String, with fullName: String) async throws -> Self {
    let user = try #require(
      await query(
        InstantQueryPlan(
          id: "users.rename-source.\(handle)",
          namespace: "users",
          filters: [.equals(field: "handle", value: .string(handle))]
        )
      ).first
    )
    let fullNameAttribute = try #require(
      attributes.first { $0.namespace == "users" && $0.name == "fullName" }
    )
    let snapshot = await store.snapshot()
    let store = InstantStore(snapshot: snapshot)
    let txID = "upstream-fixture-rename-\(handle)"
    _ = try await store.prepare(
      InstantStoreTransaction(
        id: txID,
        operations: [
          .merge(
            InstantTriple(
              entityID: user.id,
              attributeID: fullNameAttribute.id,
              value: .string(fullName),
              txID: txID,
              txTime: InstantTimestamp(milliseconds: 9_000_000_000_000)
            )
          )
        ]
      )
    )
    return Self(store: store, attributes: attributes)
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
    return Self(
      store: InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes, triples: triples)),
      attributes: attributes
    )
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

private func fixtureAttribute(
  namespace: String,
  name: String,
  valueType: InstantValueType,
  cardinality: InstantCardinality = .one,
  isIndexed: Bool = true
) -> InstantAttribute {
  InstantAttribute(
    id: "\(namespace)/\(name)",
    namespace: namespace,
    name: name,
    valueType: valueType,
    cardinality: cardinality,
    isIndexed: isIndexed,
    forwardIdentity: "\(namespace)/\(name)"
  )
}

private func mergeAttributes(
  _ existing: [InstantAttribute],
  _ additional: [InstantAttribute]
) -> [InstantAttribute] {
  Array(
    Dictionary(uniqueKeysWithValues: (existing + additional).map { ($0.id, $0) })
      .values
  )
  .sorted { $0.id < $1.id }
}

private func testTriple(
  _ entityID: String,
  _ attribute: InstantAttribute,
  _ value: InstantValue,
  _ offset: Int
) -> InstantTriple {
  InstantTriple(
    entityID: entityID,
    attributeID: attribute.id,
    value: value,
    txID: "upstream-fixture-\(attribute.namespace)",
    txTime: InstantTimestamp(milliseconds: 9_100_000_000_000 + Int64(offset))
  )
}

private extension InstantEntitySnapshot {
  var materializedScalarKeysIncludingID: [String] {
    Array(values.filter { !$0.value.containsRef }.keys).appending("id").sorted()
  }

  func string(_ field: String) -> String? {
    guard case let .string(value) = values[field]?.first else { return nil }
    return value
  }

  func valueDescription(_ field: String) -> String? {
    values[field]?.first.map(String.init(describing:))
  }

  func orderingValueDescription(_ field: String) -> String {
    switch values[field]?.first {
    case nil:
      return "undefined"
    case .null:
      return "null"
    case let .number(value):
      return String(format: "%.0f", value)
    case let .date(value):
      return String(format: "%.0f", value.timeIntervalSince1970 * 1000)
    case let .string(value):
      return value
    case let .bool(value):
      return String(value)
    case let .json(value):
      return String(describing: value)
    case let .ref(value):
      return value
    case let .lookupRef(value):
      return String(describing: value)
    }
  }

  func linkedStrings(_ relation: String, field: String) -> [String] {
    links?[relation]?.compactMap { linked in
      guard case let .string(value) = linked.values[field]?.first else { return nil }
      return value
    } ?? []
  }

  func linkedCount(_ relation: String) -> Int {
    links?[relation]?.count ?? 0
  }
}

private extension InstantLinkedEntitySnapshot {
  func string(_ field: String) -> String? {
    guard case let .string(value) = values[field]?.first else { return nil }
    return value
  }

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

  var containsRef: Bool {
    values.contains {
      guard case .ref = $0 else { return false }
      return true
    }
  }
}

private extension Collection {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

private extension Array {
  func appending(_ element: Element) -> [Element] {
    self + [element]
  }
}

private func isBooleanNumber(_ number: NSNumber) -> Bool {
  CFGetTypeID(number) == CFBooleanGetTypeID()
}
