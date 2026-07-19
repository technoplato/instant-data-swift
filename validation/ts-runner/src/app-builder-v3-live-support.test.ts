import assert from "node:assert/strict";
import test from "node:test";

import { projectCanonicalAppBuilderV3Build } from "./app-builder-v3-live-support.js";

test("projects the canonical nested App Builder graph", () => {
  assert.deepEqual(
    projectCanonicalAppBuilderV3Build({
      id: "build-1",
      instantAppId: "app-1",
      code: "export default function App() {}",
      reasoning: "Plan it.",
      slug: "build-1",
      error: { from: "openai", status: 429, message: "Rate limited" },
      isPreviewable: true,
      title: "Build a notes app",
      owner: { id: "user-1", email: "builder@example.com" },
      file: {
        id: "file-1",
        path: "build-1-App.tsx",
        url: "https://files.example/app",
        "content-disposition": "inline",
        "content-type": "text/typescript",
        "key-version": 1,
        "location-id": "location-1",
        size: 32,
      },
    }),
    {
      id: "build-1",
      instantAppId: "app-1",
      code: "export default function App() {}",
      reasoning: "Plan it.",
      slug: "build-1",
      error: { from: "openai", status: 429, message: "Rate limited" },
      isPreviewable: true,
      title: "Build a notes app",
      owner: { id: "user-1", email: "builder@example.com" },
      file: {
        id: "file-1",
        path: "build-1-App.tsx",
        url: "https://files.example/app",
        "content-disposition": "inline",
        "content-type": "text/typescript",
        "key-version": 1,
        "location-id": "location-1",
        size: 32,
      },
    },
  );
});

test("rejects widened and drifted App Builder shapes", () => {
  const canonical = {
    id: "build-1",
    instantAppId: "app-1",
    code: "code",
    owner: { id: "user-1" },
  };
  for (const drifted of [
    { ...canonical, extra: true },
    { ...canonical, isPreviewable: "yes" },
    { ...canonical, owner: { id: 1 } },
    { ...canonical, file: { id: "file-1", path: "App.tsx" } },
    { ...canonical, error: { from: "openai", status: 429.5, message: "bad" } },
  ]) {
    assert.throws(
      () => projectCanonicalAppBuilderV3Build(drifted),
      /canonical App Builder V3 build, owner, file, and error shapes/,
    );
  }
});
