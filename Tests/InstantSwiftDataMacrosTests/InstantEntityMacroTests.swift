#if os(macOS)
  import InstantSwiftDataMacros
  import SwiftDiagnostics
  import SwiftParser
  import SwiftSyntax
  import SwiftSyntaxMacroExpansion
  import SwiftSyntaxMacros
  import Testing

  @Suite(.serialized)
  struct InstantEntityMacroTests {
    @Test
    func defaultNamespace() {
      let result = expand(
        """
        @InstantEntity
        struct Todo {
        }
        """
      )

      #expect(result.expanded.contains(#"public static var instantNamespace: String"#))
      #expect(result.expanded.contains(#""todos""#))
      #expect(result.diagnostics.isEmpty)
    }

    @Test
    func defaultPluralization() {
      let result = expand(
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
      )

      #expect(result.expanded.contains(#""categories""#))
      #expect(result.expanded.contains(#""boxes""#))
      #expect(result.expanded.contains(#""brushes""#))
      #expect(result.diagnostics.isEmpty)
    }

    @Test
    func manualNamespace() {
      let result = expand(
        """
        @InstantEntity("people")
        struct Person {
        }
        """
      )

      #expect(result.expanded.contains(#""people""#))
      #expect(result.diagnostics.isEmpty)
    }

    @Test
    func generatedDraft() {
      let result = expand(
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
      )

      #expect(result.expanded.contains("public struct Draft: InstantEntityDraft"))
      #expect(!result.expanded.contains("public struct Draft: Identifiable"))
      #expect(!result.expanded.contains("public struct Draft: InstantEntityDraft, Identifiable"))
      #expect(result.expanded.contains("public typealias Entity = Todo"))
      #expect(result.expanded.contains("public var id: Todo.ID? = nil"))
      #expect(result.expanded.contains("public var text: String"))
      #expect(result.expanded.contains("public var isCompleted: Bool"))
      #expect(result.expanded.contains("public var isFlagged: Bool"))
      #expect(result.expanded.contains("public var notes: String?"))
      #expect(result.expanded.contains("public var category: Optional<String>"))
      #expect(result.expanded.contains("public var owner: Swift.Optional<String>"))
      #expect(result.expanded.contains("isCompleted: Bool = false"))
      #expect(result.expanded.contains("isFlagged: Bool = false"))
      #expect(result.expanded.contains("notes: String? = nil"))
      #expect(result.expanded.contains("category: Optional<String> = nil"))
      #expect(result.expanded.contains("owner: Swift.Optional<String> = nil"))
      #expect(result.expanded.contains("public init(_ entity: Todo)"))
      #expect(result.expanded.contains("self.id = entity.id"))
      #expect(result.expanded.contains("self.text = entity.text"))
      #expect(result.expanded.contains("self.createdAt = entity.createdAt"))
      #expect(result.expanded.contains(#"name: "text""#))
      #expect(result.expanded.contains(#"name: "notes""#))
      #expect(result.expanded.contains(#"name: "category""#))
      #expect(result.expanded.contains(#"name: "owner""#))
      #expect(result.expanded.contains("attributeID: Todo.instantAttributes"))
      #expect(result.expanded.contains(#"$0.name == "text""#))
      #expect(result.expanded.contains(#"?? Todo.instantNamespace + "/text""#))
      #expect(result.expanded.contains("value: self.text.instantValue"))
      #expect(!result.expanded.contains(#"name: "id""#))
      #expect(!result.expanded.contains("value: self.id.instantValue"))
      #expect(!result.expanded.contains(#"public var localTags"#))
      #expect(!result.expanded.contains(#"name: "localTags""#))
      #expect(!result.expanded.contains(#"self.localTags"#))
      #expect(!result.expanded.contains(#"public var createdBy"#))
      #expect(!result.expanded.contains(#"name: "createdBy""#))
      #expect(!result.expanded.contains(#"self.createdBy"#))
      #expect(!result.expanded.contains(#"public var metadata"#))
      #expect(!result.expanded.contains(#"public var ignoredA"#))
      #expect(!result.expanded.contains(#"public var ignoredB"#))
      #expect(!result.expanded.contains(#"name: "ignored""#))
      #expect(!result.expanded.contains(#"name: "computed""#))
      #expect(result.diagnostics.isEmpty)
    }

    @Test
    func generatedSchemaHelpers() {
      let result = expand(
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
      )

      #expect(result.expanded.contains(#"public static let text = InstantAttributePath<Todo, String>("text")"#))
      #expect(
        result.expanded.contains(
          #"public static let isCompleted = InstantAttributePath<Todo, Bool>("isCompleted")"#
        )
      )
      #expect(result.expanded.contains(#"public static let count = InstantAttributePath<Todo, Int>("count")"#))
      #expect(result.expanded.contains(#"public static let dueAt = InstantAttributePath<Todo, Date?>("dueAt")"#))
      #expect(
        result.expanded.contains(
          #"public static let metadata = InstantAttributePath<Todo, JSONValue>("metadata")"#
        )
      )
      #expect(
        result.expanded.contains(
          #"public static let owner = InstantAttributePath<Todo, InstantID<User>>("owner")"#
        )
      )
      #expect(!result.expanded.contains("InstantAttributePath<Todo, [String]>"))

      let schemaHelpers = result.expanded.components(separatedBy: "public struct Draft").first ?? ""
      #expect(result.expanded.contains("public static var instantAttributes: [InstantAttribute]"))
      #expect(schemaHelpers.contains("id: Todo.text.attributeID"))
      #expect(schemaHelpers.contains("name: Todo.text.name"))
      #expect(schemaHelpers.contains("valueType: .string"))
      #expect(schemaHelpers.contains("id: Todo.isCompleted.attributeID"))
      #expect(schemaHelpers.contains("valueType: .boolean"))
      #expect(schemaHelpers.contains("id: Todo.count.attributeID"))
      #expect(schemaHelpers.contains("valueType: .number"))
      #expect(schemaHelpers.contains("id: Todo.dueAt.attributeID"))
      #expect(schemaHelpers.contains("valueType: .date"))
      #expect(schemaHelpers.contains("isRequired: false"))
      #expect(schemaHelpers.contains("id: Todo.metadata.attributeID"))
      #expect(schemaHelpers.contains("valueType: .json"))
      #expect(schemaHelpers.contains("id: Todo.owner.attributeID"))
      #expect(schemaHelpers.contains("valueType: .ref"))
      #expect(schemaHelpers.contains("linkNamespace: User.instantNamespace"))
      #expect(!schemaHelpers.contains(#"name: "unsupported""#))
      #expect(result.diagnostics.isEmpty)
    }

    @Test
    func generatedSchemaHelpersUseManualAttributePaths() {
      let result = expand(
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
      )

      #expect(result.expanded.components(separatedBy: "static let title =").count - 1 == 1)
      #expect(result.expanded.contains("id: Todo.title.attributeID"))
      #expect(result.expanded.contains("name: Todo.title.name"))
      #expect(result.diagnostics.isEmpty)
    }

    @Test
    func generatedSchemaHelpersRespectManualDeclarations() {
      let result = expand(
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
      )

      #expect(result.expanded.components(separatedBy: "static let text =").count - 1 == 1)
      #expect(result.expanded.components(separatedBy: "static let instantAttributes").count == 2)
      #expect(!result.expanded.contains("public static var instantAttributes"))
      #expect(result.diagnostics.isEmpty)
    }

    @Test
    func reservedGeneratedSchemaHelperNameDiagnostic() {
      let result = expand(
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var query: String
        }
        """
      )

      #expect(!result.expanded.contains("public static let query"))
      #expect(
        result.diagnostics.contains(
          MacroDiagnostic(
            message: "Stored property 'query' uses a name reserved by @InstantEntity generated helpers.",
            severity: .error
          )
        )
      )
      #expect(result.diagnostics.count == 1)
    }

    @Test
    func inferredDraftPropertyDiagnostic() {
      let result = expand(
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var tags = ["swift"]
        }
        """
      )

      #expect(
        result.diagnostics.contains(
          MacroDiagnostic(
            message: "Stored property 'tags' needs an explicit type annotation for @InstantEntity draft generation.",
            severity: .error
          )
        )
      )
      #expect(result.diagnostics.count == 1)
    }

    @Test
    func multiBindingDraftPropertyDiagnostic() {
      let result = expand(
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var count = 0, title = "Untitled"
        }
        """
      )

      #expect(
        result.diagnostics.contains(
          MacroDiagnostic(
            message: "@InstantEntity draft generation requires one stored property per var declaration.",
            severity: .error
          )
        )
      )
      #expect(result.diagnostics.count == 1)
    }

    @Test
    func redundantNamespaceDiagnostic() {
      let result = expand(
        """
        @InstantEntity("todos")
        struct Todo {
        }
        """
      )

      #expect(result.expanded.contains(#""todos""#))
      #expect(
        result.diagnostics.contains(
          MacroDiagnostic(
            message: #"@InstantEntity("todos") is redundant; omit the argument to use the default namespace."#,
            severity: .warning
          )
        )
      )
    }

    @Test
    func unsupportedNamespaceArgumentDiagnostic() {
      let result = expand(
        """
        @InstantEntity(namespace)
        struct Todo {
        }
        """
      )

      #expect(!result.expanded.contains(#"public static var instantNamespace: String"#))
      #expect(
        result.diagnostics.contains(
          MacroDiagnostic(
            message: "@InstantEntity namespace overrides must be string literals.",
            severity: .error
          )
        )
      )
    }

    private func expand(_ source: String) -> (expanded: String, diagnostics: [MacroDiagnostic]) {
      let sourceFile = Parser.parse(source: source)
      let context = BasicMacroExpansionContext(
        sourceFiles: [
          sourceFile: .init(moduleName: "InstantSwiftDataMacrosTests", fullFilePath: "test.swift")
        ]
      )
      let expanded = sourceFile.expand(
        macros: ["InstantEntity": InstantEntityMacro.self],
        contextGenerator: { syntax in
          BasicMacroExpansionContext(
            sharingWith: context,
            lexicalContext: syntax.allMacroLexicalContexts()
          )
        },
        indentationWidth: .spaces(2)
      )

      return (
        expanded.description,
        context.diagnostics.map(MacroDiagnostic.init)
      )
    }
  }

  private struct MacroDiagnostic: Hashable {
    var message: String
    var severity: DiagnosticSeverity

    init(message: String, severity: DiagnosticSeverity) {
      self.message = message
      self.severity = severity
    }

    init(_ diagnostic: Diagnostic) {
      self.init(
        message: diagnostic.message,
        severity: diagnostic.diagMessage.severity
      )
    }
  }
#endif
