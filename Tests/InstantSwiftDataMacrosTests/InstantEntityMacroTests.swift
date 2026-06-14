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
      #expect(result.expanded.contains(#"attributeID: Todo.instantNamespace + "/text""#))
      #expect(result.expanded.contains("value: self.text.instantValue"))
      #expect(!result.expanded.contains(#"name: "id""#))
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
