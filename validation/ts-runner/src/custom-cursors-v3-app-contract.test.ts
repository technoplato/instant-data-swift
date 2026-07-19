import assert from "node:assert/strict";
import test from "node:test";

import {
  customCursorsV3AppContract,
  customCursorPresence,
  nameOnlyCustomCursorPresence,
} from "./custom-cursors-v3-app-contract.js";

test("Custom Cursors V3 preserves name plus exact dynamic cursor presence", () => {
  assert.deepEqual(customCursorsV3AppContract, {
    upstream: {
      repository: "https://github.com/instantdb/instant",
      revision: "e71017612aed4031710a35e2fcace30d38d557ac",
      recipe: "client/www/lib/recipes/custom-cursors.tsx",
      component: "client/packages/react/src/Cursors.tsx",
    },
    room: {
      type: "cursors-example",
      id: "124",
      spaceID: "cursors-space-default--cursors-example-124",
    },
    fixtures: {
      swift: {
        name: "swift-custom-avatar",
        cursor: {
          x: 150,
          y: 90,
          xPercent: 25,
          yPercent: 40,
          color: "#123456",
        },
      },
      typeScript: {
        name: "typescript-custom-avatar",
        cursor: {
          x: 300,
          y: 200,
          xPercent: 75,
          yPercent: 60,
          color: "#654321",
        },
      },
    },
    compilerWarningCount: 0,
  });
});

test("Custom Cursors V3 clear retains name-only rendering presence", () => {
  const fixture = customCursorsV3AppContract.fixtures.swift;
  assert.deepEqual(
    customCursorPresence(fixture.name, fixture.cursor),
    {
      name: fixture.name,
      [customCursorsV3AppContract.room.spaceID]: fixture.cursor,
    },
  );
  assert.deepEqual(
    nameOnlyCustomCursorPresence(fixture.name),
    { name: fixture.name },
  );
});
