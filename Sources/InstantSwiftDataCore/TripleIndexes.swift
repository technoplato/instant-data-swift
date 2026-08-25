import Foundation

struct AttributeStore: Hashable, Codable, Sendable {
  private var attributesByID: [String: InstantAttribute] = [:]
  private var attributesByForwardIdentity: [String: InstantAttribute] = [:]
  private var attributesByNamespaceAndName: [String: [String: InstantAttribute]] = [:]
  private var attributesByNamespace: [String: [InstantAttribute]] = [:]
  private var reverseAttributesByNamespaceAndName: [String: [String: InstantAttribute]] = [:]
  private var reverseAttributesByID: [String: InstantAttribute] = [:]
  private var namespaceSet: Set<String> = []
  private var namespacesWithManyCardinality: Set<String> = []

  private enum CodingKeys: String, CodingKey {
    case attributesByID
  }

  init(attributes: [InstantAttribute] = []) {
    self.replaceAll(attributes)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.attributesByID = try container.decode(
      [String: InstantAttribute].self,
      forKey: .attributesByID
    )
    rebuildLookupIndexes()
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(attributesByID, forKey: .attributesByID)
  }

  var attributes: [InstantAttribute] {
    attributesByID.values.sorted { $0.id < $1.id }
  }

  /// Maintained alongside the other derived lookup indexes rather than rebuilt per read.
  ///
  /// The write path consults this twice for every triple it validates, so deriving it on read made
  /// each write proportional to the size of the schema. See
  /// `InstantStoreWriteScalingTests.applyingAWideTransactionDoesNotScaleWithTheAttributeCount`.
  var namespaces: Set<String> {
    namespaceSet
  }

  var count: Int {
    attributesByID.count
  }

  mutating func replaceAll(_ attributes: [InstantAttribute]) {
    attributesByID = Dictionary(
      uniqueKeysWithValues: Self.withPrimaryKeys(attributes).map { ($0.id, $0) }
    )
    rebuildLookupIndexes()
  }

  mutating func merge(_ attributes: [InstantAttribute]) {
    for attribute in Self.withPrimaryKeys(attributes) {
      guard
        attribute.valueType == .ref,
        attribute.forwardIdentity != nil,
        attribute.reverseIdentity != nil
      else {
        attributesByID[attribute.id] = attribute
        continue
      }

      let sameDirectionIDs = Set(
        attributesByID.values
        .filter { Self.hasSameRelationIdentity($0, as: attribute) }
        .map(\.id)
          + [attribute.id]
      ).sorted()
      let reverseDirectionIDs = attributesByID.values
        .filter { Self.hasReverseRelationIdentity($0, as: attribute) }
        .map(\.id)
        .sorted()

      if let retainedID = durableRelationID(
        declaredAttribute: attribute,
        sameDirectionIDs: sameDirectionIDs,
        reverseDirectionIDs: reverseDirectionIDs
      ) {
        for duplicateID in sameDirectionIDs + reverseDirectionIDs
        where duplicateID != retainedID {
          attributesByID.removeValue(forKey: duplicateID)
        }

        if retainedID == attribute.id {
          // A fresh declaration or an incoming server attribute installs its own metadata.
          attributesByID[retainedID] = attribute
        } else {
          // An existing non-logical/server ID is the durable schema authority. Preserve its entire
          // metadata and orientation rather than projecting application cardinality, required,
          // index, or delete flags onto a physical attribute with different server semantics.
          // Lookup indexes still expose the incoming declaration as a forward or reverse alias.
          guard attributesByID[retainedID] != nil else { continue }
        }
      } else {
        attributesByID[attribute.id] = attribute
      }
    }
    rebuildLookupIndexes()
  }

  subscript(id: String) -> InstantAttribute? {
    forwardAttribute(id: id) ?? reverseAttributesByID[id]
  }

  func exactAttribute(id: String) -> InstantAttribute? {
    attributesByID[id]
  }

  func attribute(namespace: String, name: String) -> InstantAttribute? {
    if name == "id" {
      return attributesByNamespaceAndName[namespace]?[name]
        ?? self[InstantAttribute.primaryKeyID(namespace: namespace)]
    }
    return attributesByNamespaceAndName[namespace]?[name]
  }

  func attributes(namespace: String) -> [InstantAttribute] {
    attributesByNamespace[namespace] ?? []
  }

  func namespaceHasManyCardinality(_ namespace: String) -> Bool {
    namespacesWithManyCardinality.contains(namespace)
  }

  func primaryKeyAttribute(namespace: String) -> InstantAttribute {
    attributesByNamespaceAndName[namespace]?["id"]
      ?? self[InstantAttribute.primaryKeyID(namespace: namespace)]
      ?? .primaryKey(namespace: namespace)
  }

  func lookupAttribute(id: String) -> InstantResolvedLookupAttribute? {
    if let attribute = forwardAttribute(id: id) {
      return InstantResolvedLookupAttribute(
        attribute: attribute,
        direction: .forward,
        namespace: attribute.namespace,
        name: attribute.name
      )
    }
    guard let attribute = reverseAttributesByID[id] else {
      return nil
    }
    return InstantResolvedLookupAttribute(
      attribute: attribute,
      direction: .reverse,
      namespace: attribute.linkNamespace ?? Self.namespace(in: id) ?? attribute.namespace,
      name: Self.name(in: id) ?? id
    )
  }

  /// Canonicalizes a stored relation fact through the current physical schema.
  ///
  /// `logicalAttributeID` is used while reconciling an old physical attribute that is no longer
  /// present after merge. Ordinary loads omit it so durable logical forward and reverse IDs are
  /// resolved through the current alias indexes.
  func canonicalizedStorageTriple(
    _ triple: InstantTriple,
    logicalAttributeID: String? = nil
  ) -> InstantTriple {
    guard let resolvedAttribute = lookupAttribute(id: logicalAttributeID ?? triple.attributeID)
    else { return triple }

    guard resolvedAttribute.direction == .reverse else {
      var canonical = triple
      canonical.attributeID = resolvedAttribute.attribute.id
      return canonical
    }
    guard case let .ref(forwardEntityID) = triple.value else { return triple }
    var canonical = triple
    canonical.entityID = forwardEntityID
    canonical.attributeID = resolvedAttribute.attribute.id
    canonical.value = .ref(triple.entityID)
    return canonical
  }

  func reverseAttribute(namespace: String, name: String) -> InstantAttribute? {
    reverseAttributesByNamespaceAndName[namespace]?[name]
  }

  /// Returns only the resident attribute keys whose stored relation orientation or physical ID
  /// changed across a schema merge.
  ///
  /// This is deliberately schema-only. A scalar declaration, or a relation declaration that
  /// resolves to the same physical forward attribute, can therefore skip walking resident triple
  /// storage entirely.
  func remappedRelationAttributeIDs(from previousAttributes: AttributeStore) -> Set<String> {
    Set(
      previousAttributes.attributes.compactMap { previousAttribute in
        guard
          previousAttribute.valueType == .ref,
          let logicalForwardIdentity = previousAttribute.forwardIdentity,
          let resolvedAttribute = lookupAttribute(id: logicalForwardIdentity),
          resolvedAttribute.attribute.id != previousAttribute.id
            || resolvedAttribute.direction == .reverse
        else { return nil }
        return previousAttribute.id
      }
    )
  }

  /// Describes the durable rows that must move before reciprocal relation attributes can merge.
  ///
  /// A fresh database has no durable relation identity to preserve and returns `nil`. An upgraded
  /// database returns only obsolete source IDs; the retained physical ID is deliberately excluded
  /// so a row-addressed SQLite rewrite cannot re-read a canonical row it just inserted.
  static func relationStorageReconciliation(
    durableAttributes: [InstantAttribute],
    declaredAttributes: [InstantAttribute]
  ) -> InstantRelationStorageReconciliation? {
    let previousAttributes = AttributeStore(attributes: durableAttributes)
    let declaredRelations = Self.withPrimaryKeys(declaredAttributes).filter { declaration in
      guard
        declaration.valueType == .ref,
        declaration.forwardIdentity != nil,
        declaration.reverseIdentity != nil
      else { return false }
      return previousAttributes.attributes.contains { candidate in
        (Self.hasSameRelationIdentity(candidate, as: declaration)
          && candidate.id != declaration.id)
          || Self.hasReverseRelationIdentity(candidate, as: declaration)
      }
    }
    guard !declaredRelations.isEmpty else { return nil }

    var mergedAttributes = previousAttributes
    // Install the complete declaration set at the same durable boundary. This preserves scalar
    // and permission metadata exactly as the ordinary runtime merge would, while ensuring only
    // one attribute revision is published for the bootstrap transition.
    mergedAttributes.merge(declaredAttributes)

    var obsoleteAttributeIDs: Set<String> = []
    for declaration in declaredRelations {
      guard let retainedID = mergedAttributes.lookupAttribute(id: declaration.id)?.attribute.id
      else { continue }
      for candidate in previousAttributes.attributes
      where Self.hasSameRelationIdentity(candidate, as: declaration)
        || Self.hasReverseRelationIdentity(candidate, as: declaration)
      {
        if candidate.id != retainedID {
          obsoleteAttributeIDs.insert(candidate.id)
        }
      }
      for logicalID in [
        declaration.id,
        declaration.forwardIdentity,
        declaration.reverseIdentity,
      ].compactMap({ $0 }) where logicalID != retainedID {
        obsoleteAttributeIDs.insert(logicalID)
      }
    }
    guard !obsoleteAttributeIDs.isEmpty else { return nil }
    return InstantRelationStorageReconciliation(
      previousAttributes: previousAttributes,
      mergedAttributes: mergedAttributes,
      obsoleteAttributeIDs: obsoleteAttributeIDs,
      declaredRelationAttributes: declaredRelations.sorted { $0.id < $1.id }
    )
  }

  private mutating func rebuildLookupIndexes() {
    attributesByForwardIdentity = [:]
    attributesByNamespaceAndName = [:]
    attributesByNamespace = [:]
    reverseAttributesByNamespaceAndName = [:]
    reverseAttributesByID = [:]
    namespaceSet = []
    namespacesWithManyCardinality = []

    for attribute in attributesByID.values.sorted(by: { $0.id < $1.id }) {
      namespaceSet.insert(attribute.namespace)
      if attribute.cardinality == .many {
        namespacesWithManyCardinality.insert(attribute.namespace)
      }
      attributesByNamespaceAndName[attribute.namespace, default: [:]][attribute.name] = attribute
      attributesByNamespace[attribute.namespace, default: []].append(attribute)
      if let forwardIdentity = attribute.forwardIdentity {
        attributesByForwardIdentity[forwardIdentity] = attribute
      }
      guard
        attribute.valueType == .ref,
        let linkNamespace = attribute.linkNamespace,
        let reverseIdentity = attribute.reverseIdentity
      else { continue }
      reverseAttributesByID[reverseIdentity] = attribute
      if let reverseName = Self.name(in: reverseIdentity) {
        reverseAttributesByNamespaceAndName[linkNamespace, default: [:]][reverseName] = attribute
      }
    }
    for namespace in attributesByNamespace.keys {
      attributesByNamespace[namespace]?.sort { $0.id < $1.id }
    }
  }

  /// Reconciles a schema declaration with the server-issued ID already owning its triples.
  ///
  /// Relation IDs are physical storage keys, while forward and reverse identities are the stable
  /// schema names used by application declarations. An existing physical ID therefore wins over a
  /// newly merged logical ID. If a previous bootstrap left both rows behind, a non-declaration ID
  /// wins deterministically and the duplicate is removed.
  private func durableRelationID(
    declaredAttribute: InstantAttribute,
    sameDirectionIDs: [String],
    reverseDirectionIDs: [String]
  ) -> String? {
    let matchingIDs = Set(sameDirectionIDs).union(reverseDirectionIDs).sorted()
    guard !matchingIDs.isEmpty else { return nil }
    let logicalIDs = Set(
      [declaredAttribute.forwardIdentity, declaredAttribute.reverseIdentity].compactMap { $0 }
    )
    // Server-issued physical IDs are not one of the application schema's path identities. They
    // win across both orientations; otherwise a reciprocal local declaration could delete the
    // server attribute and orphan the next server transaction under that UUID.
    if let durableID = matchingIDs.first(where: { !logicalIDs.contains($0) }) {
      return durableID
    }
    if attributesByID[declaredAttribute.id] != nil {
      return declaredAttribute.id
    }
    return matchingIDs.first(where: { attributesByID[$0] != nil })
      ?? declaredAttribute.id
  }

  private static func hasSameRelationIdentity(
    _ candidate: InstantAttribute,
    as declared: InstantAttribute
  ) -> Bool {
    candidate.valueType == .ref
      && candidate.namespace == declared.namespace
      && candidate.name == declared.name
      && candidate.forwardIdentity == declared.forwardIdentity
      && candidate.reverseIdentity == declared.reverseIdentity
  }

  private static func hasReverseRelationIdentity(
    _ candidate: InstantAttribute,
    as declared: InstantAttribute
  ) -> Bool {
    candidate.valueType == .ref
      && candidate.forwardIdentity == declared.reverseIdentity
      && candidate.reverseIdentity == declared.forwardIdentity
  }

  private func forwardAttribute(id: String) -> InstantAttribute? {
    attributesByID[id]
      ?? attributesByForwardIdentity[id]
      ?? Self.primaryKeyAttribute(id: id)
  }

  private static func withPrimaryKeys(_ attributes: [InstantAttribute]) -> [InstantAttribute] {
    let attributes = attributes.map { attribute in
      guard attribute.name == "id" || attribute.primaryKey else { return attribute }
      var primaryKey = attribute
      primaryKey.cardinality = .one
      primaryKey.isIndexed = true
      primaryKey.isUnique = true
      primaryKey.primaryKey = true
      return primaryKey
    }
    let namespaces = Set(attributes.map(\.namespace))
    let namespacesWithPrimaryKeys = Set(
      attributes
        .filter { $0.primaryKey || $0.name == "id" }
        .map(\.namespace)
    )
    let primaryKeys = namespaces
      .subtracting(namespacesWithPrimaryKeys)
      .map(InstantAttribute.primaryKey(namespace:))
    return primaryKeys + attributes
  }

  private static func primaryKeyAttribute(id: String) -> InstantAttribute? {
    guard id.hasSuffix("/id") else { return nil }
    let namespace = String(id.dropLast("/id".count))
    guard !namespace.isEmpty else { return nil }
    return .primaryKey(namespace: namespace)
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
}

struct InstantRelationStorageReconciliation: Sendable {
  var previousAttributes: AttributeStore
  var mergedAttributes: AttributeStore
  var obsoleteAttributeIDs: Set<String>
  var declaredRelationAttributes: [InstantAttribute]

  var attributes: [InstantAttribute] {
    mergedAttributes.attributes
  }

  var markerAttributes: [InstantAttribute] {
    mergedAttributes.attributes.filter { candidate in
      guard candidate.valueType == .ref else { return false }
      return declaredRelationAttributes.contains { declaration in
        (candidate.forwardIdentity == declaration.forwardIdentity
          && candidate.reverseIdentity == declaration.reverseIdentity)
          || (candidate.forwardIdentity == declaration.reverseIdentity
            && candidate.reverseIdentity == declaration.forwardIdentity)
      }
    }
  }

  func canonicalized(_ triple: InstantTriple) -> InstantTriple {
    let logicalAttributeID = previousAttributes.exactAttribute(id: triple.attributeID)?
      .forwardIdentity
    return mergedAttributes.canonicalizedStorageTriple(
      triple,
      logicalAttributeID: logicalAttributeID
    )
  }
}

enum InstantLookupAttributeDirection: Hashable, Sendable {
  case forward
  case reverse
}

struct InstantResolvedLookupAttribute: Hashable, Sendable {
  var attribute: InstantAttribute
  var direction: InstantLookupAttributeDirection
  var namespace: String
  var name: String
}

struct InstantQueryValidationIssue: Error, Hashable, Sendable {
  var namespace: String
  var path: String?
  var message: String
  var recovery: String
}


/// Hot leaf for TripleIndexes. Map keys hold entity/attr/value; leaves only hold
/// interned tx metadata (not full InstantTriple tripled across eav/aev/vae).
struct InstantTripleStamp: Hashable, Codable, Sendable {
  var txIDIndex: UInt32
  var txTimeMilliseconds: Int64
  var txTime: InstantTimestamp { InstantTimestamp(milliseconds: txTimeMilliseconds) }
}

enum InstantTripleInsertReplayPolicy: Equatable, Sendable {
  case replaceAndInvalidate
  case preserveExactResident
}


/// Cardinality-aware attribute binding. Cardinality-one is the common Instant case;
/// a full `[InstantValue: Stamp]` Dictionary per attr was a dominant structural floor
/// on Scribe word graphs (#044 / autoresearch).
enum AttrSlot: Hashable, Codable, Sendable {
  case one(value: InstantValue, stamp: InstantTripleStamp)
  case many([InstantValue: InstantTripleStamp])

  var count: Int {
    switch self {
    case .one: return 1
    case .many(let map): return map.count
    }
  }

  var isEmpty: Bool {
    switch self {
    case .one: return false
    case .many(let map): return map.isEmpty
    }
  }

  subscript(value: InstantValue) -> InstantTripleStamp? {
    get {
      switch self {
      case let .one(stored, stamp):
        return stored == value ? stamp : nil
      case let .many(map):
        return map[value]
      }
    }
  }

  var firstEntry: (key: InstantValue, value: InstantTripleStamp)? {
    switch self {
    case let .one(value, stamp):
      return (value, stamp)
    case let .many(map):
      guard let entry = map.first else { return nil }
      return (entry.key, entry.value)
    }
  }

  var values: [InstantTripleStamp] {
    switch self {
    case let .one(_, stamp): return [stamp]
    case let .many(map): return Array(map.values)
    }
  }

  var keys: [InstantValue] {
    switch self {
    case let .one(value, _): return [value]
    case let .many(map): return Array(map.keys)
    }
  }

  func forEachPair(_ body: (InstantValue, InstantTripleStamp) -> Void) {
    switch self {
    case let .one(value, stamp):
      body(value, stamp)
    case let .many(map):
      for (value, stamp) in map {
        body(value, stamp)
      }
    }
  }

  mutating func set(value: InstantValue, stamp: InstantTripleStamp, asMany: Bool) {
    if asMany {
      if case var .many(map) = self {
        map[value] = stamp
        self = .many(map)
      } else if case let .one(existingValue, existingStamp) = self {
        self = .many([existingValue: existingStamp, value: stamp])
      } else {
        self = .many([value: stamp])
      }
    } else {
      self = .one(value: value, stamp: stamp)
    }
  }

  /// Returns true if the attribute key should be removed entirely.
  mutating func removeValue(_ value: InstantValue) -> Bool {
    switch self {
    case let .one(stored, _):
      return stored == value
    case var .many(map):
      map.removeValue(forKey: value)
      if map.isEmpty { return true }
      self = .many(map)
      return false
    }
  }
}

// SAFETY: owned exclusively by one TripleIndexes value; copies isolate via
// isKnownUniquelyReferenced in the unique* accessors, all writes stay on the
// owning actor or inside value-type mutating functions (no shared executor).
private final class TxIDInterner: @unchecked Sendable {
  var internedTxIDs: [String]
  var txIDToIndex: [String: UInt32]
  private var lastTxID = ""
  private var lastTxIDIndex: UInt32 = 0

  init() {
    internedTxIDs = [""]
    txIDToIndex = ["": 0]
  }

  init(internedTxIDs: [String]) {
    let interned = internedTxIDs.isEmpty ? [""] : internedTxIDs
    self.internedTxIDs = interned
    var map: [String: UInt32] = [:]
    map.reserveCapacity(interned.count)
    for (offset, value) in interned.enumerated() {
      map[value] = UInt32(offset)
    }
    self.txIDToIndex = map
  }

  func intern(_ txID: String) -> UInt32 {
    if txID == lastTxID {
      return lastTxIDIndex
    }
    if let existing = txIDToIndex[txID] {
      lastTxID = txID
      lastTxIDIndex = existing
      return existing
    }
    let index = UInt32(internedTxIDs.count)
    internedTxIDs.append(txID)
    txIDToIndex[txID] = index
    lastTxID = txID
    lastTxIDIndex = index
    return index
  }

  func resolved(at index: UInt32) -> String {
    let i = Int(index)
    guard i >= 0, i < internedTxIDs.count else { return "" }
    return internedTxIDs[i]
  }
}

struct TripleIndexes: Codable, Sendable {
  private struct DerivedIndexAttributeShape: Hashable, Sendable {
    var namespace: String
    var valueType: InstantValueType
    var cardinality: InstantCardinality
    var isIndexed: Bool

    init(_ attribute: InstantAttribute) {
      namespace = attribute.namespace
      valueType = attribute.valueType
      cardinality = attribute.cardinality
      isIndexed = attribute.isIndexed
    }
  }

  // SAFETY: box for TripleIndexes CoW; every mutation flows through the `eav`
  // _modify accessor, which takes uniqueness on the owning value before writing.
  // No executor or lock shares this reference across isolation domains.
  private final class EAVStorage: @unchecked Sendable {
    var rows: [String: [String: AttrSlot]] = [:]
    func copy() -> EAVStorage {
      let copied = EAVStorage()
      copied.rows = rows
      return copied
    }
  }

  // SAFETY: box for TripleIndexes CoW; every mutation flows through the `vae`
  // _modify accessor, which takes uniqueness on the owning value before writing.
  // No executor or lock shares this reference across isolation domains.
  private final class VAEStorage: @unchecked Sendable {
    var rows: [InstantValue: [String: [String: InstantTripleStamp]]] = [:]
    func copy() -> VAEStorage {
      let copied = VAEStorage()
      copied.rows = rows
      return copied
    }
  }

  // SAFETY: box for TripleIndexes CoW; both derived maps mutate only through
  // _modify accessors that take uniqueness on the owning value first. No
  // executor or lock shares this reference across isolation domains.
  private final class IndexedStorage: @unchecked Sendable {
    var valueEntities: [String: [InstantValue: Set<String>]] = [:]
    var entityValues: [String: [String: InstantValue]] = [:]
    func copy() -> IndexedStorage {
      let copied = IndexedStorage()
      copied.valueEntities = valueEntities
      copied.entityValues = entityValues
      return copied
    }
  }

  private var eavStorage = EAVStorage()
  private var vaeStorage = VAEStorage()
  private var indexedStorage = IndexedStorage()

  private var eav: [String: [String: AttrSlot]] {
    _read { yield eavStorage.rows }
    _modify {
      uniqueEAV()
      yield &eavStorage.rows
    }
  }

  private var vae: [InstantValue: [String: [String: InstantTripleStamp]]] {
    _read { yield vaeStorage.rows }
    _modify {
      uniqueVAE()
      yield &vaeStorage.rows
    }
  }
  /// Compact secondary index for **schema-indexed** attributes only (not full InstantTriple AEV).
  /// Shape: attributeID → value → entityIDs. Powers equality filters / lookup without scanning eav.
  private var indexedValueEntities: [String: [InstantValue: Set<String>]] {
    _read { yield indexedStorage.valueEntities }
    _modify {
      uniqueIndexed()
      yield &indexedStorage.valueEntities
    }
  }
  /// attributeID → entityID → value for cardinality-one indexed attrs (sort / ordered page).
  private var indexedEntityValues: [String: [String: InstantValue]] {
    _read { yield indexedStorage.entityValues }
    _modify {
      uniqueIndexed()
      yield &indexedStorage.entityValues
    }
  }
  private var internCaches = InternCaches()
  private var pendingInternEntityID: String?
  private var pendingInternNamespace: String?
  private var pendingInternValues: [String: InstantMaterializedValue] = [:]
  private var pendingInternSnapshots: [String: InstantEntitySnapshot] = [:]
  private var pendingInternExtra: [String: [String: InstantEntitySnapshot]] = [:]
  private var internInvalidationIDs: Set<String> = []
  private var internedQueryResultsNeedInvalidation = false
  private var pendingInternNeedsEAVCompletion = false
  private var shouldInternOnWrite = true
  /// namespace → entityIDs that hold at least one attr in that namespace (avoids scanning segments for recordings queries).
  private var entitiesByNamespace: [String: Set<String>] = [:]
  private var lastWrittenEntityID: String?
  private var lastWrittenNamespace: String?
  /// Attribute definitions used to build the derived indexes above. Not encoded: decoding or a
  /// schema-shape transition must rebuild before an exact authoritative insert can be a no-op.
  private var derivedIndexAttributeShapes: [String: DerivedIndexAttributeShape] = [:]
  private var storedTripleCount = 0
  private var internedTxIDsBox = TxIDInterner()
  /// Exact transient keys hydrated or written only for preparing a mutation.
  /// Consumed before prepared indexes become the next hot store.
  private var deferredValueKeysToRemove: Set<EntityAttributeKey> = []

