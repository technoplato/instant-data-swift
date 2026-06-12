import XCTest
@testable import InstantDB

final class SchemaTests: XCTestCase {

    func testBasicSchemaGeneration() throws {
        // Define schema using new Fluent-style API
        let schema = InstantSchema {
            Entity("users")
                .field("email", .string, .unique, .indexed)
                .field("name", .string)
                .optionalField("bio", .string)

            Entity("posts")
                .field("title", .string)
                .optionalField("body", .string)
        }

        // Generate JSON
        let json = try schema.toJSONString()
        print("Generated JSON:\n\(json)")

        // Verify structure
        XCTAssertEqual(schema.entities.count, 2)
        XCTAssertEqual(schema.entities[0].name, "users")
        XCTAssertEqual(schema.entities[0].attributes.count, 3)
        XCTAssertEqual(schema.entities[1].name, "posts")
        XCTAssertEqual(schema.entities[1].attributes.count, 2)

        // Verify attributes
        let emailAttr = schema.entities[0].attributes[0]
        XCTAssertEqual(emailAttr.name, "email")
        XCTAssertTrue(emailAttr.isUnique)
        XCTAssertTrue(emailAttr.isIndexed)
        XCTAssertFalse(emailAttr.isOptional)

        let bioAttr = schema.entities[0].attributes[2]
        XCTAssertEqual(bioAttr.name, "bio")
        XCTAssertTrue(bioAttr.isOptional)
    }

    func testSchemaWithLinks() throws {
        let schema = InstantSchema {
            Entity("users")
                .field("name", .string)

            Entity("posts")
                .field("title", .string)

            Link("users", "posts")
                .hasMany()
                .to("posts", "author")
                .reverseHasOne()
        }

        let json = try schema.toJSONString()
        print("Schema with links:\n\(json)")

        XCTAssertEqual(schema.links.count, 1)
        XCTAssertEqual(schema.links[0].forward.entityName, "users")
        XCTAssertEqual(schema.links[0].forward.label, "posts")
        XCTAssertEqual(schema.links[0].forward.cardinality, .many)
        XCTAssertEqual(schema.links[0].reverse.entityName, "posts")
        XCTAssertEqual(schema.links[0].reverse.label, "author")
        XCTAssertEqual(schema.links[0].reverse.cardinality, .one)
    }

    func testFullBlogSchema() throws {
        let schema = InstantSchema {
            // Users entity
            Entity("users")
                .field("email", .string, .unique, .indexed)
                .field("username", .string, .unique)
                .field("displayName", .string)
                .optionalField("bio", .string)
                .optionalField("avatarUrl", .string)
                .field("createdAt", .date)

            // Posts entity
            Entity("posts")
                .field("title", .string, .indexed)
                .field("slug", .string, .unique)
                .optionalField("content", .string)
                .field("published", .boolean)
                .field("createdAt", .date)
                .optionalField("publishedAt", .date)

            // Comments entity
            Entity("comments")
                .field("body", .string)
                .field("createdAt", .date)

            // Tags entity
            Entity("tags")
                .field("name", .string, .unique)
                .optionalField("description", .string)

            // Links
            Link("users", "posts")
                .hasMany()
                .to("posts", "author")
                .reverseHasOne()

            Link("posts", "comments")
                .hasMany()
                .to("comments", "post")
                .reverseHasOne()

            Link("users", "comments")
                .hasMany()
                .to("comments", "author")
                .reverseHasOne()
        }

        let json = try schema.toJSONString()
        print("\n=== Full Blog Schema ===\n\(json)\n")

        // Verify counts
        XCTAssertEqual(schema.entities.count, 4)
        XCTAssertEqual(schema.links.count, 3)
    }

    func testJSONOutput() throws {
        let schema = InstantSchema {
            Entity("todos")
                .field("title", .string)
                .field("completed", .boolean)
                .optionalField("priority", .number)
        }

        let jsonData = try schema.toJSON()
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        // Verify JSON structure matches InstantDB platform API format
        XCTAssertNotNil(jsonObject["entities"])
        XCTAssertNotNil(jsonObject["links"])

        let entities = jsonObject["entities"] as! [String: Any]
        let todos = entities["todos"] as! [String: Any]
        let attrs = todos["attrs"] as! [String: Any]

        // Verify title attribute
        let title = attrs["title"] as! [String: Any]
        XCTAssertEqual(title["valueType"] as? String, "string")
        XCTAssertEqual(title["required"] as? Bool, true)

        // Verify priority is optional (no "required" key)
        let priority = attrs["priority"] as! [String: Any]
        XCTAssertNil(priority["required"])

        print("JSON Output verification passed!")
    }
}
