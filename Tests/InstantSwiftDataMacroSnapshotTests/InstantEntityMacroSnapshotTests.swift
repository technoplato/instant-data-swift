#if os(macOS)
  import InstantSwiftDataMacros
  import MacroTesting
  import Testing

  @Suite
  struct InstantEntityMacroSnapshotTests {
    @Test
    func defaultNamespace() {
      assertInstantEntityMacro {
        """
        @InstantEntity
        struct Todo {
        }
        """
      }
    }

    @Test
    func defaultPluralization() {
      assertInstantEntityMacro {
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
      assertInstantEntityMacro {
        """
        @InstantEntity("people")
        struct Person {
        }
        """
      }
    }

    @Test
    func generatedDraft() {
      assertInstantEntityMacro {
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
      }
    }

    @Test
    func generatedDraftRequiresInstantPrimaryKey() {
      assertInstantEntityMacro {
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
      }
    }

    @Test
    func generatedDraftAcceptsInstantPrimaryKeyAliases() {
      assertInstantEntityMacro {
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
      }
    }

    @Test
    func generatedSchemaHelpers() {
      assertInstantEntityMacro {
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
        }
        """
      }
    }

    @Test
    func inferredDraftPropertyDiagnostic() {
      assertInstantEntityMacro {
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
      assertInstantEntityMacro {
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
      assertInstantEntityMacro {
        """
        @InstantEntity("todos")
        struct Todo {
        }
        """
      }
    }

    @Test
    func unsupportedNamespaceArgumentDiagnostic() {
      assertInstantEntityMacro {
        """
        @InstantEntity(namespace)
        struct Todo {
        }
        """
      }
    }

    private func assertInstantEntityMacro(
      _ originalSource: () throws -> String,
      fileID: StaticString = #fileID,
      file filePath: StaticString = #filePath,
      function: StaticString = #function,
      line: UInt = #line,
      column: UInt = #column
    ) {
      withMacroTesting(
        record: .failed,
        macros: ["InstantEntity": InstantEntityMacro.self]
      ) {
        assertMacro(
          of: originalSource,
          fileID: fileID,
          file: filePath,
          function: function,
          line: line,
          column: column
        )
      }
    }
  }
#endif
