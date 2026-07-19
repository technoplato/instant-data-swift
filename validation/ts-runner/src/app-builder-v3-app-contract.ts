export const appBuilderV3AppContract = {
  upstream: {
    instant: {
      repository: "https://github.com/instantdb/instant",
      revision: "e71017612aed4031710a35e2fcace30d38d557ac",
      source: "client/www/_examples/app-builder.md",
    },
    app: {
      repository: "https://github.com/Galaxies-dev/app-builder",
      revision: "e67200cc70e01d88bd9a5382cf0380f4882fb8c7",
      sources: ["instant.schema.ts", "instant.perms.ts", "app/api/generate+api.tsx"],
    },
  },
  namespaces: ["$files", "$users", "builds"],
  links: ["buildFile", "buildOwner"],
  fixtures: {
    swiftBuild: "00000000-0000-4000-8000-000000000602",
    typeScriptBuild: "00000000-0000-4000-8000-000000000604",
  },
  swift: {
    title: "Build a workout tracker",
    instantAppId: "platform-app-swift",
    reasoning: "Plan the Swift-generated screen.",
    code: "export default function SwiftGeneratedApp() {}",
    filePath: "00000000-0000-4000-8000-000000000602-App.tsx",
  },
  typeScript: {
    title: "Build a notes app",
    instantAppId: "platform-app-typescript",
    reasoning: "Plan the TypeScript-generated screen.",
    code: "export default function TypeScriptGeneratedApp() {}",
    filePath: "00000000-0000-4000-8000-000000000604-App.tsx",
  },
  compilerWarningCount: 0,
} as const;

export interface AppBuilderV3User {
  id: string;
  email?: string;
}

export interface AppBuilderV3File {
  id: string;
  path: string;
  url: string;
  "content-disposition": string;
  "content-type": string;
  "key-version": number;
  "location-id": string;
  size: number;
}

export interface AppBuilderV3BuildError {
  from: string;
  status: number;
  message: string;
}

export interface AppBuilderV3Build {
  id: string;
  instantAppId: string;
  code: string;
  reasoning?: string;
  slug?: string;
  error?: AppBuilderV3BuildError;
  isPreviewable?: boolean;
  title?: string;
  owner: AppBuilderV3User;
  file?: AppBuilderV3File;
}
