#if os(macOS)
  import InstantSwiftDataMacros
  import MacroTesting
  import XCTest

  final class InstantEntityMacroTests: XCTestCase {
    override func invokeTest() {
      withMacroTesting(
        record: .failed,
        macros: [
          "InstantEntity": InstantEntityMacro.self,
          "InstantRelation": InstantRelationMacro.self,
          "InstantWire": InstantWireMacro.self,
        ]
      ) {
        super.invokeTest()
      }
    }

    func testDefaultNamespace() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
        }
        """
      } expansion: {
        """
        struct Todo {

            public static var instantNamespace: String {
              "todos"
            }

            public static var instantAttributes: [InstantAttribute] {
              [

              ]
            }
        }
        """
      }
    }

    func testDefaultPluralization() {
      assertMacro {
        """
        @InstantEntity
        struct Category {
        }

        @InstantEntity
        struct Box {
        }

        @InstantEntity
        struct Brush {
        }
        """
      } expansion: {
        """
        struct Category {

            public static var instantNamespace: String {
              "categories"
            }

            public static var instantAttributes: [InstantAttribute] {
              [

              ]
            }
        }
        struct Box {

            public static var instantNamespace: String {
              "boxes"
            }

            public static var instantAttributes: [InstantAttribute] {
              [

              ]
            }
        }
        struct Brush {

            public static var instantNamespace: String {
              "brushes"
            }

            public static var instantAttributes: [InstantAttribute] {
              [

              ]
            }
        }
        """
      }
    }

    func testManualNamespace() {
      assertMacro {
        """
        @InstantEntity("people")
        struct Person {
        }
        """
      } expansion: {
        """
        struct Person {

            public static var instantNamespace: String {
              "people"
            }

            public static var instantAttributes: [InstantAttribute] {
              [

              ]
            }
        }
        """
      }
    }

    func testGeneratedDraft() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var text: String
          var isCompleted: Bool = false
          var isFlagged = false
          var notes: String?
          var category: Optional<String>
          var owner: Swift.Optional<String>
          var createdAt: Date
          var localTags: [String]
          let createdBy: String
          let metadata = ["local"]
          let ignoredA = 1, ignoredB = 2

          static let ignored = InstantAttributePath<Todo, String>("ignored")

          var computed: String {
            text
          }
        }
        """
      } expansion: {
        """
        struct Todo {
          var id: InstantID<Todo>
          var text: String
          var isCompleted: Bool = false
          var isFlagged = false
          var notes: String?
          var category: Optional<String>
          var owner: Swift.Optional<String>
          var createdAt: Date
          var localTags: [String]
          let createdBy: String
          let metadata = ["local"]
          let ignoredA = 1, ignoredB = 2

          static let ignored = InstantAttributePath<Todo, String>("ignored")

          var computed: String {
            text
          }

          public static var instantNamespace: String {
            "todos"
          }

          public static let text = InstantAttributePath<Todo, String>("text")

          public static let isCompleted = InstantAttributePath<Todo, Bool>("isCompleted")

          public static let isFlagged = InstantAttributePath<Todo, Bool>("isFlagged")

          public static let notes = InstantAttributePath<Todo, String?>("notes")

          public static let category = InstantAttributePath<Todo, Optional<String>>("category")

          public static let owner = InstantAttributePath<Todo, Swift.Optional<String>>("owner")

          public static let createdAt = InstantAttributePath<Todo, Date>("createdAt")

          public static var instantAttributes: [InstantAttribute] {
            [
                InstantAttribute(
                  id: Todo.text.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.text.name,
                  valueType: .string,
                  isRequired: true,
                  isIndexed: true
                ),
                InstantAttribute(
                  id: Todo.isCompleted.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.isCompleted.name,
                  valueType: .boolean,
                  isRequired: true,
                  isIndexed: true
                ),
                InstantAttribute(
                  id: Todo.isFlagged.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.isFlagged.name,
                  valueType: .boolean,
                  isRequired: true,
                  isIndexed: true
                ),
                InstantAttribute(
                  id: Todo.notes.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.notes.name,
                  valueType: .string,
                  isRequired: false,
                  isIndexed: true
                ),
                InstantAttribute(
                  id: Todo.category.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.category.name,
                  valueType: .string,
                  isRequired: false,
                  isIndexed: true
                ),
                InstantAttribute(
                  id: Todo.owner.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.owner.name,
                  valueType: .string,
                  isRequired: false,
                  isIndexed: true
                ),
                InstantAttribute(
                  id: Todo.createdAt.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.createdAt.name,
                  valueType: .date,
                  isRequired: true,
                  isIndexed: true
                )
            ]
          }

          public struct Draft: InstantEntityDraft {
            public typealias Entity = Todo
            public var id: Todo.ID? = nil

            public var text: String
            public var isCompleted: Bool
            public var isFlagged: Bool
            public var notes: String?
            public var category: Optional<String>
            public var owner: Swift.Optional<String>
            public var createdAt: Date

            public init(
              id: Todo.ID? = nil,
              text: String,
              isCompleted: Bool = false,
              isFlagged: Bool = false,
              notes: String? = nil,
              category: Optional<String> = nil,
              owner: Swift.Optional<String> = nil,
              createdAt: Date
            ) {
              self.id = id
              self.text = text
              self.isCompleted = isCompleted
              self.isFlagged = isFlagged
              self.notes = notes
              self.category = category
              self.owner = owner
              self.createdAt = createdAt
            }

            public init(_ entity: Todo) {
              self.id = entity.id
              self.text = entity.text
              self.isCompleted = entity.isCompleted
              self.isFlagged = entity.isFlagged
              self.notes = entity.notes
              self.category = entity.category
              self.owner = entity.owner
              self.createdAt = entity.createdAt
            }

            public var instantAssignments: [InstantAttributeAssignment<Todo>] {
              [
              InstantAttributeAssignment<Todo>(
                name: "text",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "text"
                  })?.id
                  ?? Todo.instantNamespace + "/text",
                value: self.text.instantValue
              ),
              InstantAttributeAssignment<Todo>(
                name: "isCompleted",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "isCompleted"
                  })?.id
                  ?? Todo.instantNamespace + "/isCompleted",
                value: self.isCompleted.instantValue
              ),
              InstantAttributeAssignment<Todo>(
                name: "isFlagged",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "isFlagged"
                  })?.id
                  ?? Todo.instantNamespace + "/isFlagged",
                value: self.isFlagged.instantValue
              ),
              InstantAttributeAssignment<Todo>(
                name: "notes",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "notes"
                  })?.id
                  ?? Todo.instantNamespace + "/notes",
                value: self.notes.instantValue
              ),
              InstantAttributeAssignment<Todo>(
                name: "category",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "category"
                  })?.id
                  ?? Todo.instantNamespace + "/category",
                value: self.category.instantValue
              ),
              InstantAttributeAssignment<Todo>(
                name: "owner",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "owner"
                  })?.id
                  ?? Todo.instantNamespace + "/owner",
                value: self.owner.instantValue
              ),
              InstantAttributeAssignment<Todo>(
                name: "createdAt",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "createdAt"
                  })?.id
                  ?? Todo.instantNamespace + "/createdAt",
                value: self.createdAt.instantValue
              )
              ]
            }
          }
        }
        """
      }
    }

    func testGeneratedDraftRequiresInstantPrimaryKey() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
          var id: String
          var text: String
        }

        @InstantEntity
        struct LegacyTodo {
          typealias ID = String
          var id: ID
          var text: String
        }
        """
      } expansion: {
        """
        struct Todo {
          var id: String
          var text: String

          public static var instantNamespace: String {
            "todos"
          }

          public static let text = InstantAttributePath<Todo, String>("text")

          public static var instantAttributes: [InstantAttribute] {
            [
                InstantAttribute(
                  id: Todo.text.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.text.name,
                  valueType: .string,
                  isRequired: true,
                  isIndexed: true
                )
            ]
          }
        }
        struct LegacyTodo {
          typealias ID = String
          var id: ID
          var text: String

          public static var instantNamespace: String {
            "legacyTodos"
          }

          public static let text = InstantAttributePath<LegacyTodo, String>("text")

          public static var instantAttributes: [InstantAttribute] {
            [
                InstantAttribute(
                  id: LegacyTodo.text.attributeID,
                  namespace: LegacyTodo.instantNamespace,
                  name: LegacyTodo.text.name,
                  valueType: .string,
                  isRequired: true,
                  isIndexed: true
                )
            ]
          }
        }
        """
      }
    }

    func testGeneratedDraftAcceptsInstantPrimaryKeyAliases() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
          typealias ID = InstantID<Todo>
          var id: ID
          var text: String
        }

        @InstantEntity
        struct Project {
          typealias ID = InstantID<Project>
          var id: Project.ID
          var title: String
        }

        @InstantEntity
        struct Profile {
          typealias ID = InstantID<Profile>
          var id: Self.ID
          var name: String
        }

        @InstantEntity
        struct Contact {
          typealias ID = InstantID<Self>
          var id: ID
          var email: String
        }
        """
      } expansion: {
        """
        struct Todo {
          typealias ID = InstantID<Todo>
          var id: ID
          var text: String

          public static var instantNamespace: String {
            "todos"
          }

          public static let text = InstantAttributePath<Todo, String>("text")

          public static var instantAttributes: [InstantAttribute] {
            [
                InstantAttribute(
                  id: Todo.text.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.text.name,
                  valueType: .string,
                  isRequired: true,
                  isIndexed: true
                )
            ]
          }

          public struct Draft: InstantEntityDraft {
            public typealias Entity = Todo
            public var id: Todo.ID? = nil

            public var text: String

            public init(
              id: Todo.ID? = nil,
              text: String
            ) {
              self.id = id
              self.text = text
            }

            public init(_ entity: Todo) {
              self.id = entity.id
              self.text = entity.text
            }

            public var instantAssignments: [InstantAttributeAssignment<Todo>] {
              [
              InstantAttributeAssignment<Todo>(
                name: "text",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "text"
                  })?.id
                  ?? Todo.instantNamespace + "/text",
                value: self.text.instantValue
              )
              ]
            }
          }
        }
        struct Project {
          typealias ID = InstantID<Project>
          var id: Project.ID
          var title: String

          public static var instantNamespace: String {
            "projects"
          }

          public static let title = InstantAttributePath<Project, String>("title")

          public static var instantAttributes: [InstantAttribute] {
            [
                InstantAttribute(
                  id: Project.title.attributeID,
                  namespace: Project.instantNamespace,
                  name: Project.title.name,
                  valueType: .string,
                  isRequired: true,
                  isIndexed: true
                )
            ]
          }

          public struct Draft: InstantEntityDraft {
            public typealias Entity = Project
            public var id: Project.ID? = nil

            public var title: String

            public init(
              id: Project.ID? = nil,
              title: String
            ) {
              self.id = id
              self.title = title
            }

            public init(_ entity: Project) {
              self.id = entity.id
              self.title = entity.title
            }

            public var instantAssignments: [InstantAttributeAssignment<Project>] {
              [
              InstantAttributeAssignment<Project>(
                name: "title",
                attributeID: Project.instantAttributes
                  .first(where: {
                    $0.name == "title"
                  })?.id
                  ?? Project.instantNamespace + "/title",
                value: self.title.instantValue
              )
              ]
            }
          }
        }
        struct Profile {
          typealias ID = InstantID<Profile>
          var id: Self.ID
          var name: String

          public static var instantNamespace: String {
            "profiles"
          }

          public static let name = InstantAttributePath<Profile, String>("name")

          public static var instantAttributes: [InstantAttribute] {
            [
                InstantAttribute(
                  id: Profile.name.attributeID,
                  namespace: Profile.instantNamespace,
                  name: Profile.name.name,
                  valueType: .string,
                  isRequired: true,
                  isIndexed: true
                )
            ]
          }

          public struct Draft: InstantEntityDraft {
            public typealias Entity = Profile
            public var id: Profile.ID? = nil

            public var name: String

            public init(
              id: Profile.ID? = nil,
              name: String
            ) {
              self.id = id
              self.name = name
            }

            public init(_ entity: Profile) {
              self.id = entity.id
              self.name = entity.name
            }

            public var instantAssignments: [InstantAttributeAssignment<Profile>] {
              [
              InstantAttributeAssignment<Profile>(
                name: "name",
                attributeID: Profile.instantAttributes
                  .first(where: {
                    $0.name == "name"
                  })?.id
                  ?? Profile.instantNamespace + "/name",
                value: self.name.instantValue
              )
              ]
            }
          }
        }
        struct Contact {
          typealias ID = InstantID<Self>
          var id: ID
          var email: String

          public static var instantNamespace: String {
            "contacts"
          }

          public static let email = InstantAttributePath<Contact, String>("email")

          public static var instantAttributes: [InstantAttribute] {
            [
                InstantAttribute(
                  id: Contact.email.attributeID,
                  namespace: Contact.instantNamespace,
                  name: Contact.email.name,
                  valueType: .string,
                  isRequired: true,
                  isIndexed: true
                )
            ]
          }

          public struct Draft: InstantEntityDraft {
            public typealias Entity = Contact
            public var id: Contact.ID? = nil

            public var email: String

            public init(
              id: Contact.ID? = nil,
              email: String
            ) {
              self.id = id
              self.email = email
            }

            public init(_ entity: Contact) {
              self.id = entity.id
              self.email = entity.email
            }

            public var instantAssignments: [InstantAttributeAssignment<Contact>] {
              [
              InstantAttributeAssignment<Contact>(
                name: "email",
                attributeID: Contact.instantAttributes
                  .first(where: {
                    $0.name == "email"
                  })?.id
                  ?? Contact.instantNamespace + "/email",
                value: self.email.instantValue
              )
              ]
            }
          }
        }
        """
      }
    }

    func testGeneratedSchemaHelpers() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var text: String
          var isCompleted = false
          var count: Int
          var dueAt: Date?
          var metadata: JSONValue
          var owner: InstantID<User>
          var unsupported: [String]

          static let manuallyDeclared = InstantAttributePath<Todo, String>("manuallyDeclared")
        }
        """
      } expansion: {
        """
        struct Todo {
          var id: InstantID<Todo>
          var text: String
          var isCompleted = false
          var count: Int
          var dueAt: Date?
          var metadata: JSONValue
          var owner: InstantID<User>
          var unsupported: [String]

          static let manuallyDeclared = InstantAttributePath<Todo, String>("manuallyDeclared")

          public static var instantNamespace: String {
            "todos"
          }

          public static let text = InstantAttributePath<Todo, String>("text")

          public static let isCompleted = InstantAttributePath<Todo, Bool>("isCompleted")

          public static let count = InstantAttributePath<Todo, Int>("count")

          public static let dueAt = InstantAttributePath<Todo, Date?>("dueAt")

          public static let metadata = InstantAttributePath<Todo, JSONValue>("metadata")

          public static let owner = InstantAttributePath<Todo, InstantID<User>>("owner")

          public static var instantAttributes: [InstantAttribute] {
            [
                InstantAttribute(
                  id: Todo.text.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.text.name,
                  valueType: .string,
                  isRequired: true,
                  isIndexed: true
                ),
                InstantAttribute(
                  id: Todo.isCompleted.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.isCompleted.name,
                  valueType: .boolean,
                  isRequired: true,
                  isIndexed: true
                ),
                InstantAttribute(
                  id: Todo.count.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.count.name,
                  valueType: .number,
                  isRequired: true,
                  isIndexed: true
                ),
                InstantAttribute(
                  id: Todo.dueAt.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.dueAt.name,
                  valueType: .date,
                  isRequired: false,
                  isIndexed: true
                ),
                InstantAttribute(
                  id: Todo.metadata.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.metadata.name,
                  valueType: .json,
                  isRequired: true,
                  isIndexed: true
                ),
                InstantAttribute(
                  id: Todo.owner.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.owner.name,
                  valueType: .ref,
                  isRequired: true,
                  isIndexed: true,
                  isUnique: false,
                  forwardIdentity: nil,
                  reverseIdentity: nil,
                  primaryKey: false,
                  linkNamespace: User.instantNamespace
                )
            ]
          }

          public struct Draft: InstantEntityDraft {
            public typealias Entity = Todo
            public var id: Todo.ID? = nil

            public var text: String
            public var isCompleted: Bool
            public var count: Int
            public var dueAt: Date?
            public var metadata: JSONValue
            public var owner: InstantID<User>

            public init(
              id: Todo.ID? = nil,
              text: String,
              isCompleted: Bool = false,
              count: Int,
              dueAt: Date? = nil,
              metadata: JSONValue,
              owner: InstantID<User>
            ) {
              self.id = id
              self.text = text
              self.isCompleted = isCompleted
              self.count = count
              self.dueAt = dueAt
              self.metadata = metadata
              self.owner = owner
            }

            public init(_ entity: Todo) {
              self.id = entity.id
              self.text = entity.text
              self.isCompleted = entity.isCompleted
              self.count = entity.count
              self.dueAt = entity.dueAt
              self.metadata = entity.metadata
              self.owner = entity.owner
            }

            public var instantAssignments: [InstantAttributeAssignment<Todo>] {
              [
              InstantAttributeAssignment<Todo>(
                name: "text",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "text"
                  })?.id
                  ?? Todo.instantNamespace + "/text",
                value: self.text.instantValue
              ),
              InstantAttributeAssignment<Todo>(
                name: "isCompleted",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "isCompleted"
                  })?.id
                  ?? Todo.instantNamespace + "/isCompleted",
                value: self.isCompleted.instantValue
              ),
              InstantAttributeAssignment<Todo>(
                name: "count",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "count"
                  })?.id
                  ?? Todo.instantNamespace + "/count",
                value: self.count.instantValue
              ),
              InstantAttributeAssignment<Todo>(
                name: "dueAt",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "dueAt"
                  })?.id
                  ?? Todo.instantNamespace + "/dueAt",
                value: self.dueAt.instantValue
              ),
              InstantAttributeAssignment<Todo>(
                name: "metadata",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "metadata"
                  })?.id
                  ?? Todo.instantNamespace + "/metadata",
                value: self.metadata.instantValue
              ),
              InstantAttributeAssignment<Todo>(
                name: "owner",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "owner"
                  })?.id
                  ?? Todo.instantNamespace + "/owner",
                value: self.owner.instantValue
              )
              ]
            }
          }
        }
        """
      }
    }

    func testGeneratedSchemaHelpersUseInstantRelationMetadata() {
      assertMacro {
        """
        @InstantEntity
        struct Post {
          var id: InstantID<Post>
          var title: String

          @InstantRelation(reverse: "posts")
          var author: InstantID<User>
        }
        """
      } expansion: {
        """
        struct Post {
          var id: InstantID<Post>
          var title: String
          var author: InstantID<User>

          public static var instantNamespace: String {
            "posts"
          }

          public static let title = InstantAttributePath<Post, String>("title")

          public static let author = InstantAttributePath<Post, InstantID<User>>("author")

          public static let `posts` = InstantReverseRelation<User, Post>(attribute: Post.author)

          public static var instantAttributes: [InstantAttribute] {
            [
                InstantAttribute(
                  id: Post.title.attributeID,
                  namespace: Post.instantNamespace,
                  name: Post.title.name,
                  valueType: .string,
                  isRequired: true,
                  isIndexed: true
                ),
                InstantAttribute(
                  id: Post.author.attributeID,
                  namespace: Post.instantNamespace,
                  name: Post.author.name,
                  valueType: .ref,
                  isRequired: true,
                  isIndexed: true,
                  isUnique: false,
                  forwardIdentity: Post.author.attributeID,
                  reverseIdentity: User.instantNamespace + "/posts",
                  primaryKey: false,
                  linkNamespace: User.instantNamespace
                )
            ]
          }

          public struct Draft: InstantEntityDraft {
            public typealias Entity = Post
            public var id: Post.ID? = nil

            public var title: String
            public var author: InstantID<User>

            public init(
              id: Post.ID? = nil,
              title: String,
              author: InstantID<User>
            ) {
              self.id = id
              self.title = title
              self.author = author
            }

            public init(_ entity: Post) {
              self.id = entity.id
              self.title = entity.title
              self.author = entity.author
            }

            public var instantAssignments: [InstantAttributeAssignment<Post>] {
              [
              InstantAttributeAssignment<Post>(
                name: "title",
                attributeID: Post.instantAttributes
                  .first(where: {
                    $0.name == "title"
                  })?.id
                  ?? Post.instantNamespace + "/title",
                value: self.title.instantValue
              ),
              InstantAttributeAssignment<Post>(
                name: "author",
                attributeID: Post.instantAttributes
                  .first(where: {
                    $0.name == "author"
                  })?.id
                  ?? Post.instantNamespace + "/author",
                value: self.author.instantValue
              )
              ]
            }
          }
        }
        """
      }
    }

    func testGeneratedSchemaHelpersUseInstantWireMetadataForEnumFields() {
      assertMacro {
        """
        enum Status: String, InstantStringEnum {
          case open
          case done
        }

        enum Priority: Int, InstantNumberEnum {
          case low = 1
          case high = 2
        }

        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>

          @InstantWire(.string)
          var status: Status

          @InstantWire(.number)
          var priority: Priority?
        }
        """
      } expansion: {
        """
        enum Status: String, InstantStringEnum {
          case open
          case done
        }

        enum Priority: Int, InstantNumberEnum {
          case low = 1
          case high = 2
        }
        struct Todo {
          var id: InstantID<Todo>
          var status: Status
          var priority: Priority?

          public static var instantNamespace: String {
            "todos"
          }

          public static let status = InstantAttributePath<Todo, Status>("status")

          public static let priority = InstantAttributePath<Todo, Priority?>("priority")

          private static let __instantWireValidation_status: Void = {
            let _: InstantStringWireValue.Type = Status.self
          }()

          private static let __instantWireValidation_priority: Void = {
            let _: InstantNumberWireValue.Type = Priority.self
          }()

          public static var instantAttributes: [InstantAttribute] {
            [
                InstantAttribute(
                  id: Todo.status.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.status.name,
                  valueType: .string,
                  isRequired: true,
                  isIndexed: true
                ),
                InstantAttribute(
                  id: Todo.priority.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.priority.name,
                  valueType: .number,
                  isRequired: false,
                  isIndexed: true
                )
            ]
          }

          public struct Draft: InstantEntityDraft {
            public typealias Entity = Todo
            public var id: Todo.ID? = nil

            public var status: Status
            public var priority: Priority?

            public init(
              id: Todo.ID? = nil,
              status: Status,
              priority: Priority? = nil
            ) {
              self.id = id
              self.status = status
              self.priority = priority
            }

            public init(_ entity: Todo) {
              self.id = entity.id
              self.status = entity.status
              self.priority = entity.priority
            }

            public var instantAssignments: [InstantAttributeAssignment<Todo>] {
              [
              InstantAttributeAssignment<Todo>(
                name: "status",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "status"
                  })?.id
                  ?? Todo.instantNamespace + "/status",
                value: self.status.instantValue
              ),
              InstantAttributeAssignment<Todo>(
                name: "priority",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "priority"
                  })?.id
                  ?? Todo.instantNamespace + "/priority",
                value: self.priority.instantValue
              )
              ]
            }
          }
        }
        """
      }
    }

    func testInstantWireRequiresScalarWireTypeDiagnostic() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>

          @InstantWire("string")
          var status: Status
        }
        """
      } diagnostics: {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>

          @InstantWire("string")
          ┬─────────────────────
          ╰─ 🛑 @InstantWire requires a scalar wire type, for example @InstantWire(.string).
          var status: Status
        }
        """
      }
    }

    func testInstantRelationRequiresRefAttributeDiagnostic() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>

          @InstantRelation(reverse: "todos")
          var title: String
        }
        """
      } diagnostics: {
        """
        @InstantEntity
        ╰─ 🛑 Stored property 'title' uses @InstantRelation, but it is not an Instant ref attribute.
        struct Todo {
          var id: InstantID<Todo>

          @InstantRelation(reverse: "todos")
          var title: String
        }
        """
      }
    }

    func testInstantRelationRequiresSwiftIdentifierReverseNameDiagnostic() {
      assertMacro {
        #"""
        @InstantEntity
        struct Post {
          var id: InstantID<Post>

          @InstantRelation(reverse: "po\"sts")
          var author: InstantID<User>
        }
        """#
      } diagnostics: {
        #"""
        @InstantEntity
        ╰─ 🛑 Reverse relation name 'po"sts' is not a valid Swift member name for @InstantRelation.
        struct Post {
          var id: InstantID<Post>

          @InstantRelation(reverse: "po\"sts")
          var author: InstantID<User>
        }
        """#
      }
    }

    func testInstantRelationRequiresUniqueReverseRelationNames() {
      assertMacro {
        """
        @InstantEntity
        struct Post {
          var id: InstantID<Post>

          @InstantRelation(reverse: "posts")
          var author: InstantID<User>

          @InstantRelation(reverse: "posts")
          var editor: InstantID<User>
        }
        """
      } diagnostics: {
        """
        @InstantEntity
        ╰─ 🛑 Reverse relation name 'posts' is used by more than one @InstantRelation on this entity.
        struct Post {
          var id: InstantID<Post>

          @InstantRelation(reverse: "posts")
          var author: InstantID<User>

          @InstantRelation(reverse: "posts")
          var editor: InstantID<User>
        }
        """
      }
    }

    func testInstantRelationRejectsGeneratedMemberCollision() {
      assertMacro {
        """
        @InstantEntity
        struct Post {
          var id: InstantID<Post>
          var posts: String

          @InstantRelation(reverse: "posts")
          var author: InstantID<User>
        }
        """
      } diagnostics: {
        """
        @InstantEntity
        ╰─ 🛑 Reverse relation name 'posts' collides with a generated @InstantEntity member.
        struct Post {
          var id: InstantID<Post>
          var posts: String

          @InstantRelation(reverse: "posts")
          var author: InstantID<User>
        }
        """
      }
    }

    func testInstantRelationRejectsReservedReverseRelationName() {
      assertMacro {
        """
        @InstantEntity
        struct Post {
          var id: InstantID<Post>

          @InstantRelation(reverse: "query")
          var author: InstantID<User>
        }
        """
      } diagnostics: {
        """
        @InstantEntity
        ╰─ 🛑 Reverse relation name 'query' is reserved by @InstantEntity generated helpers.
        struct Post {
          var id: InstantID<Post>

          @InstantRelation(reverse: "query")
          var author: InstantID<User>
        }
        """
      }
    }

    func testInstantRelationRequiresReverseNameDiagnostic() {
      assertMacro {
        """
        @InstantEntity
        struct Post {
          var id: InstantID<Post>

          @InstantRelation(reverse: "")
          var author: InstantID<User>
        }
        """
      } diagnostics: {
        """
        @InstantEntity
        struct Post {
          var id: InstantID<Post>

          @InstantRelation(reverse: "")
          ┬────────────────────────────
          ╰─ 🛑 @InstantRelation requires a non-empty string literal reverse name, for example @InstantRelation(reverse: "posts").
          var author: InstantID<User>
        }
        """
      }
    }

    func testGeneratedSchemaHelpersUseManualAttributePaths() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var title: String

          static let title = InstantAttributePath<Todo, String>(
            "title",
            attributeID: "todos/body"
          )
        }
        """
      } expansion: {
        """
        struct Todo {
          var id: InstantID<Todo>
          var title: String

          static let title = InstantAttributePath<Todo, String>(
            "title",
            attributeID: "todos/body"
          )

          public static var instantNamespace: String {
            "todos"
          }

          public static var instantAttributes: [InstantAttribute] {
            [
                InstantAttribute(
                  id: Todo.title.attributeID,
                  namespace: Todo.instantNamespace,
                  name: Todo.title.name,
                  valueType: .string,
                  isRequired: true,
                  isIndexed: true
                )
            ]
          }

          public struct Draft: InstantEntityDraft {
            public typealias Entity = Todo
            public var id: Todo.ID? = nil

            public var title: String

            public init(
              id: Todo.ID? = nil,
              title: String
            ) {
              self.id = id
              self.title = title
            }

            public init(_ entity: Todo) {
              self.id = entity.id
              self.title = entity.title
            }

            public var instantAssignments: [InstantAttributeAssignment<Todo>] {
              [
              InstantAttributeAssignment<Todo>(
                name: "title",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "title"
                  })?.id
                  ?? Todo.instantNamespace + "/title",
                value: self.title.instantValue
              )
              ]
            }
          }
        }
        """
      }
    }

    func testGeneratedSchemaHelpersRespectManualReverseRelationTokens() {
      assertMacro {
        """
        @InstantEntity
        struct Post {
          var id: InstantID<Post>

          @InstantRelation(reverse: "posts")
          var author: InstantID<User>

          static let posts = InstantReverseRelation<User, Post>("posts")
        }
        """
      } expansion: {
        """
        struct Post {
          var id: InstantID<Post>
          var author: InstantID<User>

          static let posts = InstantReverseRelation<User, Post>("posts")

          public static var instantNamespace: String {
            "posts"
          }

          public static let author = InstantAttributePath<Post, InstantID<User>>("author")

          public static var instantAttributes: [InstantAttribute] {
            [
                InstantAttribute(
                  id: Post.author.attributeID,
                  namespace: Post.instantNamespace,
                  name: Post.author.name,
                  valueType: .ref,
                  isRequired: true,
                  isIndexed: true,
                  isUnique: false,
                  forwardIdentity: Post.author.attributeID,
                  reverseIdentity: User.instantNamespace + "/posts",
                  primaryKey: false,
                  linkNamespace: User.instantNamespace
                )
            ]
          }

          public struct Draft: InstantEntityDraft {
            public typealias Entity = Post
            public var id: Post.ID? = nil

            public var author: InstantID<User>

            public init(
              id: Post.ID? = nil,
              author: InstantID<User>
            ) {
              self.id = id
              self.author = author
            }

            public init(_ entity: Post) {
              self.id = entity.id
              self.author = entity.author
            }

            public var instantAssignments: [InstantAttributeAssignment<Post>] {
              [
              InstantAttributeAssignment<Post>(
                name: "author",
                attributeID: Post.instantAttributes
                  .first(where: {
                    $0.name == "author"
                  })?.id
                  ?? Post.instantNamespace + "/author",
                value: self.author.instantValue
              )
              ]
            }
          }
        }
        """
      }
    }

    func testManualInstantAttributesSkipReverseRelationWithoutAttributePath() {
      assertMacro {
        """
        @InstantEntity
        struct Post {
          var id: InstantID<Post>

          @InstantRelation(reverse: "posts")
          var author: InstantID<User>

          static let instantAttributes = [
            InstantAttribute(
              id: "posts/author",
              namespace: Post.instantNamespace,
              name: "author",
              valueType: .ref,
              forwardIdentity: "posts/author",
              reverseIdentity: User.instantNamespace + "/posts",
              linkNamespace: User.instantNamespace
            )
          ]
        }
        """
      } expansion: {
        """
        struct Post {
          var id: InstantID<Post>
          var author: InstantID<User>

          static let instantAttributes = [
            InstantAttribute(
              id: "posts/author",
              namespace: Post.instantNamespace,
              name: "author",
              valueType: .ref,
              forwardIdentity: "posts/author",
              reverseIdentity: User.instantNamespace + "/posts",
              linkNamespace: User.instantNamespace
            )
          ]

          public static var instantNamespace: String {
            "posts"
          }

          public struct Draft: InstantEntityDraft {
            public typealias Entity = Post
            public var id: Post.ID? = nil


            public init(
              id: Post.ID? = nil
            ) {
              self.id = id
            }

            public init(_ entity: Post) {
              self.id = entity.id
            }

            public var instantAssignments: [InstantAttributeAssignment<Post>] {
              [

              ]
            }
          }
        }
        """
      }
    }

    func testGeneratedSchemaHelpersRespectManualDeclarations() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var text: String

          static let text = InstantAttributePath<Todo, String>(
            "text",
            attributeID: "todos/body"
          )

          static let instantAttributes: [InstantAttribute] = []
        }
        """
      } expansion: {
        """
        struct Todo {
          var id: InstantID<Todo>
          var text: String

          static let text = InstantAttributePath<Todo, String>(
            "text",
            attributeID: "todos/body"
          )

          static let instantAttributes: [InstantAttribute] = []

          public static var instantNamespace: String {
            "todos"
          }

          public struct Draft: InstantEntityDraft {
            public typealias Entity = Todo
            public var id: Todo.ID? = nil

            public var text: String

            public init(
              id: Todo.ID? = nil,
              text: String
            ) {
              self.id = id
              self.text = text
            }

            public init(_ entity: Todo) {
              self.id = entity.id
              self.text = entity.text
            }

            public var instantAssignments: [InstantAttributeAssignment<Todo>] {
              [
              InstantAttributeAssignment<Todo>(
                name: "text",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "text"
                  })?.id
                  ?? Todo.instantNamespace + "/text",
                value: self.text.instantValue
              )
              ]
            }
          }
        }
        """
      }
    }

    func testManualInstantAttributesExcludeManagedFieldsFromDrafts() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var title: String
          var serverManaged = "server"

          static let title = InstantAttributePath<Todo, String>("title")
          static let serverManaged = "local-only"
          static let instantAttributes = [
            InstantAttribute(
              id: Todo.title.attributeID,
              namespace: Todo.instantNamespace,
              name: Todo.title.name,
              valueType: .string
            )
          ]
        }
        """
      } expansion: {
        """
        struct Todo {
          var id: InstantID<Todo>
          var title: String
          var serverManaged = "server"

          static let title = InstantAttributePath<Todo, String>("title")
          static let serverManaged = "local-only"
          static let instantAttributes = [
            InstantAttribute(
              id: Todo.title.attributeID,
              namespace: Todo.instantNamespace,
              name: Todo.title.name,
              valueType: .string
            )
          ]

          public static var instantNamespace: String {
            "todos"
          }

          public struct Draft: InstantEntityDraft {
            public typealias Entity = Todo
            public var id: Todo.ID? = nil

            public var title: String

            public init(
              id: Todo.ID? = nil,
              title: String
            ) {
              self.id = id
              self.title = title
            }

            public init(_ entity: Todo) {
              self.id = entity.id
              self.title = entity.title
            }

            public var instantAssignments: [InstantAttributeAssignment<Todo>] {
              [
              InstantAttributeAssignment<Todo>(
                name: "title",
                attributeID: Todo.instantAttributes
                  .first(where: {
                    $0.name == "title"
                  })?.id
                  ?? Todo.instantNamespace + "/title",
                value: self.title.instantValue
              )
              ]
            }
          }
        }
        """
      }
    }

    func testReservedGeneratedSchemaHelperNameDiagnostic() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var query: String
        }
        """
      } diagnostics: {
        """
        @InstantEntity
        ╰─ 🛑 Stored property 'query' uses a name reserved by @InstantEntity generated helpers.
        struct Todo {
          var id: InstantID<Todo>
          var query: String
        }
        """
      } expansion: {
        """

        """
      }
    }

    func testInferredDraftPropertyDiagnostic() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var tags = ["swift"]
        }
        """
      } diagnostics: {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var tags = ["swift"]
              ┬───
              ╰─ 🛑 Stored property 'tags' needs an explicit type annotation for @InstantEntity draft generation.
        }
        """
      }
    }

    func testMultiBindingDraftPropertyDiagnostic() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var count = 0, title = "Untitled"
        }
        """
      } diagnostics: {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var count = 0, title = "Untitled"
          ┬────────────────────────────────
          ╰─ 🛑 @InstantEntity draft generation requires one stored property per var declaration.
        }
        """
      }
    }

    func testRedundantNamespaceDiagnostic() {
      assertMacro {
        """
        @InstantEntity("todos")
        struct Todo {
        }
        """
      } diagnostics: {
        """
        @InstantEntity("todos")
        ┬──────────────────────
        ╰─ ⚠️ @InstantEntity("todos") is redundant; omit the argument to use the default namespace.
        struct Todo {
        }
        """
      } expansion: {
        """
        struct Todo {

            public static var instantNamespace: String {
              "todos"
            }

            public static var instantAttributes: [InstantAttribute] {
              [

              ]
            }
        }
        """
      }
    }

    func testUnsupportedNamespaceArgumentDiagnostic() {
      assertMacro {
        """
        @InstantEntity(namespace)
        struct Todo {
        }
        """
      } diagnostics: {
        """
        @InstantEntity(namespace)
        ┬────────────────────────
        ╰─ 🛑 @InstantEntity namespace overrides must be string literals.
        struct Todo {
        }
        """
      } expansion: {
        """

        """
      }
    }
  }
#endif
