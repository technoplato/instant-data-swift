import XCTest
@testable import InstantDB

// Test models using @InstantEntity macro
@InstantEntity("goals")
struct TestGoal {
    var id: String
    var title: String
    var description: String?
    var completed: Bool
}

@InstantEntity("users")
struct TestUser {
    var id: String
    var email: String
    var name: String
}

final class TypeSafeSchemaTests: XCTestCase {

    // MARK: - New Fluent-Style API Tests

    func testFluentSchemaCreation() throws {
        let schema = InstantSchema {
            Entity("goals")
                .field("title", .string, .indexed)
                .optionalField("description", .string)
                .field("completed", .boolean)

            Entity("users")
                .field("email", .string, .indexed, .unique)
                .field("name", .string)

            Link("users", "goals")
                .hasMany()
                .to("goals", "owner")
        }

        XCTAssertEqual(schema.entities.count, 2)
        XCTAssertEqual(schema.links.count, 1)

        let goalEntity = schema.entities.first { $0.name == "goals" }
        XCTAssertNotNil(goalEntity)
        XCTAssertEqual(goalEntity?.attributes.count, 3)

        let titleAttr = goalEntity?.attributes.first { $0.name == "title" }
        XCTAssertNotNil(titleAttr)
        XCTAssertTrue(titleAttr?.isIndexed ?? false)

        let userEntity = schema.entities.first { $0.name == "users" }
        XCTAssertNotNil(userEntity)

        let emailAttr = userEntity?.attributes.first { $0.name == "email" }
        XCTAssertNotNil(emailAttr)
        XCTAssertTrue(emailAttr?.isIndexed ?? false)
        XCTAssertTrue(emailAttr?.isUnique ?? false)
    }

    func testSchemaSerializesToCorrectJSON() throws {
        let schema = InstantSchema {
            Entity("goals")
                .field("title", .string, .indexed)
                .field("completed", .boolean)
        }

        let dict = SchemaSerializer.toDictionary(schema)

        guard let entities = dict["entities"] as? [String: Any],
              let goals = entities["goals"] as? [String: Any],
              let attrs = goals["attrs"] as? [String: Any],
              let titleAttr = attrs["title"] as? [String: Any],
              let config = titleAttr["config"] as? [String: Any] else {
            XCTFail("Invalid schema structure")
            return
        }

        XCTAssertEqual(titleAttr["valueType"] as? String, "string")
        XCTAssertEqual(config["indexed"] as? Bool, true)
    }

    func testLinkSerializesCorrectly() throws {
        let schema = InstantSchema {
            Entity("users")
                .field("name", .string)

            Entity("goals")
                .field("title", .string)

            Link("users", "goals")
                .hasMany()
                .to("goals", "owner")
        }

        let dict = SchemaSerializer.toDictionary(schema)

        guard let links = dict["links"] as? [String: Any],
              let link = links.values.first as? [String: Any],
              let forward = link["forward"] as? [String: Any],
              let reverse = link["reverse"] as? [String: Any] else {
            XCTFail("Invalid link structure")
            return
        }

        XCTAssertEqual(forward["on"] as? String, "users")
        XCTAssertEqual(forward["label"] as? String, "goals")
        XCTAssertEqual(forward["has"] as? String, "many")

        XCTAssertEqual(reverse["on"] as? String, "goals")
        XCTAssertEqual(reverse["label"] as? String, "owner")
    }

    // MARK: - @InstantEntity Macro Tests

    func testEntitySchemaProtocolConformance() {
        XCTAssertEqual(TestGoal.namespace, "goals")
        XCTAssertEqual(TestUser.namespace, "users")

        XCTAssertEqual(TestGoal.schemaAttributes.count, 3)
        XCTAssertEqual(TestUser.schemaAttributes.count, 2)

        let titleAttr = TestGoal.schemaAttributes.first { $0.name == "title" }
        XCTAssertNotNil(titleAttr)
        XCTAssertEqual(titleAttr?.dataType, .string)
        XCTAssertFalse(titleAttr?.isOptional ?? true)

        let descAttr = TestGoal.schemaAttributes.first { $0.name == "description" }
        XCTAssertNotNil(descAttr)
        XCTAssertTrue(descAttr?.isOptional ?? false)
    }

    // MARK: - Legacy Typed API Tests (using TypedEntity directly)

    func testTypedEntityFromMacro() throws {
        // You can still use TypedEntity with @InstantEntity models
        let typedGoal = TypedEntity(TestGoal.self)
        let entity = typedGoal.toSchemaEntity()

        XCTAssertEqual(entity.name, "goals")
        XCTAssertEqual(entity.attributes.count, 3)
    }
}
