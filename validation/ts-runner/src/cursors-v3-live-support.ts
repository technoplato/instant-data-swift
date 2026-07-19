import {
  cursorsV3AppContract,
  type CursorsV3Cursor,
} from "./cursors-v3-app-contract.js";

export interface CanonicalCursorPeer {
  peerId: string;
  cursor: CursorsV3Cursor | null;
}

export interface PublicCursorsUserEvidence {
  appID: string;
  id: string;
  email: string | null;
  createdAt: string;
  isGuest: boolean;
}

export function projectCanonicalCursorPeer(value: unknown): CanonicalCursorPeer {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw peerShapeError();
  }
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  const spaceID = cursorsV3AppContract.room.spaceID;
  const expectedKeys = record[spaceID] === undefined
    ? ["peerId"]
    : [spaceID, "peerId"].sort();
  if (
    keys.length !== expectedKeys.length
    || keys.some((key, index) => key !== expectedKeys[index])
    || typeof record.peerId !== "string"
  ) {
    throw peerShapeError();
  }
  return {
    peerId: record.peerId,
    cursor: record[spaceID] === undefined ? null : exactCursorPayload(record[spaceID]),
  };
}

export function exactCursorPayload(value: unknown): CursorsV3Cursor {
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

export function visibleCursorPeers(values: ReadonlyArray<unknown>): CanonicalCursorPeer[] {
  return values
    .map(projectCanonicalCursorPeer)
    .filter((peer): peer is CanonicalCursorPeer & { cursor: CursorsV3Cursor } => (
      peer.cursor !== null
    ));
}

export function publicCursorsUserEvidence(value: unknown): PublicCursorsUserEvidence {
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
    "Expected the exact cursors peer shape: peerId metadata plus optional dynamic cursor presence.",
  );
}

function cursorShapeError(): TypeError {
  return new TypeError(
    "Expected the exact cursors payload shape: finite x, y, xPercent, yPercent numbers plus color.",
  );
}

function userShapeError(): TypeError {
  return new TypeError("Expected an Instant Admin SDK user for public cursors evidence.");
}
