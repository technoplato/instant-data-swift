import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { init } from "@instantdb/admin";

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const warnings: string[] = [];
const originalWarn = console.warn;
console.warn = (...values) => warnings.push(values.map(String).join(" "));

try {
  const db = init({ appId, adminToken, apiURI });
  const email = `auth-invalidation-${randomUUID()}@example.com`;
  const refreshToken = await db.auth.createToken({ email });
  const user = await db.auth.verifyToken(refreshToken);
  assert.ok(user?.id, "Expected canonical TypeScript verification to return a user.");

  const swift = await runSwiftAuthInvalidation({
    appId,
    apiURI,
    refreshToken,
    userID: user.id,
  });
  assert.equal(swift.ok, true);
  assert.equal(swift.details.userID, user.id);
  assert.equal(swift.details.serverVerifiedSignIn, true);
  assert.equal(swift.details.durableRelaunch, true);
  assert.equal(swift.details.localSessionCleared, true);
  assert.equal(swift.details.invalidatedTokenRejected, true);
  assert.equal(swift.details.rejectionCode, "authFailed");

  const typeScriptRejection = await rejected(db.auth.verifyToken(refreshToken));

  process.stdout.write(`${JSON.stringify({
    case: "validation.typescript.auth-live-contract",
    event: "refresh-token-invalidated",
    side: "typescript",
    appID: appId,
    ok: true,
    details: {
      userID: user.id,
      email,
      swift: swift.details,
      typeScriptRejection,
      compilerWarningCount: warnings.length,
      warnings,
    },
  }, null, 2)}\n`);
} finally {
  console.warn = originalWarn;
}

async function runSwiftAuthInvalidation(input: {
  appId: string;
  apiURI: string;
  refreshToken: string;
  userID: string;
}): Promise<{
  ok: boolean;
  details: {
    userID: string;
    serverVerifiedSignIn: boolean;
    durableRelaunch: boolean;
    localSessionCleared: boolean;
    invalidatedTokenRejected: boolean;
    rejectionCode: string;
  };
}> {
  const child = spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-auth-invalidation",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: input.appId,
        INSTANT_API_URI: input.apiURI,
        INSTANT_SWIFT_DATA_AUTH_REFRESH_TOKEN: input.refreshToken,
        INSTANT_SWIFT_DATA_AUTH_USER_ID: input.userID,
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
  const status = await new Promise<number>((resolveStatus, rejectProcess) => {
    child.once("error", rejectProcess);
    child.once("close", (code) => resolveStatus(code ?? 1));
  });
  if (status !== 0) {
    throw new Error(
      `Swift live auth validation failed with status ${status}: ${stdout.trim()} ${stderr.trim()}`,
    );
  }
  const lines = stdout.trim().split("\n").filter(Boolean);
  if (lines.length !== 1) {
    throw new Error(`Expected one Swift auth evidence row, received ${lines.length}.`);
  }
  return JSON.parse(lines[0]);
}

async function rejected(promise: Promise<unknown>): Promise<string> {
  try {
    await promise;
  } catch (error) {
    return error instanceof Error ? `${error.name}: ${error.message}` : String(error);
  }
  throw new Error("Expected the canonical TypeScript SDK to reject the invalidated token.");
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}
