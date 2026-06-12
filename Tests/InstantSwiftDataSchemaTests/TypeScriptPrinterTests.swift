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
  func permissionsPrinterEmitsTodoExample() {
    expectNoDifference(
      TypeScriptPermissionsPrinter().printPermissions(InstantSchemaExamples.todoPermissions),
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
  func permissionsPrinterSupportsBindingsAndSpecialNamespaces() {
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
      TypeScriptPermissionsPrinter().printPermissions(document),
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
  func permissionsPrinterEmitsAllowBlockForBindOnlyNamespaces() {
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
      TypeScriptPermissionsPrinter().printPermissions(document),
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
}
