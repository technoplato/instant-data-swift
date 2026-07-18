# VoiceTrail Screen Sketches

These sketches use `INSTANT_DATA_API_DESIGN_PREFERENCES_V2.md` as the source
of inspiration for a hypothetical Instant Swift Data app. They are intentionally
screen-level examples: each file names a route URI, draws the screen in ASCII,
and shows the full SwiftUI shape in one Swift block.

The purpose is to judge whether the API feels right in realistic code:

- Auth state should live in `@InstantAuth` and `db.auth`, not in view-owned
  session variables.
- Query state should live in `@FetchAll`, `@FetchOne`, and related wrappers.
- Callbacks should be optional side effects, not required state machines.
- Remote changes from other clients should be observable as remote changes, not
  hidden behind vague sync language.
- Sharing, storage, streams, roles, route data, and transcript segments should
  all read as typed Swift, without magic strings.

## Screens

- `auth.login`: `screens/v2/auth-login.md`
- `recordings.index`: `screens/v2/recordings-list.md`
- `recordings.capture`: `screens/v2/recording.md`
- `recordings.playback`: `screens/v2/playback.md`
- `settings.preferences`: `screens/v2/preferences.md`
