import CustomDump
import InstantSwiftDataCore
import InstantSwiftDataSchema
import Testing

@Suite(.serialized)
struct TypeScriptPrinterTests {
  private static let linkedTodoDocument = InstantSchemaDocument(
    entities: [
      InstantEntitySchema(
        typeName: "Project",
        namespace: "projects",
        attributes: [
          InstantAttribute(
            id: "projects/title",
            namespace: "projects",
            name: "title",
            valueType: .string,
            isIndexed: true
          )
        ]
      ),
      InstantSchemaExamples.todos,
    ],
    links: [
      InstantLinkSchema(
        name: "projectsTodos",
        forward: InstantLinkEndpoint(
          namespace: "todos",
          cardinality: .one,
          label: "project",
          onDelete: .cascade
        ),
        reverse: InstantLinkEndpoint(
          namespace: "projects",
          cardinality: .many,
          label: "todos"
        ),
        isRequired: true
      )
    ]
  )

  private static let roomDocument = InstantSchemaDocument(
    entities: [InstantSchemaExamples.todos],
    rooms: [
      InstantRoomSchema(
        name: "chat",
        presence: InstantRoomPayloadSchema(
          attributes: [
            InstantAttribute(
              id: "rooms/chat/presence/name",
              namespace: "rooms/chat/presence",
              name: "name",
              valueType: .string
            ),
            InstantAttribute(
              id: "rooms/chat/presence/status",
              namespace: "rooms/chat/presence",
              name: "status",
              valueType: .string,
              isRequired: false
            ),
          ]
        ),
        topics: [
          InstantRoomTopicSchema(
            name: "sendEmoji",
            payload: InstantRoomPayloadSchema(
              attributes: [
                InstantAttribute(
                  id: "rooms/chat/topics/sendEmoji/emoji",
                  namespace: "rooms/chat/topics/sendEmoji",
                  name: "emoji",
                  valueType: .string
                )
              ]
            )
          )
        ]
      )
    ]
  )

  private static let upstreamCoreSchemaDocument = InstantSchemaDocument(
    entities: [
      InstantEntitySchema(
        typeName: "Birthday",
        namespace: "birthdays",
        attributes: [
          InstantAttribute(id: "birthdays/date", namespace: "birthdays", name: "date", valueType: .date),
          InstantAttribute(id: "birthdays/message", namespace: "birthdays", name: "message", valueType: .string),
          InstantAttribute(id: "birthdays/prizes", namespace: "birthdays", name: "prizes", valueType: .json),
        ]
      ),
      InstantEntitySchema(
        typeName: "Comment",
        namespace: "comments",
        attributes: [
          InstantAttribute(
            id: "comments/body",
            namespace: "comments",
            name: "body",
            valueType: .string,
            isIndexed: true
          ),
          InstantAttribute(id: "comments/likes", namespace: "comments", name: "likes", valueType: .number),
        ]
      ),
      InstantEntitySchema(
        typeName: "Post",
        namespace: "posts",
        attributes: [
          InstantAttribute(
            id: "posts/title",
            namespace: "posts",
            name: "title",
            valueType: .string,
            isRequired: false
          ),
          InstantAttribute(id: "posts/body", namespace: "posts", name: "body", valueType: .string),
        ]
      ),
      InstantEntitySchema(
        typeName: "User",
        namespace: "users",
        attributes: [
          InstantAttribute(id: "users/name", namespace: "users", name: "name", valueType: .string),
          InstantAttribute(
            id: "users/email",
            namespace: "users",
            name: "email",
            valueType: .string,
            isIndexed: true,
            isUnique: true
          ),
          InstantAttribute(
            id: "users/bio",
            namespace: "users",
            name: "bio",
            valueType: .string,
            isRequired: false
          ),
          InstantAttribute(id: "users/stuff", namespace: "users", name: "stuff", valueType: .json),
          InstantAttribute(id: "users/junk", namespace: "users", name: "junk", valueType: .any),
        ]
      ),
    ],
    links: [
      InstantLinkSchema(
        name: "friendships",
        forward: InstantLinkEndpoint(namespace: "users", cardinality: .many, label: "friends"),
        reverse: InstantLinkEndpoint(namespace: "users", cardinality: .many, label: "_friends")
      ),
      InstantLinkSchema(
        name: "postsComments",
        forward: InstantLinkEndpoint(namespace: "posts", cardinality: .many, label: "comments"),
        reverse: InstantLinkEndpoint(namespace: "comments", cardinality: .one, label: "post")
      ),
      InstantLinkSchema(
        name: "referrals",
        forward: InstantLinkEndpoint(namespace: "users", cardinality: .many, label: "referred"),
        reverse: InstantLinkEndpoint(namespace: "users", cardinality: .one, label: "referrer")
      ),
      InstantLinkSchema(
        name: "usersPosts",
        forward: InstantLinkEndpoint(namespace: "users", cardinality: .many, label: "posts"),
        reverse: InstantLinkEndpoint(namespace: "posts", cardinality: .one, label: "author")
      ),
    ],
    rooms: [
      InstantRoomSchema(
        name: "chat",
        presence: InstantRoomPayloadSchema(
          attributes: [
            InstantAttribute(
              id: "rooms/chat/presence/name",
              namespace: "rooms/chat/presence",
              name: "name",
              valueType: .string
            ),
            InstantAttribute(
              id: "rooms/chat/presence/status",
              namespace: "rooms/chat/presence",
              name: "status",
              valueType: .string
            ),
          ]
        ),
        topics: [
          InstantRoomTopicSchema(
            name: "sendEmoji",
            payload: InstantRoomPayloadSchema(
              attributes: [
                InstantAttribute(
                  id: "rooms/chat/topics/sendEmoji/emoji",
                  namespace: "rooms/chat/topics/sendEmoji",
                  name: "emoji",
                  valueType: .string
                )
              ]
            )
          )
        ]
      )
    ]
  )

