import Foundation

public struct InstantLiveRefreshApplicationResult: Hashable, Codable, Sendable {
  public var transaction: InstantStoreTransaction
  public var application: InstantServerTransactionApplicationResult
  public var confirmedMutation: PendingMutation?
  public var insertedTripleCount: Int
  public var mergedAttributeCount: Int

  public init(
    transaction: InstantStoreTransaction,
    application: InstantServerTransactionApplicationResult,
    confirmedMutation: PendingMutation?,
    insertedTripleCount: Int,
    mergedAttributeCount: Int
  ) {
    self.transaction = transaction
    self.application = application
    self.confirmedMutation = confirmedMutation
    self.insertedTripleCount = insertedTripleCount
    self.mergedAttributeCount = mergedAttributeCount
  }
}

struct InstantLiveRefreshTranslation: Sendable {
  var transaction: InstantStoreTransaction
  var processedTransactionID: String
  var confirmationMutationID: String?
  var attributesToMerge: [InstantAttribute]
  var queryResultReplacements: [InstantLiveQueryResultReplacement]
}

struct InstantLiveQueryResultReplacement: Sendable {
  var key: String
  var triples: [InstantTriple]
  var pageInfo: InstantQueryPageInfo?
}

struct InstantPersistedLiveQueryResult: Hashable, Codable, Sendable {
  var key: String
  var triples: [InstantTriple]
  var pageInfo: InstantQueryPageInfo?
  var updatedAt: InstantTimestamp

  init(
    replacement: InstantLiveQueryResultReplacement,
    updatedAt: InstantTimestamp
  ) {
    self.key = replacement.key
    self.triples = Dictionary(
      replacement.triples.map { (InstantLiveTripleIdentity($0), $0) },
      uniquingKeysWith: { _, latest in latest }
    )
    .values
    .sorted(by: Self.storedOrder)
    self.pageInfo = replacement.pageInfo
    self.updatedAt = updatedAt
  }

  /// Entity, then attribute, then value, the same order as comparing
  /// `(entityID, attributeID, value.comparableKey)` tuples. A tuple comparison builds both
  /// `comparableKey` strings before comparing its first element, so every comparison copied both
  /// values into new strings even when the entity IDs already differed.
  static func storedOrder(_ lhs: InstantTriple, _ rhs: InstantTriple) -> Bool {
    if lhs.entityID != rhs.entityID { return lhs.entityID < rhs.entityID }
    if lhs.attributeID != rhs.attributeID { return lhs.attributeID < rhs.attributeID }
    return lhs.value.comparableKey < rhs.value.comparableKey
  }
}

struct InstantLiveTripleIdentity: Hashable, Sendable {
  var entityID: String
  var attributeID: String
  var value: InstantValue

  init(_ triple: InstantTriple) {
    entityID = triple.entityID
    attributeID = triple.attributeID
    value = triple.value
  }
}

actor InstantLiveQueryResultState {
  private var pageInfoByQuery: [String: InstantQueryPageInfo] = [:]
  private var observerCountByQuery: [String: Int] = [:]

  func retain(key: String) {
    observerCountByQuery[key, default: 0] += 1
  }

  func release(key: String) {
    guard let observerCount = observerCountByQuery[key] else { return }
    if observerCount > 1 {
      observerCountByQuery[key] = observerCount - 1
    } else {
      observerCountByQuery[key] = nil
      pageInfoByQuery[key] = nil
    }
  }

  func record(_ replacements: [InstantLiveQueryResultReplacement]) {
    for replacement in replacements {
      guard observerCountByQuery[replacement.key] != nil else { continue }
      pageInfoByQuery[replacement.key] = replacement.pageInfo
    }
  }

  func record(_ result: InstantPersistedLiveQueryResult) {
    guard observerCountByQuery[result.key] != nil else { return }
    pageInfoByQuery[result.key] = result.pageInfo
  }

  func pageInfo(for key: String) -> InstantQueryPageInfo? {
    pageInfoByQuery[key]
  }

  func unload(key: String) {
    pageInfoByQuery[key] = nil
  }

  func activeKeysForTesting() -> Set<String> {
    Set(observerCountByQuery.keys)
  }
}

