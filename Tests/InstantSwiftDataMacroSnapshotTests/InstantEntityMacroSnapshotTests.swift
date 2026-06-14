#if os(macOS)
  import InstantSwiftDataMacros
  import MacroTesting
  import Testing

  @Suite(
    .macros(
      ["InstantEntity": InstantEntityMacro.self],
      record: .failed
    )
  )
  struct InstantEntityMacroSnapshotTests {
    @Test
    func defaultNamespace() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
        }
        """
      }
    }

    @Test
    func defaultPluralization() {
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
      }
    }

    @Test
    func manualNamespace() {
      assertMacro {
        """
        @InstantEntity("people")
        struct Person {
        }
        """
      }
    }

    @Test
    func generatedDraft() {
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
          let createdBy: String
          let metadata = ["local"]
          let ignoredA = 1, ignoredB = 2

          static let ignored = InstantAttributePath<Todo, String>("ignored")

          var computed: String {
            text
          }
        }
        """
      }
    }

    @Test
    func inferredDraftPropertyDiagnostic() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var tags = ["swift"]
        }
        """
      }
    }

    @Test
    func multiBindingDraftPropertyDiagnostic() {
      assertMacro {
        """
        @InstantEntity
        struct Todo {
          var id: InstantID<Todo>
          var count = 0, title = "Untitled"
        }
        """
      }
    }

    @Test
    func redundantNamespaceDiagnostic() {
      assertMacro {
        """
        @InstantEntity("todos")
        struct Todo {
        }
        """
      }
    }

    @Test
    func unsupportedNamespaceArgumentDiagnostic() {
      assertMacro {
        """
        @InstantEntity(namespace)
        struct Todo {
        }
        """
      }
    }
  }
#endif
