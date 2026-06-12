import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(InstantDBMacros)
import InstantDBMacros

final class InstantEntityMacroTests: XCTestCase {
    let testMacros: [String: Macro.Type] = [
        "InstantEntity": InstantEntityMacro.self
    ]

    /// Tests that @InstantEntity only works on structs, not classes
    func testMacroErrorOnClass() throws {
        assertMacroExpansion(
            #"""
            @InstantEntity("items")
            class Item {
                let id: String
            }
            """#,
            expandedSource: #"""
            class Item {
                let id: String
            }

            extension Item: InstantEntity, InstantEntitySchema, Identifiable, Codable {
            }
            """#,
            diagnostics: [
                DiagnosticSpec(message: "@InstantEntity can only be applied to structs", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }

    /// Tests that @InstantEntity requires a namespace argument
    func testMacroErrorOnMissingNamespace() throws {
        assertMacroExpansion(
            #"""
            @InstantEntity
            struct Item {
                let id: String
            }
            """#,
            expandedSource: #"""
            struct Item {
                let id: String
            }

            extension Item: InstantEntity, InstantEntitySchema, Identifiable, Codable {
            }
            """#,
            diagnostics: [
                DiagnosticSpec(message: "@InstantEntity requires a string literal namespace argument", line: 1, column: 1)
            ],
            macros: testMacros
        )
    }
}
#endif
