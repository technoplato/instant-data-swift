import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const runnerDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(runnerDirectory, "../../..");
const usage =
  "Usage: node validation/ts-runner/src/main.ts [--fixtures|--boundary-preflight|--swift-transport-contract path|--swift-local-integrations-contract path|--swift-live-session-contract path|--swift-live-transaction-contract path|--typescript-server-transaction-contract path] [--require-boundary] [--app-id id] [--fixtures-dir path]";
const defaultAPIURI = "https://api.instantdb.com";
const defaultWebSocketURI = "wss://api.instantdb.com/runtime/session";

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

function resolvedAdminToken() {
  const candidates = [
    ["INSTANT_ADMIN_TOKEN", process.env.INSTANT_ADMIN_TOKEN],
    ["INSTANTDB_ADMIN_TOKEN", process.env.INSTANTDB_ADMIN_TOKEN],
  ];
  for (const [source, value] of candidates) {
    const trimmed = value?.trim();
    if (trimmed) {
      return { source, value: trimmed };
    }
  }
  return { source: null, value: "" };
}

function parseArguments(argv) {
  const adminToken = resolvedAdminToken();
  let appIDExplicit = false;
  const options = {
    mode: "fixtures",
    appID: process.env.VALIDATION_APP_ID ?? "local-validation",
    fixturesDirectory:
      process.env.INSTANT_SWIFT_DATA_VALIDATION_FIXTURES
      ?? resolve(repositoryRoot, "validation/fixtures"),
    requireBoundary: false,
    apiURI: process.env.INSTANT_API_URI ?? defaultAPIURI,
    websocketURI: process.env.INSTANT_WEBSOCKET_URI ?? defaultWebSocketURI,
    adminToken: adminToken.value,
    adminTokenSource: adminToken.source,
    swiftTransportContractPath: null,
    swiftLocalIntegrationsContractPath: null,
    swiftLiveSessionContractPath: null,
    swiftLiveTransactionContractPath: null,
    typeScriptServerTransactionContractPath: null,
  };

  const args = [...argv];
  while (args.length > 0) {
    const option = args.shift();
    switch (option) {
      case "--fixtures":
        options.mode = "fixtures";
        break;

      case "--boundary-preflight":
        options.mode = "boundary-preflight";
        break;

      case "--require-boundary":
        options.requireBoundary = true;
        break;

      case "--swift-transport-contract": {
        const value = args.shift();
        if (!value) {
          throw new UsageError(usage);
        }
        options.mode = "swift-transport-contract";
        options.swiftTransportContractPath = resolve(value);
        break;
      }

      case "--swift-local-integrations-contract": {
        const value = args.shift();
        if (!value) {
          throw new UsageError(usage);
        }
        options.mode = "swift-local-integrations-contract";
        options.swiftLocalIntegrationsContractPath = resolve(value);
        break;
      }

      case "--swift-live-session-contract": {
        const value = args.shift();
        if (!value) {
          throw new UsageError(usage);
        }
        options.mode = "swift-live-session-contract";
        options.swiftLiveSessionContractPath = resolve(value);
        break;
      }

      case "--swift-live-transaction-contract": {
        const value = args.shift();
        if (!value) {
          throw new UsageError(usage);
        }
        options.mode = "swift-live-transaction-contract";
        options.swiftLiveTransactionContractPath = resolve(value);
        break;
      }

      case "--typescript-server-transaction-contract": {
        const value = args.shift();
        if (!value) {
          throw new UsageError(usage);
        }
        options.mode = "typescript-server-transaction-contract";
        options.typeScriptServerTransactionContractPath = resolve(value);
        break;
      }

      case "--app-id": {
        const value = args.shift();
        if (!value) {
          throw new UsageError(usage);
        }
        options.appID = value.trim();
        appIDExplicit = true;
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

  if (options.mode === "boundary-preflight" && !appIDExplicit) {
    options.appID =
      (process.env.INSTANT_SWIFT_DATA_REMOTE_APP_ID
        ?? process.env.INSTANT_APP_ID
        ?? options.appID).trim();
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

function withoutComments(text) {
  let output = "";
  let quote = null;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    const next = text[index + 1];

    if (lineComment) {
      if (character === "\n") {
        lineComment = false;
        output += "\n";
      } else {
        output += " ";
      }
      continue;
    }

    if (blockComment) {
      if (character === "*" && next === "/") {
        blockComment = false;
        output += "  ";
        index += 1;
      } else {
        output += character === "\n" ? "\n" : " ";
      }
      continue;
    }

    if (quote) {
      output += character;
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === quote) {
        quote = null;
      }
      continue;
    }

    if (character === "/" && next === "/") {
      lineComment = true;
      output += "  ";
      index += 1;
      continue;
    }

    if (character === "/" && next === "*") {
      blockComment = true;
      output += "  ";
      index += 1;
      continue;
    }

    if (character === "\"" || character === "'" || character === "`") {
      quote = character;
    }
    output += character;
  }

  return output;
}

function indexOfOutsideString(text, marker, startIndex = 0) {
  let quote = null;
  let escaped = false;

  for (let index = startIndex; index < text.length; index += 1) {
    const character = text[index];

    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === quote) {
        quote = null;
      }
      continue;
    }

    if (character === "\"" || character === "'" || character === "`") {
      quote = character;
      continue;
    }

    if (text.startsWith(marker, index)) {
      return index;
    }
  }

  return -1;
}

function balancedBlock(text, openIndex) {
  if (openIndex < 0 || text[openIndex] !== "{") {
    return null;
  }

  let depth = 0;
  let quote = null;
  let escaped = false;
  let lineComment = false;
  let blockComment = false;

  for (let index = openIndex; index < text.length; index += 1) {
    const character = text[index];
    const next = text[index + 1];

    if (lineComment) {
      if (character === "\n") {
        lineComment = false;
      }
      continue;
    }

    if (blockComment) {
      if (character === "*" && next === "/") {
        blockComment = false;
        index += 1;
      }
      continue;
    }

    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === quote) {
        quote = null;
      }
      continue;
    }

    if (character === "/" && next === "/") {
      lineComment = true;
      index += 1;
      continue;
    }

    if (character === "/" && next === "*") {
      blockComment = true;
      index += 1;
      continue;
    }

    if (character === "\"" || character === "'" || character === "`") {
      quote = character;
      continue;
    }

    if (character === "{") {
      depth += 1;
      continue;
    }

    if (character === "}") {
      depth -= 1;
      if (depth === 0) {
        return {
          start: openIndex,
          end: index,
          content: text.slice(openIndex + 1, index),
        };
      }
    }
  }

  return null;
}

