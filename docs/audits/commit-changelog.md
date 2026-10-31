## 2026-10-31 00:25:31 EDT — instant-data-swift `47afdc9b8c802699df8989f7985d8a38b5417bfc`
Test (#1436): every outbox index a live write writes is read by its own cycle (SQLite's plans of its 66 statements), and its effect rows are written once; the levers left are #1463 and #1464.

## 2026-10-31 00:23:31 EDT — scribe `f3c7872c505467c733a9238f356d86a6226d5f3f`
Docs (#1442): a corrected cause for a counter that read zero.

## 2026-10-31 00:22:26 EDT — scribe `ffe9a13290483349780e0df1dc6df5dc3202158b`
Docs (#1442): the plan's steps name their issues.

## 2026-10-31 00:20:48 EDT — scribe `b24a46a48fbc2b2688742f04c40cd0d1d2aab611`
Docs (#1442): what a stream append and a stream reader cost, measured through the library.

## 2026-10-31 00:04:53 EDT — scribe `a44ce7ca3ae6691c308628d69cd08d807530b81e`
Docs (#1442): the first recording on the live room path.

## 2026-10-31 00:15:35 EDT — scribe `77b905e7a38c44b465f3ac80476e1db8f8c3879a`
Landing (#1432): two tests now fail on the old shared file key, and the install result of the build that carries the fix.

## 2026-10-30 22:02:21 EDT — scribe `dea8e177e35549bc77f44faf90a9e21f9789f13b`
Docs (#1432): progress entry for the build that carries the fix, on every device.

## 2026-10-30 22:01:46 EDT — scribe `145d568d9c60f711a3fa3eb6e46663c33ca65c67`
Tests (#1432): an empty read writes nothing at once, and a failed read after a write keeps the value; both fail on the old key.

## 2026-10-31 00:14:03 EDT — scribe `dc0a6e157b328d1ffd11312b75fdd3d4592b002e`
Docs (#1427): the interims audit, its ADR and its plan record the second landing as parked, a proposal only, and the first as adding no delay.

## 2026-10-31 00:02:36 EDT — scribe `3831c514f657dab10ccfb92b118566c532604354`
Fix (#1451): an agent post in a person thread names its recording.

## 2026-10-31 00:02:36 EDT — scribe `550d83f319aa1f16f4ca6c549cac31b405d8c622`
Fix (#1451): the rules let the owner set move a person thread status, and only that.

## 2026-10-30 23:49:35 EDT — scribe `e75259261720e4e727612120363fccf74e5d08a1`
Cut (#1404): Scribe 0.1 (197).

## 2026-10-30 23:49:35 EDT — scribe `32cc67c2d280610944cba5febb7bf4e4d9494ec1`
Fix (#1404): other platforms keep their list rows as they were.

## 2026-10-30 23:49:35 EDT — scribe `2c5e64f019f4666a59de4c3f13eb0ef43ced59c9`
Fix (#1404): a list row's insets reach the list on Vision Pro.

## 2026-10-30 23:37:30 EDT — scribe `3bc5bed1b4ad7b8ef12d2cee21f440444f89278f`
Chore (#1435): change-log for the export's red and green.

## 2026-10-30 23:14:14 EDT — instant-data-swift `da140b69ab85dcb77a912575096c2cc6eb9e5258`
Fix (#1435): an outbox write's body lives in instant_outbox_bodies and the row is narrow (WITHOUT ROWID), so a claim and an acknowledgement write the row alone: 4.17 and 6.17 -> 2.00 and 4.00 log frames a write; a store converts once at open.

## 2026-10-30 22:19:47 EDT — instant-data-swift `5ae13a7f0c95957c1c20428bd3f3b2e63e4c8573`
Plan (#1435): amendments 2 and 3, FOOTGUNS F59 and #1436's per-index reads test.

## 2026-10-30 22:19:23 EDT — scribe `1dc25af2317a030b34249b3a1daab5599e15964e`
Fix (#1435): Reset Local Cache's export of unsent writes, the recovery script and query-plans read the library's outbox in either layout.

## 2026-10-30 22:19:22 EDT — scribe `108c9d595b541a6b6db2fca4eca1804c07a0e78a`
Test (#1435): red: the export and the recovery script read a store whose bodies have their own table.

## 2026-10-30 22:18:58 EDT — scribe `936fdd6a08a485dc9300402477841ddee9189180`
Chore (#1435): plan and claims for the narrow outbox's readers, the instant-data-swift 1.9.55 pin and the cut.

## 2026-10-30 21:36:56 EDT — instant-data-swift `ba2c901b89067a6ee42b99b318dab7357aa5584d`
Plan (#1435): amendment 1, the retained-mutation quarantine test's raw outbox SQL.

## 2026-10-30 21:22:21 EDT — instant-data-swift `7730fb220c23ffbfc2bd351db192fc02debec781`
Test (#1435): red: a claim and an acknowledgement rewrite the write's body, and the outbox has no narrow layout to convert to.

## 2026-10-30 21:11:52 EDT — instant-data-swift `47891a5fb0c8261199e15bf7d967e57d6e8a03ff`
Plan (#1435): 2026-10-30-outbox-1435 and its claims.

## 2026-10-30 23:33:14 EDT — scribe `29063405ed03e4d758d04bfd42ed6a6f20289779`
Docs (#1442): the streams report, corrected against the source.

## 2026-10-30 23:22:49 EDT — scribe `ddadd09fefa077cff003aa4c9af059ee177ce9f2`
Docs (#1442): a report comparing streams with the live room path on latency, wire bytes and storage writes.

## 2026-10-30 22:41:55 EDT — scribe `0f09365a24948d26c68a9ff34452252a97bb0d97`
Cut (#1393, #954, #1437, #1438): Scribe 0.1 (196): Today holds what it counts, one speaker name sideways, the notice's timer.

## 2026-10-30 22:41:19 EDT — scribe `5fdd553ef3bc148700a2cb40ed39e0b29fda2202`
Landing (#954, #1437, #1438, #1395): Today's list and count ask one question, one speaker name in the split, a notice on a timer, kept stamp pictures.

## 2026-10-30 22:39:53 EDT — scribe `299890798a2e5df3842b18095ea13c5834d4b2eb`
Land (#1428): a recording's frames save together in the app's durability lane, and a media pass links its uploads in one transaction.

## 2026-10-30 22:39:53 EDT — scribe `29f07ebfc588d87e0c0faa5fa1704fd1296c7d3b`
Change log (#1428): entries for the test, fix and docs commits.

## 2026-10-30 22:39:53 EDT — scribe `d7d2f48347fc4b6a5ee435e5b9659ec68fd0094b`
Docs (#1428): an app ADR amendment on media uploads, an audit of per-frame writes, and the release notes.

## 2026-10-30 22:39:53 EDT — scribe `2ede142c235b66b90cca6b266060a0add348bf68`
Fix (#1428): an app writes a recording's images as one transaction per few seconds, and links each pass's stored files at once.

## 2026-10-30 22:39:53 EDT — scribe `6bac038f465f4164722f9a7154075d155ba27652`
Test (#1428): red tests for batching image metadata and file links.

## 2026-10-30 21:44:30 EDT — scribe `4d4c134c42965d7b619e85904befdc01a0cb6908`
Cut (#1426): Scribe 0.1 (195): instant-data-swift 1.9.54, a server refresh writes what changed; carries #1427's landing A and #1197's mirror fixes.

## 2026-10-30 21:43:44 EDT — scribe `afbef8e7c35057350102e4c50397c02cd1fc43b0`
Fix (#1426): pin instant-data-swift 1.9.54 in Scribe, Scribe Playback and the quota package; the installer's expected version follows.

## 2026-10-30 21:42:56 EDT — scribe `ed9021197bf4eacadc35aeeefcba229f10222581`
Chore (#1426): plan and claims for the 1.9.54 pin and the build 195 cut.

## 2026-10-30 21:40:39 EDT — instant-data-swift `dad50753b24bef25d0ab118f3e27b970256319d2`
Ledger (#1426): v1.9.54's release document, PROGRESS, the changelog and the audit ledger; tagged v1.9.54.

## 2026-10-30 21:39:42 EDT — instant-data-swift `86f89b02105152727be975b5ff3999b001bbf246`
Fix (#1426): a changed live-query result's JSON waits for the app's flush instead of being rewritten whole every five minutes, and a relaunch's unchanged answer writes its row only.

## 2026-10-30 21:39:41 EDT — instant-data-swift `a3d254803edf6385e188fb0b89a2adffee79a157`
Test (#1426): red: what a server refresh writes by b-tree; a changed result's JSON every five minutes and a relaunch's unchanged answers follow the result, not the change.

## 2026-10-30 20:24:38 EDT — instant-data-swift `3d5bdada429e157e4c8e3ded215452a548c74917`
Plan (#1426): 2026-10-30-sqlite-writes-1426 and its claims.

## 2026-10-30 21:22:20 EDT — scribe `6af4f1e6e972d0920875ff88cb96dfad6822e720`
Docs (#1427): landing A's What's New story and PROGRESS entry.

## 2026-10-30 21:22:20 EDT — scribe `ce50fb31a66b705e5160dc3eec0034f4e1185831`
Docs (#1427): the interims audit.

## 2026-10-30 21:22:20 EDT — scribe `f9cbef433429bb4639158eb65449b2aa6f641206`
Docs (#1427): ADR 0094 amendment A, the line in progress rides the room; landing B as the dispatcher decided.

## 2026-10-30 21:22:20 EDT — scribe `a67b10f131410aaacf9bb573811a31ac43b4e86f`
Green (#1427 landing A): the recording device publishes each open line in the take's room beside its beat, keyed by segment id; playback on every device reads it beside the rows.

## 2026-10-30 21:22:20 EDT — scribe `d34bfe05930ac1b51ac7d85660717f36633bee1a`
Mirror (#1427, #1197): the db reads the live rooms as admin; each 5 s presence poll folds the owners' lines in progress in as open lines.

## 2026-10-30 21:22:20 EDT — scribe `388ba28026dd47f98ff5abec90d1fe3b0832d48d`
Red (#1427, #1197): the mirror reads the room's line in progress, and its db reads rooms.

## 2026-10-30 21:22:20 EDT — scribe `e8e7310ec7a8c67d141eeb79b1d95c9ebb0ab723`
Red (#1427): the line in progress rides the recording's live room; declarations only, 8 tests fail on their assertions.

## 2026-10-30 21:04:14 EDT — scribe `94366681cadd78ca00f134c5b35fa4e05264fecd`
Cut (#1432): Scribe 0.1 (194): a shared file key never writes over a file it could not read, and the setup screen waits for it.

## 2026-10-30 21:03:06 EDT — scribe `c3d205fd2972ef803815b2d8a25a1bae1890a742`
Landing (#1432): a shared file key never writes over a file it could not read, and the setup screen waits for preferences it could not read.

## 2026-10-30 21:02:07 EDT — scribe `41a1c88d01cad54008479ed2d95ab6207f82c4a1`
Docs (#1432): amendment A to the capture-isolation decision: nothing is written over a file until a read has shown what it holds.

## 2026-10-30 20:27:08 EDT — scribe `b8decd3865d39e037bc5bc38e4c27c81966ba7ef`
Fix (#1432): a failed read, an empty file and undecodable bytes are read again instead of taken for no file; changes wait; the watcher never creates an empty file.

## 2026-10-30 20:27:07 EDT — scribe `db508929c2392bc3d9766a97af48072387194933`
Tests (#1432): a file the shared key could not read is never written over, and the setup screen waits for it.

## 2026-10-30 20:23:46 EDT — scribe `1b9fcd34c24d972295aea149db159eb832a45e49`
Cut (#1393, #1365): Scribe 0.1 (193): the home screen's dashboard and days, two corners sideways, three map proposals.

## 2026-10-30 20:22:57 EDT — scribe `9bb5fd57745daf09057bba36f45e55407faf72b0`
Landing (#1393, #1365): the home screen reads every recording live on any device, the agents' rows and what is due, and the iPhone held sideways keeps its controls in two corners.

## 2026-10-30 17:52:07 EDT — scribe `4ffd02f6aaedec17220601c23ba7dcdfb6b64274`
Cut (#1393): Scribe 0.1 (190): a screenshot's two times, the floating bar's comb, Answers by thread.

## 2026-10-30 17:09:14 EDT — scribe `25ac280d63335a6f653611b50aa07d26b91d0e21`
Landing (#1393): a screenshot's two times, the floating bar's comb, Answers by thread.

## 2026-10-30 16:53:52 EDT — scribe `f85201d7b54fab29986fea4d524b7f80fa1084f9`
Cut (#1393): Scribe 0.1 (189): the frames band's fold, the broadcast menu stays open, playback's live row.

## 2026-10-30 16:52:56 EDT — scribe `a1914452dd4aaad5995f67164361541f0ff18411`
Landing (#1393): the broadcast menu stays open, playback's live row, the band's close button, scroll tracking.

## 2026-10-30 15:38:21 EDT — scribe `6e6b8b77628dd1f5b9cb578a0f1ba4b5e8f7253b`
Landing (#1393): the frames band's long press chooses when it folds, synced to every device.

## 2026-10-30 19:43:41 EDT — scribe `d78cb20150dba640f9dd07ac8a02c1588e146ea9`
Docs (#1431): the builds skill keeps every installed build's symbols, with their sizes and retention.

## 2026-10-30 19:43:41 EDT — scribe `3304ef57fb41fa6fe48d3e29bd6f4d15f3bbe80b`
Feature (#1431): a script names an iOS report's main thread from the kept build whose UUID it names.

## 2026-10-30 19:43:41 EDT — scribe `31c695383975250c665f4ed5b31708818b204e87`
Fix (#1431): the installer keeps each verified build's app, dSYMs and image UUIDs before the build output is cleaned.

## 2026-10-30 19:43:41 EDT — scribe `f05be3dbc468915cc0242463b1b6129a0d2f1a25`
Test (#1431): red tests for the installer's keep step.

## 2026-10-30 18:46:38 EDT — scribe `c33e377ec94554ee5fe0438febaf3bb3255dbb66`
Cut (#1258): Scribe 0.1 (192): launch never waits on the system's upload daemon.

## 2026-10-30 18:46:38 EDT — scribe `1eceff6ee6676120f4433a06f7896ae426676486`
land(#1258): the background upload session made off the launch path, and the ledger's task count.

## 2026-10-30 18:46:38 EDT — scribe `a463b14842dd04cb6ff769ad6aa8855849d1d3e4`
Docs (#1258, #1428): the diagnostics inventory's row for the background session's task count.

## 2026-10-30 18:46:38 EDT — scribe `75d911f1a816eddfc0d67940562c82d3dd66693c`
Docs (#1258, #1428): an amendment on making the background upload session off the launch path.

## 2026-10-30 18:46:38 EDT — scribe `c946d86db3c4da13e7b1cb2082eb4fcb372f0a84`
Feature (#1258, #1428): each energy-ledger minute counts the background upload session's tasks.

## 2026-10-30 18:46:38 EDT — scribe `7411cf9eee70e68c1f304bea5cc5a731daf3c948`
Test (#1258, #1428): red tests for the background session's task count.

## 2026-10-30 18:46:38 EDT — scribe `569fbc8429206b8fd878d8ebac5198c34689272a`
Fix (#1258): the background upload session is made on its own queue; launch never waits for it.

## 2026-10-30 18:46:38 EDT — scribe `8c7c919b4520ca5818578ea4d9b3a99e03abfcb9`
Test (#1258): red tests: launch returns while the system still makes the background upload session.

## 2026-10-30 18:43:15 EDT — scribe `d223db45153c9a00128d17c2019f821a0a9a84fb`
Cut (#1404): Scribe 0.1 (191).

## 2026-10-30 18:43:15 EDT — scribe `93ebbda5b58d4876347f1ebc2c2c7e437a881481`
Fix (#1404): a live recording's length and full screen clock run on its beats.

## 2026-10-30 18:43:15 EDT — scribe `e695c0eab6f456e0437c8ed2a9817d04a461c28e`
Fix (#1404): one highlight shape, taller lines, closer rows and an opaque drawer on Vision Pro.

## 2026-10-30 18:43:15 EDT — scribe `b82d12c748e9fdfe71f4668717ff33b6c96f6c35`
Fix (#1404): Vision Pro takes the move to a speech provider with speaker labels.

## 2026-10-30 18:43:15 EDT — scribe `3889dcf3409255d737ef72c327c828ccf4fbe920`
Fix (#1404): a recording's own window reads the live room and reaches the list.

## 2026-10-30 17:01:17 EDT — scribe `e77e17445f99cf8eb0e16ee890ca36eaa6b78d3c`
Fix (#1395): restores the audits index a plumbing commit emptied.

## 2026-10-30 17:01:17 EDT — scribe `59410da727fe9df55b20ce8c04819fa72b8e5aee`
Docs (#1395): an after-the-fact performance and energy audit of one long recording.

## 2026-10-30 16:22:57 EDT — scribe `443b848d28329c75095cad40d23a12c79d467584`
Fix (#1404): the Vision Pro icon has a real top layer, and an install no longer launches on the headset.

## 2026-10-30 14:54:10 EDT — scribe `b689465ba635452c9c0df7d9a88f46c848275f32`
Cut (#396): Scribe 0.1 (187): Settings and sign-in on Vision Pro.

## 2026-10-30 14:54:10 EDT — scribe `c0ff3be7ec2328978cca7cca8c9fddaa20876d00`
Fix (#396): the floating bar inside the Settings sheet, and a sidebar wide enough for its toolbar on Vision Pro.

## 2026-10-30 14:54:10 EDT — scribe `dbfa5faa2504ecbe5b5cf254bf3a6ac1c198e16e`
Fix (#396): the Settings gear stays on the Vision Pro list, out of a More overflow.

## 2026-10-30 14:54:10 EDT — scribe `15e7dbff4a8570aa3f729e9bfbfe33aa81c23e27`
Docs (#1404): scribe-vision-pro, one skill for building and auditing the Vision Pro app.

## 2026-10-30 14:54:10 EDT — scribe `af7d8a6ca25220be836e0a9372beefaf1483cdfe`
Feature (#396): ui-check, an XCUITest run that drives the app on a visionOS simulator.

## 2026-10-30 14:54:10 EDT — scribe `ba99ae1c861870a1ef0e0eaea384372b1210ac40`
Fix (#396): Settings and sign-in on Vision Pro, the 1.9.53 pin, and the installer's Vision Pro role.

## 2026-10-30 14:04:40 EDT — scribe `293112a0f8b5772e5e0b2f69863e15d3bdab678c`
land(#1393): the two ADRs.

## 2026-10-30 13:58:10 EDT — scribe `567f800f896abba0e501bdb5a7701e59b1d2d40d`
Tooling (#1412): the old heavy.sh name forwards to build.sh and says so.

## 2026-10-30 13:58:10 EDT — scribe `1016cb8617c14e7e9d7b445a3039979d1a676627`
Docs (#1412): the agents skill describes build jobs; a historical guide line restored.

## 2026-10-30 13:58:10 EDT — scribe `f82a0f1db356e80fff47b56bffd6cfb15494f678`
Tooling (#1412): stable build info for mini test jobs (reverted: ineffective).

## 2026-10-30 13:58:10 EDT — scribe `59b1ec67df844808ca039df42f852361991d4ba7`
Docs (#1412): ADR 0104 measurements.

## 2026-10-30 13:58:10 EDT — scribe `e1f28a2f92bc8fff526467a91736736672108854`
Perf (#1412): the build machine's bare repo keeps each slot's last commit as a ref, so pushes send only new objects (12 s to 0.4 s).

## 2026-10-30 13:58:10 EDT — scribe `f5b9801411c805b2d44b6e328230031818c505fa`
Revert (#1412): the stable build info variable never reaches the package plugin.

## 2026-10-30 13:15:59 EDT — scribe `6852adc40de1db5a2d98fdaf3d727efbec72f83c`
land(#1393): Scribe 0.1 (186).

## 2026-10-30 13:07:11 EDT — scribe `8b1713a02887ed22c56d9fff47678d1ba5532b06`
Fix (#1395): a speech utterance's partial waits for voice since the last partial.

## 2026-10-30 13:07:11 EDT — scribe `01cebb86efd4e75c26e337f634b1f8993e1402d0`
Fix (#1395, #1219): a repeated partial stops in the reducer; a tick keeps the stamp's render-server schedule; a slow turn says what its CPU covers.

## 2026-10-30 13:07:11 EDT — scribe `8c116f7130f1574ea8b9d9b1a5572dbdac133a41`
Fix (#800, #1395): the level reaches the store every two seconds.

## 2026-10-30 13:07:11 EDT — scribe `5ddeb9b8b006c445855e275a5cb3cf2049cdfdc3`
Fix (#1395): a saved interim no longer updates the list rows under the recording screen.

## 2026-10-30 13:07:11 EDT — scribe `518e06a0caea59e38f2f33552139368a09b72374`
Cut (#1395): build 185.

## 2026-10-30 13:03:32 EDT — scribe `4d7c50b2e287a43cfc7438870797c68001eb2776`
Tooling (#1412): mini build jobs reach two warm slots by git over SSH (a dirty tree becomes a throwaway commit on no branch) and run in tmux; scratch removed after each job.

## 2026-10-30 13:03:32 EDT — scribe `a5fe0f69c1dea575b37df375f64fc58ee5d79a11`
Fix (#1412): build.sh's default mini root matches the worker's.

## 2026-10-30 13:03:32 EDT — scribe `0961160e079ab7f4ead99c1a1047aae10a33055d`
Schema (#1412): buildJobs, one row per build job, owner-only, a state machine in its update rules.

## 2026-10-30 13:03:32 EDT — scribe `4182c19cd94d4d960a7a0763895e33d9ff949db4`
Tooling (#1412): every build job a buildJobs row through an offline outbox; a worker per machine; mini jobs run with a fixed environment so warm builds stay incremental.

## 2026-10-30 13:03:32 EDT — scribe `8be14eef91b324d0b60c2fd6cfa8d33821e9833e`
Tooling (#1412): the mini takes jobs first; snapshot and macOS-26-behavior tests stay on the laptop; a job that cannot fit is refused before it starts.

## 2026-10-30 13:03:32 EDT — scribe `3075aa38789a9ddabb71f95cfb0cdbfed0b74fd8`
Tooling (#1412): the status page lists the build jobs in progress.

## 2026-10-30 13:03:32 EDT — scribe `811e995684052f2d642b1899441b42148f2a7cbc`
Docs (#1412): ADR 0104, the build machine and buildJobs.

## 2026-10-30 13:03:32 EDT — scribe `d62db404c52b3585cb6f17a205aba62844e4cf96`
Fix (#1412): buildJobs' terminal-state rule check carries its own parentheses (a bare || split the whole update rule).

## 2026-10-30 13:03:32 EDT — scribe `601db2328d040efbff9752b52a7e6c3824ce10fe`
Tooling (#1412): the build workers run under launchd on both machines.

## 2026-10-30 13:03:32 EDT — scribe `a4b8755e2f33fc844c29ef32ca273673ef6f8bb0`
Fix (#1412): the outbox flush counts only writes still waiting.

## 2026-10-30 13:03:32 EDT — scribe `a2b32bd8e1a53d116e5d7e6fbe3c8e7ea6d91cdf`
Tooling (#1412): the build machine's free-space floor is an operator's file.

## 2026-10-30 13:03:32 EDT — scribe `c2a4d74cfbb58cb6f0113f96a02111b122d365f4`
Fix (#1412): the laptop's build worker no longer creates the build machine's folders.

## 2026-10-30 12:50:01 EDT — scribe `97df897bb71bb5471f619a57c28aa05034647488`
land(#1393): Scribe 0.1 (184).

## 2026-10-30 12:48:53 EDT — scribe `bd6db6b955436efb60068bb3b8158b02d671da85`
land(#1393): the playground's other half: main builds again.

## 2026-10-30 12:48:32 EDT — scribe `2c4c56464ce3cc523dc9ea4add9ee6730a27052b`
land(#1393): the playground after his review, event colors, two fingers from rest, playback's words under the bar, answers paging.

## 2026-10-30 11:34:06 EDT — scribe `8101192de99b4a4be5e77aeee1331e01c716eb5e`
land(#1393): Scribe 0.1 (183).

## 2026-10-30 11:32:49 EDT — scribe `ed5c24a3cb3357c7b8667775b9105aa92aaa1ed6`
Tooling (#1412): heavy.sh renamed build.sh and versioned in the Scribe repo (scripts/build-jobs); HEAVY_* variables are BUILD_*; a transition forwarder keeps waiters queued before the rename on the old code.

## 2026-10-30 11:31:22 EDT — scribe `abcaaccbc1bb8035c6c5af3d450aa291a57270e6`
Landing (#1393, #1398, #1389, #1365, #1388): the frames band stays and pages, a thread opens in its own sheet, the broadcast long press starts it, Select moves to the long press, Search Settings, the Playback player's X, and the playground's proposals after the review.

## 2026-10-30 11:08:09 EDT — instant-data-swift `1c5fc76d9aa1329f90612ee158aa7c36d7950bfb`
Fix (#396): the package declares visionOS 2, so it cross-compiles for Vision Pro.

## 2026-10-30 10:41:06 EDT — scribe `7052cf37e586863f74709c9836afe79bd46441d5`
Scribe 0.1 (182): a line's time is the link, a card on long press, the X on everything.

## 2026-10-30 10:40:50 EDT — scribe `0d4a39bcdc8ba06879e0ee047d736ffd205c0845`
Landing (#1393, #1392, #1391, #1390, #1389): the time is the link, a card on long press, the X everywhere, side bars he writes, the map's pictures, the proposals.

## 2026-10-30 09:52:15 EDT — scribe `435e33af28acb3bab032c0c336ab13c54f31e587`
Fix (#290): a recording shows the newest heart rate at once, and readings keep coming behind another app.

## 2026-10-30 09:20:39 EDT — scribe `fe90eb83728647764c1428428f0be7139548e99b`
Guide (#1393, #1394): one agent for all UI work as a trial, and every claim of a decision cites the decision log.

## 2026-10-30 09:20:39 EDT — scribe `9851db98e3fec215db094bdf89d719f3106d143f`
Fix (#1394): only a message whose origin is human counts as typed words; pasted text is taken out.

## 2026-10-30 09:14:56 EDT — scribe `b6ee9429175b8b13818ae37c8aa03eae14491cdc`
Feature (#1394): scribe decision: an entry stands only on spoken or typed words the machine copied.

## 2026-10-30 09:14:56 EDT — scribe `433218b1576adbc48ea701dd8c896fba0c200ce1`
Schema (#1394): decisions, on sourceMoments, never deleted (ADR 0103).

## 2026-10-30 04:52:13 EDT — scribe `5929f47f1eb23fc934f5e55767ac27842a7454b1`
Fix (#1343): the app holds the window's appearance through the system's app-switcher snapshots, cutting main-thread work at a move to the background.

## 2026-10-30 04:05:50 EDT — scribe `623cfdaf16e7dcb9263ee7700554b5f574ed0980`
Green (#1376): the live transcript draws one row per line and pins the speaker's name itself, because SwiftUI's lazy stack walks every Section on each placement.

## 2026-10-30 04:05:50 EDT — scribe `747c8d409c3e613a01e69ec3783b98cabf4db5c9`
Fix (#1376): a jump to a line settles with a second scroll on macOS 26.

## 2026-10-30 03:39:29 EDT — scribe `6ccf7ebb546181805871393f7640110a4c97508f`
Fix (#1386): a post's name never waits on ps, and a post over 5 s says which step took the time.

## 2026-10-30 03:26:52 EDT — scribe `224726a91fc5b075e9b043e89083014cdff28f2e`
Cut (#1236): build 178.

## 2026-10-30 03:26:52 EDT — scribe `5d4fa1919e60316e17ee22c47adf037a248a92be`
Green (#1236): the keeper waits for the signed-in connection, uses the device's rows when the server is slow, and looks again a minute later.

## 2026-10-30 03:26:52 EDT — scribe `5f60a275f8c9f78ed9a81641a383772d79c6d80b`
Red (#1236): a launch that finds audio not in storage looks once more a minute later.

## 2026-10-30 02:26:04 EDT — scribe `e8b3d331fc06858acde001e60313446d89102d43`
Fix (#1343): the slow-turn stack reader stops the thread for its walk and reads through async frames, so a running main thread's stack reaches its root.

## 2026-10-30 00:45:51 EDT — scribe `274a1878d0ab4102265e760973a5287b2ac7acf5`
Ledger (#1236): the change-log entry for the keeper's storage read.

## 2026-10-30 00:45:51 EDT — scribe `6a948f5a00078f3204618cbb981381df6e800e5c`
Cut (#1236): build 177.

## 2026-10-30 00:45:51 EDT — scribe `7a3a6f79542b7fa0a6cb19c94f6fa2608e1addda`
Green (#1236): the kept-copy keeper reads storage from the device's audio rows and the server's, under the five-second bound.

## 2026-10-30 00:45:51 EDT — scribe `f25b4adab51114863f89334d64d98e4aca54392f`
Red (#1236): the keeper's storage read merges the device's rows and the server's.

## 2026-10-30 00:45:51 EDT — scribe `218f6d3f4e86110a3b4f559a7cb568a6a194a175`
Cut (#1236, #424): build 173.

## 2026-10-30 00:24:53 EDT — scribe `5799c5f2370eef885f4e71ac816b3a741eac0684`
Cut (#1367): Scribe 0.1 (176), whose story is one speaker per phrase.

## 2026-10-30 00:24:53 EDT — scribe `ee033ef990828c2784844f42a8a16a89aab71fbc`
Test (#1367): the phrase tests compare with expectNoDifference.

## 2026-10-30 00:24:53 EDT — scribe `ba3736d5acd945d28e05b9554ab7cfe9947164fc`
Docs (#1367): audit of speaker over-splitting and ADR 0096 amendment E: the speaker changes only at a pause.

## 2026-10-30 00:24:53 EDT — scribe `dd695678ee7bb975751c272ae8ae4c9c41abb637`
Green (#1367): one speaker per phrase; a final's words are grouped at 0.25 s pauses and each phrase takes the slot most active over all its frames.

## 2026-10-30 00:24:53 EDT — scribe `6c579b1a0bb22e8e6dd86cfcfcb916c9aa0cf6bb`
Red (#1367): a sentence without a pause keeps one speaker; an opt-in replay suite counts speaker switches without a pause.

## 2026-10-30 00:19:39 EDT — scribe `785d7952840c0d60a47b44fcaf20ed8dbce3f7f1`
Green (#1343): the slow-turn sampler keeps 256 frames a sample, counts cut-short samples, and names the samples off its heaviest path.

## 2026-10-30 00:19:39 EDT — scribe `642eccddace177ee2709ba270c693c1395386a3f`
Test (#1343): the main-thread tests run one at a time; the deep test asks for the whole path.

## 2026-10-30 00:19:39 EDT — scribe `f43673e83e6bde936e11871f484ed2986ac0a2dc`
Red (#1343): a deep main thread is sampled to its root; cut-short samples are counted.

## 2026-10-30 00:19:39 EDT — scribe `e0475e34426be177d1f764fb8ce20034eb9cfa1a`
Red (#1343): a slow turn names the samples off its heaviest path.

## 2026-10-30 00:08:52 EDT — scribe `577005270d7d6d33f34c38770e5f176078a07aad`
Docs (#1339): What's New for the next build: hear a speaker before naming them.

## 2026-10-30 00:08:52 EDT — scribe `927ec80c0ea1d6f899cf396fcb63a756b695c0db`
Green (#1339): the naming sheet plays a few of the speaker's lines, each alone; Play on a suggestion; Play This Line in the line menu.

## 2026-10-30 00:08:52 EDT — scribe `4ddecc5f06cf2f958eded43b4b7dbfe220356854`
Red (#1339): tests for the naming sheet's voice lines and both Play paths.

## 2026-10-30 00:06:08 EDT — scribe `731abe4aceebc8474a62379e677f7bd2aa7ad0e6`
Ledger (#1236): What's New and change-log entries for the compressed copy as the audio that travels.

## 2026-10-30 00:06:08 EDT — scribe `775f8b1e3db1903684350f3b4586853b338dcda7`
Docs (#1236): the exact path's word error rate and voice prints; the decision record's step for the kept copy.

## 2026-10-30 00:06:08 EDT — scribe `16ce77dc5a464323680c908df5648f6a471c31f4`
Green (#1236): a finished recording keeps its AAC copy once storage holds its WAV; continuing it restores the WAV from the copy.

## 2026-10-30 00:06:08 EDT — scribe `228d2cdeed168315b6417c720c35824612e2cb57`
Red (#1236): the kept copy's decision table, its encode and retire, and the restore on continue.

## 2026-10-30 00:06:08 EDT — scribe `8f2a3185f77163857d1894650f51085b4e14f12d`
Docs (#1236): the feature contract and decision record: the copy at 48 kbps is the audio that travels.

## 2026-10-30 00:06:08 EDT — scribe `3fa57fcbfc914f2840ccfa85f762cac61be04a0c`
Green (#1236): the copy at 48 kbps; a stream keeps its starting format; Stop sends no whole file when the copy reaches the end; no live chunks while the copy carries the audio.

## 2026-10-30 00:06:08 EDT — scribe `35ae26ab32c460113d79f2b83f6fe53d8690a749`
Red (#1236): the copy's format, its finished state and wake, the Stop decision, and the chunker's switch.

## 2026-10-30 00:06:08 EDT — scribe `5417d4f7fbebf198369dcd1214f92b776c0b6811`
Ledger (#1236): change-log entries for the schema value, the desktop decode, the catalog and the installer.

## 2026-10-30 00:06:08 EDT — scribe `35527e4ff29f5631f2caf8d925b682b2fd88d99b`
Fix (#1236): the share scrubber's installer ships the copy reader.

## 2026-10-30 00:06:08 EDT — scribe `143239c7aeb135d7da2ffb83015f93e88242ce98`
Fix (#1236): the catalog takes the copy only when no chunk exists, and never overwrites the chunk cache.

## 2026-10-30 00:06:08 EDT — scribe `57c7d5012bd5188b0c8ff49753f6e3ff5972a49b`
Feature (#1236): the catalog signs a live recording from its compressed copy.

## 2026-10-30 00:06:08 EDT — scribe `b5fbedc7b7bab24b81a371dbf37221c8b7ce9d65`
Feature (#1236): the desktop mirror decodes the compressed copy into its WAV and attaches it at Stop; the scrubber reads a live share from the copy.

## 2026-10-30 00:06:08 EDT — scribe `03118f9c4ccd330ffcf36aca2b0d16ebcb0705e3`
Schema (#1236): the audio row's upload kind gains compressedStream.

## 2026-10-30 00:06:08 EDT — scribe `fa7dc161eac2e206b8459bb5422adf65e74c4444`
Plan (#1236): the compressed copy as the audio that travels; claims.

## 2026-10-29 23:43:45 EDT — scribe `38c6225bc4fc1af6d38b50ccc73ec5a3e8ea4390`
#1377: the audit gains the like-for-like test diffs and the build 172 install; the claims are released.

## 2026-10-29 23:43:45 EDT — scribe `db15f7c866703c91baee4c9d1bc718965b8c37da`
Cut (#1377): build 172: a recording that cannot start its microphone behind another app says so at once and resumes in front.

## 2026-10-29 23:31:26 EDT — scribe `93eddaf55b2acad2596f1a226d2e34d99887b641`
#424/#921: What's New for build 173: pasted links and book pages as cards.

## 2026-10-29 23:31:26 EDT — scribe `bab7617299cfb7b93d6ea923e7d09be591953b9b`
#424/#921: merge: a link in a thread or on the timeline is its card (a YouTube video that plays in Scribe Playback, a book and each page read, any page's Open Graph), fetched once per link and cached.

## 2026-10-29 23:31:26 EDT — scribe `3629118e957f1a7a77da38e3bab0ab2180c85481`
#424/#921: green: link cards in thread answers, messages, statuses, the live answer card and the timeline; Scribe Playback queues a card's video.

## 2026-10-29 23:31:26 EDT — scribe `aa2e9d5958a8ec5585a4275376b9f4fe302031fb`
#921: green: a book page's status carries the page's books link, so the app draws each page as a card.

## 2026-10-29 23:28:48 EDT — scribe `f69f746304afb3c08f3817d6889256c77c1b9ab8`
#1378/#1383: the audit and progress for builds 171 and 172 on the iPhone: the 7,602-write backlog drains after the relaunches, no deferral expiry; the line lag after the drain is not measured yet.

## 2026-10-29 23:27:35 EDT — instant-data-swift `2be4e25dc7c97942d038c7737130864dd2d7c420`
#1383: v1.9.52's release note gets the whole-bundle result (1,599 tests, one unlisted decode timing ratio) and the device drain.

## 2026-10-29 22:41:44 EDT — scribe `b90ac545d42a4989ae4969286b7084da20c746bf`
#1377: merge: a recording armed while the app is not in front waits for the app in front, says so at once, and resumes there.

## 2026-10-29 22:41:44 EDT — scribe `b4488355b54edb691609db209287dd0bbf1b6608`
#1377: the audit, ADR 0011's amendment, What's New and progress for that change.

## 2026-10-29 22:41:44 EDT — scribe `128317446f749dcb18c6739ad130c7873d874d7a`
#1377: green: the recording asks whether the app is in front when its audio-session listener arms; a refused start behind another app waits for the app and alerts at once.

## 2026-10-29 22:41:44 EDT — scribe `d1ee8f35bd862dd8ed47c7a8ec79fb3e2f5e6369`
#1377: red: tests for a recording armed behind another app, the failure read again, '!int' with and without an interruption, and the alert at once.

## 2026-10-29 21:48:10 EDT — v1.9.52 (sync-jam-1378, #1383): a slow server frame that keeps working keeps its acknowledgement claims

- **Release:** `docs/releases/v1.9.52.md`, cut at `00b245bc` (plan `8c6de2be`, red `17149a7e`, guard `cda06974`,
  green `00b245bc`), carrying 1.9.51; also `6388bd37` (1.9.51's release note gets its whole-bundle result).
- **Why:** frames past the 120 s deferral replaced the session and dropped the rebase, so a relaunch with a large queue
  never drained (#1383). **Next:** Scribe build 171.

## 2026-10-29 21:19:26 EDT — v1.9.51 (sync-jam-1378, #1378): a server fact on a slot no pending write sets, and the store leaves empty, is kept without the rebase

- **Release:** `docs/releases/v1.9.51.md`, cut at `c133c598` (plan `676f56a5`, red `19c0b3ca`, green `c133c598`),
  carrying 1.9.50. No migration, no public API change.
- **Why:** every frame restating a new list-preview entity declined the reduction on an unset field restated as null,
  so one device's queue grew 29 -> 4,000+ in an hour (F65's spiral, second trigger).
- **Checks:** see the release document. **Known:** #1383. **Next:** the Scribe pin and build 170.

## 2026-10-29 21:19:26 EDT — scribe `71a6175044962f7448728d67037be419fa3fe583`
#1378: What's New opens Build 170 (next) for the instant-data-swift 1.9.51 pin.

## 2026-10-29 20:44:45 EDT — scribe `8457c5ed441b7a77bd61517bdd026402ecc224bc`
Cut (#1371): build 169: turning the phone keeps the live transcript.

## 2026-10-29 20:44:45 EDT — scribe `44ceff319009d0f1fd339a06b70caccbbba0fc87`
Green (#1371): the recording screen keeps one layout container across a turn, so the transcript keeps its identity instead of being rebuilt.

## 2026-10-29 20:44:45 EDT — scribe `959f2612f29469c434ccfc7ac8b9a20e0c0dc52d`
Red (#1371): a layout-harness test that the transcript's scroll view survives a turn.

## 2026-10-29 20:44:45 EDT — scribe `917bb6efc7eec4191f3aa631dfdedfa62ec98453`
Green (#1371): each recording keeps one log-only, synced row a minute of the app's own CPU, heat and turn.

## 2026-10-29 20:44:45 EDT — scribe `fb1ad16599d34b609ff7907a76ead955e7a7b140`
Red (#1371): the per-minute CPU and heat row's meter, sync and log-only tests.

## 2026-10-29 20:44:45 EDT — scribe `c3055ea160b432ee9948b74acff6f9bbf588ef2d`
Green (#1371): the Mac mirror writes the per-minute CPU and heat rows.

## 2026-10-29 20:44:45 EDT — scribe `eab00f777b92371b271f0df322c2ec44506fa5fd`
Perms (#1371): production accepts the deviceMinute runtime-event kind.

## 2026-10-29 20:43:09 EDT — scribe `2f8c9a2447b7651d69fa999691a574e6aacf54e3`
Ledger (#1372): the change-log entry for mapping the recognizer's unknown token to text.

## 2026-10-29 20:43:09 EDT — scribe `2aade7eb1a7c7e3e22f3ca85d3c7d18902a01a5a`
Green (#1372): the transcription server maps the recognizer's unknown token to text before any line is written (an ampersand between capitals or between two names; otherwise dropped).

## 2026-10-29 20:43:09 EDT — scribe `2c3491d213a67028723ae4d4e373a0fbcaecc993`
Red (#1372): recognizer output with unknown tokens, as fixtures, reaches lines unchanged.

## 2026-10-29 20:43:09 EDT — scribe `952da6727f347ecc2f8a0ad28d5b525c667001db`
Plan (#1372): the plan and claims for mapping the unknown token.

## 2026-10-29 20:19:09 EDT — scribe `039cf33d6370c6014eba5584ccbe7f679821c401`
References (#1373): a screenshot row on a phone upright and on its side, upright and sideways, every size.

## 2026-10-29 20:19:09 EDT — scribe `cfb60a43e9c236f7e68d492f95929d9f01b6327f`
Docs (#1373): ADR 0055 records that a picture's slot takes the picture's own shape.

## 2026-10-29 20:19:09 EDT — scribe `3b38d6f75771ac013719522ed86e9440afe22264`
Green (#1373): a picture under its timeline row takes its own shape from its file's header, so a sideways screenshot leaves no empty block below it.

## 2026-10-29 20:19:09 EDT — scribe `85d9bd8b0d6fbafb68fb9ea36bed7edec59eb0b8`
Red (#1373): a sideways screenshot's slot took an upright shape and left 190 points empty under it in landscape.

## 2026-10-29 20:14:30 EDT — scribe `5c139e59f5e0a9be679029685eb31b16044e05e8`
Green (#1336): the Mac writes its idle stretch and the app in front once per change; a recording lapsing as live and coming back no longer repeats them.

## 2026-10-29 20:14:30 EDT — scribe `8d0f1efe2bb0eabeeeb4dbdf3021dde486932df2`
Red (#1336): restarted Mac context sources repeat the idle stretch and app in front on the same recording.

## 2026-10-29 20:12:46 EDT — scribe `37d4139c8e257c8b3d71f17e4542abda508b334a`
#1366, #1368: cut build 167.

## 2026-10-29 20:12:46 EDT — scribe `9ab4ff16cea7e2d988f3a297ae83557024c738d6`
#1366: change-log entries.

## 2026-10-29 20:12:46 EDT — scribe `2888a2b65cda8563f50d177647abb6d5bab2bb93`
#1366: What's New and progress entries.

## 2026-10-29 20:12:46 EDT — scribe `811c515fb75d648f33b8178ef413e81c45677f9e`
#1366: audit, ADR note and the script that turned the stored upside-down frames upright.

## 2026-10-29 20:12:46 EDT — scribe `d7f3bb84b3576e40a4384f70250d43440e666083`
#1366: green: ReplayKit's sideways screen-frame orientations turn the opposite way from EXIF's.

## 2026-10-29 20:12:46 EDT — scribe `571841a06428b1128f2d29f4baa201474247b9bc`
#1366: red: orientation cases expect ReplayKit's turns.

## 2026-10-29 20:07:16 EDT — scribe `42b042d5319062aa20bde305e02be37324678b2e`
#1331: change-log and progress entries for long-pressing the live screen's frames.

## 2026-10-29 18:51:41 EDT — scribe `82a227fa1a129a1b3f5d70396548ba36d9215e60`
#1331: ADR 0055 amendment: the live screen's frames take the size chosen for Screen Frames.

## 2026-10-29 18:51:41 EDT — scribe `6258ee386ce503277baef926b2017663c525140e`
#1331: green: a long-press on the live screen's frames offers Show Screen Frames As; frames draw at the chosen size.

## 2026-10-29 18:51:41 EDT — scribe `deadceadb913157e46f419741e89af75c206dfcc`
#1331: red: live screen frames are the Screen Frames kind and take a slot per size.

## 2026-10-29 19:10:11 EDT — scribe `eeb38f9750a581541e4caba331dfb572b7c737f9`
Feature (#1332, #1333): the thread a person speaks into shows the line being said as it forms, and its composer listens by default with a keyboard button; the row that covered the newest message is gone.

## 2026-10-29 19:10:11 EDT — scribe `5f8c60bf8ff5cbd050fe5c8b30f6f41673d8faac`
Feature (#1332): the thread composer listens by default (waveform, Listening, keyboard button).

## 2026-10-29 18:55:28 EDT — scribe `4836e767a7bb1902938396cc7544bb1872038081`
Land (#1321): a line only the sound floor opened is re-decoded every second for partials, so speech a speech detector does not hear shows within about a second instead of at its line's end.

## 2026-10-29 18:55:28 EDT — scribe `5a5483b0104098f36b8da8b7e725d0fbc2b426a5`
Docs (#1321): audit section 12 and ADR 0074 amendment H: the sweep of caps and partial cadences, recall, shown latency and decode cost per recording.

## 2026-10-29 18:55:28 EDT — scribe `5a077af1fe74366ab68ea22e5b314a5b598266a0`
Green (#1321): the segmenter honors a slower partial cadence (1 s) for a line only the sound floor opened; every final is unchanged.

## 2026-10-29 18:55:28 EDT — scribe `807880294f2c8514afc9e9cd111b92fccd38bf23`
Red (#1321): a sound-only line gets no partials; the replay measures how soon each word is first shown and fails above 3% of words more than 2 s late.

## 2026-10-29 18:54:34 EDT — scribe `30dd314c11df9aad741c1bb9f14ee8c75a5f6451`
#1344, #1331: merge: the broadcast's screen frames show in a band pinned at the top of the live screen, above the speaker name, never as rows among the words; the band carries #1331's Show Screen Frames As.

## 2026-10-29 18:54:34 EDT — scribe `32b4f851e319b51a2fd575fdd40e6de913f66149`
#1344: the frames' bookkeeping reads each row's case once, never compares the rows (cost test bound).

## 2026-10-29 18:54:34 EDT — scribe `f5ebbf7508c995b4b8eb3c1981f81674512bc4d7`
#1344: green: frames leave the live lines; RecordingFrameBandView pinned above Now Playing and the speaker name.

## 2026-10-29 18:54:34 EDT — scribe `2ce3f5c2b796c2e7d706e3a0807adbefde068adb`
#1344: red: frames are not lines of the live transcript; the band's state follows frames and the clock.

## 2026-10-29 18:26:16 EDT — scribe `6dc3d6bd349bc6202b5628797ab5f956e3b209a3`
#1345: scribe-issues tells agents to include the pictures of the moment (screenshots and screen frames that issues file and mention --said now attach), always for design issues.

## 2026-10-29 18:15:49 EDT — scribe `d613f8f2180c19b9d510e829d56a8f5592b6a6d9`
#1338: green: other devices read the live room beats (the list selects liveRoomKey), and the player reports a wait for audio this device does not hold.

## 2026-10-29 18:15:49 EDT — scribe `4a42107f0182b6457ac7f81d69e55ff5a9cf17dc`
#1338: red: the list selects liveRoomKey, a waiting player says how far the audio reaches, a quiet device's stored copy plays.

## 2026-10-29 17:51:53 EDT — scribe `622ede8052bf60f9b75df7fc26db060d479406d9`
#1342: land: a continued take gives out no line index before this device's store answers.

## 2026-10-29 17:51:53 EDT — scribe `bc40b95c63d559fd520210d0373762550e8e4aa6`
#1342: green: after a relaunch mid-recording, the take holds its new lines until this device's store says where they continue; the wait reports itself every three seconds.

## 2026-10-29 17:51:53 EDT — scribe `cc0b0328b889df7f5c081d3afa5e45b55b24fe7e`
#1342: red: a failed store read is asked again (test compile fix).

## 2026-10-29 17:51:53 EDT — scribe `13c26eebf915c20cf96ee9384db0061ba21b757e`
#1342: ADR 0049 amendment B: a line index comes from the store before the first write, never from the row's count.

## 2026-10-29 17:51:53 EDT — scribe `3e0368757bfad704481e764d0ba015121fe49596`
#1342: red: a continued take from a row without counts waits past three seconds for the store; withheld voice lines wait too.

## 2026-10-29 16:59:10 EDT — scribe `19fb078ac7ec1481af511681451fba998cb50988`
#1347: green: a Photos screenshot or photo sits on the timeline at its capture time, not its pickup time.

## 2026-10-29 16:59:10 EDT — scribe `ab9a838c0a8d3d3e8dc5e410b5d800bb433a3856`
#1347: red: a screenshot sits at its capture time, not its pickup time.

## 2026-10-29 16:55:25 EDT — scribe `458abe373a731a498dd8c1ea4f31677b9d3790b6`
#1367: ADR 0096 amendment D: adoptions reach the lines; the diarizer's short-line mixes, measured.

## 2026-10-29 16:55:25 EDT — scribe `6681b31ab0ca4c7aab8b9006b5a959965d483c90`
#1367: green: the mirror writes a moved line again under the speaker it moved to.

## 2026-10-29 16:55:25 EDT — scribe `c17990eb24d2c4e7d1939989c738b65fb2c24634`
#1367: red: the mirror writes a line again when it moves to another speaker.

## 2026-10-29 16:55:25 EDT — scribe `b7db1a2eec2e6e1f0ea3b3e7f34f214438e2ded5`
#1367: a restarted broadcast voice's adoption moves its lines, as the microphone's do.

## 2026-10-29 16:55:25 EDT — scribe `2ef01163de3e0790797c9109d3005a1a8032ef6d`
#1367: red: a restarted broadcast voice's adoption reaches the recording and moves its lines.

## 2026-10-29 16:55:25 EDT — scribe `73d3c682740cd4f37e64d7fd8a3c6dec8a61b14b`
#1367: a line shifted to the recording's clock keeps the stream's speaker adoption and voice print.

## 2026-10-29 16:55:25 EDT — scribe `cb4dc0787bdd368550599a9ab4abbad2d4e16440`
#1367: red: a line shifted to the recording's clock keeps the stream's speaker adoption, identity and seal.

## 2026-10-29 16:51:49 EDT — scribe `94a01ecf2d3e1306f80f8c8205d7fb9b70e45752`
Merge (#1321): the audit's shipped section onto main.

## 2026-10-29 16:51:49 EDT — scribe `e42a0b9e1eb0a4346454eab00970d01f93d0fe22`
Docs (#1321): shipped: build 162 on the device with the sound floor running, the server at da3dc0ca4.

## 2026-10-29 16:51:49 EDT — scribe `da3dc0ca4490506856748910094eb0da8a2dd3a4`
Cut (#1321): Scribe 0.1 (162): WHATS-NEW story and build number 161 to 162.

## 2026-10-29 15:46:56 EDT — scribe `59bea156327f55930cb5563008a847bcdb2169b3`
changelog(#1348): the ledger for one-run iPhone-first installs

## 2026-10-29 15:46:56 EDT — scribe `85dcefd87d01c3dd76dc4766d1ff5b74c3320737`
docs(#1348): scribe-builds, scribe-install: nothing turns an install into a wait for his go

## 2026-10-29 15:46:56 EDT — scribe `6ed52c9262793cbd254d38906576a8c7533abb3a`
fix(#1348): one installer run puts a build on every device, the iPhone first, behind one drift check

## 2026-10-29 15:46:56 EDT — scribe `5148b323f491dc49b4473cae67fd54ea411a3110`
test(#1348): red: one installer run, iPhone first, one drift check, npm ci in a fresh worktree

## 2026-10-29 14:59:12 EDT — scribe `079ed3f8725be7cc0db0c92f72ff1a4518544db9`
Presence (#1321): vad-fix-1321b's claims released.

## 2026-10-29 14:59:12 EDT — scribe `923988f1826f4685a2446299cc59cf6446634eda`
What's New (#1321): Build 162 (next) story and the progress entry.

## 2026-10-29 14:59:12 EDT — scribe `30a06f653d6ba8ba6a086ff6a15815f391910aa8`
Changelog (#1321): ledger entries for the sound floor, the edge context and a line's own words.

## 2026-10-29 14:59:12 EDT — scribe `02be04cb1f5407c99377390d933b30931036f648`
Docs (#1321): the audit of the sound floor beside the speech detector, measured by replaying a recording through the device stream against references, and the on-device engine ADR's amendment G.

## 2026-10-29 14:59:12 EDT — scribe `e25196c8962e04fa8154c15f86e3b2fdf8b61685`
Test (#1321): audio the voice filter withholds (zeros) never opens on sound; agreed_reference.py keeps the reference words that window-shifted passes of the same recognizer also hear.

## 2026-10-29 14:59:12 EDT — scribe `5c0b6be5f60679ade74b2413b7258c8ef74e5f9b`
Green (#1321): a line at an edge keeps what its decode heard after the previous final's last word; otherwise the edge decides.

## 2026-10-29 14:59:12 EDT — scribe `34c76e9b9fa4618de85e9b968623afacf3502a8d`
Red (#1321): two edge-context tests: a word the previous final dropped at its end, a word timed across a cut.

## 2026-10-29 14:59:12 EDT — scribe `c21fe217d406987cd929fd357ea0a2d5465fdcc1`
Green (#1321): on the microphone a line that starts where the previous final ended is decoded with up to 2 s of the audio before it (no extra decode) and keeps its own words.

## 2026-10-29 14:59:12 EDT — scribe `291293f0d994eed1a9070212d1fe3b80fe0b4330`
Red (#1321): edge-context tests: a line decoded from a decode that began before it keeps only its own words.

## 2026-10-29 14:59:12 EDT — scribe `453efd1ff13332c5cb06d5a148d15533f2fe4dd0`
Green (#1321): on the microphone a 256 ms step at -50 dBFS or louder opens an utterance the speech detector heard no speech in, decoded once at its final; quiet for the endpointing ends it; the detector still starts and ends the lines it hears; the logs name the floor.

## 2026-10-29 14:59:12 EDT — scribe `618e62ca2fdc5cb2cdc45f52a5a9dc5ba0d78fc9`
Red (#1321): sound-floor segmenter tests, the microphone-only wire option, a word-recall scorer, and an opt-in replay of a recording through the device stream scored against a reference.

## 2026-10-29 14:25:57 EDT — scribe `4b25d489b2849deaa256831632f9afa43a14dd05`
Cut (#1335): Scribe 0.1 (161): WHATS-NEW story and build number 160 to 161.

## 2026-10-29 14:25:57 EDT — scribe `13cd20014b4172fc05411cee00e31aa82c8bbb7a`
Presence (#1335): answers-thread-1335's claims released.

## 2026-10-29 14:25:57 EDT — scribe `7fec0744ee738ccc48b03a09a910ade9587365fe`
Changelog (#1335): ledger entries for the Answers thread fix.

## 2026-10-29 14:25:57 EDT — scribe `f9ad7bdb599f7522834525f3033b586d14eb6b97`
Fix (#1335): Answers lists every thread with no answer, on a line or not, newest activity first.

## 2026-10-29 14:25:57 EDT — scribe `3f952576fabc19b841b77683af97372b270918a8`
Test (#1335): a thread on a line spoken into before its answer shows in Answers, newest activity first.

## 2026-10-29 14:08:30 EDT — scribe `eff0f1353456e1c3c0502d7eddd2b5b3686b92a5`
Docs (#1343): the audits index says stall-1343 is in build 160.

## 2026-10-29 14:08:10 EDT — scribe `7e681826c4548b56f4ed89e2145be5816685282e`
Progress (#1343): PROGRESS entry; audit section 7: 159 did not install (the reader did not compile for watchOS), 160 carries #1343 and launched on his iPhone 13:55:18.

## 2026-10-29 12:40:24 EDT — scribe `38c2eed1414cdf4bebac53d75cb77c4564d9311e`
Docs (#1343): WHATS-NEW Build 159 wording: the 2.7 s freeze came on a return to Scribe.

## 2026-10-29 12:40:06 EDT — scribe `fbe754210269f21c161682734bea216d725695c4`
Presence (#1343): stall-1343's claims released.

## 2026-10-29 12:38:37 EDT — scribe `df8aeb56850d795b170f7b0833124bdd7c57b742`
Test (#1343): a watchdog started on the main thread reports a 1.8 s block of it once, with the main thread's stack.

## 2026-10-29 12:36:20 EDT — scribe `bfcc606d4e6c994fa191958c997998a03921f34f`
Docs (#1343): audit section 4: the reader's fault-safe reads.

## 2026-10-29 13:54:59 EDT — scribe `953974da7d77ffe468fe14d961073ab5103d8122`
Changelog (#1357): the ledger entry for the share check's blocked causes.

## 2026-10-29 13:54:59 EDT — scribe `074b58c1a01258fa2be5f272c7e57b670db80281`
Docs (#1357): the mini got the invalid name mapping from the 10-29 02:33 install.

## 2026-10-29 13:54:59 EDT — scribe `69f0da5a17f420c5089db5de40d7a138b39e1253`
Fix (#1357): a share the privacy check could not run on says which file stops it and its fix, and is checked again once fixed; heartbeat checksBlocked.

## 2026-10-29 13:54:59 EDT — scribe `d337e6320230aad948cc1a169a76def1f78ff7a4`
Test (#1357): red tests for blocked share checks, their reasons and the retry.

## 2026-10-29 13:11:50 EDT — scribe `cae1e1686912302c83baefb0de0b415e644b5738`
Merge (#1348): the Mac's Answers window, its notification click, a Mac left alone posts answers quietly; on main.

## 2026-10-29 13:11:50 EDT — scribe `f758c2467e60a47b995a8f050b8b22be479f4621`
Fix (#1348): Answers loads older answers as the last row comes into view, never from a Show More control (#299).

## 2026-10-29 13:11:50 EDT — scribe `525e2eb6c6513aa0f3b8f536d33713eb54c3c8da`
Fix (#1348): the green compiles (bare-executable client, the post a let, CasePathable delegate); 139 + 12 tests pass.

## 2026-10-29 13:11:50 EDT — scribe `3cf05421e90616b12217ab817dfefedb9e9b916d`
Docs (#1348): ADR 0029 section 9: one place on the Mac, a click opens it there, which device rings, 35 of 35 answers on both within 5 s.

## 2026-10-29 13:11:50 EDT — scribe `831142b7ef67dfe7e5187566f182c0122cec3810`
Green (#1348): the Mac's Answers window lists every agent answer across recordings; its notification click opens it there.

## 2026-10-29 13:11:50 EDT — scribe `e0e57ea8499a57c14d3c890b203cd040522e63b9`
Red (#1348): Answers lists every agent answer and the work under way across recordings, newest first.
## 2026-10-29 12:35:05 EDT — scribe `2e323192f11c22094b5e59392e0634a9fcb9b11e`
Change log (#1343): red 3ea3993a8, green 032e3727e.

## 2026-10-29 12:34:40 EDT — scribe `032e3727ef83d900e8758eb5a6f244061c6274a6`
Green (#1343): the stack reader reads each frame record with vm_read_overwrite, so a stray frame pointer ends the walk instead of faulting (#1285); 100,000 reads at 3,545 ns, flat.

## 2026-10-29 12:32:06 EDT — scribe `3ea3993a8c53c594d1b764acd0997c74b9b05b5a`
Red (#1343): a frame record with no memory behind it must be no record and no crash.

## 2026-10-29 12:29:52 EDT — scribe `75437a0a4ab50a5aaf499eea72c4c6f2b41f44f5`
Cut (#1343): Scribe 0.1 (159): WHATS-NEW Build 159, project.yml 158 -> 159.

## 2026-10-29 12:28:25 EDT — scribe `2a217364ab7b8557b752059d3abab130870fe7b6`
Docs (#1343): audit 2026-10-29-stall-1343: builds 156-157's scene-change stalls are not a 156 regression (155 did the same main-thread work per move; the stalls came at thermal serious); the phone holds no stack for them.

## 2026-10-29 12:28:25 EDT — scribe `db3c7e1cac4662fafec6ff063816d3aeedd0eb33`
Change log (#1343): red 86f0e3cb7, green 9b5cfc9aa.

## 2026-10-29 12:27:29 EDT — scribe `9b5cfc9aa3456ad19f5b964e773be74d7fd4d0c2`
Green (#1343): the photo sheet's camera keeps its preview through a scene change and runs again after it (no AVCaptureVideoPreviewLayer.setSession on the main thread at a move to the background); the stall watchdog samples the main thread's stack in every turn of a second or more and logs watchdog.main-thread.slow-turn.

## 2026-10-29 12:27:28 EDT — scribe `86f0e3cb751bd6e5be068ac07f646dc9f12aa9cf`
Red (#1343): after an interruption ends the photo sheet's camera stays paused; the watchdog has no reader of the main thread's stack.

## 2026-10-29 12:05:53 EDT — scribe `af13d93333928c7fad0b863fd5fa37655da406ba`
Plan (#1343): 2026-10-29-stall-1343; claims.

## 2026-10-29 12:06:07 EDT — scribe `0092bf1ce97c0bf8cc5542be6b40ad24ae8fd143`
Docs (#1349): scribe-listener skill: scribe speaker NAME; never grep transcript.md for [Name].

## 2026-10-29 12:06:07 EDT — scribe `9c6a73ae554196104122f64f135dd1ab41680953`
Green (#1349): scribe speaker NAME, one person's lines across recordings, confirmed names and (Name?) guesses apart.

## 2026-10-29 12:06:07 EDT — scribe `1d956ea2d9147c76d9d9eb8b2c443e39e510e510`
Red (#1349): scribe speaker NAME finds one person's lines across recordings.

## 2026-10-29 11:31:08 EDT — scribe `6067ba4b793aa808fdbfdc526b69e8a573eb2d7e`
Merge (#1337): a recording delete goes to Recently Deleted at once, with no confirmation dialog.

## 2026-10-29 11:31:08 EDT — scribe `068b40b69176a8541b42641860f4d28dd70bb71b`
Green (#1337): the recording delete dialog is gone; Undo and Recover bring a deleted recording back; FEATURES.md item 31.

## 2026-10-29 11:31:08 EDT — scribe `99f84e7b3190116ed48e53d6c5e26b11dd5785f8`
Red (#1337): a recording delete moves to Recently Deleted at once, with no dialog.

## 2026-10-29 10:41:34 EDT — scribe `13e3d9c088108b6ecc4fd8d63c0b79d912ef56f2`
Cut (#1331): Scribe 0.1 (157), long-press a picture in a recording to choose its kind's size.

## 2026-10-29 10:41:34 EDT — scribe `1a13494eab4e298cc1d5078c6b9520304f7860d5`
Changelog (#1331): red, schema and green entries.

## 2026-10-29 10:41:34 EDT — scribe `6bb90b66723a588c27b489c7e67a14d5d3e1d3d3`
Green (#1331): a long-press on a timeline picture shows its kind collapsed, as a thumbnail, medium or large, on the live screen and in playback; one size per kind for the account, synced through settingsAccounts.timelineEmbedSizes.

## 2026-10-29 10:41:34 EDT — scribe `e9340dffdea5e315259d536539939c01f7585246`
Schema (#1331): settingsAccounts.timelineEmbedSizes, an optional string of at most 1 KiB; pushed to production, drift 0.

## 2026-10-29 10:41:34 EDT — scribe `6b9f6669ee4bfa504d6f08b2aacecf2bb4b5562f`
Red (#1331): tests for per-kind picture sizes in the timeline and their account sync.

## 2026-10-29 10:23:44 EDT — scribe `dff44d769e0124688aec17fdc1919972a1fd9dda`
changelog(#1334): red a16a2ad05, green cf12ad7f4; plan 33bf77b5e

## 2026-10-29 10:22:46 EDT — scribe `cf12ad7f4a7c34f4d68495035091470b4d856167`
fix(#1334): green: the thread's + opens a photo sheet with a live camera tile and his newest photos

## 2026-10-29 10:22:46 EDT — scribe `a16a2ad05f8391d33ff6e1d7fec9d03b2ecbfaf1`
test(#1334): red: the thread's + opens a photo sheet with a live camera tile and his newest photos

## 2026-10-29 10:22:38 EDT — scribe `33bf77b5eb2010929e7e4e4f273bf022204b0433`
plan(#1334): 2026-10-29-photo-picker-1334, the thread's + opens a photo sheet with a live camera tile and his newest photos; claims

## 2026-10-29 02:51:07 EDT — scribe `347d4f1f5dd7669372ef2954ec3b7d8f510c5b78`
Changelog (#1325, #1327, #1328): build 155 cut 0318c75c7.

## 2026-10-29 02:50:23 EDT — scribe `0318c75c753c864728878963e6ee2314f7aca7de`
Cut (#1325, #1327, #1328): Scribe 0.1 (155) and Scribe Playback 155; four files; installed on iPhone, iPad, Watch and Mac 03:02-03:16.

## 2026-10-29 02:10:14 EDT — scribe `ea7fc219e388ee615b61af98cb4ef844882910fc`
Changelog (#1325, #1327): red/green pairs, the Swift guard and the ADR 0064 amendment.

## 2026-10-29 02:27:55 EDT — scribe `f1826c70f9d7699b9a9ed6cc20764ca3eae22693`
Docs (#1328): Scribe Playback's Build 155 story names what #1328 measured.

## 2026-10-29 02:27:45 EDT — scribe `942eb264ffaf6840c0d449104392cdde94c46b30`
Docs (#1328): Scribe Playback's What's New: Build 155 (next); #1328's pin rule reaches Scribe Playback, so 155 rebuilds it.

## 2026-10-29 02:11:28 EDT — scribe `9b50740ed205d6ebf080040c9f67b2952ca27c26`
Docs (#1325, #1327): What's New: Build 155 (next) opens with SharePlay's and the share sheet's stories.

## 2026-10-29 03:03:11 EDT — scribe `3a2173a6c0fcce46a0d1e0806a35a466095a231f`
Merge (#1324): red 9fd245d84, green 76b4c33ec and changelog 2e64f3612 onto main.

## 2026-10-29 03:02:56 EDT — scribe `2e64f3612d0e1d45ed1cfd23b87d9ff3739f6c35`
Changelog (#1324): red 9fd245d84 and green 76b4c33ec in CHANGELOG.md.

## 2026-10-29 02:54:05 EDT — scribe `76b4c33ec6951d3b40dc017cf0dc2adc98f0de2e`
Green (#1324): the stream agent (watch, interact, ask), the follow-along tail and the voices backfill skip retired transcript lines: the agent's reads select the retirement and the seal and move their cursor past a retired row as a words-free frame; the tail never prints a retired line, says segment.retired once for a line it may have shown, and reads a full one-version page again larger so a bulk retirement never stops it; the backfill never hears a retired line.

## 2026-10-29 02:54:05 EDT — scribe `9fd245d84b57a788ac713c60aa632f4f49f0ae63`
Red (#1324): 19 tests (7 agent rows and cursors, 2 query plans, 7 tail, 3 backfill) fail for their reasons; synthetic rows.

## 2026-10-29 02:53:03 EDT — scribe `78fe236cdcccdf3400209db0a26eb4fc65a5ce1d`
Claim (#1324): TranscriptLineReadersTests.swift, its six #1324 known exceptions.

## 2026-10-29 01:35:57 EDT — scribe `416af3522e2ea519f7e8d8c32362e2954143c9ec`
Plan (#1324): 2026-10-29-stream-1324, the stream agent, the follow-along tail and the voices backfill skip retired lines; claims.

## 2026-10-29 02:50:55 EDT — scribe `322bb5f552b89509bc6437542ff1d7d1d7107163`
Changelog (#1329): docs 74ea164c1 in CHANGELOG.md.

## 2026-10-29 02:50:46 EDT — scribe `74ea164c15ed11ddc09b4f5331189a1364150a61`
Docs (#1329): ADR 0014 section 14.3, a share's scrubbed copy follows its sources: the rule at every copy write, the follower's look and sweep on every kind of share, sealed clips, shareScrubbedLines.wordsSeal, and what was measured.

## 2026-10-29 02:46:51 EDT — scribe `b6c6d2aa9926a7bb0c09e59da54a41651cc0f5b6`
Changelog (#1329): red 53695d7ef and green 8d01d8c66 in CHANGELOG.md.

## 2026-10-29 02:45:42 EDT — scribe `8d01d8c66fde245fac91498eb81b6031d5c29fa9`
Green (#1329): the share scrubber's follower asks Instant one query per idle look (every followed recording in one or of windows; rows already held against the copies are not asked about again) and a few per sweep (copies, section lines, whole recordings five to a query, strays); the first sweep comes 15 s after start and a failed one is tried again after 30 s, doubling to 10 min. Its first sweep on production had met the rate limit.

## 2026-10-29 02:36:48 EDT — scribe `53695d7ef84aad93f01d12af3e05410617b20e35`
Red (#1329): an idle look over four shares asked 4 queries (want 1), a sweep of four asked 9 (want at most 5), and a failed sweep waited 10 min (want 30 s, doubling); stubs answer as before.

## 2026-10-29 02:32:09 EDT — scribe `65b7caeee259aae301fdfb8abec52799a9b0ee13`
Changelog (#1329): red 1763777bc and green 1adfa0627 in CHANGELOG.md.

## 2026-10-29 02:30:46 EDT — scribe `1360603a0b5ae189fe5ecf5c4d9e03b857803dd0`
Test (#1329): the share rules matrix's sealed copies (a link holder reads a place and a seal, never words; the rules refuse words beside a seal), 49/49 on the throwaway app, and the follower's proof there (scripts/scribe-scrubber/follow-proof.ts): one look takes a retired line out of a sections, a whole-recording and a legacy share and copies a sealed one sealed; the sweep catches a retirement with its old stamp.

## 2026-10-29 02:30:46 EDT — scribe `1adfa062743fe46621570a30f61512012e5aa12a`
Green (#1329): a share's scrubbed copy follows its source line's retirement and seal, on every kind of share: the scrubber reads every line with the rule's fields, re-reads its retirement and seal inside the share's lock at every write of a copy, follows every readable share every 2 s and sweeps every copy every 10 minutes, mutes sealed lines in clips; shareScrubbedLines.wordsSeal and its rule pushed to production 02:30 EDT (drift 0).

## 2026-10-29 01:47:36 EDT — scribe `1763777bc3e505a7f6a24c45311077e98fbda7ff`
Red (#1329): 24 tests: the rule at copy time, the follower on every kind of share, sealed clips, live shares, the scrubber's guard (every read selects lineFields) and the schema's wordsSeal.

## 2026-10-29 01:38:11 EDT — scribe `298b156de14165991563e7efef9c5093619ae5d4`
Plan (#1329): 2026-10-29-scrub-1329, a share's scrubbed copy follows its source line's retirement and seal; claims.

## 2026-10-29 02:25:14 EDT — scribe `7d8e954587eb72d964d6be5a9c63cbf1ac3f87b7`
Changelog (#1328): red ecd982811 and green 3a48e5140 in CHANGELOG.md.

## 2026-10-29 02:24:02 EDT — scribe `cd7b41a6d1d3950c3c8aa0bebf8f7b5f26a56b5e`
Docs (#1328): What's New Build 155 (next): the playback opens with its first speaker named once at the top.

## 2026-10-29 02:23:02 EDT — scribe `3a48e51408a03a69c3a32e53cab231ef83e4b663`
Green (#1328): a recording whose first line starts a speaker's block opens its playback with that speaker named once (build 154's Mac pinned the name over the first row's own at offset 0); the pinned name takes over once that name scrolls away, and #992's hand-over is unchanged. Scribe Playback's media timeline shares the rule.

## 2026-10-29 01:51:17 EDT — scribe `ecd982811fa65008fc5490593501940c2e492e86`
Red (#1328): at the Mac's, iPhone/iPad's and AX5 metrics, and in the Mac's real playback window, a first row at the top of the words pins nobody; stubs answer as before.

## 2026-10-29 01:07:33 EDT — scribe `8bcb3bc03b47033256729f475f2090bc51edf827`
Plan (#1328): 2026-10-29-pin-1328 and its claims.

## 2026-10-29 02:05:53 EDT — scribe `bc63f2b84275add43ee4e1ffe259970fea4099f8`
Docs (#1325, #1327): ADR 0064 amendment: the readers #1317 left, one rule per language, and the guard.

## 2026-10-29 02:05:45 EDT — scribe `1f9a43e7335a697c0cf864ce0d4f4f3a2531b34c`
Test (#1325): the Swift guard TranscriptLineReadersTests: every reader of lines names the line rule or says why not; proven on a scratch branch.

## 2026-10-29 02:05:45 EDT — scribe `d637c6194612f5be680a74d5d88718000cf0ecf6`
Green (#1327): the range picker selects retiredAtMs and wordsSeal and lists no retired line; sealed lines drawn sealed; a share is named by its first kept line.

## 2026-10-29 02:05:45 EDT — scribe `6457f5706b56b06b3743a61604721896d09337e7`
Red (#1327): the share sheet lists no retired line and draws a sealed one sealed; the Shares list never names a share by a retired line.

## 2026-10-29 01:17:50 EDT — scribe `2734b37bb61298bf937870471a30bde881bdbea9`
Green (#1325): SharePlay reads through the timeline line rule; a retired row is a skipped cursor DurableCursorDrain moves past without sending; a sealed line goes sealed without words or envelope (RecognizedSection.withoutSealedWords).

## 2026-10-29 01:17:50 EDT — scribe `d10d5e4e3627a219f7ed365469b28cad7055a73d`
Red (#1325): SharePlay sends no retired or sealed line, and a run of retired lines never stops the drain (10 new cases fail for their reason).

## 2026-10-29 02:03:37 EDT — scribe `da61ec71319fb5851a460e028d9f42fd95d79e6f`
Changelog (#1323): the red, green and docs commits of the CLI, Mac scripts and mirror retired-line fix.

## 2026-10-29 02:02:39 EDT — scribe `4c1414e3e64194fee1250e4862ba96293fe95b62`
Docs (#1323): ADR 0064 amendment: one rule per language with a guard each, a # naming its kept line, the mirror's transcript files written again when a written line is retired, and a 5-minute look for retirements in folders the mirror does not follow.

## 2026-10-29 01:52:31 EDT — foldkit `b60b9df628b0c58f4f052a58833afd4a6052591b`
Green (Scribe #1323): issues --said never quotes a retired or a sealed Scribe line; installed as the issues CLI 1.6.1.

## 2026-10-29 01:52:28 EDT — foldkit `c7691347e806d70f3c142fa6e1e32ac7c5a3d084`
Red (Scribe #1323): issues --said quotes a retired copy written after its kept line, and a sealed line.

## 2026-10-29 01:45:59 EDT — scribe `5594e56e20aa38a9a481ef84fe77d8055fcdb46e`
Green (#1323): scripts/media-transcription/transcript_lines.py, the one Python rule for his lines; every Python reader goes through it.

## 2026-10-29 01:45:57 EDT — scribe `b551e4342c3274f9c3d397ce896e91dae6840864`
Red (#1323): the Python guard (9 problems in 4 readers on the old code) and the rule's tests.

## 2026-10-29 01:40:30 EDT — scribe `dcdd5a0eb8417907ed57bfd006861d759d6e7428`
Green (#1323): the Mac scripts (topics-tagger, youtube-companion, qa-backfill, triage-import, debug tools) read his lines through model.ts's rule; installers carry it.

## 2026-10-29 01:40:30 EDT — scribe `9d0b111d3aa7c15b254d7b39805f592d50c5fd20`
Red (#1323): the TS guard (20 problems in 18 readers on the old code) and the scripts' tests.

## 2026-10-29 01:29:32 EDT — scribe `3234f4a4be6d7067b40aec452a4844cc567073d7`
Green (#1323): one TS rule for his lines in model.ts; the mirror writes its transcript files again when a written line is retired; --segment and --quote take the kept line.

## 2026-10-29 01:29:32 EDT — scribe `373c66c3a94ce867b8efe16d891c527ef927ed8e`
Red (#1323): 16 mirror cases (the rule, the rewrite on retirement, capture, --segment/--quote, the day's read, the transcript.jsonl readers).

## 2026-10-28 23:44:28 EDT — scribe `eccb33a129d7bc2bb266c452f9337fc832a12819`
Changelog (#1317): build 154's cut.

## 2026-10-28 23:44:28 EDT — scribe `4f0fc8afee4ffe96442aca1d638c702e407df76e`
Cut (#1317): Scribe 0.1 (154): a recording's transcript shows no retired line (the Voice Memos' old 30 s lines), and scroll-back still reaches the first line; instant-data-swift 1.9.50 as in 153.

## 2026-10-28 23:09:37 EDT — scribe `e506797be32e087522a8704876135faa6040392a`
Changelog (#1317): red, green and docs of the retired-lines fix.

## 2026-10-28 23:09:37 EDT — scribe `6112ce08daa297fecf60fc2b2f743aa96db1e41e`
Docs (#1317): ADR 0064 amendment (the app's readers skip a retired line; why not a where-clause; the once-per-open read of which lines are retired) and WHATS-NEW Build 154 (next) opened with #1317's story.

## 2026-10-28 23:09:37 EDT — scribe `6b82d7d37b5b8117c13662e1b2572451a071dc39`
Green (#1317): every transcript query selects retiredAtMs (one shared selection, with #1183's seal fields it never sent); a retired row is read first and never wins a shared #; the recording screen publishes no retired section while the row keeps its # for paging; a once-per-open read of which lines are retired covers a store holding lines from before their retirement; Copy Transcript, the playback and list projection, and a person's lines skip them.

## 2026-10-28 23:09:37 EDT — scribe `c5ad9bcea1235d3dac5494e35cc2405767196bbf`
Red (#1317): no reader shows a retired line, and scroll-back over retired lines (a whole page of them too) reaches the first line; the real library's store filters retiredAtMs is null and is not null.

## 2026-10-28 22:58:32 EDT — scribe `8ba10e6095be868fe28aae34a27f4f89fbef3cae`
Changelog (#1319): build 153's cut.

## 2026-10-28 22:58:32 EDT — scribe `1e502d83ab2575cec5ce19ff997cb409a9d90636`
Cut (#1319): Scribe 0.1 (153), instant-data-swift 1.9.50; What's New Build 153 (#1319, #1321); Scribe Playback stays 148.

## 2026-10-28 22:58:32 EDT — scribe `4b9b3728e2cfba725dcd8651c2c8d4a856b39c7b`
Changelog (#1319): red 30500859c, green 6f4ed4fe7.

## 2026-10-28 22:58:32 EDT — scribe `6f4ed4fe72ce97511b7ba4669b788e4e13382014`
Green (#1319): pin instant-data-swift 1.9.50; the StallWatchdog hands each resume to InstantProcessSuspensions; session.health gateStallSuspendedMs; the installer's expected version; audit audits/2026-10-28-gate-1319.md.

## 2026-10-28 22:58:32 EDT — scribe `30500859c6d3ebbf638d1d3b66a1e2aeb7d0f59d`
Red (#1319): session.health had no suspended time beside a stall; the watchdog's resumes never reached Instant.

## 2026-10-28 22:38:19 EDT — scribe `5b4702ed8a692fbf32afa9764748602a0599e945`
Docs (#1321): the audit of a recording's speech the engine never decoded (the speech detector never opened on it), its proposals, and the on-device engine ADR's amendment F (the unopened-audio counters).

## 2026-10-28 22:34:17 EDT — scribe `3deb2af5ab953bfbb8d0b61ea3cf6ff9f871e581`
Green (#1321): every transcription stream counts the audio its speech detector never opened (never decoded), its loud part (a 256 ms step at -40 dBFS or louder) and the longest loud stretch, in the device's per-minute and closing lines and the server's closing log; diagnostics only, the replayed recording's results and words identical before and after.

## 2026-10-28 22:29:13 EDT — scribe `2df7a681281ee29dbf685f651efadcb14ba81788`
Red (#1321): UnopenedAudioTests against a stub (5 of 6 fail): opened audio not counted, quiet and loud apart, the longest loud stretch, the loud level, a step's RMS dBFS, a million steps in constant memory.

## 2026-10-28 22:25:43 EDT — scribe `c305288d7ad022bc841839e49cf4b645ddbc315f`
Plan (#1321): dropped-speech-1321 plan and claims.

## 2026-10-28 22:38:18 EDT — instant-data-swift `1a7a18990e4c59308e9203476ae5d392327aae24`
Green (#1319): a prune batch whose activity expires while it takes the server-apply and operation gates gives both back unworked.

## 2026-10-28 22:38:18 EDT — instant-data-swift `05a0edc9022e197ab665666a44fc827655fe1246`
Red (#1319): a batch whose activity expired once it held both gates still pruned.

## 2026-10-28 22:38:18 EDT — instant-data-swift `0edc7f14ab0cc9c6befd38e03c723c475e850f16`
Green (#1319): a prune batch reads the hot store's residency (only entities it can drop are materialized), re-checks a kept entity only where it releases more of it, runs inside an expiring maintenance activity; every gate counts running time (CLOCK_UPTIME_RAW minus recorded suspensions) with the suspended time beside it. Store copy: holds 300-660 ms -> 5-55 ms.

## 2026-10-28 22:38:18 EDT — instant-data-swift `39de8c92ec02d3fce6249f4c5b1c2622d9c723c1`
Red (#1319): a hub entity's 5,000 unowned facts were materialized every batch (70,824 facts to release 10,850); the gate counted a 30-minute suspension as a 1,801,000 ms wait; a prune told to stop ran all 12 batches.

## 2026-10-28 22:38:18 EDT — instant-data-swift `236915aaa901b3adf33c4b2461565fb78f0702ab`
Plan (#1319): gate-1319 plan and claims.

## 2026-10-28 20:59:36 EDT — scribe `493be905598562026ec984ecad9676ef10f4169b`
Green (#1032): a recording an ingest job is still working on (queued, held, running) is left to the ingest.

## 2026-10-28 20:59:36 EDT — scribe `bf4226b1449ba95508d0a91100006fdf897a3d14`
Red (#1032): the catalog pass signed memo 433 from its WAV minutes before its own ingest did (3 GB fetched twice).

## 2026-10-28 20:59:36 EDT — scribe `7c67b04b635ae0cff78fd9d94c796d20bb7b8372`
Docs (#1032): ADR 0083 amendment A, the catalog worker signs during an open stream with memory to spare.

## 2026-10-28 20:27:34 EDT — scribe `569638767cc4de07781f65d12156481946ac5f1d`
Green (#1032): a catalog pass counts empty WAVs apart, and as waiting only what it did not reach.

## 2026-10-28 20:27:34 EDT — scribe `579c5d5dd81f4588ea3279d6d352edb4d860e040`
Red (#1032): a catalog pass counted the WAVs it found empty as waiting.

## 2026-10-28 20:27:34 EDT — scribe `e458e51f8ba870e004d9a764b93cba8bc0cfb329`
Green (#1032): a recording is signed while a live stream is open when the Mac mini has memory to spare (normal pressure, 3 GB left after the signer's peak; signing an hour takes about 2 s of CPU and 230 MB).

## 2026-10-28 20:27:34 EDT — scribe `bfce178e6183de87d71ee3681ec7c1ebf5a48fb6`
Red (#1032): a recording streamed to the Mac waited for its stream to close before it was signed into scribe-recordings.

## 2026-10-28 20:21:07 EDT — scribe `01202f082412597e493d20126761d19fc5202bce`
Docs (#1032): ADR 0083 amendment A, what the backfill found (297 of 302 recordings with a WAV signed, 164.4 h) and how the worker meets it.

## 2026-10-28 20:21:07 EDT — scribe `b823066be1e9dffbb814013d0f76583e59cc3ed8`
Green (#1032): a WAV with no samples is counted as no audio in its file.

## 2026-10-28 20:21:07 EDT — scribe `2da4e131c60e258d307daa6c365c299183ab32a4`
Red (#1032): a header-only WAV was counted as a failure in the pass counts.

## 2026-10-28 20:21:07 EDT — scribe `510caa9e99540a26e3f965ee43d5002add685020`
Green (#1032): SIGTERM ends a pass through its cleanup: the download's folder removed, the state saved.

## 2026-10-28 20:21:07 EDT — scribe `334e0826b0372e899bc6512b88619eaa972b07a8`
Red (#1032): SIGTERM (launchd's bootout, kill) ended a pass at once and left its download in the temporary folder.

## 2026-10-28 20:21:07 EDT — scribe `dc815a30719aed5601cc56fd771a470d1459e8a0`
Green (#1032): a failure records the program's version (its own hash), and a new version tries it again at once.

## 2026-10-28 20:21:07 EDT — scribe `07b1ccebdd20a9e3e46c2cce72f93308737d4974`
Red (#1032): a failure recorded by an older version of recording_catalog.py waited a day though the new version may fix it.

## 2026-10-28 20:21:07 EDT — scribe `eb7a41dac25e2beba7b7bb41da652916114b9088`
Green (#1032): a WAV recorded at 16 kHz is signed at its own rate.

## 2026-10-28 20:21:07 EDT — scribe `189baf80fce81f6410ef97fb1b753391644fb71c`
Red (#1032): a WAV recorded at 16 kHz was refused as not the phone's 48 kHz (backfill 2, recording e17d7d30).

## 2026-10-28 20:04:09 EDT — scribe `16c985746bb24c8ea563b9f518c052cee02ebc30`
Green (#1032): a recording still going on keeps its chunks fetched so far in a cache on the Mac mini, so each 10-minute re-sign into scribe-recordings fetches only the new chunks (Recording 314's 26 chunks through the cache equal its whole WAV's samples).

## 2026-10-28 20:04:09 EDT — scribe `52d7abbca386da3d17d30cad9cc848a51fde3958`
Red (#1032): a live recording's chunks were fetched again from its first at every re-sign (Recording 316's 6.8 hours would have been about 50 GB).

## 2026-10-28 20:04:09 EDT — scribe `fcccc35e0c681e9b800de2975f7534a922e09ee8`
Docs (#1032): FEATURES item 30 (draft), every recording in our ShazamKit catalog, matched on demand; no line removed.

## 2026-10-28 20:00:24 EDT — scribe `d2621d87df2e7e078a2247c9921665b72bd6f9fd`
docs(#1315, #1316): audit: build 152 on his Watch: the event stream opens; a new iPhone recording on an active Watch not yet shown

## 2026-10-28 20:00:24 EDT — scribe `53c79b5a0c793ecd4eabcdf37532a52cb2012996`
fix(#1315): the installer's expected instant-data-swift moves to 1.9.49 with the pin

## 2026-10-28 20:00:24 EDT — scribe `67e2f7a0ee426c83160c4b9033c4083461eb7d18`
cut(#1315): Scribe 0.1 (152): the Watch's list gets iPhone recordings: its Instant session runs over HTTP (instant-data-swift 1.9.49)

## 2026-10-28 19:57:15 EDT — scribe `152aed3bbc06b3937ba683e192d9d8a6eae16cd8`
Merge (#1032, #922): every Scribe recording signed on demand into scribe-recordings within minutes of its audio (recording_catalog.py on the Mac mini, a pass every 5 minutes, newest first; its whole WAV or live chunks; mediaItems and mediaCatalogEntries rows naming the recording and its start), the existing ones backfilled; a book reading's catalog row carries its recording's audio shift (audioShiftSeconds), so a match leads to the right word.

## 2026-10-28 19:27:38 EDT — scribe `3f68daf6de6d0e9c95cede5a1d8c7a8c7baed2a1`
Merge (#1313): Voice Memos go the full ingest path through one endpoint: POST /v1/process?ingest=recording on the Mac mini keeps a recording's audio as a phone recording's (WAV and compressed copy), hears words and named speakers an hour at a time, retires the old lines, signs the recording on demand into scribe-recordings and writes the rows; `ingest last voice memos` is its thin client.

## 2026-10-28 19:25:23 EDT — scribe `591a0fbff48d60863c85a365f88f6d20adaeab6b`
fix(#1315, #1316): the Watch's Instant session runs over HTTP: instant-data-swift 1.9.49.

## 2026-10-28 19:24:21 EDT — instant-data-swift `ab81ff40613a829ee5f43deed4745d662a30ebf1`
feat(#1315): the live session over Server-Sent Events, and watchOS uses it: watchOS blocks the WebSocket outside audio (TN3135).

## 2026-10-28 18:18:31 EDT — scribe `c0f69514b5072cfa05c754fe968d374a7f0e2c46`
docs(#1305, #1314): the audit's macOS 26 bisect: uneven row heights lose the lazy stack's place on a width change.

## 2026-10-28 18:18:31 EDT — scribe `065caa7235443f13bdc9c24f47de5784f2550c8c`
docs(#1305): the audit of the Mac playback window's live resize: two causes fixed, the third filed as #1314.

## 2026-10-28 18:18:31 EDT — scribe `b374fbb94689ec29e30679b67685cad25ebb28fe`
docs(#1305): What's New for build 150: a window resize no longer rebuilds the whole window at each step.

## 2026-10-28 17:51:44 EDT — scribe `e6336f2778fb0c6e71536335a6ebc3f2422cedc7`
Docs (#1308): build 151 on his Watch streams to his Mac (17:43, his tap): the audit's on-Watch section, its row, PROGRESS.

## 2026-10-28 17:51:44 EDT — scribe `e92a013ae5f88346473a77f434c84c614561948a`
Changelog (#1308): the on-Watch docs.

## 2026-10-28 17:51:44 EDT — scribe `115f8f33e52850f7d3674adb5eb92d8d6365c3a5`
Merge (#1308): the on-Watch docs land on main.

## 2026-10-28 17:15:27 EDT — scribe `93c8c507088c512372f1f12cf2d508fd3570e8d1`
Cut (#1308, #1306): Scribe 0.1 (151): the Watch transcribes on his Mac with Deepgram standing in; the Mac list starts at the top on a first launch.

## 2026-10-28 17:15:27 EDT — scribe `85926e1dda0fbf321aefd578c74528ea10c80ab5`
Changelog (#1308): build 151 cut 93c8c5070.

## 2026-10-28 17:14:12 EDT — scribe `f21dd49f3628cdfeee50799ce1e7b4b38022f033`
Red (#1308): the Watch transcribes on his Mac with Deepgram standing in, and the iPhone hands it the Mac's code (seams keep today's Deepgram-only Watch).

## 2026-10-28 17:14:12 EDT — scribe `763ba95e35bc595aef1515350a121240a9a6b319`
Green (#1308, ADR 0100): the Watch's provider is Your Mac through ADR 0066's failover with Deepgram as the stand-in; the iPhone hands the Watch its Mac code in the WatchConnectivity context; the Watch is ready when either engine is.

## 2026-10-28 17:14:12 EDT — scribe `9d0f584bae810b3cd99bab8f6f90ff57357ebb5e`
Red (#1308): a stream's first and last lines carry no power, battery or heat.

## 2026-10-28 17:14:12 EDT — scribe `4c8d112c55c8f6b8c2a205a2ba874f90e496f1c0`
Green (#1308): a stream's first and last lines say the device's power, battery and heat, the Watch's included.

## 2026-10-28 17:14:12 EDT — scribe `d515c26f2636271581a5d4371b0c6c0af8d340c1`
Docs (#1308): ADR 0100, amendments to ADR 0053, 0066 and 0067, the Watch doc, audits/2026-10-28-watch-mac-1308.md.

## 2026-10-28 17:14:12 EDT — scribe `343ef6b8837f229fa74c0e9c395021df3f95da92`
Merge (#1308): the Watch on his Mac lands on main.

## 2026-10-28 17:11:39 EDT — scribe `bd0319c5879534b342a038625a0bfc12f77de180`
test(#1306): red: the Mac sidebar is a new list once its first page has loaded.

## 2026-10-28 17:11:39 EDT — scribe `d37c6055b2ef67a9b1c918179c3e860c119739fc`
fix(#1306): the Mac sidebar is a new list once its first page has loaded, so a first launch shows it from its top.

## 2026-10-28 17:11:39 EDT — scribe `ed312172686be099b0df006150b205c8b54de408`
merge(#1306): F2 on main.

## 2026-10-28 16:37:26 EDT — scribe `0060c565dac00927a1e1e41b9525aaa1fa656c8f`
cut(#1306, #1305): Scribe 0.1 (150): the Mac list's keyboard and selection, nothing under the playback's controls, help tags, menu commands; a live resize no longer redraws rows or rebuilds the window.

## 2026-10-28 16:31:01 EDT — scribe `43d181e5231cc5de877e80f279c45b277cb35e31`
changelog(#1305) for 29911ccfb.

## 2026-10-28 16:31:01 EDT — scribe `29911ccfbcc457444f407ca9399994a83bcbc657`
fix(#1305): the Mac window keeps the band its width falls in (compact chrome, toolbar density), so a live resize step runs the window's root body only when the chrome changes, not at every step.

## 2026-10-28 16:31:01 EDT — scribe `6793feab23774be4d5d4d2b8795a945ac9d56cf3`
test(#1305): red: a resize step inside one width band runs the Mac window's root body no time (it ran at every step).

## 2026-10-28 16:31:01 EDT — scribe `7e808dd5a634dc5f804bae5d3ee488a3e630607e`
plan(#1305): amendment A: the window's root re-renders at every resize step; keep the width's band, not the width.

## 2026-10-28 16:12:37 EDT — scribe `658ac0a2f7ed0e311fed405fb8e324db5c280def`
merge(#1306): lands the Mac sidebar's selection and arrow keys, nothing under the playback's transport strip, help tags on long titles, and the menu commands on main.

## 2026-10-28 16:12:37 EDT — scribe `b2378e81d5942dc6907b8abb1489b3414ddc7715`
test(#1306): the Mac window suites take the quiet Instant client through the dependencies trait (a once-per-process prepare covered only the first test).

## 2026-10-28 16:12:37 EDT — scribe `dafee1f9d5b57ba1fde93ea68f446c1507610f64`
changelog(#1306) for 402a2efe3.

## 2026-10-28 16:12:37 EDT — scribe `bad08a3acee5ccd228c11df6339939d89ddaabcb`
docs(#1306): the audit of the Mac's list and transcript against the macOS HIG: six findings, the test harness, the fixes, the sidebar offset at first launch open.

## 2026-10-28 16:12:37 EDT — scribe `402a2efe36d189a082e22939988c7f33e4953d83`
fix(#1306): the Mac sidebar selects the recording the detail shows so the arrow keys open recordings; the playback's transport strip sits above the screen instead of in an inset the threads panel did not pass on; long row titles carry a help tag; every toolbar item is a menu command.

## 2026-10-28 16:12:37 EDT — scribe `93f0774b19f77f9ec699b4dbbf64f37182d3912f`
test(#1306): red tests: the sidebar's arrow keys, nothing under the transport strip at 1,100/700/360/240 pt, a long title's help tag (read through the Accessibility API).

## 2026-10-28 14:56:51 EDT — scribe `7af3fb3e7e41f9716b6a58f6c507594f500afc8f`
changelog(#1305) for 16888260c.

## 2026-10-28 14:56:51 EDT — scribe `16888260c2d6cece968c2a371c0327feae690f06`
fix(#1305): a live resize of the Mac playback window redraws no transcript row (the width is a box the rows hold by identity), and the pinned name's lookup reads the drawn document by index instead of walking every line.

## 2026-10-28 14:56:51 EDT — scribe `b31c9f00719a176601ad63cdf582e5126c0f0ec4`
plan(#1305): claim the row snapshot test (one argument).

## 2026-10-28 14:56:51 EDT — scribe `95c09bfdb2afb8be329776129dbfe206a953848c`
test(#1305): red tests: a live-resize step redraws no line already drawn; the pinned speaker lookup takes no walk.

## 2026-10-28 14:56:51 EDT — scribe `d36238a6d835191922f3e6eee772235adbee71a1`
plan(#1305): plan and claims for the Mac playback window live-resize fix.

## 2026-10-28 14:26:09 EDT — scribe `e88bd025f1d00fa97489b0414896a11fd1840872`
changelog(#1307) for 7d0c88b89.

## 2026-10-28 14:26:09 EDT — scribe `7d0c88b89a7280f9fa4d5464af193799821506c0`
docs(#1307): the rubric's settings-window gate quotes two more clauses; the open timing reports its resolution.

## 2026-10-28 14:24:50 EDT — scribe `614dd749888b37ea1fba74a95d6b1bf0040406dc`
docs(#1307): PROGRESS entry for the macOS HIG skill and its rubric.

## 2026-10-28 14:24:50 EDT — scribe `f1d367d9e59cb9da7f54ec63ab4aff95a70c3f53`
changelog(#1307) for 2021f3083, 2c489e955 and 2564ab06a.

## 2026-10-28 14:24:50 EDT — scribe `2564ab06aa4df44a39da90dac67d8bd130f335c1`
docs(#1307): the mac-hig skill and its rubric: Apple's macOS pages for each Mac surface, 55 pass/fail usability and performance gates with reviewer instructions and a scoring sheet; scribe-hig links it; the agent guide installs it.

## 2026-10-28 14:24:50 EDT — scribe `2c489e9554924d5b2f5085585512d4df7cf5807b`
feat(#1307): resize_sweep.py times window resizes, scroll steps and opens through the Accessibility API without moving the pointer.

## 2026-10-28 14:24:50 EDT — scribe `645d774a620d8db7e254dff44b1eab8f94516fa2`
test(#1307): red tests for resize_sweep.py's plans, statistics, idle reading and pid refusal.

## 2026-10-28 14:24:50 EDT — scribe `2021f30830f294906837a8d9b2a4aad2e98b18a5`
feat(#1307): 128 Apple macOS pages kept offline with source and fetch time; checks that every quote is word for word and no rubric verdict lacks evidence.

## 2026-10-28 14:24:50 EDT — scribe `d8527a996e8d1adc19acd1bf24d1381f65b9a92f`
test(#1307): red tests for the quote, scoring-sheet and Apple-copy checks.

## 2026-10-28 14:24:50 EDT — scribe `abde909c7d6da263ac0570ce0b3512448ccb051a`
plan(#1307): plan and claims for the macOS HIG skill and rubric.

## 2026-10-28 13:12:49 EDT — scribe `ce59bf3b2bb9ba4ea1d016328961216605d81cee`
changelog(#1303) for 64dbc4b19.

## 2026-10-28 13:12:49 EDT — scribe `8dae468b5bbe67caefd7a3b3ec124e2bb2205394`
docs(#1303): the audit's interleaved before/after frame times: no regression while scrolling 2,000 lines.

## 2026-10-28 13:12:49 EDT — scribe `64dbc4b195e21ce062158a3480b6a9c5f1d958df`
fix(#1303): a cancelled handle drag ends the drag (no edge scrolling after the finger); an unanswered double tap is dropped.

## 2026-10-28 13:12:49 EDT — scribe `5d6b09789b20d8d2dff0ab07fa9051c52b7e9a3f`
changelog(#1303) for b1e1705dc, ce829109d and ea44b3a5f.

## 2026-10-28 12:57:21 EDT — scribe `5d6b09789b20d8d2dff0ab07fa9051c52b7e9a3f`
changelog(#1303) for b1e1705dc, ce829109d and ea44b3a5f.

## 2026-10-28 12:57:21 EDT — scribe `ea44b3a5f467b8723e606533e7f3aeec1e319915`
merge(#1303): select text across the timeline's lines: one selection layer over the rows from SwiftUI's own glyphs (live screen and playback), the harness's UI check, ADR 0099, FEATURES item 28 (draft), the audit.

## 2026-10-28 12:57:21 EDT — scribe `ce829109de7356e38087e95835219b27ff6729f8`
fix(#1303): a finished recording keeps its selection across lines; Copy copies them as the rows show them.

## 2026-10-28 12:57:21 EDT — scribe `b1e1705dcf27a01b8a62ce0fe031a9b84962343d`
fix(#1303): the selection across lines, its geometry and Copy in the recording's reducer.

## 2026-10-28 12:09:40 EDT — scribe `a12939bb06fff8995978ea2aa7e2b836ad982789`
guide(#844): the listener dispatches all work to subagents; lookups and triage on Haiku, the rest on Opus.

## 2026-10-28 12:09:40 EDT — scribe `3e19f2f643c4d32a9fddf30512975f0969cae30e`
changelog(#844) for a12939bb0.

## 2026-10-28 11:53:24 EDT — scribe `fb77fef4e84f7292ed0f6e1a2ab251211afaf702`
docs(#1282): scribe-guide feedback history: the diagrams skill keeps drawings off the Desktop (in ~/Sync/audit/diagrams).

## 2026-10-28 11:53:24 EDT — scribe `12a9923c6653cbd4e316aa7a20734c6092262cc8`
changelog(#1282) for fb77fef4e.

## 2026-10-28 11:13:36 EDT — scribe `0adcd996319ec8988a53ffb4e2789d4bc8fb4fe1`
docs(#1300, #958): PROGRESS: Scribe 0.1 (148) and Scribe Playback 148 on every device; #958's after; cleanup.

## 2026-10-28 11:13:36 EDT — scribe `981f41b0c908e45f6e9b8d4e7d5dbfea03e08a06`
changelog(#1300, #958) for 0adcd9963.

## 2026-10-28 11:10:32 EDT — scribe `5cd6242c3f45bb30ce7d5d62aa6571c28a5727ae`
docs(#958): the audit's after-measurement on build 148 (the follow is gone at launch) and a correction: the unbounded owner shape is not the lookup.

## 2026-10-28 11:10:32 EDT — scribe `f0cc7968473cd90e299ec69e04b3a0020bc27935`
docs(#958): the audit's launch rows named with their own sizes.

## 2026-10-28 11:10:32 EDT — scribe `0b08963fd476bddca331c4511637123b40581731`
test(#958): the layout harness's home screen, drawer and jump-back references show the recordings without audio in the list (11 re-recorded).

## 2026-10-28 11:10:32 EDT — scribe `ff4ca3d7cac2ecab6dbaabbc63309b7f1fb025be`
changelog(#958) for the three commits above.

## 2026-10-28 10:08:43 EDT — scribe `368ff621145b02837c22ed4a712da1a019fa247a`
cut(#1300, #958): Scribe 0.1 (148) and Scribe Playback 148 from main d68bee33a: the Without Audio filter removed (#958), #1260/#1266, #1288, #1295, #1285/#1291, #1293 and instant-data-swift 1.9.48; 146 and 147 hotfix notes carried to main.

## 2026-10-28 10:08:43 EDT — scribe `537fd386784ce074b5e65039973e90e3875f3a68`
changelog(#1300): build 148 cut 368ff6211.

## 2026-10-28 10:06:00 EDT — scribe `fb816d20962d1d3d8da6e0ee2cdb6be05894f9a6`
test(#958): red: the recordings list has no Without Audio filter and its task starts no lookup for one. Michael, Recording 315 #76-78: "Also remove the without audio." "filter and query."

## 2026-10-28 10:06:00 EDT — scribe `500585cd3609c812e13d2102ab0c0cef9abbbfee`
fix(#958): green: RecordingsWithoutAudioClient (lookup + live follow recordings[deletedAtMs,id]), RecordingWithoutAudioRule, the editing state, actions, effect, menu choice, banner and their tests removed; every recording stays in the list; decodableRowSelection moved.

## 2026-10-28 10:06:00 EDT — scribe `a37d397976b4df64d7142eecf5fc174d7bc31e3c`
docs(#958): the audit (the follow's cost on build 147) and PROGRESS.

## 2026-10-28 10:06:00 EDT — scribe `d68bee33a`
changelog(#958) for the three commits above.

## 2026-10-28 04:53:21 EDT — scribe `3a42c143bc5ecb7874a09cb7394f3cceffe7e10a`
Changelog (#1293, #1292): Scribe main's entries for the red guard, the test-support rule, the three tests the crash hid, the comments, the guide and PROGRESS.

## 2026-10-28 04:53:21 EDT — scribe `e3a0e31ca978c1dee47ba53508553d17007b9004`
PROGRESS (#1293, #1292): every test bundle runs to its end under Swift 6.4; the guards fire; main compiles for iOS and watchOS.

## 2026-10-28 04:53:21 EDT — scribe `3a67f144d295982d11e1934c6f3d5ee730906602`
Guide (#1293) on Scribe main: a guard runs only in a bundle that reaches its end; a test bundle that exits with signal 11 is fixed at its cause, never skipped.

## 2026-10-28 04:53:21 EDT — scribe `7aa6735d3568c6c2442b4acafae967f88c1238ad`
Docs (#1293) on Scribe main: three test comments no longer say their bundle lacks IssueReportingTestSupport.

## 2026-10-28 04:53:21 EDT — scribe `26d5becedc43c5d5f4978292389043e1e4377b2b`
Fix (#1293) on Scribe main: the sync-boundary scan of product sources reads code, not comments.

## 2026-10-28 04:53:21 EDT — scribe `0564842884e319e68b7bbc651b0b9a4baf739509`
Fix (#1293) on Scribe main: the trapping-uniqueness check lists the energy library counters' file-kind dictionary, keyed by a String enum.

## 2026-10-28 04:53:21 EDT — scribe `1beccd10edd168cb6eb378e422639a1c25fe4bce`
Fix (#1293) on Scribe main: the order-index scan reads both fields of a conditional order and checks each is indexed and typed.

## 2026-10-28 04:53:21 EDT — scribe `dc59e2be8a2c94f9878713886ee9d418598b2d8c`
Green (#1293, #1292) on Scribe main: every test target links DependenciesTestSupport (and so IssueReportingTestSupport), so a reported issue under Swift 6.4 is a failure, not a SIGSEGV in Test.id; whole-bundle runs reach their end.

## 2026-10-28 04:53:21 EDT — scribe `9481c074f703ccec5a8c665e25c1f036c0db99e6`
Red (#1293, #1292) on Scribe main: a test pins that every test target links the issue-reporting test support and that a failing comparison is recorded, not a crash.

## 2026-10-28 04:52:12 EDT — scribe `8bb47b2845e1f09a69b843a6e62c3f004b3ae027`
Changelog (#1295): Scribe main's entries for the red, the green, the audit and PROGRESS.

## 2026-10-28 04:52:12 EDT — scribe `21cec234b85af76e5b410e705ba2f085cadd606d`
PROGRESS (#1295): the sampling loop reads nothing on the main actor at a scene change, red and green.

## 2026-10-28 04:52:12 EDT — scribe `2b695ed90b76c42c612ff7e17228bdf19491d38a`
Audit (#1295) on Scribe main: the diagnostics audit's section 9, before and after.

## 2026-10-28 04:52:12 EDT — scribe `2763dc70a184c17863f696241cdd1cd901dc12f1`
Green (#1295) on Scribe main: the sampling loop's pass at a scene change carries the latest readings (at most 120 s old) and reads nothing on the main actor; later passes read as before; the memory fenceposts follow the setting, not the scene.

## 2026-10-28 04:52:12 EDT — scribe `e5aeb38011101f1da56b2654e4ba3bc07cba916e`
Red (#1295) on Scribe main: the sampling loop, moved into its own type with its readers injected, read 8 times on the main actor at the two restarts of a move to the background.

## 2026-10-28 04:06:56 EDT — scribe `e9feeaf61c3e24ba0ede61a01e31f25715bad249`
Changelog (#1288): Scribe main's entries for the red tests, the green, the guard, the test comments, the ADR and audit, and PROGRESS.

## 2026-10-28 04:06:56 EDT — scribe `ee5214c871a837891b529903148d99f4c176a566`
PROGRESS (#1288): the session-health scene beat off the main thread, red and green.

## 2026-10-28 04:06:56 EDT — scribe `86dbda00e7d596d85861e25600c83073a6a8de1e`
Docs (#1288) on Scribe main: ADR 0019 amendment 1 and the diagnostics audit's section 8: the scene beat off the main thread, measured before and after.

## 2026-10-28 04:06:56 EDT — scribe `c19b972ceddf39937f81f6d4ec40f64559daed38`
Docs (#1288) on Scribe main: three new test comments no longer say their bundle lacks the issue-reporting test support (#1293 landed).

## 2026-10-28 04:06:56 EDT — scribe `cf17986966f9a5a33321e8e2abcb882d1197a880`
Guard (#1288) on Scribe main: the shared region walk's million-call stress test (171 and 216 ns a call, stack constant).

## 2026-10-28 04:06:56 EDT — scribe `56aef17e1e2dfe528ff6184a7eb67dd656bba00c`
Green (#1288) on Scribe main: a scene change samples, walks and waits for nothing on the main thread (the lane's own task sends the beat with the latest sample and its age; the samplers are @concurrent async); the shared region walk is claimed under its lock, walked outside it and published under it; trigger walks capped at 12 an hour.

## 2026-10-28 04:06:56 EDT — scribe `f45fb6d9e461dd2c50fac1ae378eaac267cf9419`
Red (#1288) on Scribe main: a scene change samples on the main thread (34.6 ms and 32.0 ms with the live samplers in a test), the region walk holds its lock while walking, trigger walks are uncapped.

## 2026-10-28 01:53:25 EDT — scribe `736061245150aa66cf9ca7055820c399a9d2ad8e`
Changelog (#1285): Scribe main's entries for the diagnostics guards, the harness parser's bound, the guide, the lock check's extension, the audit and PROGRESS.

## 2026-10-28 01:53:25 EDT — scribe `1ff66622c52efd0c4c6076a42a13674d0937f642`
PROGRESS (#1285): the diagnostics rule, the inventory and the guards, red and green.

## 2026-10-28 01:53:25 EDT — scribe `063aba57c98cbbae2ff473262a8ff72eef6bf32b`
Audit (#1285) on Scribe main: the inventory of 112 in-app diagnostics against the platform's own tools, the guards red and green; README row.

## 2026-10-28 01:53:25 EDT — scribe `befd40a0dcea1150e72a91752744ea746be00fee`
Green (#1285) on Scribe main: the lock check also reads UncheckedSendable, ManagedAtomicLazyReference and every generic type the shipped code declares; 0 sites.

## 2026-10-28 01:53:25 EDT — scribe `ee73c2758fe384a0d51891e27665896612483236`
Red (#1285) on Scribe main: the lock check's self-test finds functions held in UncheckedSendable and in the repository's own generic wrappers.

## 2026-10-28 01:53:25 EDT — scribe `2b12d809e7c2e788aee2aa0bde7c19bb558d4551`
Guide (#1285) on Scribe main: an AGENTS.md section on diagnostics that never crash, hang or slow the app, and its feedback-history entry.

## 2026-10-28 01:53:25 EDT — scribe `cd7310d5b5bf428d0845c7ab55ef2cfaa7a92ae2`
Green (#1285, #1291) on Scribe main: the stream agent's harness parser reads no line nested past 64 levels, so no tool input is written back sorted past what a cooperative thread holds.

## 2026-10-28 01:53:25 EDT — scribe `2a5bcb97e5d482b2356eae5bbf44e34e3f0998d4`
Red (#1285) on Scribe main: MetricKit payloads only through the bounded reader, 10,000-level payloads through every payload processor, and a million calls per meter; the old network meter and ledger died with SIGBUS.

## 2026-10-28 01:35:36 EDT — scribe `2d6baba60fb955d7d60c93fdff1bc1033c2148ce`
Changelog (#1284): Scribe main's entries for red 2b2499fb5, green ab0ab4042 and build 147's cut feeb50df6.

## 2026-10-28 01:35:36 EDT — scribe `ab0ab40428f7abc0c53414dea195b5a9929eb2b3`
Green (#1284) on Scribe main: no lock holds a function; the network meter keeps the path as a value set by the path monitor, and eight other locks keep their function in a final class or a struct; the guard finds 0 sites in 1,409 files.

## 2026-10-28 01:35:36 EDT — scribe `2b2499fb57e4c87bd150137778c0498090750266`
Red (#1284) on Scribe main: the path reader and the ledger's library reader go 2 frames deeper every read (49, 51, 53 ... 115 at read 34); no lock may hold a function (9 sites).

## 2026-10-28 01:35:36 EDT — scribe `feeb50df6f5610a4d85fe23c7c7e275cd8e9f80a`
Cut (#1284): Scribe 0.1 (147) on release/147-hotfix, build 146 (34159c49e) plus only #1284, CURRENT_PROJECT_VERSION 147 and one What's New story; instant-data-swift exactly 1.9.48.

## 2026-10-28 01:35:36 EDT — scribe `7e8a0ae4d622e5951906d333d4a956d59a5da6d3`
Schema declaration (#1277, cherry-pick -x of Scribe main's ee490cf58) on release/147-hotfix: voiceMemos, voiceMemoOverlaps and modelCalls, which production had since ~22:20, so the Instant drift gate passes build 147; TypeScript only.

## 2026-10-28 01:35:36 EDT — scribe `d1e45a34e9d7aeca26772c73fcfa7aa36a3569a0`
Green (#1284) on release/147-hotfix: the same fix as main's ab0ab4042, on build 146's code.

## 2026-10-28 01:35:36 EDT — scribe `e46b89d2c8658d2deabf032b3ae1043c2e53f32d`
Red (#1284) on release/147-hotfix: the same tests as main's 2b2499fb5, on build 146's code.

## 2026-10-27 20:45:05 EDT — scribe `91dd904c43f24d9f1e37354c87f28b8f44bb8220`
changelog(#1270): the 1.9.48 pin (2b4c19013) and the sync jam audit (67094e3c6); the pin's SHA after the rebase in PROGRESS and the audit

## 2026-10-27 20:45:05 EDT — scribe `67094e3c61f66bd60d00b7e6bd8e0bc1593189e7`
docs(#1270): audit: the sync jam of 2026-10-27, every server frame replayed the whole outbox; README row; PROGRESS

## 2026-10-27 20:45:05 EDT — scribe `2b4c190133041d12b9bca4e6e7bd2b5fdf4dfe58`
Pin instant-data-swift exactly 1.9.48 instead of 1.9.46 in Scribe and Scribe Playback: a server frame no longer replays the whole outbox (#1270)

## 2026-10-27 20:45:05 EDT — instant-data-swift `9f898cc56496c0f9bfc789d08fb4f80842dc2061`
changelog(#1270): v1.9.48's intent entries: red fdd08d36, green 792c5411, 68fa970c, 5209e44b, 6c077e01 (the tag stays at 81af3d33)

## 2026-10-27 20:42:30 EDT — scribe `6d709f1d5bcd86df6c4b8c6e125529036189e530`
Changelog (#1274): the build 146 hotfix cut recorded in CHANGELOG.md.

## 2026-10-27 20:42:30 EDT — scribe `34159c49e2c3d81a4f11098625cccedbcd56d5d3`
Cut (#1274): Scribe 0.1 (146), a hotfix on branch release/146-hotfix: build 145 (1a21903e4) plus only instant-data-swift exactly 1.9.48 (#1270).

## 2026-10-27 20:38:28 EDT — instant-data-swift `6c077e01ea8cbcde9a63fd3d14c8bb9b6ca59b3d`
docs(#1270): the v1.9.48 release document, and FOOTGUNS F65: a queue that slows its own drain never recovers

## 2026-10-27 20:38:28 EDT — instant-data-swift `5209e44ba32719e4e2458d3def1300eba6f8e4ee`
test(#1270, #1275): the attachment differential over many seeds, and a trace that follows any slot of the recording

## 2026-10-27 20:38:28 EDT — instant-data-swift `68fa970c4bcc5f39f70ae5df45ce1e0b6a92b6e3`
feat(#1270): the gate-held line names the attribute that declined a server apply's reduction

## 2026-10-27 20:38:28 EDT — instant-data-swift `792c5411279f259d6e9857066cf3229450d7e553`
fix(#1270): green: a server apply finds a link's pending writers under every name a write gives it

## 2026-10-27 20:38:28 EDT — instant-data-swift `fdd08d363c9c376f1fdbd223c7635e3e2ceac32f`
test(#1270): red: a frame restating the recording peels and replays the whole queue when a link is written by name

## 2026-10-27 20:38:28 EDT — instant-data-swift `8e2e0cef857636ce12fb0228cbacf5ba3b963050`
plan(#1270): sync-jam-1270: a server apply finds a link's pending writers under the link's written name; claims

## 2026-10-27 20:38:28 EDT — scribe `5616b83a51ae3b6ff55781bbfb6b2b2599cf5f7e`
plan(#1270): sync-jam-1270: pin the library's fix for the sync jam, and the audit; claims

## 2026-10-27 17:54:28 EDT — scribe `95c38922aeccea8b142d02b67ffda8e99d8ae99b`
changelog(#1266): the clipboard green (4895d1297) and the audit's update (cb3126f4a)

## 2026-10-27 17:54:28 EDT — scribe `cb3126f4a686379a2cecedb9b250dcd8bac99f0a`
docs(#1266): audit: the clipboard green (4895d1297) and two claims tightened to what the samples show; README row; PROGRESS

## 2026-10-27 17:54:28 EDT — scribe `4895d129780d3318d3a73e5db1f42a0e9db73d67`
fix(#1260, #1266): green: the iOS clipboard monitors read UIPasteboard off the main actor

## 2026-10-27 17:54:28 EDT — scribe `81e3866e7a277a11c6b5afc305a8c85a81bbca72`
changelog(#1266): the red clipboard test (45f7f059c) and the watchdog audit (5df2fe000)

## 2026-10-27 17:54:28 EDT — scribe `5df2fe0007efa63c2bc140f629ca0e55077326de`
docs(#1266): audit: the scene-update watchdog kills of 2026-10-27, a starved and a saturated main thread; README row; PROGRESS

## 2026-10-27 17:54:28 EDT — scribe `45f7f059c9ec65916600e9b93c12305aae810aa2`
test(#1260, #1266): red: no clipboard monitor may read UIPasteboard on the main actor

## 2026-10-27 16:48:40 EDT — scribe `1a21903e4241d2aee76c8b031f5c445d7f4cc3fd`
Cut Scribe 0.1 (145) + Scribe Playback 145 from main 15055b6f5 (instant-data-swift 1.9.46): MetricKit crash fix, held chunks refuse cellular, per-subsystem energy, named SQLite writers.

## 2026-10-27 16:48:40 EDT — scribe `97623d61876c0764626399803e04d28b780a7f7d`
Changelog entry for the build 145 cut.

## 2026-10-27 16:42:16 EDT — scribe `f46ff669d2d3031570581743020470fac43d7fb9`
changelog(#1257): the red exit tests (af0f8ab97), the MetricKit reader and large stack (3b14ddaec), the audit (53027854c)

## 2026-10-27 16:42:16 EDT — scribe `53027854c7f725570ff4dbecec0a3a345b207d30`
docs(#1257): audit: Recording 309's crash loop, the 12 hangs replayed before and after, the relaunches' cost; README row; PROGRESS

## 2026-10-27 16:42:16 EDT — scribe `3b14ddaec6517d0b9d25abd6640432e7cde26ee1`
fix(#1257): green: MetricKit payloads are read by an iterative reader and written on an 8 MB stack, raw first, so a hang diagnostic never crashes Scribe or is lost

## 2026-10-27 16:42:16 EDT — scribe `af0f8ab9752a149ff903fc493db2e7408718e2f3`
test(#1257): red: Recording 309's hang payloads kill the MetricKit trimmer and processor (SIGBUS) or are lost

## 2026-10-27 13:40:09 EDT — instant-data-swift `3822618a301da38a2087cdb7b1a285804751a834`
docs(#1253): the v1.9.47 release document: a progressive media stream's later writes carry only what changes

## 2026-10-27 13:40:09 EDT — instant-data-swift `6fb8b6541ffaf5f9be47835f083ea71d43a21cde`
feat(#1253): green: a progressive media stream's later writes carry only its state, segment count, duration and update time

## 2026-10-27 13:40:09 EDT — instant-data-swift `464d057f5465963cde5e0182bd3db51dd3f94c5f`
test(#1253): red: a progressive media stream's later writes carry only what changes (3 of 12 fail on the seam)

## 2026-10-27 13:40:09 EDT — scribe `b288d821ed94f3a22feb30057a94c39821fac721`
changelog(#1245): the ledger's SQLite file writers (50439e356, b37e82ff6), the 1.9.46 pin (0ee978e2c), the meter's mapping (b036938a0, ca98a8b4a), the audit (504071355)

## 2026-10-27 13:40:09 EDT — scribe `50407135520cd41b4726182daa69ede645b3eb7a`
docs(#1245): audit: SQLite's own tools on the iPhone's Instant store, and where its writes go; README row

## 2026-10-27 13:40:09 EDT — scribe `ca98a8b4a645cb65b817a74885561e43476b2328`
feat(#1245): green: each energy-ledger minute reads the library's SQLite file meter, so the disk writers name checkpoints and temporary files

## 2026-10-27 13:40:09 EDT — scribe `b036938a045d813aab893838e9e99d5657768978`
test(#1245): red: the energy ledger keys the library's SQLite file meter by kind (1 of 4 fails on the seam)

## 2026-10-27 13:40:09 EDT — scribe `0ee978e2c307571813fa613fdfa8b904e5008460`
Pin instant-data-swift exactly 1.9.46 instead of 1.9.45 in Scribe and Scribe Playback: SQLite's own counters per store call and per kind of file (#1245)

## 2026-10-27 13:40:09 EDT — scribe `b37e82ff6979cd833ae9bca31eb1fb6fd239d60f`
feat(#1245): green: the ledger's disk writers name SQLite's checkpoints, temporary files and the log's own bytes

## 2026-10-27 13:40:09 EDT — scribe `50439e35688707c59fe0e8cb1507b6d7f3c5b122`
test(#1245): red: the ledger's disk writers name the SQLite files no store call counts (2 of 121 fail on the seams)

## 2026-10-27 12:53:31 EDT — scribe `79a307ec4e8cf2b5d1375e58c99ff3d766847a0d`
Merge (#1246): the energy model's display has the panel's base; fitted on three sessions.

## 2026-10-27 12:53:25 EDT — scribe `eae83c24164d09f480b22140e2991294d0d70853`
Changelog (#1246): the panel's base and the three-session fit.

## 2026-10-27 12:53:23 EDT — scribe `640d1a622f7f99ce12b776d8da725120b2cace90`
Docs (#1246): held out on two windows never fitted; the display's base; the Neural Engine by build.

## 2026-10-27 12:47:01 EDT — scribe `075184c5cd66fe67e4438bc12a0eb91da19d3ea7`
Green (#1246): the display's estimate is a base while in front plus luminance times appearance; total within +3.1%, -8.6%, +0.9% on three sessions.

## 2026-10-27 12:47:01 EDT — scribe `a225d52ff4e0a8ebf897b68ff03bf29ff029492a`
Red (#1246): a dark screen in front still costs the panel's base: the first model said 121 mW where the powerlog billed 202.

## 2026-10-27 12:41:50 EDT — scribe `4339c454fb63c783821251c90908617f1ead6943`
Plan (#1246 #1245): channel note: the energy model landed; its lines in the ledger row.
