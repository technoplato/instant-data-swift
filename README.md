# Instant Swift Data

Instant Swift Data is a Swift package for building InstantDB-backed apps with
typed schema, local persistence, optimistic writes, live observation, and
agent-friendly command-line workflows.

This repository is early, but the first local core slice is usable: todos can be
created, listed, completed, updated, deleted, and read back across separate CLI
invocations through the same SQLite cache and outbox path used by the core
runtime. Local auth, room presence, and room topic messages also persist across
CLI launches.

## Local Todo CLI Demo

Use `INSTANT_SWIFT_DATA_HOME` to keep the demo cache isolated.
The ID-capture steps use `jq` to extract IDs from JSON output.
Todo `add` uses strict create semantics, while `complete` and `update` are
strict updates: strict-create conflicts or missing update IDs exit non-zero
before any local cache or outbox write.
Local pending mutations persist typed `merge`, strict-create precondition, and
strict-update precondition steps; future transport adapters should lower these
to Instant wire operations.

```bash
export INSTANT_SWIFT_DATA_HOME="$(mktemp -d)"

swift run instant-swift-data examples todos seed --json
swift run instant-swift-data examples todos add "do the dishes"
swift run instant-swift-data examples todos list
swift run instant-swift-data examples todos list --completed false --offset 0 --limit 10 --order desc
swift run instant-swift-data examples todos list --completed false --first 2 --json
swift run instant-swift-data examples todos list --search dishes
swift run instant-swift-data query todos --completed false --json
swift run instant-swift-data query todos --completed false --select text,isCompleted --json
swift run instant-swift-data query todos --order-by none --first 1 --json
swift run instant-swift-data query todos --order-by serverCreatedAt --order desc --json
PAGE_CURSOR="$(swift run instant-swift-data query todos --completed false --first 1 --json | jq -r '.pageInfo.endCursor.entityID')"
swift run instant-swift-data query todos --completed false --first 1 --after "$PAGE_CURSOR" --json
swift run instant-swift-data examples todo-links seed --json
swift run instant-swift-data examples todo-links list --json
swift run instant-swift-data examples todo-links nested --json
swift run instant-swift-data examples todo-links unlink --json
swift run instant-swift-data examples todos watch --events 1 --jsonl
TODO_ID="$(swift run instant-swift-data examples todos add "ship the demo" --json | jq -r '.changedID')"
swift run instant-swift-data examples todos complete "$TODO_ID"
swift run instant-swift-data examples todos update "$TODO_ID" "ship the polished demo" --json
DELETE_TODO_ID="$(swift run instant-swift-data examples todos add "delete after smoke" --json | jq -r '.changedID')"
swift run instant-swift-data examples todos delete "$DELETE_TODO_ID" --json
swift run instant-swift-data examples todos refresh
swift run instant-swift-data examples todos reset --json
```

Agent-readable output is available with `--json` or `--jsonl`:

```bash
swift run instant-swift-data examples todos add "do the dishes" --json
TODO_ID="$(swift run instant-swift-data examples todos add "complete through JSONL" --json | jq -r '.changedID')"
swift run instant-swift-data examples todos complete "$TODO_ID" --jsonl
swift run instant-swift-data examples todos seed --jsonl
swift run instant-swift-data examples todos list --jsonl
swift run instant-swift-data query todos --search dishes --jsonl
swift run instant-swift-data query todos --select text,isCompleted --jsonl
swift run instant-swift-data examples todos watch --events 1 --jsonl
swift run instant-swift-data examples todos reset --jsonl
```

Run the local Instant auth recipe port:

```bash
export INSTANT_SWIFT_DATA_HOME="$(mktemp -d)"

swift run instant-swift-data examples auth status --json
MAGIC_CODE_JSON="$(swift run instant-swift-data examples auth send-code user@example.com --json)"
MAGIC_CODE="$(printf '%s' "$MAGIC_CODE_JSON" | jq -r '.localVerificationCode')"
swift run instant-swift-data examples auth verify-code user@example.com "$MAGIC_CODE" --json
swift run instant-swift-data examples auth watch --events 1 --jsonl
swift run instant-swift-data examples auth sign-out --json
```

The auth recipe mirrors the upstream magic-code flow: signed-out state shows the
login step, `send-code` persists a local verification challenge, `verify-code`
creates a durable email-backed session, `status` exposes the dashboard state,
and `sign-out` returns to the login state. Local sessions store a user id, so the
recipe output derives the dashboard email from `email:<address>` user ids.
Because the React recipe keeps the pending code-entry step in component state,
the terminal port exposes that step on the `send-code` result rather than making
plain `status` guess which pending email to show.

Run the local app-builder port:

```bash
export INSTANT_SWIFT_DATA_HOME="$(mktemp -d)"

MAGIC_CODE_JSON="$(swift run instant-swift-data examples auth send-code builder@example.com --json)"
MAGIC_CODE="$(printf '%s' "$MAGIC_CODE_JSON" | jq -r '.localVerificationCode')"
swift run instant-swift-data examples auth verify-code builder@example.com "$MAGIC_CODE" --json
BUILD_JSON="$(swift run instant-swift-data examples app-builder generate "Build a Tic Tac Toe game" --org-id local-org --json)"
BUILD_ID="$(printf '%s' "$BUILD_JSON" | jq -r '.selectedBuild.id')"
swift run instant-swift-data examples app-builder list --json
swift run instant-swift-data examples app-builder append "$BUILD_ID" --code $'\n// local edit' --reasoning $'\nPolished after preview.' --previewable false --json
swift run instant-swift-data examples app-builder finish "$BUILD_ID" --json
swift run instant-swift-data examples app-builder show "$BUILD_ID" --json
swift run instant-swift-data examples app-builder generate "Build a notes app" --jsonl
swift run instant-swift-data examples app-builder reset --json
```

The app-builder port mirrors the upstream magic-code-protected generation flow:
it creates a local platform app through `InstantPlatformAppClient.local`, writes
a linked owner/build row, streams reasoning and code through
`AppBuilderCodeGeneratorClient.local`, lists only the signed-in user's builds,
and keeps `show` as an id-only detail lookup like the website route.