function blockAfter(text, marker, startIndex = 0) {
  const markerIndex = indexOfOutsideString(text, marker, startIndex);
  if (markerIndex < 0) {
    return null;
  }
  const openIndex = indexOfOutsideString(text, "{", markerIndex + marker.length);
  return balancedBlock(text, openIndex);
}

function skipTrivia(text, index) {
  let cursor = index;
  while (cursor < text.length) {
    const character = text[cursor];
    const next = text[cursor + 1];
    if (/\s|,/.test(character)) {
      cursor += 1;
    } else if (character === "/" && next === "/") {
      cursor = text.indexOf("\n", cursor + 2);
      if (cursor < 0) {
        return text.length;
      }
    } else if (character === "/" && next === "*") {
      const closeIndex = text.indexOf("*/", cursor + 2);
      if (closeIndex < 0) {
        return text.length;
      }
      cursor = closeIndex + 2;
    } else {
      break;
    }
  }
  return cursor;
}

function propertyNameAt(text, index) {
  const character = text[index];
  if (character === "\"" || character === "'") {
    let cursor = index + 1;
    let escaped = false;
    while (cursor < text.length) {
      const current = text[cursor];
      if (escaped) {
        escaped = false;
      } else if (current === "\\") {
        escaped = true;
      } else if (current === character) {
        return { name: text.slice(index + 1, cursor), end: cursor + 1 };
      }
      cursor += 1;
    }
    return null;
  }

  const match = text.slice(index).match(/^[$A-Za-z_][\w$]*/);
  if (!match) {
    return null;
  }
  return { name: match[0], end: index + match[0].length };
}

function topLevelValueAt(text, index) {
  let cursor = index;
  let depth = 0;
  let quote = null;
  let escaped = false;

  while (cursor < text.length) {
    const character = text[cursor];

    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === quote) {
        quote = null;
      }
      cursor += 1;
      continue;
    }

    if (character === "\"" || character === "'" || character === "`") {
      quote = character;
      cursor += 1;
      continue;
    }

    if (character === "{" || character === "(" || character === "[") {
      depth += 1;
      cursor += 1;
      continue;
    }

    if (character === "}" || character === ")" || character === "]") {
      if (depth === 0) {
        break;
      }
      depth -= 1;
      cursor += 1;
      continue;
    }

    if (character === "," && depth === 0) {
      break;
    }

    cursor += 1;
  }

  return {
    value: text.slice(index, cursor).trim(),
    end: cursor,
  };
}

function topLevelPropertyValues(blockContent) {
  const entries = {};
  let cursor = 0;
  while (cursor < blockContent.length) {
    cursor = skipTrivia(blockContent, cursor);
    const property = propertyNameAt(blockContent, cursor);
    if (!property) {
      cursor += 1;
      continue;
    }

    let valueIndex = skipTrivia(blockContent, property.end);
    if (blockContent[valueIndex] !== ":") {
      cursor = property.end;
      continue;
    }

    valueIndex = skipTrivia(blockContent, valueIndex + 1);
    const value = topLevelValueAt(blockContent, valueIndex);
    if (!value.value) {
      cursor = valueIndex + 1;
      continue;
    }

    entries[property.name] = value.value;
    cursor = value.end + 1;
  }
  return entries;
}

function objectLiteralContent(value) {
  const trimmed = value.trim();
  if (!trimmed.startsWith("{")) {
    return null;
  }
  return balancedBlock(trimmed, 0)?.content ?? null;
}

