import assert from "node:assert/strict";
import { spawn, type ChildProcessByStdio } from "node:child_process";
import { dirname, resolve } from "node:path";
import { createInterface } from "node:readline";
import type { Readable } from "node:stream";
import { fileURLToPath, pathToFileURL } from "node:url";
import { init as initAdmin } from "@instantdb/admin";
import {
  init as initCore,
  StoreInterface,
  type StoreInterfaceStoreName,
} from "@instantdb/core";
import WebSocket from "ws";

import {
  appBuilderV3AppContract,
  type AppBuilderV3Build,
} from "./app-builder-v3-app-contract.js";
import { projectCanonicalAppBuilderV3Build } from "./app-builder-v3-live-support.js";

type SwiftProcess = ChildProcessByStdio<null, Readable, Readable>;

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const schemaPath = requiredEnvironment("INSTANT_SWIFT_DATA_APP_BUILDER_SCHEMA_PATH");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const websocketURI = process.env.INSTANT_WEBSOCKET_URI
  ?? "wss://api.instantdb.com/runtime/session";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const warnings: string[] = [];
const originalWarn = console.warn;
console.warn = (...values) => warnings.push(values.map(String).join(" "));

class MemoryStore extends StoreInterface {
  private readonly values = new Map<string, unknown>();

  constructor(appID: string, storeName: StoreInterfaceStoreName) {
    super(appID, storeName);
  }

  async getItem(key: string): Promise<unknown> {
    return this.values.get(key) ?? null;
  }

  async removeItem(key: string): Promise<void> {
    this.values.delete(key);
  }

  async multiSet(entries: Array<[string, unknown]>): Promise<void> {
    for (const [key, value] of entries) this.values.set(key, value);
  }

  async getAllKeys(): Promise<string[]> {
    return [...this.values.keys()];
  }
}

class AlwaysOnline {
  static async getIsOnline(): Promise<boolean> {
    return true;
  }

  static listen(_listener: (isOnline: boolean) => void): () => void {
    return () => {};
  }
}

let swift: SwiftProcess | undefined;
let db: any;

try {
  const admin = initAdmin({ appId, adminToken, apiURI });
  const refreshToken = await admin.auth.createToken({
    email: `app-builder-v3-${appId}@example.com`,
  });
  const user = await admin.auth.verifyToken(refreshToken);
  assert.ok(user?.id, "Expected a canonical App Builder V3 user.");

  const schema = unwrapSchema(await import(pathToFileURL(schemaPath).href));
  (globalThis as any).window = globalThis;
  (globalThis as any).BroadcastChannel = undefined;
  (globalThis as any).WebSocket = WebSocket;
  db = initCore(
    {
      appId,
      apiURI,
      websocketURI,
      schema,
      devtool: false,
      useDateObjects: true,
    },
    MemoryStore,
    AlwaysOnline,
  );
  await db.auth.signInWithToken(refreshToken);

  swift = spawnSwift(refreshToken, user.id);
  const stderr = collectStderr(swift);
  const lines = createInterface({ input: swift.stdout, crlfDelay: Infinity })
    [Symbol.asyncIterator]();
  const ready = await nextJSONLine(lines, swift, "Swift App Builder build readiness");
  assert.equal(ready.event, "swift-build-ready", JSON.stringify(ready));
  assert.equal(ready.ok, true);

  const swiftBuild = await waitForBuild(
    db,
    appBuilderV3AppContract.fixtures.swiftBuild,
    (build) => build.code === appBuilderV3AppContract.swift.code
      && build.reasoning === appBuilderV3AppContract.swift.reasoning
      && build.isPreviewable === true
      && build.owner.id === user.id
      && build.file?.path === appBuilderV3AppContract.swift.filePath,
  );
  assert.equal(await fetchText(swiftBuild.file?.url), appBuilderV3AppContract.swift.code);

  const typeScriptUpload = await db.storage.uploadFile(
    appBuilderV3AppContract.typeScript.filePath,
    new Blob([appBuilderV3AppContract.typeScript.code], { type: "text/typescript" }),
    { contentType: "text/typescript" },
  );
  const typeScriptFileID = typeScriptUpload.data.id;
  assert.ok(typeScriptFileID);
  await db.transact(
    db.tx.builds[appBuilderV3AppContract.fixtures.typeScriptBuild]
      .update({
        instantAppId: appBuilderV3AppContract.typeScript.instantAppId,
        code: appBuilderV3AppContract.typeScript.code,
        reasoning: appBuilderV3AppContract.typeScript.reasoning,
        isPreviewable: true,
        title: appBuilderV3AppContract.typeScript.title,
      })
      .link({ owner: user.id, file: typeScriptFileID }),
  );

  const observed = await nextJSONLine(lines, swift, "Swift App Builder TypeScript observation");
  assert.equal(observed.event, "typescript-build-observed", JSON.stringify(observed));
  assert.equal(observed.ok, true);
  const swiftEvidence = await nextJSONLine(lines, swift, "Swift App Builder final evidence");
  await requireSuccessfulExit(swift, stderr, "Swift App Builder runner");
  swift = undefined;
  assert.equal(swiftEvidence.event, "typescript-build-observed");
  assert.equal(swiftEvidence.ok, true);
  assert.equal(swiftEvidence.details.connectionState, "authenticated");
  assert.equal(swiftEvidence.details.pendingMutationCount, 0);
  assert.equal(swiftEvidence.details.swiftBuild.file.contents, appBuilderV3AppContract.swift.code);
  assert.equal(
    swiftEvidence.details.typeScriptBuild.file.contents,
    appBuilderV3AppContract.typeScript.code,
  );

  const typeScriptBuild = await waitForBuild(
    db,
    appBuilderV3AppContract.fixtures.typeScriptBuild,
    (build) => build.file?.id === typeScriptFileID
      && build.code === appBuilderV3AppContract.typeScript.code,
  );
  assert.equal(
    await fetchText(typeScriptBuild.file?.url),
    appBuilderV3AppContract.typeScript.code,
  );
  assert.deepEqual(warnings, []);

  const output = {
    case: "validation.typescript.app-builder-v3-live-contract",
    event: "bidirectional-app-builder-observed",
    side: "typescript",
    appID: appId,
    ok: true,
    details: {
      user: { id: user.id, email: user.email },
      typeScriptObservedSwiftBuild: swiftBuild,
      typeScriptObservedTypeScriptBuild: typeScriptBuild,
      swift: swiftEvidence.details,
      compilerWarningCount: warnings.length,
      warnings,
    },
  };
  const serialized = JSON.stringify(output);
  assert.equal(serialized.includes("refresh_token"), false);
  assert.equal(serialized.includes(adminToken), false);
  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
} finally {
  console.warn = originalWarn;
  db?.shutdown();
  if (swift && swift.exitCode === null) swift.kill();
}