Create a local Reminders list, add reminders, and prove two-user list sharing:

```bash
swift run instant-swift-data auth token owner-refresh --user-id user-1 --json
LIST_JSON="$(swift run instant-swift-data examples reminders add-list "Family" --json)"
LIST_ID="$(printf '%s' "$LIST_JSON" | jq -r '.changedID')"
DUE_DATE="$(date -u +%F)"
REMINDER_JSON="$(swift run instant-swift-data examples reminders add "$LIST_ID" "Pack lunch" --notes "Bring a cooler" --due-date "$DUE_DATE" --priority high --flagged --json)"
REMINDER_ID="$(printf '%s' "$REMINDER_JSON" | jq -r '.changedID')"
swift run instant-swift-data examples reminders add-tag "$REMINDER_ID" family --json
swift run instant-swift-data examples reminders list --scheduled --json
swift run instant-swift-data examples reminders list --today --json
swift run instant-swift-data examples reminders list --flagged --priority high --json
swift run instant-swift-data outbox transport --json | jq '.mutations[].txSteps[] | select(.[2] == "reminders/priority")'
swift run instant-swift-data examples reminders stats --json
swift run instant-swift-data examples reminders search "Pack" --tag family --json
swift run instant-swift-data examples reminders tags --jsonl
swift run instant-swift-data examples reminders list --refresh --jsonl
SHARE_JSON="$(swift run instant-swift-data shares create remindersLists "$LIST_ID" --json)"
SHARE_ID="$(printf '%s' "$SHARE_JSON" | jq -r '.shares[0].share.id')"
SHARE_TOKEN="$(printf '%s' "$SHARE_JSON" | jq -r '.shares[0].share.token')"
swift run instant-swift-data auth token invitee-refresh --user-id user-2 --json
swift run instant-swift-data shares accept "$SHARE_TOKEN" --json
swift run instant-swift-data examples reminders update "$REMINDER_ID" "reader edit" --json || test "$?" -eq 77
swift run instant-swift-data examples reminders add-tag "$REMINDER_ID" reader --json || test "$?" -eq 77
swift run instant-swift-data auth token owner-refresh --user-id user-1 --json
swift run instant-swift-data shares role "$SHARE_ID" user-2 writer --json
swift run instant-swift-data auth token invitee-refresh --user-id user-2 --json
swift run instant-swift-data examples reminders update "$REMINDER_ID" "writer edit" --notes "Done by the writer" --clear-due-date --clear-priority --unflagged --json
swift run instant-swift-data examples reminders complete "$REMINDER_ID" --json
swift run instant-swift-data examples reminders search "writer" --include-completed --json
swift run instant-swift-data examples reminders delete-completed --list-id "$LIST_ID" --json
swift run instant-swift-data auth token owner-refresh --user-id user-1 --json
swift run instant-swift-data shares role "$SHARE_ID" user-2 reader --json
swift run instant-swift-data auth token invitee-refresh --user-id user-2 --json
swift run instant-swift-data examples reminders rename-list "$LIST_ID" "reader list" --json || test "$?" -eq 77
swift run instant-swift-data examples reminders delete-list "$LIST_ID" --json || test "$?" -eq 77
```

Create and edit a local SyncUps meeting, record a transcript, and prove parent
cascade delete:

```bash
SYNCUP_JSON="$(swift run instant-swift-data examples sync-ups add "Design" --seconds 900 --theme appOrange --attendee Blob --attendee "Blob Jr" --json)"
SYNCUP_ID="$(printf '%s' "$SYNCUP_JSON" | jq -r '.changedID')"
swift run instant-swift-data examples sync-ups detail "$SYNCUP_ID" --json
ATTENDEE_ID="$(swift run instant-swift-data examples sync-ups detail "$SYNCUP_ID" --json | jq -r '.attendees[] | select(.name == "Blob Jr") | .id')"
swift run instant-swift-data examples sync-ups delete-attendee "$ATTENDEE_ID" --json
swift run instant-swift-data examples sync-ups add-attendee "$SYNCUP_ID" "Blob Jr" --json
swift run instant-swift-data examples sync-ups edit "$SYNCUP_ID" --title "Design Review" --seconds 1200 --theme periwinkle --attendee Blob --json
MEETING_JSON="$(swift run instant-swift-data examples sync-ups record "$SYNCUP_ID" --transcript "Reviewed launch risks." --json)"
MEETING_ID="$(printf '%s' "$MEETING_JSON" | jq -r '.changedID')"
swift run instant-swift-data examples sync-ups delete-meeting "$MEETING_ID" --json
swift run instant-swift-data examples sync-ups record "$SYNCUP_ID" --transcript "Final launch notes." --json
swift run instant-swift-data examples sync-ups record-demo "$SYNCUP_ID" --json
swift run instant-swift-data examples sync-ups list --jsonl
swift run instant-swift-data examples sync-ups delete "$SYNCUP_ID" --json
```

`record-demo` fast-forwards the local SyncUps recording model through the
deterministic `.local` speech and sound clients, saves the transcript as a
meeting, and prints recording diagnostics alongside the normal SyncUps snapshot.

Run the local Instant website-style chat demo:

```bash
swift run instant-swift-data examples chat seed --json
GENERAL_CHANNEL_ID="$(swift run instant-swift-data examples chat channels --json | jq -r '.channels[] | select(.title == "general") | .id')"
swift run instant-swift-data examples chat post "$GENERAL_CHANNEL_ID" "Hello from the guest CLI" --author "Guest CLI" --json
swift run instant-swift-data auth token local-chat-refresh --user-id user-1 --json
swift run instant-swift-data examples chat post "$GENERAL_CHANNEL_ID" "Hello from a logged-in user" --json
swift run instant-swift-data examples chat messages "$GENERAL_CHANNEL_ID" --jsonl
swift run instant-swift-data examples chat reset --json
```

Run the local Instant website-style microblog demo:

