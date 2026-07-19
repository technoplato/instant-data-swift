import assert from "node:assert/strict";
import test from "node:test";

import { todosV3AppContract } from "./todos-v3-app-contract.js";

test("Todos V3 app contract preserves exact bidirectional SDK shapes", () => {
  assert.deepEqual(todosV3AppContract, {
    namespace: "todos",
    roomType: "todos",
    swiftCreated: {
      id: "todos-v3-swift",
      text: "Swift live todo",
      isCompleted: true,
      createdAtMilliseconds: 1_700_000_000_000,
    },
    typeScriptCreated: {
      id: "todos-v3-typescript",
      text: "TypeScript live todo",
      isCompleted: false,
      createdAtMilliseconds: 1_700_000_001_000,
    },
  });
});