function buildQuery(buildID: string): any {
  return {
    builds: {
      $: { where: { id: buildID } },
      owner: {},
      file: {},
    },
  };
}

async function waitForBuild(
  database: any,
  buildID: string,
  predicate: (build: AppBuilderV3Build) => boolean,
): Promise<AppBuilderV3Build> {
  let last: unknown;
  for (let attempt = 0; attempt < 300; attempt += 1) {
    const result = await database.queryOnce(buildQuery(buildID));
    last = result.data;
    const raw = result.data.builds?.[0];
    if (raw) {
      let build: AppBuilderV3Build;
      try {
        build = projectCanonicalAppBuilderV3Build(raw);
      } catch (error) {
        throw new Error(
          `Could not project canonical App Builder build: ${String(error)}; raw=${JSON.stringify(raw)}`,
        );
      }
      if (predicate(build)) return build;
    }
    await delay();
  }
  throw new Error(`Timed out waiting for canonical App Builder build: ${JSON.stringify(last)}`);
}

function spawnSwift(refreshToken: string, userID: string): SwiftProcess {
  return spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-app-builder-v3",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: appId,
        INSTANT_API_URI: apiURI,
        INSTANT_WEBSOCKET_URI: websocketURI,
        INSTANT_SWIFT_DATA_APP_BUILDER_REFRESH_TOKEN: refreshToken,
        INSTANT_SWIFT_DATA_APP_BUILDER_USER_ID: userID,
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
}

function collectStderr(child: SwiftProcess): () => string {
  let output = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk) => { output += chunk; });
  return () => output;
}

async function nextJSONLine(
  lines: AsyncIterator<string>,
  child: SwiftProcess,
  operation: string,
): Promise<any> {
  const result = await withTimeout(lines.next(), operation);
  if (result.done) throw new Error(`${operation} ended before producing evidence.`);
  try {
    return JSON.parse(result.value);
  } catch (error) {
    child.kill();
    throw new Error(`${operation} emitted invalid JSON: ${result.value}; ${String(error)}`);
  }
}

async function requireSuccessfulExit(
  child: SwiftProcess,
  stderr: () => string,
  operation: string,
): Promise<void> {
  const exitCode = await withTimeout(childExit(child), `${operation} exit`);
  if (exitCode !== 0) {
    throw new Error(`${operation} failed with status ${exitCode}: ${stderr().trim()}`);
  }
}

async function fetchText(url: string | undefined): Promise<string> {
  assert.ok(url, "Expected the linked App Builder file URL.");
  const response = await fetch(url);
  assert.equal(response.ok, true, `Could not fetch linked App Builder file: ${response.status}`);
  return response.text();
}

function unwrapSchema(module: unknown): any {
  let candidate = module;
  for (let depth = 0; depth < 4; depth += 1) {
    if (candidate && typeof candidate === "object" && "entities" in candidate) {
      return candidate;
    }
    if (!candidate || typeof candidate !== "object" || !("default" in candidate)) break;
    candidate = (candidate as { default: unknown }).default;
  }
  throw new Error("Generated App Builder schema did not load as an Instant schema.");
}

function childExit(child: SwiftProcess): Promise<number> {
  if (child.exitCode !== null) return Promise.resolve(child.exitCode);
  return new Promise((resolveCode, reject) => {
    child.once("error", reject);
    child.once("close", (code) => resolveCode(code ?? 1));
  });
}

async function withTimeout<T>(promise: Promise<T>, operation: string): Promise<T> {
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<never>((_, reject) => {
        timeout = setTimeout(
          () => reject(new Error(`${operation} timed out.`)),
          60_000,
        );
      }),
    ]);
  } finally {
    if (timeout) clearTimeout(timeout);
  }
}

function delay(): Promise<void> {
  return new Promise((resolveDelay) => setTimeout(resolveDelay, 100));
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}