```bash
export INSTANT_SWIFT_DATA_HOME="$(mktemp -d)"
swift run instant-swift-data examples microblog seed --json
SEED_POST_ID="$(swift run instant-swift-data examples microblog feed --json | jq -r '.feed[0].post.id')"
swift run instant-swift-data examples microblog feed --jsonl
swift run instant-swift-data auth token microblog-refresh --user-id user-1 --json
swift run instant-swift-data examples microblog setup-profile "CLI User" cli-user --json
POST_ID="$(swift run instant-swift-data examples microblog post "Hello from the CLI microblog" --color bg-green-100 --json | jq -r '.changedID')"
swift run instant-swift-data examples microblog like "$SEED_POST_ID" --json
swift run instant-swift-data examples microblog unlike "$SEED_POST_ID" --json
swift run instant-swift-data examples microblog delete-post "$POST_ID" --json
swift run instant-swift-data examples microblog reset --json
```

Run the local Instant mobile chat demo:

```bash
export INSTANT_SWIFT_DATA_HOME="$(mktemp -d)"
swift run instant-swift-data examples mobile-chat seed --json
CHANNEL_ID="$(swift run instant-swift-data examples mobile-chat channels --json | jq -r '.channels[] | select(.name == "general") | .id')"
swift run instant-swift-data auth guest --json
swift run instant-swift-data examples mobile-chat setup-profile "Guest CLI" --json
swift run instant-swift-data examples mobile-chat join "$CHANNEL_ID" --json
swift run instant-swift-data examples mobile-chat send "$CHANNEL_ID" "Hello from mobile chat" --json
swift run instant-swift-data examples mobile-chat messages "$CHANNEL_ID" --jsonl
swift run instant-swift-data examples mobile-chat presence "$CHANNEL_ID" --json
swift run instant-swift-data examples mobile-chat leave "$CHANNEL_ID" --json
swift run instant-swift-data examples mobile-chat reset --json
```

`mobile-chat reset` clears the local mobile chat channels, profiles, messages,
and presence. It leaves shared auth and `$users` system state alone so other
examples and the selected app session are not wiped unexpectedly.

Run the local Instant reactions recipe port:

```bash
export INSTANT_SWIFT_DATA_HOME="$(mktemp -d)"
swift run instant-swift-data auth token reactions-a --user-id user-a --json
swift run instant-swift-data examples reactions tap wave --direction 45 --rotation 90 --json
swift run instant-swift-data auth token reactions-b --user-id user-b --json
swift run instant-swift-data examples reactions tap heart --direction 135 --rotation 270 --json
swift run instant-swift-data examples reactions list --json
swift run instant-swift-data examples reactions watch --events 1 --jsonl
```

The reactions recipe uses the upstream `topics-example/123` room, `emoji` topic,
and `{name, directionAngle, rotationAngle}` payload. Use a fresh
`INSTANT_SWIFT_DATA_HOME` for an empty local topic history.

Run the local Instant typing indicator recipe port:

```bash
export INSTANT_SWIFT_DATA_HOME="$(mktemp -d)"
swift run instant-swift-data examples typing-indicator join user-a --json
swift run instant-swift-data examples typing-indicator type user-a --json
swift run instant-swift-data examples typing-indicator type user-b --json
swift run instant-swift-data examples typing-indicator list --json
swift run instant-swift-data examples typing-indicator list --viewer-user-id user-a --json
swift run instant-swift-data examples typing-indicator watch --events 1 --jsonl
swift run instant-swift-data examples typing-indicator stop user-a --json
swift run instant-swift-data examples typing-indicator leave user-b --json
```

The typing indicator recipe uses the upstream `typing-indicator-example/1234`
room and derives active typers from the `chat-input` presence field. Pass
`--viewer-user-id` to `list` or `watch` for the upstream hook's peer-only view.

Run the local Instant avatar stack recipe port:

```bash
export INSTANT_SWIFT_DATA_HOME="$(mktemp -d)"
swift run instant-swift-data examples avatar-stack join user-alpha --json
swift run instant-swift-data examples avatar-stack join user-beta --name Betty --json
swift run instant-swift-data examples avatar-stack list --viewer-user-id user-alpha --json
swift run instant-swift-data examples avatar-stack watch --events 1 --viewer-user-id user-alpha --jsonl
swift run instant-swift-data examples avatar-stack leave user-beta --json
```

The avatar stack recipe uses the upstream `avatars-example/avatars-example-1234`
room and `{name}` presence payload. Omit `--name` on `join` to derive the
upstream-style name from the first six characters of the user id, and pass
`--viewer-user-id` to `list` or `watch` to split the current user from peers.

Run the local Instant cursors recipe ports:

```bash
export INSTANT_SWIFT_DATA_HOME="$(mktemp -d)"
swift run instant-swift-data examples cursors move user-alpha --x 10 --y 20 --x-percent 25 --y-percent 50 --color '#123456' --json
swift run instant-swift-data examples cursors move user-beta --x 30 --y 40 --x-percent 75 --y-percent 80 --json
swift run instant-swift-data examples cursors list --viewer-user-id user-alpha --json
swift run instant-swift-data examples cursors watch --events 1 --viewer-user-id user-alpha --jsonl
swift run instant-swift-data examples cursors clear user-beta --json
swift run instant-swift-data examples custom-cursors move user-custom --x 1 --y 2 --x-percent 3 --y-percent 4 --name Ada --color '#abcdef' --json
swift run instant-swift-data examples custom-cursors list --viewer-user-id viewer --json
```

The cursors recipes use the upstream `cursors-example/123` and
`cursors-example/124` rooms and the default `<Cursors>` space key. Cursor
payloads store `{x, y, xPercent, yPercent, color}`, and custom cursors also
store the `name` presence field used by the avatar renderer. Pass
`--viewer-user-id` to `list` or `watch` for the upstream peer-only cursor view.

Run the local Instant merge tile game recipe port:

```bash
export INSTANT_SWIFT_DATA_HOME="$(mktemp -d)"
swift run instant-swift-data examples merge-tile-game board --json
swift run instant-swift-data examples merge-tile-game join user-alpha --color '#e76f51' --json
swift run instant-swift-data examples merge-tile-game join user-beta --json
swift run instant-swift-data examples merge-tile-game tap user-alpha 0 0 --json
swift run instant-swift-data examples merge-tile-game tap user-beta 0 1 --json
swift run instant-swift-data examples merge-tile-game board --viewer-user-id user-alpha --json
swift run instant-swift-data examples merge-tile-game watch --events 1 --viewer-user-id user-alpha --jsonl
swift run instant-swift-data examples merge-tile-game reset --json
swift run instant-swift-data examples merge-tile-game leave user-beta --json
```

The merge tile game uses the upstream fixed board
`83c059e2-ed47-42e5-bdd9-6de88d26c521`, a 4x4 `{state}` JSON object, the
`tile-game-example/_defaultRoomId` presence room, and the six-color palette from
the React recipe. `board` lazily creates the empty board, `reset` replaces the
full board state, and `tap` deep-merges only the selected `row-column` cell so
separate players' colors survive across invocations. Omit `--color` to choose
the first available palette color for deterministic terminal evidence; the
browser recipe randomizes among available colors.

Run the local Instant Stroopwafel multiplayer demo:

```bash
export INSTANT_SWIFT_DATA_HOME="$(mktemp -d)"
swift run instant-swift-data auth token stroop-host --user-id user-host --json
swift run instant-swift-data examples stroopwafel setup-profile Host123 --json
swift run instant-swift-data examples stroopwafel create-room AB12 --json
swift run instant-swift-data auth token stroop-guest --user-id user-guest --json
swift run instant-swift-data examples stroopwafel setup-profile Guest123 --json
swift run instant-swift-data examples stroopwafel join AB12 --json
swift run instant-swift-data examples stroopwafel ready AB12 --json
swift run instant-swift-data auth token stroop-host --user-id user-host --json
GAME_ID="$(swift run instant-swift-data examples stroopwafel start AB12 --json | jq -r '.selectedGameID')"
LABEL="$(swift run instant-swift-data examples stroopwafel game "$GAME_ID" --json | jq -r '.selectedGame.colors[0].label')"
swift run instant-swift-data auth token stroop-guest --user-id user-guest --json
swift run instant-swift-data examples stroopwafel tap "$GAME_ID" "$LABEL" --json
swift run instant-swift-data examples stroopwafel games --jsonl
swift run instant-swift-data examples stroopwafel reset --json
```

`stroopwafel reset` clears local rooms, games, and point records while preserving
shared auth and `$users` profile state.

Inspect the durable cache and optimistic outbox:

```bash
swift run instant-swift-data app select local-demo --json
swift run instant-swift-data app show --json
swift run instant-swift-data app ephemeral --title reminders-port --json
swift run instant-swift-data app show --json
swift run instant-swift-data examples todos add "scoped to the selected local app" --json
swift run instant-swift-data cache inspect --json
swift run instant-swift-data cache inspect --json | jq '.queries[] | {queryID, namespace, resultCount}'
swift run instant-swift-data cache attributes todos --json
swift run instant-swift-data cache triples todos --jsonl
swift run instant-swift-data outbox inspect --jsonl
swift run instant-swift-data outbox transport --json
swift run instant-swift-data outbox flush --limit 1 --json
MUTATION_ID="$(swift run instant-swift-data outbox inspect --json | jq -r '.mutations[0].id')"
swift run instant-swift-data outbox confirm "$MUTATION_ID" --json
FAILED_MUTATION_ID="$(swift run instant-swift-data outbox inspect --json | jq -r '.mutations[0].id')"
swift run instant-swift-data outbox fail "$FAILED_MUTATION_ID" "server rejected" --json
swift run instant-swift-data connection status --json
swift run instant-swift-data outbox transport --all --jsonl
swift run instant-swift-data outbox retry "$FAILED_MUTATION_ID" --json
swift run instant-swift-data connection status --json
swift run instant-swift-data outbox drain --local-confirm --limit 1 --json
swift run instant-swift-data outbox drain --local-confirm --jsonl
swift run instant-swift-data local-id get todos.viewer --json
swift run instant-swift-data local-id list --json
swift run instant-swift-data connection status --json
swift run instant-swift-data connection close --json
swift run instant-swift-data examples todos add "queued while closed" --json
swift run instant-swift-data query todos --json # exits non-zero while closed, with cached-query details
swift run instant-swift-data examples todos watch --events 1 --jsonl # emits cached local state while closed
swift run instant-swift-data outbox flush --json # exits non-zero while closed, pending writes stay queued
swift run instant-swift-data connection connect --json
swift run instant-swift-data outbox flush --json
swift run instant-swift-data sync inspect --json
swift run instant-swift-data sync mark-processed demo-tx-1 --json
```

Write and query arbitrary local namespaces with admin helpers:

```bash
swift run instant-swift-data admin transact notes note-1 --merge '{"title":"admin note","done":false}' --transaction-id tx-admin-note-1 --json
# Replay the same pending transaction id; the outbox still has one mutation.
swift run instant-swift-data admin transact notes note-1 --merge '{"title":"admin note","done":false}' --transaction-id tx-admin-note-1 --json
swift run instant-swift-data outbox inspect --json
swift run instant-swift-data admin query notes --json
swift run instant-swift-data admin query notes --jsonl
```

Persist local CLI auth/session state:

```bash
swift run instant-swift-data auth guest --json
swift run instant-swift-data auth show --json
swift run instant-swift-data auth token <refresh-token> --user-id <user-id> --json
swift run instant-swift-data auth id-token google-ios <id-token> --nonce <nonce> --json
swift run instant-swift-data auth oauth <code> --code-verifier <verifier> --json
swift run instant-swift-data auth oauth-url google-ios myapp://oauth/callback --json
swift run instant-swift-data auth issuer --json
MAGIC_CODE_JSON="$(swift run instant-swift-data auth magic-code send user@example.com --json)"
MAGIC_CODE="$(printf '%s' "$MAGIC_CODE_JSON" | jq -r '.localVerificationCode')"
swift run instant-swift-data auth magic-code verify user@example.com "$MAGIC_CODE" --json
swift run instant-swift-data auth watch --events 1 --jsonl
swift run instant-swift-data auth sign-out --json
swift run instant-swift-data auth sign-out --skip-token-invalidation --json
```