private struct InstantTranslatedLiveComputation {
  var queryKey: String?
  var operations: [InstantTripleOperation]
  var queryResultReplacement: InstantLiveQueryResultReplacement?
}

enum InstantLiveRefreshTranslator {
  /// The attributes a raw server attribute payload adds to what this device already holds.
  ///
  /// Instant stores attributes as data, so a device only knows the namespaces whose attributes
  /// it has. This applies the same reconciliation `refresh-ok` uses: a namespace/name pair the
  /// device already has keeps its local attribute id, because local triples and pending
  /// mutations reference that id; only pairs the device has never seen are new.
  static func attributesToMerge(
    serverAttributes: [InstantLiveJSONValue],
    existingAttributes: [InstantAttribute]
  ) throws -> [InstantAttribute] {
    InstantLiveRefreshAttributeContext(
      existingAttributes: existingAttributes,
      serverAttributes: try serverAttributes.map(parseAttribute)
    )
    .attributesToMerge
  }

  /// The attribute context for `serverAttributes` over the device's `existingAttributes`: the server attrs parsed, the
  /// local id of each, and the attributes the device has never seen.
  static func attributeContext(
    serverAttributes: [InstantLiveJSONValue],
    existingAttributes: [InstantAttribute]
  ) throws -> InstantLiveRefreshAttributeContext {
    InstantLiveRefreshAttributeContext(
      existingAttributes: existingAttributes,
      serverAttributes: try serverAttributes.map(parseAttribute)
    )
  }

  /// - Parameter attributeContext: The context for `refreshOK.attrs` over `existingAttributes`, when the caller already
  ///   has it (``InstantLiveRefreshAttributeContextCache``); built here otherwise.
  static func translate(
    _ refreshOK: InstantLiveRefreshOK,
    existingAttributes: [InstantAttribute],
    receivedAt: InstantTimestamp,
    attributeContext prebuiltAttributeContext: InstantLiveRefreshAttributeContext? = nil
  ) throws -> InstantLiveRefreshTranslation {
    let processedTransactionID = nonEmpty(refreshOK.processedTransactionID)
      ?? "live-refresh-\(receivedAt.milliseconds)"
    let attributeContext = try prebuiltAttributeContext ?? attributeContext(
      serverAttributes: refreshOK.attrs,
      existingAttributes: existingAttributes
    )
    var translatedComputations: [InstantTranslatedLiveComputation] = []
    var finalComputationIndexByQueryKey: [String: Int] = [:]
    for computation in refreshOK.computations {
      var computationOperations = try operations(
        from: computation,
        processedTransactionID: processedTransactionID,
        defaultTxTime: receivedAt,
        attributes: attributeContext
      )
      var queryKey: String?
      var queryResultReplacement: InstantLiveQueryResultReplacement?
      if let query = computation.objectValue?["instaql-query"] {
        let key = try InstantLiveQueryEncoder.registrationKey(for: query)
        let insertTriples: [InstantTriple] = computationOperations.compactMap { operation in
          guard case let .insert(triple) = operation else { return nil }
          return triple
        }
        let boundedInsertTriples = InstantLiveQueryNestedLimit.limitedTriples(
          queryKey: key,
          triples: insertTriples,
          attributes: attributeContext.resolvedLocalAttributes
        )
        let retainedInsertIdentities = Set(
          boundedInsertTriples.map(InstantLiveTripleIdentity.init)
        )
        computationOperations.removeAll { operation in
          guard case let .insert(triple) = operation else { return false }
          return !retainedInsertIdentities.contains(InstantLiveTripleIdentity(triple))
        }
        queryKey = key
        queryResultReplacement = InstantLiveQueryResultReplacement(
          key: key,
          triples: boundedInsertTriples,
          pageInfo: try pageInfo(
            from: computation,
            query: query,
            queryKey: key,
            attributes: attributeContext
          )
        )
      }
      let computationIndex = translatedComputations.count
      translatedComputations.append(
        InstantTranslatedLiveComputation(
          queryKey: queryKey,
          operations: computationOperations,
          queryResultReplacement: queryResultReplacement
        )
      )
      if let queryKey {
        finalComputationIndexByQueryKey[queryKey] = computationIndex
      }
    }
    let normalizedComputations = translatedComputations.enumerated().compactMap {
      indexedComputation -> InstantTranslatedLiveComputation? in
      let (index, computation) = indexedComputation
      guard computation.queryKey.map({ finalComputationIndexByQueryKey[$0] == index }) ?? true
      else { return nil }
      return computation
    }
    let translatedOperations = normalizedComputations.flatMap(\.operations)
    let queryResultReplacements = normalizedComputations.compactMap(
      \.queryResultReplacement
    )

    return InstantLiveRefreshTranslation(
      transaction: InstantStoreTransaction(id: processedTransactionID, operations: translatedOperations),
      processedTransactionID: processedTransactionID,
      confirmationMutationID: nil,
      attributesToMerge: attributeContext.attributesToMerge,
      queryResultReplacements: queryResultReplacements
    )
  }

