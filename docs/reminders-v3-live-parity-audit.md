# Reminders V3 live parity audit

Status: current working tree, audited and exercised on July 21, 2026.

The Instant-backed Reminders app has behavioral parity with every named test in
the pinned SQLiteData Reminders example. Its data graph, auth, local persistence,
optimistic mutation, live subscriptions, and v3 sharing use InstantDB rather
than CloudKit. The SwiftUI app is intentionally not a pixel-for-pixel copy of
the reference app; the exact remaining UI and search differences are listed
below.

The separately named `cloudkit-demo-v3` validation product keeps the name of
the upstream sharing scenario only. Its port pushes an InstantDB schema and
permissions and performs its live reads and writes through InstantDB. The
Reminders app and validation gates do not use a CloudKit container,
`CKDatabase`, or `CKSyncEngine` to synchronize data.

## Pinned references

- Instant TypeScript SDK: `upstream/instant` at
  `e71017612aed4031710a35e2fcace30d38d557ac`.
- SQLiteData: `upstream/sqlite-data` at
  `0c79d7a5748fc6d9ce7a1ba2b50f31b175305049`.
- Historical Swift references: `upstream/sharing-instant` at `d78601a` and
  `upstream/instant-ios-sdk` at `304677c`. These two submodules are pinned but
  intentionally not initialized in this checkout.
- Submodule map and transfer notes: `upstream/README.md`.

The most important upstream implementation references are:

- `upstream/instant/client/packages/core/src/Reactor.js:1152` for `queryOnce`:
  register a real remote query, resolve it from server data, then remove it when
  no listener remains.
- `upstream/instant/client/packages/core/src/Reactor.js:2284` for magic-code
  login and guest upgrade, including forwarding the current guest refresh token.
- `upstream/instant/client/packages/core/src/Reactor.js:2309` for guest login.
- `upstream/instant/client/packages/core/src/Reactor.js:2318` for best-effort
  remote token invalidation followed by local sign-out.
- `upstream/instant/client/packages/core/src/Reactor.js:2381` for OAuth/code
  exchange while preserving guest identity.
- `upstream/instant/client/packages/core/src/index.ts:347` for the public auth
  surface.
- `upstream/sqlite-data/Examples/Reminders/RemindersLists.swift`,
  `RemindersDetail.swift`, `ReminderForm.swift`, `SearchReminders.swift`, and
  `RemindersListForm.swift` for the app behavior and presentation reference.
- `upstream/sqlite-data/Examples/RemindersTests` for the acceptance contract.

## Strategy alignment

| Concern | Upstream strategy | Swift implementation |
| --- | --- | --- |
| One-shot remote query | Start a server query and explicitly remove it after resolution | `InstantLiveTransport.queryOnce` uses add-query, waits for server data, and removes the query; it does not substitute an HTTP admin query |
| Live reads | Keep a registered query and react to server refreshes | `@FetchAll`/`@FetchOne` own subscription lifetime and re-materialize linked graphs after refresh |
| Optimistic writes | Apply locally, enqueue, send, then accept or roll back | `InstantRuntime` and `InstantStore` persist typed pending mutations and reconcile server acceptance/rejection |
| Offline durability | Keep local triples and pending work across process restarts | SQLite persistence stores graph state, auth, and outbox state; reconnect flushes pending work |
| Guest upgrade | Pass the guest refresh token into the next login method | Guest, magic-code, token, ID-token, and OAuth exchange preserve the existing guest user where Instant supports upgrade |
| Sign-out | Remote invalidation is best effort; local session still clears | The Swift auth client records invalidation failure but clears local auth state |
| Sharing | Protect a shared root with explicit memberships and roles | The Reminders schema uses v3 shares and memberships with owner, reader, and writer permissions |
| Relationships | Query and mutate the linked graph, not flattened copies | Lists include reminders; reminders include tags; shares include memberships; typed messages preserve refs and cascades |

## Upstream Reminders tests ported

Every test named by the pinned SQLiteData example has a Swift counterpart:

| Upstream suite | Cases | Swift evidence |
| --- | --- | --- |
| `RemindersListsTests` | basics, move, share | `Tests/RemindersV3AppTests/RemindersV3AppTests.swift`, `RemindersV3SharingTests.swift`, and list/reorder message tests |
| `RemindersDetailsTests` | basics, ordering, showCompleted, move, all, completed, flagged, scheduled, today, tagged | `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` tests explicitly named for the upstream cases, plus `RemindersV3PresentationTests.swift` |
| `SearchRemindersTests` | basics, showCompleted, deleteCompleted | `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` tests explicitly named for the upstream cases |

The Swift port additionally tests linked tag suggestions, exact tag tokens,
near-token behavior, aged completed deletion, error-state row retention, rich
form replacement, stats predicates, typed list edits, and atomic list/reminder
reordering.

