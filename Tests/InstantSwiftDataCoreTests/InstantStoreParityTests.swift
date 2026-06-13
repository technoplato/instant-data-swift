import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantStoreParityTests {
  @Test
  func storeDeepMergePortsUpstreamObjectArrayAndNullSemantics() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [
          InstantAttribute(
            id: "games/state",
            namespace: "games",
            name: "state",
            valueType: .json
          )
        ]
      )
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let secondTime = InstantTimestamp(milliseconds: time.milliseconds + 5)
    let mergeTime = InstantTimestamp(milliseconds: time.milliseconds + 10)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-game-state-seed",
        operations: [
          .insert(
            InstantTriple(
              entityID: "game-1",
              attributeID: "games/state",
              value: .json(
                .object([
                  "score": .number(100),
                  "playerStats": .object([
                    "health": .number(50),
                    "mana": .number(30),
                    "ambitions": .object(["win": .bool(true)]),
                  ]),
                  "inventory": .array([.string("sword"), .string("potion")]),
                  "locations": .array([.string("forest"), .string("castle")]),
                  "level": .number(2),
                ])
              ),
              txID: "tx-game-state-seed",
              txTime: time
            )
          ),
          .insert(
            InstantTriple(
              entityID: "game-2",
              attributeID: "games/state",
              value: .json(.object(["level": .number(1)])),
              txID: "tx-game-state-seed",
              txTime: secondTime
            )
          )
        ]
      ),
      createdAt: time
    )

    let mergeResult = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-game-state-merge",
        operations: [
          .merge(
            InstantTriple(
              entityID: "game-1",
              attributeID: "games/state",
              value: .json(
                .object([
                  "playerStats": .object([
                    "health": .null,
                    "mana": .number(40),
                    "stamina": .number(20),
                    "ambitions": .object([
                      "acquireWisdom": .bool(true),
                      "find": .array([.string("love")]),
                    ]),
                  ]),
                  "inventory": .array([.string("shield")]),
                  "score": .null,
                  "locations": .array([.string("forest"), .null, .string("castle")]),
                ])
              ),
              txID: "tx-game-state-merge",
              txTime: mergeTime
            )
          ),
          .merge(
            InstantTriple(
              entityID: "game-missing",
              attributeID: "games/state",
              value: .json(.object(["level": .number(99)])),
              txID: "tx-game-state-merge",
              txTime: mergeTime
            )
          )
        ]
      ),
      createdAt: mergeTime
    )
    expectNoDifference(mergeResult.changedEntityIDs, ["game-1"])

    let games = try await runtime.query(
      InstantQueryPlan(id: "games", namespace: "games", order: .serverCreatedAt)
    )
    expectNoDifference(games.map(\.id), ["game-1", "game-2"])
    let state = try #require(games.first { $0.id == "game-1" }?.values["state"]?.first)
    expectNoDifference(
      state,
      .json(
        .object([
          "playerStats": .object([
            "mana": .number(40),
            "stamina": .number(20),
            "ambitions": .object([
              "win": .bool(true),
              "acquireWisdom": .bool(true),
              "find": .array([.string("love")]),
            ]),
          ]),
          "inventory": .array([.string("shield")]),
          "locations": .array([.string("forest"), .null, .string("castle")]),
          "level": .number(2),
        ])
      )
    )
  }

  private func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataStoreParityTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("state.sqlite")
  }
}
