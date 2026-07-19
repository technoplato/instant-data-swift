import {
  syncUpsV3Themes,
  type SyncUpsV3Attendee,
  type SyncUpsV3Meeting,
  type SyncUpsV3SyncUp,
  type SyncUpsV3Theme,
} from "./syncups-v3-app-contract.js";

export function projectCanonicalSyncUpsV3SyncUp(value: unknown): SyncUpsV3SyncUp {
  if (!isRecord(value) || !hasExactKeys(value, [
    "id", "seconds", "theme", "title", "attendees", "meetings",
  ])) throw syncUpShapeError();
  if (
    typeof value.id !== "string"
    || !isInteger(value.seconds)
    || !isTheme(value.theme)
    || typeof value.title !== "string"
    || !Array.isArray(value.attendees)
    || !Array.isArray(value.meetings)
  ) throw syncUpShapeError();

  return {
    id: value.id,
    seconds: value.seconds,
    theme: value.theme,
    title: value.title,
    attendees: value.attendees.map(projectAttendee),
    meetings: value.meetings.map(projectMeeting),
  };
}

function projectAttendee(value: unknown): SyncUpsV3Attendee {
  if (
    !isRecord(value)
    || !hasExactKeys(value, ["id", "name"])
    || typeof value.id !== "string"
    || typeof value.name !== "string"
  ) throw syncUpShapeError();
  return { id: value.id, name: value.name };
}

function projectMeeting(value: unknown): SyncUpsV3Meeting {
  if (
    !isRecord(value)
    || !hasExactKeys(value, ["id", "date", "transcript"])
    || typeof value.id !== "string"
    || !isDate(value.date)
    || typeof value.transcript !== "string"
  ) throw syncUpShapeError();
  return { id: value.id, date: value.date, transcript: value.transcript };
}

function isTheme(value: unknown): value is SyncUpsV3Theme {
  return typeof value === "string"
    && syncUpsV3Themes.includes(value as SyncUpsV3Theme);
}

function isDate(value: unknown): value is Date {
  return value instanceof Date && !Number.isNaN(value.getTime());
}

function isInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && Number.isInteger(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: string[]): boolean {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length
    && actual.every((key, index) => key === expected[index]);
}

function syncUpShapeError(): TypeError {
  return new TypeError("Expected canonical SyncUps V3 nested graph shape.");
}