function entityCallContent(value) {
  const trimmed = value.trim();
  if (!/^i\.entity\s*\(/.test(trimmed)) {
    return null;
  }
  const openIndex = indexOfOutsideString(trimmed, "{");
  return balancedBlock(trimmed, openIndex)?.content ?? null;
}

function entityFields(entityBody) {
  const fields = {};
  for (const [name, value] of Object.entries(topLevelPropertyValues(entityBody))) {
    const match = value.match(
      /^i\.(string|number|boolean|date|json)\s*\(\s*\)\s*((?:\.\s*(?:unique|indexed|optional)\s*\(\s*\)\s*)*)$/s,
    );
    if (!match) {
      continue;
    }
    fields[name] = {
      type: match[1],
      modifiers: [...match[2].matchAll(/\.\s*(unique|indexed|optional)\s*\(\s*\)/g)]
        .map((modifierMatch) => modifierMatch[1]),
    };
  }
  return fields;
}

function namedEntityFields(blockContent) {
  const entities = {};
  for (const [name, value] of Object.entries(topLevelPropertyValues(blockContent))) {
    const content = entityCallContent(value);
    if (content !== null) {
      entities[name] = entityFields(content);
    }
  }
  return entities;
}

function quotedStringValue(value) {
  const match = value.trim().match(/^["']([^"']*)["']$/s);
  return match ? match[1] : null;
}

function parseLinkEndpoint(linkBody, direction) {
  const endpointValue = topLevelPropertyValues(linkBody)[direction];
  const endpointContent = endpointValue ? objectLiteralContent(endpointValue) : null;
  if (!endpointContent) {
    return null;
  }
  const endpointProperties = topLevelPropertyValues(endpointContent);
  const on = quotedStringValue(endpointProperties.on ?? "");
  const has = quotedStringValue(endpointProperties.has ?? "");
  const label = quotedStringValue(endpointProperties.label ?? "");
  return on && has && label ? { on, has, label } : null;
}

function schemaLinks(linksBlock) {
  const links = {};
  for (const [name, value] of Object.entries(topLevelPropertyValues(linksBlock))) {
    const body = objectLiteralContent(value);
    if (!body) {
      continue;
    }
    links[name] = {
      forward: parseLinkEndpoint(body, "forward"),
      reverse: parseLinkEndpoint(body, "reverse"),
    };
  }
  return links;
}

function schemaRooms(roomsBlock) {
  const rooms = {};
  for (const [name, value] of Object.entries(topLevelPropertyValues(roomsBlock))) {
    const body = objectLiteralContent(value);
    if (!body) {
      continue;
    }
    const roomProperties = topLevelPropertyValues(body);
    const presenceContent = roomProperties.presence
      ? entityCallContent(roomProperties.presence)
      : null;
    const topicsContent = roomProperties.topics
      ? objectLiteralContent(roomProperties.topics)
      : null;
    rooms[name] = {
      presence: presenceContent ? entityFields(presenceContent) : null,
      topics: topicsContent ? namedEntityFields(topicsContent) : {},
    };
  }
  return rooms;
}

function stringProperties(blockContent) {
  const properties = {};
  for (const [name, value] of Object.entries(topLevelPropertyValues(blockContent))) {
    const string = quotedStringValue(value);
    if (string !== null) {
      properties[name] = string;
    }
  }
  return properties;
}

function permissions(permsText) {
  const text = withoutComments(permsText);
  const rulesBlock = blockAfter(text, "const rules =");
  const namespaces = {};
  if (rulesBlock) {
    for (const [name, value] of Object.entries(topLevelPropertyValues(rulesBlock.content))) {
      const namespaceContent = objectLiteralContent(value);
      if (!namespaceContent) {
        continue;
      }
      const namespaceProperties = topLevelPropertyValues(namespaceContent);
      const allowContent = namespaceProperties.allow
        ? objectLiteralContent(namespaceProperties.allow)
        : null;
      namespaces[name] = allowContent ? stringProperties(allowContent) : null;
    }
  }
  return {
    exportsDefault: text.includes("export default rules;"),
    namespaces,
  };
}

function sortObjectKeys(value) {
  if (Array.isArray(value)) {
    return value.map(sortObjectKeys);
  }
  if (!value || typeof value !== "object") {
    return value;
  }

  return Object.fromEntries(
    Object.keys(value)
      .sort()
      .map((key) => [key, sortObjectKeys(value[key])]),
  );
}

function differences(actual, expected, path = "$") {
  if (Object.is(actual, expected)) {
    return [];
  }

  if (Array.isArray(actual) || Array.isArray(expected)) {
    if (!Array.isArray(actual) || !Array.isArray(expected)) {
      return [{ path, expected, actual }];
    }
    const issues = [];
    const count = Math.max(actual.length, expected.length);
    for (let index = 0; index < count; index += 1) {
      issues.push(...differences(actual[index], expected[index], `${path}[${index}]`));
    }
    return issues;
  }

  if (
    actual
    && expected
    && typeof actual === "object"
    && typeof expected === "object"
  ) {
    const issues = [];
    const keys = [...new Set([...Object.keys(actual), ...Object.keys(expected)])].sort();
    for (const key of keys) {
      issues.push(...differences(actual[key], expected[key], `${path}.${key}`));
    }
    return issues;
  }

  return [{
    path,
    expected: expected === undefined ? { missing: true } : expected,
    actual: actual === undefined ? { missing: true } : actual,
  }];
}

const expectedSchema = {
  importsInstantCore: true,
  exportsDefault: true,
  entities: {
    posts: {
      content: { type: "string", modifiers: [] },
      createdAt: { type: "date", modifiers: ["indexed"] },
    },
    profiles: {
      createdAt: { type: "date", modifiers: ["indexed"] },
      displayName: { type: "string", modifiers: [] },
      handle: { type: "string", modifiers: ["unique", "indexed"] },
    },
  },
  links: {
    postAuthor: {
      forward: { on: "posts", has: "one", label: "author" },
      reverse: { on: "profiles", has: "many", label: "posts" },
    },
  },
  rooms: {
    validation: {
      presence: {
        cursorX: { type: "number", modifiers: ["optional"] },
        cursorY: { type: "number", modifiers: ["optional"] },
        name: { type: "string", modifiers: [] },
      },
      topics: {
        ping: {
          message: { type: "string", modifiers: [] },
          sentAt: { type: "date", modifiers: [] },
        },
      },
    },
  },
};

const expectedPermissions = {
  exportsDefault: true,
  namespaces: {
    "$files": {
      create: "true",
      delete: "true",
      update: "true",
      view: "true",
    },
    posts: {
      create: "true",
      delete: "true",
      update: "true",
      view: "true",
    },
    profiles: {
      create: "true",
      delete: "true",
      update: "true",
      view: "true",
    },
  },
};

function schemaFixture(schemaText) {
  const text = withoutComments(schemaText);
  const entitiesBlock = blockAfter(text, "entities:");
  const linksBlock = blockAfter(text, "links:");
  const roomsBlock = blockAfter(text, "rooms:");
  return {
    importsInstantCore: text.includes("import { i } from \"@instantdb/core\";"),
    exportsDefault: text.includes("export default schema;"),
    entities: entitiesBlock ? namedEntityFields(entitiesBlock.content) : {},
    links: linksBlock ? schemaLinks(linksBlock.content) : {},
    rooms: roomsBlock ? schemaRooms(roomsBlock.content) : {},
  };
}

function validationDetails(actual, expected) {
  const normalizedActual = sortObjectKeys(actual);
  const normalizedExpected = sortObjectKeys(expected);
  const issues = differences(normalizedActual, normalizedExpected);
  return {
    ok: issues.length === 0,
    actual: normalizedActual,
    expected: normalizedExpected,
    issues,
  };
}

function endpointIssue(value, allowedProtocols) {
  let url;
  try {
    url = new URL(value);
  } catch {
    return "must be an absolute URL";
  }

  if (!allowedProtocols.includes(url.protocol)) {
    return `scheme must be one of ${allowedProtocols.map((protocol) => protocol.slice(0, -1)).join(", ")}`;
  }
  if (url.username || url.password) {
    return "must not include credentials";
  }
  if (!url.hostname) {
    return "must include a host";
  }
  if (url.search || url.hash) {
    return "must not include a query or fragment";
  }
  return null;
}

function redactedEndpoint(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    return "<invalid-url>";
  }

  const host = url.host || "<missing-host>";
  const path = url.pathname && url.pathname !== "/" ? "/..." : "";
  return `${url.protocol}//${host}${path}`;
}

