import assert from "node:assert/strict";
import test from "node:test";
import { preferencesContract } from "./preferences-sdk-contract.js";

test("preferences contract preserves exact sync and local storage values", () => {
  const contract = preferencesContract({ swiftUserID: "swift-user" });

  assert.equal(contract.swiftUserID, "swift-user");
  assert.deepEqual(contract.phaseSequence, ["connected", "authenticated"]);
  assert.equal(contract.streamContent, "hello-stream");
  assert.equal(Buffer.byteLength(contract.streamContent), 12);
  assert.deepEqual(contract.downloadedFiles, [
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
  ]);
});
