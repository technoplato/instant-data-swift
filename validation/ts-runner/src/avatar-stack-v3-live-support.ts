import type { AvatarStackV3Presence } from "./avatar-stack-v3-app-contract.js";

export interface AvatarStackV3PeerWireValue extends AvatarStackV3Presence {
  peerId: string;
}

export interface CanonicalAvatarStackPeer {
  peerId: string;
  presence: AvatarStackV3Presence;
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

function exactShapeError(): TypeError {
  return new TypeError(
    "Expected the exact avatar-stack peer shape: peerId metadata plus name-only app presence.",
  );
}
