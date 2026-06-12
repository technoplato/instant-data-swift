import Foundation

// MARK: - Schema Definition

/// InstantDB Schema definition with fluent API
///
/// Example:
/// ```swift
/// let schema = InstantSchema {
///     Entity("users")
///         .field("email", .string, .unique, .indexed)
///         .field("name", .string)
///         .optionalField("bio", .string)
///
///     Entity("posts")
///         .field("title", .string)
///         .optionalField("body", .string)
///
///     Link("users", "posts")
///         .hasMany()
///         .to("posts", "author")
///         .reverseHasOne()
/// }
///
/// // Preview changes
/// let plan = try await schema.plan(appId: "my-app", token: adminToken)
/// print(plan.description)
///
/// // Apply changes
/// try await schema.push(appId: "my-app", token: adminToken)
/// ```
public struct InstantSchema: Sendable {
    public let entities: [SchemaEntityDef]
    public let links: [SchemaLink]

    public init(@InstantSchemaBuilder content: () -> InstantSchemaContent) {
        let schemaContent = content()
        self.entities = schemaContent.entities
        self.links = schemaContent.links
    }

    public init(entities: [SchemaEntityDef], links: [SchemaLink] = []) {
        self.entities = entities
        self.links = links
    }

    // MARK: - Push/Plan Methods

    /// Preview schema changes without applying them
    /// - Parameters:
    ///   - appId: Your InstantDB app ID
    ///   - token: Admin token for authentication
    ///   - baseURL: API base URL (defaults to production)
    /// - Returns: Plan showing what changes would be made
    public func plan(
        appId: String,
        token: String,
        baseURL: String = "https://api.instantdb.com"
    ) async throws -> SchemaPlan {
        let api = PlatformAPI(token: token, baseURL: baseURL)
        let response = try await api.planSchemaPush(appId: appId, schema: self)
        return SchemaPlan(steps: response.steps)
    }

    /// Push schema changes to InstantDB
    /// - Parameters:
    ///   - appId: Your InstantDB app ID
    ///   - token: Admin token for authentication
    ///   - baseURL: API base URL (defaults to production)
    /// - Returns: Result of the push operation
    @discardableResult
    public func push(
        appId: String,
        token: String,
        baseURL: String = "https://api.instantdb.com"
    ) async throws -> SchemaPushResult {
        let api = PlatformAPI(token: token, baseURL: baseURL)
        let response = try await api.pushSchema(appId: appId, schema: self)
        return SchemaPushResult(steps: response.steps ?? [])
    }

    /// Get the current schema from InstantDB
    /// - Parameters:
    ///   - appId: Your InstantDB app ID
    ///   - token: Admin token for authentication
    ///   - baseURL: API base URL (defaults to production)
    /// - Returns: Current schema as dictionary
    public static func fetch(
        appId: String,
        token: String,
        baseURL: String = "https://api.instantdb.com"
    ) async throws -> [String: Any] {
        let api = PlatformAPI(token: token, baseURL: baseURL)
        return try await api.getSchema(appId: appId)
    }

    // MARK: - Serialization

    /// Convert schema to JSON data
    public func toJSON() throws -> Data {
        try SchemaSerializer.toJSON(self)
    }

    /// Convert schema to JSON string
    public func toJSONString() throws -> String {
        try SchemaSerializer.toJSONString(self)
    }
}

// MARK: - Schema Content

public struct InstantSchemaContent: Sendable {
    public var entities: [SchemaEntityDef] = []
    public var links: [SchemaLink] = []

    public init(entities: [SchemaEntityDef] = [], links: [SchemaLink] = []) {
        self.entities = entities
        self.links = links
    }
}

// MARK: - Schema Component

public enum InstantSchemaComponent {
    case entity(SchemaEntityDef)
    case link(SchemaLink)
}

// MARK: - Result Builder

@resultBuilder
public struct InstantSchemaBuilder {
    public static func buildBlock(_ components: InstantSchemaComponent...) -> InstantSchemaContent {
        var content = InstantSchemaContent()
        for component in components {
            switch component {
            case .entity(let entity):
                content.entities.append(entity)
            case .link(let link):
                content.links.append(link)
            }
        }
        return content
    }

    // Entity builder support
    public static func buildExpression(_ expression: Entity) -> InstantSchemaComponent {
        .entity(expression.build())
    }

    // SchemaEntityDef support (legacy)
    public static func buildExpression(_ expression: SchemaEntityDef) -> InstantSchemaComponent {
        .entity(expression)
    }

    // LinkBuilder support
    public static func buildExpression(_ expression: LinkBuilder) -> InstantSchemaComponent {
        if let link = expression.build() {
            return .link(link)
        }
        fatalError("Invalid link builder - missing reverse endpoint. Use .to(entity, label)")
    }

    // SchemaLink direct support
    public static func buildExpression(_ expression: SchemaLink) -> InstantSchemaComponent {
        .link(expression)
    }

    // Typed entity support (legacy)
    public static func buildExpression<E: InstantEntitySchema>(_ expression: TypedEntity<E>) -> InstantSchemaComponent {
        .entity(expression.toSchemaEntity())
    }

    // Typed link support (legacy)
    public static func buildExpression<From: InstantEntitySchema, To: InstantEntitySchema>(
        _ expression: TypedLinkBuilder<From, To>
    ) -> InstantSchemaComponent {
        if let link = expression.build() {
            return .link(link)
        }
        fatalError("Invalid typed link builder - missing reverse endpoint. Use .to(EntityType.self, label)")
    }

    public static func buildArray(_ components: [InstantSchemaComponent]) -> InstantSchemaContent {
        var content = InstantSchemaContent()
        for component in components {
            switch component {
            case .entity(let entity):
                content.entities.append(entity)
            case .link(let link):
                content.links.append(link)
            }
        }
        return content
    }

    public static func buildOptional(_ component: InstantSchemaContent?) -> InstantSchemaContent {
        component ?? InstantSchemaContent()
    }
}

// MARK: - Plan Results

/// Schema plan showing proposed changes
public struct SchemaPlan: Sendable {
    public let steps: [SchemaPlanStep]

    /// Whether there are any changes to apply
    public var hasChanges: Bool {
        !steps.isEmpty
    }

    /// Human-readable description of all changes
    public var description: String {
        if steps.isEmpty {
            return "No changes required"
        }
        return steps.compactMap { $0.friendlyDescription }.joined(separator: "\n")
    }
}

/// Result of pushing schema changes
public struct SchemaPushResult: Sendable {
    public let steps: [SchemaPlanStep]

    /// Whether any changes were applied
    public var appliedChanges: Bool {
        !steps.isEmpty
    }
}
