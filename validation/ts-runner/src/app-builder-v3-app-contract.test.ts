import assert from "node:assert/strict";
import test from "node:test";

import { appBuilderV3AppContract } from "./app-builder-v3-app-contract.js";

test("App Builder V3 pins the exact source, graph, and storage adaptation", () => {
  assert.deepEqual(appBuilderV3AppContract.upstream, {
    instant: {
      repository: "https://github.com/instantdb/instant",
      revision: "e71017612aed4031710a35e2fcace30d38d557ac",
      source: "client/www/_examples/app-builder.md",
    },
    app: {
      repository: "https://github.com/Galaxies-dev/app-builder",
      revision: "e67200cc70e01d88bd9a5382cf0380f4882fb8c7",
      sources: ["instant.schema.ts", "instant.perms.ts", "app/api/generate+api.tsx"],
    },
  });
  assert.deepEqual(appBuilderV3AppContract.namespaces, ["$files", "$users", "builds"]);
  assert.deepEqual(appBuilderV3AppContract.links, ["buildFile", "buildOwner"]);
  assert.deepEqual(appBuilderV3AppContract.fixtures, {
    user: "00000000-0000-4000-8000-000000000601",
    swiftBuild: "00000000-0000-4000-8000-000000000602",
    swiftFile: "00000000-0000-4000-8000-000000000603",
    typeScriptBuild: "00000000-0000-4000-8000-000000000604",
    typeScriptFile: "00000000-0000-4000-8000-000000000605",
  });
});

test("App Builder V3 preserves exact generated code and file paths", () => {
  assert.deepEqual(appBuilderV3AppContract.swift, {
    title: "Build a workout tracker",
    instantAppId: "platform-app-swift",
    reasoning: "Plan the Swift-generated screen.",
    code: "export default function SwiftGeneratedApp() {}",
    filePath: "00000000-0000-4000-8000-000000000602-App.tsx",
  });
  assert.deepEqual(appBuilderV3AppContract.typeScript, {
    title: "Build a notes app",
    instantAppId: "platform-app-typescript",
    reasoning: "Plan the TypeScript-generated screen.",
    code: "export default function TypeScriptGeneratedApp() {}",
    filePath: "00000000-0000-4000-8000-000000000604-App.tsx",
  });
  assert.equal(appBuilderV3AppContract.compilerWarningCount, 0);
});
