import AuthV3App
import Foundation
import InstantSwiftData
import InstantSwiftDataSchema

public typealias AppBuilderV3User = AuthV3User
public typealias AppBuilderV3AuthProviders = AuthV3Providers

public struct AppBuilderV3BuildError:
  Codable, Equatable, Hashable, InstantJSONWireValue, Sendable
{
  public var from: String
  public var status: Int
  public var message: String

  public init(from: String, status: Int, message: String) {
    self.from = from
    self.status = status
    self.message = message
  }

  public var instantValue: InstantValue {
    .json(
      .object([
        "from": .string(from),
        "status": .number(Double(status)),
        "message": .string(message),
      ])
    )
  }

  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard case let .json(.object(object)) = value,
      case let .string(from) = object["from"],
      case let .number(rawStatus) = object["status"],
      rawStatus.rounded() == rawStatus,
      case let .string(message) = object["message"]
    else {
      throw AppBuilderV3Build.decodeError(
        value: value,
        path: path,
        localID: localID,
        operation: operation,
        expected: "a JSON build error"
      )
    }
    return Self(from: from, status: Int(rawStatus), message: message)
  }
}

public enum AppBuilderV3Schema {
  public static let document = InstantSchemaExamples.appBuilderV3Document
  public static let attributes = document.attributes
}

@InstantEntity("$files")
public struct AppBuilderV3File: Codable, Equatable, Hashable, InstantEntityModel {
  public static let identifier = InstantAttributePath<Self, String>("id")
  public static let path = InstantAttributePath<Self, String>("path")
  public static let url = InstantAttributePath<Self, String>("url")
  public static let instantAttributes = AppBuilderV3Schema.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var path: String
  public var url: String

  public init(id: InstantID<Self>, path: String, url: String) {
    self.id = id
    self.path = path
    self.url = url
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    path = try snapshot.appBuilderV3String("path", operation: "decode App Builder file")
    url = try snapshot.appBuilderV3String("url", operation: "decode App Builder file")
  }

  public static var ordered: InstantQuery<Self> {
    query.order(path)
  }
}

@InstantEntity("builds")
public struct AppBuilderV3Build: Codable, Equatable, Hashable, InstantEntityModel {
  public static let identifier = InstantAttributePath<Self, String>("id")
  public static let instantAppID = InstantAttributePath<Self, String>("instantAppId")
  public static let code = InstantAttributePath<Self, String>("code")
  public static let reasoning = InstantAttributePath<Self, String?>("reasoning")
  public static let slug = InstantAttributePath<Self, String?>("slug")
  public static let error = InstantAttributePath<Self, AppBuilderV3BuildError?>("error")
  public static let isPreviewable = InstantAttributePath<Self, Bool?>("isPreviewable")
  public static let title = InstantAttributePath<Self, String?>("title")
  public static let file = InstantAttributePath<Self, InstantID<AppBuilderV3File>>("file")
  public static let owner = InstantAttributePath<Self, InstantID<AppBuilderV3User>>("owner")
  public static let instantAttributes = AppBuilderV3Schema.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var instantAppID: String
  public var code: String
  public var reasoning: String?
  public var slug: String?
  @InstantWire(.json)
  public var error: AppBuilderV3BuildError?
  public var isPreviewable: Bool?
  public var title: String?
  public var file: InstantID<AppBuilderV3File>?
  public var owner: InstantID<AppBuilderV3User>

  public init(
    id: InstantID<Self>,
    instantAppID: String,
    code: String,
    reasoning: String? = nil,
    slug: String? = nil,
    error: AppBuilderV3BuildError? = nil,
    isPreviewable: Bool? = nil,
    title: String? = nil,
    file: InstantID<AppBuilderV3File>? = nil,
    owner: InstantID<AppBuilderV3User>
  ) {
    self.id = id
    self.instantAppID = instantAppID
    self.code = code
    self.reasoning = reasoning
    self.slug = slug
    self.error = error
    self.isPreviewable = isPreviewable
    self.title = title
    self.file = file
    self.owner = owner
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    instantAppID = try snapshot.appBuilderV3String(
      "instantAppId",
      operation: "decode App Builder build"
    )
    code = try snapshot.appBuilderV3String("code", operation: "decode App Builder build")
    reasoning = snapshot.appBuilderV3OptionalString("reasoning")
    slug = snapshot.appBuilderV3OptionalString("slug")
    if let value = snapshot.values["error"]?.first {
      error = try AppBuilderV3BuildError.decodeInstantValue(
        value,
        namespace: snapshot.namespace,
        path: "error",
        localID: snapshot.id,
        operation: "decode App Builder build"
      )
    } else {
      error = nil
    }
    isPreviewable = snapshot.appBuilderV3OptionalBoolean("isPreviewable")
    title = snapshot.appBuilderV3OptionalString("title")
    file = snapshot.appBuilderV3OptionalRef("file")
    owner = try snapshot.appBuilderV3Ref("owner", operation: "decode App Builder build")
  }

  public static func forOwner(_ ownerID: InstantID<AppBuilderV3User>) -> InstantQuery<Self> {
    query
      .where(owner == ownerID)
      .include(file)
  }

  public static func byID(_ buildID: InstantID<Self>) -> InstantQuery<Self> {
    query
      .where(identifier == buildID.rawValue)
      .include(owner)
      .include(file)
  }

  fileprivate static func decodeError(
    value: InstantValue?,
    path: String,
    localID: String?,
    operation: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: operation,
      namespace: instantNamespace,
      path: path,
      localID: localID,
      message: "Expected \(expected), received \(String(describing: value)).",
      recovery: "Keep the App Builder V3 model aligned with the pinned source contract."
    )
  }
}

extension InstantEntitySnapshot {
  fileprivate func appBuilderV3String(_ path: String, operation: String) throws -> String {
    guard case let .string(value) = values[path]?.first else {
      throw AppBuilderV3Build.decodeError(
        value: values[path]?.first,
        path: path,
        localID: id,
        operation: operation,
        expected: "a string"
      )
    }
    return value
  }

  fileprivate func appBuilderV3OptionalString(_ path: String) -> String? {
    guard case let .string(value) = values[path]?.first else { return nil }
    return value
  }

  fileprivate func appBuilderV3OptionalBoolean(_ path: String) -> Bool? {
    guard case let .bool(value) = values[path]?.first else { return nil }
    return value
  }

  fileprivate func appBuilderV3Ref<Entity>(
    _ path: String,
    operation: String
  ) throws -> InstantID<Entity> {
    guard case let .ref(value) = values[path]?.first else {
      throw AppBuilderV3Build.decodeError(
        value: values[path]?.first,
        path: path,
        localID: id,
        operation: operation,
        expected: "an entity reference"
      )
    }
    return InstantID(rawValue: value)
  }

  fileprivate func appBuilderV3OptionalRef<Entity>(_ path: String) -> InstantID<Entity>? {
    guard case let .ref(value) = values[path]?.first else { return nil }
    return InstantID(rawValue: value)
  }
}