  private func internTxID(_ txID: String) -> UInt32 {
    internedTxIDsBox.intern(txID)
  }

  private func resolvedTxID(at index: UInt32) -> String {
    internedTxIDsBox.resolved(at: index)
  }

  private mutating func uniqueInternCaches() {
    if !isKnownUniquelyReferenced(&internCaches) {
      internCaches = internCaches.copy()
    }
  }

  private var internCachesAreEmpty: Bool {
    internCaches.isEmpty
  }

  private mutating func uniqueEAV() {
    if !isKnownUniquelyReferenced(&eavStorage) {
      eavStorage = eavStorage.copy()
    }
  }

  private mutating func uniqueVAE() {
    if !isKnownUniquelyReferenced(&vaeStorage) {
      vaeStorage = vaeStorage.copy()
    }
  }

  private mutating func uniqueIndexed() {
    if !isKnownUniquelyReferenced(&indexedStorage) {
      indexedStorage = indexedStorage.copy()
    }
  }

  func containsStoredEntity(_ entityID: String) -> Bool {
    eav[entityID] != nil
  }

  func hasIncomingReferences(_ entityID: String) -> Bool {
    guard !vae.isEmpty, let byAttribute = vae[.ref(entityID)] else { return false }
    for byEntity in byAttribute.values where !byEntity.isEmpty {
      return true
    }
    return false
  }

  func outgoingRefTargetIDs(_ entityID: String) -> [String] {
    guard let attributesByID = eav[entityID] else { return [] }
    var targetIDs: [String] = []
    for slot in attributesByID.values {
      slot.forEachPair { value, _ in
        if case let .ref(targetID) = value {
          targetIDs.append(targetID)
        }
      }
    }
    return targetIDs
  }

  mutating func applyInsert(
    _ triple: InstantTriple,
    attributes: AttributeStore,
    insertReplayPolicy: InstantTripleInsertReplayPolicy = .replaceAndInvalidate,
    into changed: inout Set<String>
  ) {
    applyInsert(
      triple,
      attribute: attributes[triple.attributeID],
      attributes: attributes,
      insertReplayPolicy: insertReplayPolicy,
      into: &changed
    )
  }

  mutating func applyInsert(
    _ triple: InstantTriple,
    attribute: InstantAttribute?,
    attributes: AttributeStore,
    insertReplayPolicy: InstantTripleInsertReplayPolicy,
    into changed: inout Set<String>
  ) {
    // Upstream isolates refresh facts in per-query stores. Swift applies them to one shared hot
    // store. Authoritative refreshes can preserve an exact resident fact so a repeated server
    // page does not invalidate every observer. Local and optimistic writes retain the ordinary
    // replace-and-invalidate behavior because their rollback captures the changed entity IDs.
    if insertReplayPolicy == .preserveExactResident,
      isExactVisibleSlot(triple, attribute: attribute)
    {
      return
    }
    if attribute?.cardinality == .one {
      switch eav[triple.entityID]?[triple.attributeID] {
      case let .one(existingValue, existingStamp)?:
        let value = Self.normalizedValue(triple.value, attribute: attribute)
        if existingValue == value {
          if existingStamp.txTime <= triple.txTime {
            eav[triple.entityID, default: [:]][triple.attributeID] = .one(
              value: existingValue,
              stamp: InstantTripleStamp(
                txIDIndex: internTxID(triple.txID),
                txTimeMilliseconds: existingStamp.txTimeMilliseconds
              )
            )
          }
          rememberChangedEntity(triple.entityID, into: &changed)
          if attribute?.valueType == .ref, let targetID = value.refValue {
            changed.insert(targetID)
          }
          return
        }
        // Last-write-wins arbitration, matching generic insert(): an incoming
        // triple older than the resident fact mutates nothing. The endpoints
        // are still reported as changed so observers refresh like HEAD did.
        let residentIsNewer = existingStamp.txTime > triple.txTime
        if !residentIsNewer {
          if derivedIndexAttributeShapes[triple.attributeID]
            != attribute.map(DerivedIndexAttributeShape.init)
          {
            unionReconcile(
              entityID: triple.entityID,
              attributeID: triple.attributeID,
              attributes: attributes,
              into: &changed
            )
          }
          var updated = triple
          updated.value = value
          replaceCardinalityOneSlot(
            entityID: triple.entityID,
            attributeID: triple.attributeID,
            previousValue: existingValue,
            triple: updated,
            attribute: attribute
          )
        }
        rememberChangedEntity(triple.entityID, into: &changed)
        if attribute?.valueType == .ref, let targetID = value.refValue {
          changed.insert(targetID)
        }
        return

      case .none:
        if let attribute {
          let shape = DerivedIndexAttributeShape(attribute)
          if derivedIndexAttributeShapes[triple.attributeID] != shape {
            unionReconcile(
              entityID: triple.entityID,
              attributeID: triple.attributeID,
              attributes: attributes,
              into: &changed
            )
          }
          insertNewCardinalityOne(triple, attribute: attribute)
          rememberChangedEntity(triple.entityID, into: &changed)
          if attribute.valueType == .ref, let targetID = triple.value.refValue {
            changed.insert(targetID)
          }
          return
        }

      case .many?:
        break
      }
    }
    unionReconcile(
      entityID: triple.entityID,
      attributeID: triple.attributeID,
      attributes: attributes,
      into: &changed
    )
    insert(triple, attribute: attribute)
    rememberChangedEntity(triple.entityID, into: &changed)
    if attribute?.valueType == .ref, let targetID = triple.value.refValue {
      changed.insert(targetID)
    }
  }

  mutating func apply(
    _ operation: InstantTripleOperation,
    attributes: AttributeStore,
    insertReplayPolicy: InstantTripleInsertReplayPolicy = .replaceAndInvalidate,
    into changed: inout Set<String>
  ) {
    switch operation {
    case .requireEntityMissing, .requireEntityMissingByLookup,
      .requireEntityExists, .requireEntityExistsByLookup,
      .requireTripleExists,
      .mergeByLookup, .insertByLookup, .retractByLookup,
      .deleteEntityByLookup, .ruleParams, .ruleParamsByLookup:
      return

    case let .merge(triple):
      unionReconcile(
        entityID: triple.entityID,
        attributeID: triple.attributeID,
        attributes: attributes,
        into: &changed
      )
      if merge(triple, attribute: attributes[triple.attributeID]) {
        changed.insert(triple.entityID)
      }

    case let .insert(triple):
      applyInsert(
        triple,
        attributes: attributes,
        insertReplayPolicy: insertReplayPolicy,
        into: &changed
      )

    case let .retract(triple):
      unionReconcile(
        entityID: triple.entityID,
        attributeID: triple.attributeID,
        attributes: attributes,
        into: &changed
      )
      changed.insert(triple.entityID)
      let attribute = attributes[triple.attributeID]
      if attribute?.valueType == .ref, let targetID = triple.value.refValue {
        changed.insert(targetID)
      }
      remove(triple, attribute: attribute)

    case let .deleteEntity(entityID):
      var visited: Set<DeleteVisit> = []
      changed.formUnion(
        deleteEntity(entityID, namespace: nil, attributes: attributes, visited: &visited)
      )

    case let .deleteEntityInNamespace(entityID, namespace):
      var visited: Set<DeleteVisit> = []
      changed.formUnion(
        deleteEntity(
          entityID,
          namespace: namespace,
          attributes: attributes,
          visited: &visited
        )
      )
    }
  }

  private func materializeTriple(
    entityID: String,
    attributeID: String,
    value: InstantValue,
    stamp: InstantTripleStamp
  ) -> InstantTriple {
    InstantTriple(
      entityID: entityID,
      attributeID: attributeID,
      value: value,
      txID: resolvedTxID(at: stamp.txIDIndex),
      txTime: stamp.txTime
    )
  }

  /// Wire shape keeps historical `aev` (always empty) so older caches decode.
  /// Secondary indexes (`indexedValueEntities`, …) are derived and not encoded.
  /// `storedTripleCount` / `internedTxIDs` rebuild on decode when needed.
  private enum CodingKeys: String, CodingKey {
    case aev
    case eav
    case vae
    case internedTxIDs
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // Legacy full InstantTriple AEV is ignored (memory floor).
    _ = try? container.decodeIfPresent(
      [String: [String: [InstantValue: InstantTriple]]].self,
      forKey: .aev
    )
    self.eav = try container.decode(
      [String: [String: AttrSlot]].self,
      forKey: .eav
    )
    self.vae = try container.decodeIfPresent(
      [InstantValue: [String: [String: InstantTripleStamp]]].self,
      forKey: .vae
    ) ?? [:]
    let interned = try container.decodeIfPresent([String].self, forKey: .internedTxIDs) ?? [""]
    self.internedTxIDsBox = TxIDInterner(internedTxIDs: interned)
    self.storedTripleCount = Self.walkedTripleCount(eav)
    // Secondary indexes stay empty until the next insert path with attributes
    // (or InstantStore rebuild via init(triples:attributes:)).
    self.indexedValueEntities = [:]
    self.indexedEntityValues = [:]
    self.internCaches = InternCaches()
    self.entitiesByNamespace = [:]
    self.derivedIndexAttributeShapes = [:]
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    // Empty aev keeps historical wire keys without retaining a third full index.
    try container.encode(
      [String: [String: [InstantValue: InstantTriple]]](),
      forKey: .aev
    )
    try container.encode(eav, forKey: .eav)
    try container.encode(vae, forKey: .vae)
    try container.encode(internedTxIDsBox.internedTxIDs, forKey: .internedTxIDs)
  }

  private static func walkedTripleCount(
    _ eav: [String: [String: AttrSlot]]
  ) -> Int {
    eav.values.reduce(into: 0) { count, attributesByID in
      for slot in attributesByID.values {
        count += slot.count
      }
    }
  }

  private struct IndexedEqualsResultKey: Hashable {
    var namespace: String
    var limit: Int
    var isAscending: Bool
    var filters: [InstantQueryFilter]
  }

  private struct SimpleOrderedResultKey: Hashable {
    var namespace: String
    var orderField: String
    var isAscending: Bool
  }

  // SAFETY: box for TripleIndexes CoW; mutations go through uniqueInternCaches()
  // (isKnownUniquelyReferenced) on the owning value, inside one actor's mutating
  // functions. No executor or lock shares this reference across domains.
  private final class InternCaches: @unchecked Sendable {
    var internedCardinalityOneSnapshots: [String: InstantEntitySnapshot] = [:]
    var internedExtraNamespaceSnapshots: [String: [String: InstantEntitySnapshot]] = [:]
    var internedServerCreatedAt: [String: InstantValue] = [:]
    var internedIndexedEqualsResults: [IndexedEqualsResultKey: [InstantEntitySnapshot]] = [:]
    var internedSimpleOrderedResults: [SimpleOrderedResultKey: [InstantEntitySnapshot]] = [:]

    func copy() -> InternCaches {
      let copied = InternCaches()
      copied.internedCardinalityOneSnapshots = internedCardinalityOneSnapshots
      copied.internedExtraNamespaceSnapshots = internedExtraNamespaceSnapshots
      copied.internedServerCreatedAt = internedServerCreatedAt
      copied.internedIndexedEqualsResults = internedIndexedEqualsResults
      copied.internedSimpleOrderedResults = internedSimpleOrderedResults
      return copied
    }

    func clearAll() {
      internedCardinalityOneSnapshots = [:]
      internedExtraNamespaceSnapshots = [:]
      internedServerCreatedAt = [:]
      internedIndexedEqualsResults = [:]
      internedSimpleOrderedResults = [:]
    }

    func clearQueryResults() {
      internedIndexedEqualsResults = [:]
      internedSimpleOrderedResults = [:]
    }

    var isEmpty: Bool {
      internedCardinalityOneSnapshots.isEmpty
        && internedExtraNamespaceSnapshots.isEmpty
        && internedServerCreatedAt.isEmpty
        && internedIndexedEqualsResults.isEmpty
        && internedSimpleOrderedResults.isEmpty
    }

    var internedEntityCount: Int {
      if internedExtraNamespaceSnapshots.isEmpty {
        return internedCardinalityOneSnapshots.count
      }
      var count = internedCardinalityOneSnapshots.count
      for entityID in internedExtraNamespaceSnapshots.keys
      where internedCardinalityOneSnapshots[entityID] == nil {
        count += 1
      }
      return count
    }

    func internedSnapshot(entityID: String, namespace: String) -> InstantEntitySnapshot? {
      if let interned = internedCardinalityOneSnapshots[entityID], interned.namespace == namespace {
        return Self.snapshotBySynthesizingID(interned, entityID: entityID)
      }
      if let interned = internedExtraNamespaceSnapshots[entityID]?[namespace] {
        return Self.snapshotBySynthesizingID(interned, entityID: entityID)
      }
      return nil
    }

    static func snapshotBySynthesizingID(
      _ interned: InstantEntitySnapshot,
      entityID: String
    ) -> InstantEntitySnapshot {
      if interned.values["id"] != nil {
        return interned
      }
      var values = interned.values
      values["id"] = .one(.string(entityID))
      return InstantEntitySnapshot(
        id: interned.id,
        namespace: interned.namespace,
        values: values,
        links: interned.links
      )
    }

    func hasInternedEntity(_ entityID: String) -> Bool {
      internedCardinalityOneSnapshots[entityID] != nil
        || internedExtraNamespaceSnapshots[entityID] != nil
    }

    func storeSnapshot(_ snapshot: InstantEntitySnapshot, entityID: String) {
      if let existing = internedCardinalityOneSnapshots[entityID] {
        if existing.namespace == snapshot.namespace {
          internedCardinalityOneSnapshots[entityID] = snapshot
          return
        }
        internedExtraNamespaceSnapshots[entityID, default: [:]][existing.namespace] = existing
        internedExtraNamespaceSnapshots[entityID, default: [:]][snapshot.namespace] = snapshot
        internedCardinalityOneSnapshots[entityID] = nil
        return
      }
      if internedExtraNamespaceSnapshots[entityID] != nil {
        internedExtraNamespaceSnapshots[entityID, default: [:]][snapshot.namespace] = snapshot
        return
      }
      internedCardinalityOneSnapshots[entityID] = snapshot
    }

    func patchSnapshot(
      entityID: String,
      namespace: String,
      name: String,
      value: InstantMaterializedValue
    ) {
      if var snapshot = internedCardinalityOneSnapshots[entityID],
        snapshot.namespace == namespace
      {
        snapshot.values[name] = value
        internedCardinalityOneSnapshots[entityID] = snapshot
        return
      }
      if internedCardinalityOneSnapshots[entityID] == nil,
        internedExtraNamespaceSnapshots[entityID] == nil
      {
        internedCardinalityOneSnapshots[entityID] = InstantEntitySnapshot(
          id: entityID,
          namespace: namespace,
          values: [name: value]
        )
        return
      }
      var extra = internedExtraNamespaceSnapshots[entityID] ?? [:]
      var snapshot = extra[namespace]
        ?? InstantEntitySnapshot(id: entityID, namespace: namespace, values: [:])
      snapshot.values[name] = value
      extra[namespace] = snapshot
      internedExtraNamespaceSnapshots[entityID] = extra
    }

    func retractSnapshotValue(
      entityID: String,
      namespace: String,
      name: String
    ) {
      if var snapshot = internedCardinalityOneSnapshots[entityID],
        snapshot.namespace == namespace
      {
        if snapshot.values[name] != nil {
          snapshot.values[name] = nil
          internedCardinalityOneSnapshots[entityID] = snapshot
        }
        return
      }
      guard var extra = internedExtraNamespaceSnapshots[entityID],
        var snapshot = extra[namespace]
      else { return }
      guard snapshot.values[name] != nil else { return }
      snapshot.values[name] = nil
      extra[namespace] = snapshot
      internedExtraNamespaceSnapshots[entityID] = extra
    }

    func removeInternedEntity(_ entityID: String) {
      internedCardinalityOneSnapshots[entityID] = nil
      internedExtraNamespaceSnapshots[entityID] = nil
    }
  }

  private struct QuerySnapshot: Hashable, Sendable {
    var snapshot: InstantEntitySnapshot
    var serverCreatedAt: InstantValue?
    var sortValue: InstantValue?
    var isFullyMaterialized = true
  }

  struct QueryMaterializationMetrics: Equatable, Sendable {
    var examinedCandidateCount = 0
    var matchingCandidateCount = 0
    var materializedSnapshotCount = 0
    var maximumRetainedCandidateCount = 0
    var boundedSelectionCount = 0
  }

  struct EntityAttributeKey: Hashable, Sendable {
    var entityID: String
    var attributeID: String
  }

  private struct StoredTripleIdentity: Hashable {
    var entityID: String
    var attributeID: String
    var value: InstantValue
  }

  struct DeferredValueRemovalMetrics: Equatable, Sendable {
    var examinedKeyCount = 0
    var residentKeyCount = 0
    var removedValueCount = 0
  }

  struct RelationStorageReconciliationMetrics: Equatable, Sendable {
    var examinedAttributeSlotCount = 0
    var examinedTripleCount = 0
    var movedTripleCount = 0
  }

  struct RelationStorageReconciliationResult: Equatable, Sendable {
    var changedEntityIDs: Set<String> = []
    var metrics = RelationStorageReconciliationMetrics()
  }

  private struct DeleteVisit: Hashable, Sendable {
    var entityID: String
    var namespace: String?
  }

  init(
    triples: [InstantTriple] = [],
    attributes: AttributeStore = AttributeStore(),
    excludingAttributeIDs excludedAttributeIDs: Set<String> = [],
    markingDeferredAttributeIDs deferredAttributeIDs: Set<String> = []
  ) {
    derivedIndexAttributeShapes = Dictionary(
      uniqueKeysWithValues: attributes.attributes.map {
        ($0.id, DerivedIndexAttributeShape($0))
      }
    )
    shouldInternOnWrite = false
    var canonicalTriples = triples
    var didCanonicalize = false
    for index in canonicalTriples.indices {
      let canonical = attributes.canonicalizedStorageTriple(canonicalTriples[index])
      guard canonical != canonicalTriples[index] else { continue }
      canonicalTriples[index] = canonical
      didCanonicalize = true
    }
    if didCanonicalize {
      canonicalTriples = Self.deduplicatingStoredTriples(canonicalTriples)
    }
    for triple in canonicalTriples
    where !excludedAttributeIDs.contains(triple.attributeID) {
      self.insert(triple, attribute: attributes[triple.attributeID])
      if deferredAttributeIDs.contains(triple.attributeID) {
        deferredValueKeysToRemove.insert(
          EntityAttributeKey(entityID: triple.entityID, attributeID: triple.attributeID)
        )
      }
    }
    shouldInternOnWrite = true
    clearPendingInternCaches()
  }

  mutating func hydrateDeferredValues(
    _ triples: [InstantTriple],
    attributes: AttributeStore
  ) {
    if triples.contains(where: {
      derivedIndexAttributeShapes[$0.attributeID]
        != attributes[$0.attributeID].map(DerivedIndexAttributeShape.init)
    }) {
      _ = rebuildDerivedIndexes(attributes: attributes)
    }
    deferredValueKeysToRemove.reserveCapacity(
      deferredValueKeysToRemove.count + triples.count
    )
    for triple in triples {
      insert(triple, attribute: attributes[triple.attributeID])
      deferredValueKeysToRemove.insert(
        EntityAttributeKey(entityID: triple.entityID, attributeID: triple.attributeID)
      )
    }
  }

  @discardableResult
  mutating func reconcileDerivedIndexShapes(attributes: AttributeStore) -> Set<String> {
    let currentShapes = Self.derivedIndexAttributeShapes(for: attributes)
    guard derivedIndexAttributeShapes != currentShapes else { return [] }
    return rebuildDerivedIndexes(attributes: attributes)
  }

  /// Moves only relation slots whose physical identity changed during a schema merge.
  ///
  /// Earlier reconciliation first materialized and sorted every resident triple, even when a
  /// merge added only scalar metadata. Scribe's long recordings make that a large transient
  /// allocation. This path discovers remaps from the schema, materializes only obsolete slots,
  /// and leaves all unrelated EAV storage in place. Exact canonical collisions retain the newest
  /// transaction stamp, with transaction ID as the deterministic tie-break.
  @discardableResult
  mutating func reconcileRelationStorage(
    previousAttributes: AttributeStore,
    mergedAttributes: AttributeStore
  ) -> RelationStorageReconciliationResult {
    let remappedAttributeIDs = mergedAttributes.remappedRelationAttributeIDs(
      from: previousAttributes
    )
    guard !remappedAttributeIDs.isEmpty else {
      return RelationStorageReconciliationResult(
        changedEntityIDs: reconcileDerivedIndexShapes(attributes: mergedAttributes)
      )
    }

    var result = RelationStorageReconciliationResult()
    var sourceTriples: [InstantTriple] = []
    for (entityID, attributesByID) in eav {
      for attributeID in remappedAttributeIDs {
        guard let slot = attributesByID[attributeID] else { continue }
        result.metrics.examinedAttributeSlotCount += 1
        sourceTriples.reserveCapacity(sourceTriples.count + slot.count)
        slot.forEachPair { value, stamp in
          result.metrics.examinedTripleCount += 1
          sourceTriples.append(
            materializeTriple(
              entityID: entityID,
              attributeID: attributeID,
              value: value,
              stamp: stamp
            )
          )
        }
      }
    }

    guard !sourceTriples.isEmpty else {
      result.changedEntityIDs = reconcileDerivedIndexShapes(attributes: mergedAttributes)
      return result
    }

    var canonicalByIdentity: [StoredTripleIdentity: InstantTriple] = [:]
    var remappedDeferredKeys: Set<EntityAttributeKey> = []
    for sourceTriple in sourceTriples {
      guard
        let previousAttribute = previousAttributes.exactAttribute(id: sourceTriple.attributeID),
        let logicalForwardIdentity = previousAttribute.forwardIdentity
      else { continue }
      let canonicalTriple = mergedAttributes.canonicalizedStorageTriple(
        sourceTriple,
        logicalAttributeID: logicalForwardIdentity
      )
      let identity = StoredTripleIdentity(
        entityID: canonicalTriple.entityID,
        attributeID: canonicalTriple.attributeID,
        value: canonicalTriple.value
      )
      if let existing = canonicalByIdentity[identity] {
        if Self.transactionStampPrecedes(existing, canonicalTriple) {
          canonicalByIdentity[identity] = canonicalTriple
        }
      } else {
        canonicalByIdentity[identity] = canonicalTriple
      }

      let sourceKey = EntityAttributeKey(
        entityID: sourceTriple.entityID,
        attributeID: sourceTriple.attributeID
      )
      if deferredValueKeysToRemove.contains(sourceKey) {
        remappedDeferredKeys.insert(
          EntityAttributeKey(
            entityID: canonicalTriple.entityID,
            attributeID: canonicalTriple.attributeID
          )
        )
      }
      result.changedEntityIDs.formUnion(Self.entityIDsAffected(by: sourceTriple))
      result.changedEntityIDs.formUnion(Self.entityIDsAffected(by: canonicalTriple))
    }

    // Remove every obsolete slot before inserting canonical candidates. This prevents a reverse
    // source from competing with itself after transposition and lets `insert` retain its ordinary
    // cardinality semantics for the physical attribute.
    for sourceTriple in sourceTriples {
      removeNormalized(
        sourceTriple,
        attribute: previousAttributes.exactAttribute(id: sourceTriple.attributeID)
      )
      deferredValueKeysToRemove.remove(
        EntityAttributeKey(
          entityID: sourceTriple.entityID,
          attributeID: sourceTriple.attributeID
        )
      )
    }

    for canonicalTriple in canonicalByIdentity.values.sorted(by: Self.triplePrecedes) {
      let physicalAttribute = mergedAttributes.exactAttribute(id: canonicalTriple.attributeID)
        ?? mergedAttributes[canonicalTriple.attributeID]
      guard shouldInstallReconciledTriple(canonicalTriple, attribute: physicalAttribute) else {
        continue
      }
      removeCompetingReconciledTriples(
        for: canonicalTriple,
        attribute: physicalAttribute
      )
      insert(canonicalTriple, attribute: physicalAttribute)
      result.metrics.movedTripleCount += 1
    }
    deferredValueKeysToRemove.formUnion(remappedDeferredKeys)
    result.changedEntityIDs.formUnion(
      reconcileDerivedIndexShapes(attributes: mergedAttributes)
    )
    return result
  }