  private static func pageInfo(
    from computation: InstantLiveJSONValue,
    query: InstantLiveJSONValue,
    queryKey: String,
    attributes: InstantLiveRefreshAttributeContext
  ) throws -> InstantQueryPageInfo? {
    guard let namespace = query.objectValue?.keys.sorted().first,
      let result = computation.objectValue?["instaql-result"]?.arrayValue?.first,
      let rawPageInfo = result.objectValue?["data"]?.objectValue?["page-info"]
    else {
      return nil
    }
    guard let pageInfoByNamespace = rawPageInfo.objectValue else {
      throw decodeError(message: "Expected live query page-info to be an object.")
    }
    guard let rawNamespacePageInfo = pageInfoByNamespace[namespace] else {
      return nil
    }
    if case .null = rawNamespacePageInfo {
      return nil
    }
    guard let namespacePageInfo = rawNamespacePageInfo.objectValue else {
      throw decodeError(
        message: "Expected live query page-info for namespace '\(namespace)' to be an object."
      )
    }
    let pageInfo = InstantQueryPageInfo(
      startCursor: try cursor(
        from: namespacePageInfo["start-cursor"],
        namespace: namespace,
        attributes: attributes
      ),
      endCursor: try cursor(
        from: namespacePageInfo["end-cursor"],
        namespace: namespace,
        attributes: attributes
      ),
      hasPreviousPage: namespacePageInfo["has-previous-page?"]?.boolValue ?? false,
      hasNextPage: namespacePageInfo["has-next-page?"]?.boolValue ?? false
    )
    // Surface raw remote page-info so hosts can compare it with local materialization
    // (Scribe iPad Jetsam: remote has-next-page on short local windows).
    InstantInfiniteQueryDiagnostics.record(
      event: "infinite.remote-page-info.decoded",
      message: "Decoded Instant live query page-info from the server result.",
      metadata: [
        "namespace": namespace,
        "hasNextPage": pageInfo.hasNextPage.description,
        "hasPreviousPage": pageInfo.hasPreviousPage.description,
        "hasStartCursor": (pageInfo.startCursor != nil).description,
        "hasEndCursor": (pageInfo.endCursor != nil).description,
        "hasLiveTupleStart":
          ((pageInfo.startCursor?.liveTuple?.isEmpty) == false).description,
        "hasLiveTupleEnd":
          ((pageInfo.endCursor?.liveTuple?.isEmpty) == false).description,
        "startEntityFingerprint": InstantInfiniteQueryDiagnostics.fingerprint(
          pageInfo.startCursor?.entityID
        ),
        "endEntityFingerprint": InstantInfiniteQueryDiagnostics.fingerprint(
          pageInfo.endCursor?.entityID
        ),
      ],
      changeKey: queryKey
    )
    return pageInfo
  }

