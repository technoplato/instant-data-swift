import Foundation
import InstantSwiftDataCore

let benchmarkNamespace = "todos"

let benchmarkPlan = InstantQueryPlan(id: "benchmark.todos", namespace: benchmarkNamespace)

/// The exact deep-join plan upstream times in `instaql.bench.ts` `big query`.
///
/// Source:
/// `upstream/instant/client/packages/core/__tests__/src/instaql.bench.ts`
/// at vendored commit `e71017612aed4031710a35e2fcace30d38d557ac`.
let zenecaBigQueryPlan = InstantQueryPlan(
  id: "users.big-query.zeneca",
  namespace: "users",
  includes: [
    InstantQueryInclude(
      "bookshelves",
      query: InstantQueryIncludePlan(
        id: "bookshelves.big-query",
        namespace: "bookshelves",
        includes: [
          InstantQueryInclude("books"),
          InstantQueryInclude(
            "users",
            direction: .reverse,
            query: InstantQueryIncludePlan(
              id: "users.nested.big-query",
              namespace: "users",
              includes: [InstantQueryInclude("bookshelves")]
            )
          ),
        ]
      )
    )
  ]
)

func benchmarkTimestamp(_ index: Int) -> InstantTimestamp {
  InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(index))
}

func benchmarkPersistenceURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantSwiftDataBenchmarks-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

func benchmarkRuntime(persistenceURL: URL? = nil) async throws -> InstantRuntime {
  try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "instant-swift-data-benchmarks",
      persistenceURL: try persistenceURL ?? benchmarkPersistenceURL(),
      initialAttributes: TodoExample.attributes
    )
  )
}

func benchmarkTransaction(index: Int) -> InstantStoreTransaction {
  let transactionID = "benchmark-tx-\(index)"
  return InstantStoreTransaction(
    id: transactionID,
    operations: TodoExample.createOperations(
      id: "benchmark-todo-\(index)",
      text: "benchmark row \(index)",
      createdAt: benchmarkTimestamp(index),
      transactionID: transactionID
    )
  )
}

// MARK: - Upstream Zeneca fixture (for LocalRead.deepJoin.zeneca)

/// Loads the vendored Zeneca attrs/triples fixture into an in-memory store.
///
/// Path is resolved from this source file so the package-benchmark tool can run
/// from any working directory. The fixture is the same one upstream's
/// `instaql.bench.ts` and `benchmarks/upstream-instant/observe.ts` use.
func loadZenecaStore() throws -> InstantStore {
  let directory = packageRootURL()
    .appendingPathComponent("upstream/instant/client/packages/core/__tests__/src/data/zeneca")
  let attrsData = try Data(contentsOf: directory.appendingPathComponent("attrs.json"))
  let triplesData = try Data(contentsOf: directory.appendingPathComponent("triples.json"))

  guard let rawTriples = try JSONSerialization.jsonObject(with: triplesData) as? [[Any]] else {
    throw InstantError(
      code: .validationFailed,
      operation: "load Zeneca fixture",
      message: "Expected triples.json to be a JSON array.",
      recovery: "Check the vendored upstream checkout."
    )
  }
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
  return InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes, triples: triples))
}

private func packageRootURL(filePath: String = #filePath) -> URL {
  // Support.swift lives at benchmarks/Benchmarks/InstantSwiftDataBenchmarking/.
  URL(fileURLWithPath: filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

private func rawAttributeObjects(from data: Data) throws -> [[String: Any]] {
  let object = try JSONSerialization.jsonObject(with: data)
  if let array = object as? [[String: Any]] {
    return array.sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
  }
  guard let dictionary = object as? [String: Any] else {
    throw InstantError(
      code: .validationFailed,
      operation: "load Zeneca fixture",
      message: "Expected attrs.json to be a JSON array or object.",
      recovery: "Check the vendored upstream checkout."
    )
  }
  return dictionary.values
    .compactMap { $0 as? [String: Any] }
    .sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
}

private func instantAttribute(
  from raw: [String: Any],
  rawValues: [String: [Any]]
) throws -> InstantAttribute {
  guard let id = raw["id"] as? String else {
    throw InstantError(
      code: .validationFailed,
      operation: "load Zeneca fixture",
      message: "Attribute is missing id.",
      recovery: "Check attrs.json."
    )
  }
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

private func identity(_ value: Any?) throws -> (namespace: String, name: String) {
  guard let values = value as? [Any],
    let namespace = values[safe: 1] as? String,
    let name = values[safe: 2] as? String
  else {
    throw InstantError(
      code: .validationFailed,
      operation: "load Zeneca fixture",
      message: "Malformed attribute identity.",
      recovery: "Check attrs.json forward/reverse identity arrays."
    )
  }
  return (namespace: namespace, name: name)
}

private func optionalIdentity(_ value: Any?) throws -> (namespace: String, name: String)? {
  guard value != nil else { return nil }
  return try identity(value)
}

private func inferredValueType(_ values: [Any]) -> InstantValueType {
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

private func instantTriple(
  from raw: [Any],
  attributesByID: [String: InstantAttribute]
) throws -> InstantTriple {
  guard let entityID = raw[safe: 0] as? String,
    let attributeID = raw[safe: 1] as? String
  else {
    throw InstantError(
      code: .validationFailed,
      operation: "load Zeneca fixture",
      message: "Malformed triple row.",
      recovery: "Check triples.json."
    )
  }
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

private func instantValue(_ value: Any, attribute: InstantAttribute?) throws -> InstantValue {
  if value is NSNull {
    return .null
  }
  if attribute?.valueType == .ref {
    guard let ref = value as? String else {
      throw InstantError(
        code: .validationFailed,
        operation: "load Zeneca fixture",
        message: "Expected string ref value.",
        recovery: "Check triples.json."
      )
    }
    return .ref(ref)
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
    operation: "load Zeneca fixture",
    message: "Unsupported upstream fixture value '\(value)'.",
    recovery: "Extend the benchmark fixture loader to decode this JSON shape."
  )
}

private func jsonValue(_ value: Any) throws -> JSONValue {
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
    operation: "load Zeneca fixture",
    message: "Unsupported JSON value '\(value)'.",
    recovery: "Extend the benchmark fixture loader."
  )
}

private func isBooleanNumber(_ number: NSNumber) -> Bool {
  CFGetTypeID(number) == CFBooleanGetTypeID()
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