function verifyBoundaryPreflight(options) {
  const requiredEnvironment = [
    "INSTANT_SWIFT_DATA_REMOTE_APP_ID or INSTANT_APP_ID",
    "INSTANT_ADMIN_TOKEN or INSTANTDB_ADMIN_TOKEN",
  ];
  const optionalEnvironment = [
    "INSTANT_API_URI",
    "INSTANT_WEBSOCKET_URI",
  ];
  const missing = [];
  const invalid = [];

  if (!options.appID || options.appID === "local-validation") {
    missing.push("INSTANT_SWIFT_DATA_REMOTE_APP_ID or INSTANT_APP_ID");
  }
  if (!options.adminToken) {
    missing.push("INSTANT_ADMIN_TOKEN or INSTANTDB_ADMIN_TOKEN");
  }

  const apiIssue = endpointIssue(options.apiURI, ["http:", "https:"]);
  if (apiIssue) {
    invalid.push({
      name: "INSTANT_API_URI",
      value: redactedEndpoint(options.apiURI),
      issue: apiIssue,
    });
  }
  const websocketIssue = endpointIssue(options.websocketURI, ["ws:", "wss:"]);
  if (websocketIssue) {
    invalid.push({
      name: "INSTANT_WEBSOCKET_URI",
      value: redactedEndpoint(options.websocketURI),
      issue: websocketIssue,
    });
  }

  const ok = missing.length === 0 && invalid.length === 0;
  emit({
    case: "validation.typescript.boundary",
    event: ok ? "preflight-ready" : "preflight-skipped",
    appID: options.appID,
    ok,
    details: {
      required: options.requireBoundary,
      requiredEnvironment,
      optionalEnvironment,
      missing,
      invalid,
      apiURI: redactedEndpoint(options.apiURI),
      websocketURI: redactedEndpoint(options.websocketURI),
      adminTokenPresent: Boolean(options.adminToken),
      adminTokenSource: options.adminTokenSource,
      implementation:
        "Real Swift/TypeScript observe/write round trips remain blocked until live transport lands.",
      next:
        "Use these credentials for ephemeral app setup, schema push, admin transact/query, and cross-client subscriptions.",
    },
  });

  if (!ok && options.requireBoundary) {
    process.exitCode = 1;
  }
}

const expectedSwiftTransportContract = {
  appID: "local-validation",
  event: "transport",
  transport: "not-implemented-local-cache-only",
  includeFailed: false,
  mutationCount: 1,
  mutationArrayCount: 1,
  txStepCount: 3,
  preconditionCount: 0,
  mutationID: "validation-transport-contract",
  status: "pending",
  txSteps: [
    ["add-triple", "contract-note", "validationTransport/id", "contract-note"],
    ["add-triple", "contract-note", "validationTransport/done", false],
    [
      "add-triple",
      "contract-note",
      "validationTransport/title",
      "Swift transport contract",
    ],
  ],
};

function issue(path, expected, actual) {
  return { path, expected, actual };
}

function verifySwiftTransportContract(options) {
  const path = options.swiftTransportContractPath;
  if (!path || !existsSync(path)) {
    emit({
      case: "validation.typescript.transport-contract",
      event: "swift-transport-contract",
      appID: options.appID,
      ok: false,
      details: {
        path,
        proofLevel: "contract-only",
        remoteBoundary: "pending",
        issues: [issue("$.path", "existing Swift transport artifact", path)],
      },
    });
    process.exitCode = 1;
    return;
  }

  let payload;
  try {
    payload = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    emit({
      case: "validation.typescript.transport-contract",
      event: "swift-transport-contract",
      appID: options.appID,
      ok: false,
      details: {
        path,
        proofLevel: "contract-only",
        remoteBoundary: "pending",
        issues: [issue("$.json", "valid JSON", String(error))],
      },
    });
    process.exitCode = 1;
    return;
  }

  const mutation = Array.isArray(payload.mutations) ? payload.mutations[0] : undefined;
  const actual = {
    appID: payload.appID,
    event: payload.event,
    transport: payload.transport,
    includeFailed: payload.includeFailed,
    mutationCount: payload.mutationCount,
    mutationArrayCount: Array.isArray(payload.mutations) ? payload.mutations.length : null,
    txStepCount: payload.txStepCount,
    preconditionCount: payload.preconditionCount,
    mutationID: mutation?.mutationID,
    transactionID: mutation?.transactionID,
    status: mutation?.status,
    preconditions: mutation?.preconditions,
    txSteps: mutation?.txSteps,
  };
  const expected = {
    ...expectedSwiftTransportContract,
    appID: options.appID,
    transactionID: expectedSwiftTransportContract.mutationID,
    preconditions: [],
  };
  const issues = [];

  for (const key of [
    "appID",
    "event",
    "transport",
    "includeFailed",
    "mutationCount",
    "mutationArrayCount",
    "txStepCount",
    "preconditionCount",
    "mutationID",
    "transactionID",
    "status",
  ]) {
    if (!Object.is(actual[key], expected[key])) {
      issues.push(issue(`$.${key}`, expected[key], actual[key]));
    }
  }
  if (JSON.stringify(actual.preconditions ?? null) !== JSON.stringify(expected.preconditions)) {
    issues.push(issue("$.preconditions", expected.preconditions, actual.preconditions));
  }
  if (JSON.stringify(actual.txSteps ?? null) !== JSON.stringify(expected.txSteps)) {
    issues.push(issue("$.txSteps", expected.txSteps, actual.txSteps));
  }

  const ok = issues.length === 0;
  emit({
    case: "validation.typescript.transport-contract",
    event: "swift-transport-contract",
    appID: options.appID,
    ok,
    details: {
      path,
      proofLevel: "contract-only",
      remoteBoundary: "pending",
      expected,
      actual,
      issues,
    },
  });

  if (!ok) {
    process.exitCode = 1;
  }
}

