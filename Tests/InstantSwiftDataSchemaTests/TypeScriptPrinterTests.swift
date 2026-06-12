import CustomDump
import InstantSwiftDataCore
import InstantSwiftDataSchema
import Testing

@Suite
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
  func schemaParserSupportsQuotedKeysAndAttributeModifiers() throws {
    let parsed = try TypeScriptSchemaParser().parse(
      """
      import { i } from '@instantdb/core';

      export default i.schema({
        entities: {
          "blog-posts": i.entity({
            "published-at": i.date().indexed(),
            slug: i.string().unique().indexed(),
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
              text: i.string().optional().indexed(),
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
          expression: "i.string().optional().indexed()"
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
          rooms: {},
        });
        """
      )
      #expect(Bool(false), "Expected parser to reject unsupported top-level schema keys.")
    } catch let error as TypeScriptSchemaParseError {
      expectNoDifference(error, .unsupportedTopLevelKey("rooms"))
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
