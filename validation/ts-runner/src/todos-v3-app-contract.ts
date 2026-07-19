export const todosV3AppContract = {
  namespace: "todos",
  roomType: "todos",
  swiftCreated: {
    id: "todos-v3-swift",
    text: "Swift live todo",
    isCompleted: true,
    createdAtMilliseconds: 1_700_000_000_000,
  },
  typeScriptCreated: {
    id: "todos-v3-typescript",
    text: "TypeScript live todo",
    isCompleted: false,
    createdAtMilliseconds: 1_700_000_001_000,
  },
} as const;
