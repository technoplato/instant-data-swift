import Foundation

public struct AppBuilderBuildError: Hashable, Codable, Sendable {
  public var from: String
  public var status: Int
  public var message: String

  public init(from: String, status: Int, message: String) {
    self.from = from
    self.status = status
    self.message = message
  }
}

public struct AppBuilderBuildRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var instantAppID: String
  public var ownerID: String
  public var code: String
  public var reasoning: String?
  public var slug: String?
  public var error: AppBuilderBuildError?
  public var isPreviewable: Bool?
  public var title: String?

  public init(
    id: String,
    instantAppID: String,
    ownerID: String,
    code: String,
    reasoning: String? = nil,
    slug: String? = nil,
    error: AppBuilderBuildError? = nil,
    isPreviewable: Bool? = nil,
    title: String? = nil
  ) {
    self.id = id
    self.instantAppID = instantAppID
    self.ownerID = ownerID
    self.code = code
    self.reasoning = reasoning
    self.slug = slug
    self.error = error
    self.isPreviewable = isPreviewable
    self.title = title
  }
}

public struct AppBuilderGenerationRequest: Hashable, Codable, Sendable {
  public var prompt: String
  public var buildID: String
  public var instantAppID: String

  public init(prompt: String, buildID: String, instantAppID: String) {
    self.prompt = prompt
    self.buildID = buildID
    self.instantAppID = instantAppID
  }
}

public struct AppBuilderGenerationChunk: Hashable, Codable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case reasoning
    case code
  }

  public var kind: Kind
  public var text: String

  public init(kind: Kind, text: String) {
    self.kind = kind
    self.text = text
  }
}

public struct AppBuilderCodeGeneratorClient: Sendable {
  public var generate:
    @Sendable (AppBuilderGenerationRequest) async throws
      -> AsyncThrowingStream<AppBuilderGenerationChunk, Error>

  public init(
    generate: @escaping @Sendable (AppBuilderGenerationRequest) async throws
      -> AsyncThrowingStream<AppBuilderGenerationChunk, Error>
  ) {
    self.generate = generate
  }
}

extension AppBuilderCodeGeneratorClient {
  public static let local = Self { request in
    AsyncThrowingStream { continuation in
      let title = AppBuilderExample.friendlyTitle(for: request.prompt)
      continuation.yield(
        AppBuilderGenerationChunk(
          kind: .reasoning,
          text:
            "Create a compact Swift-friendly preview for '\(title)' using Instant app \(request.instantAppID).\n"
        )
      )
      continuation.yield(
        AppBuilderGenerationChunk(
          kind: .code,
          text: AppBuilderExample.localPreviewCode(
            title: title,
            instantAppID: request.instantAppID
          )
        )
      )
      continuation.finish()
    }
  }
}

public enum AppBuilderExample {
  public static let usersNamespace = "$users"
  public static let filesNamespace = "$files"
  public static let buildsNamespace = "builds"

  public static let defaultOrgID = "local-instant-swift-data"

