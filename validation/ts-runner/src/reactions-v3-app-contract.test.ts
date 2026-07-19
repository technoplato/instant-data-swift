import assert from "node:assert/strict";
import test from "node:test";

import { reactionsV3AppContract } from "./reactions-v3-app-contract.js";

test("Reactions V3 preserves the exact canonical room topic shapes", () => {
  assert.deepEqual(reactionsV3AppContract, {
    upstream: {
      repository: "https://github.com/instantdb/instant",
      revision: "e71017612aed4031710a35e2fcace30d38d557ac",
      recipe: "client/www/lib/recipes/reactions.tsx",
      helper: "client/packages/react-common/src/InstantReactRoom.ts",
      helperTests: "client/packages/vue/src/tests/InstantVueDatabase.test.ts",
    },
    room: {
      type: "topics-example",
      id: "123",
      topic: "emoji",
    },
    reactions: {
      fire: "🔥",
      wave: "👋",
      confetti: "🎉",
      heart: "❤️",
    },
    swiftPublished: {
      name: "heart",
      directionAngle: 45,
      rotationAngle: 270,
    },
    typeScriptPublished: {
      name: "wave",
      directionAngle: 90,
      rotationAngle: 180,
    },
    invalidReceivedName: "sparkle",
    compilerWarningCount: 0,
  });
});
