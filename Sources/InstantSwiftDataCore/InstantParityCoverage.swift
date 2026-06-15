import Foundation

public enum InstantParityCoverageSourceKind: String, Codable, Hashable, Sendable {
  case instantTypeScript = "instant-typescript"
  case sqliteData = "sqlite-data"
}

public enum InstantParityCoverageStatus: String, Codable, CaseIterable, Hashable, Sendable {
  case exact
  case adapted
  case blocked
  case notApplicable = "not-applicable"
}

public struct InstantParityCoverageRecord: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var sourceKind: InstantParityCoverageSourceKind
  public var sourceFile: String
  public var sourceTestName: String
  public var swiftFile: String
  public var swiftTestName: String
  public var surface: String
  public var status: InstantParityCoverageStatus
  public var notes: String

  public init(
    id: String,
    sourceKind: InstantParityCoverageSourceKind,
    sourceFile: String,
    sourceTestName: String,
    swiftFile: String,
    swiftTestName: String,
    surface: String,
    status: InstantParityCoverageStatus,
    notes: String
  ) {
    self.id = id
    self.sourceKind = sourceKind
    self.sourceFile = sourceFile
    self.sourceTestName = sourceTestName
    self.swiftFile = swiftFile
    self.swiftTestName = swiftTestName
    self.surface = surface
    self.status = status
    self.notes = notes
  }
}

public struct InstantParityCoverageReport: Codable, Equatable, Sendable {
  public var event: String
  public var coverageComplete: Bool
  public var recordCount: Int
  public var exactCount: Int
  public var adaptedCount: Int
  public var blockedCount: Int
  public var notApplicableCount: Int
  public var sourceFiles: [String]
  public var swiftFiles: [String]
  public var records: [InstantParityCoverageRecord]

  public init(records: [InstantParityCoverageRecord]) {
    self.event = "parity-report"
    self.coverageComplete = records.allSatisfy { $0.status != .blocked }
    self.recordCount = records.count
    self.exactCount = records.filter { $0.status == .exact }.count
    self.adaptedCount = records.filter { $0.status == .adapted }.count
    self.blockedCount = records.filter { $0.status == .blocked }.count
    self.notApplicableCount = records.filter { $0.status == .notApplicable }.count
    self.sourceFiles = records.map(\.sourceFile).uniquedSorted()
    self.swiftFiles = records.map(\.swiftFile).uniquedSorted()
    self.records = records
  }

  public func evidenceRows(
    appID: String,
    timestampMs: Int64 = 0
  ) -> [ValidationEvidenceRow<InstantParityCoverageRecord>] {
    records.map { record in
      ValidationEvidenceRow(
        caseID: "validation.parity.report",
        side: record.sourceKind.rawValue,
        event: "parity-record",
        appID: appID,
        entityID: record.id,
        timestampMs: timestampMs,
        ok: record.status != .blocked,
        details: record
      )
    }
  }
}

public enum InstantSwiftDataParityCoverage {
  public static var current: InstantParityCoverageReport {
    InstantParityCoverageReport(records: records)
  }