Use Instant-compatible endpoint overrides for local/staging URL generation:

```bash
INSTANT_API_URI=https://api.example.test/custom \
INSTANT_WEBSOCKET_URI=wss://ws.example.test/runtime/session \
swift run instant-swift-data auth oauth-url google-ios myapp://oauth/callback --json
```

Persist local room presence and topic messages after signing in:

```bash
swift run instant-swift-data auth token local-refresh --user-id user-1 --json
swift run instant-swift-data rooms presence set chat lobby --value '{"name":"Ada","status":"online"}' --json
swift run instant-swift-data rooms presence list chat lobby --json
swift run instant-swift-data rooms presence watch chat lobby --events 1 --jsonl
swift run instant-swift-data rooms topics publish chat lobby sendEmoji --value '{"emoji":"wave"}' --json
swift run instant-swift-data rooms topics list chat lobby sendEmoji --limit 1 --json
swift run instant-swift-data rooms topics watch chat lobby sendEmoji --events 1 --jsonl
swift run instant-swift-data rooms presence leave chat lobby --json
```

Persist local file metadata and copied file contents after signing in:

```bash
swift run instant-swift-data auth token local-refresh --user-id user-1 --json
printf "hello instant files\n" > /tmp/instant-demo-file.txt
swift run instant-swift-data files upload /tmp/instant-demo-file.txt --content-type text/plain --json
swift run instant-swift-data files upload-progress /tmp/instant-demo-file.txt --content-type text/plain --jsonl
swift run instant-swift-data files list --json
FILE_ID="$(swift run instant-swift-data files list --json | jq -r '.files[0].id')"
swift run instant-swift-data files read "$FILE_ID" --json
swift run instant-swift-data files watch --events 1 --jsonl
swift run instant-swift-data files delete "$FILE_ID" --json
```

Persist local stream chunks after signing in:

```bash
swift run instant-swift-data auth token local-refresh --user-id user-1 --json
swift run instant-swift-data streams append chat/lobby --value '{"text":"hello"}' --json
swift run instant-swift-data streams append chat/lobby --value '{"text":"again"}' --json
swift run instant-swift-data streams read chat/lobby --limit 2 --json
swift run instant-swift-data streams watch chat/lobby --events 1 --jsonl
```

Create, accept, promote, demote, and revoke a local share with two users:

```bash
swift run instant-swift-data auth token owner-refresh --user-id user-1 --json
TODO_JSON="$(swift run instant-swift-data examples todos add "shared cli todo" --json)"
TODO_ID="$(printf '%s' "$TODO_JSON" | jq -r '.changedID')"
SHARE_JSON="$(swift run instant-swift-data shares create todos "$TODO_ID" --json)"
SHARE_ID="$(printf '%s' "$SHARE_JSON" | jq -r '.shares[0].share.id')"
SHARE_TOKEN="$(printf '%s' "$SHARE_JSON" | jq -r '.shares[0].share.token')"
swift run instant-swift-data auth token invitee-refresh --user-id user-2 --json
swift run instant-swift-data shares accept "$SHARE_TOKEN" --json
swift run instant-swift-data shares list --json
swift run instant-swift-data shares create todos "$TODO_ID" --json || test "$?" -eq 77
swift run instant-swift-data examples todos update "$TODO_ID" "reader edit" --json || test "$?" -eq 77
swift run instant-swift-data auth token owner-refresh --user-id user-1 --json
swift run instant-swift-data shares role "$SHARE_ID" user-2 writer --json
swift run instant-swift-data auth token invitee-refresh --user-id user-2 --json
swift run instant-swift-data examples todos update "$TODO_ID" "writer edit" --json
swift run instant-swift-data auth token owner-refresh --user-id user-1 --json
swift run instant-swift-data shares role "$SHARE_ID" user-2 reader --json
swift run instant-swift-data auth token invitee-refresh --user-id user-2 --json
swift run instant-swift-data examples todos update "$TODO_ID" "reader edit again" --json || test "$?" -eq 77
swift run instant-swift-data examples todos list --json
swift run instant-swift-data auth token owner-refresh --user-id user-1 --json
swift run instant-swift-data shares revoke "$SHARE_ID" --json
```

Run the CloudKitDemo-style shared counter demo:

```bash
swift run instant-swift-data auth token owner-refresh --user-id user-1 --json
COUNTER_JSON="$(swift run instant-swift-data examples counters add --count 24 --json)"
COUNTER_ID="$(printf '%s' "$COUNTER_JSON" | jq -r '.changedID')"
swift run instant-swift-data examples cloudkit-demo increment "$COUNTER_ID" --json
SHARE_JSON="$(swift run instant-swift-data shares create counters "$COUNTER_ID" --json)"
SHARE_ID="$(printf '%s' "$SHARE_JSON" | jq -r '.shares[0].share.id')"
SHARE_TOKEN="$(printf '%s' "$SHARE_JSON" | jq -r '.shares[0].share.token')"
swift run instant-swift-data examples counters list --json
swift run instant-swift-data auth token invitee-refresh --user-id user-2 --json
swift run instant-swift-data shares accept "$SHARE_TOKEN" --json
swift run instant-swift-data examples counters list --jsonl
swift run instant-swift-data examples counters increment "$COUNTER_ID" --json || test "$?" -eq 77
swift run instant-swift-data auth token owner-refresh --user-id user-1 --json
swift run instant-swift-data shares role "$SHARE_ID" user-2 writer --json
swift run instant-swift-data auth token invitee-refresh --user-id user-2 --json
swift run instant-swift-data examples counters increment "$COUNTER_ID" --json
swift run instant-swift-data examples counters list --json
```

