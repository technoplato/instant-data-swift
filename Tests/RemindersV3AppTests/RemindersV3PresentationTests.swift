import CustomDump
import Foundation
import InstantSwiftData
import RemindersV3App
import Testing

#if canImport(SwiftUI)
  @Suite
  struct RemindersV3PresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func smartListStatsSearchAndTagsUseTheLiveLinkedGraph() {
      let lists = fixtureLists()

      expectNoDifference(
        RemindersV3Presentation.stats(lists: lists, now: now),
        RemindersStats(
          allCount: 3,
          completedCount: 1,
          flaggedCount: 1,
          scheduledCount: 2,
          todayCount: 1
        )
      )
      expectNoDifference(
        RemindersV3Presentation.usedTags(in: lists).map(\.title),
        ["family", "home"]
      )
      expectNoDifference(
        RemindersV3Presentation.rows(
          lists: lists,
          filter: .search("pack #family"),
          showCompleted: false,
          ordering: .title,
          now: now
        ).map(\.reminder.title),
        ["Pack lunch"]
      )
      expectNoDifference(
        RemindersV3Presentation.rows(
          lists: lists,
          filter: .completed,
          showCompleted: true,
          ordering: .manual,
          now: now
        ).map(\.reminder.title),
        ["Archive receipts"]
      )
    }

    @Test
    func presentationOrderingMatchesUpstreamRules() {
      let reminders = fixtureLists().flatMap(\.reminders)

      expectNoDifference(
        RemindersV3Presentation.sorted(
          reminders: reminders,
          showCompleted: true,
          ordering: .priority
        ).map(\.title),
        ["Pack lunch", "Call dentist", "Buy milk", "Archive receipts"]
      )
      expectNoDifference(
        RemindersV3Presentation.sorted(
          reminders: reminders,
          showCompleted: false,
          ordering: .title
        ).map(\.title),
        ["Buy milk", "Call dentist", "Pack lunch"]
      )
    }

    @Test
    func searchPreviewAndCompletedCleanupMatchTheUpstreamPresentationRules() throws {
      let lists = fixtureLists()
      let rows = RemindersV3Presentation.rows(
        lists: lists,
        filter: .all,
        showCompleted: true,
        ordering: .manual,
        now: now
      )

      expectNoDifference(
        RemindersV3Presentation.searchPreview(
          for: try #require(rows.first { $0.reminder.title == "Pack lunch" }?.reminder),
          text: "water"
        ),
        "Fruit and water"
      )
      expectNoDifference(
        RemindersV3Presentation.completedRowsToDelete(
          rows: rows,
          scope: .olderThan(months: 12),
          now: now
        )
        .map(\.reminder.title),
        ["Archive receipts"]
      )
      expectNoDifference(
        RemindersV3Presentation.completedRowsToDelete(
          rows: rows,
          scope: .olderThan(months: 1),
          now: now
        )
        .map(\.reminder.title),
        ["Archive receipts"]
      )
      expectNoDifference(
        RemindersV3Presentation.completedRowsToDelete(
          rows: rows,
          scope: .all,
          now: now
        )
        .map(\.reminder.title),
        ["Archive receipts"]
      )
    }

    @Test
    func completedCleanupDoesNotDeleteUndatedCompletedRowsForAgedScopes() {
      let userID = InstantID<RemindersV3User>(rawValue: "user")
      let listID = InstantID<RemindersV3List>(rawValue: "list")
      let rows = [
        RemindersV3PresentationRow(
          list: RemindersV3List(
            id: listID,
            title: "List",
            color: "#4a99ef",
            position: 0,
            createdAt: now,
            owner: userID
          ),
          reminder: RemindersV3Reminder(
            id: InstantID(rawValue: "done"),
            title: "Done",
            notes: "",
            isCompleted: true,
            isFlagged: false,
            priority: nil,
            position: 0,
            createdAt: now,
            list: listID
          )
        )
      ]

      expectNoDifference(
        RemindersV3Presentation.completedRowsToDelete(
          rows: rows,
          scope: .olderThan(months: 1),
          now: now
        ),
        []
      )
      expectNoDifference(
        RemindersV3Presentation.completedRowsToDelete(
          rows: rows,
          scope: .all,
          now: now
        )
        .map(\.reminder.title),
        ["Done"]
      )
    }


    @Test
    func listPermissionsDistinguishOwnerReaderAndWriter() {
      let owner = InstantID<RemindersV3User>(rawValue: "owner")
      let reader = InstantID<RemindersV3User>(rawValue: "reader")
      let writer = InstantID<RemindersV3User>(rawValue: "writer")
      let list = RemindersV3List(
        id: InstantID(rawValue: "shared-list"),
        title: "Shared",
        color: "#4a99ef",
        position: 0,
        createdAt: now,
        owner: owner,
        readers: [reader],
        writers: [writer]
      )

      #expect(list.isOwned(by: owner))
      #expect(list.canWrite(as: owner))
      #expect(!list.isOwned(by: reader))
      #expect(!list.canWrite(as: reader))
      #expect(!list.isOwned(by: writer))
      #expect(list.canWrite(as: writer))
    }

    @Test
    func userIdentityPrefersProfileThenEmailAndBuildsBoundedLookupQueries() throws {
      let user = RemindersV3User(
        id: InstantID(rawValue: "user-1"),
        email: "aisha@example.com",
        displayName: "Aisha Rahman",
        username: "aisha"
      )
      expectNoDifference(user.remindersIdentityTitle, "Aisha Rahman")
      expectNoDifference(user.remindersIdentitySubtitle, "aisha@example.com")

      let emailOnly = RemindersV3User(
        id: InstantID(rawValue: "user-2"),
        email: "sam@example.com"
      )
      expectNoDifference(emailOnly.remindersIdentityTitle, "sam@example.com")
      expectNoDifference(emailOnly.remindersIdentitySubtitle, nil)

      let lookup = try #require(RemindersV3User.remindersUsers(matchingEmail: " Aisha "))
      expectNoDifference(
        lookup.plan.filters,
        [.iLike(field: "email", pattern: "%Aisha%")]
      )
      expectNoDifference(lookup.plan.limit, 8)
      expectNoDifference(
        RemindersV3User.remindersUsers(matchingEmail: "a"),
        nil
      )
    }

    private func fixtureLists() -> [RemindersV3List] {
      let userID = InstantID<RemindersV3User>(rawValue: "user")
      let listID = InstantID<RemindersV3List>(rawValue: "family")
      let family = RemindersV3Tag(id: InstantID(rawValue: "family-tag"), title: "family")
      let home = RemindersV3Tag(id: InstantID(rawValue: "home-tag"), title: "home")
      return [
        RemindersV3List(
          id: listID,
          title: "Family",
          color: "#4a99ef",
          position: 0,
          createdAt: now,
          owner: userID,
          reminders: [
            RemindersV3Reminder(
              id: InstantID(rawValue: "pack"),
              title: "Pack lunch",
              notes: "Fruit and water",
              isCompleted: false,
              isFlagged: true,
              dueDate: now,
              priority: .high,
              position: 2,
              createdAt: now,
              list: listID,
              tags: [family]
            ),
            RemindersV3Reminder(
              id: InstantID(rawValue: "dentist"),
              title: "Call dentist",
              notes: "",
              isCompleted: false,
              isFlagged: false,
              dueDate: now.addingTimeInterval(86_400),
              priority: .medium,
              position: 1,
              createdAt: now,
              list: listID,
              tags: [home]
            ),
            RemindersV3Reminder(
              id: InstantID(rawValue: "milk"),
              title: "Buy milk",
              notes: "",
              isCompleted: false,
              isFlagged: false,
              priority: nil,
              position: 0,
              createdAt: now,
              list: listID
            ),
            RemindersV3Reminder(
              id: InstantID(rawValue: "archive"),
              title: "Archive receipts",
              notes: "",
              isCompleted: true,
              isFlagged: true,
              dueDate: now.addingTimeInterval(-400 * 86_400),
              priority: .high,
              position: 3,
              createdAt: now,
              list: listID,
              tags: [home]
            ),
          ]
        )
      ]
    }
  }
#endif
