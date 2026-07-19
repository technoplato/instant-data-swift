export const reactionsV3AppContract = {
  upstream: {
    repository: "https://github.com/instantdb/instant",
    revision: "e71017612aed4031710a35e2fcace30d38d557ac",
    recipe: "client/www/lib/recipes/reactions.tsx",
    helper: "client/packages/react-common/src/InstantReactRoom.ts",
    helperTests: "client/packages/vue/src/tests/InstantVueDatabase.test.ts",
  },
  room: {
    type: "topics-example",
    id: "123",
    topic: "emoji",
  },
  reactions: {
    fire: "🔥",
    wave: "👋",
    confetti: "🎉",
    heart: "❤️",
  },
  swiftPublished: {
    name: "heart",
    directionAngle: 45,
    rotationAngle: 270,
  },
  typeScriptPublished: {
    name: "wave",
    directionAngle: 90,
    rotationAngle: 180,
  },
  invalidReceivedName: "sparkle",
  compilerWarningCount: 0,
} as const;

export type ReactionsV3AppContract = typeof reactionsV3AppContract;
export type ReactionsV3Name = keyof ReactionsV3AppContract["reactions"];

export interface ReactionsV3Payload {
  name: string;
  directionAngle: number;
  rotationAngle: number;
}
