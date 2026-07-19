import assert from "node:assert/strict";
import test from "node:test";

import {
  avatarStackV3AppContract,
  nameForAvatarStackUserID,
} from "./avatar-stack-v3-app-contract.js";

test("Avatar Stack V3 preserves the exact canonical name-only presence shape", () => {
  assert.deepEqual(avatarStackV3AppContract, {
    upstream: {
      repository: "https://github.com/instantdb/instant",
      revision: "e71017612aed4031710a35e2fcace30d38d557ac",
      recipe: "client/www/lib/recipes/avatar-stack.tsx",
      helper: "client/packages/react-common/src/InstantReactRoom.ts",
      helperTests: "client/packages/vue/src/tests/InstantVueDatabase.test.ts",
    },
    room: {
      type: "avatars-example",
      id: "avatars-example-1234",
    },
    fixtures: {
      swift: { userID: "abcdef123456", presence: { name: "abcdef" } },
      typeScript: { userID: "uvwxyz123456", presence: { name: "uvwxyz" } },
    },
    compilerWarningCount: 0,
  });
  assert.equal(nameForAvatarStackUserID("abcdef123456"), "abcdef");
  assert.equal(nameForAvatarStackUserID("tiny"), "tiny");
});
