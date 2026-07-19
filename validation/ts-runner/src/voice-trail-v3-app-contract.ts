export type VoiceTrailV3AppContract = ReturnType<typeof voiceTrailV3AppContract>;

export function voiceTrailV3AppContract(users: {
  swiftUserID: string;
  typeScriptUserID: string;
}) {
  const capture = {
    recordingID: "v3-e2e-swift-recording",
    transcriptionID: "v3-e2e-swift-transcription",
    title: "Swift E2E recording",
    ownerUserID: users.swiftUserID,
    deviceID: "swift-e2e-device",
    state: "recording",
    durationMilliseconds: 0,
    transcriptionState: "processing",
  } as const;
  return {
    tabs: ["auth", "recordings", "capture", "playback", "preferences"] as const,
    swiftUserID: users.swiftUserID,
    typeScriptUserID: users.typeScriptUserID,
    capture,
    sharing: {
      shareID: "v3-e2e-share",
      membershipID: "v3-e2e-membership",
      recordingID: "v3-e2e-typescript-recording",
      title: "TypeScript shared recording",
      ownerUserID: users.typeScriptUserID,
      memberUserID: users.swiftUserID,
      role: "reader",
    } as const,
    playback: {
      roomType: "recording.playback",
      roomID: capture.recordingID,
      swiftPresence: {
        userID: users.swiftUserID,
        displayName: "Swift Listener",
        isPlaying: true,
        offsetSeconds: 12.5,
        focusedSegmentID: "segment-swift",
      },
      typeScriptPresence: {
        userID: users.typeScriptUserID,
        displayName: "TypeScript Listener",
        isPlaying: false,
        offsetSeconds: 4.25,
        focusedSegmentID: "segment-typescript",
      },
      swiftReaction: { emoji: "swift-wave", offsetSeconds: 12.5 },
      typeScriptReaction: { emoji: "typescript-wave", offsetSeconds: 4.25 },
    } as const,
    preferences: {
      streamContent: "hello-stream",
      downloadedFiles: [
        {
          name: "recording.m4a",
          contentType: "audio/mp4",
          bytes: [0, 1, 2, 3],
          shouldClear: true,
        },
        {
          name: "transcript.txt",
          contentType: "text/plain",
          bytes: [4, 5, 6],
          shouldClear: false,
        },
      ],
      remainingFileNames: ["transcript.txt"],
    } as const,
  };
}
