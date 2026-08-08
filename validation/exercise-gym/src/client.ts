/**
 * Instant core + admin client factory for the exercise gym.
 * Polyfills WebSocket for Node, installs message logging, resolves clientId.
 */
import { randomUUID } from "node:crypto";
import { init as initAdmin } from "@instantdb/admin";
import {
  init as initCore,
  StoreInterface,
  type StoreInterfaceStoreName,
  id as instantId,
} from "@instantdb/core";
import WebSocket from "ws";
import { exerciseGemSchema } from "../schema.ts";
import { MessageLog } from "./message-log.ts";

export { instantId };

export interface GemIdentity {
  runId: string;
  suite: string;
  side: "typescript" | "swift" | "electron" | "admin";
  descriptor: string;
  clientId: string;
}

export interface GemClients {
  admin: ReturnType<typeof initAdmin>;
  db: ReturnType<typeof initCore>;
  identity: GemIdentity;
  messageLog: MessageLog;
  refreshToken: string;
  userId: string;
  appId: string;
  shutdown: () => void;
}

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

export function installNodeGlobals(): void {
  const g = globalThis as any;
  g.window = g.window ?? g;
  g.BroadcastChannel = undefined;
  g.WebSocket = WebSocket;
}

export async function openGemClients(options: {
  appId: string;
  adminToken: string;
  apiURI?: string;
  websocketURI?: string;
  runId: string;
  suite: string;
  side?: GemIdentity["side"];
  descriptor?: string;
  email?: string;
}): Promise<GemClients> {
  installNodeGlobals();
  const apiURI = options.apiURI ?? process.env.INSTANT_API_URI ?? "https://api.instantdb.com";
  const websocketURI =
    options.websocketURI
    ?? process.env.INSTANT_WEBSOCKET_URI
    ?? "wss://api.instantdb.com/runtime/session";
  const side = options.side ?? "typescript";
  const descriptor =
    options.descriptor
    ?? `ts-${side}-${options.suite}-${process.pid}`;

  const messageLog = new MessageLog({
    clientId: "(pending)",
    descriptor,
    runId: options.runId,
    suite: options.suite,
    side,
  });
  messageLog.install();

  const admin = initAdmin({
    appId: options.appId,
    adminToken: options.adminToken,
    apiURI,
    schema: exerciseGemSchema,
    useDateObjects: true,
  });

  const email =
    options.email
    ?? `exercise-gym-${options.runId.slice(0, 8)}@knophy.test`;
  const refreshToken = await admin.auth.createToken({ email });
  const user = await admin.auth.verifyToken(refreshToken);
  if (!user?.id) throw new Error("Expected admin-created user id.");

  const db = initCore(
    {
      appId: options.appId,
      apiURI,
      websocketURI,
      schema: exerciseGemSchema,
      devtool: false,
      useDateObjects: true,
    },
    MemoryStore,
    AlwaysOnline,
  );
  await db.auth.signInWithToken(refreshToken);

  // Instant local client id (Reactor.getLocalId / InstantClientID.name = "instant.client")
  const clientId = await db.getLocalId("instant.client");
  messageLog.updateIdentity({ clientId });

  // Wait briefly for websocket auth so first writes are not offline-only.
  await waitForAuth(db, 5_000);

  const identity: GemIdentity = {
    runId: options.runId,
    suite: options.suite,
    side,
    descriptor,
    clientId,
  };

  return {
    admin,
    db,
    identity,
    messageLog,
    refreshToken,
    userId: user.id,
    appId: options.appId,
    shutdown: () => {
      try {
        db.shutdown();
      } catch {
        /* ignore */
      }
      messageLog.uninstall();
    },
  };
}

async function waitForAuth(db: any, timeoutMs: number): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const auth = db._reactor?.auth || db._reactor?._auth;
    // Best-effort: also just sleep a short settle if internals unavailable.
    if (auth || Date.now() - start > 400) return;
    await new Promise((r) => setTimeout(r, 50));
  }
}

export function newEntityId(): string {
  return instantId();
}

export function requiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable ${name}`);
  return value;
}

export function resolveAppCredentials(): { appId: string; adminToken: string } {
  const appId =
    process.env.INSTANT_APP_ID
    ?? process.env.INSTANT_SWIFT_DATA_APP_ID
    ?? process.env.SCRIBE_TEST_INSTANT_APP_ID;
  const adminToken =
    process.env.INSTANT_ADMIN_TOKEN
    ?? process.env.INSTANT_APP_ADMIN_TOKEN
    ?? process.env.INSTANT_SWIFT_DATA_ADMIN_TOKEN
    ?? process.env.SCRIBE_TEST_INSTANT_ADMIN_TOKEN;
  if (!appId || !adminToken) {
    throw new Error(
      "Set INSTANT_APP_ID and INSTANT_ADMIN_TOKEN (or SCRIBE_TEST_* equivalents).",
    );
  }
  return { appId, adminToken };
}

export function makeRunId(): string {
  return randomUUID();
}
