import Foundation

enum InstantLiveQueryEncoder {
  static func encode(_ plan: InstantQueryPlan) throws -> InstantLiveJSONValue {
    .object([
      plan.namespace: try namespaceValue(
        namespace: plan.namespace,
        filters: plan.filters,
        order: plan.order,
        offset: plan.offset,
        limit: plan.limit,
        first: plan.first,
        after: plan.after,
        last: plan.last,
        before: plan.before,
        selectedFields: plan.selectedFields,
        includes: plan.includes ?? []
      )
    ])
  }

  static func registrationKey(for query: InstantLiveJSONValue) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(query), as: UTF8.self)
  }

  private static func namespaceValue(
    namespace: String,
    filters: [InstantQueryFilter],
    order: InstantQueryOrder?,
    offset: Int?,
    limit: Int?,
    first: Int?,
    after: InstantQueryCursor?,
    last: Int?,
    before: InstantQueryCursor?,
    selectedFields: [String]?,
    includes: [InstantQueryInclude]
  ) throws -> InstantLiveJSONValue {
    var value: [String: InstantLiveJSONValue] = [:]
    let options = try options(
      namespace: namespace,
      filters: filters,
      order: order,
      offset: offset,
      limit: limit,
      first: first,
      after: after,
      last: last,
      before: before,
      selectedFields: selectedFields
    )
    if !options.isEmpty {
      value["$"] = .object(options)
    }

    for include in includes {
      guard include.name != "$", value[include.name] == nil else {
        throw validationError(
          namespace: namespace,
          path: "includes.\(include.name)",
          message: "Live query relation names must be unique and cannot be '$'."
        )
      }
      if let query = include.query {
        // Nested limit/first/last go on the wire when present (InstaQL $ options).
        // Nested offset/cursors stay omitted — not supported on includes (ADR 0015).
        value[include.name] = try namespaceValue(
          namespace: query.namespace,
          filters: query.filters,
          order: query.order,
          offset: nil,
          limit: query.limit,
          first: query.first,
          after: nil,
          last: query.last,
          before: nil,
          selectedFields: query.selectedFields,
          includes: query.includes ?? []
        )
      } else {
        value[include.name] = .object([:])
      }
    }
    return .object(value)
  }

  private static func options(
    namespace: String,
    filters: [InstantQueryFilter],
    order: InstantQueryOrder?,
    offset: Int?,
    limit: Int?,
    first: Int?,
    after: InstantQueryCursor?,
    last: Int?,
    before: InstantQueryCursor?,
    selectedFields: [String]?
  ) throws -> [String: InstantLiveJSONValue] {
    var options: [String: InstantLiveJSONValue] = [:]
    if !filters.isEmpty {
      options["where"] = try whereValue(filters, namespace: namespace)
    }
    if let order {
      options["order"] = .object([
        order.field: .string(order.direction == .ascending ? "asc" : "desc")
      ])
    }
    if let offset {
      options["offset"] = .number(Double(offset))
    }
    if let limit {
      options["limit"] = .number(Double(limit))
    }
    if let first {
      options["first"] = .number(Double(first))
    }
    if let after {
      guard let liveTuple = after.liveTuple else {
        throw opaqueCursorValidationError(namespace: namespace, path: "after")
      }
      options["after"] = .array(liveTuple)
      if after.inclusive {
        options["afterInclusive"] = .bool(true)
      }
    }
    if let last {
      options["last"] = .number(Double(last))
    }
    if let before {
      guard let liveTuple = before.liveTuple else {
        throw opaqueCursorValidationError(namespace: namespace, path: "before")
      }
      options["before"] = .array(liveTuple)
      if before.inclusive {
        options["beforeInclusive"] = .bool(true)
      }
    }
    if let selectedFields {
      options["fields"] = .array(selectedFields.map(InstantLiveJSONValue.string))
    }
    return options
  }

  private static func opaqueCursorValidationError(
    namespace: String,
    path: String
  ) -> InstantError {
    validationError(
      namespace: namespace,
      path: path,
      message:
        "Canonical Instant cursors are opaque four-element tuples and cannot be reconstructed "
        + "from InstantQueryCursor. Preserve the server cursor before running this query live."
    )
  }

  private static func whereValue(
    _ filters: [InstantQueryFilter],
    namespace: String
  ) throws -> InstantLiveJSONValue {
    if filters.count == 1, let filter = filters.first {
      return try whereValue(filter, namespace: namespace)
    }
    return .object([
      "and": .array(try filters.map { try whereValue($0, namespace: namespace) })
    ])
  }

  private static func whereValue(
    _ filter: InstantQueryFilter,
    namespace: String
  ) throws -> InstantLiveJSONValue {
    switch filter {
    case let .equals(field, value):
      return .object([field: try encodeValue(value, namespace: namespace, path: field)])
    case let .notEquals(field, value):
      return try comparison("$ne", field: field, value: value, namespace: namespace)
    case let .greaterThan(field, value):
      return try comparison("$gt", field: field, value: value, namespace: namespace)
    case let .greaterThanOrEqual(field, value):
      return try comparison("$gte", field: field, value: value, namespace: namespace)
    case let .lessThan(field, value):
      return try comparison("$lt", field: field, value: value, namespace: namespace)
    case let .lessThanOrEqual(field, value):
      return try comparison("$lte", field: field, value: value, namespace: namespace)
    case let .in(field, values):
      return .object([
        field: .object([
          "$in": .array(
            try values.enumerated().map { index, value in
              try encodeValue(value, namespace: namespace, path: "\(field).$in[\(index)]")
            }
          )
        ])
      ])
    case let .like(field, pattern):
      return .object([field: .object(["$like": .string(pattern)])])
    case let .iLike(field, pattern):
      return .object([field: .object(["$ilike": .string(pattern)])])
    case let .isNull(field):
      return .object([field: .object(["$isNull": .bool(true)])])
    case let .isNotNull(field):
      return .object([field: .object(["$isNull": .bool(false)])])
    case let .and(filters):
      return .object([
        "and": .array(try filters.map { try whereValue($0, namespace: namespace) })
      ])
    case let .or(filters):
      return .object([
        "or": .array(try filters.map { try whereValue($0, namespace: namespace) })
      ])
    }
  }

  private static func comparison(
    _ operation: String,
    field: String,
    value: InstantValue,
    namespace: String
  ) throws -> InstantLiveJSONValue {
    .object([
      field: .object([
        operation: try encodeValue(value, namespace: namespace, path: "\(field).\(operation)")
      ])
    ])
  }

  private static func encodeValue(
    _ value: InstantValue,
    namespace: String,
    path: String
  ) throws -> InstantLiveJSONValue {
    switch value {
    case .null:
      return .null
    case let .string(value), let .ref(value):
      return .string(value)
    case let .number(value):
      guard value.isFinite else {
        throw validationError(
          namespace: namespace,
          path: path,
          message: "Live query numbers must be finite JSON values."
        )
      }
      return .number(value)
    case let .bool(value):
      return .bool(value)
    case let .date(value):
      return .string(iso8601String(from: value))
    case let .json(value):
      return try jsonValue(value, namespace: namespace, path: path)
    case .lookupRef:
      throw validationError(
        namespace: namespace,
        path: path,
        message: "Lookup refs are transaction addresses, not canonical Instant query values."
      )
    }
  }

  private static func jsonValue(
    _ value: JSONValue,
    namespace: String,
    path: String
  ) throws -> InstantLiveJSONValue {
    switch value {
    case .null:
      return .null
    case let .bool(value):
      return .bool(value)
    case let .number(value):
      guard value.isFinite else {
        throw validationError(
          namespace: namespace,
          path: path,
          message: "Live query JSON numbers must be finite."
        )
      }
      return .number(value)
    case let .string(value):
      return .string(value)
    case let .array(values):
      return .array(
        try values.enumerated().map { index, value in
          try jsonValue(value, namespace: namespace, path: "\(path)[\(index)]")
        }
      )
    case let .object(values):
      var object: [String: InstantLiveJSONValue] = [:]
      for key in values.keys.sorted() {
        if let value = values[key] {
          object[key] = try jsonValue(
            value,
            namespace: namespace,
            path: "\(path).\(key)"
          )
        }
      }
      return .object(object)
    }
  }

  private static func iso8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private static func validationError(
    namespace: String,
    path: String,
    message: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "encode Instant live query",
      namespace: namespace,
      path: path,
      message: message,
      recovery: "Use a query value that can be represented exactly by the canonical Instant SDK."
    )
  }
}
