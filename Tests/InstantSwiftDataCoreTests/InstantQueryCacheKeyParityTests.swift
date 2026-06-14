import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite
struct InstantQueryCacheKeyParityTests {
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
}

private func weakHashSource(_ testName: String) -> String {
  "upstream/instant/client/packages/core/__tests__/src/utils/weakHash.test.ts \(testName)"
}
