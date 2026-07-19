import {
  stroopwafelV3AppContract,
  type StroopwafelV3Color,
  type StroopwafelV3ColorPrompt,
  type StroopwafelV3Game,
  type StroopwafelV3GameStatus,
  type StroopwafelV3Point,
  type StroopwafelV3Room,
  type StroopwafelV3User,
} from "./stroopwafel-v3-app-contract.js";

export interface PublicStroopwafelV3UserEvidence {
  appID: string;
  id: string;
  email: string | null;
  createdAt: string;
  isGuest: boolean;
}

export function projectCanonicalStroopwafelUser(value: unknown): StroopwafelV3User {
  if (!isRecord(value) || !hasOnlyKeys(value, [
    "id", "email", "handle", "highScore", "created_at",
  ])) throw userShapeError();
  if (typeof value.id !== "string") throw userShapeError();
  if ("handle" in value && typeof value.handle !== "string") throw userShapeError();
  if ("highScore" in value && !isInteger(value.highScore)) throw userShapeError();
  if ("created_at" in value && typeof value.created_at !== "string") throw userShapeError();
  return value as unknown as StroopwafelV3User;
}

export function projectCanonicalStroopwafelRoom(value: unknown): StroopwafelV3Room {
  if (!isRecord(value) || !hasOnlyKeys(value, [
    "id", "code", "hostId", "readyIds", "kickedIds", "currentGameId",
    "created_at", "deleted_at", "users",
  ])) throw roomShapeError();
  if (
    typeof value.id !== "string"
    || !isOptionalString(value.code)
    || typeof value.hostId !== "string"
    || !isStringArray(value.readyIds)
    || !isStringArray(value.kickedIds)
    || !isOptionalString(value.currentGameId)
    || typeof value.created_at !== "string"
    || !isOptionalString(value.deleted_at)
    || !Array.isArray(value.users)
  ) throw roomShapeError();
  return {
    id: value.id,
    ...(typeof value.code === "string" ? { code: value.code } : {}),
    hostId: value.hostId,
    readyIds: [...value.readyIds],
    kickedIds: [...value.kickedIds],
    ...(typeof value.currentGameId === "string" ? { currentGameId: value.currentGameId } : {}),
    created_at: value.created_at,
    ...(typeof value.deleted_at === "string" ? { deleted_at: value.deleted_at } : {}),
    users: value.users.map(projectCanonicalStroopwafelUser),
  };
}

export function projectCanonicalStroopwafelPoint(value: unknown): StroopwafelV3Point {
  if (
    !isRecord(value)
    || !hasExactKeys(value, ["id", "userId", "val"])
    || typeof value.id !== "string"
    || !isInteger(value.val)
    || typeof value.userId !== "string"
  ) throw pointShapeError();
  return { id: value.id, val: value.val, userId: value.userId };
}

export function projectCanonicalStroopwafelGame(value: unknown): StroopwafelV3Game {
  if (!isRecord(value) || !hasExactKeys(value, [
    "id", "status", "playerIds", "colors", "created_at", "users", "rooms", "points",
  ])) throw gameShapeError();
  if (
    typeof value.id !== "string"
    || !isStatus(value.status)
    || !isStringArray(value.playerIds)
    || !Array.isArray(value.colors)
    || value.colors.length !== stroopwafelV3AppContract.game.promptCount
    || typeof value.created_at !== "string"
    || !Array.isArray(value.users)
    || !Array.isArray(value.rooms)
    || !Array.isArray(value.points)
  ) throw gameShapeError();
  return {
    id: value.id,
    status: value.status,
    playerIds: [...value.playerIds],
    colors: value.colors.map(projectColorPrompt),
    created_at: value.created_at,
    users: value.users.map(projectCanonicalStroopwafelUser),
    rooms: value.rooms.map(projectCanonicalStroopwafelRoom),
    points: value.points.map(projectCanonicalStroopwafelPoint),
  };
}

export function publicStroopwafelV3UserEvidence(
  value: unknown,
): PublicStroopwafelV3UserEvidence {
  if (!isRecord(value)) throw adminUserShapeError();
  const appID = value.app_id;
  const id = value.id;
  const email = value.email;
  const createdAt = value.created_at;
  const isGuest = value.isGuest;
  if (
    typeof appID !== "string"
    || typeof id !== "string"
    || (typeof email !== "string" && email !== null)
    || typeof createdAt !== "string"
    || typeof isGuest !== "boolean"
  ) throw adminUserShapeError();
  return { appID, id, email, createdAt, isGuest };
}

function projectColorPrompt(value: unknown): StroopwafelV3ColorPrompt {
  if (
    !isRecord(value)
    || !hasExactKeys(value, ["color", "label"])
    || !isColor(value.color)
    || !isColor(value.label)
  ) throw gameShapeError();
  return { color: value.color, label: value.label };
}

function isColor(value: unknown): value is StroopwafelV3Color {
  return typeof value === "string"
    && stroopwafelV3AppContract.game.colors.includes(value as StroopwafelV3Color);
}

function isStatus(value: unknown): value is StroopwafelV3GameStatus {
  return value === stroopwafelV3AppContract.game.inProgress
    || value === stroopwafelV3AppContract.game.completed;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((element) => typeof element === "string");
}

function isInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value);
}

function isOptionalString(value: unknown): value is string | null | undefined {
  return value === undefined || value === null || typeof value === "string";
}

function hasOnlyKeys(value: Record<string, unknown>, allowed: ReadonlyArray<string>): boolean {
  const keys = new Set(allowed);
  return Object.keys(value).every((key) => keys.has(key));
}

function hasExactKeys(value: Record<string, unknown>, expected: ReadonlyArray<string>): boolean {
  return hasOnlyKeys(value, expected) && Object.keys(value).length === expected.length;
}

function userShapeError(): TypeError {
  return new TypeError("Expected the exact canonical Stroopwafel $users projection.");
}

function roomShapeError(): TypeError {
  return new TypeError("Expected the exact canonical Stroopwafel room and users projection.");
}

function pointShapeError(): TypeError {
  return new TypeError("Expected the exact canonical Stroopwafel point projection.");
}

function gameShapeError(): TypeError {
  return new TypeError("Expected the exact canonical Stroopwafel game graph and 14 color prompts.");
}

function adminUserShapeError(): TypeError {
  return new TypeError("Expected an Instant Admin SDK user for public Stroopwafel evidence.");
}