  mutating func markDeferredValue(entityID: String, attributeID: String) {
    deferredValueKeysToRemove.insert(
      EntityAttributeKey(entityID: entityID, attributeID: attributeID)
    )
  }

  var pendingDeferredValueRemovalCount: Int {
    deferredValueKeysToRemove.count
  }

  @discardableResult
  mutating func removeMarkedDeferredValues(
    attributes: AttributeStore
  ) -> DeferredValueRemovalMetrics {
    var metrics = DeferredValueRemovalMetrics()
    while let key = deferredValueKeysToRemove.popFirst() {
      metrics.examinedKeyCount += 1
      guard let slot = eav[key.entityID]?[key.attributeID] else { continue }
      metrics.residentKeyCount += 1
      metrics.removedValueCount += slot.count
      var values: [(InstantValue, InstantTripleStamp)] = []
      values.reserveCapacity(slot.count)
      slot.forEachPair { value, stamp in
        values.append((value, stamp))
      }
      for (value, stamp) in values {
        removeNormalized(
          materializeTriple(
            entityID: key.entityID,
            attributeID: key.attributeID,
            value: value,
            stamp: stamp
          ),
          attribute: attributes[key.attributeID]
        )
      }
    }
    return metrics
  }

  var triples: [InstantTriple] {
    var triples: [InstantTriple] = []
    triples.reserveCapacity(tripleCount)
    for entityID in eav.keys.sorted() {
      guard let attributesByID = eav[entityID] else { continue }
      for attributeID in attributesByID.keys.sorted() {
        guard let slot = attributesByID[attributeID] else { continue }
        var reconstructed: [InstantTriple] = []
        reconstructed.reserveCapacity(slot.count)
        slot.forEachPair { value, stamp in
          reconstructed.append(
            materializeTriple(entityID: entityID, attributeID: attributeID, value: value, stamp: stamp)
          )
        }
        if reconstructed.count == 1, let triple = reconstructed.first {
          triples.append(triple)
        } else {
          triples.append(contentsOf: reconstructed.sorted(by: Self.triplePrecedes))
        }
      }
    }
    return triples
  }

  /// Maintained by `insert` and `removeNormalized`, the only two writers that change how many
  /// triples `eav` holds.
  ///
  /// `InstantStore.prepare` reads this on every applied transaction and every terminal-failure
  /// removal, so walking every entity × attribute × value made each of those proportional to the
  /// whole store. See
  /// `InstantStoreWriteScalingTests.maintainedTripleCountMatchesAFreshWalkThroughEveryMutation`.
  var tripleCount: Int {
    storedTripleCount
  }

  var newestTransactionTimeMilliseconds: Int64? {
    var newest: Int64?
    for attributesByID in eav.values {
      for slot in attributesByID.values {
        for stamp in slot.values {
          let milliseconds = stamp.txTime.milliseconds
          if let newestMilliseconds = newest {
            if milliseconds > newestMilliseconds {
              newest = milliseconds
            }
          } else {
            newest = milliseconds
          }
        }
      }
    }
    return newest
  }

  func triples(entityID: String) -> [InstantTriple] {
    guard let attributesByID = eav[entityID] else { return [] }
    return materializedTriples(entityID: entityID, attributesByID: attributesByID)
  }

  func copiedAttributeSlots(entityID: String) -> [String: AttrSlot]? {
    eav[entityID]
  }

  func materializedTriples(
    entityID: String,
    attributesByID: [String: AttrSlot]
  ) -> [InstantTriple] {
    var result: [InstantTriple] = []
    result.reserveCapacity(attributesByID.count)
    for (attributeID, slot) in attributesByID {
      slot.forEachPair { value, stamp in
        result.append(
          materializeTriple(
            entityID: entityID,
            attributeID: attributeID,
            value: value,
            stamp: stamp
          )
        )
      }
    }
    if result.count <= 1 {
      return result
    }
    return result.sorted(by: Self.triplePrecedes)
  }

  func namespaces(entityID: String, attributes: AttributeStore) -> Set<String> {
    var namespaces: Set<String> = []
    if let attributesByID = eav[entityID] {
      for attributeID in attributesByID.keys {
        if let namespace = attributes[attributeID]?.namespace {
          namespaces.insert(namespace)
        }
      }
    }
    if hasIncomingReferences(entityID) {
      for triple in reverseRefTriples(targetEntityID: entityID) {
        if let namespace = attributes[triple.attributeID]?.linkNamespace {
          namespaces.insert(namespace)
        }
      }
    }
    return namespaces
  }

  /// `lazy` matters here: the outbox is rescanned on every inbound server event, and this is asked
  /// once per write key in that scan. Materialising an array per key just to take a maximum made
  /// the scan allocate in proportion to outbox depth × versions per key.
  func newestWriteTime(entityID: String, attributeID: String) -> InstantTimestamp? {
    eav[entityID]?[attributeID]?.values.lazy.map(\.txTime).max()
  }

  mutating func reserveCapacity(entityCapacity: Int, attributeCapacity: Int) {
    guard entityCapacity > 0 || attributeCapacity > 0 else { return }
    eav.reserveCapacity(eav.count + max(entityCapacity, 0))
    vae.reserveCapacity(vae.count + max(entityCapacity, 0))
    pendingInternSnapshots.reserveCapacity(
      pendingInternSnapshots.count + max(entityCapacity, 0)
    )
  }

  func containsEntity(
    _ entityID: String,
    namespace: String?,
    attributes: AttributeStore
  ) -> Bool {
    guard let attributesByID = eav[entityID] else { return false }
    guard let namespace else { return !attributesByID.isEmpty }

    let idAttribute = attributes.primaryKeyAttribute(namespace: namespace)
    if attributesByID[idAttribute.id] != nil {
      return true
    }

    return attributesByID.keys.contains { attributeID in
      attributes[attributeID]?.namespace == namespace
    }
  }

  func containsTriple(
    entityID: String,
    attributeID: String,
    value: InstantValue,
    attribute: InstantAttribute?
  ) -> Bool {
    eav[entityID]?[attributeID]?[Self.normalizedValue(value, attribute: attribute)] != nil
  }

  func entityIDs(
    matching lookup: InstantLookupRef,
    lookupAttribute: InstantResolvedLookupAttribute
  ) -> [String] {
    switch lookupAttribute.direction {
    case .forward:
      let value = Self.normalizedValue(
        lookup.value.instantValue,
        attribute: lookupAttribute.attribute
      )
      let attributeID = lookupAttribute.attribute.id
      if lookupAttribute.attribute.isIndexed,
        let hits = indexedValueEntities[attributeID]?[value]
      {
        return hits.sorted()
      }
      var entityIDs: [String] = []
      if let namespaceMembers = entitiesByNamespace[lookupAttribute.namespace] {
        for entityID in namespaceMembers {
          if eav[entityID]?[attributeID]?[value] != nil {
            entityIDs.append(entityID)
          }
        }
      } else {
        for (entityID, attributesByID) in eav {
          if attributesByID[attributeID]?[value] != nil {
            entityIDs.append(entityID)
          }
        }
      }
      return entityIDs.sorted()

    case .reverse:
      guard case let .ref(sourceID) = lookup.value else { return [] }
      let targetIDs = eav[sourceID]?[lookupAttribute.attribute.id]?.keys
        .compactMap(\.refValue)
        ?? []
      return Array(Set(targetIDs)).sorted()
    }
  }


  func entityIDsReferencing(
    _ targetEntityID: String,
    attributeID: String? = nil
  ) -> [String] {
    let target = InstantValue.ref(targetEntityID)
    if let attributeID {
      return (vae[target]?[attributeID]?.keys.sorted()) ?? []
    }
    var ids = Set<String>()
    if let byAttr = vae[target] {
      for byEntity in byAttr.values {
        ids.formUnion(byEntity.keys)
      }
    }
    return ids.sorted()
  }

  func reverseRefTriples(targetEntityID: String) -> [InstantTriple] {
    guard let byAttribute = vae[.ref(targetEntityID)] else { return [] }
    var triples: [InstantTriple] = []
    for (attributeID, byEntity) in byAttribute {
      for (entityID, stamp) in byEntity {
        triples.append(
          materializeTriple(
            entityID: entityID,
            attributeID: attributeID,
            value: .ref(targetEntityID),
            stamp: stamp
          )
        )
      }
    }
    return triples
  }


  @discardableResult
  mutating func apply(
    _ operation: InstantTripleOperation,
    attributes: AttributeStore,
    insertReplayPolicy: InstantTripleInsertReplayPolicy = .replaceAndInvalidate
  ) -> Set<String> {
    var changed: Set<String> = []
    apply(
      operation,
      attributes: attributes,
      insertReplayPolicy: insertReplayPolicy,
      into: &changed
    )
    return changed
  }

  private mutating func unionReconcile(
    entityID: String,
    attributeID: String,
    attributes: AttributeStore,
    into changed: inout Set<String>
  ) {
    let declared = attributes[attributeID]
    if derivedIndexAttributeShapes[attributeID]
      != declared.map(DerivedIndexAttributeShape.init)
    {
      changed.formUnion(rebuildDerivedIndexes(attributes: attributes))
    }
    if declared?.cardinality == .one,
      eav[entityID]?[attributeID]?.count ?? 0 > 1
    {
      changed.formUnion(rebuildDerivedIndexes(attributes: attributes))
    }
  }

  private func isExactVisibleSlot(
    _ triple: InstantTriple,
    attribute: InstantAttribute?
  ) -> Bool {
    let value = Self.normalizedValue(triple.value, attribute: attribute)
    guard let slot = eav[triple.entityID]?[triple.attributeID],
      let stamp = slot[value]
    else {
      return false
    }
    // A schema can be learned or corrected after unknown/many values were indexed. In that case
    // an exact insert still has work to do: reconcile the slot and every derived lookup index.
    guard let attribute else {
      if case .many = slot { return true }
      return false
    }
    guard derivedIndexAttributeShapes[triple.attributeID] == DerivedIndexAttributeShape(attribute),
      entitiesByNamespace[attribute.namespace]?.contains(triple.entityID) == true
    else {
      return false
    }
    switch (attribute.cardinality, slot) {
    case (.one, .one), (.many, .many):
      break
    default:
      return false
    }
    if attribute.valueType == .ref,
      vae[value]?[triple.attributeID]?[triple.entityID] != stamp
    {
      return false
    }
    if attribute.isIndexed {
      guard indexedValueEntities[triple.attributeID]?[value]?.contains(triple.entityID) == true
      else { return false }
      if attribute.cardinality == .one,
        indexedEntityValues[triple.attributeID]?[triple.entityID] != value
      {
        return false
      }
    }
    return true
  }

  @discardableResult
  private mutating func rebuildDerivedIndexes(attributes: AttributeStore) -> Set<String> {
    var normalizedEAV: [String: [String: AttrSlot]] = [:]
    normalizedEAV.reserveCapacity(eav.count)
    var changedEntityIDs: Set<String> = []
    for (entityID, attributesByID) in eav {
      var normalizedAttributes: [String: AttrSlot] = [:]
      normalizedAttributes.reserveCapacity(attributesByID.count)
      for (attributeID, slot) in attributesByID {
        let normalized = normalizedSlot(
          slot,
          attribute: attributes[attributeID]
        )
        normalizedAttributes[attributeID] = normalized
        if normalized.count != slot.count {
          changedEntityIDs.insert(entityID)
        }
      }
      normalizedEAV[entityID] = normalizedAttributes
    }
    eav = normalizedEAV
    storedTripleCount = Self.walkedTripleCount(eav)
    vae = [:]
    indexedValueEntities = [:]
    indexedEntityValues = [:]
    uniqueInternCaches()
    internCaches.clearAll()
    clearPendingInternCaches()
    entitiesByNamespace = [:]
    clearWriteCursors()
    derivedIndexAttributeShapes = Self.derivedIndexAttributeShapes(for: attributes)

    // Copy-on-write keeps the authoritative EAV storage resident while these smaller maps rebuild.
    // Schema changes are rare, and subsequent exact inserts see the recorded attribute shape.
    let residentEAV = eav
    for (entityID, attributesByID) in residentEAV {
      for (attributeID, slot) in attributesByID {
        guard let attribute = attributes[attributeID] else { continue }
        entitiesByNamespace[attribute.namespace, default: []].insert(entityID)
        for value in slot.keys {
          guard let stamp = slot[value] else { continue }
          if attribute.valueType == .ref {
            vae[value, default: [:]][attributeID, default: [:]][entityID] = stamp
          }
          if attribute.isIndexed {
            indexIndexedAttributeInsert(
              entityID: entityID,
              attributeID: attributeID,
              value: value,
              cardinalityOne: attribute.cardinality == .one
            )
          }
        }
      }
    }
    return changedEntityIDs
  }

  private func normalizedSlot(
    _ slot: AttrSlot,
    attribute: InstantAttribute?
  ) -> AttrSlot {
    switch slot {
    case let .one(value, stamp):
      return .one(
        value: Self.normalizedValue(value, attribute: attribute),
        stamp: stamp
      )

    case .many:
      var normalized: [InstantValue: InstantTripleStamp] = [:]
      for value in slot.keys.sorted(by: { $0.comparableKey < $1.comparableKey }) {
        guard let stamp = slot[value] else { continue }
        let normalizedValue = Self.normalizedValue(value, attribute: attribute)
        if let existing = normalized[normalizedValue] {
          if stamp.txTime > existing.txTime
            || (stamp.txTime == existing.txTime
              && resolvedTxID(at: stamp.txIDIndex) > resolvedTxID(at: existing.txIDIndex))
          {
            normalized[normalizedValue] = stamp
          }
        } else {
          normalized[normalizedValue] = stamp
        }
      }
      if attribute?.cardinality == .one,
        let winner = normalized.max(by: { lhs, rhs in
          entryPrecedes(
            lhsValue: lhs.key,
            lhsStamp: lhs.value,
            rhsValue: rhs.key,
            rhsStamp: rhs.value
          )
        })
      {
        return .one(value: winner.key, stamp: winner.value)
      }
      return .many(normalized)
    }
  }

  private func entryPrecedes(
    lhsValue: InstantValue,
    lhsStamp: InstantTripleStamp,
    rhsValue: InstantValue,
    rhsStamp: InstantTripleStamp
  ) -> Bool {
    if lhsStamp.txTimeMilliseconds != rhsStamp.txTimeMilliseconds {
      return lhsStamp.txTimeMilliseconds < rhsStamp.txTimeMilliseconds
    }
    let lhsTransactionID = resolvedTxID(at: lhsStamp.txIDIndex)
    let rhsTransactionID = resolvedTxID(at: rhsStamp.txIDIndex)
    if lhsTransactionID != rhsTransactionID {
      return lhsTransactionID < rhsTransactionID
    }
    return lhsValue.comparableKey < rhsValue.comparableKey
  }

  private static func derivedIndexAttributeShapes(
    for attributes: AttributeStore
  ) -> [String: DerivedIndexAttributeShape] {
    Dictionary(
      uniqueKeysWithValues: attributes.attributes.map {
        ($0.id, DerivedIndexAttributeShape($0))
      }
    )
  }

  private mutating func reconcileDerivedIndexShape(
    for attributeID: String,
    attributes: AttributeStore
  ) -> Set<String> {
    guard
      derivedIndexAttributeShapes[attributeID]
        != attributes[attributeID].map(DerivedIndexAttributeShape.init)
    else { return [] }
    return rebuildDerivedIndexes(attributes: attributes)
  }

  private mutating func reconcileMalformedCardinalityOneSlot(
    entityID: String,
    attributeID: String,
    attributes: AttributeStore
  ) -> Set<String> {
    guard attributes[attributeID]?.cardinality == .one,
      eav[entityID]?[attributeID]?.count ?? 0 > 1
    else { return [] }
    return rebuildDerivedIndexes(attributes: attributes)
  }

  mutating func materialize(
    _ plan: InstantQueryPlan,
    attributes: AttributeStore,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) -> [InstantEntitySnapshot] {
    let __values: [InstantEntitySnapshot]
    if let values = materializeIndexedEqualsPrefix(
      plan,
      attributes: attributes,
      remotePageInfo: remotePageInfo
    ) {
      __values = values
    } else if let values = materializeInternedSimpleOrderedPage(
      plan,
      attributes: attributes,
      remotePageInfo: remotePageInfo
    ) {
      __values = values
    } else {
      __values = materializePage(plan, attributes: attributes, remotePageInfo: remotePageInfo)
        .values
    }
    return __values
  }

  func materializePage(
    _ plan: InstantQueryPlan,
    attributes: AttributeStore,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) -> InstantQueryPage {
    materializePageWithMetrics(
      plan,
      attributes: attributes,
      remotePageInfo: remotePageInfo
    ).page
  }

  func materializePageWithMetrics(
    _ plan: InstantQueryPlan,
    attributes: AttributeStore,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) -> (page: InstantQueryPage, metrics: QueryMaterializationMetrics) {
    var metrics = QueryMaterializationMetrics()
    let page = materializePage(
      plan,
      attributes: attributes,
      remotePageInfo: remotePageInfo,
      metrics: &metrics
    )
    return (page, metrics)
  }

  private mutating func materializeIndexedEqualsPrefix(
    _ plan: InstantQueryPlan,
    attributes: AttributeStore,
    remotePageInfo: InstantQueryRemotePageInfo?
  ) -> [InstantEntitySnapshot]? {
    guard remotePageInfo == nil,
      plan.includes == nil,
      plan.selectedFields == nil,
      plan.offset == nil,
      plan.first == nil,
      plan.last == nil,
      plan.after == nil,
      plan.before == nil,
      let limit = plan.limit,
      !plan.filters.isEmpty
    else { return nil }

    let order = Self.effectiveOrder(plan.order)
    guard order.isServerCreatedAt else { return nil }

    let resultKey = IndexedEqualsResultKey(
      namespace: plan.namespace,
      limit: limit,
      isAscending: order.direction == .ascending,
      filters: plan.filters
    )
    if let interned = internCaches.internedIndexedEqualsResults[resultKey] {
      return interned
    }
    uniqueInternCaches()

    let candidateSource = resolveBoundedCandidateSource(plan: plan, attributes: attributes)
    guard candidateSource.filtersFullyCoveredByIndex else { return nil }

    var entityIDs: [String] = []
    forEachEntityID(in: candidateSource) { entityIDs.append($0) }

    var ranked: [(createdAt: InstantValue, entityID: String)] = []
    ranked.reserveCapacity(entityIDs.count)
    for entityID in entityIDs {
      if let createdAt = internCaches.internedServerCreatedAt[entityID] {
        ranked.append((createdAt, entityID))
        continue
      }
      guard
        let createdAt = serverCreatedAtValue(
          entityID: entityID,
          namespace: plan.namespace,
          attributes: attributes
        )
      else { return nil }
      internCaches.internedServerCreatedAt[entityID] = createdAt
      ranked.append((createdAt, entityID))
    }

    ranked.sort { lhs, rhs in
      let valueComparison = Self.compare(lhs.createdAt, rhs.createdAt)
      let directedComparison: ComparisonResult
      switch order.direction {
      case .ascending:
        directedComparison = valueComparison
      case .descending:
        directedComparison = valueComparison.reversed
      }
      if directedComparison != .orderedSame {
        return directedComparison == .orderedAscending
      }
      switch order.direction {
      case .ascending:
        return lhs.entityID < rhs.entityID
      case .descending:
        return lhs.entityID > rhs.entityID
      }
    }

    if ranked.count > limit {
      ranked.removeLast(ranked.count - limit)
    }

    var snapshots: [InstantEntitySnapshot] = []
    snapshots.reserveCapacity(ranked.count)
    for item in ranked {
      if let interned = internCaches.internedSnapshot(
        entityID: item.entityID,
        namespace: plan.namespace
      ) {
        snapshots.append(interned)
        continue
      }
      guard
        let row = self.snapshot(
          entityID: item.entityID,
          namespace: plan.namespace,
          attributes: attributes
        )
      else { return nil }
      internCaches.storeSnapshot(row, entityID: item.entityID)
      snapshots.append(row)
    }
    internCaches.internedIndexedEqualsResults[resultKey] = snapshots
    return snapshots
  }

  func entityMatches(
    _ entityID: String,
    plan: InstantQueryPlan,
    attributes: AttributeStore
  ) -> Bool {
    entitySnapshot(entityID, plan: plan, attributes: attributes, projecting: false) != nil
  }

  /// Materializes one entity against `plan` filters, includes, and selected fields.
  /// Returns nil when the entity is missing or no longer matches the plan.
  func entitySnapshot(
    _ entityID: String,
    plan: InstantQueryPlan,
    attributes: AttributeStore
  ) -> InstantEntitySnapshot? {
    entitySnapshot(entityID, plan: plan, attributes: attributes, projecting: true)
  }

  private func entitySnapshot(
    _ entityID: String,
    plan: InstantQueryPlan,
    attributes: AttributeStore,
    projecting: Bool
  ) -> InstantEntitySnapshot? {
    guard
      let snapshot = snapshot(
        entityID: entityID,
        namespace: plan.namespace,
        attributes: attributes
      )
    else { return nil }
    guard
      matches(
        snapshot,
        filters: plan.filters,
        namespace: plan.namespace,
        attributes: attributes
      )
    else { return nil }
    guard projecting else { return snapshot }
    var metrics = QueryMaterializationMetrics()
    let linked = includeLinks(
      [snapshot],
      plan: plan,
      attributes: attributes,
      metrics: &metrics
    )
    return project(linked, selectedFields: plan.selectedFields).first
  }

  private func materializePage(
    _ plan: InstantQueryPlan,
    attributes: AttributeStore,
    remotePageInfo: InstantQueryRemotePageInfo?,
    metrics: inout QueryMaterializationMetrics
  ) -> InstantQueryPage {
    let effectiveOrder = Self.effectiveOrder(plan.order)
    if Self.hasFiniteResultBound(plan), Self.supportsBoundedSelection(plan) {
      let candidateSource = resolveBoundedCandidateSource(plan: plan, attributes: attributes)
      return materializeBoundedPage(
        plan,
        order: effectiveOrder,
        candidateSource: candidateSource,
        attributes: attributes,
        remotePageInfo: remotePageInfo,
        metrics: &metrics
      )
    }

    if let page = materializeSimpleOrderedPage(
      plan,
      order: effectiveOrder,
      attributes: attributes,
      remotePageInfo: remotePageInfo
    ) {
      return page
    }

    if let snapshots = materializeOrderedSnapshots(
      plan,
      order: effectiveOrder,
      attributes: attributes
    ) {
      let paged = paginate(
        snapshots,
        plan: plan,
        effectiveOrder: effectiveOrder,
        attributes: attributes,
        remotePageInfo: remotePageInfo
      )
      let linked = includeLinks(
        paged.values.map(\.snapshot),
        plan: plan,
        attributes: attributes,
        metrics: &metrics
      )
      return InstantQueryPage(
        values: project(linked, selectedFields: plan.selectedFields),
        pageInfo: paged.pageInfo
      )
    }

    let candidateResolution = resolveCandidateEntityIDs(plan: plan, attributes: attributes)
    let filtersFullyCoveredByIndex = candidateResolution.filtersFullyCoveredByIndex
    var snapshots: [QuerySnapshot] = []
    snapshots.reserveCapacity(
      min(candidateResolution.ids.count, plan.limit ?? candidateResolution.ids.count)
    )
    let needsServerCreated = needsServerCreatedAt(effectiveOrder)

    for entityID in candidateResolution.ids {
      guard
        let snapshot = snapshot(
          entityID: entityID,
          namespace: plan.namespace,
          attributes: attributes
        )
      else { continue }
      if !filtersFullyCoveredByIndex {
        guard matches(
          snapshot,
          filters: plan.filters,
          namespace: plan.namespace,
          attributes: attributes
        )
        else { continue }
      }
      let serverCreatedAt = needsServerCreated
        ? serverCreatedAtValue(
          entityID: entityID,
          namespace: plan.namespace,
          attributes: attributes
        )
        : nil
      snapshots.append(
        QuerySnapshot(
          snapshot: snapshot,
          serverCreatedAt: serverCreatedAt,
          sortValue: Self.orderValue(
            snapshot,
            serverCreatedAt: serverCreatedAt,
            field: effectiveOrder.field
          )
        )
      )
    }

    snapshots.sort {
      Self.compare($0, $1, order: effectiveOrder) == .orderedAscending
    }

    let paged = paginate(
      snapshots,
      plan: plan,
      effectiveOrder: effectiveOrder,
      attributes: attributes,
      remotePageInfo: remotePageInfo
    )
    let linked = includeLinks(
      paged.values.map(\.snapshot),
      plan: plan,
      attributes: attributes,
      metrics: &metrics
    )
    return InstantQueryPage(
      values: project(linked, selectedFields: plan.selectedFields),
      pageInfo: paged.pageInfo
    )
  }

