import CustomDump
import Foundation
import InstantSwiftData
import Testing

#if canImport(SwiftUI)
  import SwiftUI

  @Suite
  struct V3RecordingsListFixtureTests {
    @Test @MainActor
    func recordingsListModifierSyntaxCompilesWithDynamicQueryIdentity() {
      let screen = V3RecordingsListFixture()
      let view: any View = screen
      _ = view

      let mine = v3RecordingsQuery(scope: .mine, searchText: "walk")
      let shared = v3RecordingsQuery(scope: .shared, searchText: "walk")
      let searched = v3RecordingsQuery(scope: .mine, searchText: "meeting")

      #expect(mine.plan.id != shared.plan.id)
      #expect(mine.plan.id != searched.plan.id)
      expectNoDifference(
        mine.plan.filters,
        [
          .equals(field: "isShared", value: .bool(false)),
          .iLike(field: "title", pattern: "%walk%"),
        ]
      )
    }
  }

  @MainActor
  private struct V3RecordingsListFixture: View {
    @FetchAll
    private var rows: [V3RecordingListRow]

    @State
    private var scope: V3RecordingListScope = .mine

    @State
    private var searchText = ""

    var body: some View {
      List(rows) { row in
        Text(row.title)
      }
      .searchable(text: $searchText)
      .instantFetch(
        $rows,
        rowsQuery
      )
    }

    private var rowsQuery: InstantQuery<V3RecordingListRow> {
      v3RecordingsQuery(scope: scope, searchText: searchText)
    }
  }

  private enum V3RecordingListScope: String, Hashable, Sendable {
    case mine
    case shared
  }

  private func v3RecordingsQuery(
    scope: V3RecordingListScope,
    searchText: String
  ) -> InstantQuery<V3RecordingListRow> {
    let scoped = V3RecordingListRow.query
      .where(V3RecordingListRow.isShared == (scope == .shared))
      .order(V3RecordingListRow.title)
    guard !searchText.isEmpty else { return scoped }
    return scoped.where(V3RecordingListRow.title.iLike("%\(searchText)%"))
  }

  private struct V3RecordingListRow: Hashable, Codable, InstantEntityModel {
    var id: InstantID<V3RecordingListRow>
    var title: String
    var isShared: Bool

    static let instantNamespace = "v3_recording_list_rows"
    static let title = InstantAttributePath<V3RecordingListRow, String>("title")
    static let isShared = InstantAttributePath<V3RecordingListRow, Bool>("isShared")
    static let instantAttributes = [
      InstantAttribute(
        id: "v3_recording_list_rows/title",
        namespace: instantNamespace,
        name: "title",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_recording_list_rows/isShared",
        namespace: instantNamespace,
        name: "isShared",
        valueType: .boolean,
        isIndexed: true
      ),
    ]

    init(snapshot: InstantEntitySnapshot) throws {
      guard case let .string(title) = snapshot.values["title"]?.first,
        case let .bool(isShared) = snapshot.values["isShared"]?.first
      else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode V3 recording list row fixture",
          namespace: Self.instantNamespace,
          localID: snapshot.id,
          message: "Expected title and isShared values.",
          recovery: "Keep the compile fixture aligned with its declared attributes."
        )
      }
      self.id = InstantID(rawValue: snapshot.id)
      self.title = title
      self.isShared = isShared
    }
  }
#endif
