#if os(macOS)
  import InstantSwiftDataMacros
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
          #"@InstantEntity("todos") is redundant; omit the argument to use the default namespace."#
        )
      )
    }

    private func expand(_ source: String) -> (expanded: String, diagnostics: [String]) {
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
        context.diagnostics.map(\.message)
      )
    }
  }
#endif
