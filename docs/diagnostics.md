# Runtime diagnostics

Instant Swift Data has a structured, append-only JSON Lines diagnostic log for
debugging app lifecycle, UI focus, auth, queries, mutations, persistence, sync,
and transport behavior across process boundaries.

## Reminders macOS app

The `reminders-v3` executable enables trace-level logging automatically at:

```text
~/Library/Logs/InstantSwiftData/reminders-v3.jsonl
```

Multiple app instances safely append to the same file. Every row carries a
session ID, process ID, monotonically increasing per-process sequence, timestamp,
thread context, source location, severity, subsystem, category, event name,
correlation ID, and bounded metadata.

Follow the log while reproducing a problem:

```bash
tail -f ~/Library/Logs/InstantSwiftData/reminders-v3.jsonl | jq -R 'fromjson?'
```

Show focus and typed-field delivery events for the most recent processes:

```bash
jq -s '
  map(select(.category == "focus" or .category == "input"))
  | sort_by(.timestampMilliseconds, .sequence)
' ~/Library/Logs/InstantSwiftData/reminders-v3.jsonl
```

Show failures and the events immediately around them:

```bash
jq -s '
  sort_by(.timestampMilliseconds, .sequence)
  | map(select(.level == "error" or .level == "critical"))
' ~/Library/Logs/InstantSwiftData/reminders-v3.jsonl
```

For the focus problem specifically, compare these events:

- `application.became-active` and `application.resigned-active`
- `window.became-key`, `window.resigned-key`, and `window.updated`
- `lists-screen.focus-changed` or `list-screen.focus-changed`
- `new-list.input-changed` or `new-reminder.input-changed`

Input events record only old and new character counts. They never record typed
text.

## Reminders iOS Simulator app

The iOS app writes the same `reminders-v3.jsonl` stream inside its app sandbox:

```text
Library/Logs/InstantSwiftData/reminders-v3.jsonl
```

Resolve and follow that file from the Mac without guessing the changing
container UUID:

```bash
DEVICE_ID="$(xcrun simctl list devices booted -j \
  | jq -r '.devices[][] | select(.state == "Booted") | .udid' \
  | head -n 1)"
CONTAINER="$(xcrun simctl get_app_container "$DEVICE_ID" \
  com.technoplato.InstantSwiftData.RemindersV3iOS data)"
tail -f "$CONTAINER/Library/Logs/InstantSwiftData/reminders-v3.jsonl" \
  | jq -R 'fromjson?'
```

The app defaults to its local cache when `INSTANT_APP_ID` is absent. To launch
the Simulator app against a live Instant app from the command line, pass the
variable through `simctl`:

```bash
SIMCTL_CHILD_INSTANT_APP_ID="$INSTANT_APP_ID" \
  xcrun simctl launch --terminate-running-process "$DEVICE_ID" \
  com.technoplato.InstantSwiftData.RemindersV3iOS
```

## Library and CLI configuration

Logging is disabled by default for library consumers and test processes. Enable
it without changing code:

```bash
export INSTANT_SWIFT_DATA_LOG_PATH="$PWD/instant-swift-data.jsonl"
export INSTANT_SWIFT_DATA_LOG_LEVEL=trace
```

Supported levels are `trace`, `debug`, `info`, `notice`, `warning`, `error`, and
`critical`. Set `INSTANT_SWIFT_DATA_LOG_PATH=off` to disable environment-driven
logging.

An app can configure the shared logger directly:

```swift
InstantDiagnostics.shared.configure(
  InstantDiagnosticsConfiguration(
    fileURL: diagnosticURL,
    minimumLevel: .debug
  )
)
```

Set `REMINDERS_V3_LOG_PATH` to override only the Reminders executable's path.

## Host dual-write (Scribe Tailnet)

`InstantDiagnostics.addHandler` lets a host app forward every emitted entry into its
own collector. Scribe uses this at Instant bootstrap to dual-write library events
onto the same Tailscale WebSocket lane that ends in
`~/Library/Logs/Scribe/diagnostics.jsonl` (and the Instant `debugLogs` backup).
If the collector is unreachable, enqueue fails soft — product code never blocks.

Filter library rows in the collector file:

```bash
jq -c 'select(.entry.category|startswith("instant-library."))' \
  ~/Library/Logs/Scribe/diagnostics.jsonl
```

Infinite-query paging decisions (the Scribe iPad Jetsam class) use category
`infinite-query` / host category `instant-library.infinite-query` and events such as:

- `infinite.subscribe.started` — auth fingerprint + page size
- `infinite.starter.snapshot` — local window count, `hasMoreSource`, raw remote `hasNextPage`
- `infinite.expand.snapshot` — pre-kickstart local expand growth / close
- `infinite.kickstart` — full page + liveTuple switch to cursor paging
- `infinite.load-next.noop-closed` / `noop-cannot-advance` — thrash no-ops
- `infinite.remote-page-info.decoded` — server page-info as received

## Coverage

The log records these boundaries:

- app process, scene, activation, key window, first responder, and SwiftUI field focus;
- guest sign-in request, remote verification, auth-session persistence, and failure;
- `@FetchAll` and `@FetchOne` subscription start, emissions, cancellation, and failure;
- query encoding, local materialization, live registration, unregistration, and result count;
- live infinite-query starter/expand/kickstart/loadNextPage decisions and remote page-info;
- typed-message preparation, optimistic commit, outbox lifecycle, server acceptance, and rejection;
- SQLite open, schema bootstrap, state revision/count loads, and snapshot saves;
- connection, reconnect, decoded server events, WebSocket operations, frame sizes, and failures.

Payload bodies, query values, typed text, refresh tokens, ID tokens, OAuth codes,
cookies, passwords, secrets, and share tokens are not logged. Known sensitive
metadata keys are redacted, and the log file is created with mode `0600`.

Logging is synchronous and calls `fsync` after every row so the last event is
available after a crash. Trace logging therefore has deliberate diagnostic
overhead and should be disabled or raised to `warning` for production use.