  private struct CandidateResolution: Sendable {
    var ids: [String]
    /// True when every filter was a simple indexed equality used to build `ids`.
    var filtersFullyCoveredByIndex: Bool
  }

  private struct BoundedCandidateSource: Sendable {
    var baseEntityIDs: Set<String>?
    var additionalMemberships: [Set<String>]
    var filtersFullyCoveredByIndex: Bool
    var candidateNamespaceIsKnown: Bool
  }

  private enum RetainedCandidateEnd: Sendable {
    case first
    case last
  }

  private struct BoundedSelectionConfiguration: Sendable {
    var capacity: Int
    var retainedEnd: RetainedCandidateEnd
  }

  private struct BoundedCandidateBuffer: Sendable {
    var capacity: Int
    var retainedEnd: RetainedCandidateEnd
    var heap: [QuerySnapshot] = []

    mutating func insert(_ candidate: QuerySnapshot, order: InstantQueryOrder?) {
      guard capacity > 0 else { return }
      if heap.count < capacity {
        heap.append(candidate)
        siftUp(from: heap.count - 1, order: order)
        return
      }
      guard let root = heap.first, shouldReplaceRoot(root, with: candidate, order: order)
      else { return }
      heap[0] = candidate
      siftDown(from: 0, order: order)
    }

    func sorted(order: InstantQueryOrder?) -> [QuerySnapshot] {
      heap.sorted {
        TripleIndexes.compare($0, $1, order: order) == .orderedAscending
      }
    }

    private func shouldReplaceRoot(
      _ root: QuerySnapshot,
      with candidate: QuerySnapshot,
      order: InstantQueryOrder?
    ) -> Bool {
      switch retainedEnd {
      case .first:
        return TripleIndexes.compare(candidate, root, order: order) == .orderedAscending
      case .last:
        return TripleIndexes.compare(root, candidate, order: order) == .orderedAscending
      }
    }

    private mutating func siftUp(from index: Int, order: InstantQueryOrder?) {
      var childIndex = index
      while childIndex > 0 {
        let parentIndex = (childIndex - 1) / 2
        guard hasRootPriority(heap[childIndex], over: heap[parentIndex], order: order)
        else { return }
        heap.swapAt(childIndex, parentIndex)
        childIndex = parentIndex
      }
    }

    private mutating func siftDown(from index: Int, order: InstantQueryOrder?) {
      var parentIndex = index
      while true {
        let leftIndex = parentIndex * 2 + 1
        guard leftIndex < heap.count else { return }
        let rightIndex = leftIndex + 1
        var childIndex = leftIndex
        if rightIndex < heap.count,
          hasRootPriority(heap[rightIndex], over: heap[leftIndex], order: order)
        {
          childIndex = rightIndex
        }
        guard hasRootPriority(heap[childIndex], over: heap[parentIndex], order: order)
        else { return }
        heap.swapAt(parentIndex, childIndex)
        parentIndex = childIndex
      }
    }

    private func hasRootPriority(
      _ lhs: QuerySnapshot,
      over rhs: QuerySnapshot,
      order: InstantQueryOrder?
    ) -> Bool {
      let comparison = TripleIndexes.compare(lhs, rhs, order: order)
      switch retainedEnd {
      case .first:
        return comparison == .orderedDescending
      case .last:
        return comparison == .orderedAscending
      }
    }
  }

  private enum BoundedRangePosition {
    case inside
    case before
    case after
  }

  private static func hasFiniteResultBound(_ plan: InstantQueryPlan) -> Bool {
    plan.limit != nil || plan.first != nil || plan.last != nil
  }

  private static func supportsBoundedSelection(_ plan: InstantQueryPlan) -> Bool {
    (plan.after == nil || plan.after?.sortValue != nil)
      && (plan.before == nil || plan.before?.sortValue != nil)
  }

  private func resolveBoundedCandidateSource(
    plan: InstantQueryPlan,
    attributes: AttributeStore
  ) -> BoundedCandidateSource {
    var indexedHitSets: [Set<String>] = []
    var coveredFilterCount = 0
    for filter in plan.filters {
      guard case let .equals(field, rawValue) = filter,
        nestedField(field) == nil,
        let attribute = attributes.attribute(namespace: plan.namespace, name: field),
        attribute.isIndexed
      else { continue }
      let hits: Set<String>
      if attribute.primaryKey {
        guard let entityID = Self.entityID(fromPrimaryKeyValue: rawValue) else {
          indexedHitSets.append([])
          coveredFilterCount += 1
          continue
        }
        hits = entitiesByNamespace[plan.namespace]?.contains(entityID) == true
          ? [entityID]
          : []
      } else {
        let value = Self.normalizedValue(rawValue, attribute: attribute)
        hits = indexedValueEntities[attribute.id]?[value] ?? []
      }
      indexedHitSets.append(hits)
      coveredFilterCount += 1
    }

    let filtersFullyCoveredByIndex =
      !plan.filters.isEmpty
      && coveredFilterCount == plan.filters.count
      && !indexedHitSets.isEmpty
    if let baseIndex = indexedHitSets.indices.min(by: {
      indexedHitSets[$0].count < indexedHitSets[$1].count
    }) {
      let baseEntityIDs = indexedHitSets.remove(at: baseIndex)
      return BoundedCandidateSource(
        baseEntityIDs: baseEntityIDs,
        additionalMemberships: indexedHitSets,
        filtersFullyCoveredByIndex: filtersFullyCoveredByIndex,
        candidateNamespaceIsKnown: true
      )
    }
    if let namespaceEntityIDs = entitiesByNamespace[plan.namespace] {
      return BoundedCandidateSource(
        baseEntityIDs: namespaceEntityIDs,
        additionalMemberships: [],
        filtersFullyCoveredByIndex: false,
        candidateNamespaceIsKnown: true
      )
    }
    return BoundedCandidateSource(
      baseEntityIDs: nil,
      additionalMemberships: [],
      filtersFullyCoveredByIndex: false,
      candidateNamespaceIsKnown: false
    )
  }

  private func forEachEntityID(
    in candidateSource: BoundedCandidateSource,
    _ body: (String) -> Void
  ) {
    if let baseEntityIDs = candidateSource.baseEntityIDs {
      for entityID in baseEntityIDs
      where candidateSource.additionalMemberships.allSatisfy({ $0.contains(entityID) }) {
        body(entityID)
      }
      return
    }
    for entityID in eav.keys {
      body(entityID)
    }
  }

  private func materializeBoundedPage(
    _ plan: InstantQueryPlan,
    order: InstantQueryOrder,
    candidateSource: BoundedCandidateSource,
    attributes: AttributeStore,
    remotePageInfo: InstantQueryRemotePageInfo?,
    metrics: inout QueryMaterializationMetrics
  ) -> InstantQueryPage {
    metrics.boundedSelectionCount += 1
    guard isValidPagination(plan) else {
      return InstantQueryPage(
        values: [],
        pageInfo: pageInfo(for: [], plan: plan, effectiveOrder: order)
      )
    }
    if case .waiting? = remotePageInfo, requiresRemotePageInfo(plan) {
      return InstantQueryPage(values: [], pageInfo: nil)
    }
    if case let .ready(pageInfo)? = remotePageInfo,
      requiresRemotePageInfo(plan),
      pageInfo.startCursor == nil
    {
      return InstantQueryPage(values: [], pageInfo: pageInfo)
    }
    guard
      let configuration = boundedSelectionConfiguration(
        plan,
        remotePageInfo: remotePageInfo,
        needsLookahead: !Self.hasReadyRemotePageInfo(remotePageInfo)
      )
    else {
      return InstantQueryPage(values: [], pageInfo: nil)
    }

    var buffer = BoundedCandidateBuffer(
      capacity: configuration.capacity,
      retainedEnd: configuration.retainedEnd
    )
    var removedByStartBound = false
    var removedByEndBound = false
    forEachEntityID(in: candidateSource) { entityID in
      metrics.examinedCandidateCount += 1
      guard
        let candidate = boundedQuerySnapshot(
          entityID: entityID,
          plan: plan,
          order: order,
          filtersFullyCoveredByIndex: candidateSource.filtersFullyCoveredByIndex,
          candidateNamespaceIsKnown: candidateSource.candidateNamespaceIsKnown,
          attributes: attributes,
          metrics: &metrics
        )
      else { return }
      metrics.matchingCandidateCount += 1
      switch boundedRangePosition(
        candidate,
        plan: plan,
        order: order,
        attributes: attributes,
        remotePageInfo: remotePageInfo
      ) {
      case .inside:
        buffer.insert(candidate, order: order)
        metrics.maximumRetainedCandidateCount = max(
          metrics.maximumRetainedCandidateCount,
          buffer.heap.count
        )
      case .before:
        removedByStartBound = true
      case .after:
        removedByEndBound = true
      }
    }

    return finishBoundedPage(
      buffer,
      plan: plan,
      order: order,
      attributes: attributes,
      remotePageInfo: remotePageInfo,
      removedByStartBound: removedByStartBound,
      removedByEndBound: removedByEndBound,
      metrics: &metrics
    )
  }

  private func boundedSelectionConfiguration(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo?,
    needsLookahead: Bool
  ) -> BoundedSelectionConfiguration? {
    let usesRemoteBounds: Bool
    if case .ready? = remotePageInfo, requiresRemotePageInfo(plan) {
      usesRemoteBounds = true
    } else {
      usesRemoteBounds = false
    }
    let offset = usesRemoteBounds ? 0 : (plan.offset ?? 0)
    let lookahead = needsLookahead ? 1 : 0
    if let first = plan.first, plan.last != nil {
      return BoundedSelectionConfiguration(
        capacity: Self.saturatingSum(offset, first, lookahead),
        retainedEnd: .first
      )
    }
    if let first = plan.first {
      return BoundedSelectionConfiguration(
        capacity: Self.saturatingSum(offset, min(first, plan.limit ?? first), lookahead),
        retainedEnd: .first
      )
    }
    if let last = plan.last {
      return BoundedSelectionConfiguration(
        capacity: Self.saturatingSum(offset, last, lookahead),
        retainedEnd: .last
      )
    }
    guard let leadingCount = plan.limit else { return nil }
    return BoundedSelectionConfiguration(
      capacity: Self.saturatingSum(offset, leadingCount, lookahead),
      retainedEnd: .first
    )
  }

  private static func hasReadyRemotePageInfo(
    _ remotePageInfo: InstantQueryRemotePageInfo?
  ) -> Bool {
    if case .ready? = remotePageInfo { return true }
    return false
  }

  private static func saturatingSum(_ values: Int...) -> Int {
    values.reduce(0) { result, value in
      let (sum, overflow) = result.addingReportingOverflow(value)
      return overflow ? Int.max : sum
    }
  }

  private func boundedQuerySnapshot(
    entityID: String,
    plan: InstantQueryPlan,
    order: InstantQueryOrder,
    filtersFullyCoveredByIndex: Bool,
    candidateNamespaceIsKnown: Bool,
    attributes: AttributeStore,
    metrics: inout QueryMaterializationMetrics
  ) -> QuerySnapshot? {
    let orderAttribute = order.isServerCreatedAt
      ? nil
      : attributes.attribute(namespace: plan.namespace, name: order.field)
    let readsOrderFromIndex =
      orderAttribute?.cardinality == .one && orderAttribute?.isIndexed == true
    let requiresSnapshot =
      !candidateNamespaceIsKnown
      || (!plan.filters.isEmpty && !filtersFullyCoveredByIndex)
      || (!order.isServerCreatedAt && !readsOrderFromIndex)

    let materializedSnapshot: InstantEntitySnapshot?
    if requiresSnapshot {
      guard
        let snapshot = snapshot(
          entityID: entityID,
          namespace: plan.namespace,
          attributes: attributes
        )
      else { return nil }
      metrics.materializedSnapshotCount += 1
      guard filtersFullyCoveredByIndex
        || matches(
          snapshot,
          filters: plan.filters,
          namespace: plan.namespace,
          attributes: attributes
        )
      else { return nil }
      materializedSnapshot = snapshot
    } else {
      materializedSnapshot = nil
    }

    let serverCreatedAt = order.isServerCreatedAt
      ? serverCreatedAtValue(
        entityID: entityID,
        namespace: plan.namespace,
        attributes: attributes
      )
      : nil
    let sortValue: InstantValue?
    if order.isServerCreatedAt {
      sortValue = serverCreatedAt
    } else if let orderAttribute, readsOrderFromIndex {
      sortValue = indexedEntityValues[orderAttribute.id]?[entityID]
    } else if let materializedSnapshot {
      sortValue = Self.orderValue(
        materializedSnapshot,
        serverCreatedAt: nil,
        field: order.field
      )
    } else {
      sortValue = nil
    }

    return QuerySnapshot(
      snapshot: materializedSnapshot
        ?? InstantEntitySnapshot(id: entityID, namespace: plan.namespace, values: [:]),
      serverCreatedAt: serverCreatedAt,
      sortValue: sortValue,
      isFullyMaterialized: materializedSnapshot != nil
    )
  }

  private func boundedRangePosition(
    _ candidate: QuerySnapshot,
    plan: InstantQueryPlan,
    order: InstantQueryOrder,
    attributes: AttributeStore,
    remotePageInfo: InstantQueryRemotePageInfo?
  ) -> BoundedRangePosition {
    if case let .ready(pageInfo)? = remotePageInfo, requiresRemotePageInfo(plan) {
      if let startCursor = pageInfo.startCursor,
        Self.compare(
          candidate,
          to: startCursor,
          order: order,
          namespace: plan.namespace,
          attributes: attributes
        ) == .orderedAscending
      {
        return .before
      }
      if let endCursor = pageInfo.endCursor,
        Self.compare(
          candidate,
          to: endCursor,
          order: order,
          namespace: plan.namespace,
          attributes: attributes
        ) == .orderedDescending
      {
        return .after
      }
      return .inside
    }

    if let after = plan.after {
      let comparison = Self.compare(
        candidate,
        to: after,
        order: order,
        namespace: plan.namespace,
        attributes: attributes
      )
      if after.inclusive
        ? comparison == .orderedAscending
        : comparison != .orderedDescending
      {
        return .before
      }
    }
    if let before = plan.before {
      let comparison = Self.compare(
        candidate,
        to: before,
        order: order,
        namespace: plan.namespace,
        attributes: attributes
      )
      if before.inclusive
        ? comparison == .orderedDescending
        : comparison != .orderedAscending
      {
        return .after
      }
    }
    return .inside
  }

  private func finishBoundedPage(
    _ buffer: BoundedCandidateBuffer,
    plan: InstantQueryPlan,
    order: InstantQueryOrder,
    attributes: AttributeStore,
    remotePageInfo: InstantQueryRemotePageInfo?,
    removedByStartBound: Bool,
    removedByEndBound: Bool,
    metrics: inout QueryMaterializationMetrics
  ) -> InstantQueryPage {
    var paginationPlan = plan
    if remotePageInfo == nil {
      paginationPlan.after = nil
      paginationPlan.before = nil
    }
    var paged = paginate(
      buffer.sorted(order: order),
      plan: paginationPlan,
      effectiveOrder: order,
      attributes: attributes,
      remotePageInfo: remotePageInfo
    )
    if remotePageInfo == nil, var pageInfo = paged.pageInfo {
      pageInfo.hasPreviousPage = pageInfo.hasPreviousPage || removedByStartBound
      pageInfo.hasNextPage = pageInfo.hasNextPage || removedByEndBound
      paged.pageInfo = pageInfo
    }

    var snapshots: [InstantEntitySnapshot] = []
    snapshots.reserveCapacity(paged.values.count)
    for candidate in paged.values {
      if candidate.isFullyMaterialized {
        snapshots.append(candidate.snapshot)
      } else if let snapshot = snapshot(
        entityID: candidate.snapshot.id,
        namespace: plan.namespace,
        attributes: attributes
      ) {
        metrics.materializedSnapshotCount += 1
        snapshots.append(snapshot)
      }
    }
    let linked = includeLinks(
      snapshots,
      plan: plan,
      attributes: attributes,
      metrics: &metrics
    )
    return InstantQueryPage(
      values: project(linked, selectedFields: plan.selectedFields),
      pageInfo: paged.pageInfo
    )
  }

  /// Prefer indexed equality hits, else namespace membership — never scan unrelated namespaces.
  private func resolveCandidateEntityIDs(
    plan: InstantQueryPlan,
    attributes: AttributeStore
  ) -> CandidateResolution {
    var candidate: Set<String>?
    var coveredFilterCount = 0
    for filter in plan.filters {
      guard case let .equals(field, rawValue) = filter,
        nestedField(field) == nil,
        let attribute = attributes.attribute(namespace: plan.namespace, name: field),
        attribute.isIndexed
      else { continue }
      let hits: Set<String>
      if attribute.primaryKey {
        guard let entityID = Self.entityID(fromPrimaryKeyValue: rawValue) else {
          candidate = []
          coveredFilterCount += 1
          continue
        }
        hits = entitiesByNamespace[plan.namespace]?.contains(entityID) == true
          ? [entityID]
          : []
      } else {
        let value = Self.normalizedValue(rawValue, attribute: attribute)
        hits = indexedValueEntities[attribute.id]?[value] ?? []
      }
      if let existing = candidate {
        candidate = existing.intersection(hits)
      } else {
        candidate = hits
      }
      coveredFilterCount += 1
    }
    let fullyCovered =
      !plan.filters.isEmpty && coveredFilterCount == plan.filters.count && candidate != nil
    if let candidate {
      // Indexed equality sets are unordered; sorting here is only for stable pagination
      // when no explicit order is requested later.
      return CandidateResolution(
        ids: candidate.sorted(),
        filtersFullyCoveredByIndex: fullyCovered
      )
    }
    if let members = entitiesByNamespace[plan.namespace] {
      return CandidateResolution(ids: members.sorted(), filtersFullyCoveredByIndex: false)
    }
    return CandidateResolution(ids: eav.keys.sorted(), filtersFullyCoveredByIndex: false)
  }

  private static func entityID(fromPrimaryKeyValue value: InstantValue) -> String? {
    switch value {
    case let .string(entityID), let .ref(entityID):
      return entityID
    default:
      return nil
    }
  }

  private func materializeSimpleOrderedPage(
    _ plan: InstantQueryPlan,
    order: InstantQueryOrder,
    attributes: AttributeStore,
    remotePageInfo: InstantQueryRemotePageInfo?
  ) -> InstantQueryPage? {
    guard
      Self.canMaterializeSimpleOrderedPage(plan, remotePageInfo: remotePageInfo),
      !order.isServerCreatedAt,
      let attribute = attributes.attribute(namespace: plan.namespace, name: order.field),
      attribute.cardinality == .one,
      attribute.isIndexed,
      let valuesByEntityID = indexedEntityValues[attribute.id]
    else { return nil }

    let namespaceMembers = entitiesByNamespace[plan.namespace] ?? []
    guard !valuesByEntityID.isEmpty,
      valuesByEntityID.count == namespaceMembers.count
    else { return nil }

    let orderedEntityIDs: [String]
    switch attribute.valueType {
    case .date:
      var keyed: [(key: Double, entityID: String)] = []
      keyed.reserveCapacity(valuesByEntityID.count)
      for (entityID, value) in valuesByEntityID {
        guard case let .date(date) = value else { return nil }
        keyed.append((date.timeIntervalSince1970, entityID))
      }
      orderedEntityIDs = Self.sortedEntityIDs(keyed, direction: order.direction)
    case .number:
      var keyed: [(key: Double, entityID: String)] = []
      keyed.reserveCapacity(valuesByEntityID.count)
      for (entityID, value) in valuesByEntityID {
        guard case let .number(number) = value else { return nil }
        keyed.append((number, entityID))
      }
      orderedEntityIDs = Self.sortedEntityIDs(keyed, direction: order.direction)
    case .string:
      var keyed: [(key: String, entityID: String)] = []
      keyed.reserveCapacity(valuesByEntityID.count)
      for (entityID, value) in valuesByEntityID {
        guard case let .string(text) = value else { return nil }
        keyed.append((text, entityID))
      }
      // Text ordering must match upstream InstaQL: en_US collation with a
      // native entityID tiebreak, not raw Unicode code-point order.
      switch order.direction {
      case .ascending:
        keyed.sort { lhs, rhs in
          let comparison = lhs.key.instantTextCompare(rhs.key)
          if comparison != .orderedSame { return comparison == .orderedAscending }
          return lhs.entityID < rhs.entityID
        }
      case .descending:
        keyed.sort { lhs, rhs in
          let comparison = lhs.key.instantTextCompare(rhs.key)
          if comparison != .orderedSame { return comparison == .orderedDescending }
          return lhs.entityID > rhs.entityID
        }
      }
      orderedEntityIDs = keyed.map(\.entityID)
    case .boolean, .json, .ref, .any:
      var ordered: [(entityID: String, value: InstantValue)] = []
      ordered.reserveCapacity(valuesByEntityID.count)
      for (entityID, value) in valuesByEntityID {
        ordered.append((entityID, value))
      }
      ordered.sort { lhs, rhs in
        Self.orderedValuePrecedes(
          lhs,
          rhs,
          attribute: attribute,
          direction: order.direction
        )
      }
      orderedEntityIDs = ordered.map(\.entityID)
    }

    var snapshots: [InstantEntitySnapshot] = []
    let limit = plan.limit ?? plan.first ?? orderedEntityIDs.count
    snapshots.reserveCapacity(min(limit, orderedEntityIDs.count))
    for entityID in orderedEntityIDs {
      guard
        let row = snapshot(
          entityID: entityID,
          namespace: plan.namespace,
          attributes: attributes
        )
      else { continue }
      snapshots.append(row)
      if snapshots.count >= limit { break }
    }

    return InstantQueryPage(values: snapshots, pageInfo: nil)
  }

  private static func sortedEntityIDs<Key: Comparable>(
    _ keyed: [(key: Key, entityID: String)],
    direction: InstantQuerySortDirection
  ) -> [String] {
    var keyed = keyed
    switch direction {
    case .ascending:
      keyed.sort { lhs, rhs in
        if lhs.key != rhs.key { return lhs.key < rhs.key }
        return lhs.entityID < rhs.entityID
      }
    case .descending:
      keyed.sort { lhs, rhs in
        if lhs.key != rhs.key { return lhs.key > rhs.key }
        return lhs.entityID > rhs.entityID
      }
    }
    return keyed.map(\.entityID)
  }

  private static func orderedValuePrecedes(
    _ lhs: (entityID: String, value: InstantValue),
    _ rhs: (entityID: String, value: InstantValue),
    attribute: InstantAttribute,
    direction: InstantQuerySortDirection
  ) -> Bool {
    let valueComparison = orderedValueComparison(lhs.value, rhs.value, attribute: attribute)
    let directedComparison: ComparisonResult
    switch direction {
    case .ascending:
      directedComparison = valueComparison
    case .descending:
      directedComparison = valueComparison.reversed
    }
    guard directedComparison == .orderedSame else {
      return directedComparison == .orderedAscending
    }
    switch direction {
    case .ascending:
      return lhs.entityID < rhs.entityID
    case .descending:
      return lhs.entityID > rhs.entityID
    }
  }

  private static func orderedValueComparison(
    _ lhs: InstantValue,
    _ rhs: InstantValue,
    attribute: InstantAttribute
  ) -> ComparisonResult {
    switch attribute.valueType {
    case .number:
      if case let .number(left) = lhs, case let .number(right) = rhs {
        return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
      }

    case .date:
      if case let .date(left) = lhs, case let .date(right) = rhs {
        return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
      }

    case .string:
      break

    case .boolean, .json, .ref, .any:
      break
    }

    return lhs.compare(to: rhs)
  }