function readJSONLines(path) {
  return readFileSync(path, "utf8")
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0)
    .map((line, index) => {
      try {
        return JSON.parse(line);
      } catch (error) {
        throw new Error(`Invalid JSONL at ${path}:${index + 1}: ${String(error)}`);
      }
    });
}

function sameArray(actual, expected) {
  return JSON.stringify(actual ?? null) === JSON.stringify(expected);
}

function verifySwiftLocalIntegrationsContract(options) {
  const path = options.swiftLocalIntegrationsContractPath;
  if (!path || !existsSync(path)) {
    emit({
      case: "validation.typescript.local-integrations-contract",
      event: "swift-local-integrations-contract",
      appID: options.appID,
      ok: false,
      details: {
        path,
        proofLevel: "contract-only",
        remoteBoundary: "local-room-contract",
        issues: [issue("$.path", "existing Swift local-integrations JSONL artifact", path)],
      },
    });
    process.exitCode = 1;
    return;
  }

  let rows;
  try {
    rows = readJSONLines(path);
  } catch (error) {
    emit({
      case: "validation.typescript.local-integrations-contract",
      event: "swift-local-integrations-contract",
      appID: options.appID,
      ok: false,
      details: {
        path,
        proofLevel: "contract-only",
        remoteBoundary: "local-room-contract",
        issues: [issue("$.jsonl", "valid Swift local-integrations JSONL", String(error))],
      },
    });
    process.exitCode = 1;
    return;
  }

  const expectedEvents = [
    "auth",
    "room-presence",
    "room-topic",
    "file",
    "stream",
    "share-create",
    "share-accept",
    "share-revoke",
    "relaunch",
  ];
  const actualEvents = rows.map((row) => row.event);
  const issues = [];

  if (!sameArray(actualEvents, expectedEvents)) {
    issues.push(issue("$.events", expectedEvents, actualEvents));
  }

  for (const [index, row] of rows.entries()) {
    if (row.case !== "validation.local.integrations") {
      issues.push(issue(`$[${index}].case`, "validation.local.integrations", row.case));
    }
    if (row.side !== "swift") {
      issues.push(issue(`$[${index}].side`, "swift", row.side));
    }
    if (row.appID !== options.appID) {
      issues.push(issue(`$[${index}].appID`, options.appID, row.appID));
    }
    if (row.ok !== true) {
      issues.push(issue(`$[${index}].ok`, true, row.ok));
    }
  }

  const presenceRow = rows.find((row) => row.event === "room-presence");
  const topicRow = rows.find((row) => row.event === "room-topic");
  const relaunchRow = rows.find((row) => row.event === "relaunch");
  const presenceDetails = presenceRow?.details ?? {};
  const topicDetails = topicRow?.details ?? {};
  const relaunchDetails = relaunchRow?.details ?? {};

  for (const [pathPrefix, details] of [
    ["$.room-presence.details", presenceDetails],
    ["$.room-topic.details", topicDetails],
    ["$.relaunch.details", relaunchDetails],
  ]) {
    if (details.roomType !== "chat") {
      issues.push(issue(`${pathPrefix}.roomType`, "chat", details.roomType));
    }
    if (details.roomID !== "validation") {
      issues.push(issue(`${pathPrefix}.roomID`, "validation", details.roomID));
    }
    if (details.topic !== "sendEmoji") {
      issues.push(issue(`${pathPrefix}.topic`, "sendEmoji", details.topic));
    }
  }

  if (presenceDetails.authUserID !== "user-1") {
    issues.push(issue("$.room-presence.details.authUserID", "user-1", presenceDetails.authUserID));
  }
  if (!sameArray(presenceDetails.roomMemberIDs, ["user-1"])) {
    issues.push(
      issue("$.room-presence.details.roomMemberIDs", ["user-1"], presenceDetails.roomMemberIDs),
    );
  }
  if (!sameArray(presenceDetails.roomPresenceValueKeys, ["name", "status"])) {
    issues.push(
      issue(
        "$.room-presence.details.roomPresenceValueKeys",
        ["name", "status"],
        presenceDetails.roomPresenceValueKeys,
      ),
    );
  }
  if (!Array.isArray(topicDetails.topicMessageIDs) || topicDetails.topicMessageIDs.length !== 1) {
    issues.push(
      issue("$.room-topic.details.topicMessageIDs.length", 1, topicDetails.topicMessageIDs),
    );
  }
  if (!sameArray(topicDetails.topicPayloadKeys, ["emoji"])) {
    issues.push(issue("$.room-topic.details.topicPayloadKeys", ["emoji"], topicDetails.topicPayloadKeys));
  }
  if (!sameArray(relaunchDetails.roomMemberIDs, ["user-1"])) {
    issues.push(issue("$.relaunch.details.roomMemberIDs", ["user-1"], relaunchDetails.roomMemberIDs));
  }
  if (!sameArray(relaunchDetails.roomPresenceValueKeys, ["name", "status"])) {
    issues.push(
      issue(
        "$.relaunch.details.roomPresenceValueKeys",
        ["name", "status"],
        relaunchDetails.roomPresenceValueKeys,
      ),
    );
  }
  if (
    !Array.isArray(relaunchDetails.topicMessageIDs)
      || relaunchDetails.topicMessageIDs.length !== 1
  ) {
    issues.push(
      issue("$.relaunch.details.topicMessageIDs.length", 1, relaunchDetails.topicMessageIDs),
    );
  }
  if (!sameArray(relaunchDetails.topicPayloadKeys, ["emoji"])) {
    issues.push(issue("$.relaunch.details.topicPayloadKeys", ["emoji"], relaunchDetails.topicPayloadKeys));
  }

  const ok = issues.length === 0;
  emit({
    case: "validation.typescript.local-integrations-contract",
    event: "swift-local-integrations-contract",
    appID: options.appID,
    ok,
    details: {
      path,
      proofLevel: "contract-only",
      remoteBoundary: "local-room-contract",
      expectedEvents,
      actualEvents,
      room: {
        type: presenceDetails.roomType ?? null,
        id: presenceDetails.roomID ?? null,
      },
      topic: topicDetails.topic ?? null,
      roomMemberIDs: relaunchDetails.roomMemberIDs ?? [],
      topicMessageIDs: relaunchDetails.topicMessageIDs ?? [],
      roomPresenceValueKeys: relaunchDetails.roomPresenceValueKeys ?? [],
      topicPayloadKeys: relaunchDetails.topicPayloadKeys ?? [],
      issues,
    },
  });

  if (!ok) {
    process.exitCode = 1;
  }
}