  private static func cursor(
    from value: InstantLiveJSONValue?,
    namespace: String,
    attributes: InstantLiveRefreshAttributeContext
  ) throws -> InstantQueryCursor? {
    guard let value else { return nil }
    if case .null = value { return nil }
    guard let tuple = value.arrayValue, tuple.count == 4,
      let entityID = tuple[0].stringValue,
      !entityID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let serverAttributeID = tuple[1].stringValue
    else {
      throw decodeError(
        message:
          "Expected live query cursor for namespace '\(namespace)' to be an opaque "
          + "[entity-id, attribute-id, value, tx-time] tuple."
      )
    }
    let localAttributeID = attributes.localAttributeID(forServerAttributeID: serverAttributeID)
    let attribute = attributes.attribute(forLocalAttributeID: localAttributeID)
      ?? attributes.attribute(forServerAttributeID: serverAttributeID)
    return InstantQueryCursor(
      entityID: entityID,
      sortValue: try instantValue(from: tuple[2], attribute: attribute),
      inclusive: false,
      liveTuple: tuple
    )
  }

  private static func operations(
    from computation: InstantLiveJSONValue,
    processedTransactionID: String,
    defaultTxTime: InstantTimestamp,
    attributes: InstantLiveRefreshAttributeContext
  ) throws -> [InstantTripleOperation] {
    guard let object = computation.objectValue else {
      throw decodeError(message: "Expected live refresh computations to be objects.")
    }
    guard let resultValue = object["instaql-result"] else {
      throw decodeError(message: "Expected live refresh computation to contain an instaql-result.")
    }
    guard let canonicalResults = resultValue.arrayValue else {
      throw decodeError(message: "Expected live refresh instaql-result to be an array.")
    }
    let queryNamespace = object["instaql-query"]?.objectValue?.keys.sorted().first
    var operations = try canonicalResults.flatMap { result in
      try canonicalOperations(
        from: result,
        processedTransactionID: processedTransactionID,
        defaultTxTime: defaultTxTime,
        attributes: attributes
      )
    }
    if operations.isEmpty, let namespace = queryNamespace {
      operations = try canonicalResults.flatMap { result in
        try objectTreeOperations(
          from: result,
          namespace: namespace,
          processedTransactionID: processedTransactionID,
          defaultTxTime: defaultTxTime,
          attributes: attributes
        )
      }
    }
    return operations
  }

  private static func canonicalOperations(
    from result: InstantLiveJSONValue,
    processedTransactionID: String,
    defaultTxTime: InstantTimestamp,
    attributes: InstantLiveRefreshAttributeContext
  ) throws -> [InstantTripleOperation] {
    guard let object = result.objectValue else {
      throw decodeError(message: "Expected live refresh instaql-result entries to be objects.")
    }
    let data = object["data"]?.objectValue
    let datalogResult = data?["datalog-result"]?.objectValue
    let joinRows: [InstantLiveJSONValue]
    if let datalogResult {
      guard let joinRowsValue = datalogResult["join-rows"] else {
        throw decodeError(message: "Expected live refresh datalog-result to contain join-rows.")
      }
      guard let rows = joinRowsValue.arrayValue else {
        throw decodeError(message: "Expected live refresh join-rows to be an array.")
      }
      joinRows = rows
    } else {
      joinRows = []
    }
    let ownOperations = try joinRows.flatMap { row in
      guard let triples = row.arrayValue else {
        throw decodeError(message: "Expected live refresh join rows to contain arrays of triples.")
      }
      return try triples.map { triple in
        try canonicalTripleOperation(
          from: triple,
          processedTransactionID: processedTransactionID,
          defaultTxTime: defaultTxTime,
          attributes: attributes
        )
      }
    }
    let childOperations = try (object["child-nodes"]?.arrayValue ?? []).flatMap { child in
      try canonicalOperations(
        from: child,
        processedTransactionID: processedTransactionID,
        defaultTxTime: defaultTxTime,
        attributes: attributes
      )
    }
    return ownOperations + childOperations
  }

