import Dependencies
import Foundation
import InstantSwiftData

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public struct SyncUpsV3Screen: View {
    @FetchAll(SyncUpsV3SyncUp.list) private var syncUps: [SyncUpsV3SyncUp]
    @Dependency(\.uuid) private var uuid

    @State private var form: SyncUpsV3FormState?

    public init() {}

    public var body: some View {
      NavigationStack {
        List(syncUps) { syncUp in
          NavigationLink {
            SyncUpsV3DetailScreen(syncUp: syncUp)
          } label: {
            VStack(alignment: .leading) {
              Text(syncUp.title)
                .font(.headline)
              Text("\(syncUp.attendees.count) attendees · \(syncUp.seconds / 60) minutes")
                .font(.caption)
            }
          }
        }
        .navigationTitle("Daily Sync-ups")
        .toolbar {
          Button("Add sync-up", systemImage: "plus", action: addSyncUpButtonTapped)
        }
      }
      .sheet(item: $form) { form in
        NavigationStack {
          SyncUpsV3FormScreen(form: form)
            .navigationTitle("New sync-up")
        }
      }
    }

    private func addSyncUpButtonTapped() {
      form = SyncUpsV3FormState(
        blankAttendeeID: InstantID(rawValue: uuid().uuidString.lowercased())
      )
    }
  }

  @MainActor
  public struct SyncUpsV3DetailScreen: View {
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.uuid) private var uuid

    @State private var form: SyncUpsV3FormState?
    @State private var recording: SyncUpsV3RecordingState?
    @State private var message = ""

    public let syncUp: SyncUpsV3SyncUp

    public init(syncUp: SyncUpsV3SyncUp) {
      self.syncUp = syncUp
    }

    public var body: some View {
      List {
        Section("Sync-up Info") {
          Button("Start Meeting", systemImage: "timer", action: startMeetingButtonTapped)
          LabeledContent("Length", value: "\(syncUp.seconds / 60) minutes")
          LabeledContent("Theme", value: syncUp.theme.rawValue)
        }
        if !syncUp.meetings.isEmpty {
          Section("Past meetings") {
            ForEach(syncUp.meetings) { meeting in
              NavigationLink {
                SyncUpsV3MeetingScreen(meeting: meeting, attendees: syncUp.attendees)
              } label: {
                Text(meeting.date, format: .dateTime)
              }
            }
          }
        }
        Section("Attendees") {
          ForEach(syncUp.attendees) { attendee in
            Label(attendee.name, systemImage: "person")
          }
        }
        Section {
          Button("Delete", role: .destructive, action: deleteButtonTapped)
        }
        if !message.isEmpty {
          Text(message)
        }
      }
      .navigationTitle(syncUp.title)
      .toolbar {
        Button("Edit", action: editButtonTapped)
      }
      .sheet(item: $form) { form in
        NavigationStack {
          SyncUpsV3FormScreen(form: form)
            .navigationTitle(syncUp.title)
        }
      }
      .sheet(item: $recording) { recording in
        NavigationStack {
          SyncUpsV3RecordMeetingScreen(recording: recording)
        }
      }
    }

    private func editButtonTapped() {
      let draftIDs = syncUp.attendees.map { _ in
        InstantID<SyncUpsV3Attendee>(rawValue: uuid().uuidString.lowercased())
      }
      form = SyncUpsV3FormState(
        syncUp: syncUp,
        attendeeDraftIDs: draftIDs,
        blankAttendeeID: InstantID(rawValue: uuid().uuidString.lowercased())
      )
    }

    private func startMeetingButtonTapped() {
      recording = SyncUpsV3RecordingState(syncUp: syncUp, attendees: syncUp.attendees)
    }

    private func deleteButtonTapped() {
      db.send(
        DeleteSyncUpsV3SyncUp(syncUpID: syncUp.id),
        onServerAccepted: { _ in message = "Sync-up deleted" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }
  }

  @MainActor
  public struct SyncUpsV3FormScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.uuid) private var uuid

    @State private var form: SyncUpsV3FormState
    @State private var message = ""

    public init(form: SyncUpsV3FormState) {
      _form = State(initialValue: form)
    }

    public var body: some View {
      Form {
        Section("Sync-up Info") {
          TextField("Title", text: $form.title)
          Slider(value: $form.durationMinutes, in: 5...30, step: 1) {
            Text("Length")
          }
          Text("\(form.seconds / 60) minutes")
          Picker("Theme", selection: $form.theme) {
            ForEach(SyncUpsV3Theme.allCases, id: \.self) { theme in
              Text(theme.rawValue).tag(theme)
            }
          }
        }
        Section("Attendees") {
          ForEach($form.attendees) { $attendee in
            TextField("Name", text: $attendee.name)
          }
          .onDelete(perform: deleteAttendees)
          Button("New attendee", action: addAttendeeButtonTapped)
        }
        if !message.isEmpty {
          Text(message)
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: cancelButtonTapped)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: saveButtonTapped)
        }
      }
    }

    private func addAttendeeButtonTapped() {
      form.addAttendeeButtonTapped(
        id: InstantID(rawValue: uuid().uuidString.lowercased())
      )
    }

    private func deleteAttendees(atOffsets indices: IndexSet) {
      form.deleteAttendees(
        atOffsets: indices,
        blankAttendeeID: InstantID(rawValue: uuid().uuidString.lowercased())
      )
    }

    private func cancelButtonTapped() {
      form.cancelButtonTapped()
      dismiss()
    }

    private func saveButtonTapped() {
      let message = form.saveButtonTapped(
        newSyncUpID: InstantID(rawValue: uuid().uuidString.lowercased()),
        blankAttendeeID: InstantID(rawValue: uuid().uuidString.lowercased())
      )
      db.send(
        message,
        onOptimisticCommit: { saved in
          form.commit(saved)
          dismiss()
        },
        onFailure: { error in self.message = error.recoveryMessage }
      )
    }
  }

  public struct SyncUpsV3RecordingState: Equatable, Identifiable, Sendable {
    public var id: InstantID<SyncUpsV3SyncUp> { syncUp.id }
    public var syncUp: SyncUpsV3SyncUp
    public var attendees: [SyncUpsV3Attendee]
    public var secondsElapsed: Int
    public var speakerIndex: Int
    public var transcript: String

    public init(
      syncUp: SyncUpsV3SyncUp,
      attendees: [SyncUpsV3Attendee],
      secondsElapsed: Int = 0,
      speakerIndex: Int = 0,
      transcript: String = ""
    ) {
      self.syncUp = syncUp
      self.attendees = attendees
      self.secondsElapsed = secondsElapsed
      self.speakerIndex = speakerIndex
      self.transcript = transcript
    }

    public var durationRemaining: Int {
      max(0, syncUp.seconds - secondsElapsed)
    }

    public mutating func nextButtonTapped() {
      guard !attendees.isEmpty else { return }
      speakerIndex = min(speakerIndex + 1, attendees.count - 1)
      secondsElapsed = min(
        syncUp.seconds,
        speakerIndex * max(1, syncUp.seconds / attendees.count)
      )
    }
  }

  @MainActor
  public struct SyncUpsV3RecordMeetingScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Dependency(\.date.now) private var now
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.uuid) private var uuid

    @State private var recording: SyncUpsV3RecordingState
    @State private var message = ""

    public init(recording: SyncUpsV3RecordingState) {
      _recording = State(initialValue: recording)
    }

    public var body: some View {
      Form {
        Section("Current speaker") {
          Text(currentSpeakerName)
            .font(.title)
          ProgressView(
            value: Double(recording.secondsElapsed),
            total: Double(max(1, recording.syncUp.seconds))
          )
          LabeledContent("Time remaining", value: "\(recording.durationRemaining) seconds")
          Button("Next speaker", action: nextButtonTapped)
        }
        Section("Transcript") {
          TextEditor(text: $recording.transcript)
        }
        if !message.isEmpty {
          Text(message)
        }
      }
      .navigationTitle(recording.syncUp.title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Discard", role: .destructive) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save and end", action: saveAndEndButtonTapped)
        }
      }
    }

    private var currentSpeakerName: String {
      recording.attendees.indices.contains(recording.speakerIndex)
        ? recording.attendees[recording.speakerIndex].name
        : "Someone"
    }

    private func nextButtonTapped() {
      recording.nextButtonTapped()
    }

    private func saveAndEndButtonTapped() {
      db.send(
        RecordSyncUpsV3Meeting(
          meetingID: InstantID(rawValue: uuid().uuidString.lowercased()),
          syncUpID: recording.syncUp.id,
          date: now,
          transcript: recording.transcript
        ),
        onOptimisticCommit: { _ in dismiss() },
        onFailure: { error in message = error.recoveryMessage }
      )
    }
  }

  public struct SyncUpsV3MeetingScreen: View {
    public let meeting: SyncUpsV3Meeting
    public let attendees: [SyncUpsV3Attendee]

    public init(meeting: SyncUpsV3Meeting, attendees: [SyncUpsV3Attendee]) {
      self.meeting = meeting
      self.attendees = attendees
    }

    public var body: some View {
      List {
        Section("Attendees") {
          ForEach(attendees) { attendee in
            Text(attendee.name)
          }
        }
        Section("Transcript") {
          Text(meeting.transcript)
        }
      }
      .navigationTitle(Text(meeting.date, format: .dateTime))
    }
  }
#endif