function verifySwiftLiveSessionContract(options) {
  const path = options.swiftLiveSessionContractPath;
  if (!path || !existsSync(path)) {
    emit({
      case: "validation.typescript.live-session-contract",
      event: "swift-live-session-contract",
      appID: options.appID,
      ok: false,
      details: {
        path,
        proofLevel: "contract-only",
        remoteBoundary: "pending-cross-client-sync",
        issues: [issue("$.path", "existing Swift live-session JSONL artifact", path)],
      },
    });
    process.exitCode = 1;
    return;
  }

  let rows;
  try {
    rows = readJSONLines(path);
  } catch (error) {
    emit({
      case: "validation.typescript.live-session-contract",
      event: "swift-live-session-contract",
      appID: options.appID,
      ok: false,
      details: {
        path,
        proofLevel: "contract-only",
        remoteBoundary: "pending-cross-client-sync",
        issues: [issue("$.jsonl", "valid Swift live-session JSONL", String(error))],
      },
    });
    process.exitCode = 1;
    return;
  }

  const actualEvents = rows.map((row) => row.event);
  const finalRow = rows[rows.length - 1];
  const details = finalRow?.details ?? {};
  const receivedOps = Array.isArray(details.receivedOps) ? details.receivedOps : [];
  const finalEventByReceivedOp = {
    "add-query-ok": "receive-query",
    "add-query-exists": "receive-query",
    "refresh-ok": "receive-refresh",
  };
  const expectedEvents = [
    "session-url",
    "send-init",
    "receive-init-ok",
    "send-add-query",
    finalEventByReceivedOp[receivedOps[1]] ?? "receive-query|receive-refresh",
  ];
  const issues = [];

  if (
    actualEvents.length !== 5
      || !sameArray(actualEvents.slice(0, 4), expectedEvents.slice(0, 4))
      || !["receive-query", "receive-refresh"].includes(actualEvents[4])
  ) {
    issues.push(issue("$.events", expectedEvents, actualEvents));
  }
  for (const [index, row] of rows.entries()) {
    if (row.case !== "validation.live.session") {
      issues.push(issue(`$[${index}].case`, "validation.live.session", row.case));
    }
    if (row.side !== "swift") {
      issues.push(issue(`$[${index}].side`, "swift", row.side));
    }
    if (row.appID !== options.appID) {
      issues.push(issue(`$[${index}].appID`, options.appID, row.appID));
    }
    if (row.ok !== true) {
      issues.push(issue(`$[${index}].ok`, true, row.ok));
    }
  }
  if (!sameArray(details.sentOps, ["init", "add-query"])) {
    issues.push(issue("$.details.sentOps", ["init", "add-query"], details.sentOps));
  }
  if (receivedOps[0] !== "init-ok") {
    issues.push(issue("$.details.receivedOps[0]", "init-ok", receivedOps[0]));
  }
  if (!["add-query-ok", "add-query-exists", "refresh-ok"].includes(receivedOps[1])) {
    issues.push(
      issue(
        "$.details.receivedOps[1]",
        "add-query-ok|add-query-exists|refresh-ok",
        receivedOps[1],
      ),
    );
  }
  const expectedFinalEvent = finalEventByReceivedOp[receivedOps[1]];
  if (expectedFinalEvent && actualEvents[4] !== expectedFinalEvent) {
    issues.push(issue("$.events[4]", expectedFinalEvent, actualEvents[4]));
  }
  if (
    details.proofLevel !== "local-protocol"
      && details.proofLevel !== "live-websocket-session"
  ) {
    issues.push(
      issue(
        "$.details.proofLevel",
        "local-protocol|live-websocket-session",
        details.proofLevel,
      ),
    );
  }
  if (details.remoteBoundary !== "pending-cross-client-sync") {
    issues.push(
      issue("$.details.remoteBoundary", "pending-cross-client-sync", details.remoteBoundary),
    );
  }
  if (!String(details.websocketURL ?? "").includes(`app_id=${options.appID}`)) {
    issues.push(
      issue("$.details.websocketURL", `URL containing app_id=${options.appID}`, details.websocketURL),
    );
  }

  const ok = issues.length === 0;
  emit({
    case: "validation.typescript.live-session-contract",
    event: "swift-live-session-contract",
    appID: options.appID,
    ok,
    details: {
      path,
      proofLevel: "contract-only",
      remoteBoundary: "pending-cross-client-sync",
      expectedEvents,
      actualEvents,
      sentOps: details.sentOps ?? [],
      receivedOps,
      swiftProofLevel: details.proofLevel,
      websocketURI: redactedEndpoint(details.websocketURL ?? options.websocketURI),
      issues,
    },
  });

  if (!ok) {
    process.exitCode = 1;
  }
}