  private static func canonicalTripleOperation(
    from value: InstantLiveJSONValue,
    processedTransactionID: String,
    defaultTxTime: InstantTimestamp,
    attributes: InstantLiveRefreshAttributeContext
  ) throws -> InstantTripleOperation {
    guard let triple = value.arrayValue else {
      throw decodeError(message: "Expected live refresh join row entries to be triples.")
    }
    guard triple.count >= 3,
      let entityID = triple[0].scalarStringValue,
      let rawAttributeID = triple[1].scalarStringValue
    else {
      throw decodeError(message: "Expected live refresh join rows to contain [entity-id, attribute-id, value, tx-time] triples.")
    }
    let attributeID = attributes.localAttributeID(forServerAttributeID: rawAttributeID)
    let attribute = attributes.attribute(forLocalAttributeID: attributeID)
      ?? attributes.attribute(forServerAttributeID: rawAttributeID)
    let txTime = triple.count >= 4
      ? timestamp(from: triple[3]) ?? defaultTxTime
      : defaultTxTime
    return .insert(
      InstantTriple(
        entityID: entityID,
        attributeID: attributeID,
        value: try instantValue(from: triple[2], attribute: attribute),
        txID: processedTransactionID,
        txTime: txTime
      )
    )
  }

  private static func objectTreeOperations(
    from result: InstantLiveJSONValue,
    namespace: String,
    processedTransactionID: String,
    defaultTxTime: InstantTimestamp,
    attributes: InstantLiveRefreshAttributeContext
  ) throws -> [InstantTripleOperation] {
    guard let object = result.objectValue else { return [] }
    let data = object["data"]?.objectValue ?? object
    guard let entityID = data["id"]?.scalarStringValue else {
      return try (object["child-nodes"]?.arrayValue ?? []).flatMap { child in
        try objectTreeOperations(
          from: child,
          namespace: namespace,
          processedTransactionID: processedTransactionID,
          defaultTxTime: defaultTxTime,
          attributes: attributes
        )
      }
    }
    var operations: [InstantTripleOperation] = []
    for key in data.keys.sorted() {
      guard key != "id",
        let attribute = attributes.attribute(namespace: namespace, name: key),
        let value = data[key]
      else {
        continue
      }
      operations.append(
        .insert(
          InstantTriple(
            entityID: entityID,
            attributeID: attribute.id,
            value: try instantValue(from: value, attribute: attribute),
            txID: processedTransactionID,
            txTime: defaultTxTime
          )
        )
      )
    }
    if let idAttribute = attributes.attribute(namespace: namespace, name: "id") {
      operations.append(
        .insert(
          InstantTriple(
            entityID: entityID,
            attributeID: idAttribute.id,
            value: .string(entityID),
            txID: processedTransactionID,
            txTime: defaultTxTime
          )
        )
      )
    }
    let childOperations = try (object["child-nodes"]?.arrayValue ?? []).flatMap { child in
      try objectTreeOperations(
        from: child,
        namespace: namespace,
        processedTransactionID: processedTransactionID,
        defaultTxTime: defaultTxTime,
        attributes: attributes
      )
    }
    return operations + childOperations
  }

  private static func parseAttribute(_ value: InstantLiveJSONValue) throws -> InstantAttribute {
    guard let object = value.objectValue,
      let id = object["id"]?.scalarStringValue
    else {
      throw decodeError(message: "Expected live refresh attrs to contain an id.")
    }
    let forwardIdentity = identity(object["forward-identity"])
    let reverseIdentity = identity(object["reverse-identity"])
    let namespace = forwardIdentity?.namespace ?? namespace(in: id) ?? ""
    let name = forwardIdentity?.name ?? name(in: id) ?? id
    let wireValueType = object["value-type"]?.scalarStringValue
    let valueType = wireValueType == "ref"
      ? .ref
      : valueType(
        from: object["checked-data-type"]?.scalarStringValue ?? wireValueType
      )
    return InstantAttribute(
      id: id,
      namespace: namespace,
      name: name,
      valueType: valueType,
      isRequired: !(object["optional?"]?.boolValue ?? false),
      cardinality: cardinality(from: object["cardinality"]?.scalarStringValue),
      isIndexed: object["index?"]?.boolValue ?? object["indexed?"]?.boolValue ?? false,
      isUnique: object["unique?"]?.boolValue ?? false,
      forwardIdentity: forwardIdentity.map { "\($0.namespace)/\($0.name)" },
      reverseIdentity: reverseIdentity.map { "\($0.namespace)/\($0.name)" },
      primaryKey: false,
      linkNamespace: valueType == .ref ? reverseIdentity?.namespace : nil
    )
  }

