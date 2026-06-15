import CustomDump
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct JSONValuePathMutationParityTests {
  private let source =
    "upstream/instant/client/packages/core/__tests__/src/utils/object.test.ts"

  @Test
  func assocInMutativeAddsShallowAndNestedValues() {
    var shallow: JSONValue = .object(["a": .number(1)])
    shallow.assocIn(["b"], .number(2))
    expectNoDifference(
      shallow,
      .object(["a": .number(1), "b": .number(2)]),
      "\(source) assocInMutative adds value at a shallow path"
    )

    var nested: JSONValue = .object(["a": .object([:])])
    nested.assocIn(["a", "b", "c"], .number(3))
    expectNoDifference(
      nested,
      .object(["a": .object(["b": .object(["c": .number(3)])])]),
      "\(source) assocInMutative adds value at a nested path"
    )
  }

  @Test
  func assocInMutativeEmptyPathIsNoOpAndCreatesArrayIntermediates() {
    var emptyPath: JSONValue = .object(["a": .number(1)])
    emptyPath.assocIn([], .number(2))
    expectNoDifference(
      emptyPath,
      .object(["a": .number(1)]),
      "\(source) assocInMutative empty path returns without mutation"
    )

    var arrayIntermediate: JSONValue = .object([:])
    arrayIntermediate.assocIn(["a", 0], .string("value"))
    expectNoDifference(
      arrayIntermediate,
      .object(["a": .array([.string("value")])]),
      "\(source) assocInMutative creates arrays for numeric next path components"
    )

    var objectWithNumericKey: JSONValue = .object(["existing": .bool(true)])
    objectWithNumericKey.assocIn([0], .string("value"))
    expectNoDifference(
      objectWithNumericKey,
      .object(["0": .string("value"), "existing": .bool(true)]),
      "\(source) assocInMutative preserves object fields when the current container is not an array"
    )
  }

  @Test
  func insertInMutativeWorksOnObjectsAndArrays() {
    var object: JSONValue = .object(["a": .number(1)])
    object.insertIn(["b"], .number(2))
    expectNoDifference(
      object,
      .object(["a": .number(1), "b": .number(2)]),
      "\(source) insertInMutative it works on normal objects"
    )

    var nested: JSONValue = .object(["a": .object([:])])
    nested.insertIn(["a", "b", "c"], .number(3))
    expectNoDifference(
      nested,
      .object(["a": .object(["b": .object(["c": .number(3)])])]),
      "\(source) insertInMutative it works on normal objects"
    )

    var emptyArray: JSONValue = .array([])
    emptyArray.insertIn([0], .string("a"))
    expectNoDifference(
      emptyArray,
      .array([.string("a")]),
      "\(source) insertInMutative inserts on arrays"
    )

    var prependArray: JSONValue = .array([.string("b")])
    prependArray.insertIn([0], .string("a"))
    expectNoDifference(prependArray, .array([.string("a"), .string("b")]), source)

    var appendArray: JSONValue = .array([.string("b")])
    appendArray.insertIn([1], .string("a"))
    expectNoDifference(appendArray, .array([.string("b"), .string("a")]), source)

    var nestedArray: JSONValue = .object(["x": .array([.string("b")])])
    nestedArray.insertIn(["x", 0], .string("a"))
    expectNoDifference(
      nestedArray,
      .object(["x": .array([.string("a"), .string("b")])]),
      source
    )

    var deepArray: JSONValue = .object([
      "w": .object([
        "x": .object([
          "y": .array([.string("a"), .string("b"), .string("c"), .string("d")]),
          "z": .number(4),
        ])
      ])
    ])
    deepArray.insertIn(["w", "x", "y", 1], .string("a"))
    expectNoDifference(
      deepArray,
      .object([
        "w": .object([
          "x": .object([
            "y": .array([.string("a"), .string("a"), .string("b"), .string("c"), .string("d")]),
            "z": .number(4),
          ])
        ])
      ]),
      source
    )

    var replaceObjectLeaf: JSONValue = .object([
      "w": .object([
        "x": .object([
          "y": .array([.string("a"), .string("b"), .string("c"), .string("d")]),
          "z": .number(4),
        ])
      ])
    ])
    replaceObjectLeaf.insertIn(["w", "x", "z"], .string("a"))
    expectNoDifference(
      replaceObjectLeaf,
      .object([
        "w": .object([
          "x": .object([
            "y": .array([.string("a"), .string("b"), .string("c"), .string("d")]),
            "z": .string("a"),
          ])
        ])
      ]),
      source
    )
  }

  @Test
  func insertInMutativeEmptyPathIsNoOpAndCreatesArrayIntermediates() {
    var emptyPath: JSONValue = .object(["a": .number(1)])
    emptyPath.insertIn([], .number(2))
    expectNoDifference(
      emptyPath,
      .object(["a": .number(1)]),
      "\(source) insertInMutative empty path returns without mutation"
    )

    var arrayIntermediate: JSONValue = .object([:])
    arrayIntermediate.insertIn(["a", 0], .string("value"))
    expectNoDifference(
      arrayIntermediate,
      .object(["a": .array([.string("value")])]),
      "\(source) insertInMutative creates arrays for numeric next path components"
    )

    var objectWithNumericKey: JSONValue = .object(["existing": .bool(true)])
    objectWithNumericKey.insertIn([0], .string("value"))
    expectNoDifference(
      objectWithNumericKey,
      .object(["0": .string("value"), "existing": .bool(true)]),
      "\(source) insertInMutative preserves object fields when the current container is not an array"
    )
  }

  @Test
  func dissocInMutativeDeletesObjectsAndArrays() {
    var shallow: JSONValue = .object(["a": .number(1), "b": .number(2)])
    shallow.dissocIn(["a"])
    expectNoDifference(
      shallow,
      .object(["b": .number(2)]),
      "\(source) dissocInMutative deletes a shallow property"
    )

    var nested: JSONValue = .object([
      "a": .object([
        "b": .object([
          "c": .number(3),
          "d": .number(4),
        ])
      ])
    ])
    nested.dissocIn(["a", "b", "c"])
    expectNoDifference(
      nested,
      .object(["a": .object(["b": .object(["d": .number(4)])])]),
      "\(source) dissocInMutative deletes a nested property"
    )

    var array: JSONValue = .object([
      "a": .object([
        "b": .object([
          "c": .array([.string("a"), .string("b"), .string("c"), .string("d")])
        ])
      ])
    ])
    array.dissocIn(["a", "b", "c", 1])
    expectNoDifference(
      array,
      .object([
        "a": .object([
          "b": .object([
            "c": .array([.string("a"), .string("c"), .string("d")])
          ])
        ])
      ]),
      "\(source) dissocInMutative works on arrays"
    )
  }

  @Test
  func dissocInMutativeEmptyPathIsNoOpAndPrunesEmptyContainers() {
    var emptyPath: JSONValue = .object(["a": .number(1)])
    emptyPath.dissocIn([])
    expectNoDifference(
      emptyPath,
      .object(["a": .number(1)]),
      "\(source) dissocInMutative empty path returns without mutation"
    )

    var objectWithNumericKey: JSONValue = .object([
      "0": .string("value"),
      "existing": .bool(true),
    ])
    objectWithNumericKey.dissocIn([0])
    expectNoDifference(
      objectWithNumericKey,
      .object(["existing": .bool(true)]),
      "\(source) dissocInMutative coerces numeric keys on non-array objects"
    )

    var nestedOnlyChild: JSONValue = .object([
      "a": .object([
        "b": .object([
          "c": .number(1)
        ])
      ])
    ])
    nestedOnlyChild.dissocIn(["a", "b", "c"])
    expectNoDifference(
      nestedOnlyChild,
      .object([:]),
      "\(source) dissocInMutative prunes empty object parents"
    )

    var nestedSingleElementArray: JSONValue = .object([
      "a": .object([
        "b": .object([
          "c": .array([.string("x")])
        ])
      ])
    ])
    nestedSingleElementArray.dissocIn(["a", "b", "c", 0])
    expectNoDifference(
      nestedSingleElementArray,
      .object([:]),
      "\(source) dissocInMutative prunes empty array parents"
    )
  }
}
