# Transcription (ADR 0016)

Instant-first multi-host example: recordings list, timeline, simulated speech,
floating toolbar (toolshed SyncUps stopwatch chrome, adapted).

## Local run (no Instant app id)

```sh
# SPM executable
swift run transcription

# Xcode (Mac / iOS Simulator)
./generate-project.sh
open Transcription.xcodeproj
# Schemes: TranscriptionmacOS, TranscriptioniOS
```

Unsigned Mac:

```sh
xcodebuild -project Transcription.xcodeproj -scheme TranscriptionmacOS \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
open ~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/Transcription.app
```

Live Instant: set `INSTANT_APP_ID` in the environment (or Info.plist later).

## Modeling

Entities use `@InstantEntity` only. The macro generates attributes. See
`Sources/TranscriptionApp/TranscriptionModels.swift`.