  private static func canMaterializeSimpleOrderedPage(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo?
  ) -> Bool {
    plan.filters.isEmpty
      && (plan.includes?.isEmpty ?? true)
      && plan.selectedFields == nil
      && plan.offset == nil
      && plan.limit == nil
      && plan.first == nil
      && plan.after == nil
      && plan.last == nil
      && plan.before == nil
      && remotePageInfo == nil
  }

  private func materializeOrderedSnapshots(
    _ plan: InstantQueryPlan,
    order: InstantQueryOrder,
    attributes: AttributeStore
  ) -> [QuerySnapshot]? {
    guard
      !order.isServerCreatedAt,
      let attribute = attributes.attribute(namespace: plan.namespace, name: order.field),
      attribute.cardinality == .one,
      attribute.isIndexed,
      let valuesByEntityID = indexedEntityValues[attribute.id]
    else { return nil }

    let namespaceMembers = entitiesByNamespace[plan.namespace] ?? []
    // Every namespace member should have the ordered field for this fast path.
    guard !valuesByEntityID.isEmpty,
      valuesByEntityID.count == namespaceMembers.count
    else { return nil }

    var ordered: [(entityID: String, value: InstantValue)] = []
    ordered.reserveCapacity(valuesByEntityID.count)
    for (entityID, value) in valuesByEntityID {
      ordered.append((entityID, value))
    }
    ordered.sort { lhs, rhs in
      Self.orderedValuePrecedes(
        lhs,
        rhs,
        attribute: attribute,
        direction: order.direction
      )
    }

    var snapshots: [QuerySnapshot] = []
    snapshots.reserveCapacity(ordered.count)
    for (entityID, sortValue) in ordered {
      guard
        let snapshot = snapshot(
          entityID: entityID,
          namespace: plan.namespace,
          attributes: attributes
        ),
        matches(snapshot, filters: plan.filters, namespace: plan.namespace, attributes: attributes)
      else { continue }
      snapshots.append(
        QuerySnapshot(
          snapshot: snapshot,
          serverCreatedAt: nil,
          sortValue: sortValue
        )
      )
    }
    return snapshots
  }

  private func namespaceEntityCount(
    _ namespace: String,
    attributes: AttributeStore
  ) -> Int {
    if let members = entitiesByNamespace[namespace] {
      return members.count
    }
    return eav.values.reduce(into: 0) { count, attributesByID in
      if attributesByID.keys.contains(where: { attributeID in
        guard let attribute = attributes[attributeID], attribute.namespace == namespace else {
          return false
        }
        return !attribute.primaryKey || attributesByID[attribute.id] != nil
      }) {
        count += 1
      }
    }
  }

  static func validate(
    _ plan: InstantQueryPlan,
    attributes: AttributeStore
  ) -> InstantQueryValidationIssue? {
    let namespaces = attributes.namespaces
    if !namespaces.isEmpty, !namespaces.contains(plan.namespace) {
      return InstantQueryValidationIssue(
        namespace: plan.namespace,
        path: nil,
        message: "Query namespace '\(plan.namespace)' is not declared in the schema attributes.",
        recovery: "Declare the namespace before querying it, or bootstrap without schema attributes for schemaless queries."
      )
    }

    if let issue = validatePagination(
      offset: plan.offset,
      limit: plan.limit,
      first: plan.first,
      last: plan.last,
      namespace: plan.namespace
    ) {
      return issue
    }

    guard !namespaces.isEmpty else { return nil }

    if let issue = validate(filters: plan.filters, namespace: plan.namespace, attributes: attributes) {
      return issue
    }
    if let issue = validateSelectedFields(
      plan.selectedFields,
      namespace: plan.namespace,
      attributes: attributes
    ) {
      return issue
    }
    if let issue = validateOrder(plan.order, namespace: plan.namespace, attributes: attributes) {
      return issue
    }
    if let issue = validateIncludes(plan.includes, namespace: plan.namespace, attributes: attributes) {
      return issue
    }
    return nil
  }

/// Per-include materialization state for `includeLinks`.
private struct PreparedInclude {
  var name: String
  var childByID: [String: InstantLinkedEntitySnapshot]
  var parentIDs: [String: [String]]
  var orderIndex: [String: Int]
  /// Set when the included plan has a finite bound (limit/first/last/…).
  /// A shared candidate pool would let one parent's children evict
  /// another parent's from the window, so each parent materializes its
  /// own already-ordered, already-windowed child list.
  var childrenByParentID: [String: [InstantLinkedEntitySnapshot]]?
}

  private func includeLinks(
    _ snapshots: [InstantEntitySnapshot],
    plan: InstantQueryPlan,
    attributes: AttributeStore,
    metrics: inout QueryMaterializationMetrics
  ) -> [InstantEntitySnapshot] {
    guard let includes = plan.includes, !includes.isEmpty else { return snapshots }

    var preparedIncludes: [PreparedInclude] = []
    preparedIncludes.reserveCapacity(includes.count)
    for include in includes {
      // A finite bound must be applied per parent. Batch the pool only when
      // every matching child is returned unbounded.
      let includePlan = include.query?.queryPlan
      let needsPerParentWindows =
        includePlan.map(Self.hasFiniteResultBound) ?? false
      if needsPerParentWindows {
        guard
          let prepared = preparedIncludeWithPerParentWindows(
            include,
            planNamespace: plan.namespace,
            snapshots: snapshots,
            attributes: attributes,
            metrics: &metrics
          )
        else { continue }
        preparedIncludes.append(prepared)
        continue
      }
      var uniqueIDs: [String] = []
      uniqueIDs.reserveCapacity(snapshots.count)
      var seen: Set<String> = []
      var parentIDs: [String: [String]] = [:]
      parentIDs.reserveCapacity(snapshots.count)
      let childNamespace: String
      switch include.direction {
      case .forward:
        guard
          let attribute = attributes.attribute(namespace: plan.namespace, name: include.name),
          let linkNamespace = attribute.linkNamespace
        else { continue }
        childNamespace = linkNamespace
        for snapshot in snapshots {
          let ids = Self.linkedEntityIDs(snapshot.values[include.name])
          parentIDs[snapshot.id] = ids
          for id in ids where seen.insert(id).inserted {
            uniqueIDs.append(id)
          }
        }

      case .reverse:
        guard
          let attribute = reverseAttribute(
            namespace: plan.namespace,
            name: include.name,
            attributes: attributes
          )
        else { continue }
        childNamespace = attribute.namespace
        for snapshot in snapshots {
          let ids = vae[.ref(snapshot.id)]?[attribute.id].map { Array($0.keys) } ?? []
          parentIDs[snapshot.id] = ids
          for id in ids where seen.insert(id).inserted {
            uniqueIDs.append(id)
          }
        }
      }

      let sortedChildren =
        uniqueIDs.isEmpty
        ? []
        : materializeIncludedSnapshots(
          ids: uniqueIDs,
          namespace: childNamespace,
          include: include,
          attributes: attributes,
          metrics: &metrics
        )
      var childByID: [String: InstantLinkedEntitySnapshot] = [:]
      childByID.reserveCapacity(sortedChildren.count)
      var orderIndex: [String: Int] = [:]
      orderIndex.reserveCapacity(sortedChildren.count)
      for (offset, child) in sortedChildren.enumerated() {
        childByID[child.id] = child
        orderIndex[child.id] = offset
      }
      preparedIncludes.append(
        PreparedInclude(
          name: include.name,
          childByID: childByID,
          parentIDs: parentIDs,
          orderIndex: orderIndex,
          childrenByParentID: nil
        )
      )
    }

    return snapshots.map { snapshot in
      var links = snapshot.links ?? [:]
      for prepared in preparedIncludes {
        if let childrenByParentID = prepared.childrenByParentID {
          links[prepared.name] = childrenByParentID[snapshot.id] ?? []
          continue
        }
        let ids = prepared.parentIDs[snapshot.id] ?? []
        if ids.isEmpty {
          links[prepared.name] = []
          continue
        }
        let children = ids.compactMap { prepared.childByID[$0] }
        if children.count <= 1 {
          links[prepared.name] = children
          continue
        }
        links[prepared.name] = children.sorted {
          (prepared.orderIndex[$0.id] ?? 0) < (prepared.orderIndex[$1.id] ?? 0)
        }
      }
      return InstantEntitySnapshot(
        id: snapshot.id,
        namespace: snapshot.namespace,
        values: snapshot.values,
        links: links.isEmpty ? nil : links
      )
    }
  }

  /// Materializes a bounded include one parent at a time so each parent's
  /// limit window is independent. Returns nil when the direction cannot be
  /// resolved against the current schema.
  private func preparedIncludeWithPerParentWindows(
    _ include: InstantQueryInclude,
    planNamespace: String,
    snapshots: [InstantEntitySnapshot],
    attributes: AttributeStore,
    metrics: inout QueryMaterializationMetrics
  ) -> PreparedInclude? {
    var parentIDs: [String: [String]] = [:]
    parentIDs.reserveCapacity(snapshots.count)
    var childrenByParentID: [String: [InstantLinkedEntitySnapshot]] = [:]
    childrenByParentID.reserveCapacity(snapshots.count)

    func childIDs(_ snapshot: InstantEntitySnapshot) -> [String]? {
      switch include.direction {
      case .forward:
        guard
          let attribute = attributes.attribute(
            namespace: planNamespace,
            name: include.name
          ),
          let linkNamespace = attribute.linkNamespace
        else { return nil }
        var seen: Set<String> = []
        return Self.linkedEntityIDs(snapshot.values[include.name]).filter {
          seen.insert($0).inserted
        }
      case .reverse:
        guard
          let attribute = reverseAttribute(
            namespace: planNamespace,
            name: include.name,
            attributes: attributes
          )
        else { return nil }
        return vae[.ref(snapshot.id)]?[attribute.id].map { Array($0.keys) } ?? []
      }
    }

    for snapshot in snapshots {
      guard let ids = childIDs(snapshot) else { return nil }
      parentIDs[snapshot.id] = ids
      guard !ids.isEmpty else {
        childrenByParentID[snapshot.id] = []
        continue
      }
      childrenByParentID[snapshot.id] = materializeIncludedSnapshots(
        ids: ids,
        namespace: include.direction == .reverse
          ? reverseAttribute(
            namespace: planNamespace,
            name: include.name,
            attributes: attributes
          )?.namespace ?? ""
          : attributes.attribute(namespace: planNamespace, name: include.name)?
            .linkNamespace ?? "",
        include: include,
        attributes: attributes,
        metrics: &metrics
      )
    }
    return PreparedInclude(
      name: include.name,
      childByID: [:],
      parentIDs: parentIDs,
      orderIndex: [:],
      childrenByParentID: childrenByParentID
    )
  }

  private static func linkedEntityIDs(_ value: InstantMaterializedValue?) -> [String] {
    switch value {
    case let .one(stored)?:
      if let id = stored.refValue {
        return [id]
      }
      return []
    case let .many(stored)?:
      return stored.compactMap(\.refValue)
    case nil:
      return []
    }
  }

  private func materializeIncludedSnapshots<IDs: Collection>(
    ids: IDs,
    namespace: String,
    include: InstantQueryInclude,
    attributes: AttributeStore,
    metrics: inout QueryMaterializationMetrics
  ) -> [InstantLinkedEntitySnapshot] where IDs.Element == String {
    let query =
      include.query?.queryPlan
      ?? InstantQueryPlan(
        id: "\(namespace).included.\(include.name)",
        namespace: namespace
      )
    return materializeSnapshots(
      ids: ids,
      query: query,
      attributes: attributes,
      metrics: &metrics
    )
      .map(InstantLinkedEntitySnapshot.init)
  }

  private func materializeSnapshots<IDs: Collection>(
    ids: IDs,
    query: InstantQueryPlan,
    attributes: AttributeStore,
    metrics: inout QueryMaterializationMetrics
  ) -> [InstantEntitySnapshot] where IDs.Element == String {
    guard !ids.isEmpty else { return [] }
    guard isValidPagination(query) else { return [] }

    let effectiveOrder = Self.effectiveOrder(query.order)
    if Self.hasFiniteResultBound(query),
      Self.supportsBoundedSelection(query)
    {
      metrics.boundedSelectionCount += 1
      guard
        let configuration = boundedSelectionConfiguration(
          query,
          remotePageInfo: nil,
          needsLookahead: false
        )
      else { return [] }
      var buffer = BoundedCandidateBuffer(
        capacity: configuration.capacity,
        retainedEnd: configuration.retainedEnd
      )
      for entityID in ids {
        metrics.examinedCandidateCount += 1
        guard
          let candidate = boundedQuerySnapshot(
            entityID: entityID,
            plan: query,
            order: effectiveOrder,
            filtersFullyCoveredByIndex: false,
            candidateNamespaceIsKnown: true,
            attributes: attributes,
            metrics: &metrics
          )
        else { continue }
        metrics.matchingCandidateCount += 1
        buffer.insert(candidate, order: effectiveOrder)
        metrics.maximumRetainedCandidateCount = max(
          metrics.maximumRetainedCandidateCount,
          buffer.heap.count
        )
      }
      return finishBoundedPage(
        buffer,
        plan: query,
        order: effectiveOrder,
        attributes: attributes,
        remotePageInfo: nil,
        removedByStartBound: false,
        removedByEndBound: false,
        metrics: &metrics
      ).values
    }

    var snapshots: [QuerySnapshot] = []
    snapshots.reserveCapacity(ids.count)

    for entityID in ids {
      metrics.examinedCandidateCount += 1
      guard
        let snapshot = snapshot(
          entityID: entityID,
          namespace: query.namespace,
          attributes: attributes
        ),
        matches(
          snapshot,
          filters: query.filters,
          namespace: query.namespace,
          attributes: attributes
        )
      else { continue }
      metrics.matchingCandidateCount += 1
      metrics.materializedSnapshotCount += 1

      let serverCreatedAt = needsServerCreatedAt(effectiveOrder)
        ? serverCreatedAtValue(
          entityID: entityID,
          namespace: query.namespace,
          attributes: attributes
        )
        : nil
      snapshots.append(
        QuerySnapshot(
          snapshot: snapshot,
          serverCreatedAt: serverCreatedAt,
          sortValue: Self.orderValue(
            snapshot,
            serverCreatedAt: serverCreatedAt,
            field: effectiveOrder.field
          )
        )
      )
      metrics.maximumRetainedCandidateCount = max(
        metrics.maximumRetainedCandidateCount,
        snapshots.count
      )
    }

    snapshots.sort {
      Self.compare($0, $1, order: effectiveOrder) == .orderedAscending
    }

    if let first = query.first {
      snapshots = Array(snapshots.prefix(first))
    }
    if let last = query.last {
      snapshots = Array(snapshots.suffix(last))
    }
    if let limit = query.limit {
      snapshots = Array(snapshots.prefix(limit))
    }

    let linked = includeLinks(
      snapshots.map(\.snapshot),
      plan: query,
      attributes: attributes,
      metrics: &metrics
    )
    return project(linked, selectedFields: query.selectedFields)
  }