Create and verify a local todo scaffold:

```bash
swift run instant-swift-data init --example todos --to .instant-swift-data-todos --json
swift run instant-swift-data schema verify --example todos --from .instant-swift-data-todos/instant.schema.ts --json
swift run instant-swift-data perms verify --example todos --from .instant-swift-data-todos/instant.perms.ts --json
```

Generate just the current todo example schema and permissions:

```bash
swift run instant-swift-data schema generate --example todos --to instant.schema.ts --json
swift run instant-swift-data perms generate --example todos --to instant.perms.ts --jsonl
swift run instant-swift-data schema verify --example todos --from instant.schema.ts --json
swift run instant-swift-data perms verify --example todos --from instant.perms.ts --json
```

Generate and verify the validation schema/perms fixture:

```bash
swift run instant-swift-data schema generate --example validation --to validation.generated.schema.ts --json
swift run instant-swift-data perms generate --example validation --to validation.generated.perms.ts --json
swift run instant-swift-data schema verify --example validation --from validation/fixtures/instant.schema.ts --json
swift run instant-swift-data perms verify --example validation --from validation/fixtures/instant.perms.ts --json
```

Run the local Swift validation evidence runner:

```bash
swift run instant-swift-data validation local-todos --jsonl
swift run instant-swift-data validation local-integrations --jsonl
swift run instant-swift-data validation reminders --jsonl
swift run instant-swift-data validation server-transaction-loopback --jsonl
swift run instant-swift-data validation typed-drafts --jsonl
swift run instant-swift-data validation platform-adapters --jsonl
swift run instant-swift-data validation syncups-recording --jsonl
swift run instant-swift-data validation parity-report --jsonl
swift run instant-swift-data validation coverage --jsonl
swift run instant-swift-data-validation-runner --local-todos
swift run instant-swift-data-validation-runner --local-integrations
swift run instant-swift-data-validation-runner --reminders
swift run instant-swift-data-validation-runner --server-transaction-loopback
swift run instant-swift-data validation reminders --jsonl | jq 'select(.event == "rich-filters") | .details.priorityRanksByReminderID'
swift run instant-swift-data-validation-runner --typed-drafts
swift run instant-swift-data-validation-runner --platform-adapters
swift run instant-swift-data-validation-runner --syncups-recording
swift run instant-swift-data-validation-runner --parity-report
swift run instant-swift-data-validation-runner --coverage
node validation/ts-runner/src/main.ts --fixtures
INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR=/tmp/instant-validation-results validation/run-e2e.sh
node validation/ts-runner/src/main.ts --swift-transport-contract /tmp/instant-validation-results/swift-transport-contract.json --app-id local-validation
node validation/ts-runner/src/main.ts --boundary-preflight
INSTANT_SWIFT_DATA_REMOTE_APP_ID=your-app-id INSTANT_ADMIN_TOKEN=your-admin-token node validation/ts-runner/src/main.ts --boundary-preflight --require-boundary
INSTANT_SWIFT_DATA_NODE=/path/to/node validation/run-e2e.sh
INSTANT_SWIFT_DATA_REMOTE_APP_ID=your-app-id INSTANT_ADMIN_TOKEN=your-admin-token INSTANT_SWIFT_DATA_REQUIRE_REMOTE_PREFLIGHT=1 validation/run-e2e.sh
validation/run-e2e.sh
```

`validation local-todos` emits local JSONL evidence for seed/update/cache/reset,
closed-connection offline write, offline relaunch restore, and reconnect flush.
`validation local-integrations` emits evidence for local auth, room
presence/topic messages, file upload/read, stream chunks, and share
create/accept/revoke. `validation reminders` emits terminal evidence for local
Reminders search, tags, rich fields, upstream-ranked numeric priority storage
with named CLI filters, form-model edit saves, smart-list stats, list sharing
roles, permission rejections, writer updates, and relaunch persistence.
`validation server-transaction-loopback` emits terminal evidence that a
server-applied transaction persists triples, publishes a live todo observer,
advances the processed transaction checkpoint, survives relaunch, and leaves the
local optimistic outbox untouched.
`validation typed-drafts` emits terminal evidence for a macro-generated create
draft whose `id` starts as `nil` and whose writable assignments omit the managed
primary key, `Draft(existing)` edit, a writable relation draft with generated ref
metadata, summarized pending mutation payload shape, and relaunch persistence
through `InstantSwiftDataClient.save(_:)` and `transact(saving:)`.
`validation platform-adapters` emits terminal evidence that public wrapper
adapters bind local client values for fetches, local IDs, auth, rooms, files,
streams, and shares, that SwiftUI projected bindings cover fetches,
`@InfiniteQuery`, local IDs, auth, rooms, files, streams, and shares when
available, that `@FetchAll` handles dynamic reloads, nil queries, cached prior
values on errors, and cancellation cleanup, that optional `@FetchOne` handles
dynamic and nil-query reloads, that `@Fetch` request adapters handle dynamic
request reloads, nil request resets, and cancellation cleanup, that live
room-presence wrappers replace stale subscriptions on dynamic room changes, and
that `@FetchAll` and `@Fetch` reload filtered active rows.
`validation syncups-recording` emits terminal evidence for the SyncUps scripted
speech recording flow, meeting persistence across relaunch, sound effect
advancement, and denied speech open-settings dependency seam.
`validation parity-report`
emits machine-readable upstream Instant/SQLiteData source provenance for exact,
adapted, and blocked parity records. `validation coverage` emits the same
coverage gate as a compact summary with blocked record ids.
`validation/run-e2e.sh` records those Swift validation streams, the Swift
schema/perms fixture generation and verification artifacts, the MacroTesting
log, and a one-iteration `local-todos` benchmark JSONL artifact by default; set
`INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS` to change that count. When
Node is available it also writes `typescript-fixtures.jsonl` and
`typescript-transport-contract.jsonl` after checking Swift's
`swift-transport-contract.json` lowered outbox payload. This proves a
Swift-produced transport contract is consumable from TypeScript, but remains
contract-only evidence. The boundary preflight writes `typescript-boundary.jsonl`
and checks for a non-local app id value, a non-empty admin token, and
syntactically valid API/WebSocket endpoints without contacting Instant or
running the still blocked live transport round trip.

