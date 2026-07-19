export const syncUpsV3AppContract = {
  upstream: {
    repository: "https://github.com/pointfreeco/sqlite-data",
    revision: "0c79d7a5748fc6d9ce7a1ba2b50f31b175305049",
    schema: "Examples/SyncUps/Schema.swift",
    tests: [
      "Examples/SyncUpTests/SyncUpFormTests.swift",
      "Examples/SyncUps/RecordMeeting.swift",
    ],
  },
  namespaces: ["syncUps", "attendees", "meetings"],
  links: ["syncUpsAttendees", "syncUpsMeetings"],
  fixtures: {
    syncUp: "00000000-0000-4000-8000-000000000501",
    swiftAttendee: "00000000-0000-4000-8000-000000000502",
    swiftMeeting: "00000000-0000-4000-8000-000000000503",
    typeScriptAttendee: "00000000-0000-4000-8000-000000000504",
    typeScriptMeeting: "00000000-0000-4000-8000-000000000505",
  },
  compilerWarningCount: 0,
} as const;

export type SyncUpsV3Theme =
  | "appIndigo"
  | "appMagenta"
  | "appOrange"
  | "appPurple"
  | "appTeal"
  | "appYellow"
  | "bubblegum"
  | "buttercup"
  | "lavender"
  | "navy"
  | "oxblood"
  | "periwinkle"
  | "poppy"
  | "seafoam"
  | "sky"
  | "tan";

export interface SyncUpsV3Attendee {
  id: string;
  name: string;
}

export interface SyncUpsV3Meeting {
  id: string;
  date: Date;
  transcript: string;
}

export interface SyncUpsV3SyncUp {
  id: string;
  seconds: number;
  theme: SyncUpsV3Theme;
  title: string;
  attendees: SyncUpsV3Attendee[];
  meetings: SyncUpsV3Meeting[];
}

export const syncUpsV3Themes: readonly SyncUpsV3Theme[] = [
  "appIndigo",
  "appMagenta",
  "appOrange",
  "appPurple",
  "appTeal",
  "appYellow",
  "bubblegum",
  "buttercup",
  "lavender",
  "navy",
  "oxblood",
  "periwinkle",
  "poppy",
  "seafoam",
  "sky",
  "tan",
];
