import Foundation

public struct InstantLiveShareContract: Hashable, Codable, Sendable {
  public var queryPlan: InstantQueryPlan

  public init(queryPlan: InstantQueryPlan) {
    self.queryPlan = queryPlan
  }

  public static let v3SharedLists = Self(
    queryPlan: InstantQueryPlan(
      id: "instant.live-shares.v3-shared-lists",
      namespace: "v3_shared_lists",
      includes: [
        InstantQueryInclude("owner"),
        InstantQueryInclude("readers"),
        InstantQueryInclude("writers"),
        InstantQueryInclude(
          "share",
          direction: .reverse,
          query: InstantQueryIncludePlan(
            id: "instant.live-shares.v3-shares",
            namespace: "v3_shares",
            includes: [
              InstantQueryInclude("owner"),
              InstantQueryInclude(
                "memberships",
                direction: .reverse,
                query: InstantQueryIncludePlan(
                  id: "instant.live-shares.v3-share-memberships",
                  namespace: "v3_share_memberships",
                  includes: [InstantQueryInclude("user")]
                )
              ),
            ]
          )
        ),
      ]
    )
  )

  public func snapshots(
    appID: String,
    roots: [InstantEntitySnapshot]
  ) throws -> [InstantShareSnapshot] {
    try roots.map { root in
      let shareNode = try onlyLink("share", in: root, path: "\(root.namespace).share")
      let owner = try onlyLink("owner", in: shareNode, path: "v3_shares.owner")
      let shareID = shareNode.id
      let memberships = try (shareNode.links?["memberships"] ?? []).map { membership in
        let user = try onlyLink(
          "user",
          in: membership,
          path: "v3_share_memberships.user"
        )
        let roleValue = try string("role", in: membership.values, path: membership.id)
        guard let role = InstantShareRole(rawValue: roleValue) else {
          throw decodeError(
            path: "\(membership.id).role",
            message: "Expected owner, reader, or writer; received '\(roleValue)'."
          )
        }
        return InstantShareMembership(
          appID: appID,
          shareID: shareID,
          userID: user.id,
          role: role,
          acceptedAt: try timestamp("acceptedAt", in: membership.values, path: membership.id)
        )
      }
      .sorted(by: membershipOrder)

      return InstantShareSnapshot(
        share: InstantShare(
          id: shareID,
          appID: appID,
          rootNamespace: try string("rootNamespace", in: shareNode.values, path: shareID),
          rootID: try string("rootID", in: shareNode.values, path: shareID),
          ownerUserID: owner.id,
          token: try string("token", in: shareNode.values, path: shareID),
          createdAt: try timestamp("createdAt", in: shareNode.values, path: shareID),
          updatedAt: try timestamp("updatedAt", in: shareNode.values, path: shareID)
        ),
        memberships: memberships
      )
    }
    .sorted { lhs, rhs in lhs.share.id < rhs.share.id }
  }

  func observe(
    appID: String,
    emissions: AsyncStream<InstantQueryEmission>,
    onFailure: @escaping @Sendable (InstantError) async -> Void
  ) -> AsyncStream<[InstantShareSnapshot]> {
    AsyncStream { continuation in
      let task = Task {
        for await emission in emissions {
          guard !Task.isCancelled else { break }
          do {
            continuation.yield(
              try snapshots(appID: appID, roots: emission.values)
            )
          } catch let error as InstantError {
            await onFailure(error)
            break
          } catch {
            await onFailure(
              InstantError(
                code: .decodeFailed,
                operation: "decode live share graph",
                message: String(describing: error),
                recovery:
                  "Keep the Swift live-share contract aligned with canonical sharingQuery output."
              )
            )
            break
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func onlyLink(
    _ name: String,
    in snapshot: InstantEntitySnapshot,
    path: String
  ) throws -> InstantLinkedEntitySnapshot {
    try onlyLink(name, in: InstantLinkedEntitySnapshot(snapshot), path: path)
  }

  private func onlyLink(
    _ name: String,
    in snapshot: InstantLinkedEntitySnapshot,
    path: String
  ) throws -> InstantLinkedEntitySnapshot {
    guard let links = snapshot.links?[name], links.count == 1, let value = links.first else {
      throw decodeError(path: path, message: "Expected exactly one linked entity.")
    }
    return value
  }

  private func string(
    _ field: String,
    in values: [String: InstantMaterializedValue],
    path: String
  ) throws -> String {
    guard case let .one(.string(value)) = values[field] else {
      throw decodeError(path: "\(path).\(field)", message: "Expected a string value.")
    }
    return value
  }

  private func timestamp(
    _ field: String,
    in values: [String: InstantMaterializedValue],
    path: String
  ) throws -> InstantTimestamp {
    guard case let .one(.date(value)) = values[field] else {
      throw decodeError(path: "\(path).\(field)", message: "Expected a date value.")
    }
    return InstantTimestamp(
      milliseconds: Int64((value.timeIntervalSince1970 * 1_000).rounded())
    )
  }

  private func decodeError(path: String, message: String) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode live share graph",
      path: path,
      message: message,
      recovery: "Keep the Swift live-share contract aligned with canonical sharingQuery output."
    )
  }
}

private func membershipOrder(
  _ lhs: InstantShareMembership,
  _ rhs: InstantShareMembership
) -> Bool {
  let order: [InstantShareRole: Int] = [.owner: 0, .reader: 1, .writer: 2]
  let lhsRank = order[lhs.role] ?? Int.max
  let rhsRank = order[rhs.role] ?? Int.max
  return lhsRank == rhsRank ? lhs.userID < rhs.userID : lhsRank < rhsRank
}