  public static let records: [InstantParityCoverageRecord] = [
    instant(
      id: "instant.store.simple-add",
      sourceFile: storeSource,
      sourceTestName: "simple add",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "simpleAddMaterializesScalarAttribute",
      surface: "triple-store",
      status: .exact,
      notes: "A single scalar add creates one materialized entity."
    ),
    instant(
      id: "instant.store.cardinality-one-add",
      sourceFile: storeSource,
      sourceTestName: "cardinality-one add",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "cardinalityOneAddKeepsLastValueInSameTransaction",
      surface: "triple-store",
      status: .exact,
      notes: "Cardinality-one attributes keep only the newest value in a transaction."
    ),
    instant(
      id: "instant.store.link-unlink",
      sourceFile: storeSource,
      sourceTestName: "link/unlink",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "linkAndUnlinkPortsUpstreamUserBookshelfShape",
      surface: "links",
      status: .exact,
      notes: "User/bookshelf scalar writes, links, unlink, and relink materialize through the core store."
    ),
    instant(
      id: "instant.store.link-unlink-multi",
      sourceFile: storeSource,
      sourceTestName: "link/unlink multi",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "manyLinkUnlinkAndRelinkPortsUpstreamMultiLinkShape",
      surface: "links",
      status: .adapted,
      notes: "Swift uses an article/tag many-ref fixture and verifies both forward and reverse materialized links through unlink and relink."
    ),
    instant(
      id: "instant.store.link-unlink-without-update",
      sourceFile: storeSource,
      sourceTestName: "link/unlink without update",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "linkAndUnlinkWithoutScalarUpdatesMaintainForwardAndReverseIndexes",
      surface: "links",
      status: .adapted,
      notes: "Swift links already-created entities without scalar writes and verifies forward/reverse indexes before and after relink."
    ),
    instant(
      id: "instant.store.delete-entity",
      sourceFile: storeSource,
      sourceTestName: "delete entity",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "deleteEntityRemovesEntityAndInboundReferences",
      surface: "mutations",
      status: .exact,
      notes: "Entity deletion removes local triples and inbound refs."
    ),
    instant(
      id: "instant.store.schema-lifecycle",
      sourceFile: storeSource,
      sourceTestName: "schema attrs add/update/delete",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "addingAndRenamingAttributesReindexesExistingTriples",
      surface: "schema",
      status: .adapted,
      notes: "Swift replaces declared attributes directly instead of applying the TypeScript schema patch representation."
    ),
    instant(
      id: "instant.store.merge-json",
      sourceFile: storeSource,
      sourceTestName: "merge",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "storeDeepMergePortsUpstreamObjectArrayAndNullSemantics",
      surface: "mutations",
      status: .adapted,
      notes: "Swift covers JSON merge semantics and rejects relationship attributes before local materialization."
    ),
    instant(
      id: "instant.store.cascade-delete",
      sourceFile: storeSource,
      sourceTestName: "on-delete cascade",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "onDeleteCascadePortsUpstreamBookSeriesShape",
      surface: "links",
      status: .adapted,
      notes: "Swift uses schema-aware delete steps and local cascade metadata."
    ),
    instant(
      id: "instant.store.on-delete-reverse-cascade",
      sourceFile: storeSource,
      sourceTestName: "on-delete-reverse cascade",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "onDeleteReverseCascadePortsUpstreamBookSeriesShape",
      surface: "links",
      status: .adapted,
      notes: "Swift ports the reverse cascade book series fixture with explicit reverse on-delete metadata."
    ),
    instant(
      id: "instant.store.date-conversion",
      sourceFile: storeSource,
      sourceTestName: "date conversion",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "dateConversionMaterializesDateTypedSchemaValues",
      surface: "dates",
      status: .adapted,
      notes: "Swift materializes date attributes as Date values after coercing Instant-compatible inputs."
    ),
    instant(
      id: "instant.store.json-serialization",
      sourceFile: storeSource,
      sourceTestName: "JSON serialization round-trips",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "storeSnapshotJSONRoundTripsAndRestoresMaterializedLinks",
      surface: "triple-store",
      status: .adapted,
      notes: "Swift Codable snapshots encode attributes and triples, decode back to the same value, and rematerialize forward/reverse links from the restored indexes."
    ),
    instant(
      id: "instant.store.rule-params-no-op",
      sourceFile: storeSource,
      sourceTestName: "ruleParams no-ops",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "ruleParamsNoOpsAndFollowingUpdateMaterializes",
      surface: "mutations",
      status: .exact,
      notes: "Rule params are retained as a transaction operation that does not write triples, while the following update materializes."
    ),
    instant(
      id: "instant.store.recursive-links-same-id",
      sourceFile: storeSource,
      sourceTestName: "recursive links w same id",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "recursiveLinksWithSameRawIDDeleteOnlyRequestedNamespace",
      surface: "links",
      status: .adapted,
      notes: "Swift uses namespace-scoped deletion so an entity sharing the same raw id in another namespace survives the cascading delete."
    ),
    instant(
      id: "instant.store.v0-store-restore",
      sourceFile: storeSource,
      sourceTestName: "v0 store restores",
      swiftFile: storeParitySwiftFile,
      swiftTestName: "v0StoreSnapshotRestoresFromLegacyAttrsPayload",
      surface: "triple-store",
      status: .adapted,
      notes: "Swift accepts legacy attrs/triples snapshot payloads, decodes them into the modern snapshot, and rematerializes links."
    ),
    instant(
      id: "instant.utils.date-coercion",
      sourceFile: "upstream/instant/client/packages/core/__tests__/src/utils/dates.test.ts",
      sourceTestName: "coerceToDate valid strings, invalid strings, and edge cases",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantDateCoercionTests.swift",
      swiftTestName: "InstantDateCoercionTests",
      surface: "dates",
      status: .adapted,
      notes: "Swift ports Instant's date string, Date, number, and unsupported-type coercion matrix through InstantValue; invalid Swift inputs return nil instead of throwing JavaScript exceptions."
    ),
    instant(
      id: "instant.query.simple-where",
      sourceFile: instaQLSource,
      sourceTestName: "Simple Where",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLSimpleWhereAndDeepRelationFilters",
      surface: "query",
      status: .exact,
      notes: "Top-level scalar equality filters match the upstream fixture results."
    ),
    instant(
      id: "instant.query.simple-without-where",
      sourceFile: instaQLSource,
      sourceTestName: "Simple Query Without Where",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLSimpleWhereAndDeepRelationFilters",
      surface: "query",
      status: .exact,
      notes: "A namespace query without filters returns the upstream Zeneca user handles."
    ),
    instant(
      id: "instant.query.simple-where-expected-keys",
      sourceFile: instaQLSource,
      sourceTestName: "Simple Where has expected keys",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLSimpleWhereAndDeepRelationFilters",
      surface: "query",
      status: .adapted,
      notes: "Swift snapshots expose the same scalar keys while storing id separately from the materialized values dictionary."
    ),
    instant(
      id: "instant.query.simple-where-multiple-clauses",
      sourceFile: instaQLSource,
      sourceTestName: "Simple Where with multiple clauses",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLSimpleWhereAndDeepRelationFilters",
      surface: "query",
      status: .exact,
      notes: "Multiple top-level where clauses combine with deep relation filters and match the upstream result sets."
    ),
    instant(
      id: "instant.query.where-in-like",
      sourceFile: instaQLSource,
      sourceTestName: "Where in / Where %like%",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLSimpleWhereAndDeepRelationFilters",
      surface: "query",
      status: .exact,
      notes: "IN and LIKE filters over the Zeneca fixture match the upstream result sets."
    ),
    instant(
      id: "instant.query.where-like-equality",
      sourceFile: instaQLSource,
      sourceTestName: "Where like equality",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLSimpleWhereAndDeepRelationFilters",
      surface: "query",
      status: .exact,
      notes: "A LIKE pattern without wildcards behaves like equality for the upstream handle query."
    ),
    instant(
      id: "instant.query.where-deep-like-prefix-suffix",
      sourceFile: instaQLSource,
      sourceTestName: "Where startsWith deep / Where endsWith deep",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLSimpleWhereAndDeepRelationFilters",
      surface: "query",
      status: .exact,
      notes: "Deep relation LIKE prefix and suffix filters match the upstream bookshelf/book title fixtures."
    ),
    instant(
      id: "instant.query.like-edges",
      sourceFile: instaQLSource,
      sourceTestName: "like case sensitivity / like special regex characters",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLLikeAndAndFilterEdges",
      surface: "query",
      status: .exact,
      notes: "LIKE/ILIKE case behavior and pattern escaping are covered by fixture mutations."
    ),
    instant(
      id: "instant.query.where-and",
      sourceFile: instaQLSource,
      sourceTestName: "Where and",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLLikeAndAndFilterEdges",
      surface: "query",
      status: .exact,
      notes: "AND filters over two deep book-title relations return the same matching users as upstream."
    ),
    instant(
      id: "instant.query.logical-or",
      sourceFile: instaQLSource,
      sourceTestName: "Where OR test.each",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLCompoundOrFilters",
      surface: "query",
      status: .exact,
      notes: "Compound OR cases are ported as Swift table-driven assertions."
    ),
    instant(
      id: "instant.query.associations",
      sourceFile: instaQLSource,
      sourceTestName: "Get association / Get reverse association / Get deep association",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLForwardAndReverseAssociations",
      surface: "query",
      status: .adapted,
      notes: "Swift uses explicit include plans for forward, reverse, and deep linked materialization."
    ),
    instant(
      id: "instant.query.nested-wheres",
      sourceFile: instaQLSource,
      sourceTestName: "Nested wheres / Nested wheres with OR queries / Nested wheres with AND queries",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLForwardAndReverseAssociations",
      surface: "query",
      status: .adapted,
      notes: "Swift include plans carry nested filters and nested includes explicitly while preserving the upstream nested result sets."
    ),
    instant(
      id: "instant.query.deep-where",
      sourceFile: instaQLSource,
      sourceTestName: "Deep where",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLSimpleWhereAndDeepRelationFilters",
      surface: "query",
      status: .exact,
      notes: "A deep relation equality filter on bookshelf book title returns the upstream user handle."
    ),
    instant(
      id: "instant.query.multiple-connections",
      sourceFile: instaQLSource,
      sourceTestName: "multiple connections",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLForwardAndReverseAssociations",
      surface: "query",
      status: .adapted,
      notes: "Swift materializes multiple includes for the same namespace query with explicit forward and reverse include declarations."
    ),
    instant(
      id: "instant.query.missing-namespaces-attributes",
      sourceFile: instaQLSource,
      sourceTestName: "Missing etype / Missing inner etype / Missing filter attr",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLMissingNamespacesAndAttributes",
      surface: "query",
      status: .adapted,
      notes: "Raw Swift materialization treats missing namespaces and filters as empty, while strict runtime validation rejects undeclared include targets before cache writes."
    ),
    instant(
      id: "instant.query.relation-filter-refs",
      sourceFile: instaQLSource,
      sourceTestName: "query forward references work with and without id / query reverse references work with and without id",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLRelationFiltersWorkWithIDsAndLinkFields",
      surface: "query",
      status: .adapted,
      notes: "Swift tests both relation.id and relation-ref filter forms across declared forward and reverse link metadata."
    ),
    instant(
      id: "instant.query.namespace-isolation",
      sourceFile: instaQLSource,
      sourceTestName: "objects are created by etype",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLNamespaceIsolationAndObjectValues",
      surface: "query",
      status: .adapted,
      notes: "Swift ports the same raw id across namespaces and verifies attributes materialize only for the queried namespace."
    ),
    instant(
      id: "instant.query.create-update-triples",
      sourceFile: instaQLSource,
      sourceTestName: "create and update triples in one tx",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLNamespaceIsolationAndObjectValues",
      surface: "query",
      status: .adapted,
      notes: "Swift uses explicit strict-create and strict-update preconditions while proving the same create-then-update materialized values."
    ),
    instant(
      id: "instant.query.object-values",
      sourceFile: instaQLSource,
      sourceTestName: "object values",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLNamespaceIsolationAndObjectValues",
      surface: "query",
      status: .exact,
      notes: "JSON object attributes materialize through InstantValue.json with the upstream object payload."
    ),
    instant(
      id: "instant.query.pagination-ordering",
      sourceFile: instaQLSource,
      sourceTestName: "pagination and arbitrary ordering",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLPaginationOrderingAndFields",
      surface: "query",
      status: .adapted,
      notes: "Swift exercises local pagination/order fields with typed query plans."
    ),
    instant(
      id: "instant.query.fields",
      sourceFile: instaQLSource,
      sourceTestName: "fields",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLPaginationOrderingAndFields",
      surface: "query",
      status: .adapted,
      notes: "Swift treats partial selections as snapshots rather than decoded full entities."
    ),
    instant(
      id: "instant.query.null-not-comparators",
      sourceFile: instaQLSource,
      sourceTestName: "$isNull / $not and $ne / comparators",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamInstaQLNullNotEqualsAndComparators",
      surface: "query",
      status: .exact,
      notes: "Null, negation, not-equals, and comparison filters are matched against the upstream fixture."
    ),
    instant(
      id: "instant.datalog.movie-fixture",
      sourceFile: datalogSource,
      sourceTestName: "querySingle / queryWhere / play",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamDatalogMovieFixtureQueries",
      surface: "query",
      status: .adapted,
      notes: "Swift materializes the same movie/person facts through Instant snapshots."
    ),
    instant(
      id: "instant.datalog.pattern-query",
      sourceFile: datalogSource,
      sourceTestName: "matchPattern / query",
      swiftFile: queryExecutionSwiftFile,
      swiftTestName: "upstreamDatalogPatternMatchingAndBindingQueries",
      surface: "query",
      status: .adapted,
      notes: "Swift ports datalog's raw triple pattern binding, conflict semantics, and find-result arity over InstantStoreSnapshot. Entity and attribute terms are typed as strings, and string/ref values bind as raw ids to preserve repeated-variable joins."
    ),
    instant(
      id: "instant.query-validation.shape",
      sourceFile: queryValidationSource,
      sourceTestName: "top-level object validation",
      swiftFile: queryValidationSwiftFile,
      swiftTestName: "upstreamTypedQueryShapeAndDollarOptions",
      surface: "query-validation",
      status: .adapted,
      notes: "Swift query plans are typed, so malformed JavaScript object shapes map to explicit invalid plan cases."
    ),
    instant(
      id: "instant.query-validation.namespace-relation",
      sourceFile: queryValidationSource,
      sourceTestName: "namespace validation / relation validation",
      swiftFile: queryValidationSwiftFile,
      swiftTestName: "upstreamTopLevelEntityNames",
      surface: "query-validation",
      status: .exact,
      notes: "Unknown namespaces and invalid relation includes fail before cache writes."
    ),
    instant(
      id: "instant.query-validation.where",
      sourceFile: queryValidationSource,
      sourceTestName: "where clause type/id/dot-notation validation",
      swiftFile: queryValidationSwiftFile,
      swiftTestName: "upstreamWhereClauseTypeValidation",
      surface: "query-validation",
      status: .adapted,
      notes: "Swift validates field paths and typed filter values through declared attributes."
    ),
    instant(
      id: "instant.query-validation.pagination",
      sourceFile: queryValidationSource,
      sourceTestName: "nested pagination validation",
      swiftFile: queryValidationSwiftFile,
      swiftTestName: "upstreamNestedIncludePaginationRestriction",
      surface: "query-validation",
      status: .exact,
      notes: "Nested pagination is rejected while top-level pagination remains valid."
    ),
    instant(
      id: "instant.transaction-validation.basic",
      sourceFile: transactionValidationSource,
      sourceTestName: "validates basic transaction chunk",
      swiftFile: transactionValidationSwiftFile,
      swiftTestName: "upstreamValidatesBasicTransactionChunks",
      surface: "transaction-validation",
      status: .adapted,
      notes: "Swift starts from structured transaction values rather than JavaScript chunks."
    ),
    instant(
      id: "instant.transaction-validation.create-update",
      sourceFile: transactionValidationSource,
      sourceTestName: "validates create/update operations",
      swiftFile: transactionValidationSwiftFile,
      swiftTestName: "upstreamValidatesCreateAndUpdateOperations",
      surface: "transaction-validation",
      status: .adapted,
      notes: "Declared attributes are type checked while schemaless unknown scalar attributes remain hidden from materialization."
    ),
    instant(
      id: "instant.transaction-validation.merge-delete",
      sourceFile: transactionValidationSource,
      sourceTestName: "validates merge/delete operations",
      swiftFile: transactionValidationSwiftFile,
      swiftTestName: "upstreamValidatesMergeAndDeleteOperations",
      surface: "transaction-validation",
      status: .adapted,
      notes: "Swift validates merge values and deletes entities through typed triple operations."
    ),
    instant(
      id: "instant.transaction-validation.lookup-rule-params",
      sourceFile: transactionValidationSource,
      sourceTestName: "lookup refs and rule params",
      swiftFile: transactionValidationSwiftFile,
      swiftTestName: "upstreamAllowsLookupValuesForEntityWrites",
      surface: "transaction-validation",
      status: .adapted,
      notes: "Lookup refs and rule params are preserved for transport lowering while local optimistic effects stay deterministic."
    ),
    instant(
      id: "instant.instaml.mode-update",
      sourceFile: instamlSource,
      sourceTestName: "mode: update",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "transportMutationPortsInstamlModeUpdateOptions",
      surface: "instaml",
      status: .adapted,
      notes: "Swift uses explicit update preconditions instead of JavaScript store-aware inference; encoded txSteps preserve absent options for upserts and exact update-mode payloads."
    ),
    instant(
      id: "instant.instaml.invalid-link-lookup-attr",
      sourceFile: instamlSource,
      sourceTestName: "it throws if you use an invalid link attr",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "invalidLookupAttributePortsInstamlInvalidLinkAttrRejection",
      surface: "instaml",
      status: .adapted,
      notes: "Swift lookup refs use declared attribute ids rather than JavaScript lookup labels; link-shaped undeclared lookup attrs fail validation before local materialization or outbox persistence."
    ),
    instant(
      id: "instant.instaml.dotted-lookup-attribute",
      sourceFile: instamlSource,
      sourceTestName: "it doesn't throw if you have a period in your attr",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "lookupAttributeWithPeriodPortsInstamlDottedAttr",
      surface: "instaml",
      status: .adapted,
      notes: "Swift lookup refs use full attribute ids rather than JavaScript lookup labels; transport lowering preserves dotted lookup arrays and local optimistic resolution accepts seeded dotted unique attributes."
    ),
    instant(
      id: "instant.instaml.lookup-link-value-arrays",
      sourceFile: instamlSource,
      sourceTestName: "lookup creates unique attrs for lookups in link values with arrays",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "transportMutationPortsInstamlLookupRefArraysInLinkValues",
      surface: "instaml",
      status: .adapted,
      notes: "Swift uses declared attr ids and repeated ref inserts instead of JavaScript link arrays/add-attr generation; transport lowering preserves each lookup ref value on the same link attr."
    ),
    instant(
      id: "instant.instaml.no-duplicate-ref-attrs",
      sourceFile: instamlSource,
      sourceTestName: "it doesn't create duplicate ref attrs",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "reciprocalLinksUseSingleRefAttributeForInstamlDuplicateRefAttrParity",
      surface: "instaml",
      status: .adapted,
      notes: "Swift uses declared attributes rather than JavaScript add-attr generation; reciprocal forward/reverse link intents share one physical ref attr, materialize once locally, and preserve both transport add-triple intents."
    ),
    instant(
      id: "instant.instaml.schema-attrs-and-links",
      sourceFile: instamlSource,
      sourceTestName: "Schema: uses info in `attrs` and `links`",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "schemaMetadataPortsInstamlAttrsAndLinks",
      surface: "instaml",
      status: .adapted,
      notes: "Swift uses declared attributes rather than JavaScript add-attr generation; schema metadata preserves scalar uniqueness/indexing and forward/reverse link identity while transport lowering emits the same three add-triple intents."
    ),
    instant(
      id: "instant.instaml.schema-no-duplicate-ref-attrs",
      sourceFile: instamlSource,
      sourceTestName: "Schema: doesn't create duplicate ref attrs",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "schemaReciprocalLinksUseSingleRefAttributeForInstamlDuplicateRefAttrParity",
      surface: "instaml",
      status: .adapted,
      notes: "Swift uses declared attributes and normalized physical triples rather than JavaScript add-attr generation; the reverse-side schema link intent is represented as a second write to the same forward ref attr, dedupes locally, and preserves both transport add-triple intents."
    ),
    instant(
      id: "instant.instaml.schema-custom-lookup-attrs",
      sourceFile: instamlSource,
      sourceTestName: "Schema: lookup creates unique attrs for custom lookups",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "schemaLookupRefsUseDeclaredUniqueAttrForInstamlCustomLookupParity",
      surface: "instaml",
      status: .adapted,
      notes: "Swift uses declared attributes rather than JavaScript add-attr generation; schema metadata preserves the unique/indexed lookup attr, unresolved lookup writes remain pending for transport, and seeded local lookup rows resolve optimistically."
    ),
    instant(
      id: "instant.instaml.schema-lookup-link-value",
      sourceFile: instamlSource,
      sourceTestName: "Schema: lookup creates unique attrs for lookups in link values",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "schemaLookupRefsInLinkValuesUseDeclaredAttrsForInstamlParity",
      surface: "instaml",
      status: .adapted,
      notes: "Swift uses declared attributes rather than JavaScript add-attr generation and preserves the declared many relation cardinality; lookup link values stay lookup-shaped for transport and resolve locally once the unique target row exists."
    ),
    instant(
      id: "instant.instaml.schema-lookup-link-value-arrays",
      sourceFile: instamlSource,
      sourceTestName: "Schema: lookup creates unique attrs for lookups in link values with arrays",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "schemaLookupRefArraysInLinkValuesUseDeclaredAttrsForInstamlParity",
      surface: "instaml",
      status: .adapted,
      notes: "Swift uses declared attributes rather than JavaScript add-attr generation and preserves the declared many relation cardinality; lookup link array values lower to repeated lookup-shaped transport writes and resolve locally once each unique target row exists."
    ),
    instant(
      id: "instant.instaml.schema-ref-lookup-attrs",
      sourceFile: instamlSource,
      sourceTestName: "Schema: lookup creates unique ref attrs for ref lookup",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "schemaRefLookupUsesDeclaredUniqueRefAttrForInstamlParity",
      surface: "instaml",
      status: .adapted,
      notes: "Swift uses declared attributes rather than JavaScript add-attr generation and normalizes id attrs as indexed primary keys; ref lookup entities and lookup id values stay lookup-shaped for transport and resolve locally when the unique ref row exists."
    ),
    instant(
      id: "instant.instaml.schema-ref-lookup-link-value",
      sourceFile: instamlSource,
      sourceTestName: "Schema: lookup creates unique ref attrs for ref lookup in link value",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "schemaRefLookupInLinkValueUsesReverseIdentityForInstamlParity",
      surface: "instaml",
      status: .adapted,
      notes: "Swift uses declared attributes rather than JavaScript add-attr generation and normalizes id attrs as indexed primary keys; reverse-identity ref lookups stay lookup-shaped for transport link values and resolve locally through the declared forward ref attr."
    ),
    instant(
      id: "instant.instaml.schema-checked-data-types",
      sourceFile: instamlSource,
      sourceTestName: "Schema: populates checked-data-type",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "schemaCheckedDataTypesPreserveInstamlScalarMetadata",
      surface: "instaml",
      status: .adapted,
      notes: "Swift uses declared value types rather than JavaScript add-attr generation; string, number, date, and boolean map to checked scalar metadata, i.any() is modeled explicitly, and runtime writes are type checked before persistence."
    ),
    instant(
      id: "instant.instaml.closed-mutation-surface",
      sourceFile: instamlSource,
      sourceTestName: "instatx should not be too permissive",
      swiftFile: "Tests/InstantSwiftDataTests/TypedAPITests.swift",
      swiftTestName: "typedMutationSurfaceIsClosedForInstamlPermissivenessParity",
      surface: "instaml",
      status: .adapted,
      notes: "Swift has no dynamic unknown operation member to access after update; the adapted proof records a supported typed update lowering to the closed InstantTripleOperation enum."
    ),
    instant(
      id: "instant.weak-hash",
      sourceFile: weakHashSource,
      sourceTestName: "selected fields / object key order / date / known query",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantQueryCacheKeyParityTests.swift",
      swiftTestName: "upstreamWeakHashCanonicalQueryShapeInvariants",
      surface: "query-cache",
      status: .adapted,
      notes: "Swift pins stable cache keys for equivalent query plans and canonical JSON/date values."
    ),
    instant(
      id: "instant.weak-hash-legacy-known-query",
      sourceFile: weakHashLegacySource,
      sourceTestName: "produces a stable hash for a known query",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantQueryCacheKeyParityTests.swift",
      swiftTestName: "upstreamWeakHashLegacyKnownQueryPin / upstreamWeakHashLegacyJSSemanticsPins",
      surface: "query-cache",
      status: .adapted,
      notes: "Swift ports the pre-v1.0.39 weakHashLegacy algorithm for representable JSONValue query shapes, including JS Number, UTF-16, array, object, and parseInt coercion behavior, and pins the upstream migration smoke-test key; IndexedDB querySubs/syncSubs migration behavior is not exercised."
    ),
    instant(
      id: "instant.persisted-object.query-cache-gc",
      sourceFile: persistedObjectSource,
      sourceTestName: "save / replace-adapted / garbage collect by entries, size, and age",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "queryCacheRowsSaveReplaceAndReloadForPersistedObjectParity / queryCachePruningPreservesLiveKeysAndDropsOldestUnpreservedRowsForPersistedObjectParity / queryCachePruningUsesEncodedRowBytesForPersistedObjectSizeParity / queryCachePruningUsesUpdatedAtForPersistedObjectAgeParity / queryCachePruningKeepsRowsAtPersistedObjectAgeCutoff",
      surface: "query-cache-persistence",
      status: .adapted,
      notes: "Swift ports PersistedObject's durable keyed cache lifecycle to SQLite query cache rows: cache-key replacement covers saved/reloaded storage but not PersistedObject's custom storage-memory merge callback, preservingCacheKeys protects live rows, and max-entry, encoded-JSON-byte, and strict updated-at age policies prune only unloaded rows. Browser IndexedDB connection recovery and onKeyLoaded callbacks are not claimed."
    ),
    instant(
      id: "instant.schema.builder-shape",
      sourceFile: schemaSource,
      sourceTestName: "runs without exception",
      swiftFile: schemaPrinterSwiftFile,
      swiftTestName: "schemaParserRoundTripsUpstreamSchemaBuilderEntityLinkShape",
      surface: "schema",
      status: .adapted,
      notes: "Swift builds the same upstream users/posts/comments/birthdays entity and link shape, prints it to TypeScript schema syntax, and parses it back. TypeScript-only query inference and asType helper assertions are out of scope for this adapted record."
    ),
    instant(
      id: "instant.schema.json-serialization-round-trip",
      sourceFile: serializeSchemaSource,
      sourceTestName: "ability to parse stringified schema into real schema object",
      swiftFile: schemaPrinterSwiftFile,
      swiftTestName: "schemaDocumentJSONRoundTripsUpstreamCoreSchemaShape",
      surface: "schema-serialization",
      status: .adapted,
      notes: "Swift mirrors Instant's stringify/parseSchemaFromJSON proof with Swift-native Codable schema values: the same entity, link, and room payload shape JSON-encodes, decodes, and compares equal. TypeScript asType helper assertions are out of scope for this adapted record."
    ),
    instant(
      id: "instant.utils.object-path-mutation",
      sourceFile: objectUtilsSource,
      sourceTestName: "assocInMutative / insertInMutative / dissocInMutative",
      swiftFile: "Tests/InstantSwiftDataCoreTests/JSONValuePathMutationParityTests.swift",
      swiftTestName: "JSONValuePathMutationParityTests",
      surface: "json-utils",
      status: .adapted,
      notes: "Swift ports Instant's mutative object path helpers onto JSONValue's value semantics, preserving shallow/nested object writes, array insertions, object leaf replacement, and object/array deletion."
    ),
    sqlite(
      id: "sqlite.fetch-subscription.task-cancel",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/FetchSubscriptionTests.swift",
      sourceTestName: "stopSubscriptionWhenTaskCancelled",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "fetchSubscriptionTaskCancelsUnderlyingObservation",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "Swift cancellation tears down the underlying Instant observation."
    ),
    sqlite(
      id: "sqlite.fetch-all.concurrency",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/FetchAllTests.swift",
      sourceTestName: "concurrency",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "fetchAllReloadsAfterConcurrentCreatesAndDeletes",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "Concurrent Instant creates and deletes are reloaded through @FetchAll with deterministic ordering."
    ),
    sqlite(
      id: "sqlite.integration.filtered-reload",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/IntegrationTests.swift",
      sourceTestName: "fetchAll_SQLString / fetch_FetchKeyRequest",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "fetchAllAndFetchReloadFilteredActiveRows",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "@FetchAll and @Fetch both reload the filtered active row set after active/inactive updates."
    ),
    sqlite(
      id: "sqlite.fetch-subscription.explicit-cancel",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/FetchSubscriptionTests.swift",
      sourceTestName: "completeWhenTaskExplicitlyCancelled",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "fetchSubscriptionTaskCompletesWhenSubscriptionExplicitlyCancelled",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "Explicit subscription cancellation completes the lifecycle task without surfacing an error."
    ),
    sqlite(
      id: "sqlite.fetch-subscription.independent-lifetimes",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/FetchSubscriptionTests.swift",
      sourceTestName: "cancellingOneFetchDoesNotCancelAnother",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "cancellingOneFetchSubscriptionDoesNotCancelAnother",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "Independent Instant subscriptions keep separate cancellation tokens."
    ),
    sqlite(
      id: "sqlite.fetch-one.required-empty",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/FetchOneTests.swift",
      sourceTestName: "tableInit / selectStatementInit",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "nonOptionalFetchOnePreservesLastValueWhenQueryIsEmpty",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "A required FetchOne preserves its previous value and records an InstantError when a live query becomes empty."
    ),
    sqlite(
      id: "sqlite.fetch-one.optional-empty",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/FetchOneTests.swift",
      sourceTestName: "optionalTableInit / optionalStatementInit",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "bareOptionalFetchOneDefaultsToEntityQuery",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "Optional FetchOne defaults to the entity query and clears to nil for empty result sets."
    ),
    sqlite(
      id: "sqlite.fetch-one.initializer-defaults",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/FetchOneTests.swift",
      sourceTestName: "nonTableInit / optionalTableInit_WithDefault / fetchOneDelayedAssignment",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "fetchOneInitializersPreserveDefaultsAndDelayedAssignment",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "FetchOne preserves value-only defaults, optional entity defaults, and delayed required wrapper assignment before explicit async loads."
    ),
    sqlite(
      id: "sqlite.fetch-one.scalar-selection",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/FetchOneTests.swift",
      sourceTestName: "statementInit / statementInit_Representable / statementInit_OptionalRepresentable / statementInit_DoubleOptionalRepresentable",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "fetchOneScalarSelectionsPreserveSQLiteDataStatementSemantics",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "FetchOne can load and dynamically replace single selected Instant fields while preserving required not-found and optional nil semantics."
    ),
    sqlite(
      id: "sqlite.fetch-all.decode-failure",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/FetchAllTests.swift",
      sourceTestName: "fetchFailure",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "fetchAllLoadPreservesLastValueAndRecordsDecodeError",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "A malformed Instant query result throws a decode error, records it on FetchAll, and preserves the last successful value."
    ),
    sqlite(
      id: "sqlite.fetch-all.scalar-selection",
      sourceFile: "upstream/sqlite-data/Sources/SQLiteData/FetchAll.swift",
      sourceTestName: "@FetchAll selected value collection",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "fetchAllScalarSelectionsPreserveSQLiteDataSelectionSemantics",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "FetchAll can load, subscribe, and task over selected Instant fields as Swift arrays while preserving optional nil and decode-failure semantics."
    ),
    sqlite(
      id: "sqlite.fetch-wrappers.basic-matrix",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/FetchTests.swift",
      sourceTestName: "bareFetchAll / fetchAllWithQuery / fetchOneCountWithQuery / fetchOneOptional / fetchOneWithDefault / fetchOneOptional_SQL",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "fetchWrappersLoadBasicSQLiteDataMatrix",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "The Instant wrappers cover SQLiteData's basic fetch matrix with typed queries, derived count loading, and explicit async reloads."
    ),
    sqlite(
      id: "sqlite.fetch-all.dynamic-query",
      sourceFile: "upstream/sqlite-data/Examples/CaseStudies/DynamicQuery.swift",
      sourceTestName: "@Fetch projected load dynamic query",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "observableModelLoadsDynamicFetchQueriesThroughWrapperState",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "The Instant adapter updates observable model state through projected wrapper dynamic query loading."
    ),
    sqlite(
      id: "sqlite.fetch-one.dynamic-query",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/FetchOneTests.swift",
      sourceTestName: "selectStatementInit / optionalStatementInit projected load(query)",
      swiftFile: platformAdapterValidationSwiftFile,
      swiftTestName: "platformAdapterValidationProvesWrappersBindLocalRuntime",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "Optional Instant @FetchOne terminal validation swaps non-nil query filters, proves both limit-one plans, and updates the selected entity."
    ),
    sqlite(
      id: "sqlite.fetch-one.nil-query",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/FetchOneTests.swift",
      sourceTestName: "optionalTableInit / optionalStatementInit empty optional state",
      swiftFile: platformAdapterValidationSwiftFile,
      swiftTestName: "platformAdapterValidationProvesWrappersBindLocalRuntime",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "The optional Instant @FetchOne adapter treats a nil dynamic query as a SwiftUI-style disabled binding, clearing cached value, error, and loading state without hitting the client."
    ),
    sqlite(
      id: "sqlite.fetch.transaction-request",
      sourceFile: "upstream/sqlite-data/Examples/CaseStudies/TransactionDemo.swift",
      sourceTestName: "@Fetch(Facts()) composite transaction value",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "fetchKeyRequestLoadsTransactionStyleCompositeValues",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "InstantFetchKeyRequest gives @Fetch a reusable request object for composite values; the load path performs separate rows/count reads and the live task maps row emissions into the same value shape."
    ),
    sqlite(
      id: "sqlite.fetch.request-dynamic-query",
      sourceFile: "upstream/sqlite-data/Examples/CaseStudies/DynamicQuery.swift",
      sourceTestName: "@Fetch projected load dynamic FetchKeyRequest",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "fetchKeyRequestLoadsDynamicRequestsAndRecordsPlans",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "Dynamic InstantFetchKeyRequest values replace the configured @Fetch request, reload composite row/count state, and preserve the expected typed query plans."
    ),
    sqlite(
      id: "sqlite.fetch.request-nil-reset",
      sourceFile: "upstream/sqlite-data/Sources/SQLiteData/Fetch.swift",
      sourceTestName: "@Fetch default wrapped value before projected dynamic request",
      swiftFile: typedAPISwiftFile,
      swiftTestName:
        "fetchKeyRequestLoadNilRequestResetsDefaultValueWithoutCallingClient / fetchKeyRequestSubscribeNilRequestReturnsFinishedSubscriptionWithoutCallingClient / fetchKeyRequestTaskNilRequestDoesNotStartObservationAndClearsLoading",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "A nil InstantFetchKeyRequest disables the dynamic @Fetch request, resets to the wrapper's initial value, clears error/loading state, and does not touch the client."
    ),
    sqlite(
      id: "sqlite.fetch.request-dynamic-cancellation",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/FetchSubscriptionTests.swift",
      sourceTestName: "stopSubscriptionWhenTaskCancelled / cancellingOneFetchDoesNotCancelAnother",
      swiftFile: typedAPISwiftFile,
      swiftTestName:
        "fetchKeyRequestDynamicTaskCancellationStopsStaleEmissions / fetchKeyRequestNilResetCancelsLiveTaskAndIgnoresStaleEmissions",
      surface: "adapter-fetch",
      status: .adapted,
      notes: "Cancelling or nil-resetting a dynamic @Fetch request task terminates its Instant observation; a replacement request receives new values while stale emissions from the cancelled request no longer mutate wrapper state."
    ),
    sqlite(
      id: "sqlite.case-studies.animation-initializers",
      sourceFile: "upstream/sqlite-data/Examples/CaseStudies/Animations.swift",
      sourceTestName: "@FetchAll/@FetchOne/@Fetch animation initializers",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "fetchWrappersAcceptSQLiteDataStyleAnimationInitializers",
      surface: "adapter-swiftui",
      status: .adapted,
      notes: "SwiftUI-only animation initializer overloads preserve SQLiteData case-study call-site ergonomics while reusing the normal Instant load/request paths."
    ),
    sqlite(
      id: "sqlite.case-studies.swiftui-direct-wrappers",
      sourceFile: "upstream/sqlite-data/Examples/CaseStudies/SwiftUIDemo.swift",
      sourceTestName: "@FetchAll/@FetchOne direct view facts list and count",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "fetchWrappersDriveCaseStudiesListCountAndImperativeSnapshots",
      surface: "adapter-swiftui",
      status: .adapted,
      notes: "Direct Instant fetch wrappers load an ordered facts-style list, derived count, and delete/reload state through the same wrapper surface used by SwiftUI views."
    ),
    sqlite(
      id: "sqlite.case-studies.observable-model",
      sourceFile: "upstream/sqlite-data/Examples/CaseStudies/ObservableModelDemo.swift",
      sourceTestName: "@Observable model fetch list/count, write, and delete flow",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "observableModelCaseStudyWritesCountsAndDeletesThroughWrappers",
      surface: "adapter-observation",
      status: .adapted,
      notes: "An Observation-backed model owns Instant fetch wrapper state, writes facts through the injected client, reloads an ordered list plus derived count, and deletes selected rows without raw callbacks."
    ),
    sqlite(
      id: "sqlite.case-studies.uikit-controller",
      sourceFile: "upstream/sqlite-data/Examples/CaseStudies/UIKitDemo.swift",
      sourceTestName: "UIKit controller observes @FetchAll and applies snapshots",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "fetchWrappersDriveCaseStudiesListCountAndImperativeSnapshots",
      surface: "adapter-uikit",
      status: .adapted,
      notes: "Instant fetch wrappers can drive imperative snapshot application for UIKit-style controllers while preserving ordered list and delete/reload behavior."
    ),
    sqlite(
      id: "sqlite.bindings.fetch-wrappers",
      sourceFile: "upstream/sqlite-data/Sources/SQLiteData/FetchAll.swift + upstream/sqlite-data/Sources/SQLiteData/FetchOne.swift + upstream/sqlite-data/Sources/SQLiteData/Fetch.swift",
      sourceTestName: "projectedValue binding",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "projectedFetchWrappersExposeSwiftUIBindings",
      surface: "adapter-bindings",
      status: .adapted,
      notes: "FetchAll, FetchOne, and Fetch expose projected SwiftUI bindings over Instant values."
    ),
    instant(
      id: "instant.react-common.platform-adapter-bindings",
      sourceFile: "upstream/instant/client/packages/react-common/src",
      sourceTestName: "useQuery, useAuth, useId, room, storage, streams, and shares hooks",
      swiftFile: platformAdapterValidationSwiftFile,
      swiftTestName: "platformAdapterValidationProvesWrappersBindLocalRuntime",
      surface: "adapter-bindings",
      status: .adapted,
      notes: "Terminal platform-adapter validation proves projected Swift bindings for FetchAll, FetchOne, Fetch, LocalID, AuthSession, room presence/topic messages, storage, streams, and shares."
    ),
    sqlite(
      id: "sqlite.draft.macro-generation",
      sourceFile: "upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/Articles/AddingToGRDB.md",
      sourceTestName: "@Table generated Draft type",
      swiftFile: "Tests/InstantSwiftDataMacrosTests/InstantEntityMacroTests.swift",
      swiftTestName: "testGeneratedDraft",
      surface: "drafts",
      status: .adapted,
      notes: "@InstantEntity generates an InstantEntityDraft with optional id, defaulted memberwise init, init(_ entity), and writable assignments; unlike SQLiteData TableDrafts, Instant drafts are write values rather than query tables."
    ),
    sqlite(
      id: "sqlite.draft.nil-id-create",
      sourceFile: "upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/Articles/CloudKitSync.md",
      sourceTestName: "Reminder.Draft(title:) omits id for database default",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "generatedDraftSaveCreatesAndEditsEntities",
      surface: "drafts",
      status: .adapted,
      notes: "Nil-id generated drafts create Instant entities with dependency/runtime-generated local ids and return the created typed id."
    ),
    sqlite(
      id: "sqlite.draft.existing-edit",
      sourceFile: "upstream/sqlite-data/Examples/SyncUpTests/SyncUpFormTests.swift",
      sourceTestName: "updateExisting",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "generatedDraftSaveCreatesAndEditsEntities",
      surface: "drafts",
      status: .adapted,
      notes: "Draft(existing) preserves identity and save emits update assignments for edit flows."
    ),
    sqlite(
      id: "sqlite.draft.generated-field-exclusion",
      sourceFile: "upstream/sqlite-data/Tests/SQLiteDataTests/CloudKitTests/UserlandTests.swift",
      sourceTestName: "ModelA.Draft(id:) omits generated isEven column",
      swiftFile: typedAPISwiftFile,
      swiftTestName: "generatedDraftExcludesUndeclaredStoredFieldsFromAssignments",
      surface: "drafts",
      status: .adapted,
      notes: "Manual Instant attributes constrain generated Draft assignments so local or server-managed stored fields stay out of create/edit payloads."
    ),
    sqlite(
      id: "sqlite.reminders.search-tags",
      sourceFile: "upstream/sqlite-data/Examples/RemindersTests/SearchRemindersTests.swift",
      sourceTestName: "basics / showCompleted / deleteCompleted",
      swiftFile: "Tests/InstantSwiftDataTestingTests/LocalTodoValidationTests.swift",
      swiftTestName: "remindersValidationProducesEvidenceAndPersistsLocalSurfaces",
      surface: "examples-reminders",
      status: .adapted,
      notes: "The Instant Reminders validation emits local JSONL evidence for text search, tag filters, completed filtering, and durable reminder-tag links."
    ),
    sqlite(
      id: "sqlite.reminders.detail-rich-fields",
      sourceFile: "upstream/sqlite-data/Examples/RemindersTests/RemindersDetailsTests.swift",
      sourceTestName: "basics / ordering / showCompleted",
      swiftFile: "Tests/InstantSwiftDataCoreTests/CLITests.swift",
      swiftTestName: "cliValidationRemindersEmitsEvidence",
      surface: "examples-reminders",
      status: .adapted,
      notes: "The Instant port proves notes, flagged state, due-date filters, priority filters, completion counts, and rich-field edits through terminal validation."
    ),
    sqlite(
      id: "sqlite.reminders.form-model",
      sourceFile: "upstream/sqlite-data/Examples/Reminders/ReminderForm.swift",
      sourceTestName: "Reminder.Draft create/edit form save, date toggle, and tag replacement",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift + Tests/InstantSwiftDataTestingTests/LocalTodoValidationTests.swift",
      swiftTestName: "reminderFormModelSavesNewDraftWithTags + reminderFormModelEditsExistingDraftAndReplacesTags + remindersValidationProducesEvidenceAndPersistsLocalSurfaces",
      surface: "examples-reminders",
      status: .adapted,
      notes: "The Instant Reminders form model mirrors the SQLiteData edit/create ergonomics with nil-id draft creation, Draft(existing)-style identity preservation, due-date toggling, selected tag de-duplication, full tag-link replacement, and terminal validation through the edit-rich-fields row."
    ),
    sqlite(
      id: "sqlite.reminders.lists-share-stats",
      sourceFile: "upstream/sqlite-data/Examples/RemindersTests/RemindersListsTests.swift",
      sourceTestName: "basics / share",
      swiftFile: "Tests/InstantSwiftDataTestingTests/LocalTodoValidationTests.swift",
      swiftTestName: "remindersValidationProducesEvidenceAndPersistsLocalSurfaces",
      surface: "examples-reminders",
      status: .adapted,
      notes: "Local Instant validation proves list counts, smart-list stats, share role promotion/demotion, reader rejection, writer updates, and relaunch persistence."
    ),
    sqlite(
      id: "sqlite.syncups.form-new",
      sourceFile: "upstream/sqlite-data/Examples/SyncUpTests/SyncUpFormTests.swift",
      sourceTestName: "new sync-up draft save",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "syncUpFormModelSavesNewDraftWithNonBlankAttendees",
      surface: "examples-syncups",
      status: .adapted,
      notes: "SyncUps form draft behavior maps to Instant create/link transaction steps."
    ),
    sqlite(
      id: "sqlite.syncups.form-edit",
      sourceFile: "upstream/sqlite-data/Examples/SyncUpTests/SyncUpFormTests.swift",
      sourceTestName: "existing sync-up draft edit",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "syncUpFormModelUpdatesExistingDraftAndReplacesAttendees",
      surface: "examples-syncups",
      status: .adapted,
      notes: "Existing SyncUps drafts preserve identity and update attendees through Instant mutations."
    ),
    sqlite(
      id: "sqlite.syncups.record-meeting",
      sourceFile: "upstream/sqlite-data/Examples/SyncUps/RecordMeeting.swift",
      sourceTestName: "RecordMeetingModel task, timer, speaker advancement, and transcript save",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "syncUpRecordingModelUsesSpeechSoundAndSavesTranscript",
      surface: "examples-syncups",
      status: .adapted,
      notes: "The Instant port keeps the recording model deterministic for CLI proof while preserving speech, sound, speaker advancement, and meeting-save behavior."
    ),
    sqlite(
      id: "sqlite.syncups.record-settings",
      sourceFile: "upstream/sqlite-data/Examples/SyncUps/SyncUpDetail.swift",
      sourceTestName: "speech denied alert opens settings",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "syncUpRecordingModelDeniedSpeechOpensSettings",
      surface: "examples-syncups",
      status: .adapted,
      notes: "The Instant port exposes the denied-speech/settings branch through a Sendable open-settings dependency client."
    ),
    sqlite(
      id: "sqlite.syncups.record-dependencies",
      sourceFile: "upstream/sqlite-data/Examples/SyncUps/Dependencies",
      sourceTestName: "SpeechClient, SoundEffectClient, and OpenSettings dependencies",
      swiftFile: "Tests/InstantSwiftDataTests/BootstrapTests.swift",
      swiftTestName: "syncUpRecordingDependenciesCanBeOverridden",
      surface: "dependencies",
      status: .adapted,
      notes: "The SyncUps speech, sound, and settings seams are Sendable value clients with local static instances and DependencyValues overrides."
    ),
    instant(
      id: "instant.live-transport.swift-to-typescript",
      sourceFile: "upstream/instant/client/packages/core/__tests__",
      sourceTestName: "real server Swift write observed by TypeScript",
      swiftFile: "validation/run-e2e.sh",
      swiftTestName: "Swift/TypeScript real-run validation",
      surface: "live-transport",
      status: .blocked,
      notes: "Local validation exists, but real WebSocket/server-backed Swift-to-TypeScript observation remains future transport work."
    ),
    instant(
      id: "instant.live-transport.typescript-to-swift",
      sourceFile: "upstream/instant/client/packages/core/__tests__",
      sourceTestName: "real server TypeScript write observed by Swift",
      swiftFile: "validation/run-e2e.sh",
      swiftTestName: "Swift/TypeScript real-run validation",
      surface: "live-transport",
      status: .blocked,
      notes: "The TypeScript fixture runner is present, but Swift live subscription against a real Instant app remains incomplete."
    ),
    instant(
      id: "instant.recipe.auth.local-cli",
      sourceFile: "upstream/instant/client/www/lib/recipes/auth.tsx",
      sourceTestName: "magic-code auth SignedOut/Login and SignedIn/Dashboard flow",
      swiftFile: "Tests/InstantSwiftDataCoreTests/CLITests.swift",
      swiftTestName: "cliAuthRecipeSendsVerifiesWatchesAndSignsOutAcrossLaunches",
      surface: "recipes-auth",
      status: .adapted,
      notes: "The Instant CLI ports the Auth recipe into a durable magic-code terminal flow with send-code, verify-code, status/dashboard, watch, and sign-out commands. send-code output represents the upstream code-entry form state; status reports persisted auth state. Local magic-code sessions derive the dashboard email from email-prefixed user ids because InstantAuthSession stores userID rather than a user.email field."
    ),
    instant(
      id: "instant.website.app-builder.local-cli",
      sourceFile: "upstream/instant/client/www/_examples/app-builder.md + Galaxies-dev/app-builder@e67200cc70e01d88bd9a5382cf0380f4882fb8c7",
      sourceTestName: "magic-code protected app generation, platform app creation, owner-linked builds, stream updates, list/detail",
      swiftFile: "Tests/InstantSwiftDataCoreTests/CLITests.swift + Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "cliAppBuilderGeneratesListsUpdatesAndResetsBuildsAcrossLaunches + appBuilderExampleCreatesUpdatesAndQueriesOwnerBuilds",
      surface: "examples-app-builder",
      status: .adapted,
      notes: "The Instant CLI ports the app-builder source into local $users/$files/builds namespaces, email-backed magic-code auth, injectable local platform-app and code-generator clients, owner-filtered build lists, id-only build detail lookup, stream-like code/reasoning updates, previewable finish state, append/edit ergonomics, and reset. The current local port records $files schema and platform metadata but does not upload generated files."
    ),
    instant(
      id: "instant.website.chat.local-cli",
      sourceFile: "upstream/instant/client/www/_examples/chat.md",
      sourceTestName: "IRC-style chat guest login, channels, messages, seed/reset tooling",
      swiftFile: "Tests/InstantSwiftDataCoreTests/CLITests.swift",
      swiftTestName: "cliChatExampleSeedsPostsAndResetsAcrossLaunches",
      surface: "examples-chat",
      status: .adapted,
      notes: "The Instant CLI ports the website chat example into local channel/message refs, deterministic seed/reset tooling, guest auto-login for posts, and logged-in author attribution."
    ),
    instant(
      id: "instant.website.microblog.local-cli",
      sourceFile: "upstream/instant/client/www/_examples/microblog.md",
      sourceTestName: "$users/profiles/posts/likes feed, auth profile, likes, and cascade seed/reset",
      swiftFile: "Tests/InstantSwiftDataCoreTests/CLITests.swift",
      swiftTestName: "cliMicroblogExampleSeedsAuthPostsLikesAndCascadesAcrossLaunches",
      surface: "examples-microblog",
      status: .adapted,
      notes: "The Instant CLI ports the website microblog into local $users/profile/post/like refs, deterministic seed/reset tooling, auth-gated profile setup, post/like/unlike flows, and cascade delete proof."
    ),
    instant(
      id: "instant.website.mobile-chat.local-cli",
      sourceFile: "upstream/instant/client/www/_examples/mobile-chat.md",
      sourceTestName: "React Native auth, channels, profile-linked messages, and chat presence",
      swiftFile: "Tests/InstantSwiftDataCoreTests/CLITests.swift",
      swiftTestName: "cliMobileChatExampleSeedsAuthPresenceAndResetsAcrossLaunches",
      surface: "examples-mobile-chat",
      status: .adapted,
      notes: "The Instant CLI ports betomoedano/instant-realtime-chat at a844b48eacd2669316667cab5ffb8f5548948cf6 into isolated local channel/profile/message namespaces, preserving $users auth, channel.id-filtered message queries with nested author.user includes, optional profile authors, room presence, and explicit local seed/reset tooling."
    ),
    instant(
      id: "instant.website.stroopwafel.local-cli",
      sourceFile: "upstream/instant/client/www/_examples/stroopwafel.md + jsventures/stroopwafel@7f5e2379464d932c0e4681655cbf022f8d9c2614",
      sourceTestName: "$users, rooms, games, points, host/member room flow, ready/kick/start/tap/reset",
      swiftFile: "Tests/InstantSwiftDataCoreTests/CLITests.swift + Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "cliStroopwafelExampleRunsTwoUserRoomAndGameAcrossLaunches + stroopwafelRoomGameScoringAndSoftDeleteFlow",
      surface: "examples-stroopwafel",
      status: .adapted,
      notes: "The Instant CLI ports the Stroopwafel multiplayer source into local $users/rooms/games/points namespaces, auth-gated profile setup, code-based room join, ready membership, host-only start rejection, per-player points, JSONL game evidence, and reset. Core operation coverage proves kick, game completion, host leave as a soft-delete, and game-to-point cascade semantics. The current source declares rooms: {} and uses durable room users rather than typed presence/topics."
    ),
    instant(
      id: "instant.recipe.reactions.local-cli",
      sourceFile: "upstream/instant/client/www/lib/recipes/reactions.tsx",
      sourceTestName: "topics-example/123 emoji topic reactions",
      swiftFile: "Tests/InstantSwiftDataCoreTests/CLITests.swift + Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "cliReactionsRecipePublishesAndWatchesTopicMessagesAcrossLaunches + reactionsRecipePayloadsDecodeTopicMessages",
      surface: "recipes-reactions",
      status: .adapted,
      notes: "The Instant CLI ports the Reactions recipe onto the local room-topic runtime with the same topics-example/123 room, emoji topic, four reaction names, and {name, directionAngle, rotationAngle} payload. Local topic history is durable and listable for terminal evidence, while unknown recipe payload names are ignored during decoding like the upstream topic effect."
    ),
    instant(
      id: "instant.recipe.typing-indicator.local-cli",
      sourceFile: "upstream/instant/client/www/lib/recipes/typing-indicator.tsx + upstream/instant/client/packages/react-common/src/InstantReactRoom.ts",
      sourceTestName: "typing-indicator-example/1234 presence id and chat-input active peers",
      swiftFile: "Tests/InstantSwiftDataCoreTests/CLITests.swift + Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "cliTypingIndicatorRecipePersistsActivePresenceAcrossLaunches + typingIndicatorRecipeDerivesActivePresenceMembers",
      surface: "recipes-typing-indicator",
      status: .adapted,
      notes: "The Instant CLI ports the Typing Indicator recipe onto the local room-presence runtime with the same typing-indicator-example/1234 room, optional id presence field, chat-input activity field, and active-peer derivation. Local presence is durable and watchable for terminal evidence, and --viewer-user-id exposes the upstream hook's peer-only view while false, null, and unrelated-room values stay idle or ignored."
    ),
    instant(
      id: "instant.recipe.avatar-stack.local-cli",
      sourceFile: "upstream/instant/client/www/lib/recipes/avatar-stack.tsx",
      sourceTestName: "avatars-example/avatars-example-1234 presence name stack",
      swiftFile: "Tests/InstantSwiftDataCoreTests/CLITests.swift + Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "cliAvatarStackRecipePersistsPresenceAcrossLaunches + avatarStackRecipeBuildsViewerAndPeerSnapshot",
      surface: "recipes-avatar-stack",
      status: .adapted,
      notes: "The Instant CLI ports the Avatar Stack recipe onto the local room-presence runtime with the same avatars-example/avatars-example-1234 room and name presence field. Local presence is durable and watchable for terminal evidence, default names use the upstream user-id prefix behavior, and --viewer-user-id exposes the upstream hook's current-user plus peers view."
    ),
    instant(
      id: "instant.recipe.cursors.local-cli",
      sourceFile: "upstream/instant/client/www/lib/recipes/cursors.tsx + upstream/instant/client/packages/react/src/Cursors.tsx",
      sourceTestName: "cursors-example/123 cursor-space peer cursors",
      swiftFile: "Tests/InstantSwiftDataCoreTests/CLITests.swift + Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "cliCursorsRecipesPersistPresenceAcrossLaunches + cursorsRecipeBuildsPeerVisibleSnapshots",
      surface: "recipes-cursors",
      status: .adapted,
      notes: "The Instant CLI ports the Cursors recipe onto the local room-presence runtime with the same cursors-example/123 room, default cursor-space key, and {x, y, xPercent, yPercent, color} cursor payload. Local presence is durable and watchable for terminal evidence, clear removes the cursor payload like the upstream mouse/touch end handlers, and --viewer-user-id exposes the upstream peer-only rendering."
    ),
    instant(
      id: "instant.recipe.custom-cursors.local-cli",
      sourceFile: "upstream/instant/client/www/lib/recipes/custom-cursors.tsx + upstream/instant/client/packages/react/src/Cursors.tsx",
      sourceTestName: "cursors-example/124 custom cursor name presence",
      swiftFile: "Tests/InstantSwiftDataCoreTests/CLITests.swift + Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "cliCursorsRecipesPersistPresenceAcrossLaunches + cursorsRecipeBuildsPeerVisibleSnapshots",
      surface: "recipes-custom-cursors",
      status: .adapted,
      notes: "The Instant CLI ports the Custom Cursors recipe onto the local room-presence runtime with the same cursors-example/124 room, default cursor-space key, cursor payload, and name presence field used by the custom avatar renderer. Local move/list/watch/clear/leave commands preserve the peer-only cursor view while keeping terminal evidence durable."
    ),
    instant(
      id: "instant.recipe.merge-tile-game.local-cli",
      sourceFile: "upstream/instant/client/www/lib/recipes/merge-tile-game.tsx",
      sourceTestName: "boards/83c059e2-ed47-42e5-bdd9-6de88d26c521 merge tile game",
      swiftFile: "Tests/InstantSwiftDataCoreTests/CLITests.swift + Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "cliMergeTileGameUsesMergeAndPresenceAcrossLaunches + mergeTileGameRecipeUsesMergeForIndependentTileTaps",
      surface: "recipes-merge-tile-game",
      status: .adapted,
      notes: "The Instant CLI ports the Merge Tile Game recipe with the upstream fixed board id, 4x4 empty board, color palette, tile-game-example/_defaultRoomId presence room, and color presence field. Local board/reset commands replace the full state like update({state: makeEmptyBoard()}), while tap uses a single-cell deep merge so independent tile colors survive across terminal invocations. Omitted colors choose the first available palette color for deterministic terminal evidence instead of the browser recipe's random available-color selection."
    ),
    sqlite(
      id: "sqlite.cloudkit-demo.local-counter-share",
      sourceFile: "upstream/sqlite-data/Examples/CloudKitDemo/CountersListFeature.swift",
      sourceTestName: "Counter rows, count mutations, and visible shared state",
      swiftFile: "Tests/InstantSwiftDataCoreTests/CLITests.swift",
      swiftTestName: "cliCountersCloudKitDemoShareMetadataAndRolesPersistAcrossLaunches",
      surface: "examples-cloudkit-demo",
      status: .adapted,
      notes: "The Instant CLI ports the CloudKitDemo counter shape with add/increment/decrement/delete commands, local share metadata, accepted participants, and reader/writer role proof."
    ),
    sqlite(
      id: "sqlite.cloudkit-demo.remote-share",
      sourceFile: "upstream/sqlite-data/Examples/CloudKitDemo",
      sourceTestName: "CloudKit shared records and participants",
      swiftFile: "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift",
      swiftTestName: "Instant share model local coverage",
      surface: "sharing",
      status: .blocked,
      notes: "Local Instant share entities and the counter demo surface are covered; remote permission rejection and transport-backed CloudKitDemo-equivalent app proof remain future work."
    ),
  ]

