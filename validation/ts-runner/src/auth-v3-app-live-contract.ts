import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { init } from "@instantdb/admin";

import { authV3AppContract } from "./auth-v3-app-contract.js";

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const warnings: string[] = [];
const originalWarn = console.warn;
console.warn = (...values) => warnings.push(values.map(String).join(" "));

try {
  const db = init({ appId, adminToken, apiURI });
  const email = `auth-v3-${randomUUID()}@example.com`;
  const refreshToken = await db.auth.createToken({ email });
  const user = await db.auth.verifyToken(refreshToken);
  assert.ok(user?.id, "Expected canonical TypeScript verification to return an Auth V3 user.");

  const swift = await runSwiftAuthV3App({
    appId,
    apiURI,
    refreshToken,
    userID: user.id,
  });
  assert.equal(swift.ok, true);
  assert.equal(swift.event, "app-owned-auth-lifecycle-observed");
  assert.deepEqual(swift.details, {
    userNamespace: authV3AppContract.userNamespace,
    providerIDs: authV3AppContract.providerIDs,
    signedInStatus: authV3AppContract.statuses.signedIn,
    relaunchedStatus: authV3AppContract.statuses.relaunched,
    signedOutStatus: authV3AppContract.statuses.signedOut,
    auth: {
      userID: user.id,
      serverVerifiedSignIn: true,
      durableRelaunch: true,
      localSessionCleared: true,
      invalidatedTokenRejected: true,
      rejectionCode: authV3AppContract.rejectionCode,
    },
  });

  const typeScriptRejection = await rejected(db.auth.verifyToken(refreshToken));
  assert.match(typeScriptRejection, /record not found|app-user|400|auth/i);
  assert.deepEqual(warnings, []);

  process.stdout.write(`${JSON.stringify({
    case: "validation.typescript.auth-v3-app-live-contract",
    event: "app-owned-auth-lifecycle-observed",
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

interface SwiftAuthV3AppDetails {
  userNamespace: string;
  providerIDs: string[];
  signedInStatus: string;
  relaunchedStatus: string;
  signedOutStatus: string;
  auth: {
    userID: string;
    serverVerifiedSignIn: boolean;
    durableRelaunch: boolean;
    localSessionCleared: boolean;
    invalidatedTokenRejected: boolean;
    rejectionCode: string;
  };
}

async function runSwiftAuthV3App(input: {
  appId: string;
  apiURI: string;
  refreshToken: string;
  userID: string;
}): Promise<{ ok: boolean; event: string; details: SwiftAuthV3AppDetails }> {
  const child = spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-auth-v3-app",
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
      `Swift Auth V3 app validation failed with status ${status}: ${stdout.trim()} ${stderr.trim()}`,
    );
  }
  const lines = stdout.trim().split("\n").filter(Boolean);
  assert.equal(lines.length, 1, "Expected one Swift Auth V3 evidence row.");
  return JSON.parse(lines[0]);
}

async function rejected(promise: Promise<unknown>): Promise<string> {
  try {
    await promise;
  } catch (error) {
    return error instanceof Error ? `${error.name}: ${error.message}` : String(error);
  }
  throw new Error("Expected canonical TypeScript to reject the invalidated Auth V3 token.");
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}
