export const remindersV3AppContract = {
  upstream: {
    repository: "https://github.com/pointfreeco/sqlite-data",
    revision: "0c79d7a5748fc6d9ce7a1ba2b50f31b175305049",
    schema: "Examples/Reminders/Schema.swift",
    tests: [
      "Examples/RemindersTests/RemindersListsTests.swift",
      "Examples/RemindersTests/RemindersDetailsTests.swift",
      "Examples/RemindersTests/SearchRemindersTests.swift",
      "Tests/SQLiteDataTests/CloudKitTests/SharingTests.swift",
      "Tests/SQLiteDataTests/CloudKitTests/SharingPermissionsTests.swift",
    ],
  },
  namespaces: [
    "$users",
    "remindersLists",
    "reminders",
    "tags",
    "v3_share_memberships",
    "v3_shares",
  ],
  links: [
    "remindersList",
    "remindersTags",
    "remindersListsOwner",
    "remindersListsReaders",
    "remindersListsWriters",
    "v3_share_membershipsShare",
    "v3_share_membershipsUser",
    "v3_sharesOwner",
    "v3_sharesRoot",
  ],
  priority: { low: 1, medium: 2, high: 3 },
  fixtures: {
    list: "00000000-0000-4000-8000-000000000401",
    swiftReminder: "00000000-0000-4000-8000-000000000402",
    share: "00000000-0000-4000-8000-000000000403",
    ownerMembership: "00000000-0000-4000-8000-000000000404",
    readerMembership: "00000000-0000-4000-8000-000000000405",
    typeScriptReminder: "00000000-0000-4000-8000-000000000406",
    swiftTag: "00000000-0000-4000-8000-000000000407",
    typeScriptTag: "00000000-0000-4000-8000-000000000408",
  },
  compilerWarningCount: 0,
} as const;

export type RemindersV3Priority =
  (typeof remindersV3AppContract.priority)[keyof typeof remindersV3AppContract.priority];
export type RemindersV3Role = "owner" | "writer" | "reader";

export interface RemindersV3User {
  id: string;
  email?: unknown;
}

export interface RemindersV3Tag {
  id: string;
  title: string;
}

export interface RemindersV3Reminder {
  id: string;
  title: string;
  notes: string;
  isCompleted: boolean;
  isFlagged: boolean;
  dueDate?: string;
  priority?: RemindersV3Priority;
  position: number;
  createdAt: string;
  tags: RemindersV3Tag[];
}

export interface RemindersV3ShareMembership {
  id: string;
  role: RemindersV3Role;
  acceptedAt: string;
  revokedAt?: string;
  user: RemindersV3User;
}

export interface RemindersV3Share {
  id: string;
  token: string;
  rootNamespace: "remindersLists";
  rootID: string;
  createdAt: string;
  updatedAt: string;
  revokedAt?: string;
  owner: RemindersV3User;
  memberships: RemindersV3ShareMembership[];
}

export interface RemindersV3List {
  id: string;
  title: string;
  color: string;
  position: number;
  createdAt: string;
  owner: RemindersV3User;
  readers: RemindersV3User[];
  writers: RemindersV3User[];
  reminders: RemindersV3Reminder[];
  share?: RemindersV3Share;
}

export function remindersV3CanWrite(role: RemindersV3Role): boolean {
  return role === "owner" || role === "writer";
}

export function remindersV3ReplaceTagIDs(
  _existingTagIDs: ReadonlyArray<string>,
  selectedTagIDs: ReadonlyArray<string>,
): string[] {
  return [...new Set(selectedTagIDs)];
}