  private static func instantValue(
    from value: InstantLiveJSONValue,
    attribute: InstantAttribute?
  ) throws -> InstantValue {
    let rawValue = try rawInstantValue(from: value)
    if case .null = rawValue { return .null }
    guard let attribute else { return rawValue }
    switch attribute.valueType {
    case .ref:
      guard let id = value.scalarStringValue else {
        throw decodeError(message: "Expected ref attribute '\(attribute.id)' to contain an entity id.")
      }
      return .ref(id)

    case .date:
      guard let date = InstantDateCoercion.coerce(rawValue) else {
        throw decodeError(message: "Expected date attribute '\(attribute.id)' to contain an Instant date value.")
      }
      return .date(date)

    case .json:
      return .json(try jsonValue(from: value))

    case .any, .string, .number, .boolean:
      return rawValue
    }
  }

  private static func rawInstantValue(from value: InstantLiveJSONValue) throws -> InstantValue {
    switch value {
    case .null:
      return .null
    case let .bool(value):
      return .bool(value)
    case let .number(value):
      return .number(value)
    case let .string(value):
      return .string(value)
    case .array, .object:
      return .json(try jsonValue(from: value))
    }
  }

  private static func jsonValue(from value: InstantLiveJSONValue) throws -> JSONValue {
    switch value {
    case .null:
      return .null
    case let .bool(value):
      return .bool(value)
    case let .number(value):
      return .number(value)
    case let .string(value):
      return .string(value)
    case let .array(values):
      return .array(try values.map(jsonValue))
    case let .object(values):
      return .object(try values.mapValues(jsonValue))
    }
  }

  private static func timestamp(from value: InstantLiveJSONValue) -> InstantTimestamp? {
    switch value {
    case let .number(number):
      guard number.isFinite else { return nil }
      return InstantTimestamp(milliseconds: Int64(number.rounded()))
    case let .string(string):
      guard let number = Int64(string) else { return nil }
      return InstantTimestamp(milliseconds: number)
    case .null, .bool, .array, .object:
      return nil
    }
  }

  private static func identity(_ value: InstantLiveJSONValue?) -> InstantLiveAttributeIdentity? {
    guard let values = value?.arrayValue,
      values.count >= 3,
      let id = values[0].scalarStringValue,
      let namespace = values[1].scalarStringValue,
      let name = values[2].scalarStringValue
    else {
      return nil
    }
    return InstantLiveAttributeIdentity(id: id, namespace: namespace, name: name)
  }

  private static func valueType(from rawValue: String?) -> InstantValueType {
    switch rawValue {
    case "string":
      return .string
    case "number":
      return .number
    case "boolean", "bool":
      return .boolean
    case "date":
      return .date
    case "json":
      return .json
    case "ref":
      return .ref
    case "blob", "any", nil:
      return .any
    default:
      return .any
    }
  }

  private static func cardinality(from rawValue: String?) -> InstantCardinality {
    rawValue == "many" ? .many : .one
  }

  private static func namespace(in attributeID: String) -> String? {
    guard let separator = attributeID.firstIndex(of: "/"), separator != attributeID.startIndex
    else { return nil }
    return String(attributeID[..<separator])
  }

  private static func name(in attributeID: String) -> String? {
    guard let separator = attributeID.firstIndex(of: "/"),
      attributeID.index(after: separator) != attributeID.endIndex
    else { return nil }
    return String(attributeID[attributeID.index(after: separator)...])
  }

  private static func nonEmpty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func decodeError(message: String) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "apply live refresh",
      message: message,
      recovery: "Inspect the Instant refresh-ok payload and attrs returned by the live session."
    )
  }
}

private struct InstantLiveAttributeIdentity: Hashable, Sendable {
  var id: String
  var namespace: String
  var name: String
}