  public static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: filesNamespace),
    InstantAttribute(
      id: "$files/path",
      namespace: filesNamespace,
      name: "path",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "$files/url",
      namespace: filesNamespace,
      name: "url",
      valueType: .string
    ),

    .primaryKey(namespace: usersNamespace),
    InstantAttribute(
      id: "$users/email",
      namespace: usersNamespace,
      name: "email",
      valueType: .string,
      isRequired: false,
      isIndexed: true,
      isUnique: true
    ),

    .primaryKey(namespace: buildsNamespace),
    InstantAttribute(
      id: "builds/instantAppId",
      namespace: buildsNamespace,
      name: "instantAppId",
      valueType: .string
    ),
    InstantAttribute(
      id: "builds/code",
      namespace: buildsNamespace,
      name: "code",
      valueType: .string
    ),
    InstantAttribute(
      id: "builds/reasoning",
      namespace: buildsNamespace,
      name: "reasoning",
      valueType: .string,
      isRequired: false
    ),
    InstantAttribute(
      id: "builds/slug",
      namespace: buildsNamespace,
      name: "slug",
      valueType: .string,
      isRequired: false,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "builds/error",
      namespace: buildsNamespace,
      name: "error",
      valueType: .json,
      isRequired: false
    ),
    InstantAttribute(
      id: "builds/isPreviewable",
      namespace: buildsNamespace,
      name: "isPreviewable",
      valueType: .boolean,
      isRequired: false
    ),
    InstantAttribute(
      id: "builds/title",
      namespace: buildsNamespace,
      name: "title",
      valueType: .string,
      isRequired: false
    ),
    InstantAttribute(
      id: "builds/owner",
      namespace: buildsNamespace,
      name: "owner",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "builds/owner",
      reverseIdentity: "$users/builds",
      linkNamespace: usersNamespace
    ),
  ]

  public static let buildsQuery = InstantQueryPlan(
    id: "examples.app-builder.builds",
    namespace: buildsNamespace
  )

  public static func buildsForOwnerQuery(_ ownerID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.app-builder.builds.\(ownerID)",
      namespace: buildsNamespace,
      filters: [.equals(field: "owner", value: .ref(ownerID))]
    )
  }

  public static func buildQuery(_ buildID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.app-builder.build.\(buildID)",
      namespace: buildsNamespace,
      filters: [.equals(field: "id", value: .string(buildID))]
    )
  }

  public static func friendlyTitle(for prompt: String) -> String {
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = trimmed.isEmpty ? "Untitled build" : String(trimmed.prefix(100))
    return title.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func localPreviewCode(title: String, instantAppID: String) -> String {
    """
    import React from 'react';
    import { Text, View } from 'react-native';
    import { init } from '@instantdb/react-native';

    const db = init({ appId: "\(instantAppID)" });

    export default function App() {
      return (
        <View>
          <Text>\(title)</Text>
        </View>
      );
    }
    """
  }

  public static func createBuildOperations(
    id: String,
    ownerID: String,
    ownerEmail: String?,
    instantAppID: String,
    title: String,
    createdAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: buildsNamespace)
    ]
      + upsertUserOperations(
        id: ownerID,
        email: ownerEmail,
        updatedAt: createdAt,
        transactionID: transactionID
      )
      + updateBuildOperations(
        id: id,
        instantAppID: instantAppID,
        ownerID: ownerID,
        code: "",
        reasoning: nil,
        isPreviewable: false,
        title: title,
        updatedAt: createdAt,
        transactionID: transactionID,
        requiresExistingBuild: false
      )
  }

  public static func updateBuildOperations(
    id: String,
    instantAppID: String? = nil,
    ownerID: String? = nil,
    code: String? = nil,
    reasoning: String? = nil,
    slug: String? = nil,
    error: AppBuilderBuildError? = nil,
    isPreviewable: Bool? = nil,
    title: String? = nil,
    updatedAt: InstantTimestamp,
    transactionID: String,
    requiresExistingBuild: Bool = true
  ) -> [InstantTripleOperation] {
    var operations: [InstantTripleOperation] = []
    if requiresExistingBuild {
      operations.append(.requireEntityExists(entityID: id, namespace: buildsNamespace))
    }
    operations.append(
      identityOperation(id: id, namespace: buildsNamespace, updatedAt: updatedAt, transactionID: transactionID)
    )

    if let instantAppID {
      operations.append(insert(id: id, attributeID: "builds/instantAppId", value: .string(instantAppID), txID: transactionID, txTime: updatedAt))
    }
    if let ownerID {
      operations.append(insert(id: id, attributeID: "builds/owner", value: .ref(ownerID), txID: transactionID, txTime: updatedAt))
    }
    if let code {
      operations.append(insert(id: id, attributeID: "builds/code", value: .string(code), txID: transactionID, txTime: updatedAt))
    }
    if let reasoning {
      operations.append(insert(id: id, attributeID: "builds/reasoning", value: .string(reasoning), txID: transactionID, txTime: updatedAt))
    }
    if let slug {
      operations.append(insert(id: id, attributeID: "builds/slug", value: .string(slug), txID: transactionID, txTime: updatedAt))
    }
    if let error {
      operations.append(insert(id: id, attributeID: "builds/error", value: .json(error.jsonValue), txID: transactionID, txTime: updatedAt))
    }
    if let isPreviewable {
      operations.append(insert(id: id, attributeID: "builds/isPreviewable", value: .bool(isPreviewable), txID: transactionID, txTime: updatedAt))
    }
    if let title {
      operations.append(insert(id: id, attributeID: "builds/title", value: .string(title), txID: transactionID, txTime: updatedAt))
    }

    return operations
  }

  public static func upsertUserOperations(
    id: String,
    email: String?,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    var operations = [
      identityOperation(id: id, namespace: usersNamespace, updatedAt: updatedAt, transactionID: transactionID)
    ]
    if let email, !email.isEmpty {
      operations.append(
        insert(id: id, attributeID: "$users/email", value: .string(email), txID: transactionID, txTime: updatedAt)
      )
    }
    return operations
  }

  public static func deleteBuildOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: buildsNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: buildsNamespace),
    ]
  }

  public static func decodeBuilds(_ snapshots: [InstantEntitySnapshot]) throws
    -> [AppBuilderBuildRecord]
  {
    try snapshots.map(decodeBuild(_:))
  }

  public static func decodeBuild(_ snapshot: InstantEntitySnapshot) throws
    -> AppBuilderBuildRecord
  {
    guard case let .string(instantAppID) = snapshot.values["instantAppId"]?.first else {
      throw decodeError(
        id: snapshot.id,
        field: "instantAppId",
        expected: "string"
      )
    }
    guard case let .string(code) = snapshot.values["code"]?.first else {
      throw decodeError(id: snapshot.id, field: "code", expected: "string")
    }
    guard case let .ref(ownerID) = snapshot.values["owner"]?.first else {
      throw decodeError(id: snapshot.id, field: "owner", expected: "ref")
    }
    return AppBuilderBuildRecord(
      id: snapshot.id,
      instantAppID: instantAppID,
      ownerID: ownerID,
      code: code,
      reasoning: stringValue(snapshot.values["reasoning"]?.first),
      slug: stringValue(snapshot.values["slug"]?.first),
      error: buildError(snapshot.values["error"]?.first),
      isPreviewable: boolValue(snapshot.values["isPreviewable"]?.first),
      title: stringValue(snapshot.values["title"]?.first)
    )
  }

  private static func identityOperation(
    id: String,
    namespace: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    insert(
      id: id,
      attributeID: InstantAttribute.primaryKeyID(namespace: namespace),
      value: .string(id),
      txID: transactionID,
      txTime: updatedAt
    )
  }

  private static func insert(
    id: String,
    attributeID: String,
    value: InstantValue,
    txID: String,
    txTime: InstantTimestamp
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: id,
        attributeID: attributeID,
        value: value,
        txID: txID,
        txTime: txTime
      )
    )
  }

  private static func stringValue(_ value: InstantValue?) -> String? {
    guard case let .string(string) = value else { return nil }
    return string
  }

  private static func boolValue(_ value: InstantValue?) -> Bool? {
    guard case let .bool(bool) = value else { return nil }
    return bool
  }

  private static func buildError(_ value: InstantValue?) -> AppBuilderBuildError? {
    guard case let .json(json) = value else { return nil }
    return AppBuilderBuildError(jsonValue: json)
  }

  private static func decodeError(
    id: String,
    field: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode app-builder build",
      namespace: buildsNamespace,
      localID: id,
      message: "Expected \(buildsNamespace).\(field) to be a \(expected).",
      recovery: "Inspect the app-builder schema and local triples for \(id)."
    )
  }
}

private extension AppBuilderBuildError {
  var jsonValue: JSONValue {
    .object([
      "from": .string(from),
      "status": .number(Double(status)),
      "message": .string(message),
    ])
  }

  init?(jsonValue: JSONValue) {
    guard case let .object(object) = jsonValue,
      case let .string(from)? = object["from"],
      case let .number(status)? = object["status"],
      case let .string(message)? = object["message"]
    else { return nil }
    self.init(from: from, status: Int(status), message: message)
  }
}
