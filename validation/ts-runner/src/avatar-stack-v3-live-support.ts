import type { AvatarStackV3Presence } from "./avatar-stack-v3-app-contract.js";

export interface AvatarStackV3PeerWireValue extends AvatarStackV3Presence {
  peerId: string;
}

export interface CanonicalAvatarStackPeer {
  peerId: string;
  presence: AvatarStackV3Presence;
}

export interface PublicAvatarStackUserEvidence {
  appID: string;
  id: string;
  email: string | null;
  createdAt: string;
  isGuest: boolean;
}

export function projectCanonicalAvatarPeer(value: unknown): CanonicalAvatarStackPeer {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw exactShapeError();
  }
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  if (
    keys.length !== 2
    || keys[0] !== "name"
    || keys[1] !== "peerId"
    || typeof record.peerId !== "string"
    || typeof record.name !== "string"
  ) {
    throw exactShapeError();
  }
  return {
    peerId: record.peerId,
    presence: { name: record.name },
  };
}

export function avatarStackOnlineCount(
  peers: ReadonlyArray<AvatarStackV3PeerWireValue>,
): number {
  return peers.length + 1;
}

export function publicAvatarStackUserEvidence(
  value: unknown,
): PublicAvatarStackUserEvidence {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError("Expected an Instant Admin SDK user for public avatar evidence.");
  }
  const record = value as Record<string, unknown>;
  const appID = record.app_id;
  const id = record.id;
  const email = record.email;
  const createdAt = record.created_at;
  const isGuest = record.isGuest;
  if (typeof email !== "string" && email !== null) {
    throw new TypeError("Expected an Instant Admin SDK user for public avatar evidence.");
  }
  if (
    typeof appID !== "string"
    || typeof id !== "string"
    || typeof createdAt !== "string"
    || typeof isGuest !== "boolean"
  ) {
    throw new TypeError("Expected an Instant Admin SDK user for public avatar evidence.");
  }
  return {
    appID,
    id,
    email: email as string | null,
    createdAt,
    isGuest,
  };
}

function exactShapeError(): TypeError {
  return new TypeError(
    "Expected the exact avatar-stack peer shape: peerId metadata plus name-only app presence.",
  );
}