/// The attribute context of the latest live refresh, reused while the session's attrs and the device's schema stay the
/// same (#303).
///
/// A live session keeps the attrs of its `init-ok`, and of any refresh that carries them, and applies every attr-less
/// refresh with those. Parsing Scribe's 447 attrs and rebuilding the schema lookups for each frame cost more than
/// translating the frame's own rows. The cache keeps the attrs array and the local attribute revision its context was
/// built for. An attr-less refresh passes the session's same array, so the comparison is a buffer-identity check; a
/// refresh that carries equal attrs is compared in memory, still far cheaper than parsing it. A merged attribute bumps
/// the local revision, and changed attrs fail the comparison: either rebuilds the context.
// SAFETY: `lock` (an NSLock) guards every read and write of the cached entry.
final class InstantLiveRefreshAttributeContextCache: @unchecked Sendable {
  private struct Entry {
    var serverAttributes: [InstantLiveJSONValue]
    var localAttributeRevision: Int64
    var localAttributeCount: Int
    var context: InstantLiveRefreshAttributeContext
  }

  private let lock = NSLock()
  private var entry: Entry?
  private var builds = 0

  func context(
    serverAttributes: [InstantLiveJSONValue],
    existingAttributes: [InstantAttribute],
    localAttributeRevision: Int64
  ) throws -> InstantLiveRefreshAttributeContext {
    lock.lock()
    defer { lock.unlock() }
    if let entry,
      entry.localAttributeRevision == localAttributeRevision,
      entry.localAttributeCount == existingAttributes.count,
      entry.serverAttributes == serverAttributes
    {
      return entry.context
    }
    let context = try InstantLiveRefreshTranslator.attributeContext(
      serverAttributes: serverAttributes,
      existingAttributes: existingAttributes
    )
    builds += 1
    entry = Entry(
      serverAttributes: serverAttributes,
      localAttributeRevision: localAttributeRevision,
      localAttributeCount: existingAttributes.count,
      context: context
    )
    return context
  }

  /// How many times a context was built rather than reused.
  var buildCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return builds
  }
}

struct InstantLiveRefreshAttributeContext: Sendable {
  private var existing = AttributeStore()
  private var serverAttributesByID: [String: InstantAttribute] = [:]
  private var localAttributeIDsByServerID: [String: String] = [:]
  private(set) var attributesToMerge: [InstantAttribute] = []

  /// The local schema after this refresh's new attributes merge in, resolved once per refresh.
  /// Resolving it per computation re-merged and re-sorted the whole schema for every query result.
  let resolvedLocalAttributes: [InstantAttribute]

  init(existingAttributes: [InstantAttribute], serverAttributes: [InstantAttribute]) {
    self.existing = AttributeStore(attributes: existingAttributes)
    var attributesToMerge: [InstantAttribute] = []
    for attribute in serverAttributes {
      serverAttributesByID[attribute.id] = attribute
      if let local = existing.attribute(namespace: attribute.namespace, name: attribute.name) {
        localAttributeIDsByServerID[attribute.id] = local.id
      } else if !attribute.namespace.isEmpty, attribute.name != "id" {
        attributesToMerge.append(attribute)
      }
    }
    self.attributesToMerge = attributesToMerge
    var resolved = existing
    resolved.merge(attributesToMerge)
    self.resolvedLocalAttributes = resolved.attributes
  }

  func localAttributeID(forServerAttributeID attributeID: String) -> String {
    localAttributeIDsByServerID[attributeID] ?? attributeID
  }

  func attribute(forLocalAttributeID attributeID: String) -> InstantAttribute? {
    existing[attributeID]
  }

  func attribute(forServerAttributeID attributeID: String) -> InstantAttribute? {
    serverAttributesByID[attributeID]
  }

  func attribute(namespace: String, name: String) -> InstantAttribute? {
    existing.attribute(namespace: namespace, name: name)
  }
}

private extension InstantLiveJSONValue {
  var boolValue: Bool? {
    guard case let .bool(value) = self else { return nil }
    return value
  }

  var scalarStringValue: String? {
    switch self {
    case let .string(value):
      return value
    case let .number(value):
      guard value.isFinite else { return nil }
      if value.rounded() == value,
        value >= Double(Int64.min),
        value <= Double(Int64.max)
      {
        return String(Int64(value))
      }
      return String(value)
    case let .bool(value):
      return value ? "true" : "false"
    case .null, .array, .object:
      return nil
    }
  }
}
