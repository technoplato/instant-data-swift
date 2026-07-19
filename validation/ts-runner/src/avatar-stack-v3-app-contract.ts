export const avatarStackV3AppContract = {
  upstream: {
    repository: "https://github.com/instantdb/instant",
    revision: "e71017612aed4031710a35e2fcace30d38d557ac",
    recipe: "client/www/lib/recipes/avatar-stack.tsx",
    helper: "client/packages/react-common/src/InstantReactRoom.ts",
    helperTests: "client/packages/vue/src/tests/InstantVueDatabase.test.ts",
  },
  room: {
    type: "avatars-example",
    id: "avatars-example-1234",
  },
  fixtures: {
    swift: { userID: "abcdef123456", presence: { name: "abcdef" } },
    typeScript: { userID: "uvwxyz123456", presence: { name: "uvwxyz" } },
  },
  compilerWarningCount: 0,
} as const;

export interface AvatarStackV3Presence {
  name: string;
}

export interface AvatarStackV3Peer extends AvatarStackV3Presence {
  peerId: string;
}

export function nameForAvatarStackUserID(userID: string): string {
  return userID.slice(0, 6);
}
