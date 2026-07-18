import * as serverSchemaModule from "../../fixtures/recording-action.server.schema.ts";
import type { AppSchema } from "../../fixtures/recording-action.server.schema.js";

export const recordingActionRuntimeSchema = unwrapSchema(serverSchemaModule);

function unwrapSchema(value: unknown): AppSchema {
  let candidate = value;
  for (let depth = 0; depth < 4; depth += 1) {
    if (isRuntimeSchema(candidate)) {
      return candidate as AppSchema;
    }
    if (!candidate || typeof candidate !== "object" || !("default" in candidate)) {
      break;
    }
    candidate = (candidate as { default: unknown }).default;
  }
  throw new Error("Pulled recording-action schema did not load as an Instant runtime schema.");
}

function isRuntimeSchema(value: unknown): boolean {
  if (!value || typeof value !== "object") {
    return false;
  }
  const entities = (value as { entities?: unknown }).entities;
  return Boolean(
    entities
      && typeof entities === "object"
      && "v3_capture_recordings" in entities,
  );
}
