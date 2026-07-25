# VoiceTrail V3 for Apple Watch

The Watch app opens on the recordings list, creates a recording from the
`New Recording` button, and observes the recording's transcript through an
Instant stream. Transcript producers append snapshots using the deterministic
client ID returned by:

```swift
VoiceTrailTranscriptStream.clientID(for: recordingID)
```

Each stream chunk uses this payload shape:

```json
{"text":"Current transcript text","isFinal":false}
```

Build the unsigned Apple Watch Simulator app:

```bash
Examples/VoiceTrailV3/build-watch-simulator.sh
```

Set `INSTANT_APP_ID` in an ignored `VoiceTrailV3.local.xcconfig` to use a live
Instant app. Production launches show the compact email/guest sign-in flow.
Simulator-only visual verification can launch with
`SIMCTL_CHILD_VOICE_TRAIL_DEMO_MODE=1`; demo mode uses the same local recording,
query, stream, and transcript UI paths while appending labeled sample text.
