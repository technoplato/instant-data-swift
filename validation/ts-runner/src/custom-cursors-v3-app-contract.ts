import type { CursorsV3Cursor } from "./cursors-v3-app-contract.js";

export const customCursorsV3AppContract = {
  upstream: {
    repository: "https://github.com/instantdb/instant",
    revision: "e71017612aed4031710a35e2fcace30d38d557ac",
    recipe: "client/www/lib/recipes/custom-cursors.tsx",
    component: "client/packages/react/src/Cursors.tsx",
  },
  room: {
    type: "cursors-example",
    id: "124",
    spaceID: "cursors-space-default--cursors-example-124",
  },
  presence: {
    nameKey: "name",
  },
  avatar: {
    endpoint: "/api/avatar",
    size: 40,
  },
  fixtures: {
    swift: {
      name: "swift-custom-avatar",
      cursor: {
        x: 150,
        y: 90,
        xPercent: 25,
        yPercent: 40,
        color: "#123456",
      },
    },
    typeScript: {
      name: "typescript-custom-avatar",
      cursor: {
        x: 300,
        y: 200,
        xPercent: 75,
        yPercent: 60,
        color: "#654321",
      },
    },
  },
  compilerWarningCount: 0,
} as const;

export interface CustomCursorsV3Presence {
  name: string;
  "cursors-space-default--cursors-example-124"?: CursorsV3Cursor;
}

export function customCursorPresence(
  name: string,
  cursor: CursorsV3Cursor,
): CustomCursorsV3Presence {
  return {
    name,
    [customCursorsV3AppContract.room.spaceID]: cursor,
  };
}

export function presenceAfterCursorClear(name: string): CustomCursorsV3Presence {
  return { name };
}

export function customCursorAvatarURL(name: string): string {
  const { endpoint, size } = customCursorsV3AppContract.avatar;
  return `${endpoint}?name=${encodeURIComponent(name)}&size=${size}`;
}
