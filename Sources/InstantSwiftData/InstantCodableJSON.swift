import Foundation
import InstantSwiftDataCore

// MARK: - SQLiteData-shaped Codable JSON for Instant attributes
//
// Prior art (pointfree/swift-structured-queries):
//
//   @Column(as: [String].JSONRepresentation.self)
//   var notes: [String]
//
// Instant maps the same idea onto InstantValue (.json or JSON text in .string)
// with **loud** encode/decode failures (throws InstantError), never silent try?.

/// Shared Codable ↔ `JSONValue` bridge used by Instant attribute representations
/// and room presence/topic payloads.
public enum InstantCodableJSON {
  public static func encode<Value: Encodable>(
    _ value: Value,
    operation: String = "encode Instant Codable JSON"
  ) throws -> JSONValue {
    let data: Data
    do {
      data = try JSONEncoder().encode(value)
    } catch {
      throw InstantError(
        code: .validationFailed,
        operation: operation,
        message: "JSONEncoder failed for \(Value.self): \(error.localizedDescription)",
        recovery: "Fix the Encodable implementation or attribute type."
      )
    }
    let object: Any
    do {
      object = try JSONSerialization.jsonObject(
        with: data,
        options: [.fragmentsAllowed]
      )
    } catch {
      throw InstantError(
        code: .validationFailed,
        operation: operation,
        message: "JSONSerialization failed for \(Value.self): \(error.localizedDescription)",
        recovery: "Ensure the encoded value is valid JSON."
      )
    }
    return try jsonValue(from: object, operation: operation)
  }

  public static func decode<Value: Decodable>(
    _ type: Value.Type,
    from value: JSONValue,
    operation: String = "decode Instant Codable JSON",
    namespace: String? = nil,
    path: String? = nil,
    localID: String? = nil
  ) throws -> Value {
    // Bridge through Foundation NS types so JSONSerialization accepts numbers/bools.
    let foundationObject = foundationValue(from: value)
    let data: Data
    do {
      data = try JSONSerialization.data(
        withJSONObject: foundationObject,
        options: [.fragmentsAllowed]
      )
    } catch {
      throw InstantError(
        code: .decodeFailed,
        operation: operation,
        namespace: namespace,
        path: path,
        localID: localID,
        message: "Could not re-serialize Instant JSON for \(Value.self): \(error.localizedDescription)",
        recovery: "Check the Instant entity schema and server value for '\(namespace ?? "?").\(path ?? "?")'."
      )
    }
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw InstantError(
        code: .decodeFailed,
        operation: operation,
        namespace: namespace,
        path: path,
        localID: localID,
        message: "JSONDecoder failed for \(Value.self): \(error.localizedDescription)",
        recovery: "Check the Instant entity schema and server value for '\(namespace ?? "?").\(path ?? "?")'."
      )
    }
  }

  /// Decode from either Instant `.json` or a JSON-text `.string` (Scribe-style columns).
  public static func decodeFlexible<Value: Decodable>(
    _ type: Value.Type,
    from value: InstantValue?,
    operation: String = "decode Instant Codable JSON",
    namespace: String? = nil,
    path: String? = nil,
    localID: String? = nil
  ) throws -> Value {
    guard let value, value != .null else {
      throw InstantError(
        code: .decodeFailed,
        operation: operation,
        namespace: namespace,
        path: path,
        localID: localID,
        message: "Expected JSON for '\(path ?? "?")' but value was missing or null.",
        recovery: "Provide a JSON payload or use Optional JSONRepresentation."
      )
    }
    switch value {
    case let .json(json):
      return try decode(
        type,
        from: json,
        operation: operation,
        namespace: namespace,
        path: path,
        localID: localID
      )
    case let .string(text):
      guard let data = text.data(using: .utf8) else {
        throw InstantError(
          code: .decodeFailed,
          operation: operation,
          namespace: namespace,
          path: path,
          localID: localID,
          message: "JSON text for '\(path ?? "?")' is not valid UTF-8.",
          recovery: "Write JSON with UTF-8 encoding."
        )
      }
      do {
        return try JSONDecoder().decode(type, from: data)
      } catch {
        throw InstantError(
          code: .decodeFailed,
          operation: operation,
          namespace: namespace,
          path: path,
          localID: localID,
          message: "JSONDecoder failed for string-column JSON \(Value.self): \(error.localizedDescription)",
          recovery: "Check the Instant entity schema and server value for '\(namespace ?? "?").\(path ?? "?")'."
        )
      }
    default:
      throw InstantError(
        code: .decodeFailed,
        operation: operation,
        namespace: namespace,
        path: path,
        localID: localID,
        message: "Expected json or JSON string for '\(path ?? "?")', got \(value).",
        recovery: "Check the Instant entity schema and server value for '\(namespace ?? "?").\(path ?? "?")'."
      )
    }
  }

  private static func jsonValue(from value: Any, operation: String) throws -> JSONValue {
    // Important: do **not** match `as Bool` before NSNumber — Swift bridges
    // NSNumber(1)/NSNumber(0) to Bool and would corrupt numeric JSON fields
    // (e.g. word start/end times become true/false).
    switch value {
    case is NSNull:
      return .null
    case let value as String:
      return .string(value)
    case let value as NSNumber:
      // JSON true/false are CFBoolean; numeric values are CFNumber.
      if CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() {
        return .bool(value.boolValue)
      }
      return .number(value.doubleValue)
    case let value as [Any]:
      return .array(try value.map { try jsonValue(from: $0, operation: operation) })
    case let value as [String: Any]:
      return .object(
        try value.mapValues { try jsonValue(from: $0, operation: operation) }
      )
    default:
      throw InstantError(
        code: .validationFailed,
        operation: operation,
        message: "Unsupported JSON value \(String(describing: value)).",
        recovery: "Use Codable values supported by JSONEncoder."
      )
    }
  }

  private static func foundationValue(from value: JSONValue) -> Any {
    switch value {
    case .null:
      return NSNull()
    case let .bool(value):
      return NSNumber(value: value)
    case let .number(value):
      return NSNumber(value: value)
    case let .string(value):
      return value as NSString
    case let .array(values):
      return values.map { foundationValue(from: $0) } as NSArray
    case let .object(values):
      let mapped = values.mapValues { foundationValue(from: $0) }
      return mapped as NSDictionary
    }
  }
}

