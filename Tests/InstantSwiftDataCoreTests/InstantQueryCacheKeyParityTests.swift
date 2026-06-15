import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite
struct InstantQueryCacheKeyParityTests {
  @Test
  func upstreamWeakHashIntegerVaryingQueriesAvoidCollisions() {
    let source = weakHashSource(
      "no collisions across many integer-varying queries "
        + "[adapted: upstream skips the 50,000-case stress in CI; Swift cache keys are canonical plan payloads.]"
    )
    let taggedID = "b14fae2f-ce9b-4677-b6a9-6dddd81914d0"
    let shapes: [(label: String, makePlan: (Int) -> InstantQueryPlan)] = [
      (
        "users by id",
        { i in
          InstantQueryPlan(
            id: "users.by-id",
            namespace: "users",
            filters: [.equals(field: "id", value: .number(Double(i)))]
          )
        }
      ),
      (
        "posts by author",
        { i in
          InstantQueryPlan(
            id: "posts.by-author",
            namespace: "posts",
            filters: [.equals(field: "authorId", value: .number(Double(i)))],
            includes: [InstantQueryInclude("author")]
          )
        }
      ),
      (
        "items by tag and n",
        { i in
          InstantQueryPlan(
            id: "items.by-tag-and-n",
            namespace: "items",
            filters: [
              .equals(field: "tag", value: .string(taggedID)),
              .equals(field: "n", value: .number(Double(i))),
            ]
          )
        }
      ),
    ]

    for shape in shapes {
      var cacheKeys: Set<String> = []
      for i in 0..<512 {
        let cacheKey = shape.makePlan(i).cacheKey
        #expect(cacheKeys.insert(cacheKey).inserted, "\(source) \(shape.label) collision at i=\(i)")
      }
      expectNoDifference(cacheKeys.count, 512, "\(source) \(shape.label)")
    }
  }

  @Test
  func upstreamWeakHashCanonicalQueryShapeInvariants() {
    let selectedFieldsSource = weakHashSource(
      "is stable across object key order and undefined values "
        + "[adapted: Swift selected fields are normalized because there is no undefined value.]"
    )
    let selectedFieldsPlan = InstantQueryPlan(
      id: "users.selected",
      namespace: "users",
      selectedFields: ["name", "email", "email"]
    )
    let reorderedSelectedFieldsPlan = InstantQueryPlan(
      id: "users.selected",
      namespace: "users",
      selectedFields: ["email", "name"]
    )

    expectNoDifference(selectedFieldsPlan.selectedFields, ["email", "name"], selectedFieldsSource)
    expectNoDifference(
      selectedFieldsPlan.cacheKey,
      reorderedSelectedFieldsPlan.cacheKey,
      selectedFieldsSource
    )

    let jsonObjectSource = weakHashSource("is stable across object key order and undefined values")
    let jsonObjectPlan = InstantQueryPlan(
      id: "items.json",
      namespace: "items",
      filters: [
        .equals(
          field: "payload",
          value: .json(.object(["b": .number(2), "a": .number(1)]))
        )
      ]
    )
    let reorderedJSONObjectPlan = InstantQueryPlan(
      id: "items.json",
      namespace: "items",
      filters: [
        .equals(
          field: "payload",
          value: .json(.object(["a": .number(1), "b": .number(2)]))
        )
      ]
    )

    expectNoDifference(jsonObjectPlan.cacheKey, reorderedJSONObjectPlan.cacheKey, jsonObjectSource)
    expectNoDifference(
      jsonObjectPlan.cacheKey,
      "plan:aWQ6YVhSbGJYTXVhbk52Ymc9PXxuYW1lc3BhY2U6YVhSbGJYTT18ZmlsdGVyczpbZXF1YWxzKGNHRjViRzloWkE9PSxqc29uOm9iamVjdDp7WVE9PTpudW1iZXI6NDYwNzE4MjQxODgwMDAxNzQwOCxZZz09Om51bWJlcjo0NjExNjg2MDE4NDI3Mzg3OTA0fSldfG9yZGVyOm5pbHxvZmZzZXQ6bmlsfGxpbWl0Om5pbHxmaXJzdDpuaWx8YWZ0ZXI6bmlsfGxhc3Q6bmlsfGJlZm9yZTpuaWx8c2VsZWN0ZWRGaWVsZHM6bmlsfGluY2x1ZGVzOltd",
      "\(jsonObjectSource) pinned sorted JSON object cache key"
    )

    let explicitArraySource = weakHashSource(
      "keeps array and top-level undefined explicit "
        + "[adapted: Swift has typed null/json-null instead of undefined.]"
    )
    let arrayWithNullPlan = InstantQueryPlan(
      id: "items.array",
      namespace: "items",
      filters: [.equals(field: "payload", value: .json(.array([.null])))]
    )
    let emptyArrayPlan = InstantQueryPlan(
      id: "items.array",
      namespace: "items",
      filters: [.equals(field: "payload", value: .json(.array([])))]
    )
    let jsonNullPlan = InstantQueryPlan(
      id: "items.array",
      namespace: "items",
      filters: [.equals(field: "payload", value: .json(.null))]
    )
    let scalarNullPlan = InstantQueryPlan(
      id: "items.array",
      namespace: "items",
      filters: [.equals(field: "payload", value: .null)]
    )

    expectNoDifference(arrayWithNullPlan.cacheKey != emptyArrayPlan.cacheKey, true, explicitArraySource)
    expectNoDifference(arrayWithNullPlan.cacheKey != jsonNullPlan.cacheKey, true, explicitArraySource)
    expectNoDifference(jsonNullPlan.cacheKey != scalarNullPlan.cacheKey, true, explicitArraySource)
  }

