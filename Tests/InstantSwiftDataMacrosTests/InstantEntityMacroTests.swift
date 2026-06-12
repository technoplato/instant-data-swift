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