// MARK: - JSONRepresentation (native Instant .json wire)

/// Codable value stored as Instant `.json`, mirroring SQLiteData
/// `Type.JSONRepresentation` / structured-queries `_CodableJSONRepresentation`.
///
/// ```swift
/// struct Segment: InstantEntityModel {
///   static let words = InstantAttributePath<Self, [Word].JSONRepresentation>("words")
/// }
///
/// try Segment.update(
///   id: id,
///   Segment.words.set(try [Word].JSONRepresentation(queryOutput: words))
/// )
/// // or:
/// try Segment.update(id: id, Segment.words.setJSON(words))
/// ```
public struct InstantCodableJSONRepresentation<
  QueryOutput: Codable & Sendable
>: InstantJSONWireValue, Sendable {
  public var queryOutput: QueryOutput
  private let preencoded: InstantValue

  public init(queryOutput: QueryOutput) throws {
    self.queryOutput = queryOutput
    let json = try InstantCodableJSON.encode(
      queryOutput,
      operation: "encode \(QueryOutput.self) Instant JSONRepresentation"
    )
    self.preencoded = .json(json)
  }

  public var instantValue: InstantValue { preencoded }

  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    let decoded = try InstantCodableJSON.decodeFlexible(
      QueryOutput.self,
      from: value,
      operation: operation,
      namespace: namespace,
      path: path,
      localID: localID
    )
    return try Self(queryOutput: decoded)
  }
}

extension InstantCodableJSONRepresentation: Equatable where QueryOutput: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.queryOutput == rhs.queryOutput
  }
}

extension InstantCodableJSONRepresentation: Hashable where QueryOutput: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(queryOutput)
  }
}

// MARK: - JSONStringRepresentation (JSON text in Instant .string — Scribe wordsJSON today)