function verifySwiftLiveTransactionContract(options) {
  const path = options.swiftLiveTransactionContractPath;
  if (!path || !existsSync(path)) {
    emit({
      case: "validation.typescript.live-transaction-contract",
      event: "swift-live-transaction-contract",
      appID: options.appID,
      ok: false,
      details: {
        path,
        proofLevel: "contract-only",
        remoteBoundary: "pending-cross-client-sync",
        issues: [issue("$.path", "existing Swift live-transaction JSONL artifact", path)],
      },
    });
    process.exitCode = 1;
    return;
  }

  let rows;
  try {
    rows = readJSONLines(path);
  } catch (error) {
    emit({
      case: "validation.typescript.live-transaction-contract",
      event: "swift-live-transaction-contract",
      appID: options.appID,
      ok: false,
      details: {
        path,
        proofLevel: "contract-only",
        remoteBoundary: "pending-cross-client-sync",
        issues: [issue("$.jsonl", "valid Swift live-transaction JSONL", String(error))],
      },
    });
    process.exitCode = 1;
    return;
  }

  const actualEvents = rows.map((row) => row.event);
  const finalRow = rows[rows.length - 1];
  const details = finalRow?.details ?? {};
  const receivedOps = Array.isArray(details.receivedOps) ? details.receivedOps : [];
  const finalEventByReceivedOp = {
    "add-query-ok": "receive-query",
    "add-query-exists": "receive-query",
    "refresh-ok": "receive-refresh",
  };
  const expectedEvents = [
    "session-url",
    "send-init",
    "receive-init-ok",
    "send-add-query",
    finalEventByReceivedOp[receivedOps[1]] ?? "receive-query|receive-refresh",
    "send-transact",
    "receive-transact-ok",
    "receive-transaction-refresh",
  ];
  const issues = [];

  if (
    actualEvents.length !== 8
      || !sameArray(actualEvents.slice(0, 4), expectedEvents.slice(0, 4))
      || !["receive-query", "receive-refresh"].includes(actualEvents[4])
      || !sameArray(actualEvents.slice(5), expectedEvents.slice(5))
  ) {
    issues.push(issue("$.events", expectedEvents, actualEvents));
  }
  for (const [index, row] of rows.entries()) {
    if (row.case !== "validation.live.transaction") {
      issues.push(issue(`$[${index}].case`, "validation.live.transaction", row.case));
    }
    if (row.side !== "swift") {
      issues.push(issue(`$[${index}].side`, "swift", row.side));
    }
    if (row.appID !== options.appID) {
      issues.push(issue(`$[${index}].appID`, options.appID, row.appID));
    }
    if (row.ok !== true) {
      issues.push(issue(`$[${index}].ok`, true, row.ok));
    }
  }
  if (!sameArray(details.sentOps, ["init", "add-query", "transact"])) {
    issues.push(issue("$.details.sentOps", ["init", "add-query", "transact"], details.sentOps));
  }
  if (receivedOps[0] !== "init-ok") {
    issues.push(issue("$.details.receivedOps[0]", "init-ok", receivedOps[0]));
  }
  if (!["add-query-ok", "add-query-exists", "refresh-ok"].includes(receivedOps[1])) {
    issues.push(
      issue(
        "$.details.receivedOps[1]",
        "add-query-ok|add-query-exists|refresh-ok",
        receivedOps[1],
      ),
    );
  }
  if (!receivedOps.slice(2).includes("transact-ok")) {
    issues.push(issue("$.details.receivedOps[2...]", "transact-ok", receivedOps.slice(2)));
  }
  if (!receivedOps.slice(2).includes("refresh-ok")) {
    issues.push(issue("$.details.receivedOps[2...]", "refresh-ok", receivedOps.slice(2)));
  }
  const expectedFinalQueryEvent = finalEventByReceivedOp[receivedOps[1]];
  if (expectedFinalQueryEvent && actualEvents[4] !== expectedFinalQueryEvent) {
    issues.push(issue("$.events[4]", expectedFinalQueryEvent, actualEvents[4]));
  }
  if (
    details.proofLevel !== "local-protocol"
      && details.proofLevel !== "live-websocket-transaction"
  ) {
    issues.push(
      issue(
        "$.details.proofLevel",
        "local-protocol|live-websocket-transaction",
        details.proofLevel,
      ),
    );
  }
  if (details.remoteBoundary !== "pending-cross-client-sync") {
    issues.push(
      issue("$.details.remoteBoundary", "pending-cross-client-sync", details.remoteBoundary),
    );
  }
  if (!String(details.websocketURL ?? "").includes(`app_id=${options.appID}`)) {
    issues.push(
      issue("$.details.websocketURL", `URL containing app_id=${options.appID}`, details.websocketURL),
    );
  }
  if (!details.transactionID) {
    issues.push(issue("$.details.transactionID", "non-empty transaction id", details.transactionID));
  }
  if (!details.transactionISN) {
    issues.push(issue("$.details.transactionISN", "non-empty transaction isn", details.transactionISN));
  }
  if (details.processedTransactionID !== details.transactionID) {
    issues.push(
      issue(
        "$.details.processedTransactionID",
        details.transactionID,
        details.processedTransactionID,
      ),
    );
  }

  const ok = issues.length === 0;
  emit({
    case: "validation.typescript.live-transaction-contract",
    event: "swift-live-transaction-contract",
    appID: options.appID,
    ok,
    details: {
      path,
      proofLevel: "contract-only",
      remoteBoundary: "pending-cross-client-sync",
      expectedEvents,
      actualEvents,
      sentOps: details.sentOps ?? [],
      receivedOps,
      transactionID: details.transactionID ?? null,
      processedTransactionID: details.processedTransactionID ?? null,
      transactionISN: details.transactionISN ?? null,
      swiftProofLevel: details.proofLevel,
      websocketURI: redactedEndpoint(details.websocketURL ?? options.websocketURI),
      issues,
    },
  });

  if (!ok) {
    process.exitCode = 1;
  }
}

