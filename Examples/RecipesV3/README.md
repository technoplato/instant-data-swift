# Instant Recipes V3

This universal SwiftUI host contains every recipe currently listed at
<https://www.instantdb.com/recipes>:

- Todos
- **Linked Infinite** — infinite page of parent entities with linked children
  (e.g. recordings + transcription word counts via `.include`, not a second
  infinite stream)
- Cursors
- Custom Cursors
- Reactions
- Typing Indicator
- Avatar Stack
- Merge Tile Game
- Auth

All durable state, presence, topic, mutation, and authentication behavior lives
in the Swift package targets. This folder only supplies native macOS, iOS,
tvOS, and watchOS application hosts.

The tvOS host uses Siri Remote focus for navigation, directional cursor
controls, reactions, authentication, and the Merge Tile board. The watchOS
host uses a compact recipe catalog, touch-driven cursor surfaces, and a
watch-sized Merge Tile grid. Both hosts embed the same persisted public app ID
as the Mac and iPhone apps, so durable state and presence are shared across all
four platforms.

## Provision a persistent live app

Run the provisioning helper once before building the native applications:

```bash
Examples/RecipesV3/provision-live-app.sh
```

It reuses the existing recipes app when possible. Pass `--fresh` to provision
a new ephemeral app through getadb.com. The helper pushes the aggregate recipes
schema and permissions (including **Linked Infinite** namespaces), saves the app
ID and admin token with mode `0600` under the adjacent
`private/credentials/swift-instant-data` directory, writes the app ID to the
ignored `RecipesV3.local.xcconfig`, and writes a gitignored
`Examples/RecipesV3/.env` for `swift run`. Override the private location with
`INSTANT_RECIPES_CREDENTIAL_DIR`. Only the public app ID is embedded in
application bundles; the admin token remains in private credentials / `.env`.

### Live Linked Infinite (Mac)

```bash
# Once: provision + push schema (linked_infinite_* namespaces)
Examples/RecipesV3/provision-live-app.sh

# Run against Instant (loads Examples/RecipesV3/.env automatically)
cd /path/to/instant-data-swift
INSTANT_RECIPE=linked-infinite swift run recipes-v3
```

The catalog shows **Connected to InstantDB** when `INSTANT_APP_ID` is set.
Without it, the host stays **Local data only**. Admin tokens are never required
for normal recipe UI — only for schema push.

## Run on macOS with SwiftPM

```bash
swift run recipes-v3
```

Set `INSTANT_APP_ID` to connect the SwiftPM executable to a live Instant app.
The Xcode applications read the persistent app ID created by the provisioning
helper. With no app ID, the executable uses the durable local runtime. Use `INSTANT_RECIPE` or
`--recipe <path-name>` to open one recipe directly.

```bash
INSTANT_RECIPE=merge-tile-game swift run recipes-v3
swift run recipes-v3 --recipe todos
swift run recipes-v3 --recipe linked-infinite
```

### Linked Infinite (CLI seed + page)

Demonstrate join-shaped infinite paging without the UI:

```bash
swift run instant-swift-data examples linked-infinite seed
swift run instant-swift-data examples linked-infinite list   # first page (3 roots + linked word counts)
swift run instant-swift-data examples linked-infinite page   # loadNextPage expands roots
swift run instant-swift-data examples linked-infinite list --json
```

## Build every Apple platform

```bash
Examples/RecipesV3/build-all-platforms.sh
```

The script regenerates `InstantRecipesV3.xcodeproj` from `project.yml` and
builds unsigned Mac, iPhone/iPad Simulator, Apple TV Simulator, and Apple Watch
Simulator apps. Override destinations with the `INSTANT_RECIPES_*_DESTINATION`
environment variables when a specific simulator is required.

## CLI

One-shot commands are the noninteractive surface:

```bash
swift run instant-swift-data recipes todos add "do the dishes"
swift run instant-swift-data recipes todos list --json
swift run instant-swift-data recipes reactions tap fire
swift run instant-swift-data recipes merge-tile-game board --json
```

The shell keeps accepting recipe commands until `exit` or end-of-file:

```bash
swift run instant-swift-data recipes interactive
```

Use `--no-prompt` for piped input and `--json` or `--jsonl` for structured
output.