  private static func instant(
    id: String,
    sourceFile: String,
    sourceTestName: String,
    swiftFile: String,
    swiftTestName: String,
    surface: String,
    status: InstantParityCoverageStatus,
    notes: String
  ) -> InstantParityCoverageRecord {
    InstantParityCoverageRecord(
      id: id,
      sourceKind: .instantTypeScript,
      sourceFile: sourceFile,
      sourceTestName: sourceTestName,
      swiftFile: swiftFile,
      swiftTestName: swiftTestName,
      surface: surface,
      status: status,
      notes: notes
    )
  }

  private static func sqlite(
    id: String,
    sourceFile: String,
    sourceTestName: String,
    swiftFile: String,
    swiftTestName: String,
    surface: String,
    status: InstantParityCoverageStatus,
    notes: String
  ) -> InstantParityCoverageRecord {
    InstantParityCoverageRecord(
      id: id,
      sourceKind: .sqliteData,
      sourceFile: sourceFile,
      sourceTestName: sourceTestName,
      swiftFile: swiftFile,
      swiftTestName: swiftTestName,
      surface: surface,
      status: status,
      notes: notes
    )
  }

  private static let storeSource =
    "upstream/instant/client/packages/core/__tests__/src/store.test.ts"
  private static let instaQLSource =
    "upstream/instant/client/packages/core/__tests__/src/instaql.test.ts"
  private static let instamlSource =
    "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts"
  private static let datalogSource =
    "upstream/instant/client/packages/core/__tests__/src/datalog.test.ts"
  private static let queryValidationSource =
    "upstream/instant/client/packages/core/__tests__/src/queryValidation.test.ts"
  private static let transactionValidationSource =
    "upstream/instant/client/packages/core/__tests__/src/transactionValidation.test.ts"
  private static let weakHashSource =
    "upstream/instant/client/packages/core/__tests__/src/utils/weakHash.test.ts"
  private static let weakHashLegacySource =
    "upstream/instant/client/packages/core/__tests__/src/utils/weakHashLegacy.test.ts"
  private static let persistedObjectSource =
    "upstream/instant/client/packages/core/__tests__/src/utils/PersistedObject.test.ts"
  private static let schemaSource =
    "upstream/instant/client/packages/core/__tests__/src/schema.test.ts"
  private static let serializeSchemaSource =
    "upstream/instant/client/packages/core/__tests__/src/serializeSchema.test.ts"
  private static let objectUtilsSource =
    "upstream/instant/client/packages/core/__tests__/src/utils/object.test.ts"
  private static let storeParitySwiftFile =
    "Tests/InstantSwiftDataCoreTests/InstantStoreParityTests.swift"
  private static let queryExecutionSwiftFile =
    "Tests/InstantSwiftDataCoreTests/InstantQueryExecutionParityTests.swift"
  private static let queryValidationSwiftFile =
    "Tests/InstantSwiftDataCoreTests/InstantQueryValidationParityTests.swift"
  private static let transactionValidationSwiftFile =
    "Tests/InstantSwiftDataCoreTests/InstantTransactionValidationParityTests.swift"
  private static let schemaPrinterSwiftFile =
    "Tests/InstantSwiftDataSchemaTests/TypeScriptPrinterTests.swift"
  private static let typedAPISwiftFile =
    "Tests/InstantSwiftDataTests/TypedAPITests.swift"
  private static let platformAdapterValidationSwiftFile =
    "Tests/InstantSwiftDataTests/BootstrapTests.swift"
}

extension Sequence where Element: Comparable & Hashable {
  fileprivate func uniquedSorted() -> [Element] {
    Array(Set(self)).sorted()
  }
}
