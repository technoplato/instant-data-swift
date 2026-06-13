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
          var createdAt: Date

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
      #expect(result.expanded.contains("isCompleted: Bool = false"))
      #expect(result.expanded.contains("isFlagged: Bool = false"))
      #expect(result.expanded.contains("public init(_ entity: Todo)"))
      #expect(result.expanded.contains(#"name: "text""#))
      #expect(result.expanded.contains(#"attributeID: Todo.instantNamespace + "/text""#))
      #expect(result.expanded.contains("value: self.text.instantValue"))
      #expect(!result.expanded.contains(#"name: "id""#))
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
