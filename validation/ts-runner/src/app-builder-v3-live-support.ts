import type {
  AppBuilderV3Build,
  AppBuilderV3BuildError,
  AppBuilderV3File,
  AppBuilderV3User,
} from "./app-builder-v3-app-contract.js";

export function projectCanonicalAppBuilderV3Build(value: unknown): AppBuilderV3Build {
  if (!isRecord(value) || !hasOnlyKeys(value, [
    "id", "instantAppId", "code", "reasoning", "slug", "error",
    "isPreviewable", "title", "owner", "file",
  ])) throw shapeError();
  if (
    typeof value.id !== "string"
    || typeof value.instantAppId !== "string"
    || typeof value.code !== "string"
    || !isOptionalString(value.reasoning)
    || !isOptionalString(value.slug)
    || !isOptionalBoolean(value.isPreviewable)
    || !isOptionalString(value.title)
    || !isRecord(value.owner)
  ) throw shapeError();

  const result: AppBuilderV3Build = {
    id: value.id,
    instantAppId: value.instantAppId,
    code: value.code,
    owner: projectUser(value.owner),
  };
  if (typeof value.reasoning === "string") result.reasoning = value.reasoning;
  if (typeof value.slug === "string") result.slug = value.slug;
  if (typeof value.isPreviewable === "boolean") result.isPreviewable = value.isPreviewable;
  if (typeof value.title === "string") result.title = value.title;
  if (value.error !== undefined && value.error !== null) result.error = projectError(value.error);
  if (value.file !== undefined && value.file !== null) result.file = projectFile(value.file);
  return result;
}

function projectUser(value: Record<string, unknown>): AppBuilderV3User {
  if (!hasOnlyKeys(value, ["id", "email"]) || typeof value.id !== "string") {
    throw shapeError();
  }
  if (!isOptionalString(value.email)) throw shapeError();
  return {
    id: value.id,
    ...(typeof value.email === "string" ? { email: value.email } : {}),
  };
}

function projectFile(value: unknown): AppBuilderV3File {
  if (
    !isRecord(value)
    || !hasExactKeys(value, ["id", "path", "url"])
    || typeof value.id !== "string"
    || typeof value.path !== "string"
    || typeof value.url !== "string"
  ) throw shapeError();
  return { id: value.id, path: value.path, url: value.url };
}

function projectError(value: unknown): AppBuilderV3BuildError {
  if (
    !isRecord(value)
    || !hasExactKeys(value, ["from", "status", "message"])
    || typeof value.from !== "string"
    || typeof value.status !== "number"
    || !Number.isInteger(value.status)
    || typeof value.message !== "string"
  ) throw shapeError();
  return { from: value.from, status: value.status, message: value.message };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isOptionalString(value: unknown): value is string | null | undefined {
  return value === undefined || value === null || typeof value === "string";
}

function isOptionalBoolean(value: unknown): value is boolean | null | undefined {
  return value === undefined || value === null || typeof value === "boolean";
}

function hasOnlyKeys(value: Record<string, unknown>, allowed: ReadonlyArray<string>): boolean {
  const keys = new Set(allowed);
  return Object.keys(value).every((key) => keys.has(key));
}

function hasExactKeys(value: Record<string, unknown>, expected: ReadonlyArray<string>): boolean {
  return hasOnlyKeys(value, expected) && Object.keys(value).length === expected.length;
}

function shapeError(): TypeError {
  return new TypeError("Expected canonical App Builder V3 build, owner, file, and error shapes.");
}