  @Test
  func upstreamWeakHashDateAndKnownQueryPins() {
    let dateSource = weakHashSource(
      "distinguishes objects by their toJSON output "
        + "[adapted: Swift cache keys preserve the typed date/string boundary.]"
    )
    let date = Date(timeIntervalSince1970: 0.001)
    let sameDatePlan = InstantQueryPlan(
      id: "events.date",
      namespace: "events",
      filters: [.equals(field: "happenedAt", value: .date(date))]
    )
    let equivalentDatePlan = InstantQueryPlan(
      id: "events.date",
      namespace: "events",
      filters: [.equals(field: "happenedAt", value: .date(Date(timeIntervalSince1970: 0.001)))]
    )
    let otherDatePlan = InstantQueryPlan(
      id: "events.date",
      namespace: "events",
      filters: [.equals(field: "happenedAt", value: .date(Date(timeIntervalSince1970: 0.002)))]
    )
    let stringDatePlan = InstantQueryPlan(
      id: "events.date",
      namespace: "events",
      filters: [.equals(field: "happenedAt", value: .string("1970-01-01T00:00:00.001Z"))]
    )

    expectNoDifference(sameDatePlan.cacheKey, equivalentDatePlan.cacheKey, dateSource)
    expectNoDifference(sameDatePlan.cacheKey != otherDatePlan.cacheKey, true, dateSource)
    expectNoDifference(sameDatePlan.cacheKey != stringDatePlan.cacheKey, true, dateSource)

    let knownQuery = InstantQueryPlan(
      id: "users.by-id",
      namespace: "users",
      filters: [.equals(field: "id", value: .number(42))]
    )
    expectNoDifference(
      knownQuery.cacheKey,
      "plan:aWQ6ZFhObGNuTXVZbmt0YVdRPXxuYW1lc3BhY2U6ZFhObGNuTT18ZmlsdGVyczpbZXF1YWxzKGFXUT0sbnVtYmVyOjQ2MzExMDc3OTE4MjA0MjMxNjgpXXxvcmRlcjpuaWx8b2Zmc2V0Om5pbHxsaW1pdDpuaWx8Zmlyc3Q6bmlsfGFmdGVyOm5pbHxsYXN0Om5pbHxiZWZvcmU6bmlsfHNlbGVjdGVkRmllbGRzOm5pbHxpbmNsdWRlczpbXQ==",
      weakHashSource("produces a stable hash for a known query [adapted: Swift pins the plan cache key.]")
    )
  }

  @Test
  func upstreamWeakHashBigIntValuesAreUnrepresentableButClosed() {
    let source = weakHashSource(
      "handles bigint values without throwing "
        + "[adapted: Swift has no BigInt InstantValue case and keeps representable numeric/string cases distinct.]"
    )
    let numberPlan = InstantQueryPlan(
      id: "items.bigint",
      namespace: "items",
      filters: [.equals(field: "id", value: .number(123))]
    )
    let stringPlan = InstantQueryPlan(
      id: "items.bigint",
      namespace: "items",
      filters: [.equals(field: "id", value: .string("123"))]
    )
    let stringNPlan = InstantQueryPlan(
      id: "items.bigint",
      namespace: "items",
      filters: [.equals(field: "id", value: .string("123n"))]
    )

    expectNoDifference(numberPlan.cacheKey != stringPlan.cacheKey, true, source)
    expectNoDifference(numberPlan.cacheKey != stringNPlan.cacheKey, true, source)
    expectNoDifference(stringPlan.cacheKey != stringNPlan.cacheKey, true, source)
  }

  @Test
  func upstreamWeakHashLegacyKnownQueryPin() {
    let query = JSONValue.object([
      "pro_search_properties": .object([
        "$": .object([
          "where": .object([
            "pro_searches": .string("b14fae2f-ce9b-4677-b6a9-6dddd81914d0"),
            "propertyId": .number(936),
          ]),
        ]),
        "pro_searches": .object([:]),
      ]),
    ])

    expectNoDifference(
      InstantLegacyWeakHash.hash(query),
      "dcb9614",
      weakHashLegacySource("produces a stable hash for a known query")
    )
  }

  @Test
  func upstreamWeakHashLegacyJSSemanticsPins() {
    let source = weakHashLegacySource(
      "JS Number, UTF-16, array, object, and parseInt coercion pins [adapted: supplemental Swift regression table.]"
    )
    let cases: [(String, JSONValue, String)] = [
      ("number 936", .number(936), "7ad4ef28"),
      ("NaN", .number(.nan), "0"),
      ("infinity", .number(.infinity), "0"),
      ("emoji string", .string("😀"), "cb31c4b8"),
      ("array null", .array([.null]), "15c231b8"),
      ("array mixed", .array([.number(1), .string("a")]), "178d2a48"),
      ("object sorted ascii", .object(["b": .number(2), "a": .number(1)]), "253d73ce"),
      ("object null", .object(["a": .null]), "6ae33f24"),
      ("object false", .object(["a": .bool(false)]), "6ae33f24"),
      ("object non-ascii keys", .object(["😀": .number(1), "\u{E000}": .number(2)]), "d22f77d0"),
    ]

    for (label, value, expectedHash) in cases {
      expectNoDifference(
        InstantLegacyWeakHash.hash(value),
        expectedHash,
        "\(source) \(label)"
      )
    }
  }
}

private func weakHashSource(_ testName: String) -> String {
  "upstream/instant/client/packages/core/__tests__/src/utils/weakHash.test.ts \(testName)"
}

private func weakHashLegacySource(_ testName: String) -> String {
  "upstream/instant/client/packages/core/__tests__/src/utils/weakHashLegacy.test.ts \(testName)"
}
