import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { init as initAdmin } from "@instantdb/admin";
import { preferencesContract } from "./preferences-sdk-contract.js";

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const websocketURI = process.env.INSTANT_WEBSOCKET_URI
  ?? "wss://api.instantdb.com/runtime/session";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const suffix = randomUUID();
const warnings: string[] = [];
const originalWarn = console.warn;
console.warn = (...values) => warnings.push(values.map(String).join(" "));

try {
  const admin = initAdmin({ appId, adminToken, apiURI });
  const refreshToken = await admin.auth.createToken({
    email: `preferences-swift-${suffix}@example.com`,
  });
  const user = await admin.auth.verifyToken(refreshToken);
  assert.ok(user?.id, "Expected a canonical preferences user.");
  const contract = preferencesContract({ swiftUserID: user.id });
  const swift = await runSwiftPreferences({
    appId,
    apiURI,
    websocketURI,
    refreshToken,
    userID: user.id,
  });

  assert.equal(swift.ok, true);
  assert.equal(swift.case, "validation.live.preferences");
  assert.equal(swift.details.userID, contract.swiftUserID);
  assert.deepEqual(swift.details.phaseSequence, contract.phaseSequence);
  assert.equal(swift.details.connectionState, "authenticated");
  assert.ok(swift.details.localCacheSize > 0);
  assert.equal(
    swift.details.streamCacheSize,
    Buffer.byteLength(contract.streamContent),
  );
  const totalDownloadedBytes = contract.downloadedFiles.reduce(
    (total, file) => total + file.bytes.length,
    0,
  );
  const clearedFiles = contract.downloadedFiles.filter((file) => file.shouldClear);
  assert.equal(swift.details.downloadedFileSizeBeforeClear, totalDownloadedBytes);
  assert.equal(swift.details.downloadedFileCountBeforeClear, contract.downloadedFiles.length);
  assert.equal(swift.details.clearedFileCount, clearedFiles.length);
  assert.equal(
    swift.details.clearedBytes,
    clearedFiles.reduce((total, file) => total + file.bytes.length, 0),
  );
  assert.equal(swift.details.downloadedFileSizeAfterClear, 3);
  assert.equal(swift.details.downloadedFileCountAfterClear, 1);
  assert.deepEqual(swift.details.remainingFileNames, ["transcript.txt"]);
  assert.deepEqual(warnings, []);

  process.stdout.write(`${JSON.stringify({
    case: "validation.typescript.preferences-live-contract",
    event: "summary",
    side: "typescript",
    appID: appId,
    ok: true,
    details: {
      user: { id: user.id, email: user.email },
      contract,
      swift: swift.details,
      compilerWarningCount: warnings.length,
      warnings,
    },
  }, null, 2)}\n`);
} finally {
  console.warn = originalWarn;
}

async function runSwiftPreferences(input: {
  appId: string;
  apiURI: string;
  websocketURI: string;
  refreshToken: string;
  userID: string;
}): Promise<any> {
  const child = spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-preferences",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: input.appId,
        INSTANT_API_URI: input.apiURI,
        INSTANT_WEBSOCKET_URI: input.websocketURI,
        INSTANT_SWIFT_DATA_PREFERENCES_REFRESH_TOKEN: input.refreshToken,
        INSTANT_SWIFT_DATA_PREFERENCES_USER_ID: input.userID,
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const exitCode = await new Promise<number>((resolveCode, reject) => {
    child.once("error", reject);
    child.once("close", (code) => resolveCode(code ?? 1));
  });
  if (exitCode !== 0) {
    throw new Error(
      `Swift preferences validation failed with status ${exitCode}: ${stdout.trim()} ${stderr.trim()}`,
    );
  }
  const lines = stdout.trim().split("\n").filter(Boolean);
  if (lines.length !== 1) {
    throw new Error(`Expected one Swift preferences evidence row, received ${lines.length}.`);
  }
  return JSON.parse(lines[0]);
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}