## User-visible functionality present

- The app exposes guest login, magic-code login, in-place guest-to-email
  upgrade, sign-out, and durable session restoration. Token, ID-token, and OAuth
  modes are available through the shared auth client and CLI surfaces rather
  than fields in the Reminders account sheet.
- List creation, rename, preset color, deletion, and manual reordering.
- Reminder creation, editing, deletion, completion, manual reordering, and moving
  between lists.
- Notes, due date, low/medium/high priority, flag, and many linked tags.
- Live All, Today, Scheduled, Flagged, Completed, and tag collections.
- All/incomplete/completed counts and the incomplete-only semantics for Today,
  Scheduled, and Flagged.
- Due-date, manual, priority, and title ordering; show/hide completed.
- Case-insensitive title/notes/tag search and exact `#tag` search.
- Instant v3 share creation, role grant/change, and revoke with owner, reader,
  writer, and outsider boundaries.
- Local-first persistence, optimistic writes, reconnect/outbox support, and
  structured diagnostics from app, wrappers, store, persistence, auth, and live
  transport.

## Actual app-binary evidence

This was exercised through the rendered SwiftUI apps, not only through unit
tests:

- Two separate macOS app processes used independent SQLite files and the same
  live Instant app. Both accepted real keyboard input. A reminder created on one
  Mac, with notes, date, high priority, flag, and linked tags, appeared on the
  second Mac. Editing it on the second Mac updated the first in real time.
- The macOS smart-list counts updated live, search returned the linked remote
  reminder, and distinct Today/Scheduled/All/Flagged/Completed navigation rows
  opened only the selected query.
- A real guest account created data, requested a real magic code, and upgraded
  through the emailed code while retaining the same Instant user id and list.
- A Mac binary was launched against a deliberately unreachable local endpoint,
  created a rich reminder optimistically, exited with one pending outbox item,
  and relaunched online against the same SQLite file. The pending transaction
  was accepted and appeared in the second running Mac binary. This found and
  fixed a reconnect-state bug that had incorrectly persisted automatic failure
  as an explicit user close.
- A second, fresh guest account joined the owner's v3 share. Reader writes were
  rejected and rolled back; promotion to writer was delivered live and the
  writer's accepted reminder appeared in the owner's running app. The rebuilt
  UI now disables reader mutation controls, hides owner-only sharing controls,
  and enables writer controls immediately when the linked role changes.
- The final iOS Simulator build read that same linked reminder. Its form showed
  the title, notes, tags, date, and priority. Completing it on iOS removed it
  from the Mac's live Flagged view; restoring it from iOS updated the Mac again.
- The final permission-audit logs contained 181 rows/55 event kinds for the
  owner Mac and 151 rows/55 event kinds for the collaborator Mac. The current
  rebuilt iOS process emitted 52 rows/36 event kinds, including a live
  collection result. All three contained zero warning, error, or critical rows.
- The retained-credential cross-SDK contract was run twice consecutively
  against the same InstantDB app. Each run used unique graph IDs, share token,
  and globally unique tag titles; both proved Swift-to-TypeScript and
  TypeScript-to-Swift live observation, reader rejection, writer acceptance,
  and outsider invisibility with zero warnings or pending mutations.
- The dedicated `reminders-v3-cli` created a scheduled, flagged, prioritized,
  tagged reminder through the same InstantDB app. The running macOS app and the
  iOS Simulator both rendered it without a relaunch. The CLI cache was then
  copied to a separate mode-`0600` SQLite file and used as an isolated third
  client to update the title, notes, due date, priority, and linked tags. Both
  apps received the update through their live WebSocket subscriptions; the iOS
  edit form displayed the CLI-authored title, notes, and tags. CLI, macOS, and
  iOS diagnostic logs contained zero warning, error, or critical rows for the
  proof window.

The durable getadb.com credentials used for this prototype are outside the
repository at:

```text
~/Sync/private/credentials/swift-instant-data/reminders-v3.env
```

The file is mode `0600`. Logs redact auth tokens, magic codes, share tokens,
query values, and typed text.

## Exact remaining reference differences

These are the things that are still different from the SQLiteData example:

1. The reference list editor has a cover photo/PhotosPicker. The Instant
   Reminders schema and app do not have a list-cover asset.
2. The reference uses an arbitrary `ColorPicker`; this app offers five stable
   preset list colors.
3. The app search is case-insensitive substring search plus exact `#tag` search.
   The core model tests token, near, highlight, and aged-delete behavior, but the
   SwiftUI app does not reproduce SQLite FTS ranking, snippets, or its token UI.
4. The reference search UI can clear completed reminders older than 1, 6, or 12
   months. The core model implements and tests aged deletion, but that age menu
   is not exposed in this SwiftUI app.
