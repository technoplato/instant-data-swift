# Plan 2026-10-27-toolbox-1244-footguns: a footgun ledger, each entry held by a guard test

- planId: 2026-10-27-toolbox-1244-footguns
- agentId: claude-code/toolbox-1244@strangelearning
- role: grower (ordered on the consuming app's #1244: meticulous notes on the library's footguns, and optimized queries)
- issues: #1244, #1214

## Why

The consuming app has paid for the same classes of mistakes more than once: refreshes that restate whole results
(#1117, #1239), a live query that holds a row being written, the operation gate held for whole results (#1128, #1129),
outbox b-tree rewrites (#1115), temp-file staging (#1119), whole-result JSON rewrites (#1123), upload copies left after a
container move (#1227), connections pinned to an expensive route (#1237). Each was found by measurement after it cost
energy, disk or time. A single page that names each one, its measured cost, the rule that avoids it and the test that
keeps it fixed lets the next consumer and the next change avoid it before it ships.

## Design

1. docs/FOOTGUNS.md: one entry per footgun, grouped (queries and live results, writes and the outbox, storage and files,
   network, concurrency and gates, observation and memory, tooling). Each entry: symptom, measured cost (with the
   conditions), the rule, the issue, the guard test (file and test name). Neutral wording only.
2. A footgun without a guard gets one: red first (the test fails on the code before the fix, or the guard is shown to
   catch a reintroduction), then green. Guards prefer counters the library already exposes (InstantWireMeter,
   InstantStorageWriteMeter, query/statement counts) over timings.
3. Upstream parity is unchanged: the page documents behavior; any fix that a guard exposes gets its own issue and plan.

## Steps

1. This plan and its claims (plan-only commit on main).
2. Mine the sources (issues naming the library, docs/audits, CHANGELOG, commits, the consuming app's audits).
3. Write FOOTGUNS.md; map each entry to an existing guard test or mark it missing.
4. Missing guards: red, then green, focused suites through the shared heavy queue.
5. CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md.

## Touching

docs/FOOTGUNS.md (new), Tests/InstantSwiftDataCoreTests/FootgunGuardTests.swift (new; other test files only by an
amendment to this plan), README.md (one link to the page), CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md.

## Conflict check

No open claim names docs/FOOTGUNS.md or the new test file. README.md, CHANGELOG.md, PROGRESS.md and the commit ledger
take single entries.