  @Test
  func schemaPrinterEmitsTodoExample() throws {
    expectNoDifference(
      try TypeScriptSchemaPrinter().printSchema([InstantSchemaExamples.todos]),
      """
      import { i } from '@instantdb/core';

      export default i.schema({
        entities: {
          todos: i.entity({
            createdAt: i.date().indexed(),
            isCompleted: i.boolean().indexed(),
            text: i.string().indexed(),
          }),
        },
      });

      """
    )
  }

  @Test
  func schemaPrinterEmitsLinks() throws {
    expectNoDifference(
      try TypeScriptSchemaPrinter().printSchema(Self.linkedTodoDocument),
      """
      import { i } from '@instantdb/core';

      export default i.schema({
        entities: {
          projects: i.entity({
            title: i.string().indexed(),
          }),
          todos: i.entity({
            createdAt: i.date().indexed(),
            isCompleted: i.boolean().indexed(),
            text: i.string().indexed(),
          }),
        },
        links: {
          projectsTodos: {
            forward: {
              on: "todos",
              has: "one",
              label: "project",
              required: true,
              onDelete: "cascade",
            },
            reverse: {
              on: "projects",
              has: "many",
              label: "todos",
            },
          },
        },
      });

      """
    )
  }

  @Test
  func schemaPrinterEmitsOptionalAttributes() throws {
    let document = InstantSchemaDocument(
      entities: [
        InstantEntitySchema(
          typeName: "Profile",
          namespace: "profiles",
          attributes: [
            InstantAttribute(
              id: "profiles/bio",
              namespace: "profiles",
              name: "bio",
              valueType: .string,
              isRequired: false,
              isIndexed: true
            )
          ]
        )
      ]
    )

    expectNoDifference(
      try TypeScriptSchemaPrinter().printSchema(document),
      """
      import { i } from '@instantdb/core';

      export default i.schema({
        entities: {
          profiles: i.entity({
            bio: i.string().optional().indexed(),
          }),
        },
      });

      """
    )
  }

  @Test
  func schemaPrinterEmitsRooms() throws {
    expectNoDifference(
      try TypeScriptSchemaPrinter().printSchema(Self.roomDocument),
      """
      import { i } from '@instantdb/core';

      export default i.schema({
        entities: {
          todos: i.entity({
            createdAt: i.date().indexed(),
            isCompleted: i.boolean().indexed(),
            text: i.string().indexed(),
          }),
        },
        rooms: {
          chat: {
            presence: i.entity({
              name: i.string(),
              status: i.string().optional(),
            }),
            topics: {
              sendEmoji: i.entity({
                emoji: i.string(),
              }),
            },
          },
        },
      });

      """
    )
  }

  @Test
  func schemaParserRoundTripsGeneratedTodoExample() throws {
    let printed = try TypeScriptSchemaPrinter().printSchema([InstantSchemaExamples.todos])
    let parsed = try TypeScriptSchemaParser().parse(printed)

    expectNoDifference(
      parsed,
      [
        ParsedInstantEntitySchema(InstantSchemaExamples.todos)
      ]
    )
  }

  @Test
  func schemaParserRoundTripsGeneratedLinks() throws {
    let printed = try TypeScriptSchemaPrinter().printSchema(Self.linkedTodoDocument)
    let parsed = try TypeScriptSchemaParser().parseDocument(printed)

    expectNoDifference(
      parsed,
      ParsedInstantSchemaDocument(Self.linkedTodoDocument)
    )
  }

  @Test
  func schemaParserRoundTripsGeneratedRooms() throws {
    let printed = try TypeScriptSchemaPrinter().printSchema(Self.roomDocument)
    let parsed = try TypeScriptSchemaParser().parseDocument(printed)

    expectNoDifference(
      parsed,
      ParsedInstantSchemaDocument(Self.roomDocument)
    )
  }

  @Test
  func schemaParserRoundTripsUpstreamCoreSchemaShape() throws {
    let source =
      "upstream/instant/client/packages/core/__tests__/src/schema.test.ts runs without exception "
      + "and serializeSchema.test.ts ability to parse stringified schema into real schema object."
    let printed = try TypeScriptSchemaPrinter().printSchema(Self.upstreamCoreSchemaDocument)
    let parsed = try TypeScriptSchemaParser().parseDocument(printed)

    expectNoDifference(
      parsed,
      ParsedInstantSchemaDocument(Self.upstreamCoreSchemaDocument),
      source
    )
    expectNoDifference(
      parsed.entities.map(\.namespace),
      ["birthdays", "comments", "posts", "users"],
      source
    )
    expectNoDifference(
      parsed.links.map(\.name),
      ["friendships", "postsComments", "referrals", "usersPosts"],
      source
    )
    expectNoDifference(parsed.rooms.map(\.name), ["chat"], source)
  }

