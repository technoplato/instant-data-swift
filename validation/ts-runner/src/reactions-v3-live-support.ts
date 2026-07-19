import {
  reactionsV3AppContract,
  type ReactionsV3Name,
  type ReactionsV3Payload,
} from "./reactions-v3-app-contract.js";

export interface AcceptedReaction extends ReactionsV3Payload {
  name: ReactionsV3Name;
  symbol: string;
}

export function exactReactionPayload(value: unknown): ReactionsV3Payload {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw exactShapeError();
  }
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  if (
    keys.length !== 3
    || keys[0] !== "directionAngle"
    || keys[1] !== "name"
    || keys[2] !== "rotationAngle"
    || typeof record.name !== "string"
    || typeof record.directionAngle !== "number"
    || !Number.isFinite(record.directionAngle)
    || typeof record.rotationAngle !== "number"
    || !Number.isFinite(record.rotationAngle)
  ) {
    throw exactShapeError();
  }
  return {
    name: record.name,
    directionAngle: record.directionAngle,
    rotationAngle: record.rotationAngle,
  };
}

export function acceptedReactions(values: ReadonlyArray<unknown>): AcceptedReaction[] {
  return values.flatMap((value) => {
    const payload = exactReactionPayload(value);
    if (!isReactionName(payload.name)) return [];
    return [{
      ...payload,
      name: payload.name,
      symbol: reactionsV3AppContract.reactions[payload.name],
    }];
  });
}

export function isReactionName(value: string): value is ReactionsV3Name {
  return Object.prototype.hasOwnProperty.call(reactionsV3AppContract.reactions, value);
}

function exactShapeError(): TypeError {
  return new TypeError(
    "Expected the exact reactions payload shape: name string plus finite directionAngle and rotationAngle numbers.",
  );
}
