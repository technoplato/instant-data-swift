import CustomDump
import InstantSwiftDataSchema
import Testing

@Suite
struct TypeScriptPrinterTests {
  @Test
  func schemaPrinterEmitsTodoExample() {
    expectNoDifference(
      TypeScriptSchemaPrinter().printSchema([InstantSchemaExamples.todos]),
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