Run local core benchmarks:

```bash
swift run instant-swift-data benchmark --suite local-todos --iterations 3 --json
swift run instant-swift-data benchmark --suite local-todos --iterations 3 --jsonl
swift run instant-swift-data-benchmarks --suite local-todos --iterations 3 --json
swift run instant-swift-data-benchmarks --suite local-todos --iterations 3 --jsonl
```

The `local-todos` suite records bootstrap, insert, query, enqueue, cache,
reset, offline-restore, high-bandwidth scalar update, high-bandwidth linked
write, storage metadata query, stream read/write, and live-query, presence,
topic, storage, and stream cancellation timings as structured JSON metrics.
High-bandwidth scalar, linked, and 1k/10k/50k triple workload samples include
resident-memory high-water growth and budget fields, and local store/query/
outbox hot-path samples include actor-hop breakdowns.

The current transport is intentionally marked `not-implemented-local-cache-only`
in command output. That means the demo proves durable local cache, typed triples,
query materialization, plan-aware persisted query results, optimistic outbox
persistence, local auth/session state, local room presence/topics, local file
metadata/content copies, local stream chunks, local share metadata/memberships,
local admin query/transact helpers, and non-captive CLI interaction, but it does
not yet sync with a real Instant app. The outbox can lower pending mutations to
Instant-shaped transport `txSteps` for inspection with `outbox transport` and
can exercise the local mutation transport ack path with `outbox flush`; explicit
`connection close` keeps writes queued until `connection connect`.
Endpoint helpers such as `auth oauth-url` and `auth issuer` mirror Instant's URL
shape and use configured `INSTANT_API_URI`/`INSTANT_WEBSOCKET_URI` values, but
they do not perform network I/O.

## Development

### Dependency Bootstrap

App, preview, test, and CLI entry points can install the default client through
Point-Free's Dependencies library:

```swift
import Dependencies
import InstantSwiftData

try await withDependencies {
  $0.instantMagicCodeExchange = .local
  $0.instantRefreshTokenVerifier = .local
  $0.instantIDTokenExchange = .local
  $0.instantOAuthExchange = .local
  $0.instantAuthTokenInvalidator = .local
  $0.instantMutationTransport = .local
  try await $0.bootstrapInstantSwiftData(
    appID: "local-demo",
    persistenceURL: cacheURL,
    context: .test,
    initialAttributes: TodoExample.attributes
  )
} operation: {
  @Dependency(\.defaultInstantSwiftData) var db
  let challenge = try await db.sendMagicCode(email: "user@example.com")
  _ = try await db.signInWithMagicCode(email: challenge.email, code: challenge.code)
  _ = try await db.signInWithIDToken(clientName: "google-ios", idToken: "local-jwt")
  _ = try await db.signInWithOAuth(code: "local-oauth-code")
  _ = try await db.query(TodoExample.query)
  try await db.signOut()
}
```

`instantMagicCodeExchange`, `instantRefreshTokenVerifier`,
`instantIDTokenExchange`, `instantOAuthExchange`,
`instantAuthTokenInvalidator`, and `instantMutationTransport` default to
`.local`, and app/test entry points can override them before
`bootstrapInstantSwiftData` to install live or fixture-backed auth/transport
behavior. Local/demo clients should be reusable static instances on the client
type, for example
`extension InstantMagicCodeExchange { public static let local = Self(...) }`,
while dependency keys remain computed `static var` `liveValue`, `testValue`, and
`previewValue` properties.
When the app declares `$users` attributes, use the result-returning magic-code
API to mirror Instant's auth extra-fields flow:

```swift
let result = try await db.signInWithMagicCodeResult(
  email: challenge.email,
  code: challenge.code,
  extraFields: ["username": .string("cool_user")]
)
print(result.created)
```

This stores `$users/id`, `$users/email`, and declared extra fields locally
without adding a pending client mutation.
The dependency client exposes durable auth directly with `authSession`,
`observeAuthSession`, `signInAsGuest`, `sendMagicCode`,
`signInWithMagicCode`, `signInWithMagicCodeResult`,
`signInWithRefreshToken`, `signInWithIDToken`, and `signInWithOAuth`,
`oauthAuthorizationURL`, `issuerURI`, and
`signOut(invalidateToken:)`, so app code does not need to reach through to the
core runtime.

### Typed Queries And Writes

Entities that conform to `InstantEntityModel` can build typed local queries and
optimistic mutations over the same runtime:

```swift
try await db.transact {
  Todo.create(
    id: InstantID(rawValue: "todo-1"),
    Todo.text.set("Ship Instant Swift Data"),
    Todo.isCompleted.set(false),
    Todo.createdAt.set(Date())
  )
}

let openTodos = try await db.query(
  Todo.query
    .where(Todo.isCompleted == false)
    .order(.serverCreatedAt, .descending)
)

let firstPage = try await db.queryOnceDecoded(
  Todo.query
    .order(Todo.createdAt)
    .first(10)
)

let selectedSnapshots = try await db.query(
  Todo.query
    .select(Todo.text, Todo.isCompleted)
    .plan
)

let usersWithPosts = try await db.query(
  User.query
    .include(Post.posts, Post.query.select(Post.title))
    .plan
)

@FetchAll(Todo.query.where(Todo.isCompleted == false))
var todos: [Todo]

try await $todos.load()

let subscription = try await $todos.subscribe()
defer { subscription.cancel() }

for try await todos in subscription {
  // Update model state from the latest local materialization.
}

@InfiniteQuery(Todo.query.order(Todo.createdAt).limit(20))
var pagedTodos: [Todo]

let paging = $pagedTodos
let pagingTask = Task { try await paging.task() }
defer { pagingTask.cancel() }

// Later, from a scroll threshold or button action:
if paging.canLoadNextPage {
  paging.loadNextPage()
}

@LocalID("todos.compose") var composeTodoID: String?
try await $composeTodoID.load()
try await $composeTodoID.load("todos.viewer")

@AuthSession var authSession: InstantAuthSession?
try await $authSession.load()

@RoomPresence("chat", "lobby") var presence: [InstantRoomPresenceMember]
try await $presence.load()

@RoomTopicMessages("chat", "lobby", "sendEmoji", limit: 10)
var messages: [InstantRoomTopicMessage]
try await $messages.load()

@StoredFiles var files: [InstantStoredFile]
try await $files.load()

@StreamChunks("chat/lobby", limit: 10) var chunks: [InstantStreamChunk]
try await $chunks.load()

@Shares var shares: [InstantShareSnapshot]
try await $shares.load()
```