function typeScriptServerTransactionContract(appID) {
  const transactionID = "validation.typescript.server.tx";
  const entityID = "validation-typescript-server";
  const text = "TypeScript-authored server transaction";
  const createdAtMs = 4_100_002_000_003;
  return {
    case: "validation.typescript.server.transaction.contract",
    event: "typescript-server-transaction-contract",
    appID,
    transactionID,
    processedTransactionID: "validation.typescript.server.processed",
    entityID,
    text,
    createdAtMs,
    operations: [
      {
        type: "requireEntityMissing",
        entityID,
        namespace: "todos",
      },
      {
        type: "insert",
        entityID,
        attributeID: "todos/id",
        value: { type: "string", string: entityID },
        txTimeMs: createdAtMs,
      },
      {
        type: "insert",
        entityID,
        attributeID: "todos/text",
        value: { type: "string", string: text },
        txTimeMs: createdAtMs,
      },
      {
        type: "insert",
        entityID,
        attributeID: "todos/isCompleted",
        value: { type: "bool", bool: false },
        txTimeMs: createdAtMs,
      },
      {
        type: "insert",
        entityID,
        attributeID: "todos/createdAt",
        value: { type: "date", dateMs: createdAtMs },
        txTimeMs: createdAtMs,
      },
    ],
  };
}

function writeTypeScriptServerTransactionContract(options) {
  const path = options.typeScriptServerTransactionContractPath;
  if (!path) {
    emit({
      case: "validation.typescript.server.transaction.contract",
      event: "typescript-server-transaction-contract",
      appID: options.appID,
      ok: false,
      details: {
        path,
        proofLevel: "contract-only",
        remoteBoundary: "pending",
        issues: [issue("$.path", "output path", path)],
      },
    });
    process.exitCode = 1;
    return;
  }

  const contract = typeScriptServerTransactionContract(options.appID);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(contract, null, 2)}\n`, "utf8");
  emit({
    case: contract.case,
    event: contract.event,
    appID: options.appID,
    ok: true,
    details: {
      path,
      proofLevel: "contract-only",
      remoteBoundary: "pending",
      transactionID: contract.transactionID,
      processedTransactionID: contract.processedTransactionID,
      entityID: contract.entityID,
      createdAtMs: contract.createdAtMs,
      operationCount: contract.operations.length,
    },
  });
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

  const schemaValidation = validationDetails(schemaFixture(schemaText), expectedSchema);
  emit({
    case: "validation.typescript.fixtures",
    event: "schema-fixture",
    appID: options.appID,
    ok: schemaValidation.ok,
    details: {
      path: schemaPath,
      entityNames: Object.keys(schemaValidation.actual.entities ?? {}),
      linkNames: Object.keys(schemaValidation.actual.links ?? {}),
      roomNames: Object.keys(schemaValidation.actual.rooms ?? {}),
      expected: schemaValidation.expected,
      actual: schemaValidation.actual,
      issues: schemaValidation.issues,
    },
  });

  const permissionsValidation = validationDetails(permissions(permsText), expectedPermissions);
  emit({
    case: "validation.typescript.fixtures",
    event: "permissions-fixture",
    appID: options.appID,
    ok: permissionsValidation.ok,
    details: {
      path: permsPath,
      namespaces: Object.keys(permissionsValidation.actual.namespaces ?? {}),
      expected: permissionsValidation.expected,
      actual: permissionsValidation.actual,
      issues: permissionsValidation.issues,
    },
  });

  if (!schemaValidation.ok || !permissionsValidation.ok) {
    process.exitCode = 1;
    return;
  }
}

class UsageError extends Error {
  constructor(message, exitCode = 64) {
    super(message);
    this.exitCode = exitCode;
  }
}

try {
  const options = parseArguments(process.argv.slice(2));
  switch (options.mode) {
    case "boundary-preflight":
      verifyBoundaryPreflight(options);
      break;

    case "swift-transport-contract":
      verifySwiftTransportContract(options);
      break;

    case "swift-local-integrations-contract":
      verifySwiftLocalIntegrationsContract(options);
      break;

    case "swift-live-session-contract":
      verifySwiftLiveSessionContract(options);
      break;

    case "swift-live-transaction-contract":
      verifySwiftLiveTransactionContract(options);
      break;

    case "typescript-server-transaction-contract":
      writeTypeScriptServerTransactionContract(options);
      break;

    default:
      verifyFixtures(options);
      break;
  }
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
