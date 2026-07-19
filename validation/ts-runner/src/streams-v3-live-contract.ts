import assert from "node:assert/strict";
import { spawn, type ChildProcessByStdio } from "node:child_process";
import { randomUUID } from "node:crypto";
import { dirname, resolve } from "node:path";
import { createInterface } from "node:readline";
import type { Readable } from "node:stream";
import { fileURLToPath } from "node:url";
import { init as initAdmin } from "@instantdb/admin";

type SwiftProcess = ChildProcessByStdio<null, Readable, Readable>;

const appId = requiredEnvironment("INSTANT_APP_ID");
const adminToken = requiredEnvironment("INSTANT_ADMIN_TOKEN");
const apiURI = process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
const websocketURI = process.env.INSTANT_WEBSOCKET_URI
  ?? "wss://api.instantdb.com/runtime/session";
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const suffix = randomUUID();
const typeScriptClientID = `typescript-stream-${suffix}`;
const swiftClientID = `swift-stream-${suffix}`;
const typeScriptContent = "typescript to swift 🚀";
const swiftContent = "swift to typescript 🚀";
const warnings: string[] = [];
const originalWarn = console.warn;
console.warn = (...values) => warnings.push(values.map(String).join(" "));

try {
  const admin = initAdmin({ appId, adminToken, apiURI });
  process.stderr.write("streams-v3: creating Swift auth token\n");
  const swiftToken = await withTimeout(
    admin.auth.createToken({ email: `streams-swift-${suffix}@example.com` }),
    "create Swift streams token",
  );
  const swiftUser = await withTimeout(
    admin.auth.verifyToken(swiftToken),
    "verify Swift streams token",
  );
  assert.ok(swiftUser?.id, "Expected a canonical Swift streams user.");

  process.stderr.write("streams-v3: starting Swift reader\n");
  const swift = spawnSwift({
    appId,
    apiURI,
    websocketURI,
    refreshToken: swiftToken,
    swiftUserID: swiftUser.id,
    typeScriptClientID,
    swiftClientID,
  });
  const lines = createInterface({ input: swift.stdout, crlfDelay: Infinity })
    [Symbol.asyncIterator]();

  const ready = await nextJSONLine(lines, swift, "Swift stream reader readiness");
  assert.equal(ready.event, "typescript-writer-ready");
  assert.equal(ready.details.clientID, typeScriptClientID);

  process.stderr.write("streams-v3: writing TypeScript stream\n");
  const typeScriptWriter = admin.streams.createWriteStream({ clientId: typeScriptClientID });
  const typeScriptStreamID = typeScriptWriter.streamId();
  const writer = typeScriptWriter.getWriter();
  await withTimeout(writer.write("typescript "), "write TypeScript stream prefix");
  await withTimeout(writer.write("to swift 🚀"), "write TypeScript stream suffix");
  await withTimeout(writer.close(), "close TypeScript stream");

  const created = await nextJSONLine(lines, swift, "Swift writer creation");
  assert.equal(created.event, "swift-writer-created");
  assert.equal(created.details.clientID, swiftClientID);
  assert.ok(created.details.streamID);

  process.stderr.write("streams-v3: reading Swift stream\n");
  const observedSwiftContent = await withTimeout((async () => {
    let content = "";
    const swiftReader = admin.streams.createReadStream({ streamId: created.details.streamID });
    for await (const chunk of swiftReader) content += chunk;
    return content;
  })(), "read Swift stream in TypeScript");

  const swiftEvidence = await nextJSONLine(lines, swift, "Swift stream evidence");
  await requireSuccessfulExit(swift, "Swift streams runner");
  assert.equal(swiftEvidence.ok, true);
  assert.equal(swiftEvidence.details.swiftUserID, swiftUser.id);
  assert.equal(swiftEvidence.details.typeScriptClientID, typeScriptClientID);
  assert.equal(swiftEvidence.details.typeScriptStreamID, await typeScriptStreamID);
  assert.equal(swiftEvidence.details.typeScriptContent, typeScriptContent);
  assert.equal(swiftEvidence.details.typeScriptByteCount, Buffer.byteLength(typeScriptContent));
  assert.equal(swiftEvidence.details.swiftClientID, swiftClientID);
  assert.equal(swiftEvidence.details.swiftStreamID, created.details.streamID);
  assert.equal(swiftEvidence.details.swiftContent, swiftContent);
  assert.equal(swiftEvidence.details.swiftByteCount, Buffer.byteLength(swiftContent));
  assert.equal(swiftEvidence.details.connectionState, "authenticated");
  assert.equal(observedSwiftContent, swiftContent);
  assert.deepEqual(warnings, []);

  process.stdout.write(`${JSON.stringify({
    case: "validation.typescript.streams-v3-live-contract",
    event: "bidirectional-streams-observed",
    side: "typescript",
    appID: appId,
    ok: true,
    details: {
      upstream: {
        app: "upstream/instant/examples/ai-chat",
        resumable: "upstream/instant/client/packages/resumable-stream/src/index.ts",
      },
      swiftUser: { id: swiftUser.id, email: swiftUser.email },
      typeScriptWriter: {
        clientID: typeScriptClientID,
        streamID: await typeScriptStreamID,
        content: typeScriptContent,
        byteCount: Buffer.byteLength(typeScriptContent),
      },
      swiftWriter: {
        clientID: swiftClientID,
        streamID: created.details.streamID,
        content: observedSwiftContent,
        byteCount: Buffer.byteLength(observedSwiftContent),
      },
      swift: swiftEvidence.details,
      compilerWarningCount: warnings.length,
      warnings,
    },
  }, null, 2)}\n`);
} finally {
  console.warn = originalWarn;
}

function spawnSwift(input: {
  appId: string;
  apiURI: string;
  websocketURI: string;
  refreshToken: string;
  swiftUserID: string;
  typeScriptClientID: string;
  swiftClientID: string;
}): SwiftProcess {
  return spawn(
    "swift",
    [
      "run",
      "--package-path",
      repositoryRoot,
      "instant-swift-data-validation-runner",
      "--live-streams-v3",
    ],
    {
      cwd: repositoryRoot,
      env: {
        ...process.env,
        INSTANT_APP_ID: input.appId,
        INSTANT_API_URI: input.apiURI,
        INSTANT_WEBSOCKET_URI: input.websocketURI,
        INSTANT_SWIFT_DATA_STREAMS_REFRESH_TOKEN: input.refreshToken,
        INSTANT_SWIFT_DATA_STREAMS_SWIFT_USER_ID: input.swiftUserID,
        INSTANT_SWIFT_DATA_STREAMS_TYPESCRIPT_CLIENT_ID: input.typeScriptClientID,
        INSTANT_SWIFT_DATA_STREAMS_SWIFT_CLIENT_ID: input.swiftClientID,
      },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
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

async function requireSuccessfulExit(child: SwiftProcess, operation: string): Promise<void> {
  let stderr = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const exitCode = await withTimeout(childExit(child), `${operation} exit`);
  if (exitCode !== 0) {
    throw new Error(`${operation} failed with status ${exitCode}: ${stderr.trim()}`);
  }
}

function childExit(child: SwiftProcess): Promise<number> {
  return new Promise((resolveExit) => child.once("exit", (code) => resolveExit(code ?? -1)));
}

async function withTimeout<T>(promise: Promise<T>, operation: string): Promise<T> {
  let timeout: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<never>((_, reject) => {
        timeout = setTimeout(() => reject(new Error(`${operation} timed out.`)), 30_000);
      }),
    ]);
  } finally {
    if (timeout) clearTimeout(timeout);
  }
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}.`);
  return value;
}
