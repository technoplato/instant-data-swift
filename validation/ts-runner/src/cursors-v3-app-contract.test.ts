import assert from "node:assert/strict";
import test from "node:test";

import {
  cursorForPoint,
  cursorsV3AppContract,
  darkCursorColor,
} from "./cursors-v3-app-contract.js";

test("Cursors V3 preserves the exact canonical dynamic presence shape", () => {
  assert.deepEqual(cursorsV3AppContract, {
    upstream: {
      repository: "https://github.com/instantdb/instant",
      revision: "e71017612aed4031710a35e2fcace30d38d557ac",
      recipe: "client/www/lib/recipes/cursors.tsx",
      component: "client/packages/react/src/Cursors.tsx",
    },
    room: {
      type: "cursors-example",
      id: "123",
      spaceID: "cursors-space-default--cursors-example-123",
    },
    fixtures: {
      swift: {
        x: 150,
        y: 90,
        xPercent: 25,
        yPercent: 40,
        color: "#123456",
      },
      typeScript: {
        x: 300,
        y: 200,
        xPercent: 75,
        yPercent: 60,
        color: "#654321",
      },
    },
    compilerWarningCount: 0,
  });
});

test("Cursors V3 preserves canonical viewport math and dark hex formatting", () => {
  assert.deepEqual(
    cursorForPoint(
      { clientX: 150, clientY: 90 },
      { left: 100, top: 50, width: 200, height: 100 },
      "#123456",
    ),
    cursorsV3AppContract.fixtures.swift,
  );
  assert.equal(darkCursorColor(0, 15, 199), "#000fc7");
});