`serverCreatedAt` is order-only metadata. Do not declare a model attribute with
that name; use a domain field like `createdAt` for decoded data, and use
`.order(.serverCreatedAt, ...)` when you want server-created ordering.
Queries without an explicit order follow Instant's implicit
`serverCreatedAt` ascending order.
`queryOnceDecoded` returns decoded typed values plus `pageInfo` for paginated
one-shot reads; use raw `queryOnce` when you need snapshots or emissions.
Partial field selection returns raw snapshots unless your entity decoder can
build a value from the selected fields.
Forward includes use typed ref attributes such as `Post.author`. Add
`@InstantRelation(reverse: "posts")` to a ref property when the generated schema
should carry reverse metadata and a typed reverse include token:

```swift
@InstantEntity
struct Post {
  var id: InstantID<Post>
  @InstantRelation(reverse: "posts")
  var author: InstantID<User>
}
```

The generated token is hosted on the relation-bearing type, so reverse includes
can use `.include(Post.posts, Post.query.select(Post.title))`. If you need a
custom token implementation, declare a static member with the same reverse name;
the macro will leave that manual declaration in place.
Strict one-shot queries validate field, order, and include references before
materializing or caching results.
`@Shares` observes local share snapshots for the signed-in user and runtime at
subscription time; resubscribe after switching auth sessions or runtime
instances.

`create` follows Instant's strict-insert semantics and fails when the entity
already exists. Use `update` for upsert-style writes, `updateExisting` when a
missing entity should fail, and `merge` for deep JSON merges. The local seed
demos use explicit upsert helpers so the same terminal commands can be run more
than once against durable state.

Primary-keyed `@InstantEntity` models also derive SQLiteData-style drafts for
form flows. New drafts may omit `id`; saving allocates the Instant id and
returns it, and draft assignments never write that managed id as a normal
attribute. Optional writable fields default to `nil` even when the entity
property does not spell out `= nil`, while non-optional fields keep their Swift
defaults or remain required. Writable Instant ref fields are included with their
relation metadata so linked entity forms can save relation drafts. Edit drafts
copy an existing entity and save back through the same typed mutation surface:

```swift
var draft = Todo.Draft(
  text: "Ship generated drafts",
  isCompleted: false,
  createdAt: Date()
  // notes defaults to nil
)
let todoID = try await db.save(draft, localIDName: "todos.compose")

var editDraft = Todo.Draft(try await db.query(Todo.query).first!)
editDraft.text = "Ship generated draft edits"
try await db.save(editDraft)

let composedDraft = Todo.Draft(
  text: "Ship draft and comment together",
  isCompleted: false,
  createdAt: Date()
)
let save = try await db.transact(
  saving: composedDraft,
  localIDName: "todos.compose-with-comment"
) { todoID in
  Comment.create(
    id: InstantID(rawValue: UUID().uuidString.lowercased()),
    Comment.todo.set(todoID),
    Comment.body.set("Created beside the draft")
  )
}
print(save.id)
```

Drafts do not conform to `Identifiable` automatically because multiple unsaved
drafts can share `nil` ids. Opt in locally when a SwiftUI flow needs it:

```swift
extension Todo.Draft: Identifiable {}
```

Unique attributes can identify entities and link targets with lookup refs, just
like Instant's `lookup(...)` transaction helper:

```swift
try await db.transact {
  User.update(
    lookup: User.email.lookup("blob@example.com"),
    User.name.set("Blob")
  )

  Post.author.link(
    from: Post.slug.lookup("lookup-refs-in-swift"),
    to: User.email.lookup("blob@example.com")
  )
}

let posts = try await db.query(
  Post.query
    .include(Post.author, User.query.select(User.name))
    .plan
)
```

Lookup writes are kept in lookup form in the pending outbox for future transport
lowering. The local store resolves them optimistically when the unique value is
already present; unresolved non-strict lookup writes remain pending for the
server to resolve later, while `updateExisting(lookup:)` fails before cache or
outbox writes when the lookup is missing.

`ruleParams` writes are also preserved in the pending outbox for transport
lowering, but they do not change local materialized entities optimistically:

```swift
try await db.transact {
  User.ruleParams(
    lookup: User.email.lookup("blob@example.com"),
    .object(["role": .string("owner")])
  )
}
```

Inspect lowered transport payloads before real network sync is configured:

```bash
swift run instant-swift-data outbox transport --json
swift run instant-swift-data outbox transport --all --jsonl
swift run instant-swift-data outbox flush --limit 1 --json
swift run instant-swift-data connection close --json
swift run instant-swift-data outbox flush --json # exits non-zero while closed
swift run instant-swift-data connection connect --json
swift run instant-swift-data outbox flush --jsonl
```

Subscriptions are bounded newest-value streams, so slow consumers receive the
latest local materialization rather than every intermediate invalidation.

Build and test:

```bash
swift build
swift test
```

Macro tests use Point-Free's MacroTesting library. To run just the macro
snapshot suite with a dedicated scratch path:

```bash
validation/run-macro-tests.sh
```

The core package is compiled in Swift 6 mode. Mutable runtime state is owned by
actors, and values crossing actor boundaries are immutable `Sendable` types.
