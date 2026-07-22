import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = requiredEnvironment("INSTANT_SWIFT_DATA_EVIDENCE_ROOT");
const results = requiredEnvironment("INSTANT_SWIFT_DATA_EVIDENCE_RESULTS");
const sqliteDataRevision = requiredEnvironment("INSTANT_SWIFT_DATA_EVIDENCE_SQLITE_REVISION");
const instantRevision = requiredEnvironment("INSTANT_SWIFT_DATA_EVIDENCE_INSTANT_REVISION");
const read = (name: string): any => JSON.parse(
  readFileSync(resolve(results, name), "utf8"),
);
const schema = read("swift-server-schema-verify.json");
const permissions = read("swift-server-perms-verify.json");
const live = read("app-builder-v3.json");
const manifest = JSON.parse(readFileSync(resolve(root, "validation/ts-runner/package.json"), "utf8"));
const serializedLive = JSON.stringify(live);
const swiftBuildID = "00000000-0000-4000-8000-000000000602";
const typeScriptBuildID = "00000000-0000-4000-8000-000000000604";
const swiftCode = "export default function SwiftGeneratedApp() {}";
const typeScriptCode = "export default function TypeScriptGeneratedApp() {}";

assert.equal(live.ok, true);
assert.equal(serializedLive.includes("refresh_token"), false);
assert.equal(serializedLive.includes("INSTANT_ADMIN_TOKEN"), false);
assert.equal(live.details.compilerWarningCount, 0);
assert.deepEqual(live.details.warnings, []);

const swiftBuild = live.details.typeScriptObservedSwiftBuild;
assert.equal(swiftBuild.id, swiftBuildID);
assert.equal(swiftBuild.instantAppId, "platform-app-swift");
assert.equal(swiftBuild.code, swiftCode);
assert.equal(swiftBuild.reasoning, "Plan the Swift-generated screen.");
assert.equal(swiftBuild.isPreviewable, true);
assert.equal(swiftBuild.title, "Build a workout tracker");
assert.equal(swiftBuild.owner.id, live.details.user.id);
assert.equal(swiftBuild.file.path, `${swiftBuildID}-App.tsx`);
assert.equal(swiftBuild.file["content-disposition"], "inline");
assert.equal(swiftBuild.file["content-type"], "text/typescript");
assert.equal(swiftBuild.file.size, Buffer.byteLength(swiftCode));

const typeScriptBuild = live.details.typeScriptObservedTypeScriptBuild;
assert.equal(typeScriptBuild.id, typeScriptBuildID);
assert.equal(typeScriptBuild.instantAppId, "platform-app-typescript");
assert.equal(typeScriptBuild.code, typeScriptCode);
assert.equal(typeScriptBuild.reasoning, "Plan the TypeScript-generated screen.");
assert.equal(typeScriptBuild.isPreviewable, true);
assert.equal(typeScriptBuild.title, "Build a notes app");
assert.equal(typeScriptBuild.owner.id, live.details.user.id);
assert.equal(typeScriptBuild.file.path, `${typeScriptBuildID}-App.tsx`);
assert.equal(typeScriptBuild.file["content-disposition"], "inline");
assert.equal(typeScriptBuild.file["content-type"], "text/typescript");
assert.equal(typeScriptBuild.file.size, Buffer.byteLength(typeScriptCode));

assert.equal(live.details.swift.swiftBuild.id, swiftBuildID);
assert.equal(live.details.swift.swiftBuild.ownerID, live.details.user.id);
assert.equal(live.details.swift.swiftBuild.file.id, swiftBuild.file.id);
assert.equal(live.details.swift.swiftBuild.file.contents, swiftCode);
assert.equal(live.details.swift.typeScriptBuild.id, typeScriptBuildID);
assert.equal(live.details.swift.typeScriptBuild.ownerID, live.details.user.id);
assert.equal(live.details.swift.typeScriptBuild.file.id, typeScriptBuild.file.id);
assert.equal(live.details.swift.typeScriptBuild.file.contents, typeScriptCode);
assert.equal(live.details.swift.connectionState, "authenticated");
assert.equal(live.details.swift.pendingMutationCount, 0);

assert.equal(schema.entityCount, 3);
assert.equal(schema.attributeCount, 13);
assert.equal(schema.linkCount, 2);
assert.deepEqual(schema.warnings, [
  { code: "system-entity", path: "$streams" },
  { code: "system-attribute", path: "$users.imageURL" },
  { code: "system-attribute", path: "$users.type" },
  { code: "server-json-as-any", path: "builds.error" },
  { code: "canonical-link-name", path: "buildFile->buildsFile" },
  { code: "canonical-link-name", path: "buildOwner->buildsOwner" },
  { code: "system-link", path: "$streams$files" },
  { code: "system-link", path: "$usersLinkedPrimaryUser" },
]);
assert.equal(permissions.namespaceCount, 1);
assert.equal(permissions.allowRuleCount, 5);
assert.equal(permissions.rateLimitCount, 0);
const noDriftLog = readFileSync(resolve(results, "instant-cli-push-no-drift.log"), "utf8");
assert.match(noDriftLog, /No schema changes to apply!/);
assert.match(noDriftLog, /No perms changes to apply!/);

const evidence = {
  case: "validation.app-builder-v3-app.live-contract",
  event: "bidirectional-sdk-storage-summary",
  appID: process.env.INSTANT_APP_ID,
  ok: true,
  details: {
    swiftRevision: execFileSync("git", ["-C", root, "rev-parse", "HEAD"], {
      encoding: "utf8",
    }).trim(),
    worktreeDirty: process.env.WORKTREE_DIRTY === "true",
    sqliteDataRevision,
    instantRevision,
    coreVersion: manifest.dependencies["@instantdb/core"],
    adminVersion: manifest.dependencies["@instantdb/admin"],
    cliVersion: manifest.devDependencies["instant-cli"],
    typescriptVersion: manifest.devDependencies.typescript,
    compilerWarningCount: 0,
    schema: {
      entityCount: schema.entityCount,
      attributeCount: schema.attributeCount,
      linkCount: schema.linkCount,
      warnings: schema.warnings,
      sha256: sha256(resolve(results, "pull/instant.schema.ts")),
    },
    permissions: {
      namespaceCount: permissions.namespaceCount,
      allowRuleCount: permissions.allowRuleCount,
      rateLimitCount: permissions.rateLimitCount,
      sha256: sha256(resolve(results, "pull/instant.perms.ts")),
    },
    appBuilder: live.details,
  },
};
process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);

function sha256(path: string): string {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}
