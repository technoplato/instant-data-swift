export const reactionsV3AppContract = {
  upstream: {
    repository: "https://github.com/instantdb/instant",
    revision: "e71017612aed4031710a35e2fcace30d38d557ac",
    recipe: "client/www/lib/recipes/reactions.tsx",
    helper: "client/packages/react-common/src/InstantReactRoom.ts",
  },
  room: {
    type: "topics-example",
    id: "123",
    topic: "emoji",
  },
  names: ["fire", "wave", "confetti", "heart"],
  swiftPayload: {
    name: "wave",
    directionAngle: 90,
    rotationAngle: 180,
  },
  typeScriptPayload: {
    name: "heart",
    directionAngle: 45,
    rotationAngle: 270,
  },
  compilerWarningCount: 0,
} as const;

export type ReactionsV3AppContract = typeof reactionsV3AppContract;
export type ReactionsV3Name = ReactionsV3AppContract["names"][number];

export interface ReactionsV3Payload {
  name: string;
  directionAngle: number;
  rotationAngle: number;
}
