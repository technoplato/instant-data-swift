import Foundation

// MARK: - Field Constraints

/// Field constraints that can be combined when defining a field
public struct FieldConstraint: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Field is required (non-optional). This is the default.
    public static let required = FieldConstraint(rawValue: 1 << 0)

    /// Field should be indexed for faster queries
    public static let indexed = FieldConstraint(rawValue: 1 << 1)

    /// Field value must be unique across all entities
    public static let unique = FieldConstraint(rawValue: 1 << 2)
}

// MARK: - Entity Builder (Fluent-style)

/// Builder for defining an entity's schema using method chaining
///
/// Example:
/// ```swift
/// Entity("users")
///     .field("email", .string, .unique, .indexed)
///     .field("name", .string)
///     .optionalField("bio", .string)
/// ```
public final class Entity: @unchecked Sendable {
    public let name: String
    private var fields: [SchemaAttribute] = []

    public init(_ name: String) {
        self.name = name
    }

    /// Add a required field
    /// - Parameters:
    ///   - name: Field name
    ///   - type: Data type
    ///   - constraints: Additional constraints (.indexed, .unique)
    @discardableResult
    public func field(_ name: String, _ type: InstantDataType, _ constraints: FieldConstraint...) -> Entity {
        let combined = constraints.reduce(FieldConstraint()) { $0.union($1) }
        let attr = SchemaAttribute(
            name,
            type,
            isOptional: false,
            isIndexed: combined.contains(.indexed) || combined.contains(.unique),
            isUnique: combined.contains(.unique)
        )
        fields.append(attr)
        return self
    }

    /// Add an optional field
    /// - Parameters:
    ///   - name: Field name
    ///   - type: Data type
    ///   - constraints: Additional constraints (.indexed, .unique)
    @discardableResult
    public func optionalField(_ name: String, _ type: InstantDataType, _ constraints: FieldConstraint...) -> Entity {
        let combined = constraints.reduce(FieldConstraint()) { $0.union($1) }
        let attr = SchemaAttribute(
            name,
            type,
            isOptional: true,
            isIndexed: combined.contains(.indexed) || combined.contains(.unique),
            isUnique: combined.contains(.unique)
        )
        fields.append(attr)
        return self
    }

    /// Build the entity definition
    internal func build() -> SchemaEntityDef {
        SchemaEntityDef(name, attributes: fields)
    }
}

// MARK: - Schema Entity Definition

/// Entity definition with name and attributes
public struct SchemaEntityDef: Sendable {
    public let name: String
    public let attributes: [SchemaAttribute]

    public init(_ name: String, @SchemaAttributeBuilder attributes: () -> [SchemaAttribute]) {
        self.name = name
        self.attributes = attributes()
    }

    public init(_ name: String, attributes: [SchemaAttribute]) {
        self.name = name
        self.attributes = attributes
    }
}

// MARK: - Legacy Result Builder (for backwards compatibility)

@resultBuilder
public struct SchemaAttributeBuilder {
    public static func buildBlock(_ components: [SchemaAttribute]...) -> [SchemaAttribute] {
        components.flatMap { $0 }
    }

    public static func buildArray(_ components: [[SchemaAttribute]]) -> [SchemaAttribute] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [SchemaAttribute]?) -> [SchemaAttribute] {
        component ?? []
    }

    public static func buildEither(first component: [SchemaAttribute]) -> [SchemaAttribute] {
        component
    }

    public static func buildEither(second component: [SchemaAttribute]) -> [SchemaAttribute] {
        component
    }

    public static func buildExpression(_ expression: SchemaAttribute) -> [SchemaAttribute] {
        [expression]
    }
}

// MARK: - Type alias for backwards compatibility

@available(*, deprecated, renamed: "SchemaEntityDef")
public typealias SchemaEntity = SchemaEntityDef
