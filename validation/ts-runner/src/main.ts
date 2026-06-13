import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const runnerDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(runnerDirectory, "../../..");
const usage =
  "Usage: node validation/ts-runner/src/main.ts [--fixtures] [--app-id id] [--fixtures-dir path]";

function timestampMs() {
  return Date.now();
}

function emit(row) {
  const { details = {}, ...rest } = row;
  console.log(
    JSON.stringify({
      side: "typescript",
      timestampMs: timestampMs(),
      ...rest,
      details,
    }),
  );
}

function parseArguments(argv) {
  const options = {
    appID: process.env.VALIDATION_APP_ID ?? "local-validation",
    fixturesDirectory:
      process.env.INSTANT_SWIFT_DATA_VALIDATION_FIXTURES
      ?? resolve(repositoryRoot, "validation/fixtures"),
  };

  const args = [...argv];
  while (args.length > 0) {
    const option = args.shift();
    switch (option) {
      case "--fixtures":
        break;

      case "--app-id": {
        const value = args.shift();
        if (!value) {
          throw new UsageError(usage);
        }
        options.appID = value;
        break;
      }

      case "--fixtures-dir": {
        const value = args.shift();
        if (!value) {
          throw new UsageError(usage);
        }
        options.fixturesDirectory = resolve(value);
        break;
      }

      case "--help":
      case "-h":
        throw new UsageError(usage, 0);

      default:
        throw new UsageError(`Unknown option: ${option}. ${usage}`);
    }
  }

  return options;
}

function readFixture(path, appID) {
  if (!existsSync(path)) {
    emit({
      case: "validation.typescript.fixtures",
      event: "fixture-missing",
      appID,
      ok: false,
      details: { path },
    });
    throw new Error(`Missing fixture: ${path}`);
  }
  return readFileSync(path, "utf8");
}

function requireSnippets(text, snippets) {
  return snippets.filter((snippet) => !text.includes(snippet));
}

function topLevelSchemaEntities(schemaText) {
  const entitiesBlock = schemaText.match(/entities:\s*\{([\s\S]*?)\n\s{2}\},\n\s{2}links:/)?.[1] ?? "";
  return [...entitiesBlock.matchAll(/^\s{4}([A-Za-z_$][\w$]*):\s*i\.entity\(/gm)]
    .map((match) => match[1]);
}

function permissionNamespaces(permsText) {
  return [...permsText.matchAll(/^\s{2}("?[$A-Za-z_][\w$]*"?):\s*\{/gm)]
    .map((match) => match[1].replace(/^"|"$/g, ""));
}

function verifyFixtures(options) {
  const schemaPath = resolve(options.fixturesDirectory, "instant.schema.ts");
  const permsPath = resolve(options.fixturesDirectory, "instant.perms.ts");
  emit({
    case: "validation.typescript.fixtures",
    event: "start",
    appID: options.appID,
    ok: true,
    details: {
      fixturesDirectory: options.fixturesDirectory,
    },
  });

  const schemaText = readFixture(schemaPath, options.appID);
  const permsText = readFixture(permsPath, options.appID);

  const schemaEntities = topLevelSchemaEntities(schemaText);
  const missingSchemaSnippets = requireSnippets(schemaText, [
    "import { i } from \"@instantdb/core\";",
    "const _schema = i.schema({",
    "profiles: i.entity({",
    "handle: i.string().unique().indexed()",
    "posts: i.entity({",
    "postAuthor: {",
    "forward: { on: \"posts\", has: \"one\", label: \"author\" }",
    "reverse: { on: \"profiles\", has: \"many\", label: \"posts\" }",
    "rooms: {",
    "validation: {",
    "presence: i.entity({",
    "topics: {",
    "ping: i.entity({",
    "export default schema;",
  ]);
  const schemaOK = missingSchemaSnippets.length === 0;
  emit({
    case: "validation.typescript.fixtures",
    event: "schema-fixture",
    appID: options.appID,
    ok: schemaOK,
    details: {
      path: schemaPath,
      entityNames: schemaEntities,
      missingSnippets: missingSchemaSnippets,
    },
  });

  const namespaces = permissionNamespaces(permsText);
  const missingPermissionSnippets = requireSnippets(permsText, [
    "const rules = {",
    "profiles: {",
    "posts: {",
    "\"$files\": {",
    "view: \"true\"",
    "create: \"true\"",
    "update: \"true\"",
    "delete: \"true\"",
    "export default rules;",
  ]);
  const permissionsOK = missingPermissionSnippets.length === 0;
  emit({
    case: "validation.typescript.fixtures",
    event: "permissions-fixture",
    appID: options.appID,
    ok: permissionsOK,
    details: {
      path: permsPath,
      namespaces,
      missingSnippets: missingPermissionSnippets,
    },
  });

  if (!schemaOK || !permissionsOK) {
    process.exitCode = 1;
    return;
  }

  emit({
    case: "validation.typescript.boundary",
    event: "real-instant-pending",
    appID: options.appID,
    ok: true,
    details: {
      reason:
        "Fixture parity is local-only until ephemeral app creation, schema push, and admin query/transact land.",
    },
  });
}

class UsageError extends Error {
  constructor(message, exitCode = 64) {
    super(message);
    this.exitCode = exitCode;
  }
}

try {
  verifyFixtures(parseArguments(process.argv.slice(2)));
} catch (error) {
  if (error instanceof UsageError) {
    if (error.exitCode === 0) {
      console.log(error.message);
    } else {
      emit({
        case: "validation.typescript.arguments",
        event: "failed",
        appID: process.env.VALIDATION_APP_ID ?? "local-validation",
        ok: false,
        details: { message: error.message },
      });
    }
    process.exit(error.exitCode);
  }

  emit({
    case: "validation.typescript.fixtures",
    event: "failed",
    appID: process.env.VALIDATION_APP_ID ?? "local-validation",
    ok: false,
    details: { message: String(error) },
  });
  process.exit(1);
}
