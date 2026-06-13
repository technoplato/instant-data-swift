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
