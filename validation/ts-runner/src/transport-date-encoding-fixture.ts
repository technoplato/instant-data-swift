// Writes how @instantdb/core puts a date on the wire, for the Swift transport-date test (#403).
//
// The core leaves a JavaScript Date in an add-triple step (instaml.ts, expandUpdate) and sends the message with
// JSON.stringify (Connection.ts), so the wire string is Date.prototype.toJSON, that is toISOString(): UTC, "Z", and
// exactly three fractional digits. This script runs a real update through the core's transform, stringifies the
// steps the way the connection does, and records the string for each millisecond value.
//
//   pnpm --dir validation/ts-runner exec tsx src/transport-date-encoding-fixture.ts > ../fixtures/transport-date-encoding.json
import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const packageEntry = fileURLToPath(import.meta.resolve("@instantdb/core"));
const dist = dirname(packageEntry);
const module = async (path: string) => import(pathToFileURL(resolve(dist, path)).href);
const [schemaModule, txModule, transformModule, storeModule, linkModule, packageManifest] = await Promise.all([
  module("schema.js"),
  module("instatx.js"),
  module("instaml.js"),
  module("store.js"),
  module("utils/linkIndex.js"),
  import("@instantdb/core/package.json", { with: { type: "json" } }),
]);
const schema = schemaModule.i.schema({
  entities: { todos: schemaModule.i.entity({ createdAt: schemaModule.i.date() }) },
  links: {},
});

// Milliseconds since 1970: edges of the fractional digits, both sides of the epoch, a leap day, the last ISO year
// with four digits, and a fixed pseudo-random spread over 1970-2100 (a 64-bit LCG, so the file never changes).
const milliseconds: number[] = [
  0, 1, 10, 100, 999, -1, -1_250, 951_782_400_000, 1_700_000_000_000, 1_700_000_000_001,
  1_700_000_000_123, 1_700_000_000_999, 1_790_897_979_124, 4_102_444_800_000, 253_402_300_799_999,
];
let state = 0x2545f4914f6cdd1dn;
for (let index = 0; index < 64; index += 1) {
  state = (state * 6364136223846793005n + 1442695040888963407n) & 0xffffffffffffffffn;
  milliseconds.push(Number(state % 4_102_444_800_000n));
}

const id = "00000000-0000-4000-8000-000000000001";
const entries = milliseconds.map((value) => {
  const attrsStore = new storeModule.AttrsStoreClass({}, linkModule.createLinkIndex(schema));
  const steps = transformModule.transform(
    { attrsStore, schema },
    [txModule.tx.todos[id].update({ createdAt: new Date(value) })],
  );
  const wire = JSON.parse(JSON.stringify({ op: "transact", "tx-steps": steps }));
  const dates = wire["tx-steps"]
    .filter((step: any[]) => step[0] === "add-triple" && typeof step[3] === "string" && step[3] !== id)
    .map((step: any[]) => step[3]);
  assert.equal(dates.length, 1, `one date value for ${value}`);
  assert.equal(dates[0], new Date(value).toISOString());
  return { milliseconds: value, encoded: dates[0] };
});

process.stdout.write(
  `${JSON.stringify(
    {
      source: "@instantdb/core transform + JSON.stringify, as Connection.send writes a transact",
      coreVersion: packageManifest.default.version,
      entries,
    },
    null,
    2,
  )}\n`,
);
