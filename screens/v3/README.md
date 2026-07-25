# VoiceTrail V3 Screen Sketches

These sketches demonstrate the V3 API direction in full SwiftUI-file examples.
They are design targets, not a complete current symbol inventory. For code that
must compile today, `Sources/` and the compiling fixtures in `Tests/` are
authoritative. In particular, projection/fetch-builder spellings shown in a
sketch may not exist yet and must be confirmed in source before use.

The main differences from V2:

- Button closures send synchronous messages.
- Property wrappers and small models own async work.
- Static `@FetchAll`, `@FetchOne`, and `@Fetch` declarations observe
  local-first without a task or manual load.
- Dynamic query inputs replace wrapper-owned observations; features never
  fetch, subscribe, and merge composite values themselves.
- Auth and mutation callbacks live at the call site.
- Callback payloads are for one-off behavior.
- Rooms, presence, and topics are first-class in playback.
- `@LocalID` is shown where device identity matters.
- `@InstantSyncStatus` appears only in Preferences as an explicit user-visible
  operation over otherwise library-owned delivery state.
- Queryable `$files` replaces ad hoc download URL and delete APIs.
- Mutation callbacks borrow generated change envelopes. Truly noncopyable
  generic envelopes remain the language/toolchain target recorded in the V3
  design document.
- Normal feature screens do not know about local materialization, outbox,
  reconnect, delivery, or rejected-stream mechanics.

Screens:

- `auth.login`: `screens/v3/auth-login.md`
- `recordings.index`: `screens/v3/recordings-list.md`
- `recordings.capture`: `screens/v3/recording.md`
- `recordings.playback`: `screens/v3/playback.md`
- `settings.preferences`: `screens/v3/preferences.md`