  @Test
  func schemaParserRoundTripsUnsortedRooms() throws {
    let document = InstantSchemaDocument(
      entities: [InstantSchemaExamples.todos],
      rooms: [
        InstantRoomSchema(
          name: "chat",
          presence: InstantRoomPayloadSchema(
            attributes: [
              InstantAttribute(
                id: "rooms/chat/presence/status",
                namespace: "rooms/chat/presence",
                name: "status",
                valueType: .string
              ),
              InstantAttribute(
                id: "rooms/chat/presence/name",
                namespace: "rooms/chat/presence",
                name: "name",
                valueType: .string
              ),
            ]
          ),
          topics: [
            InstantRoomTopicSchema(
              name: "zTopic",
              payload: InstantRoomPayloadSchema(
                attributes: [
                  InstantAttribute(
                    id: "rooms/chat/topics/zTopic/z",
                    namespace: "rooms/chat/topics/zTopic",
                    name: "z",
                    valueType: .string
                  )
                ]
              )
            ),
            InstantRoomTopicSchema(
              name: "aTopic",
              payload: InstantRoomPayloadSchema(
                attributes: [
                  InstantAttribute(
                    id: "rooms/chat/topics/aTopic/z",
                    namespace: "rooms/chat/topics/aTopic",
                    name: "z",
                    valueType: .string
                  ),
                  InstantAttribute(
                    id: "rooms/chat/topics/aTopic/a",
                    namespace: "rooms/chat/topics/aTopic",
                    name: "a",
                    valueType: .string
                  ),
                ]
              )
            ),
          ]
        )
      ]
    )

    let printed = try TypeScriptSchemaPrinter().printSchema(document)
    let parsed = try TypeScriptSchemaParser().parseDocument(printed)

    expectNoDifference(
      parsed,
      ParsedInstantSchemaDocument(document)
    )
  }

  @Test
  func schemaParserUsesLastTopLevelLinksValue() throws {
    let parsed = try TypeScriptSchemaParser().parseDocument(
      """
      export default i.schema({
        entities: {
          projects: i.entity({
            title: i.string().indexed(),
          }),
          todos: i.entity({
            text: i.string().indexed(),
          }),
        },
        links: {},
        links: {
          projectsTodos: {
            forward: {
              on: "todos",
              has: "one",
              label: "project",
            },
            reverse: {
              on: "projects",
              has: "many",
              label: "todos",
            },
          },
        },
      });
      """
    )

    expectNoDifference(
      parsed.links,
      [
        InstantLinkSchema(
          name: "projectsTodos",
          forward: InstantLinkEndpoint(
            namespace: "todos",
            cardinality: .one,
            label: "project"
          ),
          reverse: InstantLinkEndpoint(
            namespace: "projects",
            cardinality: .many,
            label: "todos"
          )
        )
      ]
    )
  }

  @Test
  func schemaParserUsesLastTopLevelEntitiesValue() throws {
    let parsed = try TypeScriptSchemaParser().parse(
      """
      export default i.schema({
        entities: {
          ignored: i.entity({
            name: i.string(),
          }),
        },
        entities: {
          todos: i.entity({
            createdAt: i.date().indexed(),
            isCompleted: i.boolean().indexed(),
            text: i.string().indexed(),
          }),
        },
      });
      """
    )

    expectNoDifference(
      parsed,
      [
        ParsedInstantEntitySchema(InstantSchemaExamples.todos)
      ]
    )
  }

  @Test
  func linkSchemaDerivesCoreRefAttributes() {
    expectNoDifference(
      Self.linkedTodoDocument.links.flatMap(\.attributes),
      [
        InstantAttribute(
          id: "todos/project",
          namespace: "todos",
          name: "project",
          valueType: .ref,
          cardinality: .one,
          isIndexed: true,
          forwardIdentity: "todos/project",
          reverseIdentity: "projects/todos",
          linkNamespace: "projects",
          onDelete: .cascade
        )
      ]
    )
  }

