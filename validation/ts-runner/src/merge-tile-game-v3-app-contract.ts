export const mergeTileGameV3AppContract = {
  upstream: {
    repository: "https://github.com/instantdb/instant",
    revision: "e71017612aed4031710a35e2fcace30d38d557ac",
    recipe: "client/www/lib/recipes/merge-tile-game.tsx",
  },
  namespace: "boards",
  board: {
    id: "83c059e2-ed47-42e5-bdd9-6de88d26c521",
    size: 4,
    emptyColor: "#f5f3f0",
  },
  room: {
    type: "tile-game-example",
    id: "_defaultRoomId",
  },
  colors: [
    "#e76f51",
    "#2a9d8f",
    "#e9c46a",
    "#264653",
    "#f4a261",
    "#d4a0d0",
  ],
  fixtures: {
    swift: {
      cell: "0-0",
      color: "#e76f51",
    },
    typeScript: {
      cell: "0-1",
      color: "#2a9d8f",
    },
  },
  compilerWarningCount: 0,
} as const;

export type MergeTileGameV3Cell = `${number}-${number}`;
export type MergeTileGameV3BoardState = Record<MergeTileGameV3Cell, string>;

export interface MergeTileGameV3Board {
  id: string;
  state: MergeTileGameV3BoardState;
}

export interface MergeTileGameV3Presence {
  color: string;
}

export interface MergeTileGameV3BoardPatch {
  state: Partial<MergeTileGameV3BoardState>;
}

export function mergeTileGameEmptyState(): MergeTileGameV3BoardState {
  const state: Record<string, string> = {};
  const { size, emptyColor } = mergeTileGameV3AppContract.board;
  for (let row = 0; row < size; row += 1) {
    for (let column = 0; column < size; column += 1) {
      state[`${row}-${column}`] = emptyColor;
    }
  }
  return state as MergeTileGameV3BoardState;
}

export function mergeTileGameBoardPatch(
  cell: MergeTileGameV3Cell,
  color: string,
): MergeTileGameV3BoardPatch {
  return { state: { [cell]: color } };
}

export function mergeTileGameMergedState(
  state: MergeTileGameV3BoardState,
  patch: MergeTileGameV3BoardPatch,
): MergeTileGameV3BoardState {
  const merged = { ...state };
  for (const [cell, color] of Object.entries(patch.state)) {
    if (color !== undefined) merged[cell as MergeTileGameV3Cell] = color;
  }
  return merged;
}

export function mergeTileGamePresence(color: string): MergeTileGameV3Presence {
  return { color };
}
