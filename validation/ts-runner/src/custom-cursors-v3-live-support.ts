import type { CursorsV3Cursor } from "./cursors-v3-app-contract.js";
import { customCursorsV3AppContract } from "./custom-cursors-v3-app-contract.js";

export interface CanonicalCustomCursorPeer {
  peerId: string;
  name: string;
  cursor: CursorsV3Cursor | null;
}

export interface PublicCustomCursorsUserEvidence {
  appID: string;
  id: string;
  email: string | null;
  createdAt: string;
  isGuest: boolean;
}

export function projectCanonicalCustomCursorPeer(
  value: unknown,
): CanonicalCustomCursorPeer {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw peerShapeError();
  }
  const record = value as Record<string, unknown>;
  const spaceID = customCursorsV3AppContract.room.spaceID;
  const keys = Object.keys(record).sort();
  const expectedKeys = record[spaceID] === undefined
    ? ["name", "peerId"]
    : [spaceID, "name", "peerId"].sort();
  if (
    keys.length !== expectedKeys.length
    || keys.some((key, index) => key !== expectedKeys[index])
    || typeof record.peerId !== "string"
    || typeof record.name !== "string"
  ) {
    throw peerShapeError();
  }
  return {
    peerId: record.peerId,
    name: record.name,
    cursor: record[spaceID] === undefined
      ? null
      : exactCustomCursorPayload(record[spaceID]),
  };
}

export function exactCustomCursorPayload(value: unknown): CursorsV3Cursor {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw cursorShapeError();
  }
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  const expectedKeys = ["color", "x", "xPercent", "y", "yPercent"];
  if (
    keys.length !== expectedKeys.length
    || keys.some((key, index) => key !== expectedKeys[index])
    || !finiteNumber(record.x)
    || !finiteNumber(record.y)
    || !finiteNumber(record.xPercent)
    || !finiteNumber(record.yPercent)
    || typeof record.color !== "string"
  ) {
    throw cursorShapeError();
  }
  return {
    x: record.x,
    y: record.y,
    xPercent: record.xPercent,
    yPercent: record.yPercent,
    color: record.color,
  };
}

export function visibleCustomCursorPeers(
  values: ReadonlyArray<unknown>,
): CanonicalCustomCursorPeer[] {
  return values
    .map(projectCanonicalCustomCursorPeer)
    .filter((peer): peer is CanonicalCustomCursorPeer & { cursor: CursorsV3Cursor } => (
      peer.cursor !== null
    ));
}

export function publicCustomCursorsUserEvidence(
  value: unknown,
): PublicCustomCursorsUserEvidence {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw userShapeError();
  }
  const record = value as Record<string, unknown>;
  const appID = record.app_id;
  const id = record.id;
  const email = record.email;
  const createdAt = record.created_at;
  const isGuest = record.isGuest;
  if (typeof email !== "string" && email !== null) throw userShapeError();
  if (
    typeof appID !== "string"
    || typeof id !== "string"
    || typeof createdAt !== "string"
    || typeof isGuest !== "boolean"
  ) {
    throw userShapeError();
  }
  return {
    appID,
    id,
    email: email as string | null,
    createdAt,
    isGuest,
  };
}

function finiteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function peerShapeError(): TypeError {
  return new TypeError(
    "Expected the exact custom cursors peer shape: peerId metadata, required name, and optional dynamic cursor presence.",
  );
}

function cursorShapeError(): TypeError {
  return new TypeError(
    "Expected the exact custom cursors payload shape: finite x, y, xPercent, yPercent numbers plus color.",
  );
}

function userShapeError(): TypeError {
  return new TypeError(
    "Expected an Instant Admin SDK user for public custom cursors evidence.",
  );
}
