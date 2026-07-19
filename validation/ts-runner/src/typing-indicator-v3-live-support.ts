export type TypingIndicatorPhase = "initial" | "active" | "inactive" | "cleared";

export interface TypingIndicatorPresence {
  id: string;
  "chat-input"?: boolean | null;
}

export interface TypingIndicatorPresenceFrame {
  phase: TypingIndicatorPhase;
  presence: TypingIndicatorPresence;
}

export interface CanonicalTypingIndicatorPeer {
  peerId: string;
  presence: TypingIndicatorPresence;
}

export function exactTypingIndicatorFrames(peerID: string): TypingIndicatorPresenceFrame[] {
  return [
    { phase: "initial", presence: { id: peerID } },
    { phase: "active", presence: { id: peerID, "chat-input": true } },
    { phase: "inactive", presence: { id: peerID, "chat-input": false } },
    { phase: "cleared", presence: { id: peerID, "chat-input": null } },
  ];
}

export function typeScriptPatchObservedTypingIndicatorFrames(
  peerID: string,
): TypingIndicatorPresenceFrame[] {
  return exactTypingIndicatorFrames(peerID);
}

export function phaseForTypingIndicatorPresence(
  value: Record<string, unknown>,
): TypingIndicatorPhase {
  if (typeof value.id !== "string") throw exactShapeError();

  const keys = Object.keys(value).sort();
  if (keys.length === 1 && keys[0] === "id") {
    return "initial";
  }
  if (keys.length !== 2 || keys[0] !== "chat-input" || keys[1] !== "id") {
    throw exactShapeError();
  }

  switch (value["chat-input"]) {
    case true:
      return "active";
    case false:
      return "inactive";
    case null:
      return "cleared";
    default:
      throw exactShapeError();
  }
}

export function activeTypingPeerIDs(
  peers: ReadonlyArray<Record<string, unknown>>,
  selfID: string,
): string[] {
  return peers.flatMap((peer) => {
    const phase = phaseForTypingIndicatorPresence(peer);
    return phase === "active" && peer.id !== selfID ? [peer.id as string] : [];
  });
}

export function projectCanonicalTypingPeer(
  peer: Record<string, unknown>,
): CanonicalTypingIndicatorPeer {
  const unexpectedKeys = Object.keys(peer).filter(
    (key) => key !== "id" && key !== "chat-input" && key !== "peerId",
  );
  if (
    unexpectedKeys.length > 0
    || typeof peer.peerId !== "string"
  ) {
    throw exactShapeError();
  }

  const presence: Record<string, unknown> = { id: peer.id };
  if (Object.prototype.hasOwnProperty.call(peer, "chat-input")) {
    presence["chat-input"] = peer["chat-input"];
  }
  phaseForTypingIndicatorPresence(presence);
  return {
    peerId: peer.peerId,
    presence: presence as unknown as TypingIndicatorPresence,
  };
}

function exactShapeError(): TypeError {
  return new TypeError(
    "Expected the exact typing-indicator presence shape: id plus optional chat-input boolean or null.",
  );
}