  private func snapshot(
    entityID: String,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantEntitySnapshot? {
    if let interned = internCaches.internedSnapshot(
      entityID: entityID,
      namespace: namespace
    ) {
      guard attributes.namespaceHasManyCardinality(namespace) else {
        return interned
      }
      return internedSnapshotByMergingManyCardinality(
        interned,
        entityID: entityID,
        namespace: namespace,
        attributes: attributes
      )
    }
    guard let attributesByID = eav[entityID] else { return nil }

    guard
      let values = materializedValues(
        entityID: entityID,
        namespace: namespace,
        attributesByID: attributesByID,
        attributes: attributes
      )
    else { return nil }
    return InstantEntitySnapshot(id: entityID, namespace: namespace, values: values)
  }

  private func internedSnapshotByMergingManyCardinality(
    _ interned: InstantEntitySnapshot,
    entityID: String,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantEntitySnapshot {
    let namespaceAttributes = attributes.attributes(namespace: namespace)
    var hasManyCardinality = false
    for attribute in namespaceAttributes where attribute.cardinality == .many {
      hasManyCardinality = true
      break
    }
    guard hasManyCardinality, let attributesByID = eav[entityID] else {
      return interned
    }
    var values = interned.values
    var didChange = false
    for attribute in namespaceAttributes where attribute.cardinality == .many {
      guard let slot = attributesByID[attribute.id] else {
        if values[attribute.name] != nil {
          values[attribute.name] = nil
          didChange = true
        }
        continue
      }
      if let value = materializedValue(slot, attribute: attribute) {
        if values[attribute.name] != value {
          values[attribute.name] = value
          didChange = true
        }
      } else if values[attribute.name] != nil {
        values[attribute.name] = nil
        didChange = true
      }
    }
    guard didChange else { return interned }
    return InstantEntitySnapshot(
      id: interned.id,
      namespace: interned.namespace,
      values: values,
      links: interned.links
    )
  }

  private func materializedValues(
    entityID: String,
    namespace: String,
    attributesByID: [String: AttrSlot],
    attributes: AttributeStore
  ) -> [String: InstantMaterializedValue]? {
    let namespaceAttributes = attributes.attributes(namespace: namespace)
    if namespaceAttributes.isEmpty {
      return materializedValuesByScanningEntityAttributes(
        namespace: namespace,
        attributesByID: attributesByID,
        attributes: attributes
      )
    }

    var values: [String: InstantMaterializedValue] = [:]
    var hasNamespaceData = false
    values.reserveCapacity(namespaceAttributes.count)
    for attribute in namespaceAttributes {
      if attribute.primaryKey {
        if attributesByID[attribute.id] != nil {
          hasNamespaceData = true
        }
        values[attribute.name] = .one(.string(entityID))
        continue
      }
      guard let valuesByValue = attributesByID[attribute.id] else { continue }
      hasNamespaceData = true

      if let value = materializedValue(valuesByValue, attribute: attribute) {
        values[attribute.name] = value
      }
    }

    return hasNamespaceData ? values : nil
  }

  private func materializedValuesByScanningEntityAttributes(
    namespace: String,
    attributesByID: [String: AttrSlot],
    attributes: AttributeStore
  ) -> [String: InstantMaterializedValue]? {
    var values: [String: InstantMaterializedValue] = [:]
    values.reserveCapacity(attributesByID.count)
    for (attributeID, valuesByValue) in attributesByID {
      guard let attribute = attributes[attributeID], attribute.namespace == namespace
      else { continue }

      if let value = materializedValue(valuesByValue, attribute: attribute) {
        values[attribute.name] = value
      }
    }

    return values.isEmpty ? nil : values
  }

  private func materializedValue(
    _ slot: AttrSlot,
    attribute: InstantAttribute
  ) -> InstantMaterializedValue? {
    switch attribute.cardinality {
    case .one:
      guard let value = slot.firstEntry?.key else { return nil }
      return .one(value)

    case .many:
      return .many(
        slot.keys.sorted { $0.comparableKey < $1.comparableKey }
      )
    }
  }

  private func needsServerCreatedAt(_ order: InstantQueryOrder) -> Bool {
    order.isServerCreatedAt
  }

  private func serverCreatedAtValue(
    entityID: String,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantValue? {
    let idAttribute = attributes.primaryKeyAttribute(namespace: namespace)
    if let triple = eav[entityID]?[idAttribute.id]?[.string(entityID)] {
      return .number(Double(triple.txTime.milliseconds))
    }

    let earliestNamespaceTime = eav[entityID]?
      .flatMap { attributeID, valuesByValue -> [InstantTimestamp] in
        guard attributes[attributeID]?.namespace == namespace else { return [] }
        return valuesByValue.values.map(\.txTime)
      }
      .min()
    return earliestNamespaceTime.map { .number(Double($0.milliseconds)) }
  }

  private func paginate(
    _ snapshots: [QuerySnapshot],
    plan: InstantQueryPlan,
    effectiveOrder: InstantQueryOrder,
    attributes: AttributeStore,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) -> (values: [QuerySnapshot], pageInfo: InstantQueryPageInfo?) {
    guard isValidPagination(plan) else {
      return ([], pageInfo(for: [], plan: plan, effectiveOrder: effectiveOrder))
    }

    var page = snapshots
    var removedBefore = 0
    var removedAfter = 0
    var returnedPageInfo: InstantQueryPageInfo?

    switch remotePageInfo {
    case .waiting? where requiresRemotePageInfo(plan):
      return ([], nil)

    case let .ready(pageInfo)? where requiresRemotePageInfo(plan):
      guard let startCursor = pageInfo.startCursor else {
        return ([], pageInfo)
      }
      let startIndex =
        page.firstIndex {
          Self.compare(
            $0,
            to: startCursor,
            order: effectiveOrder,
            namespace: plan.namespace,
            attributes: attributes
          ) != .orderedAscending
        }
        ?? page.count
      removedBefore += min(startIndex, page.count)
      page = Array(page.dropFirst(startIndex))

      if let endCursor = pageInfo.endCursor {
        let endIndex =
          page.firstIndex {
            Self.compare(
              $0,
              to: endCursor,
              order: effectiveOrder,
              namespace: plan.namespace,
              attributes: attributes
            ) == .orderedDescending
          }
          ?? page.count
        let boundedEndIndex = max(0, min(endIndex, page.count))
        removedAfter += page.count - boundedEndIndex
        page = Array(page.prefix(boundedEndIndex))
      }
      returnedPageInfo = pageInfo

    case let .ready(pageInfo)?:
      returnedPageInfo = pageInfo

    case .some(.waiting), .none:
      break
    }

    if returnedPageInfo == nil, let after = plan.after {
      let startIndex: Int
      if after.sortValue == nil {
        guard let index = page.firstIndex(where: { $0.snapshot.id == after.entityID }) else {
          return ([], pageInfo(for: [], plan: plan))
        }
        startIndex = after.inclusive ? index : index + 1
      } else {
        startIndex = page.firstIndex {
          let comparison = Self.compare(
            $0,
            to: after,
            order: effectiveOrder,
            namespace: plan.namespace,
            attributes: attributes
          )
          return after.inclusive
            ? comparison != .orderedAscending
            : comparison == .orderedDescending
        } ?? page.count
      }
      removedBefore += min(startIndex, page.count)
      page = Array(page.dropFirst(startIndex))
    }

    if returnedPageInfo == nil, let before = plan.before {
      let endIndex: Int
      if before.sortValue == nil {
        guard let index = page.firstIndex(where: { $0.snapshot.id == before.entityID }) else {
          return ([], pageInfo(for: [], plan: plan))
        }
        endIndex = before.inclusive ? index + 1 : index
      } else {
        endIndex = page.firstIndex {
          let comparison = Self.compare(
            $0,
            to: before,
            order: effectiveOrder,
            namespace: plan.namespace,
            attributes: attributes
          )
          return before.inclusive
            ? comparison == .orderedDescending
            : comparison != .orderedAscending
        } ?? page.count
      }
      let boundedEndIndex = max(0, min(endIndex, page.count))
      removedAfter += page.count - boundedEndIndex
      page = Array(page.prefix(boundedEndIndex))
    }

    if returnedPageInfo == nil, let offset = plan.offset {
      let count = min(offset, page.count)
      removedBefore += count
      page = Array(page.dropFirst(offset))
    }

    if let first = plan.first {
      let count = min(first, page.count)
      removedAfter += page.count - count
      page = Array(page.prefix(first))
    }

    if let last = plan.last {
      let count = min(last, page.count)
      removedBefore += page.count - count
      page = Array(page.suffix(last))
    }

    if let limit = plan.limit {
      let count = min(limit, page.count)
      removedAfter += page.count - count
      page = Array(page.prefix(limit))
    }

    return (
      page,
      returnedPageInfo
        ?? pageInfo(
          for: page,
          plan: plan,
          effectiveOrder: effectiveOrder,
          hasPreviousPage: removedBefore > 0,
          hasNextPage: removedAfter > 0
        )
    )
  }

  private func requiresRemotePageInfo(_ plan: InstantQueryPlan) -> Bool {
    plan.offset.map { $0 > 0 } ?? false
      || plan.after != nil
      || plan.before != nil
  }

  private func isValidPagination(_ plan: InstantQueryPlan) -> Bool {
    guard plan.offset.map({ $0 >= 0 }) ?? true else { return false }
    guard plan.limit.map({ $0 > 0 }) ?? true else { return false }
    guard plan.first.map({ $0 > 0 }) ?? true else { return false }
    guard plan.last.map({ $0 > 0 }) ?? true else { return false }
    return true
  }

  private func pageInfo(
    for snapshots: [QuerySnapshot],
    plan: InstantQueryPlan,
    effectiveOrder: InstantQueryOrder? = nil,
    hasPreviousPage: Bool = false,
    hasNextPage: Bool = false
  ) -> InstantQueryPageInfo? {
    guard requestsPageInfo(plan) else { return nil }
    let order = effectiveOrder ?? Self.effectiveOrder(plan.order)
    return InstantQueryPageInfo(
      startCursor: snapshots.first.map { cursor(for: $0, order: order) },
      endCursor: snapshots.last.map { cursor(for: $0, order: order) },
      hasPreviousPage: hasPreviousPage,
      hasNextPage: hasNextPage
    )
  }

  private func requestsPageInfo(_ plan: InstantQueryPlan) -> Bool {
    plan.offset != nil
      || plan.limit != nil
      || plan.first != nil
      || plan.after != nil
      || plan.last != nil
      || plan.before != nil
  }

  private func cursor(
    for querySnapshot: QuerySnapshot,
    order: InstantQueryOrder?
  ) -> InstantQueryCursor {
    InstantQueryCursor(
      entityID: querySnapshot.snapshot.id,
      sortValue: order.flatMap { Self.orderValue(querySnapshot, field: $0.field) }
    )
  }

  private mutating func insertNewCardinalityOne(
    _ triple: InstantTriple,
    attribute: InstantAttribute
  ) {
    let value = Self.normalizedValue(triple.value, attribute: attribute)
    let stamp = InstantTripleStamp(
      txIDIndex: internTxID(triple.txID),
      txTimeMilliseconds: triple.txTime.milliseconds
    )
    storedTripleCount += 1
    eav[triple.entityID, default: [:]][triple.attributeID] = .one(
      value: value,
      stamp: stamp
    )
    if attribute.valueType == .ref {
      vae[value, default: [:]][triple.attributeID, default: [:]][triple.entityID] = stamp
    }
    if !attribute.primaryKey {
      touchInternCachesAfterWrite(entityID: triple.entityID, attribute: attribute, value: value)
    }
    rememberEntityInNamespace(triple.entityID, namespace: attribute.namespace)
    if attribute.isIndexed {
      indexIndexedAttributeInsert(
        entityID: triple.entityID,
        attributeID: triple.attributeID,
        value: value,
        cardinalityOne: true
      )
    }
    if derivedIndexAttributeShapes[triple.attributeID] == nil {
      derivedIndexAttributeShapes[triple.attributeID] = DerivedIndexAttributeShape(attribute)
    }
  }

  private mutating func insert(
    _ triple: InstantTriple,
    attribute: InstantAttribute?
  ) {
    var triple = Self.normalizedTriple(triple, attribute: attribute)
    if let existing = eav[triple.entityID]?[triple.attributeID]?[triple.value] {
      triple.txTime = existing.txTime
    }

    let isCardinalityOne = attribute?.cardinality == .one
    if isCardinalityOne,
      let existingSlot = eav[triple.entityID]?[triple.attributeID]
    {
      guard !existingSlot.values.contains(where: { $0.txTime > triple.txTime }) else { return }
      if case let .one(existingValue, _) = existingSlot {
        if existingValue == triple.value {
          let existingStamp = existingSlot.firstEntry?.value
          let stamp = InstantTripleStamp(
            txIDIndex: internTxID(triple.txID),
            txTimeMilliseconds: (existingStamp?.txTimeMilliseconds)
              ?? triple.txTime.milliseconds
          )
          eav[triple.entityID, default: [:]][triple.attributeID] = .one(
            value: existingValue,
            stamp: stamp
          )
          return
        }
        replaceCardinalityOneSlot(
          entityID: triple.entityID,
          attributeID: triple.attributeID,
          previousValue: existingValue,
          triple: triple,
          attribute: attribute
        )
        return
      }
      var toRemove: [InstantTriple] = []
      existingSlot.forEachPair { value, stamp in
        toRemove.append(
          materializeTriple(
            entityID: triple.entityID,
            attributeID: triple.attributeID,
            value: value,
            stamp: stamp
          )
        )
      }
      for existing in toRemove {
        removeNormalized(existing, attribute: attribute)
      }
    }

    if eav[triple.entityID]?[triple.attributeID]?[triple.value] == nil {
      storedTripleCount += 1
    }
    let stamp = InstantTripleStamp(
      txIDIndex: internTxID(triple.txID),
      txTimeMilliseconds: triple.txTime.milliseconds
    )
    if isCardinalityOne {
      eav[triple.entityID, default: [:]][triple.attributeID] = .one(
        value: triple.value,
        stamp: stamp
      )
    } else {
      var slot = eav[triple.entityID]?[triple.attributeID] ?? .many([:])
      if case let .one(existingValue, existingStamp) = slot {
        slot = .many([existingValue: existingStamp])
      }
      slot.set(value: triple.value, stamp: stamp, asMany: true)
      eav[triple.entityID, default: [:]][triple.attributeID] = slot
    }

    if attribute?.valueType == .ref {
      vae[triple.value, default: [:]][triple.attributeID, default: [:]][triple.entityID] = stamp
    }

    touchInternCachesAfterWrite(entityID: triple.entityID, attribute: attribute, value: triple.value)
    if let attribute {
      rememberEntityInNamespace(triple.entityID, namespace: attribute.namespace)
      if attribute.isIndexed {
        indexIndexedAttributeInsert(
          entityID: triple.entityID,
          attributeID: triple.attributeID,
          value: triple.value,
          cardinalityOne: isCardinalityOne
        )
      }
      derivedIndexAttributeShapes[triple.attributeID] = DerivedIndexAttributeShape(attribute)
    }
  }

  private mutating func replaceCardinalityOneSlot(
    entityID: String,
    attributeID: String,
    previousValue: InstantValue,
    triple: InstantTriple,
    attribute: InstantAttribute?
  ) {
    if let attribute, attribute.isIndexed {
      indexIndexedAttributeRemove(
        entityID: entityID,
        attributeID: attributeID,
        value: previousValue,
        cardinalityOne: true
      )
    }
    if attribute?.valueType == .ref {
      removeVAE(value: previousValue, attributeID: attributeID, entityID: entityID)
    }
    let stamp = InstantTripleStamp(
      txIDIndex: internTxID(triple.txID),
      txTimeMilliseconds: triple.txTime.milliseconds
    )
    eav[entityID, default: [:]][attributeID] = .one(value: triple.value, stamp: stamp)
    if attribute?.valueType == .ref {
      vae[triple.value, default: [:]][attributeID, default: [:]][entityID] = stamp
    }
    touchInternCachesAfterWrite(entityID: entityID, attribute: attribute, value: triple.value)
    if let attribute, attribute.isIndexed {
      indexIndexedAttributeInsert(
        entityID: entityID,
        attributeID: attributeID,
        value: triple.value,
        cardinalityOne: true
      )
    }
  }

  private mutating func removeVAE(
    value: InstantValue,
    attributeID: String,
    entityID: String
  ) {
    uniqueVAE()
    guard var byAttribute = vaeStorage.rows[value] else { return }
    guard var byEntity = byAttribute[attributeID] else { return }
    byEntity[entityID] = nil
    if byEntity.isEmpty {
      byAttribute[attributeID] = nil
    } else {
      byAttribute[attributeID] = byEntity
    }
    if byAttribute.isEmpty {
      vaeStorage.rows[value] = nil
    } else {
      vaeStorage.rows[value] = byAttribute
    }
  }

  private mutating func touchInternCachesAfterWrite(
    entityID: String,
    attribute: InstantAttribute?,
    value: InstantValue
  ) {
    guard shouldInternOnWrite else { return }
    if !internCachesAreEmpty {
      if !internCaches.internedIndexedEqualsResults.isEmpty
        || !internCaches.internedSimpleOrderedResults.isEmpty
      {
        internedQueryResultsNeedInvalidation = true
      }
      if !internCaches.internedServerCreatedAt.isEmpty {
        uniqueInternCaches()
        internCaches.internedServerCreatedAt[entityID] = nil
      }
    }
    internCardinalityOneSnapshot(
      entityID: entityID,
      attribute: attribute,
      value: value
    )
  }

  private mutating func internCardinalityOneSnapshot(
    entityID: String,
    attribute: InstantAttribute?,
    value: InstantValue
  ) {
    guard let attribute, attribute.cardinality == .one, !attribute.primaryKey else { return }
    let materialized = InstantMaterializedValue.one(value)
    if pendingInternEntityID == entityID, pendingInternNamespace == attribute.namespace {
      pendingInternValues[attribute.name] = materialized
      return
    }
    if !internCachesAreEmpty, internCaches.hasInternedEntity(entityID) {
      internInvalidationIDs.insert(entityID)
      internedQueryResultsNeedInvalidation = true
      return
    }
    if !internInvalidationIDs.isEmpty, internInvalidationIDs.contains(entityID) {
      internedQueryResultsNeedInvalidation = true
      return
    }
    if !pendingInternSnapshots.isEmpty,
      var existing = pendingInternSnapshots[entityID],
      existing.namespace == attribute.namespace
    {
      existing.values[attribute.name] = materialized
      pendingInternSnapshots[entityID] = existing
      return
    }
    if !pendingInternExtra.isEmpty,
      var extra = pendingInternExtra[entityID],
      var existing = extra[attribute.namespace]
    {
      existing.values[attribute.name] = materialized
      extra[attribute.namespace] = existing
      pendingInternExtra[entityID] = extra
      return
    }
    flushPendingIntern()
    pendingInternEntityID = entityID
    pendingInternNamespace = attribute.namespace
    pendingInternValues = [:]
    pendingInternValues.reserveCapacity(8)
    pendingInternValues[attribute.name] = materialized
  }

  private func pendingInternOmitsExistingCardinalityOneFields(
    entityID: String,
    namespace: String
  ) -> Bool {
    // Attribute IDs may be canonical UUIDs instead of "namespace/name" strings,
    // so completeness cannot be derived from id prefixes. Compare the pending
    // snapshot's field count (written fields plus the synthesized id) against
    // every stored slot of the entity. Any leftover slot may hold an
    // uninterned cardinality-one field, so treat it as omitting and skip
    // interning rather than serve a partial snapshot later.
    guard let existingCount = eavStorage.rows[entityID]?.count else { return false }
    return existingCount > pendingInternValues.count + 1
  }

  private mutating func flushPendingIntern() {
    guard
      let entityID = pendingInternEntityID,
      let namespace = pendingInternNamespace
    else { return }
    if pendingInternOmitsExistingCardinalityOneFields(
      entityID: entityID,
      namespace: namespace
    ) {
      pendingInternEntityID = nil
      pendingInternNamespace = nil
      pendingInternValues = [:]
      internedQueryResultsNeedInvalidation = true
      if pendingInternSnapshots[entityID] != nil || pendingInternExtra[entityID] != nil {
        pendingInternNeedsEAVCompletion = true
      } else {
        internInvalidationIDs.insert(entityID)
      }
      return
    }
    pendingInternValues["id"] = .one(.string(entityID))
    let snapshot = InstantEntitySnapshot(
      id: entityID,
      namespace: namespace,
      values: pendingInternValues
    )
    pendingInternEntityID = nil
    pendingInternNamespace = nil
    pendingInternValues = [:]
    if var existing = pendingInternSnapshots[entityID] {
      if existing.namespace == namespace {
        existing.values.merge(snapshot.values) { _, new in new }
        pendingInternSnapshots[entityID] = existing
      } else {
        pendingInternExtra[entityID, default: [:]][existing.namespace] = existing
        pendingInternExtra[entityID, default: [:]][namespace] = snapshot
        pendingInternSnapshots[entityID] = nil
      }
    } else if pendingInternExtra[entityID] != nil {
      if var extraSnapshot = pendingInternExtra[entityID]?[namespace] {
        extraSnapshot.values.merge(snapshot.values) { _, new in new }
        pendingInternExtra[entityID, default: [:]][namespace] = extraSnapshot
      } else {
        pendingInternExtra[entityID, default: [:]][namespace] = snapshot
      }
    } else {
      pendingInternSnapshots[entityID] = snapshot
    }
  }

  mutating func discardInternedQueryResultsBeforeWrite() {
    internedQueryResultsNeedInvalidation = false
    invalidateInternedQueryResults()
    clearPendingInternCaches()
    clearWriteCursors()
  }

  private mutating func rememberEntityInNamespace(_ entityID: String, namespace: String) {
    if lastWrittenEntityID == entityID, lastWrittenNamespace == namespace {
      return
    }
    entitiesByNamespace[namespace, default: []].insert(entityID)
    lastWrittenEntityID = entityID
    lastWrittenNamespace = namespace
  }

  private mutating func rememberChangedEntity(_ entityID: String, into changed: inout Set<String>) {
    changed.insert(entityID)
  }

  private mutating func clearWriteCursors() {
    lastWrittenEntityID = nil
    lastWrittenNamespace = nil
  }

  private mutating func clearPendingInternCaches() {
    pendingInternEntityID = nil
    pendingInternNamespace = nil
    pendingInternValues = [:]
    pendingInternSnapshots = [:]
    pendingInternExtra = [:]
    internInvalidationIDs = []
    internedQueryResultsNeedInvalidation = false
    pendingInternNeedsEAVCompletion = false
  }

  mutating func finishInternCachesAfterWrite(
    invalidating changedEntityIDs: Set<String> = [],
    attributes: AttributeStore
  ) {
    dropPendingIntern(for: internInvalidationIDs)
    flushPendingIntern()
    if pendingInternNeedsEAVCompletion {
      completePendingInternSnapshotsFromEAV(attributes: attributes)
      pendingInternNeedsEAVCompletion = false
    }
    internedQueryResultsNeedInvalidation = false
    invalidateInternedQueryResults()
    if pendingInternSnapshots.isEmpty && pendingInternExtra.isEmpty {
      internInvalidationIDs.formUnion(changedEntityIDs)
    } else if !internInvalidationIDs.isEmpty {
      internInvalidationIDs.subtract(pendingInternSnapshots.keys)
      internInvalidationIDs.subtract(pendingInternExtra.keys)
    }
    applyPendingInternSnapshots()
    if !internInvalidationIDs.isEmpty {
      invalidateInternedEntities(internInvalidationIDs)
      internInvalidationIDs = []
    }
  }

  private mutating func completePendingInternSnapshotsFromEAV(
    attributes: AttributeStore
  ) {
    for entityID in pendingInternSnapshots.keys {
      guard var snapshot = pendingInternSnapshots[entityID] else { continue }
      if completeInternSnapshotFromEAV(&snapshot, attributes: attributes) {
        pendingInternSnapshots[entityID] = snapshot
      }
    }
    guard !pendingInternExtra.isEmpty else { return }
    for entityID in pendingInternExtra.keys {
      guard var byNamespace = pendingInternExtra[entityID] else { continue }
      var didChangeEntity = false
      for namespace in byNamespace.keys {
        guard var snapshot = byNamespace[namespace] else { continue }
        if completeInternSnapshotFromEAV(&snapshot, attributes: attributes) {
          byNamespace[namespace] = snapshot
          didChangeEntity = true
        }
      }
      if didChangeEntity {
        pendingInternExtra[entityID] = byNamespace
      }
    }
  }

  private func completeInternSnapshotFromEAV(
    _ snapshot: inout InstantEntitySnapshot,
    attributes: AttributeStore
  ) -> Bool {
    guard let attrs = eav[snapshot.id] else { return false }
    var didChange = false
    for (attributeID, slot) in attrs {
      guard let attribute = attributes[attributeID] else { continue }
      guard attribute.namespace == snapshot.namespace, attribute.cardinality == .one,
        !attribute.primaryKey
      else { continue }
      guard case let .one(value, _) = slot else { continue }
      if snapshot.values[attribute.name] == nil {
        snapshot.values[attribute.name] = .one(value)
        didChange = true
      }
    }
    if snapshot.values["id"] == nil {
      snapshot.values["id"] = .one(.string(snapshot.id))
      didChange = true
    }
    return didChange
  }

  private mutating func dropPendingIntern(for entityIDs: Set<String>) {
    guard !entityIDs.isEmpty else { return }
    if let pendingID = pendingInternEntityID, entityIDs.contains(pendingID) {
      pendingInternEntityID = nil
      pendingInternNamespace = nil
      pendingInternValues = [:]
    }
    if !pendingInternSnapshots.isEmpty || !pendingInternExtra.isEmpty {
      for entityID in entityIDs {
        pendingInternSnapshots[entityID] = nil
        pendingInternExtra[entityID] = nil
      }
    }
  }

  private mutating func applyPendingInternSnapshots() {
    guard !pendingInternSnapshots.isEmpty || !pendingInternExtra.isEmpty else { return }
    uniqueInternCaches()
    if internCaches.internedExtraNamespaceSnapshots.isEmpty, pendingInternExtra.isEmpty {
      if internCaches.internedCardinalityOneSnapshots.isEmpty {
        internCaches.internedCardinalityOneSnapshots = pendingInternSnapshots
      } else {
        internCaches.internedCardinalityOneSnapshots.merge(pendingInternSnapshots) { _, new in new }
      }
    } else {
      internCaches.internedCardinalityOneSnapshots.reserveCapacity(
        internCaches.internedCardinalityOneSnapshots.count + pendingInternSnapshots.count
      )
      for (entityID, snapshot) in pendingInternSnapshots {
        internCaches.storeSnapshot(snapshot, entityID: entityID)
      }
      for (entityID, byNamespace) in pendingInternExtra {
        for snapshot in byNamespace.values {
          internCaches.storeSnapshot(snapshot, entityID: entityID)
        }
      }
    }
    pendingInternSnapshots = [:]
    pendingInternExtra = [:]
  }

  private mutating func materializeInternedSimpleOrderedPage(
    _ plan: InstantQueryPlan,
    attributes: AttributeStore,
    remotePageInfo: InstantQueryRemotePageInfo?
  ) -> [InstantEntitySnapshot]? {
    let order = Self.effectiveOrder(plan.order)
    guard
      Self.canMaterializeSimpleOrderedPage(plan, remotePageInfo: remotePageInfo),
      !order.isServerCreatedAt
    else { return nil }
    let resultKey = SimpleOrderedResultKey(
      namespace: plan.namespace,
      orderField: order.field,
      isAscending: order.direction == .ascending
    )
    if let interned = internCaches.internedSimpleOrderedResults[resultKey] {
      return interned
    }
    uniqueInternCaches()
    guard
      let page = materializeSimpleOrderedPage(
        plan,
        order: order,
        attributes: attributes,
        remotePageInfo: remotePageInfo
      )
    else { return nil }
    internCaches.internedSimpleOrderedResults[resultKey] = page.values
    return page.values
  }

  private mutating func invalidateInternedQueryResults() {
    if internCaches.internedIndexedEqualsResults.isEmpty,
      internCaches.internedSimpleOrderedResults.isEmpty
    {
      return
    }
    uniqueInternCaches()
    internCaches.clearQueryResults()
  }

  private mutating func invalidateInternedEntity(_ entityID: String) {
    invalidateInternedEntities([entityID])
  }

  private mutating func invalidateInternedEntities(_ entityIDs: Set<String>) {
    guard !internCachesAreEmpty, !entityIDs.isEmpty else { return }
    flushPendingIntern()
    uniqueInternCaches()
    invalidateInternedQueryResults()
    if internCaches.internedEntityCount <= entityIDs.count {
      var allInternedAreDeleted = true
      for internedID in internCaches.internedCardinalityOneSnapshots.keys {
        if !entityIDs.contains(internedID) {
          allInternedAreDeleted = false
          break
        }
      }
      if allInternedAreDeleted {
        for internedID in internCaches.internedExtraNamespaceSnapshots.keys {
          if !entityIDs.contains(internedID) {
            allInternedAreDeleted = false
            break
          }
        }
      }
      if allInternedAreDeleted {
        internCaches.internedCardinalityOneSnapshots = [:]
        internCaches.internedExtraNamespaceSnapshots = [:]
        internCaches.internedServerCreatedAt = [:]
        return
      }
    }
    let shouldClearCreatedAt = !internCaches.internedServerCreatedAt.isEmpty
    for entityID in entityIDs {
      internCaches.removeInternedEntity(entityID)
      if shouldClearCreatedAt {
        internCaches.internedServerCreatedAt[entityID] = nil
      }
    }
  }

  var internedCardinalityOneEntityCount: Int {
    internCaches.internedEntityCount
  }

  mutating func internChangedEntities(
    _ entityIDs: Set<String>,
    attributes: AttributeStore
  ) {
    guard !entityIDs.isEmpty else { return }
    var snapshots: [String: InstantEntitySnapshot] = [:]
    var extraSnapshots: [String: [String: InstantEntitySnapshot]] = [:]
    snapshots.reserveCapacity(entityIDs.count)
    for entityID in entityIDs {
      if internCaches.hasInternedEntity(entityID) { continue }
      guard let attributesByID = eav[entityID] else { continue }
      var values: [String: InstantMaterializedValue] = [:]
      values.reserveCapacity(4)
      var snapshotNamespace: String?
      var extra: [String: [String: InstantMaterializedValue]] = [:]
      for (attributeID, slot) in attributesByID {
        guard let attribute = attributes[attributeID] else { continue }
        guard attribute.cardinality == .one, !attribute.primaryKey else { continue }
        guard let materialized = materializedValue(slot, attribute: attribute) else { continue }
        if snapshotNamespace == nil || snapshotNamespace == attribute.namespace {
          snapshotNamespace = attribute.namespace
          values[attribute.name] = materialized
        } else {
          extra[attribute.namespace, default: [:]][attribute.name] = materialized
        }
      }
      guard let snapshotNamespace, !values.isEmpty else { continue }
      snapshots[entityID] = InstantEntitySnapshot(
        id: entityID,
        namespace: snapshotNamespace,
        values: values
      )
      if !extra.isEmpty {
        var extraByNamespace: [String: InstantEntitySnapshot] = [:]
        extraByNamespace.reserveCapacity(extra.count)
        for (namespace, extraValues) in extra {
          extraByNamespace[namespace] = InstantEntitySnapshot(
            id: entityID,
            namespace: namespace,
            values: extraValues
          )
        }
        extraSnapshots[entityID] = extraByNamespace
      }
    }
    guard !snapshots.isEmpty || !extraSnapshots.isEmpty else { return }
    uniqueInternCaches()
    if internCaches.internedCardinalityOneSnapshots.isEmpty,
      internCaches.internedExtraNamespaceSnapshots.isEmpty,
      extraSnapshots.isEmpty
    {
      internCaches.internedCardinalityOneSnapshots = snapshots
      return
    }
    internCaches.internedCardinalityOneSnapshots.merge(snapshots) { _, new in new }
    for (entityID, byNamespace) in extraSnapshots {
      for snapshot in byNamespace.values {
        internCaches.storeSnapshot(snapshot, entityID: entityID)
      }
    }
  }

  private static func transactionStampPrecedes(
    _ lhs: InstantTriple,
    _ rhs: InstantTriple
  ) -> Bool {
    if lhs.txTime != rhs.txTime { return lhs.txTime < rhs.txTime }
    return lhs.txID < rhs.txID
  }

  private static func entityIDsAffected(by triple: InstantTriple) -> Set<String> {
    guard case let .ref(targetEntityID) = triple.value else {
      return [triple.entityID]
    }
    return [triple.entityID, targetEntityID]
  }

  private func shouldInstallReconciledTriple(
    _ candidate: InstantTriple,
    attribute: InstantAttribute?
  ) -> Bool {
    guard let slot = eav[candidate.entityID]?[candidate.attributeID] else { return true }
    if attribute?.cardinality == .one {
      var newest: InstantTriple?
      slot.forEachPair { value, stamp in
        let existing = materializeTriple(
          entityID: candidate.entityID,
          attributeID: candidate.attributeID,
          value: value,
          stamp: stamp
        )
        if newest.map({ Self.transactionStampPrecedes($0, existing) }) ?? true {
          newest = existing
        }
      }
      return newest.map { Self.transactionStampPrecedes($0, candidate) } ?? true
    }
    guard let stamp = slot[candidate.value] else { return true }
    let existing = materializeTriple(
      entityID: candidate.entityID,
      attributeID: candidate.attributeID,
      value: candidate.value,
      stamp: stamp
    )
    return Self.transactionStampPrecedes(existing, candidate)
  }

  private mutating func removeCompetingReconciledTriples(
    for candidate: InstantTriple,
    attribute: InstantAttribute?
  ) {
    guard let slot = eav[candidate.entityID]?[candidate.attributeID] else { return }
    var existingTriples: [InstantTriple] = []
    if attribute?.cardinality == .one {
      existingTriples.reserveCapacity(slot.count)
      slot.forEachPair { value, stamp in
        existingTriples.append(
          materializeTriple(
            entityID: candidate.entityID,
            attributeID: candidate.attributeID,
            value: value,
            stamp: stamp
          )
        )
      }
    } else if let stamp = slot[candidate.value] {
      existingTriples.append(
        materializeTriple(
          entityID: candidate.entityID,
          attributeID: candidate.attributeID,
          value: candidate.value,
          stamp: stamp
        )
      )
    }
    for existingTriple in existingTriples {
      removeNormalized(existingTriple, attribute: attribute)
    }
  }

  private mutating func indexIndexedAttributeInsert(
    entityID: String,
    attributeID: String,
    value: InstantValue,
    cardinalityOne: Bool
  ) {
    if cardinalityOne {
      if let previous = indexedEntityValues[attributeID]?[entityID], previous != value {
        indexedValueEntities[attributeID, default: [:]][previous, default: []].remove(entityID)
        if indexedValueEntities[attributeID]?[previous]?.isEmpty == true {
          indexedValueEntities[attributeID, default: [:]][previous] = nil
        }
      }
      indexedEntityValues[attributeID, default: [:]][entityID] = value
    }
    indexedValueEntities[attributeID, default: [:]][value, default: []].insert(entityID)
  }

  private mutating func indexIndexedAttributeRemove(
    entityID: String,
    attributeID: String,
    value: InstantValue,
    cardinalityOne: Bool
  ) {
    indexedValueEntities[attributeID, default: [:]][value, default: []].remove(entityID)
    if indexedValueEntities[attributeID]?[value]?.isEmpty == true {
      indexedValueEntities[attributeID, default: [:]][value] = nil
    }
    if indexedValueEntities[attributeID]?.isEmpty == true {
      indexedValueEntities[attributeID] = nil
    }
    if cardinalityOne {
      if indexedEntityValues[attributeID]?[entityID] == value {
        indexedEntityValues[attributeID, default: [:]][entityID] = nil
      }
      if indexedEntityValues[attributeID]?.isEmpty == true {
        indexedEntityValues[attributeID] = nil
      }
    }
  }

  private mutating func merge(_ triple: InstantTriple, attribute: InstantAttribute?) -> Bool {
    guard
      attribute?.cardinality != .many,
      let existingEntry = eav[triple.entityID]?[triple.attributeID]?.firstEntry
    else {
      return false
    }
    let existingValue = existingEntry.key
    let existingStamp = existingEntry.value

    var merged = triple
    merged.value = Self.deepMerge(existingValue, with: triple.value)
    merged.txTime = existingStamp.txTime
    insert(merged, attribute: attribute)
    return true
  }

  private static func deepMerge(_ current: InstantValue, with update: InstantValue) -> InstantValue {
    guard
      case let .json(currentJSON) = current,
      case let .json(updateJSON) = update
    else { return update }
    return .json(deepMerge(currentJSON, with: updateJSON))
  }

  private static func deepMerge(_ current: JSONValue, with update: JSONValue) -> JSONValue {
    guard
      case let .object(currentFields) = current,
      case let .object(updateFields) = update
    else { return update }

    var merged = currentFields
    for (key, value) in updateFields {
      if case .null = value {
        merged[key] = nil
        continue
      }
      if let currentValue = merged[key] {
        merged[key] = deepMerge(currentValue, with: value)
      } else {
        merged[key] = value
      }
    }
    return .object(merged)
  }

  private mutating func remove(_ triple: InstantTriple, attribute: InstantAttribute?) {
    let triple = Self.normalizedTriple(triple, attribute: attribute)
    removeNormalized(triple, attribute: attribute)
  }

  private mutating func removeNormalized(
    _ triple: InstantTriple,
    attribute: InstantAttribute?,
    invalidateIntern: Bool = true
  ) {
    uniqueEAV()
    guard var attrs = eavStorage.rows[triple.entityID], var slot = attrs[triple.attributeID] else {
      return
    }
    if slot[triple.value] != nil {
      storedTripleCount -= 1
    }
    if slot.removeValue(triple.value) {
      attrs[triple.attributeID] = nil
    } else {
      attrs[triple.attributeID] = slot
    }
    if attrs.isEmpty {
      eavStorage.rows[triple.entityID] = nil
    } else {
      eavStorage.rows[triple.entityID] = attrs
    }

    if attribute?.valueType == .ref {
      removeVAE(
        value: triple.value,
        attributeID: triple.attributeID,
        entityID: triple.entityID
      )
    }

    if let attribute, attribute.isIndexed {
      indexIndexedAttributeRemove(
        entityID: triple.entityID,
        attributeID: triple.attributeID,
        value: triple.value,
        cardinalityOne: attribute.cardinality == .one
      )
    }
    if let attribute {
      if eav[triple.entityID] == nil {
        for namespace in entitiesByNamespace.keys {
          entitiesByNamespace[namespace, default: []].remove(triple.entityID)
          if entitiesByNamespace[namespace]?.isEmpty == true {
            entitiesByNamespace[namespace] = nil
          }
        }
        if lastWrittenEntityID == triple.entityID {
          clearWriteCursors()
        }
      } else {
        let remainsInThisNamespace = (eav[triple.entityID] ?? [:]).keys.contains { key in
          key.hasPrefix(attribute.namespace + "/")
        }
        if !remainsInThisNamespace {
          entitiesByNamespace[attribute.namespace, default: []].remove(triple.entityID)
          if entitiesByNamespace[attribute.namespace]?.isEmpty == true {
            entitiesByNamespace[attribute.namespace] = nil
          }
          if lastWrittenEntityID == triple.entityID,
            lastWrittenNamespace == attribute.namespace
          {
            lastWrittenEntityID = nil
            lastWrittenNamespace = nil
          }
        }
      }
    }
    if internCaches.hasInternedEntity(triple.entityID) || invalidateIntern {
      internInvalidationIDs.insert(triple.entityID)
      internedQueryResultsNeedInvalidation = true
    }
  }

  private static func normalizedTriple(
    _ triple: InstantTriple,
    attribute: InstantAttribute?
  ) -> InstantTriple {
    var triple = triple
    triple.value = normalizedValue(triple.value, attribute: attribute)
    return triple
  }

  private static func normalizedValue(
    _ value: InstantValue,
    attribute: InstantAttribute?
  ) -> InstantValue {
    guard attribute?.valueType == .date else { return value }
    if case .date = value { return value }
    guard let date = InstantDateCoercion.coerce(value) else { return value }
    return .date(date)
  }

  private mutating func deleteEntity(
    _ entityID: String,
    namespace: String?,
    attributes: AttributeStore,
    visited: inout Set<DeleteVisit>
  ) -> Set<String> {
    guard visited.insert(DeleteVisit(entityID: entityID, namespace: namespace)).inserted else {
      return []
    }

    var changed: Set<String> = [entityID]
    var outgoingRefs: [(attribute: InstantAttribute, targetID: String)] = []
    if let attributesByID = eav[entityID] {
      for (attributeID, slot) in attributesByID {
        let attribute = attributes[attributeID]
        if let namespace, attribute?.namespace != namespace {
          continue
        }
        guard let attribute, attribute.valueType == .ref else { continue }
        slot.forEachPair { value, _ in
          guard case let .ref(targetID) = value else { return }
          outgoingRefs.append((attribute, targetID))
        }
      }
    }

    var incomingRefs: [(sourceID: String, attributeID: String, attribute: InstantAttribute?)] = []
    if !vae.isEmpty, let byAttribute = vae[.ref(entityID)] {
      for (attributeID, byEntity) in byAttribute {
        let attribute = attributes[attributeID]
        if let namespace, attribute?.linkNamespace != namespace {
          continue
        }
        incomingRefs.reserveCapacity(incomingRefs.count + byEntity.count)
        for sourceID in byEntity.keys {
          incomingRefs.append((sourceID, attributeID, attribute))
        }
      }
    }

    for item in outgoingRefs {
      changed.insert(item.targetID)
      if item.attribute.onDeleteReverse == .cascade {
        changed.formUnion(
          deleteEntity(
            item.targetID,
            namespace: item.attribute.linkNamespace,
            attributes: attributes,
            visited: &visited
          )
        )
      }
    }

    for item in incomingRefs {
      changed.insert(item.sourceID)
      if item.attribute?.onDelete == .cascade {
        changed.formUnion(
          deleteEntity(
            item.sourceID,
            namespace: item.attribute?.namespace,
            attributes: attributes,
            visited: &visited
          )
        )
      }
    }

    removeEntityAttributes(entityID, namespace: namespace, attributes: attributes)
    let deletedRef = InstantValue.ref(entityID)
    for item in incomingRefs {
      removeNormalized(
        InstantTriple(
          entityID: item.sourceID,
          attributeID: item.attributeID,
          value: deletedRef,
          txID: "",
          txTime: InstantTimestamp(milliseconds: 0)
        ),
        attribute: item.attribute,
        invalidateIntern: false
      )
    }
    internInvalidationIDs.formUnion(changed)
    dropPendingIntern(for: changed)

    return changed
  }

  private mutating func removeEntityAttributes(
    _ entityID: String,
    namespace: String?,
    attributes: AttributeStore
  ) {
    guard let attributesByID = eav[entityID] else { return }
    var remaining: [String: AttrSlot] = [:]
    var removedNamespaces: Set<String> = []
    remaining.reserveCapacity(attributesByID.count)
    for (attributeID, slot) in attributesByID {
      let attribute = attributes[attributeID]
      if let namespace, attribute?.namespace != namespace {
        remaining[attributeID] = slot
        continue
      }
      storedTripleCount -= slot.count
      slot.forEachPair { value, _ in
        if attribute?.valueType == .ref {
          removeVAE(value: value, attributeID: attributeID, entityID: entityID)
        }
        if let attribute, attribute.isIndexed {
          indexIndexedAttributeRemove(
            entityID: entityID,
            attributeID: attributeID,
            value: value,
            cardinalityOne: attribute.cardinality == .one
          )
        }
      }
      if let attribute {
        removedNamespaces.insert(attribute.namespace)
      }
    }
    if remaining.isEmpty {
      eav[entityID] = nil
      for namespace in removedNamespaces {
        entitiesByNamespace[namespace, default: []].remove(entityID)
        if entitiesByNamespace[namespace]?.isEmpty == true {
          entitiesByNamespace[namespace] = nil
        }
      }
      if lastWrittenEntityID == entityID {
        clearWriteCursors()
      }
      return
    }
    eav[entityID] = remaining
    for namespace in removedNamespaces {
      let remainsInNamespace = remaining.keys.contains { key in
        attributes[key]?.namespace == namespace
      }
      if !remainsInNamespace {
        entitiesByNamespace[namespace, default: []].remove(entityID)
        if entitiesByNamespace[namespace]?.isEmpty == true {
          entitiesByNamespace[namespace] = nil
        }
        if lastWrittenEntityID == entityID, lastWrittenNamespace == namespace {
          lastWrittenEntityID = nil
          lastWrittenNamespace = nil
        }
      }
    }
  }

  private func matches(
    _ snapshot: InstantEntitySnapshot,
    filters: [InstantQueryFilter],
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    for filter in filters {
      switch filter {
      case let .equals(field, value):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .equals(field: nested.field, value: value),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        let value = normalizedValue(value, field: field, namespace: namespace, attributes: attributes)
        guard
          materializedValue(
            snapshot,
            field: field,
            namespace: namespace,
            attributes: attributes
          )?.contains(value) == true
        else { return false }
      case let .notEquals(field, value):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .notEquals(field: nested.field, value: value),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        let value = normalizedValue(value, field: field, namespace: namespace, attributes: attributes)
        guard isDeclaredField(
          field,
          namespace: namespace,
          attributes: attributes,
          allowReverseRelations: true
        ) else { return false }
        guard matchesNotEquals(
          snapshot,
          field: field,
          value: value,
          namespace: namespace,
          attributes: attributes
        ) else { return false }
      case let .greaterThan(field, value):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .greaterThan(field: nested.field, value: value),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        let value = normalizedValue(value, field: field, namespace: namespace, attributes: attributes)
        guard matchesComparison(
          snapshot,
          field: field,
          value: value,
          namespace: namespace,
          attributes: attributes,
          allowed: [.orderedDescending]
        )
        else { return false }
      case let .greaterThanOrEqual(field, value):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .greaterThanOrEqual(field: nested.field, value: value),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        let value = normalizedValue(value, field: field, namespace: namespace, attributes: attributes)
        guard matchesComparison(
          snapshot,
          field: field,
          value: value,
          namespace: namespace,
          attributes: attributes,
          allowed: [.orderedSame, .orderedDescending]
        )
        else { return false }
      case let .lessThan(field, value):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .lessThan(field: nested.field, value: value),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        let value = normalizedValue(value, field: field, namespace: namespace, attributes: attributes)
        guard matchesComparison(
          snapshot,
          field: field,
          value: value,
          namespace: namespace,
          attributes: attributes,
          allowed: [.orderedAscending]
        )
        else { return false }
      case let .lessThanOrEqual(field, value):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .lessThanOrEqual(field: nested.field, value: value),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        let value = normalizedValue(value, field: field, namespace: namespace, attributes: attributes)
        guard matchesComparison(
          snapshot,
          field: field,
          value: value,
          namespace: namespace,
          attributes: attributes,
          allowed: [.orderedAscending, .orderedSame]
        )
        else { return false }
      case let .in(field, values):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .in(field: nested.field, values: values),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        guard
          let materialized = materializedValue(
            snapshot,
            field: field,
            namespace: namespace,
            attributes: attributes
          ),
          !values.isEmpty
        else { return false }
        let values = normalizedValues(values, field: field, namespace: namespace, attributes: attributes)
        guard materialized.values.contains(where: values.contains) else { return false }
      case let .like(field, pattern):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .like(field: nested.field, pattern: pattern),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        guard matchesStringPattern(
          snapshot,
          field: field,
          pattern: pattern,
          caseInsensitive: false,
          namespace: namespace,
          attributes: attributes
        )
        else { return false }
      case let .iLike(field, pattern):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .iLike(field: nested.field, pattern: pattern),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        guard matchesStringPattern(
          snapshot,
          field: field,
          pattern: pattern,
          caseInsensitive: true,
          namespace: namespace,
          attributes: attributes
        )
        else { return false }
      case let .isNull(field):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .isNull(field: nested.field),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        guard isDeclaredField(
          field,
          namespace: namespace,
          attributes: attributes,
          allowReverseRelations: true
        ) else { return false }
        guard isFieldNull(snapshot, field: field, namespace: namespace, attributes: attributes)
        else { return false }
      case let .isNotNull(field):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .isNotNull(field: nested.field),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        guard isDeclaredField(
          field,
          namespace: namespace,
          attributes: attributes,
          allowReverseRelations: true
        ) else { return false }
        guard !isFieldNull(snapshot, field: field, namespace: namespace, attributes: attributes)
        else { return false }
      case let .and(filters):
        guard matches(snapshot, filters: filters, namespace: namespace, attributes: attributes)
        else { return false }
      case let .or(filters):
        guard
          !filters.isEmpty
            && filters.contains(where: {
              matches(snapshot, filter: $0, namespace: namespace, attributes: attributes)
            })
        else { return false }
      }
    }
    return true
  }

  private func filtersReferenceDeclaredFields(
    _ filters: [InstantQueryFilter],
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    filters.allSatisfy { filterReferencesDeclaredFields($0, namespace: namespace, attributes: attributes) }
  }

  private static func validate(
    filters: [InstantQueryFilter],
    namespace: String,
    attributes: AttributeStore
  ) -> InstantQueryValidationIssue? {
    for filter in filters {
      if let issue = validate(filter: filter, namespace: namespace, attributes: attributes) {
        return issue
      }
    }
    return nil
  }

  private static func validate(
    filter: InstantQueryFilter,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantQueryValidationIssue? {
    switch filter {
    case let .equals(field, value), let .notEquals(field, value):
      switch validateFilterField(
        field,
        namespace: namespace,
        attributes: attributes
      ) {
      case let .success(attribute):
        return validateFilterValue(value, field: field, attribute: attribute)

      case let .failure(issue):
        return issue
      }

    case let .greaterThan(field, value),
      let .greaterThanOrEqual(field, value),
      let .lessThan(field, value),
      let .lessThanOrEqual(field, value):
      switch validateFilterField(
        field,
        namespace: namespace,
        attributes: attributes
      ) {
      case let .success(attribute):
        if let issue = validateFilterValue(value, field: field, attribute: attribute) {
          return issue
        }
        guard attribute.valueType.isRangeComparableInQueries else {
          return unsupportedRangeFilterIssue(field: field, attribute: attribute)
        }
        return nil

      case let .failure(issue):
        return issue
      }

    case let .in(field, values):
      switch validateFilterField(
        field,
        namespace: namespace,
        attributes: attributes
      ) {
      case let .success(attribute):
        for value in values {
          if let issue = validateFilterValue(value, field: field, attribute: attribute) {
            return issue
          }
        }
        return nil

      case let .failure(issue):
        return issue
      }

    case let .like(field, _):
      switch validateFilterField(
        field,
        namespace: namespace,
        attributes: attributes
      ) {
      case let .success(attribute):
        guard attribute.valueType == .string else {
          return incompatibleFilterValueIssue(
            field: field,
            attribute: attribute,
            received: "pattern"
          )
        }
        return nil

      case let .failure(issue):
        return issue
      }

    case let .iLike(field, _):
      switch validateFilterField(
        field,
        namespace: namespace,
        attributes: attributes
      ) {
      case let .success(attribute):
        guard attribute.valueType == .string else {
          return incompatibleFilterValueIssue(
            field: field,
            attribute: attribute,
            received: "pattern"
          )
        }
        guard attribute.isIndexed else {
          return unindexedILikeFilterIssue(field: field, attribute: attribute)
        }
        return nil

      case let .failure(issue):
        return issue
      }

    case let .isNull(field), let .isNotNull(field):
      return validateFieldReference(
        field,
        namespace: namespace,
        attributes: attributes,
        context: "query filter",
        allowNested: true,
        allowReverseRelations: true
      )

    case let .and(filters), let .or(filters):
      return validate(filters: filters, namespace: namespace, attributes: attributes)
    }
  }

  private static func validateSelectedFields(
    _ fields: [String]?,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantQueryValidationIssue? {
    guard let fields else { return nil }
    for field in fields {
      if let issue = validateFieldReference(
        field,
        namespace: namespace,
        attributes: attributes,
        context: "selected field",
        allowNested: false
      ) {
        return issue
      }
    }
    return nil
  }

  private static func validateOrder(
    _ order: InstantQueryOrder?,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantQueryValidationIssue? {
    guard let order, !order.isServerCreatedAt else { return nil }
    return validateFieldReference(
      order.field,
      namespace: namespace,
      attributes: attributes,
      context: "query order",
      allowNested: false
    )
  }

  private static func validatePagination(
    offset: Int?,
    limit: Int?,
    first: Int?,
    last: Int?,
    namespace: String,
    path: String = "pagination"
  ) -> InstantQueryValidationIssue? {
    if let offset, offset < 0 {
      return InstantQueryValidationIssue(
        namespace: namespace,
        path: path,
        message: "Pagination 'offset' must not be negative.",
        recovery: "Use a nonnegative pagination offset."
      )
    }
    let bounds: [(name: String, value: Int?)] = [
      ("limit", limit),
      ("first", first),
      ("last", last),
    ]
    for bound in bounds {
      if let value = bound.value, value <= 0 {
        return InstantQueryValidationIssue(
          namespace: namespace,
          path: path,
          message: "Pagination '\(bound.name)' must be greater than 0.",
          recovery: "Use a positive pagination bound."
        )
      }
    }
    return nil
  }

  private static func validateIncludes(
    _ includes: [InstantQueryInclude]?,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantQueryValidationIssue? {
    guard let includes else { return nil }
    for include in includes {
      let childNamespace: String?
      switch include.direction {
      case .forward:
        childNamespace = attributes.attribute(namespace: namespace, name: include.name).flatMap {
          attribute in
          guard attribute.valueType == .ref else { return nil }
          return attribute.linkNamespace
        }

      case .reverse:
        childNamespace = reverseAttribute(
          namespace: namespace,
          name: include.name,
          attributes: attributes
        )?.namespace
      }

      guard let childNamespace else {
        return InstantQueryValidationIssue(
          namespace: namespace,
          path: include.name,
          message: "'\(include.name)' is not a declared \(include.direction.rawValue) relation.",
          recovery: "Include a declared ref relation, or update the schema attributes before querying."
        )
      }

      guard let query = include.query else { continue }
      guard query.namespace == childNamespace else {
        return InstantQueryValidationIssue(
          namespace: namespace,
          path: include.name,
          message: "Include '\(include.name)' targets '\(childNamespace)' but its query targets '\(query.namespace)'.",
          recovery: "Use an include query for the relation's target namespace."
        )
      }
      if let issue = validatePagination(
        offset: nil,
        limit: query.limit,
        first: query.first,
        last: query.last,
        namespace: query.namespace,
        path: "\(include.name).pagination"
      ) {
        return issue
      }
      if let issue = validate(filters: query.filters, namespace: query.namespace, attributes: attributes) {
        return issue
      }
      if let issue = validateSelectedFields(
        query.selectedFields,
        namespace: query.namespace,
        attributes: attributes
      ) {
        return issue
      }
      if let issue = validateOrder(query.order, namespace: query.namespace, attributes: attributes) {
        return issue
      }
      if let issue = validateIncludes(query.includes, namespace: query.namespace, attributes: attributes) {
        return issue
      }
    }
    return nil
  }

  private static func validateFieldReference(
    _ field: String,
    namespace: String,
    attributes: AttributeStore,
    context: String,
    allowNested: Bool,
    allowReverseRelations: Bool = false
  ) -> InstantQueryValidationIssue? {
    switch resolvedFieldAttribute(
      field,
      namespace: namespace,
      attributes: attributes,
      context: context,
      allowNested: allowNested,
      allowReverseRelations: allowReverseRelations
    ) {
    case .success:
      return nil

    case let .failure(issue):
      return issue
    }
  }

  private static func validateFilterField(
    _ field: String,
    namespace: String,
    attributes: AttributeStore
  ) -> Result<InstantAttribute, InstantQueryValidationIssue> {
    resolvedFieldAttribute(
      field,
      namespace: namespace,
      attributes: attributes,
      context: "query filter",
      allowNested: true,
      allowReverseRelations: true
    )
  }

  private static func resolvedFieldAttribute(
    _ field: String,
    namespace: String,
    attributes: AttributeStore,
    context: String,
    allowNested: Bool,
    allowReverseRelations: Bool = false
  ) -> Result<InstantAttribute, InstantQueryValidationIssue> {
    if !field.contains(".") {
      guard
        let attribute = fieldAttribute(
          field,
          namespace: namespace,
          attributes: attributes,
          allowReverseRelations: allowReverseRelations
        )
      else {
        return .failure(undeclaredFieldIssue(field, namespace: namespace, context: context))
      }
      return .success(attribute)
    }

    guard allowNested else {
      return .failure(
        InstantQueryValidationIssue(
          namespace: namespace,
          path: field,
          message: "\(context) '\(field)' cannot use a nested relation path.",
          recovery: "Use a direct field for this query clause."
        )
      )
    }
    guard let nested = nestedField(field) else {
      return .failure(
        InstantQueryValidationIssue(
          namespace: namespace,
          path: field,
          message: "Nested field path '\(field)' is not supported.",
          recovery: "Use one or more relations followed by a field, such as 'project.owner.name'."
        )
      )
    }
    switch nestedFieldTargetNamespace(nested, namespace: namespace, attributes: attributes) {
    case let .success(targetNamespace):
      guard
        let attribute = fieldAttribute(
          nested.field,
          namespace: targetNamespace,
          attributes: attributes,
          allowReverseRelations: allowReverseRelations
        )
      else {
        return .failure(
          undeclaredFieldIssue(
            nested.field,
            namespace: targetNamespace,
            context: context,
            path: field
          )
        )
      }
      return .success(attribute)

    case let .failure(invalidRelation):
      return .failure(
        InstantQueryValidationIssue(
          namespace: invalidRelation.namespace,
          path: field,
          message: "'\(invalidRelation.name)' is not a declared relation.",
          recovery: "Filter through a declared forward or reverse relation."
        )
      )
    }
  }

  private static func validateFilterValue(
    _ value: InstantValue,
    field: String,
    attribute: InstantAttribute
  ) -> InstantQueryValidationIssue? {
    if isCompatibleFilterValue(value, with: attribute) {
      return nil
    }
    return incompatibleFilterValueIssue(
      field: field,
      attribute: attribute,
      received: value.queryValidationTypeDescription
    )
  }

  private static func isCompatibleFilterValue(
    _ value: InstantValue,
    with attribute: InstantAttribute
  ) -> Bool {
    if case .null = value {
      return !attribute.isRequired
    }

    switch (value, attribute.valueType) {
    case (.string, .string),
      (.number, .number),
      (.bool, .boolean),
      (.json, .json),
      (.ref, .ref):
      return true

    case (.date, .date):
      return true

    case (.string, .any),
      (.number, .any),
      (.bool, .any),
      (.date, .any),
      (.json, .any):
      return true

    case (.string, .date), (.number, .date):
      return InstantDateCoercion.coerce(value) != nil

    case (.null, _),
      (.string, _),
      (.number, _),
      (.bool, _),
      (.date, _),
      (.json, _),
      (.ref, _),
      (.lookupRef, _):
      return false
    }
  }

  private static func incompatibleFilterValueIssue(
    field: String,
    attribute: InstantAttribute,
    received: String
  ) -> InstantQueryValidationIssue {
    InstantQueryValidationIssue(
      namespace: attribute.namespace,
      path: field,
      message:
        "query filter '\(field)' expects \(attribute.valueType.queryValidationDescription) values, but received \(received).",
      recovery: "Use a filter value that matches the schema attribute type."
    )
  }

  private static func unsupportedRangeFilterIssue(
    field: String,
    attribute: InstantAttribute
  ) -> InstantQueryValidationIssue {
    InstantQueryValidationIssue(
      namespace: attribute.namespace,
      path: field,
      message:
        "query filter '\(field)' cannot use range operators with \(attribute.valueType.queryValidationDescription) values.",
      recovery: "Use range operators with string, number, boolean, or date fields."
    )
  }

  private static func unindexedILikeFilterIssue(
    field: String,
    attribute: InstantAttribute
  ) -> InstantQueryValidationIssue {
    InstantQueryValidationIssue(
      namespace: attribute.namespace,
      path: field,
      message:
        "query filter '\(field)' cannot use case-insensitive pattern matching because the schema attribute is not indexed.",
      recovery: "Mark the attribute indexed, or use a different query predicate."
    )
  }

  private static func isDeclaredField(
    _ field: String,
    namespace: String,
    attributes: AttributeStore,
    allowReverseRelations: Bool = false
  ) -> Bool {
    fieldAttribute(
      field,
      namespace: namespace,
      attributes: attributes,
      allowReverseRelations: allowReverseRelations
    ) != nil
  }

  private static func fieldAttribute(
    _ field: String,
    namespace: String,
    attributes: AttributeStore,
    allowReverseRelations: Bool = false
  ) -> InstantAttribute? {
    if let attribute = attributes.attribute(namespace: namespace, name: field) {
      return attribute
    }
    guard
      allowReverseRelations,
      let reverse = reverseAttribute(namespace: namespace, name: field, attributes: attributes)
    else { return nil }
    return InstantAttribute(
      id: "\(namespace)/\(field)",
      namespace: namespace,
      name: field,
      valueType: .ref,
      isRequired: false,
      cardinality: .many,
      isIndexed: reverse.isIndexed,
      forwardIdentity: reverse.reverseIdentity,
      reverseIdentity: reverse.forwardIdentity,
      linkNamespace: reverse.namespace
    )
  }

  private static func undeclaredFieldIssue(
    _ field: String,
    namespace: String,
    context: String,
    path: String? = nil
  ) -> InstantQueryValidationIssue {
    InstantQueryValidationIssue(
      namespace: namespace,
      path: path ?? field,
      message: "\(context) '\(path ?? field)' references an undeclared field.",
      recovery: "Declare the field in the schema attributes, or remove it from the query."
    )
  }

  private static func nestedField(_ field: String) -> NestedField? {
    let parts = field.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
    return NestedField(
      relations: parts.dropLast().map(String.init),
      field: String(parts[parts.count - 1])
    )
  }

  private static func nestedFieldTargetNamespace(
    _ nested: NestedField,
    namespace: String,
    attributes: AttributeStore
  ) -> Result<String, InvalidNestedRelation> {
    var namespace = namespace
    for relation in nested.relations {
      guard let targetNamespace = relationTargetNamespace(
        relation,
        namespace: namespace,
        attributes: attributes
      ) else {
        return .failure(InvalidNestedRelation(name: relation, namespace: namespace))
      }
      namespace = targetNamespace
    }
    return .success(namespace)
  }

  private static func relationTargetNamespace(
    _ relation: String,
    namespace: String,
    attributes: AttributeStore
  ) -> String? {
    if
      let attribute = attributes.attribute(namespace: namespace, name: relation),
      attribute.valueType == .ref,
      let linkNamespace = attribute.linkNamespace
    {
      return linkNamespace
    }

    return reverseAttribute(
      namespace: namespace,
      name: relation,
      attributes: attributes
    )?.namespace
  }

  private static func reverseAttribute(
    namespace: String,
    name: String,
    attributes: AttributeStore
  ) -> InstantAttribute? {
    attributes.reverseAttribute(namespace: namespace, name: name)
  }

  private func selectedFieldsReferenceDeclaredFields(
    _ fields: [String]?,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    fields?.allSatisfy { isDeclaredField($0, namespace: namespace, attributes: attributes) } ?? true
  }

  private func orderReferencesDeclaredField(
    _ order: InstantQueryOrder?,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    guard let order else { return true }
    guard !order.isServerCreatedAt else { return true }
    return isDeclaredField(order.field, namespace: namespace, attributes: attributes)
  }

  private func includesReferenceDeclaredLinks(
    _ includes: [InstantQueryInclude]?,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    guard let includes else { return true }
    return includes.allSatisfy { include in
      let childNamespace: String?
      switch include.direction {
      case .forward:
        childNamespace = attributes.attribute(namespace: namespace, name: include.name).flatMap {
          attribute in
          guard attribute.valueType == .ref else { return nil }
          return attribute.linkNamespace
        }

      case .reverse:
        childNamespace = reverseAttribute(
          namespace: namespace,
          name: include.name,
          attributes: attributes
        )?.namespace
      }

      guard let childNamespace else { return false }
      guard let query = include.query else { return true }
      guard query.namespace == childNamespace else { return false }
      guard filtersReferenceDeclaredFields(
        query.filters,
        namespace: query.namespace,
        attributes: attributes
      )
      else { return false }
      guard selectedFieldsReferenceDeclaredFields(
        query.selectedFields,
        namespace: query.namespace,
        attributes: attributes
      )
      else { return false }
      guard orderReferencesDeclaredField(query.order, namespace: query.namespace, attributes: attributes)
      else { return false }
      guard includesReferenceDeclaredLinks(query.includes, namespace: query.namespace, attributes: attributes)
      else { return false }
      return true
    }
  }

  private func reverseAttribute(
    namespace: String,
    name: String,
    attributes: AttributeStore
  ) -> InstantAttribute? {
    attributes.reverseAttribute(namespace: namespace, name: name)
  }

  private func project(
    _ snapshots: [InstantEntitySnapshot],
    selectedFields: [String]?
  ) -> [InstantEntitySnapshot] {
    guard let selectedFields else { return snapshots }
    let selectedFieldSet = Set(selectedFields)
    return snapshots.map { snapshot in
      InstantEntitySnapshot(
        id: snapshot.id,
        namespace: snapshot.namespace,
        values: snapshot.values.filter { selectedFieldSet.contains($0.key) },
        links: snapshot.links
      )
    }
  }

  private func filterReferencesDeclaredFields(
    _ filter: InstantQueryFilter,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    switch filter {
    case let .equals(field, _),
      let .notEquals(field, _),
      let .greaterThan(field, _),
      let .greaterThanOrEqual(field, _),
      let .lessThan(field, _),
      let .lessThanOrEqual(field, _),
      let .in(field, _),
      let .like(field, _),
      let .iLike(field, _),
      let .isNull(field),
      let .isNotNull(field):
      return fieldReferencesDeclaredField(field, namespace: namespace, attributes: attributes)

    case let .and(filters), let .or(filters):
      return filtersReferenceDeclaredFields(filters, namespace: namespace, attributes: attributes)
    }
  }

  private func matches(
    _ snapshot: InstantEntitySnapshot,
    filter: InstantQueryFilter,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    matches(
      snapshot,
      filters: [filter],
      namespace: namespace,
      attributes: attributes
    )
  }

  private func isDeclaredField(
    _ field: String,
    namespace: String,
    attributes: AttributeStore,
    allowReverseRelations: Bool = false
  ) -> Bool {
    Self.isDeclaredField(
      field,
      namespace: namespace,
      attributes: attributes,
      allowReverseRelations: allowReverseRelations
    )
  }

  private func fieldReferencesDeclaredField(
    _ field: String,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    guard field.contains(".") else {
      return isDeclaredField(
        field,
        namespace: namespace,
        attributes: attributes,
        allowReverseRelations: true
      )
    }
    guard
      let nested = nestedField(field),
      case let .success(targetNamespace) = Self.nestedFieldTargetNamespace(
        nested,
        namespace: namespace,
        attributes: attributes
      )
    else { return false }
    return isDeclaredField(
      nested.field,
      namespace: targetNamespace,
      attributes: attributes,
      allowReverseRelations: true
    )
  }

  private struct NestedField: Hashable, Sendable {
    var relations: [String]
    var field: String
  }

  private struct InvalidNestedRelation: Error, Hashable, Sendable {
    var name: String
    var namespace: String
  }

  private struct NestedFieldSnapshots: Hashable, Sendable {
    var namespace: String
    var snapshots: [InstantEntitySnapshot]
  }

  private func nestedField(_ field: String) -> NestedField? {
    let parts = field.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
    return NestedField(
      relations: parts.dropLast().map(String.init),
      field: String(parts[parts.count - 1])
    )
  }

  private func nestedFieldTargetNamespace(
    _ nested: NestedField,
    namespace: String,
    attributes: AttributeStore
  ) -> Result<String, InvalidNestedRelation> {
    Self.nestedFieldTargetNamespace(nested, namespace: namespace, attributes: attributes)
  }

  private func relationTargetNamespace(
    _ relation: String,
    namespace: String,
    attributes: AttributeStore
  ) -> String? {
    Self.relationTargetNamespace(relation, namespace: namespace, attributes: attributes)
  }

  private func linkedSnapshots(
    for snapshot: InstantEntitySnapshot,
    relation: String,
    namespace: String,
    attributes: AttributeStore
  ) -> NestedFieldSnapshots? {
    if
      let attribute = attributes.attribute(namespace: namespace, name: relation),
      attribute.valueType == .ref,
      let linkNamespace = attribute.linkNamespace
    {
      let ids = Set(snapshot.values[relation]?.values.compactMap(\.refValue) ?? [])
      return NestedFieldSnapshots(
        namespace: linkNamespace,
        snapshots: ids.sorted().compactMap {
          self.snapshot(entityID: $0, namespace: linkNamespace, attributes: attributes)
        }
      )
    }

    if
      let attribute = reverseAttribute(
        namespace: namespace,
        name: relation,
        attributes: attributes
      )
    {
      let ids = entityIDsReferencing(snapshot.id, attributeID: attribute.id)
      return NestedFieldSnapshots(
        namespace: attribute.namespace,
        snapshots: ids.compactMap {
          self.snapshot(entityID: $0, namespace: attribute.namespace, attributes: attributes)
        }
      )
    }

    return nil
  }

  private func matchesNestedField(
    _ snapshot: InstantEntitySnapshot,
    nested: NestedField,
    filter: InstantQueryFilter,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    matchesNestedField(
      snapshot,
      relations: nested.relations[...],
      filter: filter,
      namespace: namespace,
      attributes: attributes
    )
  }

  private func matchesNestedField(
    _ snapshot: InstantEntitySnapshot,
    relations: ArraySlice<String>,
    filter: InstantQueryFilter,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    guard let relation = relations.first else {
      return matches(snapshot, filter: filter, namespace: namespace, attributes: attributes)
    }
    guard
      let linked = linkedSnapshots(
        for: snapshot,
        relation: relation,
        namespace: namespace,
        attributes: attributes
      )
    else { return false }
    guard !linked.snapshots.isEmpty else {
      switch filter {
      case .notEquals, .isNull:
        return true
      default:
        return false
      }
    }
    return linked.snapshots.contains {
      matchesNestedField(
        $0,
        relations: relations.dropFirst(),
        filter: filter,
        namespace: linked.namespace,
        attributes: attributes
      )
    }
  }

  private func materializedValue(
    _ snapshot: InstantEntitySnapshot,
    field: String,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantMaterializedValue? {
    if let value = snapshot.values[field] {
      return value
    }
    if field == "id" {
      return .one(.string(snapshot.id))
    }
    guard
      let reverse = reverseAttribute(namespace: namespace, name: field, attributes: attributes)
    else { return nil }
    let ids = entityIDsReferencing(snapshot.id, attributeID: reverse.id)
    guard !ids.isEmpty else { return nil }
    return .many(ids.map(InstantValue.ref))
  }

  private func normalizedValue(
    _ value: InstantValue,
    field: String,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantValue {
    Self.normalizedValue(
      value,
      attribute: Self.fieldAttribute(
        field,
        namespace: namespace,
        attributes: attributes,
        allowReverseRelations: true
      )
    )
  }

  private func normalizedValues(
    _ values: [InstantValue],
    field: String,
    namespace: String,
    attributes: AttributeStore
  ) -> [InstantValue] {
    let attribute = Self.fieldAttribute(
      field,
      namespace: namespace,
      attributes: attributes,
      allowReverseRelations: true
    )
    return values.map { Self.normalizedValue($0, attribute: attribute) }
  }

  private func matchesNotEquals(
    _ snapshot: InstantEntitySnapshot,
    field: String,
    value: InstantValue,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    guard
      let materialized = materializedValue(
        snapshot,
        field: field,
        namespace: namespace,
        attributes: attributes
      )
    else { return true }
    return materialized.values.contains { $0 != value } || materialized.values.contains(.null)
  }

  private func isFieldNull(
    _ snapshot: InstantEntitySnapshot,
    field: String,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    guard
      let materialized = materializedValue(
        snapshot,
        field: field,
        namespace: namespace,
        attributes: attributes
      )
    else { return true }
    return materialized.values.contains(.null)
  }

  private func matchesComparison(
    _ snapshot: InstantEntitySnapshot,
    field: String,
    value: InstantValue,
    namespace: String,
    attributes: AttributeStore,
    allowed: Set<ComparisonResult>
  ) -> Bool {
    guard
      let materialized = materializedValue(
        snapshot,
        field: field,
        namespace: namespace,
        attributes: attributes
      )
    else { return false }
    return materialized.values.contains {
      guard Self.canRangeCompare($0, value) else { return false }
      return allowed.contains($0.compare(to: value))
    }
  }

  private static func canRangeCompare(_ lhs: InstantValue, _ rhs: InstantValue) -> Bool {
    switch (lhs, rhs) {
    case (.string, .string), (.number, .number), (.date, .date), (.bool, .bool):
      return true
    default:
      return false
    }
  }

  private func matchesStringPattern(
    _ snapshot: InstantEntitySnapshot,
    field: String,
    pattern: String,
    caseInsensitive: Bool,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    guard
      let materialized = materializedValue(
        snapshot,
        field: field,
        namespace: namespace,
        attributes: attributes
      )
    else { return false }
    return materialized.values.contains {
      guard case let .string(value) = $0 else { return false }
      return Self.matchesLikePattern(value, pattern: pattern, caseInsensitive: caseInsensitive)
    }
  }

  private enum LikeToken: Hashable {
    case literal(Character)
    case anyOne
    case anyMany
  }

  private static func matchesLikePattern(
    _ value: String,
    pattern: String,
    caseInsensitive: Bool
  ) -> Bool {
    let input = Array(caseInsensitive ? value.lowercased() : value)
    let tokens = tokenizeLikePattern(caseInsensitive ? pattern.lowercased() : pattern)

    var table = Array(
      repeating: Array(repeating: false, count: tokens.count + 1),
      count: input.count + 1
    )
    table[0][0] = true

    for inputIndex in 0...input.count {
      for tokenIndex in 0..<tokens.count where table[inputIndex][tokenIndex] {
        switch tokens[tokenIndex] {
        case let .literal(character):
          if inputIndex < input.count, input[inputIndex] == character {
            table[inputIndex + 1][tokenIndex + 1] = true
          }

        case .anyOne:
          if inputIndex < input.count {
            table[inputIndex + 1][tokenIndex + 1] = true
          }

        case .anyMany:
          table[inputIndex][tokenIndex + 1] = true
          if inputIndex < input.count {
            table[inputIndex + 1][tokenIndex] = true
          }
        }
      }
    }

    return table[input.count][tokens.count]
  }

  private static func tokenizeLikePattern(_ pattern: String) -> [LikeToken] {
    pattern.map { character in
      switch character {
      case "%":
        .anyMany
      case "_":
        .anyOne
      default:
        .literal(character)
      }
    }
  }

  private static func compare(
    _ lhs: QuerySnapshot,
    _ rhs: QuerySnapshot,
    order: InstantQueryOrder?
  ) -> ComparisonResult {
    guard let order else {
      return lhs.snapshot.id.compare(rhs.snapshot.id)
    }

    let lhsValue = lhs.sortValue
    let rhsValue = rhs.sortValue
    let valueComparison = compare(lhsValue, rhsValue)
    let directedComparison: ComparisonResult
    switch order.direction {
    case .ascending:
      directedComparison = valueComparison
    case .descending:
      directedComparison = valueComparison.reversed
    }
    guard directedComparison == .orderedSame else {
      return directedComparison
    }

    switch order.direction {
    case .ascending:
      return lhs.snapshot.id.compare(rhs.snapshot.id)
    case .descending:
      return rhs.snapshot.id.compare(lhs.snapshot.id)
    }
  }

  private static func effectiveOrder(_ order: InstantQueryOrder?) -> InstantQueryOrder {
    order ?? .serverCreatedAt
  }

  private static func compare(
    _ querySnapshot: QuerySnapshot,
    to cursor: InstantQueryCursor,
    order: InstantQueryOrder?,
    namespace: String,
    attributes: AttributeStore
  ) -> ComparisonResult {
    guard let order, let sortValue = cursor.sortValue else {
      return querySnapshot.snapshot.id.compare(cursor.entityID)
    }

    let value = querySnapshot.sortValue
    let normalizedSortValue = normalizedValue(
      sortValue,
      attribute: attributes.attribute(namespace: namespace, name: order.field)
    )
    let valueComparison = compare(value, normalizedSortValue)
    let directedComparison: ComparisonResult
    switch order.direction {
    case .ascending:
      directedComparison = valueComparison
    case .descending:
      directedComparison = valueComparison.reversed
    }
    guard directedComparison == .orderedSame else {
      return directedComparison
    }

    switch order.direction {
    case .ascending:
      return querySnapshot.snapshot.id.compare(cursor.entityID)
    case .descending:
      return cursor.entityID.compare(querySnapshot.snapshot.id)
    }
  }

  private static func orderValue(_ querySnapshot: QuerySnapshot, field: String) -> InstantValue? {
    querySnapshot.sortValue
  }

  private static func orderValue(
    _ snapshot: InstantEntitySnapshot,
    serverCreatedAt: InstantValue?,
    field: String
  ) -> InstantValue? {
    field == InstantQueryOrder.serverCreatedAtField
      ? serverCreatedAt
      : snapshot.values[field]?.first
  }

  private static func compare(_ lhs: InstantValue?, _ rhs: InstantValue?) -> ComparisonResult {
    switch (lhs, rhs) {
    case (nil, nil):
      return .orderedSame
    case (nil, .some(.null)), (.some(.null), nil):
      return .orderedSame
    case (nil, .some):
      return .orderedAscending
    case (.some, nil):
      return .orderedDescending
    case let (.some(lhs), .some(rhs)):
      return lhs.compare(to: rhs)
    }
  }

  private static func triplePrecedes(_ lhs: InstantTriple, _ rhs: InstantTriple) -> Bool {
    if lhs.entityID != rhs.entityID {
      return lhs.entityID < rhs.entityID
    }
    if lhs.attributeID != rhs.attributeID {
      return lhs.attributeID < rhs.attributeID
    }
    return lhs.value.comparableKey < rhs.value.comparableKey
  }

  private static func deduplicatingStoredTriples(
    _ triples: [InstantTriple]
  ) -> [InstantTriple] {
    var triplesByIdentity: [StoredTripleIdentity: InstantTriple] = [:]
    triplesByIdentity.reserveCapacity(triples.count)
    for triple in triples {
      let identity = StoredTripleIdentity(
        entityID: triple.entityID,
        attributeID: triple.attributeID,
        value: triple.value
      )
      if let existing = triplesByIdentity[identity] {
        if existing.txTime < triple.txTime
          || (existing.txTime == triple.txTime && existing.txID < triple.txID)
        {
          triplesByIdentity[identity] = triple
        }
      } else {
        triplesByIdentity[identity] = triple
      }
    }
    return triplesByIdentity.values.sorted(by: triplePrecedes)
  }

  private static func lexicographicallyPrecedes(_ lhs: [String], _ rhs: [String]) -> Bool {
    for (left, right) in zip(lhs, rhs) {
      if left != right {
        return left < right
      }
    }
    return lhs.count < rhs.count
  }

  private static func valuePrecedes(
    _ lhs: InstantValue?,
    _ rhs: InstantValue?,
    lhsTieBreaker: [String],
    rhsTieBreaker: [String]
  ) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
      return lexicographicallyPrecedes(lhsTieBreaker, rhsTieBreaker)
    case (nil, .some):
      return true
    case (.some, nil):
      return false
    case let (.some(lhs), .some(rhs)):
      switch lhs.compare(to: rhs) {
      case .orderedAscending:
        return true
      case .orderedDescending:
        return false
      case .orderedSame:
        return lexicographicallyPrecedes(lhsTieBreaker, rhsTieBreaker)
      }
    }
  }
}

extension TripleIndexes: Hashable {
  static func == (lhs: TripleIndexes, rhs: TripleIndexes) -> Bool {
    lhs.eav == rhs.eav
      && lhs.vae == rhs.vae
      && lhs.indexedValueEntities == rhs.indexedValueEntities
      && lhs.indexedEntityValues == rhs.indexedEntityValues
      && lhs.entitiesByNamespace == rhs.entitiesByNamespace
      && lhs.derivedIndexAttributeShapes == rhs.derivedIndexAttributeShapes
      && lhs.storedTripleCount == rhs.storedTripleCount
      && lhs.internedTxIDsBox.internedTxIDs == rhs.internedTxIDsBox.internedTxIDs
      && lhs.deferredValueKeysToRemove == rhs.deferredValueKeysToRemove
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(eav)
    hasher.combine(vae)
    hasher.combine(indexedValueEntities)
    hasher.combine(indexedEntityValues)
    hasher.combine(entitiesByNamespace)
    hasher.combine(derivedIndexAttributeShapes)
    hasher.combine(storedTripleCount)
    hasher.combine(internedTxIDsBox.internedTxIDs)
    hasher.combine(deferredValueKeysToRemove)
  }
}

private extension InstantValue {
  var queryValidationTypeDescription: String {
    switch self {
    case .null:
      return "null"
    case .string:
      return "string"
    case .number:
      return "number"
    case .bool:
      return "boolean"
    case .date:
      return "date"
    case .json:
      return "json"
    case .ref:
      return "ref"
    case .lookupRef:
      return "lookup ref"
    }
  }
}

private extension InstantValueType {
  var queryValidationDescription: String {
    switch self {
    case .string:
      return "string"
    case .number:
      return "number"
    case .boolean:
      return "boolean"
    case .date:
      return "date"
    case .json:
      return "json"
    case .any:
      return "any"
    case .ref:
      return "ref"
    }
  }

  var isRangeComparableInQueries: Bool {
    switch self {
    case .string, .number, .boolean, .date:
      return true
    case .json, .any, .ref:
      return false
    }
  }
}

private extension ComparisonResult {
  var reversed: Self {
    switch self {
    case .orderedAscending:
      return .orderedDescending
    case .orderedDescending:
      return .orderedAscending
    case .orderedSame:
      return .orderedSame
    }
  }
}