/// Codable value stored as Instant **string** of JSON text (SQLite text / Scribe
/// `wordsJSON: String` shape). Decode also accepts native `.json` for flexibility.
public struct InstantCodableJSONStringRepresentation<
  QueryOutput: Codable & Sendable
>: InstantStringWireValue, Sendable {
  public var queryOutput: QueryOutput
  private let preencoded: InstantValue

  public init(queryOutput: QueryOutput) throws {
    self.queryOutput = queryOutput
    let data: Data
    do {
      data = try JSONEncoder().encode(queryOutput)
    } catch {
      throw InstantError(
        code: .validationFailed,
        operation: "encode \(QueryOutput.self) Instant JSONStringRepresentation",
        message: "JSONEncoder failed: \(error.localizedDescription)",
        recovery: "Fix the Encodable implementation or attribute type."
      )
    }
    guard let text = String(data: data, encoding: .utf8) else {
      throw InstantError(
        code: .validationFailed,
        operation: "encode \(QueryOutput.self) Instant JSONStringRepresentation",
        message: "JSONEncoder produced non-UTF-8 data.",
        recovery: "Use UTF-8 encodable values."
      )
    }
    self.preencoded = .string(text)
  }

  public var instantValue: InstantValue { preencoded }

  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    let decoded = try InstantCodableJSON.decodeFlexible(
      QueryOutput.self,
      from: value,
      operation: operation,
      namespace: namespace,
      path: path,
      localID: localID
    )
    return try Self(queryOutput: decoded)
  }
}

extension InstantCodableJSONStringRepresentation: Equatable where QueryOutput: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.queryOutput == rhs.queryOutput
  }
}

extension InstantCodableJSONStringRepresentation: Hashable where QueryOutput: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(queryOutput)
  }
}

// MARK: - Typealiases (SQLiteData spelling)

extension Decodable where Self: Encodable {
  /// Instant `.json` wire — same name as structured-queries / SQLiteData.
  public typealias JSONRepresentation = InstantCodableJSONRepresentation<Self>

  /// Instant `.string` holding JSON text (legacy Instant string columns).
  public typealias JSONStringRepresentation = InstantCodableJSONStringRepresentation<Self>
}

// MARK: - Attribute path convenience

extension InstantAttributePath {
  /// Encode `value` as Instant JSONRepresentation and assign.
  public func setJSON<T: Codable & Sendable>(
    _ value: T
  ) throws -> InstantAttributeAssignment<Entity>
  where Value == InstantCodableJSONRepresentation<T> {
    set(try InstantCodableJSONRepresentation(queryOutput: value))
  }

  /// Encode `value` as JSON text string and assign.
  public func setJSONString<T: Codable & Sendable>(
    _ value: T
  ) throws -> InstantAttributeAssignment<Entity>
  where Value == InstantCodableJSONStringRepresentation<T> {
    set(try InstantCodableJSONStringRepresentation(queryOutput: value))
  }
}

extension InstantEntitySnapshot {
  /// Decode a typed Codable JSON attribute (accepts `.json` or JSON `.string`).
  public func codableJSON<Entity, T: Codable & Sendable>(
    _ attribute: InstantAttributePath<Entity, InstantCodableJSONRepresentation<T>>,
    operation: String = "decode Instant Codable JSON attribute"
  ) throws -> T {
    try InstantCodableJSON.decodeFlexible(
      T.self,
      from: values[attribute.name]?.first,
      operation: operation,
      namespace: namespace,
      path: attribute.name,
      localID: id
    )
  }

  /// Decode a typed Codable JSON-string attribute (Scribe-style).
  public func codableJSONString<Entity, T: Codable & Sendable>(
    _ attribute: InstantAttributePath<Entity, InstantCodableJSONStringRepresentation<T>>,
    operation: String = "decode Instant Codable JSON string attribute"
  ) throws -> T {
    try InstantCodableJSON.decodeFlexible(
      T.self,
      from: values[attribute.name]?.first,
      operation: operation,
      namespace: namespace,
      path: attribute.name,
      localID: id
    )
  }
}