5. Tags are created and selected in the reminder form. There is no separate UI
   for deleting a tag entity globally.
6. The CloudKit `CKShare` sheet and its platform cover image are deliberately
   replaced by Instant v3 share memberships and roles. The sharing behavior is
   present; its platform UI is adapted.

Items 1-6 are exact reference-UI differences, not broken InstantDB sync. The
previous offline/reconnect and distinct-user sharing evidence gaps are closed by
the actual-binary runs above.

## Run the live apps

Load the durable prototype app id without printing its secrets:

```bash
set -a
source "$HOME/Sync/private/credentials/swift-instant-data/reminders-v3.env"
set +a
```

Run a macOS instance with an explicit cache and log:

```bash
INSTANT_PERSISTENCE_PATH=/tmp/reminders-a.sqlite \
REMINDERS_V3_LOG_PATH=/tmp/reminders-a.jsonl \
swift run reminders-v3
```

Run a second terminal with different `INSTANT_PERSISTENCE_PATH` and
`REMINDERS_V3_LOG_PATH` values for a genuinely separate client.

Drive the running apps from the terminal with the dedicated CLI:

```bash
INSTANT_PERSISTENCE_PATH=/tmp/reminders-cli.sqlite \
swift run reminders-v3-cli --json auth guest

# Grant the reported CLI user writer access to the list in the owner app, then:
INSTANT_PERSISTENCE_PATH=/tmp/reminders-cli.sqlite \
swift run reminders-v3-cli --json reminders add <list-id> "CLI reminder" \
  --notes "Observed live by macOS and iOS" \
  --due-date 2026-07-23 --priority high --flagged --tag cli
```

Using the same authenticated persistence path as an existing app instance uses
that app user's session. Using a different path creates a fully isolated CLI
client; sign it in and grant it the appropriate Instant v3 share role first.
The CLI supports live `lists list --watch` and `reminders list --watch` readers
as well as add, update, complete, reopen, delete, tag, sharing, and sync verbs.

Build all three simulator apps:

```bash
cd Examples/RemindersV3
xcodegen generate
./build-all-simulators.sh
```

The helper builds `RemindersV3iOS`, `RemindersV3tvOS`, and
`RemindersV3watchOS` into `/tmp/reminders-v3-simulators/Build/Products`. It
contains a DerivedData-only workaround for an Xcode 26.6 local SwiftPM
macro-product selection defect. It builds the current host macro tool and never
modifies source or the app bundle to apply the workaround.

For normal use, install each app and launch it with only `INSTANT_APP_ID`, then
sign into the same email account through the UI on iPhone, Apple TV, and Apple
Watch. Owned and shared lists follow that authenticated Instant user; no
separate sharing step is needed between devices signed into the same account.

Open a list's `Sharing` screen to invite a different account. The owner first
selects `Set up sharing`, searches for the other account by email, and grants
either view or edit access. The owner can later update or remove that access.

Automated simulator verification can instead launch each installed app with
one injected demo identity:

```bash
launch_reminders() {
  local device="$1"
  local app="$2"
  local bundle_id="$3"
  xcrun simctl install "$device" "$app"
  SIMCTL_CHILD_INSTANT_APP_ID="$INSTANT_APP_ID" \
  SIMCTL_CHILD_REMINDERS_V3_USER_ID="$REMINDERS_V3_USER_ID" \
  SIMCTL_CHILD_REMINDERS_V3_REFRESH_TOKEN="$REMINDERS_V3_REFRESH_TOKEN" \
    xcrun simctl launch --terminate-running-process "$device" "$bundle_id"
}

launch_reminders "$IOS_UDID" \
  '/tmp/reminders-v3-simulators/Build/Products/Debug-iphonesimulator/Reminders V3.app' \
  com.technoplato.InstantSwiftData.RemindersV3iOS
launch_reminders "$TVOS_UDID" \
  '/tmp/reminders-v3-simulators/Build/Products/Debug-appletvsimulator/Reminders V3.app' \
  com.technoplato.InstantSwiftData.RemindersV3tvOS
launch_reminders "$WATCHOS_UDID" \
  '/tmp/reminders-v3-simulators/Build/Products/Debug-watchsimulator/Reminders V3.app' \
  com.technoplato.InstantSwiftData.RemindersV3watchOS
```

The app ID must point at a server with the current generated Reminders schema
and permissions. For the automation path, the user ID must match the
refresh-token identity on all three processes. The refresh token is accepted
only from the process environment and is deliberately not supported as an
Info.plist value.

See `docs/diagnostics.md` for log locations and focused `jq` recipes. Run the
fresh-server cross-SDK contract with:

```bash
INSTANT_GETADB_CREDENTIALS_FILE="$HOME/Sync/private/credentials/swift-instant-data/reminders-v3.env" \
validation/verify-reminders-v3-app-live.sh
```
