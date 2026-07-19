import assert from "node:assert/strict";
import test from "node:test";
import { voiceTrailV3AppContract } from "./voice-trail-v3-app-contract.js";

test("VoiceTrail V3 app contract preserves every screen's exact cross-SDK shape", () => {
  const contract = voiceTrailV3AppContract({
    swiftUserID: "swift-user",
    typeScriptUserID: "typescript-user",
  });

  assert.deepEqual(contract.tabs, [
    "auth",
    "recordings",
    "capture",
    "playback",
    "preferences",
  ]);
  assert.deepEqual(contract.capture, {
    recordingID: "v3-e2e-swift-recording",
    transcriptionID: "v3-e2e-swift-transcription",
    title: "Swift E2E recording",
    ownerUserID: "swift-user",
    deviceID: "swift-e2e-device",
    state: "recording",
    durationMilliseconds: 0,
    transcriptionState: "processing",
  });
  assert.deepEqual(contract.sharing, {
    shareID: "v3-e2e-share",
    membershipID: "v3-e2e-membership",
    recordingID: "v3-e2e-typescript-recording",
    title: "TypeScript shared recording",
    ownerUserID: "typescript-user",
    memberUserID: "swift-user",
    role: "reader",
  });
  assert.equal(contract.playback.roomType, "recording.playback");
  assert.equal(contract.playback.roomID, contract.capture.recordingID);
  assert.deepEqual(contract.playback.swiftReaction, {
    emoji: "swift-wave",
    offsetSeconds: 12.5,
  });
  assert.deepEqual(contract.playback.typeScriptReaction, {
    emoji: "typescript-wave",
    offsetSeconds: 4.25,
  });
  assert.equal(Buffer.byteLength(contract.preferences.streamContent), 12);
  assert.equal(
    contract.preferences.downloadedFiles.reduce(
      (total, file) => total + file.bytes.length,
      0,
    ),
    7,
  );
  assert.deepEqual(contract.preferences.remainingFileNames, ["transcript.txt"]);
});
