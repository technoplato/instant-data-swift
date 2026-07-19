import {
  type MergeTileGameV3Board,
  type MergeTileGameV3BoardState,
  mergeTileGameV3AppContract,
} from "./merge-tile-game-v3-app-contract.js";

export interface CanonicalMergeTileGamePeer {
  peerId: string;
  color: string;
}

export interface PublicMergeTileGameUserEvidence {
  appID: string;
  id: string;
  email: string | null;
  createdAt: string;
  isGuest: boolean;
}

export function projectCanonicalMergeTileBoard(value: unknown): MergeTileGameV3Board {
  if (!isRecord(value) || !hasExactKeys(value, ["id", "state"])) {
    throw boardShapeError();
  }
  if (value.id !== mergeTileGameV3AppContract.board.id) {
    throw boardShapeError();
  }
  return {
    id: value.id,
    state: exactMergeTileBoardState(value.state),
  };
}

export function exactMergeTileBoardState(value: unknown): MergeTileGameV3BoardState {
  if (!isRecord(value)) throw boardStateShapeError();
  const expectedCells = canonicalMergeTileCells();
  if (!hasExactKeys(value, expectedCells)) throw boardStateShapeError();

  const allowedColors = new Set<string>([
    mergeTileGameV3AppContract.board.emptyColor,
    ...mergeTileGameV3AppContract.colors,
  ]);
  const state: Record<string, string> = {};
  for (const cell of expectedCells) {
    const color = value[cell];
    if (typeof color !== "string" || !allowedColors.has(color)) {
      throw boardStateShapeError();
    }
    state[cell] = color;
  }
  return state as MergeTileGameV3BoardState;
}

export function projectCanonicalMergeTilePeer(value: unknown): CanonicalMergeTileGamePeer {
  if (
    !isRecord(value)
    || !hasExactKeys(value, ["color", "peerId"])
    || typeof value.peerId !== "string"
    || typeof value.color !== "string"
    || !mergeTileGameV3AppContract.colors.includes(
      value.color as (typeof mergeTileGameV3AppContract.colors)[number],
    )
  ) {
    throw peerShapeError();
  }
  return { peerId: value.peerId, color: value.color };
}

export function publicMergeTileGameUserEvidence(
  value: unknown,
): PublicMergeTileGameUserEvidence {
  if (!isRecord(value)) throw userShapeError();
  const appID = value.app_id;
  const id = value.id;
  const email = value.email;
  const createdAt = value.created_at;
  const isGuest = value.isGuest;
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

export function canonicalMergeTileCells(): string[] {
  const cells: string[] = [];
  for (let row = 0; row < mergeTileGameV3AppContract.board.size; row += 1) {
    for (let column = 0; column < mergeTileGameV3AppContract.board.size; column += 1) {
      cells.push(`${row}-${column}`);
    }
  }
  return cells;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, expected: ReadonlyArray<string>): boolean {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  return actual.length === sortedExpected.length
    && actual.every((key, index) => key === sortedExpected[index]);
}

function boardShapeError(): TypeError {
  return new TypeError(
    "Expected the exact Merge Tile Game board shape: fixed id plus canonical state.",
  );
}

function boardStateShapeError(): TypeError {
  return new TypeError(
    "Expected the exact Merge Tile Game state: all 16 canonical cells with allowed string colors.",
  );
}

function peerShapeError(): TypeError {
  return new TypeError(
    "Expected the exact Merge Tile Game peer shape: peerId metadata plus one canonical color.",
  );
}

function userShapeError(): TypeError {
  return new TypeError(
    "Expected an Instant Admin SDK user for public Merge Tile Game evidence.",
  );
}
