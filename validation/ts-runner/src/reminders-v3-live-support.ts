import {
  remindersV3AppContract,
  type RemindersV3List,
  type RemindersV3Priority,
  type RemindersV3Reminder,
  type RemindersV3Role,
  type RemindersV3Share,
  type RemindersV3ShareMembership,
  type RemindersV3Tag,
  type RemindersV3User,
} from "./reminders-v3-app-contract.js";

export function projectCanonicalRemindersV3List(value: unknown): RemindersV3List {
  if (!isRecord(value) || !hasOnlyKeys(value, [
    "id", "title", "color", "coverFileID", "position", "createdAt", "owner", "readers",
    "writers", "reminders", "share",
  ])) throw listShapeError();
  if (
    typeof value.id !== "string"
    || typeof value.title !== "string"
    || typeof value.color !== "string"
    || !isOptionalString(value.coverFileID)
    || !isInteger(value.position)
    || !isDate(value.createdAt)
    || !Array.isArray(value.readers)
    || !Array.isArray(value.writers)
    || !Array.isArray(value.reminders)
  ) throw listShapeError();

  return {
    id: value.id,
    title: value.title,
    color: value.color,
    ...(typeof value.coverFileID === "string" ? { coverFileID: value.coverFileID } : {}),
    position: value.position,
    createdAt: value.createdAt,
    owner: projectUser(value.owner),
    readers: value.readers.map(projectUser),
    writers: value.writers.map(projectUser),
    reminders: value.reminders.map(projectCanonicalRemindersV3Reminder),
    ...(value.share === null || value.share === undefined
      ? {}
      : { share: projectShare(value.share) }),
  };
}

export function projectCanonicalRemindersV3Reminder(
  value: unknown,
): RemindersV3Reminder {
  if (!isRecord(value) || !hasOnlyKeys(value, [
    "id", "title", "notes", "isCompleted", "isFlagged", "dueDate", "priority",
    "position", "createdAt", "tags",
  ])) throw reminderShapeError();
  if (
    typeof value.id !== "string"
    || typeof value.title !== "string"
    || typeof value.notes !== "string"
    || typeof value.isCompleted !== "boolean"
    || typeof value.isFlagged !== "boolean"
    || !isOptionalDate(value.dueDate)
    || !isOptionalPriority(value.priority)
    || !isInteger(value.position)
    || !isDate(value.createdAt)
    || !Array.isArray(value.tags)
  ) throw reminderShapeError();

  return {
    id: value.id,
    title: value.title,
    notes: value.notes,
    isCompleted: value.isCompleted,
    isFlagged: value.isFlagged,
    ...(value.dueDate instanceof Date ? { dueDate: value.dueDate } : {}),
    ...(typeof value.priority === "number" ? { priority: value.priority } : {}),
    position: value.position,
    createdAt: value.createdAt,
    tags: value.tags.map(projectTag),
  };
}

function projectShare(value: unknown): RemindersV3Share {
  if (!isRecord(value) || !hasOnlyKeys(value, [
    "id", "token", "rootNamespace", "rootID", "createdAt", "updatedAt",
    "revokedAt", "owner", "memberships",
  ])) throw listShapeError();
  if (
    typeof value.id !== "string"
    || typeof value.token !== "string"
    || value.rootNamespace !== "remindersLists"
    || typeof value.rootID !== "string"
    || !isDate(value.createdAt)
    || !isDate(value.updatedAt)
    || !isOptionalDate(value.revokedAt)
    || !Array.isArray(value.memberships)
  ) throw listShapeError();
  return {
    id: value.id,
    token: value.token,
    rootNamespace: value.rootNamespace,
    rootID: value.rootID,
    createdAt: value.createdAt,
    updatedAt: value.updatedAt,
    ...(value.revokedAt instanceof Date ? { revokedAt: value.revokedAt } : {}),
    owner: projectUser(value.owner),
    memberships: value.memberships.map(projectMembership),
  };
}

function projectMembership(value: unknown): RemindersV3ShareMembership {
  if (!isRecord(value) || !hasOnlyKeys(value, [
    "id", "role", "acceptedAt", "revokedAt", "user",
  ])) throw listShapeError();
  if (
    typeof value.id !== "string"
    || !isRole(value.role)
    || !isDate(value.acceptedAt)
    || !isOptionalDate(value.revokedAt)
  ) throw listShapeError();
  return {
    id: value.id,
    role: value.role,
    acceptedAt: value.acceptedAt,
    ...(value.revokedAt instanceof Date ? { revokedAt: value.revokedAt } : {}),
    user: projectUser(value.user),
  };
}

function projectUser(value: unknown): RemindersV3User {
  if (!isRecord(value) || !hasOnlyKeys(value, ["id", "email"])) throw listShapeError();
  if (typeof value.id !== "string") throw listShapeError();
  return "email" in value ? { id: value.id, email: value.email } : { id: value.id };
}

function projectTag(value: unknown): RemindersV3Tag {
  if (
    !isRecord(value)
    || !hasExactKeys(value, ["id", "title"])
    || typeof value.id !== "string"
    || typeof value.title !== "string"
  ) throw reminderShapeError();
  return { id: value.id, title: value.title };
}

function isPriority(value: unknown): value is RemindersV3Priority {
  return isInteger(value) && Object.values(remindersV3AppContract.priority).includes(value as 1 | 2 | 3);
}

function isOptionalPriority(value: unknown): value is RemindersV3Priority | null | undefined {
  return value === null || value === undefined || isPriority(value);
}

function isRole(value: unknown): value is RemindersV3Role {
  return value === "owner" || value === "writer" || value === "reader";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: string[]): boolean {
  const actual = Object.keys(value).sort();
  return actual.length === keys.length
    && actual.every((key, index) => key === [...keys].sort()[index]);
}

function hasOnlyKeys(value: Record<string, unknown>, keys: string[]): boolean {
  return Object.keys(value).every((key) => keys.includes(key));
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function isDate(value: unknown): value is Date {
  return value instanceof Date && !Number.isNaN(value.getTime());
}

function isOptionalDate(value: unknown): value is Date | null | undefined {
  return value === null || value === undefined || isDate(value);
}

function isOptionalString(value: unknown): value is string | null | undefined {
  return value === null || value === undefined || typeof value === "string";
}

function isInteger(value: unknown): value is number {
  return isFiniteNumber(value) && Number.isInteger(value);
}

function listShapeError(): TypeError {
  return new TypeError("Expected canonical Reminders V3 list sharing shape.");
}

function reminderShapeError(): TypeError {
  return new TypeError("Expected canonical Reminders V3 reminder shape.");
}
