# Instant Recipes V3

This universal SwiftUI host contains every recipe currently listed at
<https://www.instantdb.com/recipes>:

- Todos
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
as the Mac and iPhone apps. In provisioned cloud mode, durable state and
presence are therefore shared across all four platforms.

## Provision a persistent live app

Run the provisioning helper once before building the native applications:

```bash
Examples/RecipesV3/provision-live-app.sh
```

It reuses the existing recipes app when possible. Pass `--fresh` to provision
a new ephemeral app through getadb.com. The helper pushes the aggregate recipes
schema and permissions, saves the app ID and admin token with mode `0600` under
the adjacent `private/credentials/swift-instant-data` directory, and writes the
app ID to the ignored `RecipesV3.local.xcconfig`. Override the private location
with `INSTANT_RECIPES_CREDENTIAL_DIR`. Only the public app ID is embedded in
application bundles; the admin token remains in the private credentials file.

## Run on macOS with SwiftPM

```bash
swift run recipes-v3
```

Set `INSTANT_APP_ID` to connect the SwiftPM executable to a live Instant app.
The Xcode applications read the persistent app ID created by the provisioning
helper. With no app ID, the executable uses the durable local runtime. Use
`INSTANT_RECIPE` or `--recipe <path-name>` to open one recipe directly.

```bash
INSTANT_RECIPE=merge-tile-game swift run recipes-v3
swift run recipes-v3 --recipe todos
```

## Run the forced-Desert loopback prototype

All eight recipes can be forced onto the Desert route even while Internet
access is available. The current prototype uses a memory-only coordinator in
the Mac host and an actual Network.framework TCP connection from the iOS
Simulator peer over `127.0.0.1`. It does not discover peers and is not evidence
for physical devices, a router/LAN, direct peer-to-peer Wi-Fi, Bluetooth, or
WatchConnectivity.

Build from a clean `desert` commit first:

```bash
Examples/RecipesV3/build-all-platforms.sh
```

In one terminal, start the Mac host. The app ID is a local session identifier in
this forced lane; it must be nonempty and must match the peer:

```bash
INSTANT_APP_ID=recipes-v3-desert-manual-01 \
INSTANT_SWIFT_DATA_SYNC_ROUTE=desert-required \
INSTANT_DESERT_ROLE=host \
INSTANT_DESERT_HOST=127.0.0.1 \
INSTANT_DESERT_PORT=49800 \
INSTANT_RECIPE=todos \
"/tmp/instant-recipes-v3-platforms/Build/Products/Debug/Instant Recipes.app/Contents/MacOS/Instant Recipes"
```

Wait for the Mac banner to show
`Desert host · 127.0.0.1:49800 · Connected`. With a simulator already booted,
run the peer from a second terminal:

```bash
xcrun simctl install booted \
  "/tmp/instant-recipes-v3-platforms/Build/Products/Debug-iphonesimulator/Instant Recipes.app"

xcrun simctl launch --terminate-running-process --console \
  booted com.technoplato.InstantSwiftData.RecipesV3iOS \
  --instant-app-id recipes-v3-desert-manual-01 \
  --sync-route desert-required \
  --desert-role peer \
  --desert-host 127.0.0.1 \
  --desert-port 49800 \
  --recipe todos
```

The iOS banner must show
`Desert peer · 127.0.0.1:49800 · Connected`. Replace `todos` in both launch
commands with any one of these exact recipe path names:

```text
todos
cursors
custom-cursors
reactions
typing-indicator
avatar-stack
merge-tile-game
auth
```

The equivalent environment keys are `INSTANT_APP_ID`,
`INSTANT_SWIFT_DATA_SYNC_ROUTE`, `INSTANT_DESERT_ROLE`,
`INSTANT_DESERT_HOST`, `INSTANT_DESERT_PORT`, `INSTANT_RECIPE`, and optional
`INSTANT_PERSISTENCE_PATH`. Their command-line equivalents are
`--instant-app-id`, `--sync-route`, `--desert-role`, `--desert-host`,
`--desert-port`, `--recipe`, and `--persistence-path`.

Forced startup fails visibly if a required value is missing, the role/port is
invalid, the peer cannot connect, or the recipe asks the prototype for an
unsupported query. It never falls back to cloud. Merge Tile supports the
recipe's exact string-ID query with `limit(1)`; broader query shapes remain
unsupported. Auth supports guest and local magic-code sign-in, but each client
keeps an independent local session. Cloud provider sign-in is unavailable in
forced Desert mode.

Run the strict all-eight non-UI gate with:

```bash
validation/verify-recipes-v3-desert-smoke.sh
```

The gate requires exactly one successful JSONL record for every recipe. It uses
an in-process host plus an actual loopback Network.framework peer and returns
nonzero for missing, duplicate, skipped, unsupported, wrong-route, or
wrong-adapter evidence.

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
