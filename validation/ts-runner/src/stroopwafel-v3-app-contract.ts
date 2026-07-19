export const stroopwafelV3AppContract = {
  upstream: {
    repository: "https://github.com/jsventures/stroopwafel",
    revision: "7f5e2379464d932c0e4681655cbf022f8d9c2614",
    schema: "instant.schema.ts",
    permissions: "instant.perms.ts",
  },
  namespaces: ["$users", "rooms", "games", "points"],
  links: ["roomUsers", "gameUsers", "gameRooms", "gamePoints"],
  game: {
    inProgress: "GAME_IN_PROGRESS",
    completed: "GAME_COMPLETED",
    scoreToWin: 13,
    promptCount: 14,
    colors: ["red", "green", "blue", "yellow"],
  },
  fixtures: {
    room: {
      id: "00000000-0000-4000-8000-000000000301",
      code: "AB12",
    },
    game: {
      id: "00000000-0000-4000-8000-000000000302",
    },
    points: {
      swift: "00000000-0000-4000-8000-000000000303",
      typeScript: "00000000-0000-4000-8000-000000000304",
    },
  },
  compilerWarningCount: 0,
} as const;

export type StroopwafelV3Color =
  (typeof stroopwafelV3AppContract.game.colors)[number];
export type StroopwafelV3GameStatus =
  | typeof stroopwafelV3AppContract.game.inProgress
  | typeof stroopwafelV3AppContract.game.completed;

export interface StroopwafelV3User {
  id: string;
  email?: unknown;
  handle?: string;
  highScore?: number;
  created_at?: string;
}

export interface StroopwafelV3Room {
  id: string;
  code?: string;
  hostId: string;
  readyIds: string[];
  kickedIds: string[];
  currentGameId?: string;
  created_at: string;
  deleted_at?: string;
  users: StroopwafelV3User[];
}

export interface StroopwafelV3ColorPrompt {
  color: StroopwafelV3Color;
  label: StroopwafelV3Color;
}

export interface StroopwafelV3Point {
  id: string;
  val: number;
  userId: string;
}

export interface StroopwafelV3Game {
  id: string;
  status: StroopwafelV3GameStatus;
  playerIds: string[];
  colors: StroopwafelV3ColorPrompt[];
  created_at: string;
  users: StroopwafelV3User[];
  rooms: StroopwafelV3Room[];
  points: StroopwafelV3Point[];
}

export interface StroopwafelV3ScoreResult {
  value: number;
  status: StroopwafelV3GameStatus;
  clearsCurrentGame: boolean;
}

export function stroopwafelEligiblePlayerIDs(
  room: Pick<StroopwafelV3Room, "hostId" | "readyIds" | "users">,
): string[] {
  return room.users
    .map((user) => user.id)
    .filter((id) => id === room.hostId || room.readyIds.includes(id));
}

export function stroopwafelReadyIDs(
  readyIDs: ReadonlyArray<string>,
  userID: string,
  isReady: boolean,
): string[] {
  if (isReady) return readyIDs.includes(userID) ? [...readyIDs] : [...readyIDs, userID];
  return readyIDs.filter((id) => id !== userID);
}

export function stroopwafelScoreTap(
  value: number,
  prompt: StroopwafelV3ColorPrompt | undefined,
  selectedColor: StroopwafelV3Color,
): StroopwafelV3ScoreResult {
  const nextValue = selectedColor === prompt?.label
    ? value + 1
    : Math.max(value - 2, 0);
  const completed = nextValue === stroopwafelV3AppContract.game.scoreToWin;
  return {
    value: nextValue,
    status: completed
      ? stroopwafelV3AppContract.game.completed
      : stroopwafelV3AppContract.game.inProgress,
    clearsCurrentGame: completed,
  };
}

export function stroopwafelSoftDeletedRoom(
  room: StroopwafelV3Room,
  deletedAt: string,
): StroopwafelV3Room {
  const copy = { ...room, deleted_at: deletedAt };
  delete copy.code;
  return copy;
}
