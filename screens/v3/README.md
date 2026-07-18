# VoiceTrail V3 Screen Sketches

These sketches demonstrate the V3 API direction in full SwiftUI-file
examples.

The main differences from V2:

- Button closures send synchronous messages.
- Property wrappers and small models own async work.
- Auth and mutation callbacks live at the call site.
- Callback payloads are for one-off behavior.
- Rooms, presence, and topics are first-class in playback.
- `@LocalID` is shown where device identity matters.
- `@InstantSyncStatus` is shown as a UI facade over lower-level
  connection and outbox state.
- Queryable `$files` replaces ad hoc download URL and delete APIs.
- Mutation callbacks receive generated borrowed, noncopyable change
  envelopes.

Screens:

- `auth.login`: `screens/v3/auth-login.md`
- `recordings.index`: `screens/v3/recordings-list.md`