  @Test
  func schemaPrinterRejectsCascadeOnManyLinks() {
    let document = InstantSchemaDocument(
      entities: [InstantSchemaExamples.todos],
      links: [
        InstantLinkSchema(
          name: "badCascade",
          forward: InstantLinkEndpoint(
            namespace: "todos",
            cardinality: .many,
            label: "children",
            onDelete: .cascade
          ),
          reverse: InstantLinkEndpoint(
            namespace: "todos",
            cardinality: .many,
            label: "parents"
          )
        )
      ]
    )

    do {
      _ = try TypeScriptSchemaPrinter().printSchema(document)
      #expect(Bool(false), "Expected printer to reject cascade on has: many links.")
    } catch let error as InstantSchemaValidationError {
      expectNoDifference(
        error,
        .invalidLinkCascadeEndpoint(
          link: "badCascade",
          endpoint: "forward",
          cardinality: .many
        )
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func schemaPrinterRejectsStandaloneRefAttributes() {
    let document = InstantSchemaDocument(
      entities: [
        InstantEntitySchema(
          typeName: "Comment",
          namespace: "comments",
          attributes: [
            InstantAttribute(
              id: "comments/book",
              namespace: "comments",
              name: "book",
              valueType: .ref
            )
          ]
        )
      ]
    )

    do {
      _ = try TypeScriptSchemaPrinter().printSchema(document)
      #expect(Bool(false), "Expected printer to reject standalone ref attributes.")
    } catch let error as InstantSchemaValidationError {
      expectNoDifference(
        error,
        .unsupportedRefAttribute(namespace: "comments", name: "book")
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func linkSchemaDerivesReverseCascadeMetadata() {
    let link = InstantLinkSchema(
      name: "usersProfiles",
      forward: InstantLinkEndpoint(
        namespace: "users",
        cardinality: .one,
        label: "profile"
      ),
      reverse: InstantLinkEndpoint(
        namespace: "profiles",
        cardinality: .one,
        label: "user",
        onDelete: .cascade
      )
    )

    expectNoDifference(
      link.attributes,
      [
        InstantAttribute(
          id: "users/profile",
          namespace: "users",
          name: "profile",
          valueType: .ref,
          isRequired: false,
          cardinality: .one,
          isIndexed: true,
          isUnique: true,
          forwardIdentity: "users/profile",
          reverseIdentity: "profiles/user",
          linkNamespace: "profiles",
          onDeleteReverse: .cascade
        )
      ]
    )
  }

  @Test
  func linkSchemaDerivesOptionalCoreRefAttributes() {
    let link = InstantLinkSchema(
      name: "postsAuthors",
      forward: InstantLinkEndpoint(
        namespace: "posts",
        cardinality: .one,
        label: "author"
      ),
      reverse: InstantLinkEndpoint(
        namespace: "profiles",
        cardinality: .many,
        label: "posts"
      ),
      isRequired: false
    )

    expectNoDifference(
      link.attributes,
      [
        InstantAttribute(
          id: "posts/author",
          namespace: "posts",
          name: "author",
          valueType: .ref,
          isRequired: false,
          cardinality: .one,
          isIndexed: true,
          forwardIdentity: "posts/author",
          reverseIdentity: "profiles/posts",
          linkNamespace: "profiles"
        )
      ]
    )
  }

  @Test
  func schemaParserSupportsQuotedKeysAndAttributeModifiers() throws {
    let parsed = try TypeScriptSchemaParser().parse(
      """
      import { i } from '@instantdb/core';

      export default i.schema({
        entities: {
          "blog-posts": i.entity({
            "published-at": i.date().indexed(),
            slug: i.string().unique().indexed(),
            summary: i.string().optional().indexed(),
            metadata: i.json(),
          }),
        },
      });

      """
    )

    expectNoDifference(
      parsed,
      [
        ParsedInstantEntitySchema(
          namespace: "blog-posts",
          attributes: [
            InstantAttribute(
              id: "blog-posts/metadata",
              namespace: "blog-posts",
              name: "metadata",
              valueType: .json
            ),
            InstantAttribute(
              id: "blog-posts/published-at",
              namespace: "blog-posts",
              name: "published-at",
              valueType: .date,
              isIndexed: true
            ),
            InstantAttribute(
              id: "blog-posts/slug",
              namespace: "blog-posts",
              name: "slug",
              valueType: .string,
              isIndexed: true,
              isUnique: true
            ),
            InstantAttribute(
              id: "blog-posts/summary",
              namespace: "blog-posts",
              name: "summary",
              valueType: .string,
              isRequired: false,
              isIndexed: true
            ),
          ]
        )
      ]
    )
  }

  @Test
  func schemaParserRejectsUnsupportedAttributeExpression() {
    do {
      _ = try TypeScriptSchemaParser().parse(
        """
        export default i.schema({
          entities: {
            todos: i.entity({
              text: i.custom(),
            }),
          },
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject unsupported attribute expressions.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(
        error,
        .unsupportedAttributeExpression(
          namespace: "todos",
          attribute: "text",
          expression: "i.custom()"
        )
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func schemaParserRejectsUnsupportedEntityExpression() {
    do {
      _ = try TypeScriptSchemaParser().parse(
        """
        export default i.schema({
          entities: {
            todos: i.entityLoose({
              text: i.string().indexed(),
            }),
          },
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject unsupported entity expressions.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(
        error,
        .unsupportedEntityExpression(
          namespace: "todos",
          expression: """
            i.entityLoose({
                  text: i.string().indexed(),
                })
            """
            .trimmingCharacters(in: .whitespacesAndNewlines)
        )
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func schemaParserRejectsUnsupportedAttributeModifiers() {
    do {
      _ = try TypeScriptSchemaParser().parse(
        """
        export default i.schema({
          entities: {
            todos: i.entity({
              text: i.string().clientRequired().indexed(),
            }),
          },
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject unsupported attribute modifiers.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(
        error,
        .unsupportedAttributeExpression(
          namespace: "todos",
          attribute: "text",
          expression: "i.string().clientRequired().indexed()"
        )
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func schemaParserIgnoresCommentsInObjectTrivia() throws {
    let parsed = try TypeScriptSchemaParser().parse(
      """
      // This file calls i.schema below.
      export default i.schema({
        entities: {
          // The generated todo entity.
          todos: i.entity({
            createdAt: i.date().indexed(), // generated field
            /* user-visible text */
            text: i.string().indexed(),
            isCompleted: i.boolean().indexed(),
          }),
        },
      });
      """
    )

    expectNoDifference(
      parsed,
      [
        ParsedInstantEntitySchema(InstantSchemaExamples.todos)
      ]
    )
  }

  @Test
  func schemaParserIgnoresCommentsBeforeValueComma() throws {
    let parsed = try TypeScriptSchemaParser().parse(
      """
      export default i.schema({
        entities: {
          todos: i.entity({
            createdAt: i.date().indexed() // generated field
            ,
            text: i.string().indexed() /* generated field */,
            isCompleted: i.boolean().indexed(),
          }),
        },
      });
      """
    )

    expectNoDifference(
      parsed,
      [
        ParsedInstantEntitySchema(InstantSchemaExamples.todos)
      ]
    )
  }

  @Test
  func schemaParserRejectsUnsupportedTopLevelSchemaKeys() {
    do {
      _ = try TypeScriptSchemaParser().parse(
        """
        export default i.schema({
          entities: {
            todos: i.entity({
              text: i.string().indexed(),
            }),
          },
          storage: {},
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject unsupported top-level schema keys.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(error, .unsupportedTopLevelKey("storage"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func schemaParserRejectsRoomsWithoutPresence() {
    do {
      _ = try TypeScriptSchemaParser().parseDocument(
        """
        export default i.schema({
          entities: {
            todos: i.entity({
              text: i.string().indexed(),
            }),
          },
          rooms: {
            chat: {
              topics: {
                sendEmoji: i.entity({
                  emoji: i.string(),
                }),
              },
            },
          },
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject rooms without presence.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(error, .missingRoomPresence(room: "chat"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func schemaParserRejectsWrappedRoomContainers() {
    do {
      _ = try TypeScriptSchemaParser().parseDocument(
        """
        export default i.schema({
          entities: {
            todos: i.entity({
              text: i.string().indexed(),
            }),
          },
          rooms: {
            chat: makeRoom({
              presence: i.entity({}),
            }),
          },
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject wrapped room definitions.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(error, .unsupportedRoomKey(room: "chat", key: "initializer"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try TypeScriptSchemaParser().parseDocument(
        """
        export default i.schema({
          entities: {
            todos: i.entity({
              text: i.string().indexed(),
            }),
          },
          rooms: {
            chat: {
              presence: i.entity({}),
              topics: makeTopics({
                sendEmoji: i.entity({
                  emoji: i.string(),
                }),
              }),
            },
          },
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject wrapped topics definitions.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(error, .unsupportedRoomKey(room: "chat", key: "topics"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func schemaParserRejectsTrailingRoomExpressions() {
    do {
      _ = try TypeScriptSchemaParser().parseDocument(
        """
        export default i.schema({
          entities: {
            todos: i.entity({
              text: i.string().indexed(),
            }),
          },
          rooms: {
            chat: {
              presence: i.entity({}),
            },
          } && {
            chat: {
              presence: i.entity({
                different: i.string(),
              }),
            },
          },
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject trailing top-level rooms expressions.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(error, .malformedObject("Expected rooms object."))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try TypeScriptSchemaParser().parseDocument(
        """
        export default i.schema({
          entities: {
            todos: i.entity({
              text: i.string().indexed(),
            }),
          },
          rooms: {
            chat: {
              presence: i.entity({}),
            } && {
              presence: i.entity({
                different: i.string(),
              }),
            },
          },
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject trailing room definition expressions.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(error, .unsupportedRoomKey(room: "chat", key: "initializer"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try TypeScriptSchemaParser().parseDocument(
        """
        export default i.schema({
          entities: {
            todos: i.entity({
              text: i.string().indexed(),
            }),
          },
          rooms: {
            chat: {
              presence: i.entity({}),
              topics: {
                sendEmoji: i.entity({
                  emoji: i.string(),
                }),
              } && {},
            },
          },
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject trailing topics expressions.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(error, .unsupportedRoomKey(room: "chat", key: "topics"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try TypeScriptSchemaParser().parseDocument(
        """
        export default i.schema({
          entities: {
            todos: i.entity({
              text: i.string().indexed(),
            }),
          },
          rooms: {
            chat: {
              presence: i.entity({}) && i.entity({
                different: i.string(),
              }),
            },
          },
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject trailing room payload expressions.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(
        error,
        .unsupportedEntityExpression(
          namespace: "rooms/chat/presence",
          expression: """
            i.entity({}) && i.entity({
                    different: i.string(),
                  })
            """
            .trimmingCharacters(in: .whitespacesAndNewlines)
        )
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func schemaParserRejectsUnsupportedLinkEndpointValues() {
    do {
      _ = try TypeScriptSchemaParser().parseDocument(
        """
        export default i.schema({
          entities: {
            todos: i.entity({
              text: i.string().indexed(),
            }),
            projects: i.entity({
              title: i.string().indexed(),
            }),
          },
          links: {
            projectsTodos: {
              forward: {
                on: "todos",
                has: "some",
                label: "project",
              },
              reverse: {
                on: "projects",
                has: "many",
                label: "todos",
              },
            },
          },
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject unsupported link endpoint values.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(
        error,
        .unsupportedLinkEndpointValue(
          name: "projectsTodos",
          endpoint: "forward",
          key: "has",
          value: "some"
        )
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func schemaParserRejectsCascadeOnManyLinks() {
    do {
      _ = try TypeScriptSchemaParser().parseDocument(
        """
        export default i.schema({
          entities: {
            todos: i.entity({
              text: i.string().indexed(),
            }),
          },
          links: {
            badCascade: {
              forward: {
                on: "todos",
                has: "many",
                label: "children",
                onDelete: "cascade",
              },
              reverse: {
                on: "todos",
                has: "many",
                label: "parents",
              },
            },
          },
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject cascade on has: many links.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(
        error,
        .invalidLinkCascadeEndpoint(
          link: "badCascade",
          endpoint: "forward",
          cardinality: .many
        )
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func schemaParserRejectsUnsupportedSchemaCall() {
    do {
      _ = try TypeScriptSchemaParser().parse(
        """
        export default i.schemaLoose({
          entities: {
            todos: i.entity({
              text: i.string().indexed(),
            }),
          },
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject unsupported schema calls.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(error, .missingEntitiesObject)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func permissionsPrinterEmitsTodoExample() throws {
    expectNoDifference(
      try TypeScriptPermissionsPrinter().printPermissions(InstantSchemaExamples.todoPermissions),
      """
      // Docs: https://www.instantdb.com/docs/permissions

      import type { InstantRules } from "@instantdb/core";

      const rules = {
        todos: {
          allow: {
            view: "true",
            create: "true",
            update: "true",
            delete: "true",
          },
        },
      } satisfies InstantRules;

      export default rules;

      """
    )
  }

  @Test
  func permissionsParserRoundTripsTodoExample() throws {
    let printed = try TypeScriptPermissionsPrinter()
      .printPermissions(InstantSchemaExamples.todoPermissions)
    let parsed = try TypeScriptPermissionsParser().parse(printed)

    expectNoDifference(parsed, InstantSchemaExamples.todoPermissions)
  }

  @Test
  func permissionsPrinterSupportsBindingsAndSpecialNamespaces() throws {
    let document = InstantPermissionsDocument(
      namespaces: [
        InstantNamespacePermissions(
          namespace: "$files",
          allow: [
            .view: "isOwner",
            .create: "isOwner",
            .delete: "isOwner",
          ],
          bind: [
            InstantPermissionBinding(
              "isOwner",
              "auth.id != null && data.path.startsWith(auth.id + '/')"
            )
          ]
        ),
        InstantNamespacePermissions(
          namespace: "posts",
          allow: [
            .view: "true",
            .create: "isOwner",
            .update: "isOwner",
            .delete: "isOwner",
          ],
          bind: [
            InstantPermissionBinding("isOwner", "auth.id != null && auth.id == data.ownerId")
          ]
        ),
      ]
    )

    expectNoDifference(
      try TypeScriptPermissionsPrinter().printPermissions(document),
      """
      // Docs: https://www.instantdb.com/docs/permissions

      import type { InstantRules } from "@instantdb/core";

      const rules = {
        "$files": {
          allow: {
            view: "isOwner",
            create: "isOwner",
            delete: "isOwner",
          },
          bind: [
            "isOwner", "auth.id != null && data.path.startsWith(auth.id + '/')",
          ],
        },
        posts: {
          allow: {
            view: "true",
            create: "isOwner",
            update: "isOwner",
            delete: "isOwner",
          },
          bind: [
            "isOwner", "auth.id != null && auth.id == data.ownerId",
          ],
        },
      } satisfies InstantRules;

      export default rules;

      """
    )
  }

  @Test
  func permissionsParserRoundTripsGeneratedRuleSurface() throws {
    let document = InstantPermissionsDocument(
      attrs: InstantAttributePermissions(
        allow: [.create: "isAdmin"],
        bind: [
          InstantPermissionBinding("isAdmin", "auth.ref('$users.admins.id') != null")
        ]
      ),
      defaults: InstantDefaultPermissions(
        allow: [.view: "true"],
        link: ["owner": "isOwner"],
        unlink: ["owner": "isOwner"],
        bind: [
          InstantPermissionBinding("isOwner", "auth.id != null && auth.id == data.ownerId")
        ]
      ),
      rateLimits: [
        InstantRateLimit(
          name: "writes",
          limits: [
            InstantRateLimitLimit(capacity: 20),
            InstantRateLimitLimit(
              capacity: 10,
              refill: InstantRateLimitRefill(
                amount: 1,
                period: "1 minute",
                type: .greedy
              )
            ),
          ]
        )
      ],
      namespaces: [
        InstantNamespacePermissions(
          namespace: "posts",
          allow: [
            .view: "true",
            .create: "isOwner",
            .update: "isOwner",
          ],
          link: ["author": "isOwner"],
          unlink: ["author": "isOwner"],
          bind: [
            InstantPermissionBinding("isOwner", "auth.id != null && auth.id == data.ownerId")
          ],
          fields: ["privateNotes": "false"]
        )
      ]
    )

    let printed = try TypeScriptPermissionsPrinter().printPermissions(document)
    let parsed = try TypeScriptPermissionsParser().parse(printed)

    expectNoDifference(parsed, document)
  }

  @Test
  func permissionsParserRejectsUnsupportedAllowKeys() {
    do {
      _ = try TypeScriptPermissionsParser().parse(
        """
        const rules = {
          todos: {
            allow: {
              publish: "true",
            },
          },
        } satisfies InstantRules;

        export default rules;
        """
      )
      #expect(Bool(false), "Expected parser to reject unsupported allow keys.")
    } catch let error as TypeScriptPermissionsParseError {
      expectNoDifference(
        error,
        .unsupportedRuleKey(context: "todos.allow", key: "publish")
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func permissionsParserRejectsWrappedRulesInitializers() {
    do {
      _ = try TypeScriptPermissionsParser().parse(
        """
        const rules = makeRules({
          todos: {
            allow: {
              view: "true",
              create: "true",
              update: "true",
              delete: "true",
            },
          },
        }) satisfies InstantRules;

        export default rules;
        """
      )
      #expect(Bool(false), "Expected parser to reject non-literal rules initializers.")
    } catch let error as TypeScriptPermissionsParseError {
      expectNoDifference(
        error,
        .unsupportedRuleValue(
          context: "rules",
          key: "initializer",
          value: """
            makeRules({
              todos: {
                allow: {
                  view: "true",
                  create: "true",
                  update: "true",
                  delete: "true",
                },
              },
            }) satisfies InstantRules;

            export default rules;
            """
            .trimmingCharacters(in: .whitespacesAndNewlines)
        )
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func permissionsParserRejectsTrailingInitializerExpressions() {
    do {
      _ = try TypeScriptPermissionsParser().parse(
        """
        const rules = {
          todos: {
            allow: {
              view: "true",
              create: "true",
              update: "true",
              delete: "true",
            },
          },
        } && {
          todos: {
            allow: {
              view: "false",
            },
          },
        };

        export default rules;
        """
      )
      #expect(Bool(false), "Expected parser to reject trailing initializer expressions.")
    } catch let error as TypeScriptPermissionsParseError {
      guard case let .unsupportedRuleValue(context, key, value) = error else {
        #expect(Bool(false), "Unexpected parser error: \(error)")
        return
      }
      expectNoDifference(context, "rules")
      expectNoDifference(key, "initializer")
      #expect(value.contains("&&"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func permissionsParserRejectsPostInitializerMutation() {
    do {
      _ = try TypeScriptPermissionsParser().parse(
        """
        const rules = {
          todos: {
            allow: {
              view: "true",
              create: "true",
              update: "true",
              delete: "true",
            },
          },
        } satisfies InstantRules;

        rules.todos.allow.view = "false";
        export default rules;
        """
      )
      #expect(Bool(false), "Expected parser to reject mutated rules exports.")
    } catch let error as TypeScriptPermissionsParseError {
      guard case let .unsupportedRuleValue(context, key, value) = error else {
        #expect(Bool(false), "Unexpected parser error: \(error)")
        return
      }
      expectNoDifference(context, "rules")
      expectNoDifference(key, "initializer")
      #expect(value.contains("rules.todos.allow.view"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func permissionsParserRejectsMissingRulesExport() {
    do {
      _ = try TypeScriptPermissionsParser().parse(
        """
        const rules = {
          todos: {
            allow: {
              view: "true",
              create: "true",
              update: "true",
              delete: "true",
            },
          },
        } satisfies InstantRules;
        """
      )
      #expect(Bool(false), "Expected parser to reject permissions without export default rules.")
    } catch let error as TypeScriptPermissionsParseError {
      guard case let .unsupportedRuleValue(context, key, _) = error else {
        #expect(Bool(false), "Unexpected parser error: \(error)")
        return
      }
      expectNoDifference(context, "rules")
      expectNoDifference(key, "initializer")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func permissionsParserRejectsUnsupportedContextKeys() {
    do {
      _ = try TypeScriptPermissionsParser().parse(
        """
        const rules = {
          attrs: {
            allow: {
              link: {
                owner: "true",
              },
            },
          },
        } satisfies InstantRules;

        export default rules;
        """
      )
      #expect(Bool(false), "Expected parser to reject relationship rules in attrs.")
    } catch let error as TypeScriptPermissionsParseError {
      expectNoDifference(
        error,
        .unsupportedRuleKey(context: "attrs.allow", key: "link")
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try TypeScriptPermissionsParser().parse(
        """
        const rules = {
          "$default": {
            allow: {
              view: "true",
            },
            fields: {
              privateNotes: "false",
            },
          },
        } satisfies InstantRules;

        export default rules;
        """
      )
      #expect(Bool(false), "Expected parser to reject fields in $default.")
    } catch let error as TypeScriptPermissionsParseError {
      expectNoDifference(
        error,
        .unsupportedRuleKey(context: "$default", key: "fields")
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func permissionsPrinterEmitsAllowBlockForBindOnlyNamespaces() throws {
    let document = InstantPermissionsDocument(
      namespaces: [
        InstantNamespacePermissions(
          namespace: "posts",
          bind: [
            InstantPermissionBinding("isOwner", "auth.id != null && auth.id == data.ownerId")
          ]
        )
      ]
    )

    expectNoDifference(
      try TypeScriptPermissionsPrinter().printPermissions(document),
      """
      // Docs: https://www.instantdb.com/docs/permissions

      import type { InstantRules } from "@instantdb/core";

      const rules = {
        posts: {
          allow: {},
          bind: [
            "isOwner", "auth.id != null && auth.id == data.ownerId",
          ],
        },
      } satisfies InstantRules;

      export default rules;

      """
    )
  }

  @Test
  func permissionsPrinterSupportsTopLevelAndRelationshipRules() throws {
    let document = InstantPermissionsDocument(
      attrs: InstantAttributePermissions(
        allow: [
          .create: "false"
        ]
      ),
      defaults: InstantDefaultPermissions(
        allow: [
          .view: "false"
        ],
        link: [
          "comments": "isOwner"
        ],
        unlink: [
          "comments": "isOwner"
        ]
      ),
      rateLimits: [
        InstantRateLimit(
          name: "writeBurst",
          limits: [
            InstantRateLimitLimit(
              capacity: 10,
              refill: InstantRateLimitRefill(
                amount: 5,
                period: "1 minute",
                type: .interval
              )
            )
          ]
        )
      ],
      namespaces: [
        InstantNamespacePermissions(
          namespace: "posts",
          allow: [
            .view: "true",
            .update: "isOwner",
          ],
          link: [
            "comments": "isOwner"
          ],
          unlink: [
            "comments": "isOwner"
          ],
          bind: [
            InstantPermissionBinding("isOwner", "auth.id != null && auth.id == data.ownerId")
          ],
          fields: [
            "title": "isOwner"
          ]
        )
      ]
    )

    expectNoDifference(
      try TypeScriptPermissionsPrinter().printPermissions(document),
      """
      // Docs: https://www.instantdb.com/docs/permissions

      import type { InstantRules } from "@instantdb/core";

      const rules = {
        attrs: {
          allow: {
            create: "false",
          },
        },
        "$default": {
          allow: {
            view: "false",
            link: {
              comments: "isOwner",
            },
            unlink: {
              comments: "isOwner",
            },
          },
        },
        "$rateLimits": {
          writeBurst: {
            limits: [
              { capacity: 10, refill: { amount: 5, period: "1 minute", type: "interval" } },
            ],
          },
        },
        posts: {
          allow: {
            view: "true",
            update: "isOwner",
            link: {
              comments: "isOwner",
            },
            unlink: {
              comments: "isOwner",
            },
          },
          bind: [
            "isOwner", "auth.id != null && auth.id == data.ownerId",
          ],
          fields: {
            title: "isOwner",
          },
        },
      } satisfies InstantRules;

      export default rules;

      """
    )
  }

  @Test
  func permissionsPrinterRejectsServerInvalidFieldRules() {
    let document = InstantPermissionsDocument(
      namespaces: [
        InstantNamespacePermissions(
          namespace: "posts",
          fields: [
            "id": "true"
          ]
        )
      ]
    )

    do {
      _ = try TypeScriptPermissionsPrinter().printPermissions(document)
      #expect(Bool(false), "Expected printer to reject field rules for id.")
    } catch let error as InstantPermissionsValidationError {
      expectNoDifference(
        error,
        .reservedFieldRule(namespace: "posts", field: "id")
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func permissionsPrinterRejectsServerInvalidRateLimits() {
    do {
      _ = try TypeScriptPermissionsPrinter().printPermissions(
        InstantPermissionsDocument(
          rateLimits: [
            InstantRateLimit(name: "empty", limits: [])
          ],
          namespaces: []
        )
      )
      #expect(Bool(false), "Expected printer to reject empty rate limits.")
    } catch let error as InstantPermissionsValidationError {
      expectNoDifference(error, .emptyRateLimit(name: "empty"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try TypeScriptPermissionsPrinter().printPermissions(
        InstantPermissionsDocument(
          rateLimits: [
            InstantRateLimit(
              name: "badCapacity",
              limits: [
                InstantRateLimitLimit(capacity: 0)
              ]
            )
          ],
          namespaces: []
        )
      )
      #expect(Bool(false), "Expected printer to reject nonpositive capacity.")
    } catch let error as InstantPermissionsValidationError {
      expectNoDifference(error, .invalidRateLimitCapacity(name: "badCapacity", capacity: 0))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try TypeScriptPermissionsPrinter().printPermissions(
        InstantPermissionsDocument(
          rateLimits: [
            InstantRateLimit(
              name: "badRefill",
              limits: [
                InstantRateLimitLimit(
                  capacity: 1,
                  refill: InstantRateLimitRefill(amount: 0)
                )
              ]
            )
          ],
          namespaces: []
        )
      )
      #expect(Bool(false), "Expected printer to reject nonpositive refill amount.")
    } catch let error as InstantPermissionsValidationError {
      expectNoDifference(error, .invalidRateLimitRefillAmount(name: "badRefill", amount: 0))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try TypeScriptPermissionsPrinter().printPermissions(
        InstantPermissionsDocument(
          rateLimits: [
            InstantRateLimit(
              name: "shortPeriod",
              limits: [
                InstantRateLimitLimit(
                  capacity: 1,
                  refill: InstantRateLimitRefill(period: "0 seconds")
                )
              ]
            )
          ],
          namespaces: []
        )
      )
      #expect(Bool(false), "Expected printer to reject too-short refill period.")
    } catch let error as InstantPermissionsValidationError {
      expectNoDifference(
        error,
        .invalidRateLimitRefillPeriod(name: "shortPeriod", period: "0 seconds")
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try TypeScriptPermissionsPrinter().printPermissions(
        InstantPermissionsDocument(
          rateLimits: [
            InstantRateLimit(
              name: "longPeriod",
              limits: [
                InstantRateLimitLimit(
                  capacity: 1,
                  refill: InstantRateLimitRefill(period: "2 days")
                )
              ]
            )
          ],
          namespaces: []
        )
      )
      #expect(Bool(false), "Expected printer to reject too-long refill period.")
    } catch let error as InstantPermissionsValidationError {
      expectNoDifference(
        error,
        .invalidRateLimitRefillPeriod(name: "longPeriod", period: "2 days")
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }
}
