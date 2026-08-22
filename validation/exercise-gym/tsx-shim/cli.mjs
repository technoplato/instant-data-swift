#!/usr/bin/env node
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [script, ...args] = process.argv.slice(2);
if (!script) {
  console.error("Usage: tsx <plain-JavaScript .ts file> [arguments]");
  process.exit(64);
}
const directory = mkdtempSync(join(tmpdir(), "instant-exercise-gym-"));
const temporary = join(directory, `${basename(script).replace(/\.ts$/, "")}.mjs`);
writeFileSync(temporary, readFileSync(resolve(script), "utf8"));
process.argv = [process.argv[0], resolve(script), ...args];
try {
  await import(`${pathToFileURL(temporary).href}?run=${Date.now()}`);
} finally {
  rmSync(directory, { recursive: true, force: true });
}
