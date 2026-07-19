import assert from "node:assert/strict";
import test from "node:test";

import {
  acceptedReactions,
  exactReactionPayload,
} from "./reactions-v3-live-support.js";

test("live reactions support preserves exact payload keys and finite values", () => {
  assert.deepEqual(
    exactReactionPayload({ name: "heart", directionAngle: 45, rotationAngle: 270 }),
    { name: "heart", directionAngle: 45, rotationAngle: 270 },
  );
  assert.throws(
    () => exactReactionPayload({
      name: "heart",
      directionAngle: 45,
      rotationAngle: 270,
      emoji: "❤️",
    }),
    /exact reactions payload shape/i,
  );
  assert.throws(
    () => exactReactionPayload({ name: "heart", directionAngle: Number.NaN, rotationAngle: 270 }),
    /exact reactions payload shape/i,
  );
});

test("live reactions support accepts four source names and ignores unknown names", () => {
  assert.deepEqual(
    acceptedReactions([
      { name: "fire", directionAngle: 10, rotationAngle: 20 },
      { name: "wave", directionAngle: 30, rotationAngle: 40 },
      { name: "confetti", directionAngle: 50, rotationAngle: 60 },
      { name: "heart", directionAngle: 70, rotationAngle: 80 },
      { name: "sparkle", directionAngle: 90, rotationAngle: 100 },
    ]),
    [
      { name: "fire", symbol: "🔥", directionAngle: 10, rotationAngle: 20 },
      { name: "wave", symbol: "👋", directionAngle: 30, rotationAngle: 40 },
      { name: "confetti", symbol: "🎉", directionAngle: 50, rotationAngle: 60 },
      { name: "heart", symbol: "❤️", directionAngle: 70, rotationAngle: 80 },
    ],
  );
});
