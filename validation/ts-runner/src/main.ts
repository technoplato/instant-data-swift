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
