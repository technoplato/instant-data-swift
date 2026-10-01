## 2026-10-01 08:44:01 EDT — scribe `ccb05eab20fe4cb2bfc3888d83800783b1f19da4`
Record the refused-write recovery tool in the change log (#332).

## 2026-10-01 08:39:15 EDT — scribe `79e3c6a160745f9244d11ea6e2583d4f72e45803`
The outbox recovery tool folds chosen failed rows with per-value write stamps (a refused value production superseded is never written back), adds --plan-only (no token), terminates chunks with production's samples, uploads attachment bytes to the row's storageName before writing the row, and writes one entity per transaction with a re-read, journal, and verification. Used for the 2026-09-26/27 recovery Michael approved: 19 owner writes, 0 refused (#332).

## 2026-10-01 08:24:36 EDT — scribe `3e70cacac4b921d22f57d7ea8127b1ac898347e9`
Plan the Sept 26-27 recovery into production and claim the outbox recovery tool's paths, plan 2026-10-01-recovery-0926 (#332).

## 2026-09-30 20:35:50 EDT — scribe `ce0f01801274fc22c6c02e3a4df53c2dae87e688`
Record the Account screen without the demo counters in the change log (#289).

## 2026-09-30 20:26:07 EDT — scribe `a70b8850cb03e07afbe9dc39aa40d44d0f256206`
Hide the library's demo counters on the Account screen on iPhone, iPad, and Mac, and drop the discard switch's iOS-only guard; ScribeAccountViewSchemaTests fails when the screen reads or writes an entity instant.schema.ts does not declare (#289). Needs instant-data-swift 9f72413d.

## 2026-09-30 20:25:22 EDT — instant-data-swift `41b912d7b6ea9eab04815c2c23174832ce251424`
Record the AuthV3 demo counters switch in the change log (#289).

## 2026-09-30 20:24:34 EDT — instant-data-swift `9f72413db9fb8db1bcc496fcea3c6344e6b63194`
Let apps turn off AuthV3LoginScreen's demo counters: environment value authV3ShowsDemoCounters, default on; AuthV3 UI module only, no InstantSwiftDataCore change (#289).

## 2026-09-30 19:30:48 EDT — scribe `44e9379db3e61168ce6ea967cb23b95b62806ce8`
Plan the Account screen without the library's demo counters and claim its paths, plan 2026-09-30-auth-counters (#289).

## 2026-09-30 19:29:59 EDT — instant-data-swift `54c8a963267a9843b9f8522e94d0f1fc3545ab08`
Claim the AuthV3 login screen and its tests for plan 2026-09-30-auth-counters (#289).
## 2026-09-30 21:53:30 EDT — instant-data-swift `1907c0b49859612372531a9ab36aa8044e461d73`
Restore a refused write's receipt as written, then restamp what it restored to txTime 0, so an insert-only receipt still removes the overlay (the ten suites' failedActiveOverlayIsARootEvenWhenTheServerWriteIsDisjoint on df0a711a) (#296).

## 2026-09-30 20:56:20 EDT — instant-data-swift `df0a711a66b33fd768eec9527f71abd5e0817103`
Record the persisting-decline fix and the refused-write restore in the change log and the audit ledger (#296).

## 2026-09-30 20:55:10 EDT — instant-data-swift `f53f779317bdddba4912d92d5a676e5982001a02`
Let the server's facts win against what a refused write restores: restored facts are base facts at txTime 0 at the splice, the terminal-failure removals, and the full rebase's reverse pass; the differential gains a multi-refusal event (#296).

## 2026-09-30 20:18:37 EDT — instant-data-swift `b78e978f8aee30821485d10ad312d70e1b4604d9`
Skip a restated fact that loses to a later-stamped resident fact, as the full rebase's last-write-wins does, so the phone's list frames stop declining on recordings/clipboardEntries (#296).

## 2026-09-30 18:34:29 EDT — instant-data-swift `678b5faf1722c6e75274828f426d5f2f928061f0`
Claim the build-75 fast-drain paths for plan 2026-09-30-fast-drain-3 (#296).

## 2026-09-30 14:51:40 EDT — instant-data-swift `ad1da185ed8f46ff422924425e46fa60a9aeb5c9`
Record build 73's library, its gates, and the open follow-ups in PROGRESS (#296).

## 2026-09-30 14:51:40 EDT — instant-data-swift `3980a73df9317c4d5280e1f256e68a2928569992`
Claim PROGRESS.md for plan 2026-09-30-fast-drain-2 (#296).

## 2026-09-30 14:10:53 EDT — instant-data-swift `506089b22043c2f5bcb02712f5b7df698e31b6d3`
Record build 73's library commits in the audit ledger (#296); this is build 73's library head.
## 2026-09-30 19:42:44 EDT — instant-data-swift `9d5e185cd1a80eddbaf0f83a93e3d8ece8aee897`
Record the backward-navigation seed fix in the change log (#300).

## 2026-09-30 19:42:29 EDT — instant-data-swift `0d66e6bb5d7ce8d3283dca446ef7f389bfa26704`
Start a backward-navigation page from the server's answer, not an earlier query's stored result: a stale stored "no rows above" made the window believe it reached the top and climb to the head (#300).

## 2026-09-30 19:02:12 EDT — instant-data-swift `1562eeeef3ba821983515b18834f9422cc0263ee`
Claim observeLiveInfiniteQueryChunk in InstantRuntime.swift for plan 2026-09-30-infinite-leading-rows (#300).

## 2026-09-30 18:24:18 EDT — instant-data-swift `ce374ab734aa6771b2f574d8e4c3acdebf5ec047`
Record the leading-rows window fix in the change log (#300).

## 2026-09-30 18:23:33 EDT — instant-data-swift `3bcf817da8813bbf1733df51ccc4fa3729926e19`
Keep a windowed live infinite query paging when rows appear above its first row: the leading watcher leaves with the evicted top page and returns only when navigation reaches the top, trims cut at page boundaries, and evicted pages reload from their exact boundaries (#300).

## 2026-09-30 16:42:06 EDT — instant-data-swift `d30c538d43055859d31163133294ae3b80b45e48`
Claim the live infinite query's retention window for plan 2026-09-30-infinite-leading-rows (#300).

## 2026-09-30 13:51:53 EDT — instant-data-swift `46c131d7413cb3185c80d6e0ce70f467879dfc9e`
Merge connection survival (984cc351) into build 73's library: one reconnect per socket death, and reading while a frame applies (#296).

## 2026-09-30 13:50:18 EDT — instant-data-swift `a18786c8f017a46cce09edcdb18d64b31021def4`
Record the refused-overlay removal in the change log (#296).

## 2026-09-30 13:50:01 EDT — instant-data-swift `5424c73365c63d487fe8f0f4768531450f970c2e`
Remove refused writes' overlays without the whole-component rebase, and respect last-write-wins in receipt patches (#296).

## 2026-09-30 11:47:07 EDT — instant-data-swift `b4d6bce2e948f324910525de243299efb6a64bf9`
Record the deferred-value, reverse-link, and tail-order fixes in the change log (#296).

## 2026-09-30 11:14:09 EDT — instant-data-swift `b4b9fbe32d6d89f223a69f76e05dc1180bc8fe3b`
Hydrate deferred values before classifying, decide links written from the other side from their writer's receipt, and order the stamp guard's tail check by id; pin the bounded rebase tests to the full rebase (#296).

## 2026-09-30 10:53:07 EDT — instant-data-swift `22a24ab857a3f50971d082d6a0cb64a8228757ef`
Claim InstantBoundedServerApplyRebaseTests for plan 2026-09-30-fast-drain-2 (#296).

## 2026-09-30 10:05:34 EDT — instant-data-swift `69ae247687f0eb73ca3f37907d788f530cc1dff8`
Record the build-73 reapply and the receipt-patch reduction in the change log (#296).

## 2026-09-30 10:05:07 EDT — instant-data-swift `ae55eeda35195ba27671356227b34e7964c71cf9`
Add the production check of build 72's six refusals to the refused-replay open item (#296, N47).

## 2026-09-30 10:04:54 EDT — instant-data-swift `bcbcaaed00cf2511456dbb6e14e7fc8840fe62d8`
Record the refused replays behind "32 failed mutations" as an open item for N47, with the read-only bd40c50a comparison (#296).

## 2026-09-30 10:01:15 EDT — instant-data-swift `2666d34396f43800a94692cfd7b8925afa5d890b`
Receipt patches: a server change beneath a slot's writers re-receipts the first writer instead of rebasing the component; F1 (no earlier-overlays cap) and F2 (links written from the other side decline) (#296).

## 2026-09-30 09:09:15 EDT — instant-data-swift `81eb122c04cc300940b694944a8eb33a533bf7ca`
Reapply 8bee78eb on the build-73 branch as the base for its fixes; not shippable alone (#296).

## 2026-09-30 09:08:09 EDT — instant-data-swift `83652b96cc33d74bb6cd8ae79b51f9513b06d2fe`
Claim the build-73 fast-drain paths for plan 2026-09-30-fast-drain-2, with the channel that splits InstantRuntime.swift with the connection-survival worker (#296).

## 2026-09-30 13:04:58 EDT — instant-data-swift `e503090047d3123a337ef20f920d7415de15b6ee`
Record the stale-acknowledgement settle fix in the change log (#296).

## 2026-09-30 13:04:58 EDT — instant-data-swift `bc5dc403a9df82f68e160a5c767cb590e9976b3c`
Record the measurement wording fix in the change log (#296).

## 2026-09-30 13:04:58 EDT — instant-data-swift `b3e1c6f6f0f69ebcf23696b229c3e5b9aef6a816`
Record the stale-acknowledgement deadline tolerance in the change log (#296).

## 2026-09-30 13:04:27 EDT — instant-data-swift `5e994bdc92e5fc0543798ab23283828d9ea9d8c8`
The stale-acknowledgement test waits for the delivery pump to settle before its reclaim, so a pass cannot strand the reoffer it waits for; the reader widened this pre-existing window (6 of 35 runs timed out, now 0 of 40 at load 693-929) (#296).

## 2026-09-30 12:04:51 EDT — instant-data-swift `2ddad19f7056b3fed9e6b7d42166888fb1a1ecf4`
Comments name the server of the keepalive measurements: Instant's hosted server through the throwaway app bd40c50a, not Scribe's production app (#296).

## 2026-09-30 12:04:44 EDT — instant-data-swift `8abcc002cdfaa45eefd87d20aa1d76a1d72c7ba0`
The stale-acknowledgement test accepts a claim deadline the acknowledgement deferral moved later; the race is pre-existing (20 of 20 failures on 0078484f at load 680-940) (#296).

## 2026-09-30 11:39:56 EDT — instant-data-swift `73a94b6ea0c3634d0aa1ac5d6edd24051c3c5f2d`
Record the reader and applier receiver in the change log (#296).

## 2026-09-30 11:39:42 EDT — instant-data-swift `7cf2658e6ccd55fb763dc054ebccb8ec15b56a72`
The live receiver keeps a receive() outstanding while a frame applies (a reader plus one sequential applier, 128-frame buffer), so URLSession keeps answering server pings; a 40 s apply against bd40c50a now keeps its connection (#296).

## 2026-09-30 11:19:40 EDT — instant-data-swift `20fa140bf35567af11879d89dfda16cf7e98b152`
Claim InstantLiveTransportTests.swift for plan 2026-09-30-connection-survival (#296).

## 2026-09-30 10:39:05 EDT — instant-data-swift `d72e8b809b29bab0f0570429c85ac1e4d70cf0f4`
Record the one-replacement reconnect fix in the change log (#296).

## 2026-09-30 10:38:54 EDT — instant-data-swift `473fc933766d7db56e91c41a51b0871c171abd80`
One socket death opens exactly one replacement connection: the delivery pump defers to a scheduled reconnect instead of cancelling it, and a reconnect reuses a session opened after its loss (#296).

## 2026-09-30 10:38:20 EDT — instant-data-swift `2a74f9a8e2f9f1d56d8402b07ac33037bc585be3`
Record the live keepalive evidence suite in the change log (#296).

## 2026-09-30 10:37:52 EDT — instant-data-swift `5740987826273333323c80f40309c839ca823b0a`
An opt-in live suite proves with the library's URLSession transport that a withheld receive() loses the socket after about 20-30 s (POSIX 57), measured through the throwaway app bd40c50a (#296).

## 2026-09-30 09:32:45 EDT — instant-data-swift `920c9f0ae01b1cfb5b26ffd2b2282364589ba2d7`
Claim the connection-survival paths for plan 2026-09-30-connection-survival (#296).

## 2026-09-30 08:29:29 EDT — instant-data-swift `25ac7c612b4279a3fdbd9d76ee89ef44f23f6fa2`
Record the fast-drain revert in the change log (#296).

## 2026-09-30 08:28:59 EDT — instant-data-swift `184767d5f68555d5d26ce0abb8c1ccbe8ed39c7c`
Revert 8bee78eb (the fast-drain server-apply reduction and tail-write stamp guard) for Scribe build 72 (#296). On an iPhone simulator against bd40c50a, bb88af72 (build 71) fell behind a live recording (about 830 pending writes after 11 minutes; accepts 4-15 per 30 s) while 4e281ddd, whose library sources equal 80db4271's, kept up (pending 0-1, accepts 49-54 per 30 s). Library sources are byte-identical to 80db4271 again; ce40ebe3's test-only busy timeout stays.

## 2026-09-30 08:28:44 EDT — instant-data-swift `d0817ce07e3f38ca8e8cd937895802066805f5a1`
Claim the fast-drain revert paths for plan 2026-09-30-fast-drain-revert (#296).

## 2026-09-30 05:53:47 EDT — instant-data-swift `095c7995483f3fb92a84fd4a85b66fdd2aa7b4d9`
Record the retry fault injection's busy timeout in the change log (#296).

## 2026-09-30 05:53:31 EDT — instant-data-swift `ce40ebe3ae5da73a13909922ae07bc17acd184a2`
Let the discard tests' retry fault injection wait for the runtime's own write instead of failing "database is locked" (#296). Measured on frozen exports of 80db4271 and 773429ae alike (24 of 120 and 17 of 120 injections failed; 0 of 480 with a busy timeout): a pre-existing test-harness race, not caused by the fast-drain branch.

## 2026-09-30 05:50:36 EDT — instant-data-swift `69fb74600fb5d8018567430962117d07c73ad262`
Claim the discard tests' retry fault injection for plan 2026-09-30-fast-drain (#296).

## 2026-09-30 04:22:20 EDT — instant-data-swift `214d175f1ccc710a11667a6c818d29dbb52ef9ec`
Record the fast-drain server-apply reduction and the tail-write stamp guard in the change log (#296).

## 2026-09-30 04:19:27 EDT — instant-data-swift `8bee78eb3dd6974734b45280cbeb72d6ab5ac999`
Skip the whole-component rebase for server frames that cannot change the base beneath pending writes (#296). Recording 023's phone peeled and replayed 2,487 writes for each server frame (22.5-24.9 s); in the harness a 2,502-write drain now does 0 rebases, and a tail write that lost to a later-stamped fact shows instead of being dropped from delivery.

## 2026-09-30 01:49:05 EDT — instant-data-swift `e8331558e0a7838ee3a0fec40b9df8190b5ac03e`
Claim the server-apply fast-drain paths for plan 2026-09-30-fast-drain (#296).

## 2026-09-30 01:19:55 EDT — realtime-voice-sqlite-instant `3fbf226f12afa98cfbca21b669b734ab90551308`
Correct the stale-writes channel note: which server results the phone applied during the loop (#296).

## 2026-09-30 01:03:17 EDT — realtime-voice-sqlite-instant `e600c66bc02627992b2fa43468624f78d9413865`
Note the stale-writes branches, the reconnect-loop finding, and the waiting recovery in the Recording 023 channel (#296 #113).

## 2026-09-30 00:58:29 EDT — instant-data-swift `987395d9e540ed8059c70df00af1bd87e94a8dc7`
Record the whole-entity replacement and the deadline deferral with refusal diagnostics in the change log (#296).

## 2026-09-30 00:57:10 EDT — instant-data-swift `4e281ddd0e22a1c4263b44559bf530ab99c4cef4`
Keep delivery claims while a server frame is still applying, and name what a refusal refused (#296). Recording 023's outbox never drained: each reconnect's first query result started a 22-25 s rebase, and the 6 s acknowledgement deadline replaced the connection first, 385 times.

## 2026-09-30 00:51:05 EDT — instant-data-swift `8ed26be3e87a6607200040214bf94094ec5e52df`
Keep an entity whole when it leaves one live query result (#296). Per-fact retraction stripped three list-only fields from 4 of Recording 023's segments on the phone, and typed reads quarantined them.

## 2026-09-30 00:50:50 EDT — instant-data-swift `0666573728322d9f7effaad17ced526bb3cc7ddc`
Claim the delivery-loop, refusal-diagnostics, and whole-entity replacement paths for plan 2026-09-29-stale-writes (#296 #113).

## 2026-09-30 00:30:14 EDT — realtime-voice-sqlite-instant `15ab9dfbac94f26be61f84c6d873eddcc31371f8`
Record ADR 0018 in the change log (#296).

## 2026-09-30 00:30:13 EDT — realtime-voice-sqlite-instant `534e3553238eaad46c91a25d07d6e6e96e2701a7`
Record the recovery tool's cleanup fix in the change log (#296).

## 2026-09-30 00:30:13 EDT — realtime-voice-sqlite-instant `11e8bf532e3a7ec3138fd8479f97bc342ae0c61b`
Record the one monotonic write clock in the change log (#296).

## 2026-09-30 00:29:54 EDT — realtime-voice-sqlite-instant `d90a21365ec78c8767ad01e7655ed7fbc0d22921`
Record ADR 0018: refused replays, one write clock, and recovering a stuck outbox (#296).

## 2026-09-30 00:04:11 EDT — realtime-voice-sqlite-instant `fe1eb9715b79bab2f74e3e9a56dc63cbbfddebef`
Remove the recovery tool's temporary store copy after reading it (#296).

## 2026-09-30 00:04:04 EDT — realtime-voice-sqlite-instant `ac61758495ccbdd1a2bcba1a18c59eae41247cf0`
Give every recording write one monotonic clock for its queue order and updatedAtMs (#296). Later writes of one device can no longer carry earlier stamps, and consecutive final segments no longer interleave their transactions.

## 2026-09-29 23:20:54 EDT — realtime-voice-sqlite-instant `50f88730fa22a2ae4a4b00f9cda373cbc095a931`
Record the outbox recovery script in the change log (#296).

## 2026-09-29 23:20:36 EDT — realtime-voice-sqlite-instant `71588c3d8335abab6e00affb1e695b29e81cacfa`
Add a dry-run-first recovery for a recording whose writes are stuck in a phone's outbox (#296). It writes to production only with --execute --approved-by-michael.

## 2026-09-29 23:08:15 EDT — realtime-voice-sqlite-instant `8b985a5b06ee8e3a8e117400d480da833dff5751`
Plan the Recording 023 refused-write, stalled-outbox, and recovery work and claim its paths (#296 #113).

## 2026-09-29 02:34:15 EDT — realtime-voice-sqlite-instant `f0f9b225375c8df52069e88c20eaa607d4c3de91`
Record the double-comparison share-rule fix in the change log (#113 #282).

## 2026-09-29 02:33:49 EDT — realtime-voice-sqlite-instant `b9b8891b0f20626554a64011019c93d1e44c1596`
Compare share-rule numbers as doubles so shares with fractional section seconds are accepted (#113 #282).

## 2026-09-29 02:12:54 EDT — instant-data-swift `ee3dea04a2a5449b4f36b0f0dd6bc9faf6154859`
Record the Discard guest session flag in the change log (#113).

## 2026-09-29 02:10:15 EDT — realtime-voice-sqlite-instant `cf22dac76254865d7dd70e8fd51e08b703839293`
Keep the product-source architecture rule: no sync-internals wording in the Account feature (#113).

## 2026-09-29 01:53:30 EDT — realtime-voice-sqlite-instant `911c92c7aa487565fbff7e2fee92f81d238ab8d5`
Record the sharing, privacy, and linked-guest merge commits in the change log (#113 #095 #287).

## 2026-09-29 01:52:16 EDT — realtime-voice-sqlite-instant `9db224f6ca2cf298b1523d564b91a6b25623866d`
Merge remote-tracking branch 'origin/main' into agent/claude-opus-5.5/sharing-accounts.

## 2026-09-29 01:51:48 EDT — realtime-voice-sqlite-instant `04c3855c03f4c15037ea715a979a9a2d9d20b064`
Sync settings per account instead of one row every Scribe user shared (#095).

## 2026-09-29 01:51:48 EDT — realtime-voice-sqlite-instant `e3580f00b3edc7101fa9b1303bb48be1012ee290`
Keep the session that owns the library: no static-account button in Settings, a swap guard, no guest discard (#113 #095).

## 2026-09-29 01:44:05 EDT — instant-data-swift `fa570b3d5602b43d6113d928d6e82d2c66fc80cd`
Let apps hide "Discard guest session" on the login screen (#113).

## 2026-09-29 01:42:34 EDT — realtime-voice-sqlite-instant `fa2fb9d11562af62e41d4fad88aee2b76817ccee`
Claim the debug-account settings hunks, the account-swap guard, and per-user settings for the sharing work (#113 #095).

## 2026-09-29 01:38:38 EDT — realtime-voice-sqlite-instant `8da19ec2b38b7fbfe0c9fcb261ac8f108530b487`
Let the sharing access matrix write its rows as JSON for the audit report (#095).

## 2026-09-29 01:38:38 EDT — realtime-voice-sqlite-instant `70aac10ddd73800794874a91b2c993962b0d4d8c`
Add the range share screen with recipient autocomplete (RecordingShareFeature) (#287).

## 2026-09-29 01:38:25 EDT — realtime-voice-sqlite-instant `f0534be282f1955ccdf7a93f27edff2adb3884e6`
Merge a linked guest's library into the account after sign-in; make member and range-share writes work (#113 #095 #287).

## 2026-09-29 00:46:53 EDT — realtime-voice-sqlite-instant `d28f72ac67bb2da84f54d4fd35c493a63e6796eb`
Record the linked-guest merge in ADR 0005 and let the admin tool adopt named earlier-install guests (#113).

## 2026-09-29 00:42:05 EDT — realtime-voice-sqlite-instant `1e806c96cb960d9bc4242a0e28a2dd4833fc1c7f`
Prove the linked-guest library merge end to end and add a dry-run admin fallback (#113).

## 2026-09-29 00:28:17 EDT — realtime-voice-sqlite-instant `3d90401ce721d25be2cf29322a7a1037880114a4`
Merge remote-tracking branch 'origin/main' into agent/claude-opus-5.5/sharing-accounts.

## 2026-09-29 00:28:05 EDT — realtime-voice-sqlite-instant `5b84153fae351eddd0c8e3c1c25d3cce698df0e2`
Claim the schema registration list in ScribeInstantStore.swift for the sharing work (#113).

## 2026-09-29 00:16:28 EDT — realtime-voice-sqlite-instant `3a0f19a977d68c7126b132bf3f2410ca0520d90a`
Pin the prepared sharing and linked-guest rules in the schema contract tests (#113 #095).

## 2026-09-29 00:11:33 EDT — realtime-voice-sqlite-instant `4edb7e061c99594dcdad0c9ff200c939e8c4aef6`
Prepare private media, working member links, range shares, and linked-guest adoption rules (not pushed to production) (#113 #095).

## 2026-09-29 00:09:10 EDT — realtime-voice-sqlite-instant `e13f16831ae57655a8ec117e8afdbc353c6760f0`
ADR 0014: range shares and recipient history (data model for the web and iOS) (#113 #095).

## 2026-09-28 23:43:17 EDT — instant-data-swift `0b0471a89842395ed67eb4b409c23855f9eee091`
Merge remote-tracking branch 'origin/agent/claude-opus-5.5/guest-upgrade-audit' into agent/claude-opus-5.5/sharing-accounts.

## 2026-09-28 23:40:19 EDT — realtime-voice-sqlite-instant `51c59a083c439485cfd4109ce971e206d15153fa`
Plan the sharing audit, linked-guest library merge, and range shares; claim their paths (#113 #095).

## 2026-09-29 00:48:46 EDT — instant-data-swift `204f1e78926692d03c6dcd0c96809ab9b6183356`
Record the log-safe auth session change in the change log (#113).

## 2026-09-29 00:48:24 EDT — instant-data-swift `a9a55563683867e7ab1ed640745a25fa832ff550`
InstantAuthSession prints, debug-prints, and reflects without its refresh token or email, so logging a session or a value that carries one cannot leak the token (#113).

## 2026-09-29 00:41:47 EDT — instant-data-swift `8f313c1a46189f8c2d3f9083f4e9f763040a0e06`
Record the guest-promotion outbox pin and guidance in the change log (#113).

## 2026-09-29 00:41:42 EDT — instant-data-swift `2d29e8f2e7401d7b1d3f38830d5d479db987b5ec`
Pin that a guest's pending write survives a link into an existing account and is sent under the promoted session, and document this divergence from Reactor.updateUser in skills/instant-data/SKILL.md (#113).

## 2026-09-29 00:41:17 EDT — instant-data-swift `3dfe15f9afc345485e2f8e45ba982732d533a8b6`
Record the guest-only OAuth token change in the change log (#113).

## 2026-09-29 00:41:02 EDT — instant-data-swift `f5e1aec4835f5ec7284d5f5019735ac4f65e3e4b`
The ordinary OAuth sign-in forwards the refresh token only for a guest session, matching Reactor.exchangeCodeForToken; ID-token sign-in keeps forwarding any token, matching Reactor.signInWithIdToken (#113). Branch agent/claude-opus-5.5/sharing-accounts.

## 2026-09-29 00:28:37 EDT — instant-data-swift `857e7053d2768844110f1cdc2b4534289b208624`
Plan guest-only OAuth token forwarding, log-safe auth sessions, and the outbox across a guest link; claim paths (#113).

## 2026-09-28 14:43:30 EDT — realtime-voice-sqlite-instant `195f16b9623ebb991f038f3e5577d08c231d9b71`
Log web Scribe on words.knophy.com and Scribe 0.1 (68) with universal links in PROGRESS (#282 #283 #113).

## 2026-09-28 14:29:09 EDT — realtime-voice-sqlite-instant `0c1643ee83f3defac25807bf977a23457ee228d9`
Record Scribe 0.1 (68) in the change log.

## 2026-09-28 14:29:09 EDT — realtime-voice-sqlite-instant `8f943b9cfe331433f807e79416cbfd326ee6c6f5`
Release Scribe 0.1 (68): universal links on words.knophy.com with build 67's copy and link fixes, on the Xcode 27 beta (#283 #282).

## 2026-09-28 14:28:58 EDT — realtime-voice-sqlite-instant `c8e8e3876a3b4820656ebbc04f6765c01c2767dc`
ADR 0012: record the words.knophy.com deployment (dedicated tunnel, Access bypass for only the universal links file) and the iPhone-first sign-in order from the guest upgrade audit (#282 #283 #113).

## 2026-09-28 14:13:05 EDT — instant-data-swift `b65192594f019106ae3d39a48d2c6ed2a41fb84c`
Record the guest-token magic-code fix in the change log (#113).

## 2026-09-28 14:12:40 EDT — instant-data-swift `aa3d97795b2e7a78830bbd9631534cd4357f8625`
Magic-code sign-in forwards only a guest session's refresh token (upstream parity; a revoked non-guest token made verify_magic_code fail live), and auth HTTP failures keep Instant's error type and message without the hint (#113). Branch agent/claude-opus-5.5/guest-upgrade-audit; audit /Users/laptop/Sync/audit/web-scribe-2026-09-28/AUTH-AUDIT.md.

## 2026-09-28 14:07:58 EDT — realtime-voice-sqlite-instant `299dbed641251e05de5c2e136581a76c349cdef0`
Record the universal links change in the change log (#283).

## 2026-09-28 14:07:40 EDT — realtime-voice-sqlite-instant `03c7e1a1409fdc1dae5b67abeb79404ce113107e`
Parse and emit https://words.knophy.com links: shares, copies, and QR codes use the web form; in-app surfaces keep the custom scheme; applinks entitlement on both iPhone lanes (#283).

## 2026-09-28 13:42:16 EDT — realtime-voice-sqlite-instant `f8053eb537cd449bd220fda9d09f15ce8dd8ab65`
Plan universal links on words.knophy.com and claim the link-emission paths (#283).

## 2026-09-28 13:30:57 EDT — realtime-voice-sqlite-instant `e9a80c5fccaf643f5458cb95122e07721a8fc2a6`
ADR 0012: web Scribe on words.knophy.com with one link format for the iPhone and the web (#282 #283 #113).

## 2026-09-28 10:57:13 EDT — realtime-voice-sqlite-instant `0098da75acc67232037846e036cdb4b5c216210b`
Log recording 018's copy and link fixes and build 67 in PROGRESS, with the install held while a recording is active (#280 #036 #233).

## 2026-09-28 10:54:59 EDT — realtime-voice-sqlite-instant `3f7226602defbbe7b79cf8c990620beb65b063ff`
Record Scribe 0.1 (67) in the change log.

## 2026-09-28 10:54:59 EDT — realtime-voice-sqlite-instant `d7475aa2324691e9b257ad6bf5d531dce606f19a`
Release Scribe 0.1 (67): recording 018 feedback on copies and links, on the Xcode 27 beta (#280 #036 #233).

## 2026-09-28 10:54:59 EDT — realtime-voice-sqlite-instant `36dff0a2920924be4121bb1ead0ba019a8c066ee`
Record the recording 018 link and copy fixes in the change log (#280 #036 #233).

## 2026-09-28 10:54:36 EDT — realtime-voice-sqlite-instant `08456f96d16b161093cfcd9689bad5d23154a0cf`
Copies made in Scribe join the recording timeline by default, tagged by the clipboard client from the pasteboard change count, with a toggle to leave them out; a long press on any transcript section offers Copy Text and link actions; the full-screen double tap no longer delays taps on controls (#280 #036 #233).

## 2026-09-28 10:36:14 EDT — realtime-voice-sqlite-instant `67c057f772ab3d7968f8e8267f6314f3c7d596fe`
Plan recording 018's link and copy feedback and claim its paths (#036 #280 #233).

## 2026-09-28 09:23:32 EDT — realtime-voice-sqlite-instant `a938e1fd46602af964917ea82a4815e1ca159317`
Log Scribe 0.1 (66) with section and recording links in PROGRESS, including main's red baseline (63 failing, 2 crashing tests) (#036).

## 2026-09-28 09:16:52 EDT — realtime-voice-sqlite-instant `fda9ea6cb47188b14c72523815011a7f2ff3c6ad`
Record Scribe 0.1 (66) in the change log.

## 2026-09-28 09:16:45 EDT — realtime-voice-sqlite-instant `48b3e5022190e78e98692e3f383dd4f96eb8bf7c`
Release Scribe 0.1 (66): section and recording links on the Xcode 27 beta (#036).

## 2026-09-28 09:14:44 EDT — realtime-voice-sqlite-instant `894346a79b7289e2722dd03efcf37d6cb1cff409`
Record the section and recording links change in the change log (#036).

## 2026-09-28 09:14:25 EDT — realtime-voice-sqlite-instant `96d6c602a45032a7e6da8933e4c09acdc50b633f`
Section timestamps (live and playback) copy or share a link to that moment and the recording list copies or shares a recording link; opening a section link for another recording positions playback and scrolls to and highlights the section once the transcript shows it (#036).

## 2026-09-28 08:42:24 EDT — realtime-voice-sqlite-instant `b8c0d795b076211be389e3cf11fbec902d8d26dc`
Plan deep links to sections and recordings and claim their paths (#036).

## 2026-09-27 17:58:41 EDT — realtime-voice-sqlite-instant `22330e27eb4ea017ab9ac32f3c5e0179a94d6f72`
Log Scribe 0.1 (65) with the reconnect write gate and bad-row repair in PROGRESS (#277 #278).

## 2026-09-27 17:51:24 EDT — realtime-voice-sqlite-instant `a1fa965a462957e83ffaf3852e9277f551c9e37f`
Record Scribe 0.1 (65) in the change log.

## 2026-09-27 17:51:24 EDT — realtime-voice-sqlite-instant `dcec639e97491c51d316d7231aa158445b26adef`
Release Scribe 0.1 (65).

## 2026-09-27 17:37:07 EDT — instant-data-swift `2fced8d1930cb26334ce4581ce14ea94188a01c2`
Migration 0024 drops, once, local entities that lost their id fact to partial pruning (1,067 sections on the iPhone, nothing else), keeping pending ones and never-synced stores, so the server delivers them whole (#278).

## 2026-09-27 17:36:38 EDT — instant-data-swift `246e191d556dd5f873a678eeb019e318dd26a202`
Typed reads leave out and report (reportIssue plus query.row-decode-quarantined) a row that fails to decode instead of failing the whole query; one damaged section had failed recording 008's playback detail (#278).

## 2026-09-27 17:32:08 EDT — instant-data-swift `cd19ba2f59ca890f6ca8b0900ec6bfd84c75e11c`
Claims for triage L's row quarantine: typed read paths, the SQLiteData parity record, and TypedAPITests (#278).

## 2026-09-27 17:19:54 EDT — instant-data-swift `8c66edca71fa7d8eb0be03ccc718b00f7d06d2cc`
Merge the triage integration branch's audit ledger (355f6629) into triage L.

## 2026-09-27 17:06:56 EDT — realtime-voice-sqlite-instant `0258cd0128bac7f724a5a758027443e1f343d3d6`
Log Scribe 0.1 (64), the first Xcode 27 beta build, in PROGRESS (#272 #123).

## 2026-09-27 16:58:17 EDT — instant-data-swift `e08c0327dcb2db442fbe14b482f885cdc9646898`
Change-log ledger.

## 2026-09-27 16:57:42 EDT — instant-data-swift `af3c05849c4ad07b812a8f56abed07dbf757b1cb`
Local writes no longer wait behind server apply: breadth-first component closure and an uncorrelated outbox rewrite cut the operation gate hold during server apply from 23.5 s to 570 ms at 2,000 pending (969 -> 207 ms at 439); the gate names its holder's phase and reports long waits (#277).

## 2026-09-27 16:56:30 EDT — realtime-voice-sqlite-instant `cfcb07ea7e0ae0a18e84b5b5190607560f1157cb`
Record Scribe 0.1 (64) in the change log.

## 2026-09-27 16:56:30 EDT — realtime-voice-sqlite-instant `8c298bc579ea03e1dba4464e37be46f7cab73892`
Release Scribe 0.1 (64), the first build with the Xcode 27 beta (iOS 27 SDK, Swift 6.4).

## 2026-09-27 16:48:46 EDT — realtime-voice-sqlite-instant `7eb83e3c217b8847712a6f87370a7d890b552c2a`
Log Scribe 0.1 (63) with the audio upload and broadcast fixes in PROGRESS (#258 #260).

## 2026-09-27 16:36:22 EDT — realtime-voice-sqlite-instant `2b53e001d770f8f66f9ab3ae3e9c56d7187e7c77`
Record Scribe 0.1 (63) in the change log.

## 2026-09-27 16:36:21 EDT — realtime-voice-sqlite-instant `5bbeeeaeae3053f578b8bac139697a5fa3187e75`
Release Scribe 0.1 (63).

## 2026-09-27 16:23:24 EDT — instant-data-swift `686c6a3d9b0258491f7c5aa8ed6d6b5abc568de0`
Plan and claims for triage L: server-apply operation gate and selected-field row quarantine (#277 #278).

## 2026-09-27 16:21:21 EDT — realtime-voice-sqlite-instant `ce0ef0f24ab42bbff5c342d8a8422c38e8e86a09`
Merge triage A: upload retries from the local store, broadcast survives pauses and interruptions, robust PCM reader, lane and extension diagnostics (#258 #260 #272).

## 2026-09-27 16:19:30 EDT — realtime-voice-sqlite-instant `141775b65c324266b90356a7445923ce5395b754`
Note triage A's landed changes for D, E, F, and G in the channel (#258 #260 #272).

## 2026-09-27 16:18:33 EDT — realtime-voice-sqlite-instant `ae67047dcc9739b24ba1e90931bccac14d54e7ae`
Log Scribe 0.1 (62) with the recording-8 triage fixes in PROGRESS (#259 #274 #273 #275 #272 #123).

## 2026-09-27 16:17:51 EDT — realtime-voice-sqlite-instant `d31ce4365b5b942b5a1b7a72a53f391550c1fa50`
Record triage A's broadcast audio, media scan, and device log commits in the change log.

## 2026-09-27 16:12:15 EDT — realtime-voice-sqlite-instant `3bdf6db664783dd809bae0ffd1447a39680d0ba7`
Merge main into triage A (#258 #260 #272).

## 2026-09-27 16:12:04 EDT — realtime-voice-sqlite-instant `757e209e4090e26d29b721fd0d80f412e61643a4`
Record lane stalls, end reasons, and system-audio evidence in the device log (#258 #260 #272).

## 2026-09-27 16:07:21 EDT — realtime-voice-sqlite-instant `d5ac987a86af7f8c64f7c9449d89be9e2cf9f413`
Release Scribe 0.1 (62).

## 2026-09-27 16:07:21 EDT — realtime-voice-sqlite-instant `0422b3a29402dc8a97c8bca9d503bf144c211663`
Record Scribe 0.1 (62) in the change log.

## 2026-09-27 15:55:57 EDT — realtime-voice-sqlite-instant `90707c27dc3a39b303d8a3d166a3b64fc3fba593`
Declare the capture telemetry dependency once in the Recording reducer (#276).

## 2026-09-27 15:49:15 EDT — realtime-voice-sqlite-instant `7a4ed61b4467b81160c23dabfd8cc7ae06d4e17f`
Merge triage E: recognizer restarts through other apps' voice mode and dictation, stall detection, telemetry, smooth waveform (#272 #123 #225).

## 2026-09-27 15:43:45 EDT — realtime-voice-sqlite-instant `203695fde65462051262a867c44fae9c6c093eb1`
Pausing for another app's voice session no longer ends the user's broadcast (#260).

## 2026-09-27 15:42:57 EDT — realtime-voice-sqlite-instant `efe6991cac2c048bbc06dbf2e9e136b0c480a8d5`
Record the waveform scroll commit in the change log.

## 2026-09-27 15:42:56 EDT — realtime-voice-sqlite-instant `485c131218994e8a2ad7e06c55d1ea040a0da1ac`
Scroll the recording waveform smoothly between level updates (#225).

## 2026-09-27 15:40:33 EDT — realtime-voice-sqlite-instant `2547dfa8a87476510029cfba2294734de667aa7c`
Merge triage F: slow saves never block or pause, self-retrying blocks, interruptions keep recording, capture-health banner, telemetry call sites (#273 #275 #276).

## 2026-09-27 15:36:01 EDT — realtime-voice-sqlite-instant `57a475faf13a4b3ceee87b677d066aa1e6f19ea9`
Record the resume and never-auto-pause commits in the change log (#273 #275).

## 2026-09-27 15:35:28 EDT — realtime-voice-sqlite-instant `3568d897686273ee43854a50458bf2860a8db5cd`
Keep recordings live through durability stalls, interruptions, and capture failures (#273 #275).

## 2026-09-27 15:34:23 EDT — realtime-voice-sqlite-instant `612377c5e1640a11858577f9c4cc9f928078259a`
Record the capture telemetry call sites in the change log.

## 2026-09-27 15:34:22 EDT — realtime-voice-sqlite-instant `82abfba7fd0c5a39900e42bbdc701d1f60445c3e`
Record interruptions, route changes, recognizer errors, and transcription recovery in capture telemetry (#276 #272 #123).

## 2026-09-27 15:32:56 EDT — realtime-voice-sqlite-instant `f8ba32d9fddc572e8ec4d2041f7f0fce1559e0a2`
Merge triage D: saved-movie notification that plays it, live preview of the growing broadcast movie, ADR 0010 (#266 #267).

## 2026-09-27 15:32:47 EDT — realtime-voice-sqlite-instant `0961b2119db8c1bf337101c6fadd5d2611517dfe`
Keep timeline tests off the real 5-second first-snapshot clock (#274).

## 2026-09-27 15:20:59 EDT — realtime-voice-sqlite-instant `84edc77574d44670b8eedb8a129e849db56c052d`
Merge main into the triage D branch (#266 #267).

## 2026-09-27 15:20:33 EDT — realtime-voice-sqlite-instant `b274612bcc25bafa9d40ebdb1ba60a8d2d2b80a8`
Record the saved-movie notification and ADR 0010 live scrub in the change log (#266 #267).

## 2026-09-27 15:19:54 EDT — realtime-voice-sqlite-instant `63348354ba941ca264b54bee29302efb2893e63d`
Decide live scrub plays the growing broadcast movie in Scribe, not Photos; prototype it (#267).

## 2026-09-27 15:19:53 EDT — realtime-voice-sqlite-instant `e72ebd23ad79b732605c5009370a8977acc96a3f`
Announce saved broadcast movies with a notification that opens them in Scribe (#266).

## 2026-09-27 15:13:36 EDT — realtime-voice-sqlite-instant `e5578f3b1ff6d79ec86311ee6f58ed83af7bc952`
Merge main (capture telemetry #276 and triage work) into the speech recovery branch (#272 #123).

## 2026-09-27 15:13:31 EDT — realtime-voice-sqlite-instant `099041a05607c0bce6f6f92a183bf03976e2071b`
Merge triage C: static route snapshot inline, live map mode, iPhone landscape side column, map-state memory context (#263 #264 #265).

## 2026-09-27 15:13:21 EDT — realtime-voice-sqlite-instant `a1ee2a2ad5a270fe1e28128ed39ed08b83fc5e95`
Record the speech recovery commit in the change log.

## 2026-09-27 15:13:21 EDT — realtime-voice-sqlite-instant `8dad9e969803f11c456ffcfbbe8475062a97304f`
Record every mid-broadcast audio format change and the extension footprint (#260 #272 #258).

## 2026-09-27 15:13:15 EDT — realtime-voice-sqlite-instant `ed9ebe06570e0a3e894b7e7faf9fcafc188a6b81`
Merge triage B: 5-second saved-transcript cap with retry, words-missing diagnostic, Return to Latest as the only jump control (#259 #274 #261).

## 2026-09-27 15:13:08 EDT — realtime-voice-sqlite-instant `31068bed756f447d877545fc210d5c7bd049da76`
Restart transcription when the recognizer ends mid-recording, and let Resume start a new speech session (#272 #123 #273).

## 2026-09-27 15:13:03 EDT — instant-data-swift `fc7ce10c59400fe1f7ba28702ec990984d78d03e`
Saturate the live timeout sleep instead of trapping on a far-future deadline (#259).

## 2026-09-27 15:13:03 EDT — instant-data-swift `44f4c0c3c889136603122c9dd0640a8a33ad6e99`
Record the timeout sleep overflow fix in the change log.

## 2026-09-27 15:04:27 EDT — instant-data-swift `14007bdee6ad4387da81c58ffdedef1d4881d914`
Merge the deferred hydration fixes: whole-entity pruning and hydration that keeps its result (#259 #274).

## 2026-09-27 15:02:42 EDT — realtime-voice-sqlite-instant `dc32dee7df5496c7a1ddbcf60543ff59a063993c`
Note agent C's landed regions in the recording screen channel (#263 #264 #265).

## 2026-09-27 15:01:34 EDT — instant-data-swift `27745b1c9eadcfbe800c0a6fa99556f23a155a9e`
Record triage B's library and Scribe commits in the audit ledger (#259 #274 #261).

## 2026-09-27 14:54:01 EDT — realtime-voice-sqlite-instant `f57bf4e683e0742dbf2dd13ca234cf5b22bdd2d3`
Merge main into triage B (#259 #274 #261).

## 2026-09-27 14:53:51 EDT — realtime-voice-sqlite-instant `cddae46615df349d00562f89d52551c957d8a97e`
Change-log ledger.

## 2026-09-27 14:53:35 EDT — realtime-voice-sqlite-instant `e97acdbdda37e4d99b788af85256bef1733f66b3`
Saved-transcript first page bounded to 5 s with a named failure and Retry; playback.detail.words-missing diagnostic (#274 #259).

## 2026-09-27 14:53:35 EDT — realtime-voice-sqlite-instant `95eaeb93320a1bf7523af3a24d989b0ad2347861`
Delete Return to Live and Newer; Return to Latest is the only jump and returns a paged window to the newest rows (#261).

## 2026-09-27 14:53:12 EDT — realtime-voice-sqlite-instant `e4f68b4387bf63acea455dc42b82d82ff56963ee`
Merge main into the map layout branch (#263 #264 #265).

## 2026-09-27 14:49:59 EDT — realtime-voice-sqlite-instant `eeca44e496957d106b53f03d159063b001e1654a`
Scan pending media from the local store, not a live one-shot query (#258).

## 2026-09-27 14:42:17 EDT — realtime-voice-sqlite-instant `8ef6a2511e5e20b935532d13e2ac04536616a51f`
Record the snapshot route map, map mode, and landscape layout in the change log.

## 2026-09-27 14:42:01 EDT — realtime-voice-sqlite-instant `5f46fdc442b8e3a0eb2be60438f246b7c6f4aca9`
Add map mode and a landscape side column to the recording screen (#264 #265 #263).

## 2026-09-27 14:41:27 EDT — realtime-voice-sqlite-instant `975ceaa2c1473060c4def9f27ddc7c19672c0982`
Draw the inline route map over one snapshot image instead of a live map (#263).

## 2026-09-27 14:41:21 EDT — instant-data-swift `4a5d63a1fe892de63e00dca746150fd0d8de2f43`
Change-log ledger.

## 2026-09-27 14:28:19 EDT — realtime-voice-sqlite-instant `ef245700542f6277f6690fb8b88267fd982c7ebc`
WIP: resume-after-block lane, list, and reducer changes before merging telemetry (#273 #275).

## 2026-09-27 14:28:19 EDT — realtime-voice-sqlite-instant `1ec66938c9b31594e20b3c29960dd2478f34d85a`
Merge main (capture telemetry #276) into the resume branch (#273 #275).

## 2026-09-27 14:25:41 EDT — realtime-voice-sqlite-instant `be9d727c73d84f592aa2a11f36cdb709609bb632`
Merge capture telemetry: typed, lock-light event recorder with batched background writes (#276).

## 2026-09-27 14:25:33 EDT — instant-data-swift `552457420ee3dfea8b72514257307b76606b027d`
Deferred hydration drops a stale emission only when its query was refreshed after it; live-query pruning collects whole entities only and deletes their deferred payloads (#259 #274).

## 2026-09-27 14:24:16 EDT — realtime-voice-sqlite-instant `a910b6332f5a79df5cdbc1b8031342c3c45b51a8`
Record the #273 device evidence and the fix split in the channel (#273 #275).

## 2026-09-27 14:23:30 EDT — realtime-voice-sqlite-instant `b0e60432ed3fe9188538233d4d06bc9097bbd7f9`
Record the capture telemetry module commit in the change log (#276).

## 2026-09-27 14:23:07 EDT — realtime-voice-sqlite-instant `f511f75613d197f9bc05095f5c433dab57312c10`
Record the capture telemetry commits in the change log; post the API for agents E and F (#276).

## 2026-09-27 14:22:45 EDT — realtime-voice-sqlite-instant `a674927cd4164888f304d44fd08cc0cc7207fcae`
Export capture telemetry through the device pull and the triage skills (#276).

## 2026-09-27 14:22:45 EDT — realtime-voice-sqlite-instant `998d0c68ca216711d4188870a4a3f012ab565782`
Add lightweight capture telemetry: typed events, two rings, batched off-thread JSONL (#276).

## 2026-09-27 14:21:42 EDT — realtime-voice-sqlite-instant `acc004ff9176d0e1e0c82e3e97b4b5d2a54b80ca`
Read ReplayKit PCM at its real sample width and never past a buffer's end (#260 #272 #229).

## 2026-09-27 14:10:22 EDT — realtime-voice-sqlite-instant `23614c42db043949b39f1a45a9c063d7ff071374`
Plan lightweight capture telemetry; claim its paths (#276).

## 2026-09-27 14:02:19 EDT — instant-data-swift `436bebe3eed8b84783b09d8e2d144f43c3db3656`
Plan and claims for the deferred hydration progress fix (#259 #274).

## 2026-09-27 14:02:18 EDT — realtime-voice-sqlite-instant `5d59438ad370dff5a45caa1411426e48bf88ee7a`
Plan and claims for triage B: words, saved-transcript loading, jump controls (#259 #274 #261 #020 #262).

## 2026-09-27 14:00:01 EDT — realtime-voice-sqlite-instant `5a8156d014c661e3240f6025d70fd29125560a80`
Plan the resume-after-pause fix; claim paths (#273).

## 2026-09-27 13:59:00 EDT — realtime-voice-sqlite-instant `41ebe817812fc5bec6a86a8147f903dc6b39288b`
Plan speech recovery through other apps' voice modes, audio input selection, and meter rate; claim paths (#272 #123 #268 #225 #271).

## 2026-09-27 13:58:46 EDT — realtime-voice-sqlite-instant `e2d2b022cad12e5b0641bf4bb9eabdecf0a51544`
Add the triage-scribe skill and a read-only recording evidence script (#270).

## 2026-09-27 13:58:46 EDT — realtime-voice-sqlite-instant `6122b84052c4b63ebe5bc3ac32434090a8928cf7`
Record the triage-scribe skill in the change log.

## 2026-09-27 13:56:49 EDT — realtime-voice-sqlite-instant `74b42ff8ee8f8a6fb04b52bbf11456dafef01dda`
Plan the triage-scribe skill; claim its new paths (#270).

## 2026-09-27 13:56:24 EDT — realtime-voice-sqlite-instant `b42db55844a85f14a649820c8eb3214c58eaff9d`
Plan triage A: broadcast audio, extension stop, voice-session audio; claim paths (#258 #260 #272).

## 2026-09-27 13:52:25 EDT — realtime-voice-sqlite-instant `7d6f97c5a8c31969c13c80d627b0614a3b016d0f`
Plan the map memory cut, map mode, and landscape layout; claim paths (#263 #264 #265).

## 2026-09-27 13:50:59 EDT — realtime-voice-sqlite-instant `dfaccd6a6c4fe3242b70462eb5408d7c3431b264`
Plan the saved-movie notification and live scrub research; claim paths (#266 #267).

## 2026-09-27 12:47:34 EDT — realtime-voice-sqlite-instant `a5b192c298927e36080235ef352386bc6f760c6f`
PROGRESS: Scribe 0.1 (61) on the iPhone and the Mac app with the phone-to-Mac stream (#003 #224 #257).

## 2026-09-27 12:44:30 EDT — realtime-voice-sqlite-instant `a89cf77c577991f6ee2793a73f5deff22b54589e`
Mac installs with the published Instant pin no longer die on macOS bash 3.2's empty-array rule in install_scribe_shared_app.sh; new /bin/bash test (#257).

## 2026-09-27 12:44:30 EDT — realtime-voice-sqlite-instant `4ebefe7b27fd632c1de0f9b4bfeef1d31723fc1b`
Change-log ledger.

## 2026-09-27 12:37:15 EDT — realtime-voice-sqlite-instant `f16bc252530987631e3478de3555e38c2b810e78`
Change-log ledger.

## 2026-09-27 12:37:15 EDT — realtime-voice-sqlite-instant `d719ec8b024143a5508fb875b08b4219edc0a891`
Release Scribe 0.1 (61).

## 2026-09-27 12:37:15 EDT — realtime-voice-sqlite-instant `c577c7eac0b3bcef430504fac7229489f6995c7b`
Change-log ledger.

## 2026-09-27 12:35:10 EDT — realtime-voice-sqlite-instant `f36908497ea916e745c38c3e3346b0d4cf70c3c9`
Agent room thread-page test expects the bounded tool-call query the Stream Interactor added (limit 32) (#256).

## 2026-09-27 12:14:42 EDT — realtime-voice-sqlite-instant `e89b9182f9a3198ef9cfdf64229e868b0fd3344a`
Merge fork F's phone-to-Mac stream into main: broadcast extension encodes and streams screen with mixed system audio and mic to the Mac ingest, OBS relay goes live only once phone media arrives, LiveKit removed (#003 #224 #229 #255).

## 2026-09-27 12:05:33 EDT — realtime-voice-sqlite-instant `e4e26c6402f28dfa375c4a20e2b005dc8eb04061`
Renumber the stream decision to ADR 0009; fork E's Stream Interactor took 0008 (#003).

## 2026-09-27 12:02:00 EDT — realtime-voice-sqlite-instant `b9e47fb7600dbd32334bf839b90543af4744f075`
Refuse streams to sessions a restarted Mac forgot, and keep the ingest types building on watchOS (#003).

## 2026-09-27 11:44:07 EDT — realtime-voice-sqlite-instant `67df82eda5083871595e42d17958a25d9c003309`
Keep quiet broadcasts streaming in sync, let OBS open early, and check OBS from the harness (#003).

## 2026-09-27 11:14:33 EDT — realtime-voice-sqlite-instant `4da1b812151314381d68025ea697d1812a3ce53d`
Log Scribe 0.1 (60) with the audio fixes and the Stream Interactor in PROGRESS (#142 #122 #256).

## 2026-09-27 11:09:19 EDT — realtime-voice-sqlite-instant `c241f29e5fe98e8e84a3fe2b91f585c65fb3f040`
Change-log ledger.

## 2026-09-27 11:09:18 EDT — realtime-voice-sqlite-instant `2477874337d40581310a089dd6bf5fc8b640346f`
Release Scribe 0.1 (60).

## 2026-09-27 11:04:36 EDT — realtime-voice-sqlite-instant `cf95ad4fa3fc266889f7db0d75cc3739e535d60b`
Merge fork E's Stream Interactor into main: directed-speech trigger (2.3% false starts vs 51%), Mac worker threads, transcript cards, thread screen, taps, deep links (#256).

## 2026-09-27 10:56:39 EDT — realtime-voice-sqlite-instant `9af9ee523fefcc9bff3ebb6f83b4e574bb9ebc34`
Merge fork H's audio fixes into main: system-audio sections timed over their own audio in the recording (#142), loudspeaker routing preference and microphone level logging (#122), scripts/audio-route-ab.py.

## 2026-09-27 10:53:29 EDT — realtime-voice-sqlite-instant `aeb843a2160d29cc567f587c63af8c67b1284e23`
Print the speaker-routing microphone A/B from a diagnostics pull (#122).

## 2026-09-27 10:49:27 EDT — realtime-voice-sqlite-instant `3867d05b307fe8d88b91d711561564d62a5c3f0d`
PROGRESS: Scribe 0.1 (59) installed on iPhone with route maps and the permissions fix (#028 #083).

## 2026-09-27 10:45:33 EDT — realtime-voice-sqlite-instant `b92af88078ec62351c1dbfed55b1568a423eb74d`
Keep other apps on the loudspeaker while recording, behind a preference (#122).

## 2026-09-27 10:45:21 EDT — realtime-voice-sqlite-instant `17f99e8de3248de22693d30926ef9cca50e3b49d`
Time system-audio sections over their own audio in the recording (#142).

## 2026-09-27 10:42:03 EDT — realtime-voice-sqlite-instant `72a548659fd4a6e6d0141c67247d1cb4ed3ba56b`
Remove LiveKit from Scribe and add the Mac-side stream harness (#003).

## 2026-09-27 10:39:59 EDT — realtime-voice-sqlite-instant `e6dd18453fad37ea4428ecbf2271990eb3c6d3c7`
Deep link to interactor threads, answers, and transcript moments (#256).

## 2026-09-27 10:39:46 EDT — realtime-voice-sqlite-instant `fb4340a092db1d3553060fce5ba53101da7c92d8`
Change-log ledger.

## 2026-09-27 10:39:46 EDT — realtime-voice-sqlite-instant `da2cb1fdf6a338fd405aaf1fae310e1e25581fc5`
Release Scribe 0.1 (59).

## 2026-09-27 10:28:30 EDT — realtime-voice-sqlite-instant `06f5d27b62b6bfde8edc88274e68ec6c745febf3`
Remove route-finalize-shapes.mjs, whose expectations the permissions fix inverted; route-update-shapes.mjs covers both shapes (#028 #083).

## 2026-09-27 10:28:14 EDT — realtime-voice-sqlite-instant `f8f60159e72376433bcc72ae6c832225689f183d`
Merge fork G's route maps into main: route chunks in their own transactions, elapsed-stamped capture, playback/live/recordings maps, route deep links (#028 #083).

## 2026-09-27 10:27:49 EDT — realtime-voice-sqlite-instant `f0be586fc1989aa84dee786029d10ecc030537ce`
Change-log ledger.

## 2026-09-27 10:27:35 EDT — realtime-voice-sqlite-instant `ad37dd61b17044a9f95e53b2afda278e80a0c762`
Production route chunk rule accepts re-sent identity fields and the same-recording link, so build 58 recordings with a route keep their final summary; pushed to production, drift check matches; route-update-shapes 10/10, app-write-shapes 14/14 (#028 #083).

## 2026-09-27 10:23:00 EDT — realtime-voice-sqlite-instant `9606f5a8da90fa263124d2ccdb2eb747fcdddef5`
Show worker threads in the transcript and buzz gently on answers (#256).

## 2026-09-27 10:20:33 EDT — realtime-voice-sqlite-instant `8c0b917a29ae5e4c10dc3f571288842dcc47a366`
Keep route taps off tvOS and add the finalize-shape permissions regression (#028 #083).

## 2026-09-27 10:10:10 EDT — realtime-voice-sqlite-instant `39e4ca0704d32905718232c15541fb5adf4c5c85`
Document recording route maps: time mapping, capture rules, write isolation, bounds, links (#028).

## 2026-09-27 10:01:56 EDT — realtime-voice-sqlite-instant `7fe341cfb1c02cc23d63b994b9b4c79078adc706`
Serve the phone stream from the Mac's ingest server and relay it through OBS to Twitch or YouTube (#003).

## 2026-09-27 10:01:49 EDT — realtime-voice-sqlite-instant `47391ebbce77e2d922718ccc81c898e12e8ff5cd`
Close a recording's last route chunk with only its mutable fields, and add a terminal route probe (#083 #028).

## 2026-09-27 10:01:31 EDT — realtime-voice-sqlite-instant `c5dcba4939f9f2c56fc7f9a48d437ffa92bae392`
Change-log ledger.

## 2026-09-27 10:01:30 EDT — realtime-voice-sqlite-instant `2ca1ed194a9957791756e26409506dc2da1fe377`
Scribe pins Instant 1.7.0 and the installer expects it; v1.7.0 sources equal 2f55c81b, which Scribe 0.1 (58) embeds (#250 #254 #155). Scribe main fast-forwarded to c5dcba49.

## 2026-09-27 09:58:40 EDT — realtime-voice-sqlite-instant `f3d84d33b5b7690f7df182f327b0a3db4a45e38f`
Run Stream Interactor workers from a Mac daemon (#256).

## 2026-09-27 09:58:40 EDT — realtime-voice-sqlite-instant `9b5be52e6de6e4e195709e1287a98d3062ec5291`
Page agent segments with queries the Instant server accepts (#256).

## 2026-09-27 09:45:50 EDT — realtime-voice-sqlite-instant `10868c034210116b899e659b844b0e66ee3d48ad`
Draw every recording's route on the map, open a recording from any point, and deep link route moments (#028 #018).

## 2026-09-27 09:44:10 EDT — realtime-voice-sqlite-instant `0167a28c12a608139ef897405b35ea43846c2977`
Stream the broadcast from the extension to a Mac ingest server, next to the Photos movie (#003 #224 #255).

## 2026-09-27 09:42:04 EDT — realtime-voice-sqlite-instant `7c26725dcce962a5a7f430da3775f6f70fc7c6b0`
Show the route walked so far on the recording screen and scroll the transcript from it (#028).

## 2026-09-27 09:36:47 EDT — realtime-voice-sqlite-instant `963bb3bbd9610353c82b67933f755280ba70e36e`
Show a recording's route in playback and move playback by tapping the route (#028 #018).

## 2026-09-27 09:24:48 EDT — realtime-voice-sqlite-instant `c32825e2e229c356768565ae9f5cf20d10098453`
Map recording routes to moments of the audio and back, with a bounded live trail (#028).

## 2026-09-27 09:18:51 EDT — realtime-voice-sqlite-instant `397311f633478c56d5dbbdcab1d64503d9142f80`
Keep stale and cell-tower fixes off recording routes and stamp each sample with elapsed time (#083 #028).

## 2026-09-27 09:09:12 EDT — instant-data-swift `252bb6cd79ed6fa6b966de29a770e204598cbc0a`
Release commit for v1.7.0 (change log, audit ledger, PROGRESS); tagged v1.7.0 and published, main fast-forwarded (#250 #254 #155).

## 2026-09-27 09:08:40 EDT — instant-data-swift `18831d088dbb50cfc7e6950c47fe8d7e5d40d1d0`
Release document for v1.7.0: payload-order JSON decode, one schema resolution per refresh, copy-free result sort, change-only snapshots, 16 MiB diagnostics file cap (#250 #254 #155).

## 2026-09-27 09:07:37 EDT — realtime-voice-sqlite-instant `319ce767bfd0b34dbfe9a7dcb37ab4ad9459e1d4`
PROGRESS: Scribe 0.1 (58) iPhone install on the merged library (#247 #252 #224 #250 #257).

## 2026-09-27 08:58:19 EDT — realtime-voice-sqlite-instant `2435063de5b93dd02a33e8f6c51cdf4414157e7c`
Start interactor work only for speech addressed to it (#256).

## 2026-09-27 08:50:49 EDT — realtime-voice-sqlite-instant `233799644121b9caebd6f17eb281dc7e2b42e85c`
Write route chunks in their own transactions so a chunk can never block recording data (#083 #028).

## 2026-09-27 08:23:44 EDT — realtime-voice-sqlite-instant `c1c7b6e578bcea2bc96cbe5e6dc8f927c37bce08`
Change-log ledger.

## 2026-09-27 08:23:22 EDT — realtime-voice-sqlite-instant `ab4ef7812c180d6a6829c756708765dac85316b9`
Local-Instant installs build the Instant checkout edit mode verified instead of a hardcoded path (#257).

## 2026-09-27 08:23:22 EDT — realtime-voice-sqlite-instant `3e2b26f320b57b80130def5b3d9b42c7432b8595`
Release Scribe 0.1 (58).

## 2026-09-27 08:19:54 EDT — realtime-voice-sqlite-instant `5731cc8481b2028d8143aa4840c8ea518870b7cd`
Merge fork A's memory diagnostics work into the integration branch (#252 #254 #044).

## 2026-09-27 08:19:49 EDT — realtime-voice-sqlite-instant `f9c0583f8b018766878d45b0c03f6ad8606ea559`
Merge fork B's broadcast reliability work into the integration branch (#224 #044).

## 2026-09-27 08:19:29 EDT — realtime-voice-sqlite-instant `5cb0d29f85794a1b96165869ee364936900488be`
Merge fork D's Scribe performance and concurrency audit into the integration branch (#250 #155).

## 2026-09-27 08:09:57 EDT — instant-data-swift `2f55c81bf40084a7f206eb2e182a349b0b37829e`
Merge fork A's diagnostics file cap into the integration branch (#252 #254 #044).

## 2026-09-27 08:09:46 EDT — instant-data-swift `886a6fabb1a59d1db493a324bfc677e5476a5a03`
Merge fork D's library performance audit (decode order, one schema resolution per refresh, change-only snapshots) into the integration branch (#250 #155).

## 2026-09-27 08:08:55 EDT — realtime-voice-sqlite-instant `355161370e88070e5c8f763e9e23a88cc4fff338`
Change-log ledger and permissions channel for the production permissions fix.

## 2026-09-27 08:08:54 EDT — realtime-voice-sqlite-instant `15e300aa467fe597d2dcd8cc4a03ed3cda342df2`
Production permissions: CEL int/double comparisons wrapped in double() with null guards; route chunks link through explicit owner and recording checks; recordings allow linking routeChunks. Throwaway-app suite: 14 of 14 cases as expected (8 owner writes accepted, 6 refused).

## 2026-09-27 01:55:14 EDT — realtime-voice-sqlite-instant `fe804fe8992c0d45618020dcf0a0324fb651bed6`
Change-log ledger.

## 2026-09-27 01:55:14 EDT — realtime-voice-sqlite-instant `6a596fd0c9f5ca242d2324a01ba357841e6c11e1`
MetricKit signposts for recording and broadcast intervals; pull script summarizes signpost metrics (#252 #044).

## 2026-09-27 01:37:57 EDT — realtime-voice-sqlite-instant `947a5642be98b488a81de7e0174a9483bde8405e`
Change-log ledger.

## 2026-09-27 01:37:57 EDT — realtime-voice-sqlite-instant `5365c7102caa39c6d5302a6a31abce1d294f106c`
Region breakdowns on falls of 12 MB or more too, so a footprint flip is captured on both sides (#252 #044).

## 2026-09-27 01:33:54 EDT — realtime-voice-sqlite-instant `9d4a951eb10d18e0d84a9a814d1286d85d054854`
Change-log ledger.

## 2026-09-27 01:33:39 EDT — realtime-voice-sqlite-instant `2b29b0508a4ad35bbf5df336e889d7a652acb94b`
System surface updates flow through one long-lived effect fed by @Shared state, so TCA no longer retains a task per timer tick, section, or list update; Simulator soak: live tasks +142/min before, flat after (#252 #044).

## 2026-09-27 01:32:22 EDT — realtime-voice-sqlite-instant `aa560a222befa6e8dc06b9a4fd0204fa7de205ef`
Log redactor skips the regex for values without ':' or '='; 21.9 -> 2.5 us per event, identical results (#252 #250).

## 2026-09-27 01:27:05 EDT — realtime-voice-sqlite-instant `0a3b8b4b8acb46c86ed81b8bdcbd70979107481a`
Claims for the next change (coordination protocol).

## 2026-09-27 00:51:27 EDT — realtime-voice-sqlite-instant `99a6e5ae2d3bd09a375adf428ca6eae8fd83e658`
Mac CPU regression harness (scripts/perf) and performance-budget reference numbers from the audit's paired soaks (#250). Branch agent/claude-opus-5.5/perf-audit-2026-09-26.

## 2026-09-27 00:46:15 EDT — realtime-voice-sqlite-instant `5ea26b81d260ef5a0f1a584d6efe073f4be8a0d2`
Claims for the next change (coordination protocol).

## 2026-09-27 00:40:09 EDT — realtime-voice-sqlite-instant `2ba82fd657aaf8d06ef5c9afbd1d9ec8e350cd61`
Change-log ledger.

## 2026-09-27 00:40:09 EDT — realtime-voice-sqlite-instant `dab45cbef7aaf0f55823cfd1ffa46a9d07df7b5a`
Recorder test guard: thread assertions apply only when TestStore's main serial executor was off (#252).

## 2026-09-27 00:39:55 EDT — realtime-voice-sqlite-instant `1abf3e0d491d6aa133e5cffc73cc8644dbe17ba1`
Journal rows kept in a read-only map of the file after load, compaction, and every 256 KiB of appends; MallocStackLogging: 6.46 MB live heap -> 0.54 MB for 4,000 rows (#252 #044).

## 2026-09-27 00:20:42 EDT — realtime-voice-sqlite-instant `2ed42916dd301acf7ce087e1d96ee2694be45ba6`
Read transcript row values once per pass instead of per row through the scoped store (#250 #044). Branch agent/claude-opus-5.5/perf-audit-2026-09-26.

## 2026-09-27 00:20:32 EDT — instant-data-swift `e3cf7c01a1fc5f64753ef0d857e851140c67a39d`
Decode server JSON without throwing an error per string; ABBA thread CPU 513 -> 225 ms per 40 refresh decodes (#250 #155). Branch agent/claude-opus-5.5/perf-audit-2026-09-26.

## 2026-09-26 23:58:30 EDT — instant-data-swift `cb6e9e45ed4cd826a4ed33af977ddaf8924b53de`
Cap the diagnostics file at 16 MiB by default and keep one previous file; a writer on a just-rotated file reopens instead of rotating again (#254). Needs a library release before Scribe (pinned 1.6.0) picks it up.

## 2026-09-26 23:48:59 EDT — realtime-voice-sqlite-instant `5afb78fca3ea92ebc1ddd931a92744120b3444d3`
Change-log ledger.

## 2026-09-26 23:48:49 EDT — realtime-voice-sqlite-instant `2b5d4e8536046c77605f037e67ee1b3f9afe9acd`
Collector outbox spool capped as a delivery queue (1,024 rows / 2 MiB) instead of a second device log; phone outbox was 4.3 MB after the hour (#252 #044).

## 2026-09-26 23:46:09 EDT — realtime-voice-sqlite-instant `4ea3db281a2c3a2ba68ba60d01cc8e432b567b41`
Claims for the next change (coordination protocol).

## 2026-09-26 23:41:53 EDT — realtime-voice-sqlite-instant `acedae1b63f57883023b4c77c39ed0bd36f8d574`
Change-log ledger.

## 2026-09-26 23:41:43 EDT — realtime-voice-sqlite-instant `cda248bf77adde7b1fabd832582ac052c783ba36`
One first-sample region breakdown per process (trigger shared across sampling-task restarts); dylib __DATA split from VM_ALLOCATE; pull script reads the library's previous log file (#252 #044).

## 2026-09-26 23:31:55 EDT — realtime-voice-sqlite-instant `d0c3fbbc740613df6557070b2240467e885327fe`
Change-log ledger for the launch watchdog fix and the memory diagnostics (#252 #044).

## 2026-09-26 23:31:34 EDT — realtime-voice-sqlite-instant `36af3ae1286554b1fc6589cdb9a5ad7d4d3c31fd`
Record where memory lives: kernel ledgers (graphics, media, neural, purgeable, compressed, headroom) on every memory sample, VM region breakdowns on thresholds and jumps, and samples every 30 s while recording in the background with feature context (#252 #044).

## 2026-09-26 23:31:28 EDT — instant-data-swift `87b7687dcbf34103def0fcca51fb9bbbcd07967a`
Record repeating infinite-query snapshots only when they change; 97.8% / 79.7% of two per-refresh events were exact repeats on the phone (#250 #155). Branch agent/claude-opus-5.5/perf-audit-2026-09-26.

## 2026-09-26 23:31:01 EDT — realtime-voice-sqlite-instant `4e4d9908f4a54473f31137a3a36598822157a272`
Stop resolving the host name in App.init: ProcessInfo.hostName blocked a first launch for 20 s and iOS killed the app (0x8BADF00D); local device name plus an architecture test (#252 #044).

## 2026-09-26 23:23:17 EDT — realtime-voice-sqlite-instant `1a9392ddbc05d4e3441edff89ca5257cb18999cd`
Change-log ledger for the device diagnostics pull (#044).

## 2026-09-26 23:22:57 EDT — realtime-voice-sqlite-instant `db51b89467084adaa388855b48a705462b051394`
scripts/pull-device-diagnostics.py pulls on-device diagnostics after the fact and writes a Markdown/JSON report; skill scribe-device-diagnostics, referenced from scribe-install (#044).

## 2026-09-26 23:13:13 EDT — realtime-voice-sqlite-instant `d2e6fbc69a2f5dec5ffbc28d7f0d23a102222577`
Render the recording timeline once per mutation, not per internal write; ABBA thread CPU (debug) 300 live partials on a full window 1,020 -> 199 ms (#250 #044). Branch agent/claude-opus-5.5/perf-audit-2026-09-26, not on main.

## 2026-09-26 23:08:29 EDT — instant-data-swift `44b176a492b5d883fb58c6bf29287b689354ebb5`
Resolve the schema once per live refresh and sort persisted results without string copies; ABBA thread CPU (debug) translate 5,123 -> 1,223 ms, persisted results 1,071 -> 627 ms, empty merges eliminated (#250 #155). Branch agent/claude-opus-5.5/perf-audit-2026-09-26, not on main.

## 2026-09-26 22:58:49 EDT — realtime-voice-sqlite-instant `088f6c79fa35b17671545d5ac202a2aa1610ce30`
Plan-only commit: performance and concurrency audit, Scribe side, with _touching claims (#250).

## 2026-09-26 22:58:49 EDT — instant-data-swift `fc1134fd6be928f3e327f2a47989be3d2735b60e`
Plan-only commit: performance and concurrency audit, library side, with _touching claims (#250).

## 2026-09-26 22:33:35 EDT — realtime-voice-sqlite-instant `06988a4c36c03451ec343fae0d4df7c08b5f21bc`
Plan-only commit: memory audit and after-the-fact device diagnostics, with _touching claims (#044).

## 2026-09-26 21:10:38 EDT — realtime-voice-sqlite-instant `b2a8614ead7ec79f20977e775ac3057235b8c2bf`
PROGRESS: Scribe 0.1 (57) installed and running on Michael's iPhone from clean cc684872 with instant-data-swift 1.6.0 (#247 #044).

## 2026-09-26 21:02:46 EDT — realtime-voice-sqlite-instant `cc684872d7f36fb33c492b446f35ac633e4e60a6`
Change-log ledger for the single guest sign-in fix; this commit was installed on the iPhone as Scribe 0.1 (57) (#247).

## 2026-09-26 21:02:30 EDT — realtime-voice-sqlite-instant `59f9bb55b9680ca816eb9d554ac3d648bdd4a72a`
Sign in as one guest per app at launch: ScribeInstantAuthGate joins concurrent reconciliations; the composition root opens the live default client once per app and database file (ScribeLiveClientRegistry). The regression test reproduces two guests without the gate (#247).

## 2026-09-26 21:00:33 EDT — realtime-voice-sqlite-instant `2b73c7b824deb86279c5f4ffdae3a3f8c1a03c5d`
Plan-only commit: single guest sign-in fix with _touching claims (#247).

## 2026-09-26 20:10:25 EDT — realtime-voice-sqlite-instant `6d829c54233ff0e1456f3347a034fa08ad9f8722`
Installer expects instant-data-swift 1.6.0 (stable-deployment check); GitHub main fast-forwarded 9a7dba56 -> 6d829c54, SQLite kept on backup/sqlite-data-lane (#044 #155).

## 2026-09-26 20:08:44 EDT — realtime-voice-sqlite-instant `f871e43f060ef9e3ac75b959c5ff3fa0da19f3ad`
Change-log ledger for the 1.6.0 pin and Scribe 0.1 (57).

## 2026-09-26 20:08:13 EDT — realtime-voice-sqlite-instant `baaafb580e7fdad4c385e273fc01242731e3b423`
Pin instant-data-swift exact 1.6.0 (a7d0eafd) instead of the local path dependency; ScribeInstantStoreTests 46, ScribeRecordingLibraryMemoryTests 12, InstantRecordingWriteCoordinatorTests 12 pass against the tag (#044 #155).

## 2026-09-26 20:08:13 EDT — realtime-voice-sqlite-instant `8ca78b8ede0e8fb862f9eed2705ad9d3fcfc834e`
Release Scribe 0.1 (57): GitHub main shipped 56, the Instant merge carried 13, 57 never used.

## 2026-09-26 20:08:04 EDT — realtime-voice-sqlite-instant `6bfd5c7bd5a6b9534dd11f9ae7e51855249a82c5`
Plan-only commit: Instant 1.6.0 pin and Scribe 0.1 (57) install, with _touching claims (#044 #155).

## 2026-09-26 19:28:43 EDT — instant-data-swift `94166c5a05df475e831fbcedeff24e11d2a8c700`
Handle new and small entities whole and capture whole delete cascades: the v1.6.0 release gate showed per-fact bookkeeping made small-entity writes 12-45% slower than 1.5.7; after the fix inserts/streams/scalar/reads are at parity, update 1.09x, delete 1.10x; rollback now restores multi-level cascade deletes (#044 #155).

## 2026-09-26 18:07:24 EDT — realtime-voice-sqlite-instant `5bf28e38594c4cf8339f67a81b96ab7f0168ac9d`
Merge the preview-slot list fix and library write-scope follow-ups into the Instant main candidate (GitHub main + combined + #248 #249); only CHANGELOG/PROGRESS conflicted (#044 #155).

## 2026-09-26 18:04:43 EDT — instant-data-swift `c24724c9871a5859b82bd2013e309a0db13b1689`
Document the v1.6.0 release (writes cost what they touch): per-fact write scope, in-place multi-value slots, share-gated store snapshot, nested-limit docs; measured before/after and the offline-runner publication rule (#044 #155).

## 2026-09-26 18:03:26 EDT — instant-data-swift `183370d9d923af3dd2a126fc5c10d5f6c89095a6`
Plan-only commit on `main`: write-scope and v1.6.0 release plan, channel note, and `_touching` claims for every path the implementation changes (#044 #155).

## 2026-09-26 17:35:34 EDT — instant-data-swift `546da49f2783bf3b3af122fbb51d097961ecc7ed`
Skip the full-store snapshot on writes when no share can refuse them; 40 one-field writes on a 20,000-fact store 6.09 s -> 0.069 s (Debug). Local branch `agent/claude-opus-5.5/scribe-perf-2026-09-24`, not pushed (#044).

## 2026-09-26 16:59:27 EDT — instant-data-swift `7c567126f9a0eb35cade7e3d8d4f324bc8562997`
Say plainly that nested include limits do not bound the network: fetch-request guidance, include comment, and parity note (#155).

## 2026-09-26 16:53:50 EDT — instant-data-swift `636c348880612ad6e11d1feed6ba4c3b39962a51`
Capture and persist only the facts a write touches: per-fact rollback capture, scoped SQLite rewrites, and in-place multi-value slots; 50 writes on a 16,000-link recording 33.4 s -> 0.13 s (Debug). Local branch `agent/claude-opus-5.5/scribe-perf-2026-09-24`, not pushed (#044 #155).

## 2026-09-26 16:12:45 EDT — realtime-voice-sqlite-instant `100e69b024e7bd83e20946af86d0cf9c8823bb76`
Pace the preview-slot backfill and retry admin rate limits; applied to production 2026-09-26: 241 recordings linked, 116 without segments. Local branch `agent/claude-opus-5.5/combine-instant-2026-09-24`, not pushed (#044 #155).

## 2026-09-24 23:49:13 EDT — realtime-voice-sqlite-instant `7fb9ea4a8124165b12b9b9900f5e943d99286f24`
Bound list previews with two has-one slots instead of an unbounded nested include; the two links were pushed to the production schema on 2026-09-26. Merged into local branch `agent/claude-opus-5.5/combine-instant-2026-09-24`, not pushed (#044 #155).

## 2026-08-20 14:32:00 EDT — scribe-sqlite-data `a6ed0a8b8f9cdd7f2451bfddd3f091de88769153`
Document fb7a7c6 in the change log (#228).

## 2026-08-20 14:31:40 EDT — scribe-sqlite-data `fb7a7c66a71c5155fea1282d7e2c9e7043b39ff5`
Record Scribe 0.1 (55) iPhone install for system transcript PiP (#228).

## 2026-08-20 14:30:49 EDT — scribe-sqlite-data `f347fc76e7ee8d4f0a8bee8d22f3e8bafda979d5`
Installed Scribe 0.1 (55) localDev on Michael’s iPhone for system transcript PiP (#228).

## 2026-08-20 14:23:30 EDT — scribe-sqlite-data `f347fc76e7ee8d4f0a8bee8d22f3e8bafda979d5`
Document 1c7e756 in the change log (#228).

## 2026-08-20 14:23:20 EDT — scribe-sqlite-data `1c7e756c3a0d910b603d8ea46ead3bacad73aeec`
Compile the iOS transcript PiP host without a MainActor NSObject subclass (#228).

## 2026-08-20 14:08:20 EDT — scribe-sqlite-data `ecd4133f48a85d5ca9dad75a8ff22e946457d19a`
Document c3007a8 in the change log (#228).

## 2026-08-20 14:08:10 EDT — scribe-sqlite-data `c3007a87637f43a9ae4e83d04f2a4d0744cc9163`
Arm system transcript Picture-in-Picture before the user leaves the app (#228).

## 2026-08-20 13:37:10 EDT — scribe-sqlite-data `c62361614bd34848ebe8754cbd7b371148c1dfaf`
Document 8b67c2c in the change log (#228 #229).

## 2026-08-20 13:37:00 EDT — scribe-sqlite-data `8b67c2c24955d9afc9091104937107c362d81548`
Record Scribe 0.1 (54) iPhone install for #228 #229.

## 2026-08-20 13:28:20 EDT — scribe-sqlite-data `84fe65dc1be1b5c35533fec7281fb14163b17f45`
Document 8bb810d in the change log (#228 #229).

## 2026-08-20 13:28:10 EDT — scribe-sqlite-data `8bb810df8e885d0ba05dbb079471917cdff8ffdf`
Bump CURRENT_PROJECT_VERSION 53 -> 54 for the combined #228 #229 localDev install.

## 2026-08-20 13:23:40 EDT — scribe-sqlite-data `ad81b721` ledger for `65e09102bfcf1871f105543e3937096bae786322`
Keep the Mac CloudKit observer lean and show a list robot (#216).

## 2026-08-20 13:23:20 EDT — scribe-sqlite-data `65e09102bfcf1871f105543e3937096bae786322`
Keep the Mac CloudKit observer lean and show a list robot (#216).

## 2026-08-20 13:20:20 EDT — scribe-sqlite-data `f87c2fc86f408312a1ef6b4eeed6081389d94770`
Record the 0.1 (53) install note in the change log (#147).

## 2026-08-20 13:20:10 EDT — scribe-sqlite-data `199dc9bbbc50e94cd02aa61131d464b20bbc6f06`
Record Scribe 0.1 (53) iPhone install for AirPods HFP reconnect (#147).

## 2026-08-20 13:05:57 EDT — scribe-sqlite-data `ba2fbabbb75b89318684a80df7945255a4c01a81`
Record a4c6bb1 in the change log (#147).

## 2026-08-20 13:05:50 EDT — scribe-sqlite-data `a4c6bb1aae702317df81365ab29c949f915c582c`
Skip preferred sample rate on watchOS during HFP recovery (#147).

## 2026-08-20 13:03:52 EDT — scribe-sqlite-data `ef3e2f06db832b441fac42fccf4c96f8cf4e8ed7`
Document c47bf9a in the change log (#229).

## 2026-08-20 13:03:42 EDT — scribe-sqlite-data `c47bf9a0f692d6c6b93d48bb4cc9b674286388e1`
Convert ReplayKit PCM by layout so Photos and WAV audio is not static (#229).

## 2026-08-20 12:57:27 EDT — scribe-sqlite-data `13bd805342c0be196fcaf64af5c9b51cbac5f44b`
Add a settings-driven transcript Picture-in-Picture window (#228).

## 2026-08-20 12:47:30 EDT — scribe-sqlite-data `593f1ee6a229f2840c67b5be826d9bd3e9a6e8dc`
Record 1efe7b9 in the change log (#147).

## 2026-08-20 12:47:13 EDT — scribe-sqlite-data `1efe7b9221f4651c5b1a97fde0f00dd78c6f764c`
Keep recording through AirPods HFP connect instead of a 5-attempt dead-end (#147).

## 2026-08-20 12:37:40 EDT — scribe-sqlite-data `e40a6663379f976ca0a0b58b15c5ae19769bf61f`
Add a separate CloudKit observer app for Mac Grok sessions (#216).

## 2026-08-20 12:16:10 EDT — scribe-sqlite-data `f4b6bccb31d160024c59a3b8e133b90b1a64ddc5`
Record Scribe 0.1 (52) iPhone install for Photos movie audio (#224).

## 2026-08-20 12:05:40 EDT — scribe-sqlite-data `eea5f4fc5d8bb0fddab663ea4c3bb65f519ddb47`
Log d3eadf6 in the change log (#224).

## 2026-08-20 12:05:20 EDT — scribe-sqlite-data `d3eadf63af9fa3aed670703f30f703b88b667fd8`
Mix system and microphone audio onto one Photos movie track (#224).

## 2026-08-20 11:33:20 EDT — scribe-sqlite-data `be2e5108d0e1b267d73ccb6fda7c8e27fed79267`
Log bbb1ec5 in the change log (#227).

## 2026-08-20 11:33:05 EDT — scribe-sqlite-data `bbb1ec53969fd6bb8f5d14798b646e15d691e062`
Keep the recording overflow menu from rebuilding on every waveform tick (#227).

## 2026-08-20 11:08:22 EDT — scribe-sqlite-data `397bd88e7102cc3708a48884cda8b81358cf1879`
Log e147ecc in the change log (#226).

## 2026-08-20 11:07:48 EDT — scribe-sqlite-data `e147ecc825a6dc17b5917eabfb80b0e1bbc856a6`
Keep the collapsed build debug overlay fully on-screen (#226).

## 2026-08-20 10:24:10 EDT — scribe-sqlite-data `72df11926bd7f31025e07aaf5cb41e92f29f7e8e`
Log 3e5ade8 in the change log (#224 #225 #114).

## 2026-08-20 10:23:38 EDT — scribe-sqlite-data `3e5ade8ca1144fdd51447aea7dce6d0fa2878efc`
Persist opt-in ReplayKit movies to Photos and reclaim the recording bottom bar (#224 #225 #114).

## 2026-08-19 14:59:39 EDT — scribe-sqlite-data `c316fa113db9584aff774102929a84e9140d03fe`
Log 53e1363 in the change log (#218).

## 2026-08-19 14:59:39 EDT — scribe-sqlite-data `53e136325cea4f1d201c08aada715d40874acfee`
Bump Scribe SQLiteData Dev to 0.1 (49) for the #218 file-backed CKAsset install.

## 2026-08-19 14:59:39 EDT — scribe-sqlite-data `9a0c2b8c66443c73ce559d2943a81317d770aba6`
Log 9f4fddd in the change log (#218).

## 2026-08-19 14:59:39 EDT — scribe-sqlite-data `9f4fddde4f18c41b9a2a892cf07f979ff61b540c`
Send evacuated audio as a file-backed CKAsset so dest receives real bytes (#218).

## 2026-08-19 14:59:39 EDT — tca/sqlite-data `b87466a4baf1db900add8d9064f5aed56c7e9f17`
Build outgoing CKAssets from evacuated files so empty SQL blobs do not upload (#218). Local fork only.

## 2026-08-19 14:44:42 EDT — scribe-sqlite-data `cc07a71099c035ac14e22ccc443083ebad691136`
Bump Scribe SQLiteData Dev to 0.1 (48) for the #147 engine-reset install.

## 2026-08-19 14:44:42 EDT — scribe-sqlite-data `34a936958d8a6567d07eebf116a798184d08a39c`
Reset the audio engine before the recovery reinstall so a route change cannot leave the graph at the stale format (kAudioUnitErr -10868, physical AirPods evidence) (#147).

## 2026-08-19 14:44:42 EDT — scribe-sqlite-data `1cbad3151246676b444c664ea8f856f082e6a750`
Install the mic tap with a nil format; AdaptiveTapConverter adapts conversion per live buffer format (physical AirPods format-mismatch evidence) (#147).

## 2026-08-19 14:44:42 EDT — scribe-sqlite-data `5e234707ca049d42a09e96aad15907f7aa9065c2`
Add updateVideoSampleInterval to the non-iOS capture client fallback so the watch slice builds for device installs (#219).

## 2026-08-19 14:43:13 EDT — scribe-sqlite-data `6a1edf7edec0959b228802ecaff5eab7275014dd`
Record #218 C1 072 numbers: upload-at-stop works, dest apply still over 100.

## 2026-08-19 13:40:00 EDT — scribe-sqlite-data `2255d46644b1`
Bump Scribe SQLiteData Dev to 0.1 (45) for the #218 C1 leftover install.

## 2026-08-19 13:39:38 EDT — scribe-sqlite-data `5304b4e`
Keep dest WAV recovery tests off live recording IDs so they cannot delete product files (#218).

## 2026-08-19 13:38:30 EDT — scribe-sqlite-data `5304b4eb3557`
Keep dest WAV recovery tests off live recording IDs so they cannot delete product files (#218).

## 2026-08-19 13:30:30 EDT — scribe-sqlite-data `c69125a0de13c2135d217837a0f962f5b9e36d6b`
Mix system audio into the recording WAV (dedicated capture lane + capture-clock-aligned saturating writer mix), force Apple Speech mid-stream finalization past a 30 s open-section cap so continuous audio rolls segments, and enforce the periodic-frame preference at host admission plus the configured Mac frame interval (#142 #222 #223).

## 2026-08-19 13:07:41 EDT — scribe-sqlite-data `7ce73b37f103ffe125f6ee47cda9412bf6c27a86`
Recover dest WAVs from CloudKit when the blob is empty. Hydrate refetches a staged CKAsset onto Documents/Scribe/recordings/<UUID>/audio.wav (#218).

## 2026-08-19 13:07:41 EDT — sqlite-data `ccf420a5e9efeb76315bf939f658ba2843cf12be`
CloudKitAssetLanding hook at SyncEngine apply (~2055 and ~2486). Never Data(contentsOf:) a full CKAsset into a SQL BLOB (#218).

## 2026-08-19 13:07:41 EDT — scribe-sqlite-data `1f90b14be50de4ffb06303e0322b7072b2b0cc35`
Bump Scribe SQLiteData Dev to 0.1 (43) for the #218 C1 install.

## 2026-08-19 11:55:42 EDT — scribe-sqlite-data `742f853770f0bdf41f97c5f67ed3a09a9add0e53`
Stream dest CKAsset apply onto disk and restore process.memory.sample on the SQLite lane (#218).

## 2026-08-19 11:35:00 EDT — scribe-sqlite-data f17f4f7292d3f7a92e9d2e9017edc28763e204f4

- 2026-08-19 14:15:54 EDT — scribe-sqlite-data — ffed6a670f21df10209e1f6854cbeca79f95b2af — Log every path that pops the open playback surface (#221): compact navigation pop, presentation dismiss, detail-mode transitions.
- 2026-08-19 14:15:54 EDT — scribe-sqlite-data — 89a1a2d9e875b59376b6fe637befb652cbe5a765 — Bump Scribe SQLiteData Dev to 0.1 (46) for the #221 instrumentation install.
- **Repo:** scribe-sqlite-data
- **SHA:** f17f4f7292d3f7a92e9d2e9017edc28763e204f4
- **Reason:** Empty snapshotJSON on persist, 1s stamp-skipped list observe, 5s CloudKit fetch, chunked hydrate, CloudKit reader/writer harness. Scribe 0.1 (40). #218.

## 2026-08-19 10:10:20 EDT — scribe-sqlite-data d7242ef750eaf13546d307c5ed252f7065b2f449

- **Repo:** scribe-sqlite-data
- **SHA:** d7242ef750eaf13546d307c5ed252f7065b2f449
- **Reason:** Upload the finalized WAV once at stop. Mid-take persist no longer publishes a growing CKAsset. Local ProgressiveWAVWriter growth stays. Scribe 0.1 (39). #217.

## 2026-08-17 20:48:40 EDT — scribe-sqlite-data 9e767382c3019cfe3a6dc83abefd5e6f8f0f3369

- **Repo:** scribe-sqlite-data
- **SHA:** 9e767382c3019cfe3a6dc83abefd5e6f8f0f3369
- **Reason:** Persist timeline images as SQLiteData ScribeAttachment rows and isolate Instant-drift tests so #214 function-lane proof (attachments, media, progressive audio, words-JSON save) can compile and pass. Scribe 0.1 (21).

## 2026-08-17 18:03:06 EDT — scribe-sqlite-data 70a4f3a5ca2933bc993a95df9e53f3de6ba5040e

- **Repo:** scribe-sqlite-data
- **SHA:** 70a4f3a5ca2933bc993a95df9e53f3de6ba5040e
- **Reason:** Port Instant #197 standard SwiftUI iPhone chrome onto the SQLiteData fallback so product UI matches Instant main without copying Instant façades (#214 #197 #194).

## 2026-08-16 05:56:24 EDT — realtime-voice-sqlite-instant 5fe583919f70de88daf97416d775ac9c5221e7fe

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** 5fe583919f70de88daf97416d775ac9c5221e7fe
- **Reason:** Restore canonical parent-forward recording-list children, production-compatible relation metadata, and current correctness fixtures so receiving devices retain bounded transcription, segment, and attachment projection across fresh and upgraded stores (#073).

## 2026-08-16 05:55:41 EDT — realtime-voice-sqlite-instant 2a79d84141edcb31ed2c77393094d04d03f3a59c

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** 2a79d84141edcb31ed2c77393094d04d03f3a59c
- **Reason:** Bound synthetic transcript section and word timestamps by PCM16 delivered during the exact speech-session activation, preserving pending-final identity without allowing stop or same-ID reuse to extend or inherit the audio timeline (#044 #073).

## 2026-08-16 05:54:23 EDT — instant-data-swift 73ff55491fbd18efeaa19375c0b725d40096ce5f

- **Repo:** instant-data-swift
- **SHA:** 73ff55491fbd18efeaa19375c0b725d40096ce5f
- **Reason:** Reconcile logical forward/reverse declarations with one exact durable server relation, transactionally transpose affected resident and SQLite cold/live rows, and preserve outbox intent so upgraded Scribe list projections cannot lose their recording children (#073).

## 2026-08-16 02:53:37 EDT — realtime-voice-sqlite-instant 177fc7972dfc4f883a86020b292a0e52dd36e7d1

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** 177fc7972dfc4f883a86020b292a0e52dd36e7d1
- **Reason:** Derive the memory-soak transcript's section and word offsets from each stream's injected wall clock, preserving interim/final identities and duration-drain behavior so an eight-minute recording cannot display or persist transcript timestamps around 22 minutes (#044).

## 2026-08-16 02:00:09 EDT — instant-data-swift 46024e30df6e7cf3b7df81c38c296349627ab2ce

- **Repo:** instant-data-swift
- **SHA:** 46024e30df6e7cf3b7df81c38c296349627ab2ce
- **Reason:** Move long authoritative refresh planning outside the local-write gate, then catch up only proven append-only rows with bounded peer-runtime fallback so recording writes remain durable and observable without weakening claim, receipt, closure, or acceptance authority (#008 #073 #107).

## 2026-08-16 02:00:09 EDT — realtime-voice-sqlite-instant 9040be5b8bbb2854a8e4ddc1d6e0de8d7b6493cb

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** 9040be5b8bbb2854a8e4ddc1d6e0de8d7b6493cb
- **Reason:** Give speech and system audio independent segment identity, persist final child words before rejectable derived summaries, and strictly order those durable groups so Recording 052's index holes and stale-summary atomic data loss cannot recur (#008 #073 #107).

## 2026-08-15 17:18:34 EDT — instant-data-swift a0805fc44a2c32642279d14b5d4040c7dd7a7fa6

- **Repo:** instant-data-swift
- **SHA:** a0805fc44a2c32642279d14b5d4040c7dd7a7fa6
- **Reason:** Wait for the exact outbound mutation before mock server acceptance so the full serialized gate exercises SQLite's claim-token boundary without injecting a protocol-impossible premature acknowledgement (#155).

## 2026-08-15 16:33:17 EDT — instant-data-swift 3649a63e1d41470f8b213fdd69d0dc4488928908

- **Repo:** instant-data-swift
- **SHA:** 3649a63e1d41470f8b213fdd69d0dc4488928908
- **Reason:** Replace full persisted live-query ownership rewrites with exact identity deltas and reused prepared statements so the measured 772-row Scribe recordings refresh no longer blocks the serial receive path behind 772 deletes plus 772 inserts (#044 #155).

## 2026-08-15 15:43:20 EDT — realtime-voice-sqlite-instant e312be58deed0fb68db1ab6d81c1fc0aa95db782

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** e312be58deed0fb68db1ab6d81c1fc0aa95db782
- **Reason:** Replace full-library PhotoKit enumeration with incremental inserted-asset tracking, cleanup-on-deinit temporary-file leases, and recording-identity validation for every asynchronous image completion so Photo Library attachments remain enabled without the measured recording-start footprint spike (#044).

## 2026-08-15 14:22:57 EDT — realtime-voice-sqlite-instant 3da90f701595c6584547823b499f8d2aa9c0711f

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** 3da90f701595c6584547823b499f8d2aa9c0711f
- **Reason:** Resolve the official Swift Crypto and Swift ASN.1 packages introduced by linked Instant receipt authority so clean-provenance Scribe Mac and physical-iPad localDev builds can proceed without moving existing dependencies or changing app source (#044 #095 #155).

## 2026-08-15 14:17:01 EDT — instant-data-swift ae000fce901fff693971d1ebcbdca8bdd10a6ef4

- **Repo:** instant-data-swift
- **SHA:** ae000fce901fff693971d1ebcbdca8bdd10a6ef4
- **Reason:** Bind optimistic-effect, exact claim, and server-acceptance authority to SQLite-owned receipts; run bounded full-durable application migrations before services; and close the reconnect, cancellation, local-transport, and observer invalidation races uncovered by the physical Scribe program (#044 #095 #155).

## 2026-08-15 00:43:07 EDT — instant-data-swift 141d1e9ec68531c4e92370521f7bb4256eeb2765

- **Repo:** instant-data-swift
- **SHA:** 141d1e9ec68531c4e92370521f7bb4256eeb2765
- **Reason:** Suppress semantically unchanged authoritative refresh invalidation, reconcile schema transitions on the peeled server base, and give current-session failures one receiver-owned reconnect path without same-generation wire replay (#044 #095 #155).

## 2026-08-14 21:34:53 EDT — instant-data-swift 30b180423666ac038210636d4377d60da2734006

- **Repo:** instant-data-swift
- **SHA:** 30b180423666ac038210636d4377d60da2734006
- **Reason:** Bound nested live-query children before authoritative hot-store apply and isolate oversized terminal rejection to the exact claimed target without reconnecting (#044 #095 #155).

## 2026-08-14 20:21:05 EDT — realtime-voice-sqlite-instant d0350deaf8a66669c4338e495a0b091fe461b1f9

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** d0350deaf8a66669c4338e495a0b091fe461b1f9
- **Reason:** Resolve the agent-control endpoint from explicit diagnostics configuration before asynchronous bootstrap, preserving process-lifetime connection deduplication and fail-closed opt-out semantics (#095 #155).

## 2026-08-14 19:47:22 EDT — realtime-voice-sqlite-instant c47b8b3957f99774c20f2208e43aa0ce84317715

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** c47b8b3957f99774c20f2208e43aa0ce84317715
- **Reason:** Replace the measured capped diagnostics journal's per-event whole-file rewrite with one-file streamed low-water compaction, bounded recovery, canonical raw parity, and physical acknowledgement purge (#044 #155).

## 2026-08-14 18:06:00 EDT — realtime-voice-sqlite-instant a38761dd128138c006560514a1687b257f3bd267

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** a38761dd128138c006560514a1687b257f3bd267
- **Reason:** Require an explicit bounded state projection for discrete signal diagnostics, eliminating full-root copy and CustomDump diff churn while preserving base effects and agent-control visibility (#044 #095 #155).

## 2026-08-14 17:58:00 EDT — instant-data-swift bdc7d10276132ce9cbddb010d53bde4a7b984c3e

- **Repo:** instant-data-swift
- **SHA:** bdc7d10276132ce9cbddb010d53bde4a7b984c3e
- **Reason:** Replace the live generation before retrying an acknowledgement-unknown durable event, using Reactor-shaped ordinal deadlines so delayed acknowledgements cannot cause same-socket replay and later permission rejection (#044 #095 #155).

## 2026-08-14 17:25:12 EDT — realtime-voice-sqlite-instant 0da0651942e329064bdc2a8a7c63bd1f60e14dc1

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** 0da0651942e329064bdc2a8a7c63bd1f60e14dc1
- **Reason:** Keep one process-wide physical-footprint baseline while rearming the one-second safety stop for every sequential recording, with exact-identity main-actor revalidation and bounded one-UUID state (#044 #095 #155).

## 2026-08-14 16:27:12 EDT — realtime-voice-sqlite-instant bbebe7fd417994598cd6064a7359082b4274713a

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** bbebe7fd417994598cd6064a7359082b4274713a
- **Reason:** Project compact recording-list segment scalars at the server boundary while omitting detail-only wordsJSON, preserving realtime order, child limits, and the single cursor query (#044 #155).

## 2026-08-14 16:25:25 EDT — instant-data-swift 5d00f27644b02397691ab46f3802193e1acedf06

- **Repo:** instant-data-swift
- **SHA:** 5d00f27644b02397691ab46f3802193e1acedf06
- **Reason:** Hydrate selected deferred values through retained nested query pages, keep unselected transcript word blobs in SQLite, and rematerialize projected ordered observations when a splice cannot prove stable order (#044 #155).

## 2026-08-14 14:37:09 EDT — realtime-voice-sqlite-instant 2c808963e3d5627ae4873f6b57227d21325155d2

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** 2c808963e3d5627ae4873f6b57227d21325155d2
- **Reason:** Classify measured companion-listener heartbeats before root-state diagnostics while preserving their base effect, and match upstream scalar-before-link segment transaction ordering (#044 #095 #155).

## 2026-08-14 14:37:08 EDT — instant-data-swift 6cad77c8c95452ac5632bde833252a6367672429

- **Repo:** instant-data-swift
- **SHA:** 6cad77c8c95452ac5632bde833252a6367672429
- **Reason:** Preserve required scalar foundation through stale-write projection and atomically bound post-hydration outbox claims to the existing 8 MiB envelope (#044 #095 #155).

## 2026-08-14 12:40:03 EDT — realtime-voice-sqlite-instant f3fcf958b1688a31b505997243ae6d8064f79544

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** f3fcf958b1688a31b505997243ae6d8064f79544
- **Reason:** Give lifecycle-scoped recording attachments stable UUID identities and canonical blob binding, preserve legacy retry keys, and contain the production recording-list child overfetch with the measured 12-root page (#044 #095 #155).

## 2026-08-14 12:40:02 EDT — realtime-voice-sqlite-instant de00bea0288cfbf276ae3c74129c7933842999bd

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** de00bea0288cfbf276ae3c74129c7933842999bd
- **Reason:** Join local stop and exact speech/system session release across repeated recordings, fence canned-speech activations, and construct the agent-control catalog only once per process dependency lifetime (#044 #095 #155).

## 2026-08-14 10:07:28 EDT — realtime-voice-sqlite-instant c8d0176a92ef3ee557d5f7c54bb63fedd0669801

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** c8d0176a92ef3ee557d5f7c54bb63fedd0669801
- **Reason:** Make the dependency-controlled physical soak preflight honor disabled memory gates and construct canned speech clients with deterministic Point-Free UUID dependencies before the Mac/iPad acceptance sequence (#044 #095 #155).

## 2026-08-14 09:34:08 EDT — realtime-voice-sqlite-instant 3c0b969c3412d55a9d523b380a5ac0c1c44ef164

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** 3c0b969c3412d55a9d523b380a5ac0c1c44ef164
- **Reason:** Preserve the verified iPhone transcription, stop, local playback, server projection, and remaining Mac visibility/audio blockers for #095 before continuing cross-device acceptance.

## 2026-08-13 18:03:31 EDT — realtime-voice-sqlite-instant 73ff8487ce53d7ecc49d8ef3ecbb9ed839b4a925

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** 73ff8487ce53d7ecc49d8ef3ecbb9ed839b4a925
- **Reason:** Debug Instant static-account sign-in so iPhone and Mac share one durable user for cross-device playback (#095).


- **Repo:** realtime-voice-sqlite-instant
- **SHA:** 81165583871549032878bcc937954139fdceddde
- **Reason:** Restore the iPhone build debug overlay so Expanded actually paints and Stop taps through (#197).

## 2026-08-13 16:33:33 EDT — realtime-voice-sqlite-instant 81165583871549032878bcc937954139fdceddde

## 2026-08-13 15:39:34 EDT — realtime-voice-sqlite-instant f3ecc1c05313855d16cb5e35ba7dda55a3afc68a

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** f3ecc1c05313855d16cb5e35ba7dda55a3afc68a
- **Reason:** Restore iPhone recording list and recording chrome to standard SwiftUI (#197).

## 2026-08-12 18:21:19 EDT — instant-data-swift 94f9ff30fb8c5192ab3f887c9e7ed4fb5a182295

- **Repo:** instant-data-swift
- **SHA:** 94f9ff30fb8c5192ab3f887c9e7ed4fb5a182295
- **Reason:** Follow recordingID strings and parent many-refs in nested live-query limits (#044 #155). Trial 5 follow-up.

## 2026-08-12 18:03:10 EDT — instant-data-swift 48456facf86aa871d7e129c6ee5646e48558a078

- **Repo:** instant-data-swift
- **SHA:** 48456facf86aa871d7e129c6ee5646e48558a078
- **Reason:** Apply nested include limits to persisted live query triples (#044 #155). Autoresearch `2026-08-12-live-put-observation-memory` trial 5.

## 2026-08-12 17:27:58 EDT — instant-data-swift 6c6760b40d9c457d5c2d60f5bfa60c7c27558587

- **Repo:** instant-data-swift
- **SHA:** 6c6760b40d9c457d5c2d60f5bfa60c7c27558587
- **Reason:** Unload inactive live querySubs during session prune (#044 #155). Autoresearch `2026-08-12-live-put-observation-memory` trial 4.

## 2026-08-12 16:16:40 EDT — instant-data-swift fe9ebe07862241a572d11f3cb74ace8a5d82d79c

- **Repo:** instant-data-swift
- **SHA:** fe9ebe07862241a572d11f3cb74ace8a5d82d79c
- **Reason:** Load InstantStore bootstrap from live query entities, not the full SQLite graph (#044 #155). Autoresearch `2026-08-12-live-put-observation-memory` trial 3.



- **Repo:** instant-data-swift
- **SHA:** 437ee8fbfbbc1dbdab6f5575252cac5a87c234d2
- **Reason:** Prove deferred string transcript payloads stay out of TripleIndexes (#044 #155). Autoresearch `2026-08-12-live-put-observation-memory` trial 2.

## 2026-08-12 13:09:13 EDT — scribe-sqlite-data 065b712de41a400aba5b9822ad2890da5ebed9fb


- **Repo:** scribe-sqlite-data
- **SHA:** 065b712de41a400aba5b9822ad2890da5ebed9fb
- **Reason:** Configure agent control before the root store exists; Mac loopback collector fallback when Tailscale DNS is off (#194).

## 2026-08-12 13:07:02 EDT — instant-data-swift 6536a8345d350117414a542da3c1f1f790a6f586

- **Repo:** instant-data-swift
- **SHA:** 6536a8345d350117414a542da3c1f1f790a6f586
- **Reason:** Skip and splice InstantStore observers on same-entity live puts (#044 #155). Autoresearch `2026-08-12-live-put-observation-memory`.

## 2026-08-12 12:55:49 EDT — scribe-sqlite-data cce623c51a49e114d5f4f23155ed7a1e4e0fee1f

- **Repo:** scribe-sqlite-data
- **SHA:** cce623c51a49e114d5f4f23155ed7a1e4e0fee1f
- **Reason:** Live Mac CloudKit SyncEngine plus progressive SQLiteData audio CKAssets (#194).

## 2026-08-12 12:22:00 EDT — scribe-sqlite-data 88ede6b2ac8578a91a801c05ba768b4f4d4ce0e7

- **Repo:** scribe-sqlite-data
- **SHA:** 88ede6b2ac8578a91a801c05ba768b4f4d4ce0e7
- **Reason:** Accept Mac scribe-shared deep links on the SQLiteData fork (#194).

## 2026-08-12 12:12:00 EDT — scribe-sqlite-data 8522651619d55e1757cfccc1c9e4c6c2224d3d08

- **Repo:** scribe-sqlite-data
- **SHA:** 8522651619d55e1757cfccc1c9e4c6c2224d3d08
- **Reason:** Fix SQLiteData interim segment primary-key collision (#194); live speech no longer double-inserts the open segment.

## 2026-08-12 10:24:42 EDT — realtime-voice-sqlite-instant 8c380cd79e0760407b134c76d977cbab178d345d

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** 8c380cd79e0760407b134c76d977cbab178d345d
- **Reason:** Bind Onboarding @Doc surface to #041 for fail-closed consolidator (no --allow-unbound).
## 2026-08-11 17:33:15 EDT — instant-data-swift c58253d5162fdd998bcb136ee1effcd7e302a8c5

- **Repo:** instant-data-swift
- **SHA:** c58253d5162fdd998bcb136ee1effcd7e302a8c5
- **Reason:** Transcription example scaffold (#193): Instant entities + floating toolbar; Mac + iPhone sim.

## 2026-08-11 17:04:29 EDT — instant-data-swift cbb679ec6480f13005537d489cbdd287a28eb4ba

- **Repo:** instant-data-swift
- **SHA:** cbb679ec6480f13005537d489cbdd287a28eb4ba
- **Reason:** ADR 0016 decisions locked; plan.md + Instant #193 Transcription example.

## 2026-08-11 16:57:42 EDT — instant-data-swift 77307d48387372508a9be0776bffaca749ae0844

- **Repo:** instant-data-swift
- **SHA:** 77307d48387372508a9be0776bffaca749ae0844
- **Reason:** ADR 0016 Q25: goBack is program navigation stack (Swift Navigation style).

## 2026-08-11 16:53:44 EDT — instant-data-swift c44911e27a0358940b7ae4068b43ef3a21dd713f

- **Repo:** instant-data-swift
- **SHA:** c44911e27a0358940b7ae4068b43ef3a21dd713f
- **Reason:** ADR 0016 all nine mode leaves accepted; goesTo handle args normalized (Q23–Q24 blanket).

## 2026-08-11 16:47:56 EDT — instant-data-swift f647abee9dc89a9dc3ae706ae7b9747719957b6a

- **Repo:** instant-data-swift
- **SHA:** f647abee9dc89a9dc3ae706ae7b9747719957b6a
- **Reason:** ADR 0016 flat mode leaves through Q22 (`recording.create`); restore after external overwrite; HANDOFF for cold resume.

## 2026-08-11 16:41:49 EDT — realtime-voice-sqlite-instant 10d82164c9f8d95d8785addd3960f4916ec0a927

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** 10d82164c9f8d95d8785addd3960f4916ec0a927
- **Reason:** Message–issue consolidator opt-in Instant product edge write (#041): append-log issue.message-path + issue.derivedMessageEdges; Onboarding 6 edges live.
## 2026-08-11 16:28:39 EDT

- **repo:** realtime-voice-sqlite-instant
- **sha:** `061d737863b8dd62afc10ac10b720b0b964f242a`
- **subject:** Default debug overlay to expanded with v2 settings file.
- **reason:** Captain-requested default expanded debug overlay; v2 file so prior hidden defaults do not trap reinstalls. Companion to KEEP handoff pickup (schema push + stop force-finish WT).

## 2026-08-11 16:27:31 EDT

- **repo:** realtime-voice-sqlite-instant
- **commit:** `0c1791b8317f5212f6b70c6ed91fc6dba5110a93`
- **reason:** Message–issue consolidator ideal mode: product vs noise, multi-line @Doc, ideal Instant touches edges; Onboarding sample in docs (#041).

## 2026-08-11 16:14:48 EDT

- **repo:** realtime-voice-sqlite-instant
- **commit:** `98fe3302b7afa51db76f6468f4aa9baa470b5d29`
- **reason:** Adopt `@DocumentedActions` + STE `@Doc` on `Onboarding.Action` (first real product Action enum docs surface).

## 2026-08-11 16:12:00 EDT

- **repo:** realtime-voice-sqlite-instant
- **sha:** `e9dc08ab0f4761764073f962798fbb75b6a6efc0`
- **reason:** Add message–issue consolidator CLI (git + Action/message derive; Instant write stub). #041

## 2026-08-11 15:36:15 EDT

- **repo:** realtime-voice-sqlite-instant
- **commit:** dbe162caec5a0bfda431d7f5c89568755eb5a61c
- **reason:** Scaffold @Doc(what:why:) + @DocumentedActions macros for TCA Action documentation lookup (ADR 0007); docs-only derivation next to @RemoteControl.

## 2026-08-11 15:57:27 EDT

- **repo:** instant-data-swift
- **commit:** `7c4e5ab6ee3af10f5861af188ea4d87a4636541d`
- **reason:** Make InstantError actionable (no opaque error 1) and fix deferred-residency bootstrap rejection of indexed JSON payloads.

## 2026-08-10 11:39:19 EDT

## 2026-08-11 14:44:46 EDT

- **repo:** instant-data-swift
- **commit:** `afe09bdba1fe0e0f6ce6f91cdc22ba6fc61c69b9`
- **reason:** Split InstantRuntime translation unit (ExactTaskOwner / LiveSession / VisibleWrite) and drop debug SIL ClosureLifetimeFixup disable flag; focused freeze contracts green; physical KEEP still blocked on dirty Scribe.

## 2026-08-11 13:56:00 EDT

- **Repo:** instant-data-swift
- **Commit:** `8b7c384e45455cdbf4c5906a786b486354369eaa`
- **Subject:** Land bounded outbox/memory freezes and unblock suite compile
- **Reason:** Performance wrap-up after ChatGPT credit exhaustion; bounded outbox/memory freezes + suite compile unblocks (#044 #150 #155)


- **repo:** instant-data-swift
- **commit:** `43c1dcdb6881f7e5726d6434a43bd7f499575afe`
- **reason:** Fence WebSocket mutation errors to the exact durable SQLite delivery claim, make duplicate and reclaimed responses body-free no-ops, atomically release terminal and retryable claims, and preserve the healthy socket/query registrations while publishing local rollback (#044, #155, #190).

## 2026-08-10 10:40:27 EDT

- **repo:** instant-data-swift
- **commit:** `9a802149c790f6d0b24668624d8c01c39d1e84c5`
- **reason:** Bound high-churn same-entity outbox mutation bodies by atomically replacing only the exact never-offered scalar-assignment tail, while preserving causal barriers, direct rollback, immutable transaction-ID lifecycle observation, and loud bounded corruption handling (#044, #155, #190).

## 2026-08-10 03:35:45 EDT

- **repo:** instant-data-swift
- **commit:** `96db9b3e52de20ef70e170f6d75b267b9bf558d1`
- **reason:** Make SQLite the bounded automatic-outbox authority with durable 50-mutation, 256-step, and 8 MiB claims; row-address acknowledgements and explicit disposition; five-second self-waking retry; body-free startup and public waits; cross-runtime ordering; and raw-preserving loud quarantine, verified against 10,000-row queues (#044, #155, #168).

## 2026-08-09 23:27:35 EDT

- **repo:** instant-data-swift
- **commit:** `beffc9b4c98c24eda1f0bea24b8a60b35c29d3d7`
- **reason:** Replace whole-outbox reconstruction on every WebSocket acknowledgement with one revision-checked SQLite row transition and prove cold-cache one-row decoding against 10,000 durable mutations plus an unrelated malformed row (#044, #155, #168).

## 2026-08-09 22:19:47 EDT

- **repo:** realtime-voice-sqlite-instant (Scribe)
- **commit:** `406131713869fcc986bb01950f01f258e480d55d`
- **reason:** Correct the failed-row terminology and record the verified physical-iPad cleanup of 1,039 retained terminal-rejection receipts while preserving pending mutations, triples, media, revision invariants, and a recoverable pre-cleanup backup (#044).

## 2026-08-09 20:23:20 EDT

- **repo:** realtime-voice-sqlite-instant (Scribe)
- **commit:** `0ed93aeb22d435560091b7d42ae51df06dfb2d07`
- **reason:** Correct the build 10 production snapshot after a post-stop admin query showed eventual but still severely delayed materialization, preserving the failed five-second live-sync verdict without claiming a permanent freeze (#187).

## 2026-08-09 20:20:36 EDT

- **repo:** realtime-voice-sqlite-instant (Scribe)
- **commit:** `3c475f93e5cde8dd6acfed882940751d06e3c66f`
- **reason:** Record the corrected-Instant build 10 physical-iPad memory and live-sync failure with exact host footprint, outbox/acknowledgement churn, partial relation-fix success, limitations, and next repair (#044, #187).

## 2026-08-09 19:56:10 EDT

- **repo:** realtime-voice-sqlite-instant (Scribe)
- **commit:** `304fc5a17777e0d73e67d70d05242c878da6706f`
- **reason:** Assign Scribe 0.1 (10) a unique clean build identity for physical-iPad acceptance of the corrected Instant reverse-relation and durable-rebase implementation (#044, #187).

## 2026-08-09 18:00:47 EDT

- **repo:** instant-data-swift
- **commit:** `71ddd401de9a329233e4175549ee5281e31353de`
- **reason:** Match canonical TypeScript reverse-relation endpoint orientation, remove invalid modes from swapped links, keep durable and optimistic rebase timestamps aligned so required scalar writes survive refresh/rejection/retry, and preserve exact same-ID idempotency while rejecting changed intent (#187).

## 2026-08-09 16:39:00 EDT

- **repo:** realtime-voice-sqlite-instant (Scribe)
- **commit:** `4773fa0c298517a215fc1d6c12cc4713d7e5cb22`
- **reason:** Replace root whole-state debug dumping with a publishable signal-aware higher-order reducer that classifies analog and periodic actions before state capture, preserves the complete Agent Control action catalog, and retains bounded discrete history only on the Mac collector.

## 2026-08-09 15:12:24 EDT

- **repo:** realtime-voice-sqlite-instant (Scribe)
- **commit:** `d989eeb7bc99bdda91df5c66e5d59416074ebc48`
- **reason:** Assign unique Scribe 0.1 (7) build identity to the physical-iPhone ReplayKit autoresearch binary before install.

## 2026-08-09 15:06:39 EDT

- **repo:** realtime-voice-sqlite-instant (Scribe)
- **commit:** `1c3e58cdec6dcc6221d7dc1b20e8573d98088824`
- **reason:** Add an audio-and-transcription-only stress override that leaves real ReplayKit and Instant live; correlate recording saves to exact Instant transaction IDs and preserve privacy-safe failure provenance.

## 2026-08-09 15:00:13 EDT

- **repo:** instant-data-swift
- **commit:** `8213ed3557d6f23455840699a8948f676858cbf6`
- **reason:** Hydrate exact durable outbox transaction bodies only at delivery and lifecycle boundaries while keeping resident/cache mutation graphs compact; restore exact live delivery, rejection isolation, cross-runtime revision safety, and explicit-close reconnect ordering.

## 2026-08-09 10:00:28 EDT

- **repo:** realtime-voice-sqlite-instant (Scribe)
- **commit:** `f7f581025e13f7b74d60813c0ccde6e4eac0e1fa`
- **reason:** Peel product Instant I/O off ScribeInstantStore; InstantRecordingClient; InstantFacadeBanTests; loud wordsJSON segment decode.

## 2026-08-09 09:54:25 EDT

- **repo:** instant-data-swift
- **commit:** `ca27941efc55c9ddb52e6b9eb99ea926f111f631`
- **reason:** Align InstantCodableJSON with structured-queries shared encoder (sortedKeys, ISO-8601), Optional typealiases; loud InstantError encode/decode for wordsJSON parity.


## 2026-08-09 09:53:10 EDT
- **repository:** instant-data-swift
- **commit:** 5d903c86f595baac8a6581223b07c8426e7639e8
- **reason:** ADR 0015 / #155 same-entity outbox supersession recipe — pure policy + 17 unit tests; TODO at InstantRuntime enqueue; not wired into delivery yet.

## 2026-08-09 09:12:38 EDT
- **repository:** instant-data-swift
- **commit:** 2f32fd84137f4197338aba3c55e7127370ac1952
- **reason:** ADR 0015 / #155 open-segment write recipe — library doc, Core builders + typed InstantEntityModel sketch, unit tests, overview/plan cross-links.

## 2026-08-07 00:46:54 EDT
- **repo:** realtime-voice-sqlite-instant
- **sha:** 45c0022409b580f0b78378a6687a597d2eddd193
- **reason:** #167 agent-addressable ScribePressPadSanity CLI (reduce/self-test/events) + Rec 018 mailbox; Core/Client already on main
## August 07, 2026 at 00:45:33 EDT

- **repository:** instant-data-swift
- **commit:** fdbef6d76506b286717ca0db42359b5be2b8e896
- **reason:** Link multi-agent coordination protocol in AGENTS; land proposed ADR 0014 (entity lifecycle/status on fetch, open-segment writes still outbox).

## August 07, 2026 at 00:45:33 EDT

- **repository:** realtime-voice-sqlite-instant
- **commit:** faccdf133506bbcf50ab22d77be44007a3d5e819
- **reason:** Document agent-control BigInt command-ID hazard; mailbox SSH self-loop and iPad remote-control probes.

## 2026-08-07 00:44:17 EDT

- **repo:** realtime-voice-sqlite-instant
- **sha:** c5e2b5f (Core), 38c754b (Client), b21a6b8 (wire), 2a37393 (plan merge)
- **reason:** #167 pure SPM press-pad core + Dependency client + sanity CLI (no Xcode host)

## 2026-08-07 00:08:32 EDT

- **repo:** realtime-voice-sqlite-instant
- **sha:** `383c73b8e539e082fefb82c9a481118afb91c4c7`
- **reason:** Complete core agent axioms 1–8 (plan/touch/mower-grower + Instant issues + Genesis + no browser spam) at AGENTS.md top; presence operational-only.

## 2026-08-06 23:32:15 EDT — realtime-voice-sqlite-instant be56ed1de0535a37ca13710c4a705425897f542d

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** be56ed1de0535a37ca13710c4a705425897f542d
- **Reason:** #163 minuscule attachment image titles (watched-folder Screen Shot names); docs for #164 feature mini-apps and #165 Mow/Grow.


## 2026-08-06 21:33:10 EDT

- **repo:** realtime-voice-sqlite-instant
- **sha:** 29f39f7025af24c8d44226d70d428c00d995c245
- **reason:** Ship recording activity badges + OpenSegment CLI sanity harness (#155)

## 2026-08-06 19:39:03 EDT

- **repo:** instant-data-swift
- **commit:** 549f740c9a8001ff1ccfd0e9ee15a9a850f304db
- **reason:** Expose Instant clientID() for activity ADT this vs other device (ADR 0015 Q23 / #155 P1)

## 2026-08-06 18:14:49 EDT

- **repo:** instant-data-swift
- **commit:** de1fa08e242f632dac05c4f3414698e4ba58c4e2
- **reason:** InstantFetchRequest(snapshotsOf:) for multi-bag aggregate list values (ADR 0015 / #155)

## August 6, 2026 at 4:52:26 PM EDT — instant-data-swift `421f735343f59cc9903affe38d3c3a7d2dff907c`

**Return from transact after local commit, not wire send**

Optimistic `transact` no longer awaits websocket outbox delivery (counter lag root cause). Delete-all restored to offline-capable fire-and-forget `send`. #151.

## August 6, 2026 at 4:31:26 PM EDT — instant-data-swift `289c148fbddccff3b85fbfe6e7424e4caf3b5d03`

**Harden todos delete-all to await server acceptance**

Todos delete-all awaits Instant server acceptance within 5s and fails loud. Live tests cover single-client accept and two-client peer propagation for #151.

## August 6, 2026 at 4:12:59 PM EDT — instant-data-swift `b97ad44752e37615c5d1b8efdc71626fe06523ee`

**Allow swipe-down keyboard dismiss on todos composer**

Todos composer keeps focus after send, but swipe/scroll down can dismiss the keyboard without server callbacks reclaiming focus. Interactive scrollDismissesKeyboard on the list.

## 2026-08-06 15:49:19 EDT

- **Repository:** instant-data-swift
- **Commit:** `22a973c204926c7133f91b02aff6d23456f79c7b`
- **High-level reason:** Add Scribe open-segment 20s network write/observe benchmark CLI (#156) — Net-A admin→Swift, Net-B Swift→admin, wordsJSON on open segment, observer-validated seq + process memory/CPU.

## 2026-08-05 23:35:07 EDT

## 2026-08-06 13:55:22 EDT

- **Repository:** instant-data-swift
- **Commit:** `c3fadbac66a743d4d1fec598e3c5ef8b91cfbfd5`
- **High-level reason:** Fix iOS Instant Recipes install (wipe path + iOS 17 availability)

## 2026-08-06 13:55:22 EDT

- **Repository:** instant-data-swift
- **Commit:** `24520678695b530f1dc2ca5462094e93228830be`
- **High-level reason:** Auth recipe page public + account counters reacting to login/logout (#152)


## 2026-08-06 13:49:55 EDT

- **Repository:** instant-data-swift
- **Commit:** `24520678695b530f1dc2ca5462094e93228830be`
- **High-level reason:** Put public + account counters on Auth recipe page so they react to login/logout (#152)


- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `44cd5f9ff0005907f53eb748d94b26dd46c71bd2`
- **Reason:** Memory soak dependency fixtures + debounced timeline saves for long-recording footprint (#044).

## 2026-08-05 22:20:42 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `6390d50ba2899ad65008c9652f854bbbdc15f5ea`
- **Reason:** Denser greppable process metrics (5s, CPU peak, thermal) and discrete TCA dual-write over diagnostics WebSocket for #044 long-recording thrash diagnosis.

# Commit changelog

## 2026-08-05 20:19:02 EDT

- **instant-data-swift** tag `v1.5.6` @ `29495b966108b5a90de0ab09a61a8a93f8ed87ed` — Production Scribe namespace soak + dual Instant thrash + demotion guest auth (#150).
- **realtime-voice-sqlite-instant** `39ebb186136d` — Pin Package.swift exact 1.5.6.
- **realtime-voice-sqlite-instant** `204e6582af9efb66410c6e39703de6b25c37e5f2` — Instant-lane library chatter filter.


## 2026-08-05 20:03:36 EDT

- **instant-data-swift** `60df101efae42243b139eb4d5b2260934e1b1a99` — Production Scribe namespaces + dual Instant debugLogs thrash soak (#150).
- **realtime-voice-sqlite-instant** `204e6582af9efb66410c6e39703de6b25c37e5f2` — Instant-lane filter for library chatter re-entering debugLogs thrash (#150).

## 2026-08-05 13:12:29 EDT

## 2026-08-05 17:37:25 EDT — realtime-voice-sqlite-instant dual-write feedback fix

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `a3d415fdd4500c3b6edb1232d74eaa1473bc36ef`
- **Reason:** App-side bridge filter + smaller debug log batches to stop Instant dual-write memory thrash on idle iPad.


## 2026-08-05 17:37:14 EDT — instant-data-swift diagnostic dual-write thrash fix

- **Repository:** instant-data-swift
- **Commit:** `759c899a8a4f76ccaa2d473e5f15c33fe86946fc`
- **Reason:** Break InstantDiagnostics dual-write feedback that drove multi-GB idle memory via continuous debug-log-batch mutations.


## 2026-08-05 13:31:35 EDT — realtime-voice-sqlite-instant performance plan pointer

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `af82b476348d2ece9d976b9740dd99f9986eb4ba`
- **Reason:** Point Scribe agents at Instant production performance readiness plan after iPad 880MB+ thrash evidence.

## 2026-08-05 13:31:18 EDT — realtime-voice-sqlite-instant plan handoff (instant-data-swift)

- **Repository:** instant-data-swift
- **Commit:** `c5f9a0cef24161e92b0f51bc252faf50cb87fccc`
- **Reason:** Document production performance readiness plan from research quorum and live iPad thrash evidence (880MB+ idle, gate holds, receive-loop isolation gaps).

- **Repository:** instant-data-swift
- **Commit:** `8fbfa0c8ef1d95457929a9b4462c65f85923c9f2`
- **Reason:** Recipes outbox panel, wipe/clear, delete todos, sharing counters (#152)

## 2026-08-05 12:58:28 EDT

- **Repository:** instant-data-swift
- **Commit:** `551bb333839dcd050fb7ad4acf312124ee87d046`
- **Reason:** Scribe-shaped linked-infinite memory soak publish gate (#150)

## 2026-08-05 12:48:03 EDT

- **Repository:** instant-data-swift
- **Commit:** `ca483b549791175854c0f21faf25eae72a016cc2`
- **Reason:** Isolate failed legacy unknown-overlay mutations so live server apply continues (fixes receive-loop thrash on poison outbox rows; #134)

## 2026-08-05 12:41:23 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** 4320fc235fa953d5c7116f91541ce6d8fc92e22a
- **Reason:** Require mid-work Instant workLog progress so future agents can resume from query-issue.

- **Repository:** skills
- **Commit:** 39496e6099b66461242534302e926690c94f208a
- **Reason:** issue-tracker mandatory progress workLog section for future-agent handoff.

## 2026-08-05 12:29:20 EDT

- **repo:** instant-data-swift
- **commit:** `1a7303ac92ff0d689b34a4c12e541b86337edd29`
- **reason:** Recipes-v3 floating debug panel (memory/logs) after idle 5GB linked-infinite process; relaunch front and center.

## 2026-08-05 12:27:16 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** d77d69ed48930836bac97ef1786cbda90db67cc8
- **Reason:** Expand Instant issue-triage policy to feature requests, ideas, and capability gaps.

- **Repository:** skills
- **Commit:** 77b39de584456e7e47bd09d7ef44b2d87e218c83
- **Reason:** issue-triage skill covers features/ideas; claim only when executing.


## 2026-08-05 12:27:03 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `35afbcc9f144180f16bb889e584c56f950b47eba`
- **Reason:** Remove 640pt readable-column cap so recording transcript uses full width on iPad/Mac.
## 2026-08-05 12:24:10 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** c9fe3386fbcf961f93cb73a6f258234883704f89
- **Reason:** Require Instant issue triage on user-reported defects; Instant-only tracker, never GitHub Issues.

- **Repository:** skills
- **Commit:** da08e4ed703c4e1e4a69ad5c9a93cecd9d1cab7c
- **Reason:** Add issue-triage skill (search Instant catalog, claim or create, hand mutations to issue-tracker).

## 2026-08-05 12:10:52 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** ee7da38254ec72db838c954794c93a1993273b78
- **Reason:** Build debug overlay process-memory series (5s samples) + sparkline graph.

## 2026-08-05 09:51:26 EDT

- **repository:** realtime-voice-sqlite-instant
- **commit:** `16b7e9e82146305d03f68065334c9b30aeda67e1`
- **reason:** Add Scribe Diagnostics suite with audio route probe and Device Hub silent-mic warning

## 2026-08-05 09:36:23 EDT

- **repo:** instant-data-swift
- **commit:** `adeea919009c` (tag v1.5.2 / `7dc2fe28`)
- **reason:** Instrument live infinite-query page-info and auth for host dual-write diagnostics.

- **repo:** realtime-voice-sqlite-instant
- **commit:** `5f0c98429013e198ecc31df62eac22ec649fe59b`
- **reason:** Bridge InstantDiagnostics to Tailnet dual-write logger; pin 1.5.2; list owner fingerprints.

## 2026-08-05 09:44:30 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `68f1a8faa44f14cfee7452f028b61327c808c43a`
- **Reason:** Multi-lane deep links/OAuth/companion pairing + localDev agent evidence defaults from bundle-id audit.

## 2026-08-05 09:09:23 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** d8ae5cd489883d22200b8eaa58e9297253b6e972
- **Reason:** Floating build debug overlay with Shared file-backed presentation modes (hidden/collapsed/expanded), opacity, and build provenance copy panel.

## 2026-08-05 09:22:15 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `bb22fd3507dc4dc48c68536febd2989aba3e5060`
- **Reason:** Typed ScribeBuildCatalog multi-lane identity + \$scribe-install skill (localDev default; TestFlight upload-only for production host).

## 2026-08-05 08:51:00 EDT

- **repo:** instant-data-swift
- **commit:** `cdd1ba421f27269b4307ff6056e2bd908096e926` (tag v1.5.1 / `43e3385c2e0aa2318aafcd63c0171192ce8e55ef`)
- **reason:** Fix live infinite short-page canLoadNextPage thrash that Jetsam-killed Scribe on iPad during recording.

- **repo:** realtime-voice-sqlite-instant
- **commit:** `39722d4e9a2bd75e79d5da9477b692b61659b2a0`
- **reason:** Pin instant-data-swift 1.5.1 and stop list/constellation loadNextPage thrash that OOM-killed iPad recordings.

## 2026-08-05 08:32:30 EDT

- **repo:** realtime-voice-sqlite-instant
- **commit:** 
- **reason:** Land TestFlight App Store validation fixes, versioning docs, and app/vakyume/0.1+3 tag metadata for the first VALID Vakyume upload (build 3).

## 2026-08-05 00:19:30 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `51eb3a58ecf08047c55baeb31b7ef3702da55322`
- **Reason:** Make Stream Companion Settings agent-controllable without QR

## 2026-08-04 23:27:17 EDT

- **repository:** realtime-voice-sqlite-instant
- **commit:** `b63973acac674e1fd9a51c2f3629c57af3d8f073`
- **reason:** Stamp and show auto-detected device icons on recordings (list UI, settings auto-detect, device-local preference).


## 2026-08-04 22:42:05 EDT

- **repository:** instant-data-swift
- **commit/tag:** v1.5.0 (0a91a121) / a3b63e73
- **reason:** Empty live-query replacements preserve pending optimistic children; Linked Infinite blank-detail recipe + tests; ADR 0013.

- **repository:** realtime-voice-sqlite-instant
- **commit:** c3423e09e31460c85072962dbc196c04a644b310
- **reason:** Pin instant-data-swift exact 1.5.0 for blank-detail library fix.
## 2026-08-04 22:38:35 EDT

- **repo:** realtime-voice-sqlite-instant
- **commit:** 9e21a429821bf10b5d3bfd7dfd2d94d0b3317861
- **reason:** Stream Companion Instant owner perms + TS auth daemon skeleton


## 2026-08-04 22:30:42 EDT

- **repository:** realtime-voice-sqlite-instant
- **commit:** 5f1cdfa7380fa9efd67745cfb5dfc9dd89ede1ed
- **reason:** Preserve playback timeline when Instant detail join is empty; full transcription upserts and empty-detail diagnostics.

- **repository:** instant-data-swift
- **commit:** a3b63e73af0f32921506132a5c40e71621064962
- **reason:** Do not retract pending-optimistic entity triples on empty live-query replacements (Scribe blank-detail).
## 2026-08-04 22:11:33 EDT

- **repo:** realtime-voice-sqlite-instant
- **commit:** ff7835d2642875a9b83ad1ed6b8f8781efa1606d
- **reason:** Tuple-inspired Stream Companion: scribe-stream-agent connect (Grok/Claude/Codex) + design/prompt docs
## 2026-08-04 17:31:40 EDT

- **repo**: realtime-voice-sqlite-instant
- **commit**: `2aa994a60468841c73640ce9b8651e3444f6fd1e`
- **reason**: Stream Interactor multi-message segment replies, AgentThread navigation, fenceposts

## 2026-08-04 17:31:25 EDT

- **repo**: realtime-voice-sqlite-instant
- **commit**: `144d0f6d875effa5ac320a145ed1ffa3381cafb8`
- **reason**: Stream Interactor multi-message segment replies, AgentThread navigation, fenceposts

## 2026-08-04 17:12:23 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `0156b980d46f9912f6ad38acf666269f25bb1691`
- **Reason:** Rename the Mac app to Scribe and embed the real AppIcon so Spotlight no longer shows a generic "Scribe Shared" Application tile.

## 2026-08-04 16:15:34 EDT

- **repository:** realtime-voice-sqlite-instant
- **commit:** 1f1c3637a7eca44cc918f2406bbac4a217beada6
- **reason:** Join-shaped recording list: single infinite + transcription include; dual-write graph ref

## 2026-08-04 16:15:34 EDT

- **repository:** instant-data-swift
- **commit:** d862dc083d8d0614bff0dd126557687fd8ac3a4b
- **reason:** Linked infinite paging recipe with includes, InfiniteQueryPhase/pageSize, CLI seed/list/page, README

## 2026-08-04 15:59:36 EDT

- **Repository:** instant-data-swift
- **Commit:** 43015b16fec14a49157915fb88c51a323a813618
- **Reason:** Detailed handoff for typed Instant permissions result builder + custom bindings.

## 2026-08-04 15:55:21 EDT

- **Repository:** instant-data-swift
- **Commit:** 0ac518d51c716dc05c94fc46e14d2177bc8ce411
- **Reason:** ADR 0012 — typed Swift Instant permissions as source of truth (ADT + TS parse/print).

## 2026-08-04 15:44:40 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** 1112c4f045934212bf5a1d3a1ff393bada86dfb8
- **Reason:** Add private Instant segment-range shares for partial transcript access.

## 2026-08-04 15:32:18 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** be0d24be3d4f07b54405f49844a692dec0a8cdda
- **Reason:** Restrict recording/transcription Instant access to owner, linked guest, and share members (schema, perms, write-path ownership, reader/writer share helpers).

# Cross-Repository Commit Changelog

Newest entries go at the top. Timestamps include seconds and use Eastern Time
(`America/New_York`). Each substantive commit records the repository, full
commit SHA, and high-level reason. Changelog-only bookkeeping commits are
visible in Git history but are not self-recorded because a commit cannot
contain its own final SHA.

## 2026-08-04 14:50:12 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `8d192863b280887cd6bbe69ed7cfe364d91626e1`
- **Reason:** Wire installed Mac `ScribeSharedApp` Settings to `ScribeMacSettingsView` so Manage account / Instant sign-in is available on Mac (Option A; uses `apple-mac` provider config).

## August 4, 2026 at 12:55:02 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f1f74bb6915c`
- Reason: Pin published `instant-data-swift` **1.4.0** (API-convergence inventories)
  in Package.swift, Package.resolved, and installer required dependencies.

## August 4, 2026 at 12:53:10 PM EDT

- Repository: `instant-data-swift`
- Commit: `c8c8011f5846a66fa29da4f1ca809b62dc418c09`
- Reason: Full suite green for 1.4.0 (1351 tests / 115 suites, known issues
  only). Parity-count pins, outbox-revision and mutationCount expectations,
  reactor message counts, SAFETY comment, and `docs/releases/v1.4.0.md`.

## August 4, 2026 at 12:13:51 PM EDT

- Repository: `instant-data-swift`
- Commit: `3e625416e2db9376606bcecaff97043de4073c94`
- Reason: Same inventory/port procedure as Instant TypeScript, applied to
  Point-Free SQLiteData: 261 runtime tests enumerated at vendored `0c79d7a`
  (dual-method + subagent), gap analysis with CloudKit/SQL human boundaries,
  ergonomics ports for date roundtrip and assertQuery-style dumps, full parity
  registry coverage, and reconciliation tests that fail on drift.

## August 4, 2026 at 11:34:35 AM EDT

- Repository: `instant-data-swift`
- Commit: `c4badb4bf6b0deb1d44e0fc98fd1f9a827c0f86e`
- Reason: Port upstream's only core benchmark (`instaql.bench.ts` `big query`)
  to Swift: correctness pin, package-benchmark `LocalRead.deepJoin.zeneca`,
  parity record, and reconciliation coverage for `*.bench.ts`. Measured
  release arm64 p50 23 ms vs TypeScript 4.707 ms (~4.9× slower) — the port is
  complete and the gap is now a performance task with numbers in
  `INSTANT_DATA_PERFORMANCE_BENCHMARKS.md`.

## August 4, 2026 at 11:28:18 AM EDT

- Repository: `instant-data-swift`
- Commit: `5d28f49070efbecc49fc32ab02a66b730af881f5`
- Reason: Finish the inventory re-baseline against the package's own vendored
  InstantDB checkout (`e7101761`, 19 files / 186 declarations / 225 runtime
  cases) and close the loop that made parity checkable. Fixed stale Swift test
  names and paraphrased `sourceTestName`s in `InstantParityCoverage`, and added
  `InstantUpstreamParityReconciliationTests` so renames, invented upstream
  names, missing records, and a moved vendored commit fail the suite. The only
  remaining open porting item from the gap analysis is the
  `instaql.bench.ts` deep-join benchmark.

## August 4, 2026 at 11:04:13 AM EDT

- Repository: `instant-data-swift`
- Commit: `a4c445ad97b4b8ca17ad1a0b56e284957cd6fba2`
- Reason: Make "we have parity with upstream" a measurement instead of an
  assertion. Added `docs/porting/upstream-typescript-test-inventory.md` (every
  one of the 175 declarations / 211 runtime cases in `@instantdb/core`, with
  file, line and greppable name, plus the single benchmark) and
  `docs/porting/swift-port-gap-analysis.md` (that inventory reconciled against
  `InstantParityCoverage.swift` and the 1338 Swift tests). Counts converged
  across three independent methods run twice consecutively. All 175 upstream
  declarations resolve to a parity record; date coercion and the `Where OR`
  table were verified case-by-case rather than by record count and are
  complete. Real gaps found: a stale Swift test name cited by four records,
  ~20 records storing paraphrases where upstream's literal test name belongs,
  and no Swift equivalent for upstream's `instaql.bench.ts` deep-join
  benchmark.

## August 4, 2026 at 10:19:57 AM EDT

- Repository: `instant-data-swift`
- Commit: `900050e68ee08714f09422182b14a3322b06ab2b`
- Tag: `v1.3.1` moved here — **still local, NOT pushed**
- Reason: Stop counting every triple on every prepare. Third instance of the
  same shape as `04f1b668`, and the one that dominated once the outbox resend
  loop was gone: `TripleIndexes.tripleCount` walked every entity × attribute ×
  value, and `InstantStore.prepare` reads it on every applied transaction and
  every terminal-failure removal. Sampled on a Mac holding ~400% CPU against an
  883,388-triple store, that single getter was 2,400 of 5,301 samples, reached
  through `failMutation → prepareTerminalFailureRemoval → prepare`. Now
  maintained by `insert` and `removeNormalized`, which already read the slot
  they are about to write, so the delta is exact for the cases that are easy to
  get wrong — identical re-insert, cardinality-one eviction, retracting an
  absent triple. `Codable` is now explicit so only eav/aev/vae are encoded and
  the count is recomputed on decode: adding a derived field to the wire format
  would have stopped persisted caches from decoding, which is precisely the
  migration failure behind `3ebc6704`. Measured on a copy of the real store,
  one transaction through `prepare`: 0.0744 s → 0.0119 s. **Relevant to the
  Scribe repository:** with all three fixes the Mac converged to 7–26% CPU
  after ~150 s and its outbox drained (pending 256 → 110) for the first time,
  where before it held 200–400% indefinitely against an unchanging store.

## August 4, 2026 at 9:59:35 AM EDT

- Repository: `instant-data-swift`
- Commit: `3ebc6704973ce470a356457de8a4b5236d5641e8`
- Tag: `v1.3.1` — **created locally, NOT pushed**
- Reason: Stop re-sending mutations the server already accepted. This is the
  root cause of the Mac holding ~200% CPU indefinitely while its store stayed
  byte-for-byte unchanged: it was re-sending 7,125 already-accepted mutations
  in a loop. `confirmationSource` was added to `PendingMutation` after
  `serverTransactionID`, so every mutation accepted by an earlier build carries
  a server-assigned ID and a nil source; six call sites asked "has the server
  accepted this?" by consulting `confirmationSource` alone and answered "no"
  for all 6,887 such rows, permanently. A single
  `PendingMutation.provesServerAcceptance` predicate now also honours a non-nil
  `serverTransactionID`, which `Outbox.accepting` alone writes and only from a
  server `transact-ok` — so delivery finally agrees with `pruningConfirmed`,
  which already treated it as the authority. Measured on a copy of the real
  645 MB store: 7,125 → 256 mutations offered per server event, and 1.05 s →
  0.047 s to build one batch. The count is the bug; the time is why it never
  recovered, because a rebuild took longer than the gap between inbound events.
  **Relevant to the Scribe repository:** this is why the Mac "went quiet" and
  never claimed a screen-stream session — its Instant event loop never
  returned. Tracked as issue 146.

## August 4, 2026 at 9:59:35 AM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commit: `bb2c26b437d5d1070af8cc2df6adffaf11b916aa`
- Reason: Consume `instant-data-swift` 1.3.1 so the outbox stops re-sending
  accepted work. **This commit does not build anywhere but the authoring
  machine until `git push origin v1.3.1` is run in the library repository** —
  the tag was created locally so the fix could be verified against a real
  device before publishing, and publishing was deliberately left to the
  repository owner. Push the tag or revert this commit before sharing the
  branch. A local SwiftPM mirror (`.swiftpm/configuration/mirrors.json`) points
  the dependency at the sibling checkout, because `swift package edit` silently
  fails to take effect here: the committed `Packages/instant-data-swift`
  symlink already occupies the directory SwiftPM manages for edited packages,
  so `show-dependencies` kept reporting the remote 1.3.0 and two full app
  builds were measured against the unfixed library before this was caught.

## August 4, 2026 at 7:07:52 AM EDT

- Repository: `instant-data-swift`
- Commit: `04f1b6682bf23c17103da501174d50e27fb38bd5`
- Reason: Stop the write path from scaling with the size of the schema. A Mac
  Scribe process sat at 99.5% CPU across three cooperative-pool threads for 136
  minutes, applying server transactions against the diagnostics store (343
  attributes, 883,388 triples, 7,928-deep outbox) and never returning to its
  event loop. `AttributeStore.namespaces` rebuilt a `Set` from the whole
  attribute table on every read while `validateWriteValue` reads it twice per
  triple, so each write was O(attributes); it is now maintained beside the other
  derived lookup indexes. `newestWriteTime` materialised an array per write key
  to take a maximum, and `visibleWriteFilter` asks for it once per key across the
  entire outbox on every inbound server event; it is now `lazy`. Measured at
  2,000 writes with attribute count varied: 800 attributes went 1.825 s → 0.025 s,
  and the growth from 100 → 800 attributes went 7.1× → flat. **Relevant to the
  Scribe repository:** the app looked disconnected — a screen-stream session
  stayed `requested` and was never claimed — when it was actually saturated, so
  "the Mac went quiet" was a CPU-starvation symptom, not a transport failure.
  Evidence is linked to issue 125, which owns the complementary half (why the
  diagnostics store grew that large). Still unfixed and named there:
  `sendOutstandingMutationsToLiveSession` rescans the entire outbox on every
  inbound server event, which remains O(outbox) per event.

## August 4, 2026 at 7:41:18 AM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commit: `f991e9b8675203d1c9c60b1f0dae68ceb0c79d1e`
- Reason: Make the unlaunchable macOS build loud, and offer a reproducible way
  past it. The macOS app has been unlaunchable since 2026-08-02 (issue #141):
  it declares `com.apple.developer.applesignin`, macOS honours that restricted
  entitlement only when an embedded provisioning profile grants it, and the
  installer embeds no profile — so launchd refuses to spawn the process before
  any application code runs, leaving the app's own logs empty while the
  installer reports success. The default path now warns with the unauthorized
  entitlement, the missing profile path, and the exact error about to appear;
  `--strip-unprofiled-entitlements` opts into a launchable local build and says
  plainly that Sign in with Apple is absent from it. Issue #141 records that the
  choice among its three fixes is a product decision about signing identity, so
  this deliberately leaves that decision open and only removes the silence.
  Previously the only working macOS build was a hand-re-signed artifact that no
  repository change could reproduce.

## August 4, 2026 at 7:07:52 AM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commits: `65076f1cdb5fbbd0abd7fb748f0a85a26e5f6b63`,
  `6f035076d6e76366549ec3922a54e09149631f12` (WIP checkpoint)
- Reason: Make five seconds the timeout everywhere in `AGENTS.md`. Written down
  after the wedged Mac above went undiagnosed while a probe sat on a 60-second
  watch and reported nothing: a long timeout does not make a stall less likely,
  it only delays discovery and turns a loud failure into a hang that reads as
  "still working". Work that legitimately needs longer is a progress-reporting
  problem, not a timeout problem. The second commit checkpoints another agent's
  untracked `docs/core-module-extraction-audit.md` unmodified, because the macOS
  installer refuses to build from a dirty checkout and `AGENTS.md` names a WIP
  checkpoint as the way to preserve another agent's in-flight work rather than
  stashing it.

## August 4, 2026 at 5:10:00 AM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commits: `8b51efd191d84a0b2e47815be4fd718f168c90cc`,
  `276ec1f4017e9b4bbb34cc27eeb3a8b59eb724ee`,
  `5fdddd7` (docs/ADR)
- Reason: Open the running TCA store to an agent over the diagnostics WebSocket.
  A physical device has no terminal touch path (`devicectl` exposes no input
  command), so the reducer that was meant to be terminal-drivable was reachable
  only by a finger. `.agentRemoteControl` sits at the root beside `_printChanges`
  and accepts `listActions`, `readState`, `sendAction` through the same reducer
  the UI uses. The catalog is generated by a `@RemoteControl` macro from each
  `Action` enum instead of being hand-maintained; nesting composes, so the iPad
  build exposes 181 actions with no list in the source. **Relevant to this
  repository:** driving the store from a terminal immediately exposed a lost
  reservation acknowledgement — the recording-title counter advanced 184 → 185
  server-side while the client sat in `isRecordingTitleReservationInFlight` with
  no timeout, which is delivery/acknowledgement behaviour the library owns.

## August 4, 2026 at 1:56:30 AM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commit: `325af15aedb4a4a53e0f9a2ba14b6e1b0f4a4b3c` (see `git log` for the full SHA)
- Reason: HACK — tolerate an empty pre-sync emission for the recording-title
  counter so the record button can start a recording. On a fresh iPad install the
  live observation emitted an empty materialization for `recordingTitleSequences`
  16 seconds before that namespace synced; the client read it as data, threw
  "received 0", ended the observation, and discarded the authoritative high water
  of 183. **Owed to this repository:** load state on `InstantQueryEmission`,
  mirroring upstream InstantDB `isLoading`, so consumers can distinguish a cold
  cache from a server-confirmed empty set. Landing that flag removes the hack.

## August 4, 2026 at 1:15:49 AM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commit: `7cd5c6d2d2826c6cce1dfeea5d81569184cda05a`
- Reason: Write diagnostics to the tailnet WebSocket collector and the InstantDB
  `debugLogs` app at the same time, and instrument the record-button gate in the
  reducer. An iPad on `dfbe377` produced no diagnostic events for a dead-looking
  record button, and its InstantDB lane had been dark for two days while the app
  kept running, so a lane built on the Instant client could not report its own
  outage. Also preserves `InstantError` detail that the `NSError` cast had
  collapsed to domain plus code 1.

## August 3, 2026 at 11:39:21 PM EDT

- Repository: `instant-data-swift`
- Commit: `a52ab0911d4e78e1b7b33f610240fe55c74f069b`
- High-level reason: Fix the library-side blocker behind the Mac livestream (#003) and, more broadly, behind every stale device. Instant stores attributes as data, so a client can only materialize namespaces whose attributes it holds, and query observation refuses to subscribe to a namespace it cannot validate. The client decoded the attribute set the server sends in every `init-ok` but kept it in memory; attributes only became durable as a side effect of a query result for a namespace it already knew. That deadlocks for every namespace it did not: no attributes means no subscription, no subscription means no result, no result means the attributes never arrive — silently, with a healthy-looking connection. Upstream applies the set on every `init-ok` (`Reactor.js:640`); this now does the same on the connect path, merging rather than replacing so a namespace/name pair the device already holds keeps the local attribute id its triples and pending mutations reference. Proven against the real server from a cache holding no attributes: 0 → 361 attributes across 37 namespaces after one connect, and unchanged with the call removed. Decision recorded in ADR 0011. CORRECTED 2026-08-04: this entry originally said the defect was why the Mac never saw a stream request (#003), citing a cache frozen at 133 attributes over 16 namespaces. That file (`~/Library/Application Support/InstantDB/`) is stale and unopened; the app uses `~/.instant-swift-data/apps/`, which holds 466 attributes over 38 namespaces including 16 locally-seeded `screenStreamSessions` attributes. The causal claim is withdrawn — an app that seeds `initialAttributes` from its schema cannot hit this deadlock — while the defect and fix stand on the clean-cache evidence.

## August 3, 2026 at 6:42:32 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `46e20a2c80611e4b832e7e386ba819ba9029ee1b`
- High-level reason: Isolate the Mac-side claim failure for the livestream (#003) with a terminal-driven probe rather than UI guesswork. `scripts/screen-stream/probe-mac-claim.mjs` writes a fresh unexpired `screenStreamSessions` request in exactly the shape the phone produces and polls for 60 s; the running Mac never claimed it. Ruled out the false negatives first: permissions grant `view: "true"`, the Mac process was alive with two established TLS connections, and every session since 2026-07-29 is likewise unclaimed. Narrows the cause to the Mac Instant store never installing as default (where an `AsyncSerialGate` stall would present, and the deployed build pins published 1.2.2 without the fix) or `observeAll` never emitting — and notes that the remote log lane, dead since 2026-07-30, is installed by that same bootstrap, so both symptoms may be one defect.

## August 3, 2026 at 6:42:32 PM EDT (build blockers)

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commits: `082dd0f8b5253e5f02ccc9fae122020c39a0cc95`, `0ee348982516d680508d7aef2dc168ed45f5f8c8`, `749e06d21ff3c97b9ebf0f1fa418865d0a82c3a7`
- High-level reason: Clear three blockers that prevented any provenance-checked device install. `.claude/settings.local.json` was ignored only by the user-level global gitignore, which the SwiftPM plugin sandbox cannot read, so every reproducible build failed "requires a clean worktree" while the tree looked clean outside the sandbox. Two genuine bugs in the checkpointed code stored JavaScript's `MAX_SAFE_INTEGER` in an untyped `Int`, which overflows on watchOS `arm64_32`; `SharedModels` then failed to emit for the watch leg and took the whole embedded iOS scheme down, which was the root of all 150 device-build failures and is invisible to the 64-bit macOS test suite.

## August 3, 2026 at 7:19:04 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commits: `5919c9e672b922e659615542a4002a44bbb1ce68`, `f5c4dc3` (see Git history for the full SHA)
- High-level reason: Fix the Mac half of the livestream (#003) and narrow what remains. The Instant store was started by a SwiftUI view's `.task` and cancelled by its `.onDisappear` with a per-view `@StateObject`, so on a macOS app that deliberately outlives its windows, closing one cancelled the shared bootstrap — taking down both the screen-stream claim loop and the real remote logger at once, which is why both went silent on 2026-07-30 with no error reported. The store is now process-wide and started from `applicationDidFinishLaunching`; on-device logs confirm the claim loop starts for the first time. Separately, `observeScreenStreamSessions` swallowed every subscription error into an empty catch and then finished the stream, leaving the Mac in a silent one-second retry loop; failures are now loud through `reportIssue` and a structured event. What remains is precise and library-side per ADR 0001: the `screenStreamSessions` subscription stays alive and never delivers a first batch, with the `AsyncSerialGate` stall (absent from the pinned published 1.2.2) as the leading hypothesis.

## August 3, 2026 at 5:06:55 PM EDT

- Repository: `instant-data-swift`
- Commit: `4b596d4ec9b42ba8c62dada1aa52cf22442c82ae`
- High-level reason: Honor cancellation in `AsyncSerialGate` and name the holder when it stalls. The old 23-line gate parked cancelled waiters forever (non-throwing continuation, no cancellation handler), so Scribe's cancel-in-flight session-request retries each made the stall permanently worse; `transact` now enters the operation gate cancellation-aware (honored only before acquisition so a started critical section still completes), the four runtime gates are labelled, and a watchdog reports the holding function, longest waiter, and queue depth through `InstantDiagnostics` and `reportIssue` instead of stalling silently. Verified against upstream: `Reactor.js` has no equivalent primitive because the JS reactor is a single event loop, making this a documented Swift-side adaptation. Continues an earlier agent's uncompiled work; it built and all 8 gate tests plus the full suite passed unmodified.

## August 3, 2026 at 5:05:10 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8e79caa0201c12684609df2de0e39c4a8f2b498e`
- High-level reason: Link the live screen publisher into the iPhone app and record the decision. The phone linked only `ScribeSharedAppCore`, whose closure deliberately contains no LiveKit, so no publisher could ever have run on device regardless of reducer wiring; `project.yml` now links `ScreenStreamFeature` (mirroring the Mac target), the host app registers the live client with `prepareDependencies` so the linker cannot dead-strip the conformance, and the #066 linkage test pins the new product list while the appex allowlist stays `SystemAudioBroadcastHandoff` only. Decision recorded as Scribe ADR 0001.

## August 3, 2026 at 5:03:35 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `55c08113995164d82c6045a8794800adb8dda3be`
- High-level reason: Wire the `Recording` reducer to start, feed, and stop the screen publisher (#003). Start on ReplayKit broadcast activity with a ready saved configuration, forward every JPEG frame with no second throttle so `videoSampleInterval` stays the only rate control, stop on broadcast end and every teardown path, log loud named failures with the exact fix, and exclude the Mac by data (`automatesScreenStreamPublisher`) because it holds a subscriber-only grant in the same App Group slot. Seven TestStore tests pin the behavior.

## August 3, 2026 at 5:01:20 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c0fc4ac0da5ba1b785f7ea817c269b397e4c46f2`
- High-level reason: Build the missing host-side bridge from broadcast JPEG frames to the LiveKit publisher (#003). `captureVideo` had zero callers; this adds the `ScreenStreamPublisherClient` seam, the JPEG→BGRA `CMSampleBuffer` converter, a strictly increasing host-side publish timeline that refuses to inherit the #143 clock reset, and a live bridge session reporting `framesReceived` vs `framesPublished` on every event so frame loss can never be silent again.

## August 3, 2026 at 4:18:52 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1b5321e068d6a44bdb280c83006e8601fddab2dd`
- High-level reason: Correct the livestream diagnosis and reorder the work behind it. `ScreenStreamClientLive.captureVideo` and `captureAppAudio` have zero callers anywhere in the repository, so the LiveKit publisher is fed by nothing at all — the broadcast extension's JPEG frames terminate in the recording transcript instead — which means the prior framing of "the carrier is too slow to reach video rate" was wrong and fixing the session-request stall alone would have connected a room and published an empty track, presenting as a LiveKit or token defect. Records the revised order (bridge the existing frames into the publisher first to prove room connect, token, publish and render end to end, then fix the stall, then replace the file carrier with LiveKit's Unix-domain-socket path), the developer's requirement that publish cadence respect the existing `videoSampleInterval` setting rather than a second throttle that would silently multiply it, the per-frame performance measurement points the bridge must leave behind given the device already leads energy use at ~25% of one core and 40.3 °C, and the state of three subagents terminated mid-task by an account usage limit — including uncommitted and never-compiled `AsyncSerialGate` cancellation work in this repository, and a proven-compiling WebRTC-free 16-file broadcast closure whose host-side symbol collisions argue for forking `client-sdk-swift` rather than vendoring it.

## August 3, 2026 at 2:41:06 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c7a236377030000fc23be3b8596e25c42499c52c`
- High-level reason: Record that Scribe and `instant-data-swift` are co-developed through a symlink so a Scribe symptom is as likely to originate in the library (and a reinstall does not rule it out, because the cache and outbox persist on disk); add `docs/performance-budget.md` as the release gate, written against the measured 2026-08-03 sysdiagnose baseline with a measurement command beside every threshold; symlink `CLAUDE.md` to `AGENTS.md` so the canonical instructions cannot drift.

## August 3, 2026 at 2:39:23 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `6430fd0d6b725c3e7bfdf9b5ceb74fea56822465`
- High-level reason: Point the diagnostics status probe at the port the collector actually listens on, because the Foldkit portal squatting the old port answers `/health` with a 404 rather than refusing and so disguised a healthy collector as a broken one; document the tailnet TLS prerequisite whose absence kept the shipping diagnostics lane dark, along with its device-visible `NSURLError -1004` / POSIX 61 signature and the fact that `tailscale cert` writes a private key into the working directory.

## August 3, 2026 at 2:37:05 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3dbc3a4ff6d1384cce2ab99d6fdc109ce2a7e103`
- High-level reason: Restore supervision of the shipping diagnostics collector by binding it to a free port instead of evicting an unrelated project that has held 8765 since 2026-07-26, and scope the installer's dirty-tree guard to the files launchd actually executes so unrelated in-flight work on shared `main` can no longer block a clean install — the repository-wide check could only be satisfied by committing another agent's uncommitted changes.

## August 3, 2026 at 2:32:51 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1b586060af1d024085ae9c50b1e27dc220607c8a`
- High-level reason: Teach the Instant schema drift gate the pulled `rooms` root key so its comparison runs again instead of failing closed on every invocation; record and enforce the decision not to compare rooms (they are client-side declarations the pull echoes, never server state), and report an unrecognized root key as a named unsupported-feature failure. (#144)

## August 3, 2026 at 12:49:11 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `9fdadc081e81e9e688c0c117d94eebcf6697e986`
- High-level reason: End the ReplayKit broadcast when the recording stops, via a Darwin notification the extension honours, because only the extension can call finishBroadcastWithError. (#066, #120)

## August 3, 2026 at 12:23:16 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `66b30f5e57bdc2e94615fa678a2d34212c384eda`
- High-level reason: Remove a DragGesture(minimumDistance: 0) that claimed every touch in the recording timeline so rows opened on swipes, and make the system-video frame interval configurable end to end. (#140)

## August 3, 2026 at 10:23:20 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `39bd55cd7d2edc4ebc3d6f104f22cc7abc90c23c`
- High-level reason: Make the broadcast panel's video toggle and picker work: the toggle guarded on !isRecording while its panel only renders during recording, and the picker searched only RPSystemBroadcastPickerView's direct subviews for a button that is nested deeper. (#140)

## August 3, 2026 at 8:38:14 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `7f7e1ddad4a6b995854c86379d5eebe162cd1dd7`
- High-level reason: Unlink ScreenStreamClientLive from the broadcast upload extension, which had pulled LiveKitWebRTC and RustLiveKitUniFFI into an appex with no Frameworks directory on its runpath, so dyld killed the extension at launch every time. Root cause of system audio being dead since c409dec on 2026-07-28; verified on the physical iPhone. (#066)

## August 3, 2026 at 6:24:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `fedeae5301c87f1424a1df13905b85e01b2bcff1`
- High-level reason: Guard a Mac-only Process/Pipe call site so ScribeSharedSupport compiles for iOS, watchOS, tvOS and visionOS again; the entire iOS app had been unbuildable since bdf0173. (#138)

## August 3, 2026 at 6:09:43 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5b18ed77e4cc5a043db2bc4f744654301c733f93`
- High-level reason: Give the broadcast upload extension a diagnostic lane that is not the channel under suspicion: a heartbeat written by whole-file replacement, mirrored into the shared UserDefaults suite and readable after the extension exits. (#066)

## August 3, 2026 at 3:24:09 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `823d547e669f6545224cc9b76bc3e581a64b2b0f`
- High-level reason: Align the E2E latency gate to the 200 ms target #089 actually states; the previous 100 ms sat below this location's measured network floor to api.instantdb.com, so it failed on something no client change could reach.

## August 3, 2026 at 3:24:00 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `654e07549bad14da4ab51dcd02981aac8d954aed`
- High-level reason: Pin with a focused test that one unrelated terminal outbox row no longer silences the InstantDB diagnostics lane, giving #135 criterion 3 the evidence d829490 shipped without.

## August 3, 2026 at 3:23:50 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5a4f552774bca07f3253cc4a3128da29b07e2ea4`
- High-level reason: Give the stream listener per-segment isolation so one unanswerable segment stops losing the developer's speech, and stop a failed remote write leaving presence claiming a listener is both observing and stopped. Five focused tests verified to fail against the pre-fix source. (#137)

## August 2, 2026 at 7:21:33 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8b7db0813ec8282a906d3287a80a016723180143`
- High-level reason: Isolate the generic real-Instant Swift E2E writer in a
  fresh per-report HOME/Application Support/database tree so the test cannot
  open the production CLI cache or inherit legacy outbox mutations. The
  platform/local-root contract passes 25/25, and credentialed diagnostics
  delivered 5/5 and 25/25 rows while correctly retaining the strict latency
  failure (25-row p95 214.2 ms against the 100 ms target).

## August 2, 2026 at 8:06:12 PM EDT

- Repository: `instant-data-swift`
- Commit: `1ac73a1bce165920deb83f06c7d7070c652cacf2`
- High-level reason: Stop one unretryable legacy outbox row from taking down
  the whole live connection. Rows written before durable optimistic-overlay
  metadata carry the deploy-fixable "could not resolve" message, so the
  connect-time retry sweep selected them and threw `retainedUnknown`; the
  live-connect catch then closed the socket, stored an `errored` connection
  state and rethrew, repeating on every reconnect. That silenced queries, all
  later mutations, and the separate diagnostic-log client, presenting on the
  physical iPhone and iPad as an indefinite "Loading recordings…" with no
  error. The row is now retained and reported while the sweep continues.
  Tracked as issue #134 (P0).

## August 2, 2026 at 7:06:28 PM EDT

- Repository: `instant-data-swift`
- Commit: `460b7ca01e049dd45338a0a1766c90195655d33d`
- High-level reason: Restore the declared `.watchOS(.v8)` platform. The
  browser-OAuth and Apple ID authorizer guards relied on `canImport(UIKit)`,
  which is true on watchOS even though the platform has no
  `ASPresentationAnchor`, `UIApplication.connectedScenes`, or
  presentation-context protocols, so the module failed to compile with 13
  unavailability errors. Adding `!os(watchOS)` routes watchOS to the existing
  unsupported-platform branch. Found while building Scribe for the physical
  iPhone, whose iOS app embeds the `ScribeSharedWatch` companion. Published as
  tag `v1.2.1`; tag `v1.2.0` at `01ac62bd` does not compile for watchOS.

## August 2, 2026 at 6:39:23 PM EDT

- Repository: `instant-data-swift`
- Commit: `71ccbcf132508376adb0281fd100821e1ff6c12f`
- High-level reason: Match upstream exact-value retract semantics by
  reconciling a retained server-accepted write only when the prepared
  authoritative transition proves the exact EAV existed before and its
  cardinality-one key is absent afterward; base-absent and unrelated retracts
  remain fail-closed, with the complete 139-test gate green.

## August 2, 2026 at 6:29:55 PM EDT

- Repository: `instant-data-swift`
- Commit: `8d02a7a8d6b7000dea42be0b534e96761e3b1daf`
- High-level reason: Require explicit WebSocket or server-transport
  acknowledgement before resolving mutation delivery, atomically remove known
  optimistic effects on terminal rejection while rebuilding successors, and
  fail closed when authoritative refresh does not cover every materialized
  effect; the coupled 136-test gate and independent P0/P1/P2 review are green.

## August 2, 2026 at 6:11:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d15c3aa6b290bfc83955063fabf47c611032431b`
- High-level reason: Preserve the user's 17%-usage cutoff boundary with the
  exact three hash-anchored #117 acknowledgement P1 findings, protected typed
  log identity, ownership and re-review gate, plus #043's current read-only
  production title evidence (`178` to planned `179`) and continuation order.

## August 2, 2026 at 5:55:23 PM EDT

- Repository: `instant-data-swift`
- Commit: `95cc1f03cf533696ac3fb1ac86e7977c1f130f17`
- High-level reason: Preserve issue #043's exact 39/39 acknowledgement and
  rollback evidence while explicitly recording the four independent-review
  no-ship blockers, expanded ownership, and regression-to-ledger continuation
  boundary required before stabilizing the editable ABI for Scribe #059.

## August 2, 2026 at 5:44:35 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `fe43d27475b47664a6ae893bbd65a731fa903e76`
- High-level reason: Preserve a cutoff-safe cross-repository boundary naming
  the immutable Recipes presence commits and protected evidence for #127–#130,
  while recording #059's zero-completed-test SIGSEGV as unverified mixed-ABI
  evidence with the exact fresh-scratch continuation gate.

## August 2, 2026 at 5:41:40 PM EDT

- Repository: `instant-data-swift`
- Commit: `671e370509294195992f6482aced9b7b169c4bc1`
- High-level reason: Preserve topic event identity so repeated equal-payload
  Recipes reactions animate across devices, expose touch-device custom cursor
  feedback, and project Avatar Stack presence once per logical user, with 25/25
  focused wrapper and app regressions green for issues #127–#129.

## August 2, 2026 at 5:34:02 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `653fb7d02ce39c82ca7cadfb1e436e5ae6faa015`
- High-level reason: Integrate the proven shared AuthV3 account surface into
  iPhone/iPad Settings and Mac General Settings through one TCA route, with
  platform-owned Apple client names, shared Google/callback configuration,
  guest/canonical session projection, loud failure state, and 4/4 focused tests
  for issues #113 and #131.

## August 2, 2026 at 5:30:25 PM EDT

- Repository: `instant-data-swift`
- Commit: `5d506d7a393c0e340445190677c5f151b53b0791`
- High-level reason: Preserve a cutoff-safe, newest-first checkpoint for issue
  #043's explicit server-acceptance RED contract and issues #127–#130's
  upstream-backed topic, cursor, presence, and Merge Tiles diagnoses, including
  exact ownership, dirty-file boundaries, test evidence, and unfinished device
  acceptance.

## August 2, 2026 at 5:29:29 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `61dc6668920c611128e5acd3aed892e66c823252`
- High-level reason: Preserve a cutoff-safe recovery boundary with exact
  subagent ownership, physical Recipes Apple acceptance evidence, typed issue
  references, acknowledgement NO-SHIP findings, title/list/auth test state,
  concurrent dirty-file boundaries, and the clean landing/device order for
  issues #043, #059, #113, and #127–#131.

## August 2, 2026 at 4:29:34 PM EDT

- Repository: `instant-data-swift`
- Commit: `6408c8ec1982bda51442a6e517c4d900c7818734`
- High-level reason: Route app-owned Apple and Google provider metadata into
  the runnable Recipes auth surface, register its OAuth callback, enable the
  signed Apple capability on iOS and macOS, and protect the packaging contract
  with focused tests for issue #113.

## August 2, 2026 at 4:26:07 PM EDT

- Repository: `instant-data-swift`
- Commit: `ff736a0ae8c01b251d75507e8e9cbba5162d6fc1`
- High-level reason: Require canonical upstream Instant TypeScript behavior as
  the starting point for tricky synchronization, optimistic-state, rejection,
  reconnect, query, auth, and persistence edge cases; preserve its transition
  and test shape and document necessary Swift adaptations for issue #043.

## August 2, 2026 at 4:24:56 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `67e4c27fea7a5541ef21e7569bc96d84a5fa0091`
- High-level reason: Make canonical upstream Instant the required starting
  point for tricky synchronization, optimistic-state, rejection, reconnect,
  query, auth, and persistence behavior; preserve the upstream transition and
  document any necessary Swift/Scribe adaptation for issue #043.

## August 2, 2026 at 2:22:59 PM EDT

- Repository: `instant-data-swift`
- Commit: `f13ee441dabbcdf3144a0cd42dfa9f00c1ebdf37`
- High-level reason: Add callback-safe native Apple auth, state/PKCE browser
  OAuth for Google and other providers, and atomic exact-guest-token promotion
  with injectable client seams, truthful linked-existing-user outcomes, a
  polished sample surface, independent review, and 62 passing auth tests for
  Scribe issue #113.

## August 2, 2026 at 2:18:49 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3636f17c8954549e2762d8382186c25b68f2d7a6`
- High-level reason: Preserve physical-iPad proof that the Home Screen widget
  routes into recording but the enabled built-in microphone returns an exact
  all-zero WAV, while the local row/media survive behind 901 pending Instant
  mutations and disappear from the UI after relaunch despite zero remote rows
  for #023 and #026.

## August 2, 2026 at 1:59:36 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `adf30204cb36e0b73c60cf7b215994257bcc6fd0`
- High-level reason: Preserve physical-iPhone #044 evidence that audio had
  stopped before a stale pre-WebSocket Scribe process was normally terminated,
  record its continued Instant/diagnostics activity, and correctly rule the
  visible 27-hour Apple Clock stopwatch out of the Scribe thermal incident.

## August 2, 2026 at 1:47:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `03d95f864a74e959e8ef914e259dd9449dfa8556`
- High-level reason: Enable the signed Sign in with Apple capability across the
  iPhone/iPad host and both Mac packaging paths, with a focused regression that
  keeps the entitlement present while physical provisioning and account
  completion remain explicit unverified acceptance lanes for #113.

## August 2, 2026 at 1:14:58 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `9b22efe8ac1ff33b909a47bc137aa32c1c1184f8`
- High-level reason: Record the returned-device recovery boundary with immutable E2E and system-surface SHAs, exact auth-worker ownership, verified guest-promotion semantics, the Mac inline-response contract, the iPhone thermal lane, and the safe continuation order for #035, #044, #089, #099, #113, and #116.

## August 2, 2026 at 1:11:46 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `cd272b3ba21ffc3d88f8291cd190d56600eee1af`
- High-level reason: Keep iPhone/iPad widgets, Live Activities, deep links, and app-icon quick actions aligned with canonical recording state; coalesce rapid transcript reloads across both widget kinds; preserve paused state; and remove Start Recording while capture or playback is already active for #013, #105, #116, and #126.

## August 2, 2026 at 1:05:58 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `20e664c9f15073c59c348fbe05185ccc604b8a8f`
- High-level reason: Add a repository-owned bounded E2E JSONL observer skill, make Scribe-specific guidance qualify evidence while the generic typed tracker owns lifecycle mutations, and teach the two-commit ledger to link canonical issues #041 and #089 with focused tests.

## August 2, 2026 at 1:03:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `6fe4be91321e5598471932ac5b1387b9a3c196fb`
- High-level reason: Harden the simulator-only real-audio Instant matrix so nine independent Mac/iPhone/iPad writer-observer lanes require exact fixture PCM, deterministic transcript projection, materialized storage bytes, guest identity separation, publication-anchored latency, private issue-tagged local JSONL, bounded artifacts, and clean participant shutdown for #089 and #116.

## August 2, 2026 at 12:43:34 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `6b11ab6194560c5d1b61dbce47a4d3e965a7201d`
- High-level reason: Replace the synthetic Instant matrix with independent guest writer/observer participants that drive the shipping recorder from a checked-in real 48 kHz WAV, mock only transcription, require exact PCM and remote materialization, anchor latency to successful publication events, and emit dependency-injected bounded private device logs for #089 and #116.

## August 2, 2026 at 12:28:13 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1e3297dda65698f52e08a1c791cc1b256510fa9f`
- High-level reason: Add a disposable 128 KiB startup recording projection that renders cached and valid-empty libraries before canonical bootstrap, reconciles only paired fresh pages, isolates cache paths by database/persistence/account/E2E participant identity, and strictly bounds corrupt quarantine while retaining physical under-200 ms acceptance as an explicit open lane for #059.

## August 2, 2026 at 12:17:53 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `252af0be307c47734f702f72ef161d9b24ce853a`
- High-level reason: Preserve the connected physical iPhone's inspected widget and Live Activity screenshots as immutable before evidence for typed issues #013, #105, and #116, proving the observed active-recording versus idle-widget state mismatch without overstating tap-routing acceptance.

## August 2, 2026 at 11:45:25 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3e4d78a01e873f4001582a409adfa196b911bdd6`
- High-level reason: Preserve the green generic simulator build without overstating acceptance, record every independently reviewed E2E false-pass blocker, lock the physical-iPhone no-contact boundary, and select the bounded read-only launch-projection design and exact restart order before further implementation.

## August 2, 2026 at 11:28:59 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `4b2d08f29e3a1a41123f5a652e2e203d66a19a38`
- High-level reason: Persist immutable diagnostics and cold-load commits, exact test and performance evidence, memory and physical-acceptance boundaries, the disconnected-iPhone prohibition, remaining simulator E2E ownership, and the safe ordered continuation so limited premium-model access cannot strand the recovery state.

## August 2, 2026 at 11:27:29 AM EDT

- Repository: `instant-data-swift`
- Commit: `0f78572e02a17189409fc918b912188e9d50680a`
- High-level reason: Reduce eager SQLite state-load time with bounded 1 MiB/1,024-row JSON arrays and two decode slots, preserve exact ordering and outbox semantics, add loud row-range/path failures and per-collection tracing, and retain a release profiler plus explicit memory and physical-acceptance boundaries.

## August 2, 2026 at 11:26:44 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `de0ee7df1b6052e072ee208e76507dac6f3661ea`
- High-level reason: Replace the startup-blocking diagnostics Instant database with bounded crash-recoverable device JSONL, one process-long tailnet WebSocket, durable collector acknowledgements, protected-evidence retention, opt-out lifecycle enforcement, and a loopback-only launchd-supervised collector.

## August 2, 2026 at 10:59:06 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a3cb9f652865d18636bf7c2180e77e6226a91cb9`
- High-level reason: Persist the user's explicit no-access boundary for the disconnected iPhone, the simulator and physical-iPad continuation lanes, the committed audio-recovery evidence, and collision-free worker ownership so a restart cannot violate the device boundary or lose progress.

## August 2, 2026 at 10:57:23 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `38a822c3b81cc92f32f98a63bf31c9e9ae33f6fa`
- High-level reason: Recover the active microphone capture graph after input-hardware changes without changing recording identity, serialize teardown against recovery, and keep automatic audio-session reclaim alive in bounded retry windows when iOS omits the interruption-ended notification.

## August 2, 2026 at 10:34:43 AM EDT

- Repository: `instant-data-swift`
- Commit: `b92d5f0976e99bea2712973b5e1f5cfce48c9429`
- High-level reason: Standardize immutable, restartable progress checkpoints across the active library and Scribe repositories because ChatGPT and Sol Ultra access is limited.

## August 2, 2026 at 10:33:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `e5fd42b51712990b2c7faa08e22961e53db401b1`
- High-level reason: Preserve a restartable physical-recovery checkpoint with immutable commits, device evidence, worker ownership, simulator real-audio E2E acceptance criteria, and exact continuation steps because premium-model access is limited.

## August 2, 2026 at 10:26:35 AM EDT

- Repository: `instant-data-swift`
- Commit: `e87765b8cd8c5c2830494ee05c9686f7edb9f4d4`
- High-level reason: Prevent deep persisted outboxes from starving live queries by sending query registrations first, bounding unacknowledged transaction work by count and low-level step weight, and refilling only after acknowledgements with reentrancy-safe reservation cleanup.

## August 2, 2026 at 10:06:27 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `aa5229f13d6a2e2a7a985cc15c848cfb9e6e6c5a`
- High-level reason: Add typed, bounded Instant issue-file evidence handling with validation before upload, SHA-256 over the exact streamed bytes, atomic issue linking, orphan cleanup, relation materialization, and overwrite-safe downloads.

## August 1, 2026 at 11:54:55 PM EDT

- Repository: `instant-data-swift`
- Commit: `be978ea30743b1aa05f03dd2ceae4fdf1bf77bbd`
- High-level reason: Enforce UUID validation on INSTANT_APP_ID environment variable in AuthV3AppConfiguration to prevent non-UUID strings (like 'auth-v3-local') from reaching InstantDB server OAuth endpoints.

## August 1, 2026 at 11:45:40 PM EDT

- Repository: `instant-data-swift`
- Commit: `f8bf1938bfe43818e90632b719ee18e11a2f6460`
- High-level reason: Update default InstantDB app ID in AuthV3AppConfiguration from 'auth-v3-local' placeholder string to canonical UUID ('28c98cc4-e65b-41be-a5bc-204827f5d364').

## August 1, 2026 at 11:40:40 PM EDT

- Repository: `instant-data-swift`
- Commit: `4a5f309e088d22384a86acdf2cfecfef2ef3ecfa`
- High-level reason: Implement ASWebAuthenticationSession browser OAuth authorizer with automatic fallback for Apple Sign-In when running in development/un-entitled binary builds.

## August 1, 2026 at 11:18:00 PM EDT

- Repository: `instant-data-swift`
- Commit: `4048c2058d85ffd5214f1c456a1d727524065828`
- High-level reason: Implement native Apple Sign-In authorizer using AuthenticationServices ASAuthorizationController and update AuthV3App UI to display logged-in credentials and logout functionality.

## August 1, 2026 at 10:15:24 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `b4c2d04ec3e8c99db222249c871010a8d45a5d9a`
- High-level reason: Keep the recording audio session alive through system alerts and hardware-muted microphones — adds setPrefersNoInterruptionsFromSystemAlerts and .overrideMutedMicrophoneInterruption, retries setCategory without resilience options instead of failing the recording, and downgrades three previously fatal optional preferences to reported issues. Ledger entry added by the session that owned this repository, since the authoring agent was scoped out of it.

## August 1, 2026 at 10:07:28 PM EDT

- Repository: `instant-data-swift`
- Commit: `3f4e8926c6b7845ecb3f46a0ab7316328ba2a0e8`
- High-level reason: Add a package-benchmark suite (the tool TCA2 uses) measuring wall clock, CPU, malloc, peak resident memory, and throughput for local write, read, and cold store reopen — first run: write p50 28ms, query p50 41ms, reopen p50 117ms.

## August 1, 2026 at 10:07:28 PM EDT

- Repository: `instant-data-swift`
- Commit: `4fbc07fb6421b7591e3dea61bc409ad20b2aa299`
- High-level reason: Recover mutations quarantined by schema or permission drift by retrying deploy-fixable failures on a fresh session, so the 463 and 1 stranded field mutations can deliver once the deployment lands.

## August 1, 2026 at 9:38:07 PM EDT

- Repository: `instant-data-swift`
- Commit: `0d0fbc3d5acb3308fe6c652fe57904a6d080aa50`
- High-level reason: Stop a schema-drifted mutation from stalling the whole outbox — bounded flush batches, in-flight acknowledgement timeout, IssueReporting visibility for quarantines/deep backlog, and keeping a healthy connection open when recording a quarantine fails. Reconstructed from a Scribe device outbox holding 691 pending mutations.

## August 1, 2026 at 5:02:23 PM EDT

- Repository: `instant-data-swift`
- Commit: `5ae2f6b7d6f5c2904918544f7e1a578798163626`
- High-level reason: Add newest-first PROGRESS.md tracking library-side work driven by the Scribe production-readiness plan (seam defects under diagnosis, planned RecipesV3 latency/large-list validation recipes, dedicated E2E test database with Instant-room semaphore).

## August 1, 2026 at 5:02:23 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3bf8a8b915514937c812ea14244433baf6887d38`
- High-level reason: Author production-readiness master plan (docs/production-readiness-plan.md), newest-first PROGRESS.md, and getadb test-database provisioning documentation (.env.example placeholders, .gitignore coverage for .env.test).

## August 1, 2026 at 10:12:45 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ca1bb950b7f30440699d6d3385e7e51b811efb63`
- High-level reason: Quote node labels and link titles in README.md Mermaid diagram to prevent syntax rendering errors.

## August 1, 2026 at 10:02:20 AM EDT

- Repository: `instant-data-swift`
- Commit: `d86fe4a6c0b70c11c8b8573205c35ada954be8c3`
- High-level reason: Add root MIT LICENSE file.

## August 1, 2026 at 9:56:50 AM EDT

- Repository: `instant-data-swift`
- Commit: `2a50ed044f10d026e9374585d273ae1414cb6127`
- High-level reason: Update README with InstantDB open-source platform-agnostic sync details across TypeScript, React, React Native, Vue, Svelte, and Swift.

## August 1, 2026 at 9:54:30 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5c982a7c30ef891bba44f8896b59d403cad5774c`
- High-level reason: Audit repository secrets, extract environment variables template to .env.example, and author comprehensive README.

## August 1, 2026 at 9:52:35 AM EDT

- Repository: `instant-data-swift`
- Commit: `6ec3cb6ac70f135e9d8c68ceac7985795607b70d`
- High-level reason: Create Point-Free style README with comprehensive feature list,
  quick start guide, code comparisons, and pre-release disclaimer.


## August 1, 2026 at 1:14:47 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `68d5aad21486aa49fdde1c30f88e6d260b0268b2`
- High-level reason: Preserve sanitized physical-iPad evidence for Recordings
  175 and 176 with exact persisted counts, PCM duration and signal facts, build
  provenance, and hashes while explicitly leaving screenshot causation unproven.

## August 1, 2026 at 1:13:20 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f3f8f33e5516ce1e00ac55067f35e11d7ea47fa0`
- High-level reason: Add a dependency-controlled TCA health snapshot pipeline
  that reads Voice Memos and local Instant Swift Data metadata without mutation,
  establishes a start-now watermark, and persists only salted memo identities
  plus aggregate Scribe counts and deltas in a private host-local SQLite store.

## August 1, 2026 at 1:10:54 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `9185d36968a03af6f4e708787a6f4fedc78252bd`
- High-level reason: Add a serialized regression gate with a deterministic
  recording corpus, exact focused Instant Swift Data tests, stale-binary
  fingerprinting, strict sub-minute acceptance, and honest separation of
  credentialed, simulator, resource, and physical evidence lanes.

## August 1, 2026 at 1:10:31 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `64b845fab3685d26f0bf2481333701e9db12ee94`
- High-level reason: Preserve the latest persisted transcription word count in
  cold recording-list projections until real timeline sections hydrate, while
  keeping hydrated timeline words authoritative.

## July 31, 2026 at 3:37:08 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c109f7a369df5fffe75d76c1f8c3ffb202d06a53`
- High-level reason: Defer the restricted user-assigned device-name entitlement
  until Apple grants it for the iOS bundle, retain the exact restoration patch
  in an immutable named stash, and add a root index explaining the blocker,
  fallback behavior, and post-approval recovery steps.

## July 31, 2026 at 11:26:16 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `bb43a6bf833983e5cf14bc6baac21863aa74e443`
- High-level reason: Move recording-list loading, retry, cancellation, and
  pagination into a reducer-owned dependency lifecycle; preserve complete and
  pending local history across partial pages; expose typed failures; and keep
  one observation alive across shared multi-window presentation.

## July 31, 2026 at 11:06:03 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `2f340d1e23e34d89984cb84205fc594f8f5f01d1`
- High-level reason: Make remote-diagnostics opt-out invalidate queued events
  across blocked preparation and transient disable/reenable transitions, make
  disabled flush return without waiting for setup, and replace global
  quiescence waits with call-time enqueue completion fences.

## July 31, 2026 at 10:29:31 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `e31a56a7a20502c264db1ada0ef8ad8d5876f0ab`
- High-level reason: Make explicitly requested physical-device deployment fail
  closed when the target is absent or unready, add exact CoreDevice ID and name
  selection without fallback, and bind plan and result evidence to that same
  device identity.

## July 31, 2026 at 10:20:24 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ecbfe82e268be472669f5103bc95b808372245e3`
- High-level reason: Remove dedicated diagnostics-store preparation from the
  startup critical path, bound and preserve queued evidence, stop active-recording
  system-surface churn, keep system-audio transcription provider-neutral, and
  add ReplayKit source diagnostics that distinguish missing callbacks,
  conversion failures, and all-zero PCM.

## July 30, 2026 at 6:25:00 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `6fd3ad7cd7b0d78efc78669d18524854b72ace04`
- High-level reason: Use one automatic Apple Development signing identity for
  the iOS host, App Clip, widgets, broadcast extension, and Watch app so Xcode
  embedded-binary validation and physical-device deployment resolve the same
  certificate and team throughout the bundle.

## July 30, 2026 at 5:41:53 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `240019f98d9c62da359da9de6c1847238dea4458`
- High-level reason: Restore iPhone, watchOS, and unsupported-platform builds
  after the screen-recording permission dependency became required, while
  retaining macOS as the only live permission-request implementation.

## July 30, 2026 at 3:07:35 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `66a0f0926fd5607388c5d1b206846f86a51ae0c6`
- High-level reason: Bind Screen Recording recovery to Scribe's stable Apple
  Development identity, isolate ad-hoc QA builds, promote only verified signed
  bundles, and prevent stale ScreenCaptureKit failures from stopping a
  replacement capture session.

## July 30, 2026 at 3:02:21 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `77d93672443fabf32e1a8b01974e509a60ac8f4a`
- High-level reason: Restore the portable issue success-evidence vocabulary as
  the same explicit closed enum in Swift and TypeScript, rejecting arbitrary
  wire labels instead of silently accepting schema drift.

## July 30, 2026 at 1:56:32 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3ca298562069787aba201baffca5e3f5db36e58b`
- High-level reason: Bind the verified public clip duration into the exact
  publication approval fingerprint so duration drift always requires fresh
  approval.

## July 30, 2026 at 1:55:05 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `0d08577e7957ac517bc8e24c60eb30bc6cb3de2f`
- High-level reason: Publish only trusted recording-time word ranges behind
  random 256-bit capabilities, immutable atomic handoffs, non-enumerating
  recording-bound routes, and fail-closed X create/delete intent recovery.

## July 30, 2026 at 1:51:45 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `97e8309a0babab64c0a791a664c3eb20692f4047`
- High-level reason: Give Scribe a canonical Mac window, native tabbed
  Settings, shared command-aware state, and Recording, Search, Sidebar, and
  editing menu commands while moving build provenance out of the main chrome.

## July 30, 2026 at 1:49:46 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a60dc7aad79f4b89626c2b4b0559941454b833a1`
- High-level reason: Productionize recording interaction with one control bar,
  a live dependency-controlled full-screen clock, deterministic scroll follow,
  complete corpus copy, readable Mac sidebar, and fail-closed ReplayKit image
  provenance.

## July 30, 2026 at 1:48:35 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `920d11257e707bb43364affb6bb0f598d8ed5e59`
- High-level reason: Add a private, disabled-by-default image-analysis domain,
  Apple Foundation Models adapter, byte- and profile-bound idempotency, portable
  capture provenance, and fail-closed Instant schema permissions.

## July 30, 2026 at 1:46:31 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1a780aea3f172ff0cbac274d4f9e5a7595d7d9c4`
- High-level reason: Give playback and export one ordered mixed-corpus document
  that preserves full clipboard text and every media/context entry for native
  selection plus explicit all-platform copy.

## July 30, 2026 at 1:36:34 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3656460c82936d7a666b873695801b5e94357907`
- High-level reason: Preserve a privacy-reviewed, hash-addressed #044 evidence
  package for the observed Scribe process CPU and memory incident while
  excluding raw transcripts, logs, environments, heaps, and databases.

## July 30, 2026 at 1:29:46 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8ac599eb20648cce53a0b0efba557dc890283d3c`
- High-level reason: Bound remote diagnostic delivery to one 256-event drain,
  preserve error, critical, and issue-linked evidence under pressure, and stop
  producing Instant mutations when the remote outbox is already saturated.

## July 30, 2026 at 1:26:26 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `adb538ddb20f4404f9d30946c0ed78b10391a9c7`
- High-level reason: Make Mac ScreenStream grant refresh, local LiveKit host
  ownership, relay teardown, and app-group handoff generation-safe across
  expiry and cancellation, with typed errors, credential redaction, focused
  reducer coverage, and a real local publisher/subscriber room join.

## July 30, 2026 at 1:12:24 PM EDT

- Repository: `instant-data-swift`
- Commit: `ac6ee60fb2b0435578138a22e8fbc798224a2d9a`
- High-level reason: Materialize deterministic large store snapshots by walking
  the existing entity and attribute index order instead of flattening and
  globally stable-sorting every triple, with a 50,000-entity sparse regression
  test shaped like Scribe diagnostics.

## July 30, 2026 at 12:43:23 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `b7b30d033ed46f1900161e8360100d743761baae`
- High-level reason: Make Swift Issue success-evidence decoding preserve
  unfamiliar non-empty wire labels while retaining the current known values,
  so independent client schema evolution cannot make the entire issue catalog
  unreadable.

## July 30, 2026 at 12:10:27 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `427c2862827e0069e4b0cf743331d0c8cc7bb759`
- High-level reason: Keep the Swift Issue evidence wire values aligned with
  live Instant and Foldkit by adding Research and CodeReview, and preserve the
  user-supplied public IssueTrackerError screenshot as hashed issue evidence.

## July 30, 2026 at 11:48:54 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `6f4c3a02c4da184c0564eb0ba74dda2d97482f07`
- High-level reason: Make the protected typed append-log command the explicit
  repository agent boundary and align its documentation and tracker skill with
  the committed required, optional, and success fields.

## July 30, 2026 at 11:45:18 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f512057408573691526b57458069ee41e392cecc`
- High-level reason: Preserve a privacy-reviewed installed-app baseline of 12
  screenshots, their 12 direct ASCII renderings, and three safe accessibility
  trees before the canonical Mac and cross-platform visual refactor.

## July 30, 2026 at 11:42:45 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `152b0e75c1b1360cd5f25fc8c2b1624361e9b224`
- High-level reason: Document the committed typed append-log JSON contract and
  clarify that scribe-issue-tracker owns lifecycle while
  instantdb-log-observer owns structured evidence emission and observation.

## July 30, 2026 at 11:34:25 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `03aad74a1e319f86a2437594861a57cfc851219e`
- High-level reason: Add a committed typed CLI for atomic issue-tagged log
  emission, with Swift-compatible payloads, canonical `logID` lookup support,
  ergonomic diagnostic path relationships, and shared RFC UUID-v5 link IDs.

## July 30, 2026 at 11:24:26 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `16bba15c9ad0ed926750dbc67e3e809e82453d40`
- High-level reason: Replace invalid composite Instant issue-link entity IDs
  with cross-language RFC 4122 UUID-v5 identities derived from the URL
  namespace and canonical log namespace, log ID, and issue ID path.

## July 30, 2026 at 8:19:31 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8b02035d5b9d3f347ef3eb18d98fc4b354c7f334`
- High-level reason: Add a fail-closed standalone YouTube comment plugin with
  exact microphone grammar, explicit final confirmation, bounded unique
  transcript/audio provenance matching, scoped Google OAuth identity
  verification, and durable exactly-once publication receipts and audit.

## July 30, 2026 at 7:45:33 AM EDT

- Repository: `foldkit`
- Commit: `aa2417af07b6da5ec921cb3115b0569b2fc8e053`
- High-level reason: Correct Foldkit skill drift around Disclosure and scoped
  Effect Layers, and add a focused regression proving one Program can run as
  isolated simultaneous runtimes with independent state, evidence, Ports,
  resources, and shutdown.

## July 30, 2026 at 7:44:40 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ae4f941823a8e78a0d8ab8643458a1b42035dc81`
- High-level reason: Add default-on Apple performance diagnostics using
  MetricKit on macOS and iOS/iPadOS, with a bounded process-memory fallback on
  watchOS and privacy-filtered remote summaries.

## July 30, 2026 at 7:39:11 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `cfd923ad28421b623fc27160201f8d3a8fe7f280`
- High-level reason: Add discoverable Codex interface metadata for the typed
  realtime Scribe issue-tracker skill, validated by the official skill checker
  and a strict zero-finding skill audit.

## July 30, 2026 at 7:34:56 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `7c354c67d75845780adc53c3b4600c1e40cc3de9`
- High-level reason: Prevent the generated Instant Issue `status` attribute
  path from being shadowed by a loop binding, eliminating the reproducible
  arm64 SIGBUS in filtered issue queries while preserving bounded server filters.

## July 30, 2026 at 7:34:02 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f9d93a6751f9522f19c2b51ca8f4281781e5be15`
- High-level reason: Add participant-attributed SharePlay transcription with
  mandatory confirmed alphanumeric display names, Apple message-source identity
  binding, bounded reliable replay, spoof-resistant contribution IDs, validated
  party timelines, and persistence through Scribe's existing recording path.

## July 30, 2026 at 7:29:28 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d70af8e8a56ac08c438fd48aec163c8392867fe3`
- High-level reason: Keep Apple speech and on-device language-model work on
  Scribe's standard local-first Instant room path so transcript and agent turns
  remain visible without internet while auth, sync, and enabled diagnostics
  continue retrying and catch up when connectivity returns.

## July 30, 2026 at 7:28:45 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `dd251fb15bdd588f9df862117523828a2bba52a2`
- High-level reason: Complete the typed realtime Instant issue cutover after
  exact reconciliation of all 45 legacy source documents, remove the Markdown
  catalog/import target, and route agent guidance, feedback intake, persistent
  corrections/preferences, log tagging, and source-path hypotheses through the CLI.

## July 30, 2026 at 7:25:32 AM EDT

- Repository: `foldkit`
- Commit: `5108dd1453fa99a446a3c9ef712b7528f6ec05db`
- High-level reason: Align Foldkit's portable issue and logging domains with the
  typed Instant tracker, infer issue tags at append time, persist server-queryable
  evidence links and path relationships, and render the selected issue's latest
  evidence through the same Program across the web runtime.

## July 30, 2026 at 7:21:13 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `54a0aa9613004a4141c850a2d20761ab504fc233`
- High-level reason: Add a typed YouTube comment plugin tool target and
  room-scoped stable tool identifiers while preserving global identifiers and
  shared recording-tool defaults, with focused contract tests.

## July 30, 2026 at 7:16:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d5cb4fd1321c4305551f5f4c6b78b72e4f884863`
- High-level reason: Add the guarded 2:17 a.m. macOS nightly bonsai runner,
  five-million-token goal, recent recording/log-aware bounded issue ranking,
  independent QA and Mac screenshot requirements, and brief measured-usage
  reporting.

## July 30, 2026 at 7:05:52 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `61c54fc52f6a558c476cdfbba0ced72f24375a09`
- High-level reason: Preserve a first-class `Planned` workflow state across the
  Swift issue model and typed Node CLI so structured library feature intake is
  not flattened during realtime Instant upsert.

## July 30, 2026 at 7:02:23 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `4707a45f7be4559a2f050966a78998fa8798b154`
- High-level reason: Add the typed realtime Instant issue/guidance schema and
  structured JSON CLI with deterministic Swift/Node identities, merge-safe
  updates, evidence queries, public-read/admin-write permissions, and no
  Markdown parsing path.

## July 30, 2026 at 7:01:57 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `572373b8c54913322bd6dd0334eab206793d6889`
- High-level reason: Make structured logs tag issue mentions immediately,
  retain suspected/contributing/ruled-out source paths, and persist direct
  evidence links to the lightweight Instant issue viewer with legacy-read
  compatibility.

## July 30, 2026 at 6:59:48 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `55556b7045b4b278c044ca20ef3d316e63bf0827`
- High-level reason: Build recording-scoped Instant listener rooms, a
  standalone Mac stream-agent CLI, hidden passive responses, allow-listed TCA
  actions, explicit Apple system TTS, and a fully local Apple SpeechAnalyzer
  and Foundation Models intelligence mode.

## July 30, 2026 at 6:13:15 AM EDT

- Repository: `foldkit`
- Commit: `80c1969ade21ff69dc15fde3e43988f4c9f63ee1`
- High-level reason: Add and package a Foldkit-native companion skill family
  for composable architecture, Schema modeling, Effect dependencies, shared
  state, navigation, testing, views, and portable client hosts without
  importing the separate ts-pfw runtime contract.

## July 30, 2026 at 2:36:38 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3a2790751a38044636d79d0566b31ea0b0616cc5`
- High-level reason: Verify issue 001 with immutable before-and-after
  transcriber-selection evidence, independent QA, and a synchronized active
  issue queue.

## July 30, 2026 at 2:28:47 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f1064d4d27eeaa4e968b7f626fd12e464cd38e96`
- High-level reason: Freeze the selected transcriber identity at recording
  start so an unavailable Apple session cannot be mislabeled as Deepgram.

## July 30, 2026 at 2:15:55 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `4f4b9070c790d86eebd5813394ed6428628f8263`
- High-level reason: Restore the iPhone and iPad transcriber Settings gear by
  moving it into the recording sidebar's rendered navigation toolbar while
  preserving root ownership of selection and the Settings sheet.

## July 30, 2026 at 2:05:07 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c01d263bdadacc457494bc115a8493aa1362d895`
- High-level reason: Claim issue 001 for current provider-selector verification,
  adopt the canonical success-criteria heading, and repair its malformed link
  to the original selector implementation commit.

## July 30, 2026 at 1:22:59 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c3300c2cd44d54ae5d891aca62d3042dda5d1725`
- High-level reason: Install the supplied Scribe artwork as the shared app icon
  for iPhone, iPad, App Clip, Mac, Apple Watch, Apple Vision Pro, and Apple TV,
  with platform-specific asset catalog variants validated by Apple's compiler.

## July 30, 2026 at 1:21:52 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8b051d215230f8ba57ef8ade745e89f754af6955`
- High-level reason: Add portable and Markdown workflow states that distinguish
  partial implementation, missing verification, concrete feedback requests,
  fixes, and regressions; migrate issue 040 to `verification-needed` without
  discarding its completed implementation and passing criteria.

## July 30, 2026 at 12:15:20 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d2221439ef8220aa8c62acd96c239742bf7c99ca`
- High-level reason: Record the independent issue-040 QA verdict and return the
  P0 to open and unclaimed until non-manual literal press-and-hold evidence and
  fresh physical-iPad evidence exist for both new-window entry points.

## July 30, 2026 at 12:14:08 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d3ecabf26014e404196ca67f94f48f03d6b5f597`
- High-level reason: Add an accessible recording-window action and preserve
  Computer Use iPad simulator evidence proving route hydration and three
  concurrent Scribe scenes, while recording the literal long-press gesture and
  fresh physical-iPad verification as still outstanding.

## July 30, 2026 at 12:02:05 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c2d1c2737f9e65a71044deb6162d37f91e54f3f5`
- High-level reason: Add typed issue success criteria to the dependency-light
  Swift schema, align their encoded shape and legacy default with Foldkit, and
  prove lossless Instant payload persistence with focused tests.

## July 30, 2026 at 12:01:59 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1f1351782e247059a82f5e10a1148ad4dfe107ca`
- High-level reason: Limit default-on process-memory sampling to the requested
  initial iOS, iPadOS, and macOS platform set so shared Watch and visionOS hosts
  do not start performance instrumentation.

## July 29, 2026 at 11:58:01 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d08edbf96b717fa6350d28972f55908539de249c`
- High-level reason: Make process-memory diagnostics default-on with a one-time
  settings migration, then move collection and dedicated-store logging into a
  once-per-minute background single-flight path with focused self-overhead,
  main-thread, persistence, and collection-cost tests.

## July 29, 2026 at 11:50:27 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `caaee133d7a340f6a9327d78e78e41a5fa08bc29`
- High-level reason: Make Scribe complaint intake explicitly event-driven,
  require measurable success criteria and independent before/after QA, and
  return issue 042 to the open queue when physical behavior proof remains
  inconclusive.

## July 29, 2026 at 11:36:32 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `171661d329da41681112b57ca7ac4398c902460d`
- High-level reason: Add a default-off, device-local process-memory diagnostics
  setting, a dependency-controlled Darwin sampler, privacy-filtered active-scene
  logging, and focused settings and sampling tests so long-recording performance
  reports can be correlated with stable memory evidence.

## July 29, 2026 at 11:20:34 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f2509f88f2fdf6fdb7854384aaa82c0039c2b6d2`
- High-level reason: Enable the iOS multi-scene capability required for the
  existing identity-keyed SwiftUI recording-chat window actions to create real
  iPadOS windows, with a focused manifest regression test.

## July 29, 2026 at 11:18:05 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `eb075a69189184d7c6da037ff7b8468274f177ef`
- High-level reason: Preserve current-commit portrait and landscape,
  normal and full-screen visual evidence that the one-line transcript now
  starts at the top reading position, while retaining the physical iPhone
  interaction gap in the active issue.

## July 29, 2026 at 11:15:36 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `013238b344e54bec831b056986a4dc501ed8bfed`
- High-level reason: Preserve current clean physical deployment evidence for
  the active transcript-offset issue and attach a hashed iPad reproduction of
  repeated `Recording 001` titles without claiming unverified physical layout
  behavior or closing the recording-identity defect.

## July 29, 2026 at 11:14:35 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5b46d0bdeb4dc2f1847af5dd0cf84569a9c47b3a`
- High-level reason: Replace the lossy Mac bootstrap notification race with a
  latched default-store installation rendezvous so the resident screen-stream
  listener starts whether InstantDB becomes ready before or after AppKit launch.

## July 29, 2026 at 11:02:46 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8ee3ed92ccebbea1b07c4f194c8ec5bcc3569024`
- High-level reason: Extract the portable Swift issue and attachment wire
  contract into a dependency-light SPM leaf module, keep issue behavior and
  InstantDB transport in separate dependent targets, align the TypeScript
  Effect schema, and make complaint screenshots durable issue attachments.

## July 29, 2026 at 11:02:45 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3c3d07b99ac040b737a6d534dba90017d8ccd999`
- High-level reason: Give normal and full-screen short transcripts one shared
  top-leading layout policy so the first transcript row no longer sits near
  the bottom of an otherwise empty viewport.

## July 29, 2026 at 10:51:15 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `acf7d780016f85dc1e149d6a7d88422498ab1c02`
- High-level reason: Keep the Mac InstantDB screen-stream listener alive after
  its windows close, start LiveKit with the Mac's Tailscale address advertised
  to WebRTC peers, deliver room-scoped credentials without manual entry, and
  make an already-open receiver react to newly prepared sessions.

## July 29, 2026 at 8:39:45 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `0763612e9eeede65118f0d52c2cc81b8c535dd7b`
- High-level reason: Add transport-independent Swift logging and issue domains,
  TCA dependency control, separate Instant adapters, lossless Markdown import,
  recurrence-based priority escalation, and explicit intake for the remaining
  transcript-offset, recording-title, and Settings requests.

## July 29, 2026 at 8:38:15 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `80f36d99bed857b83cef1e8fb9b9c82d4e6032c1`
- High-level reason: Keep portrait and landscape full-screen transcripts
  visible and wrapping beside a full local millisecond timestamp gutter, and
  close the thumbnail file-arrival lost-wakeup window that could defer a
  screenshot until later transcript activity.

## July 29, 2026 at 7:02:13 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `315e1a25b8570d19af87a003628f4193336e6568`
- High-level reason: Replace the forgotten-password custom build keychain with
  one-time command-line signing permissions on the existing login-keychain
  Apple Development keys, without storing a second password.

## July 29, 2026 at 6:45:59 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8b7f8a29e0887b011dbbf752383608283204f791`
- High-level reason: Make physical-device signing repeatable without Xcode by
  securely bootstrapping the isolated ScribeBuild keychain once, unlocking it
  from an encrypted login-Keychain credential, and selecting it explicitly for
  every deployment build.

## July 29, 2026 at 6:34:02 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3d8f9ad18965c5e8fe28c0e96417da4d14fc7756`
- High-level reason: Keep the shared passive-watcher controls buildable on
  watchOS with typed Picker bindings while preserving the existing Menu and
  rounded text-field presentation on supported platforms.

## July 29, 2026 at 6:30:20 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `37400396e68d6222e5b5fa241275a7662bef489d`
- High-level reason: Add accessible recording-bar and historical-chat actions
  that open recording-identity-keyed windows on iPadOS, macOS, and visionOS,
  backed by shared TCA state and focused platform-routing tests.

## July 29, 2026 at 6:15:36 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `df9e06ed78e5fdb0aa2d049cc5d95d839a086f6b`
- High-level reason: Enable installed Scribe builds to send privacy-filtered
  diagnostics to the dedicated Instant app by default, with a durable
  device-local Settings opt-out and live delivery gating. The shared-index
  commit also links the concurrent issue 035 watcher work.

## July 29, 2026 at 6:13:56 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a9ce1d8b6148c592c78028312fc879e9b1a5fb91`
- High-level reason: Add the smallest recording-scoped passive watcher with
  visible agent presence, persisted GPT target settings, stable transcript
  threads, terse offline responses, lifecycle controls, and focused tests.

## July 29, 2026 at 6:11:57 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `458e5154be773c1d411f60c88f219642b3274d58`
- High-level reason: Create and immediately claim issue 040 as P0 before
  implementation, with an identity-keyed recording-chat multiwindow contract
  for iPadOS, macOS, and visionOS.

## July 29, 2026 at 6:10:43 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5d4a9b36e63d47b19b7013b4c85973ec7f0f8037`
- High-level reason: Correct the public-sharing LaunchAgent to the installed
  Node path proven by a live loopback and Cloudflare-hosted health check.

## July 29, 2026 at 6:10:36 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5d38fbddb474e75960352a2e483c8134618e2097`
- High-level reason: Consolidate build provenance and speech-provider controls
  into Settings and adapt the recording surface for wide iPad layouts with
  focused presentation and layout tests.

## July 29, 2026 at 6:08:52 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `e1c086c350dcb58a88728c449fc219ed81a9bc46`
- High-level reason: Add a local-first public segment and X publishing
  prototype with bounded audio export, explicit approval gates, PKCE Keychain
  authorization, unenumerable serving, recoverable revocation, and focused
  dry-run and duplicate-suppression tests.

## July 29, 2026 at 6:03:23 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `65b4a43e2575529df1ee1dc8dd47c897b0150b6a`
- High-level reason: Require canonical agent claimants in issue metadata,
  append-only claim history, and atomic claim-before-implementation workflow.

## July 29, 2026 at 6:02:57 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a205bd1f54f9e76098256a05c2173b3d32d63c70`
- High-level reason: Capture the reproduced incremental-copy failure and a
  bounded ChatGPT audio-handoff investigation, specify the full local
  millisecond gutter contract, and make foreground-independent hands-free
  watching explicit without displacing higher-priority capture work.

## July 29, 2026 at 5:56:45 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ffb4153c0f09bcfbddcf9937c600e2d18f0ed66c`
- High-level reason: Clarify immediate screenshot visibility, scroll-to-bottom,
  full-screen iPhone text overflow, and SyncUps branch-discovery requirements;
  prove that the installed physical-iPad app generated local logs while its
  environment-gated remote destination remained unconfigured; and track that
  observability defect as a P1 prerequisite.

## July 29, 2026 at 5:54:36 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `59a33eada1012e6cd3dd779b30b1e8a91b6e6c90`
- High-level reason: Correct the screenshot symptom to measurable
  capture-to-chat visibility latency, preserve Settings and iPad layout as
  active requests, and separate the first passive room/thread watcher
  prototype from deferred public audio-segment publishing.

## July 29, 2026 at 5:50:55 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `35a70e904af6116eed562f14849103e4efe29131`
- High-level reason: Fetch and inspect the physical-iPad feedback screenshots;
  preserve the stale remote-log boundary; split screenshot latency, in-app
  ReplayKit access, Settings consolidation, and SyncUps toolbar reuse into
  prioritized backlog items; and update recurring layout issues without
  displacing capture, continuity, and identity priorities.

## July 29, 2026 at 5:50:21 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `598ad5f4a55fe364a023472b45f33d38f95425dc`
- High-level reason: Record clean physical-iPad build, install, launch, process,
  provider, transcript, and plugged-in microphone evidence; preserve
  interaction-dependent acceptance gaps; and track the newly observed unused
  iPad display area without assuming its windowing cause.

## July 29, 2026 at 5:41:07 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `028b55c651dd102d01fc5bf260b6077f41ba8d4d`
- High-level reason: Tie prioritized local issues to their immutable
  addressing commits, update exact status timestamps and evidence-backed
  acceptance, and preserve the remaining physical-device and speech-reconnect
  boundaries.

## July 29, 2026 at 5:39:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `00cb4a3a7422f5978d106fbc29aa2b4c5692e199`
- High-level reason: Catch up active recording duration from wall time after
  scheduler suspension, preserve hidden active-recording routing through
  compact navigation, and cover the surrounding timer and health behavior
  without claiming speech transport reconnection.

## July 29, 2026 at 5:39:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `4ea4e28c832f95aa64c73ae33fab83b8f713bd0e`
- High-level reason: Expose privacy-safe account, device, and authoritative
  recording identity on iPhone and iPad while keeping raw identifiers, email,
  recording titles, and tokens out of diagnostic metadata.

## July 29, 2026 at 5:23:20 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `2bfdf7603881be0ff630372082162992331e2fe7`
- High-level reason: Bound automatic physical-device-to-Mac screen-stream
  requests, Mac claims, and LiveKit preparation with typed recovery, stale
  attempt cleanup, sanitized diagnostics, 21 focused tests, and a real
  Mac-local publisher/subscriber token join.

## July 29, 2026 at 5:23:20 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `b36c8b8fee2ec3362363561065ce66615ac0f34d`
- High-level reason: Expose the next or active recording provider on iPhone and
  iPad, permit device-local selection before recording, explain active-session
  locking, and keep the compact picker explicit and accessible.

## July 29, 2026 at 5:19:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d33e1c00d0a9afe66743317eb7ceea4ba3be9aa2`
- High-level reason: Detect two seconds of exact-zero physical-device
  microphone PCM before any real signal, preserve active route evidence, stop
  the false live pipeline, and present an actionable retry with focused
  teardown and diagnostic coverage.

## July 29, 2026 at 5:19:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `9ceb673ca9e933affc9c21a6a94709a81a0edfd5`
- High-level reason: Version the reusable Scribe feedback-intake skill with
  physical-device recording/media retrieval, non-overwrite defaults, fresh-log
  chronology, parser tests, prioritized issue intake, and immutable
  addressing/fixing commit links.

## July 29, 2026 at 5:19:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `dab216bbf646355db4fea33d8e3f0a11c80aaa97`
- High-level reason: Rank the physical-device backlog, add exact issue
  timestamps and P0-P4 priorities, preserve the all-zero iPad evidence and
  lower-priority map direction, and require commit-linked work logs.

## July 29, 2026 at 4:55:56 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a37c740ee45d9067b64dbddbec0a798a216d2db3`
- High-level reason: Separate 25 physical-device feedback items into
  independently actionable local issues with transcript evidence, acceptance
  criteria, cross-links, an indexed lifecycle, and confirmed-working
  observations preserved as constraints.

## July 29, 2026 at 2:43:34 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `b333e6d37d071ad5f9ff0d37d5e26e648f456cab`
- High-level reason: Generate destination-aware iOS, Watch, and Apple TV
  schemes from the tracked XcodeGen source of truth, match the App Clip to its
  iPhone-and-iPad container, and make stable deployment regenerate the ignored
  Xcode project before building.

## July 29, 2026 at 2:13:57 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `54a596c0e3177985f35bbdd69367c41793d341b5`
- High-level reason: Restore repository-owned, destination-aware shared Xcode
  schemes for the iOS, Watch, and Apple TV products and return the stable
  installer to scheme builds with isolated derived data and regression
  coverage for each scheme's target identity.

## July 29, 2026 at 2:01:41 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `0945c66a7d841bcc3f8d29ae438e6a6be661d0cc`
- High-level reason: Keep direct iOS and Watch target builds isolated with
  target-compatible product and intermediate roots while retaining
  derived-data isolation for the Apple TV shared scheme.

## July 29, 2026 at 1:56:40 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a1ffc654b500a2fe2253401deaa8ebbfdcf13ee2`
- High-level reason: Build the iOS and Watch deployment products through their
  concrete Xcode targets while retaining the verified shared scheme for Apple
  TV, with regression coverage for the target-versus-scheme contract.

## July 29, 2026 at 1:42:48 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `02677bb3328cc7813c28bec07bd875b932f847d5`
- High-level reason: Pin stable Scribe builds to exact published
  `instant-data-swift` and Point-Free `swift-sharing` releases, preserve a
  no-worktree editable-package workflow, and embed and verify dependency
  revisions alongside the Scribe commit.

## July 29, 2026 at 1:30:07 PM EDT

- Repository: `instant-data-swift`
- Commit: `2b2517e256351f7e82286424aa83b4055b7e174c`
- High-level reason: Make the published SwiftPM package self-contained by
  removing reference-only Git submodules, preserving their optional local
  checkout pins in documentation, and adding a publication-surface check.

## July 29, 2026 at 1:20:15 PM EDT

- Repository: `instant-data-swift`
- Commit: `0584ffb6c1488461e5d52081f5c88412e4cb82d5`
- High-level reason: Reconcile every current Instant and cross-repository SHA
  reference with the verified technoplato identity-rewrite maps while
  preserving external revisions and non-reference content.

## July 29, 2026 at 1:19:23 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5709f8b367d6496a69c35bab67b68165e1e82db8`
- High-level reason: Reconcile every current Scribe SHA reference with the
  verified technoplato identity-rewrite map while preserving external hashes
  and non-reference content.

## July 29, 2026 at 10:39:55 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3d4d539ac3f684f3f0a44881e426eb3a2232572f`
- High-level reason: Clean SwiftPM outputs before generating Mac build
  provenance so the installed app compiles the current clean commit and build
  timestamp instead of reusing a stale generated build-info object.

## July 29, 2026 at 10:36:56 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `32d79ef6c36ae62c2717ef919048e44f1839ebff`
- High-level reason: Apply the bundle-relative framework runtime path to the
  installed Mac executable rather than the already-copied SwiftPM build
  product, with a focused installer-wiring regression check.

## July 29, 2026 at 10:35:32 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `52e9c3735efae986eb72c18a942c16540d95de0f`
- High-level reason: Add the bundle-relative framework runtime search path to
  the installed macOS executable so dyld can load the packaged LiveKit
  frameworks before Scribe startup.

## July 29, 2026 at 10:33:08 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `01adc38e97710b592b4b49108abf1cdf7600d151`
- High-level reason: Package top-level SwiftPM runtime frameworks in the
  installed macOS wrapper so the LiveKit-enabled Scribe host can launch instead
  of aborting in dyld before startup.

## July 29, 2026 at 10:08:43 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `2b43cce1457381385ec0d4f184b63eb70f8f7418`
- High-level reason: Make selective clean deployment reliable for unblocked
  targets, recognize provenance in Xcode Debug dylibs, and restore the shared
  recording and screen-stream settings views to a successful tvOS build.

## July 29, 2026 at 9:47:46 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c5616c4fab6c94cea8c9b9976b0029161f7d9673`
- High-level reason: Build, verify, install, and launch one clean Scribe commit
  across the Mac and every discoverable iPhone, Apple Watch, iPad, and Apple TV,
  with explicit simulator fallbacks and per-target deployment results.

## July 28, 2026 at 10:27:21 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1a5b6aa5305e204bfb11938b1a3ef6022cf59448`
- High-level reason: Run the InstantDB screen-stream watcher and automatic
  LiveKit receiver window in the stable signed Finder-installed Mac app while
  preserving its existing bundle identity and Keychain continuity.

## July 28, 2026 at 10:24:00 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8fa185553320b4f184ce3add50d320e29cf513ae`
- High-level reason: Automate phone-requested screen streams through an
  InstantDB control plane, Mac-hosted LiveKit room-scoped credentials, and a
  guarded OBS-to-unlisted-YouTube relay with automatic receiver setup.

## July 28, 2026 at 9:23:31 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `2e81885ca2959f96f72a10edda057a9e37e28c38`
- High-level reason: Keep live-screen stream configuration reachable from the
  active recording menu so the publisher endpoint and token can be set before
  starting the ReplayKit broadcast.

## July 28, 2026 at 9:11:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c409dec45ced0cc878120e7dc2b496132d76c31c`
- High-level reason: Stream ReplayKit screen video and app audio from iPhone
  through LiveKit WebRTC to a dedicated Mac receiver while preserving the
  existing transcription and periodic screen-image handoff paths.

## July 28, 2026 at 8:28:02 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `01b725112d94f44f2ddc60d7a185e6b46f73e796`
- High-level reason: Keep the live bottom margin proportional in extremely
  short landscape transcript viewports instead of allowing its minimum clamp
  to push all current text off screen.

## July 28, 2026 at 8:24:11 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `7449acde8cd8f51ab3985654483d1940740e68bd`
- High-level reason: Re-anchor a following live transcript after viewport-size
  changes so rotation and window resizing keep the newest line on its lower
  reading line.

## July 28, 2026 at 8:13:24 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `fd761a5d44418089fe9f4b31ea85e947cc697055`
- High-level reason: Give short live transcripts a viewport-aware minimum
  content height so the newest line reaches the same lower-screen reading
  position as long scrolling transcripts.

## July 28, 2026 at 8:10:49 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `7257748cb1d57a6bf44f24e00de9c7217ab0073b`
- High-level reason: Show a satellite uplink icon on the recording page's
  native ReplayKit broadcast launcher while keeping periodic screen-frame
  attachments as a separate opt-in control.

## July 28, 2026 at 8:00:43 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `beef03a956d52b659510323ed1e24c05cc051f75`
- High-level reason: Add bounded transcript voice commands and a bottom-pinned
  full-screen reader, disable all automatic heart-rate workout consumption,
  document the guest App Clip path, and expose the supported CarPlay surfaces.

## July 27, 2026 at 8:49:00 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8459e4953799876dd978c41bdf32a929ee54e058`
- High-level reason: Add a minimal recording App Clip that creates or reuses an
  Instant guest session, uploads a finalized M4A, waits for server
  acknowledgement before showing Saved, and preserves failed drafts for retry.

## July 27, 2026 at 7:20:14 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ff00831ceb314e58d48aa7652ec3295bbb334807`
- High-level reason: Remove the redundant speech-provider icon from the Home
  recording control and constrain the live transcript to a vertical,
  viewport-width scroll surface so horizontal swipes cannot shift the text.

## July 27, 2026 at 6:24:23 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `9fd2a6373354ff252b1bea19fce35b2bf1b7f19f`
- High-level reason: Add runtime-selectable Apple Speech Analyzer transcription
  with on-device model preparation, time-indexed progressive results, explicit
  finalization, visible device-local provider controls, and an immutable
  Deepgram-or-Apple choice for each active microphone and system-audio session.

## July 27, 2026 at 4:20:15 PM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commit: `2fea96e53b5981071dc9761ed10b7d0a8a9497f5`
- High-level reason: Keep live Watch heart-rate samples associated with the
  requesting iPhone recording, bound the relay, replace indefinite waiting
  with an actionable timeout, and expose the full recovery message.

## July 27, 2026 at 4:06:21 PM EDT

- Repository: `instant-data-swift`
- Commit: `598ec0b2459e83aef66d13ad3480410f51c29f52`
- High-level reason: Remove repeated full-snapshot sorting from optimistic
  live-data rebases after physical iPhone and Apple Watch CPU reports
  identified it as the shared recording-freeze hot path.

## July 27, 2026 at 2:14:01 PM EDT

- Repository: `instant-data-swift`
- Commit: `4f077bc71c4e81a73850cb866f5b17619b430c90`
- High-level reason: Preserve the repeated clean current-head signing result,
  ready Watch state, and protected-log freshness boundary without presenting
  compilation as installation or runtime acceptance.

## July 27, 2026 at 2:00:16 PM EDT

- Repository: `instant-data-swift`
- Commit: `10ad6819c0d8cf321c80e8289f32ed27f9111ef0`
- High-level reason: Reconcile the cross-repository audit with the final
  server-acknowledged delivery fix, full suites, clean six-lane performance
  evidence, and the exact unsigned-versus-signed physical Watch boundary.

## July 27, 2026 at 1:55:54 PM EDT

- Repository: `instant-data-swift`
- Commit: `981427972ac338838f08706ed161eb855ac8016d`
- High-level reason: Availability-gate the Duration-based live delivery waiter
  so InstantSwiftData continues compiling for its iOS 15 and watchOS 8 package
  deployment targets while newer Scribe targets use the explicit server-ack
  boundary.

## July 27, 2026 at 1:43:44 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `864f541483087f65af50a45d27c9872f49ec4a9a`
- High-level reason: Make explicit logger and replay durability boundaries wait
  for actual Instant server acknowledgement instead of invoking a local
  mutation transport that could remove outbox work before remote observation.

## July 27, 2026 at 1:42:48 PM EDT

- Repository: `instant-data-swift`
- Commit: `27b65349097e233b434100654693ccb543d34e93`
- High-level reason: Wait for actual live server acknowledgement without
  locally confirming the durable outbox, and preserve causally required older
  scalar writes during ordered replay while continuing to filter isolated
  stale retries.

## July 27, 2026 at 1:20:59 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `db7f808e143623b7407bec20ed7682104b2b5f4f`
- High-level reason: Carry Deepgram finalization acknowledgements through the
  transcript stream and hold stop persistence behind a reducer-owned,
  five-second-bounded provider acknowledgement so the final transcript cannot
  be discarded by the former fixed 500 ms delay.

## July 27, 2026 at 1:05:33 PM EDT

- Repository: `instant-data-swift`
- Commit: `36e871c147e4040f105de408e66c6a2e81baea95`
- High-level reason: Reject stale live-refresh writes atomically, preserve
  migration and relaunch ownership boundaries, normalize duplicate canonical
  query computations with final-result-wins semantics, and serialize live
  registration with durable pruning.

## July 27, 2026 at 1:02:29 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `94cfd243650ed34c27104e0c5f97ad9c7ee91a92`
- High-level reason: Keep the live Apple Watch BPM and exact failure reason
  visible outside the compressed iPhone recording toolbar, and let the active
  recording retry the dependency-controlled heart-rate session without showing
  a stale sample.

## July 27, 2026 at 12:55:33 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `634240a53a142283069899f24cffa4fad1d2cb4c`
- High-level reason: Bound diagnostic action-key extraction to known TCA enum
  wrappers so payload cases cannot replace the real leaf action or trigger an
  unbounded CustomDump traversal; refresh the committed heart-rate snapshot and
  restore the 466-test Scribe suite.

## July 27, 2026 at 12:39:15 PM EDT

- Repository: `instant-data-swift`
- Commit: `6386abc892aa0ef8516b9dd283efb59c57200a26`
- High-level reason: Apply Reactor-aligned age, entry, and owned-triple bounds
  to durable live query results; preserve active and optimistic owners; and
  transactionally collect only global triples whose final semantic owner is
  gone.

## July 27, 2026 at 12:28:17 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8c397aa1d8b34f1d1aa8880b48b2d579e82390c4`
- High-level reason: Model simulator heart-rate streams behind the Point-Free
  dependency boundary with controlled clocks and dates while preserving the
  live HealthKit and WatchConnectivity dependency on physical devices.

## July 27, 2026 at 12:27:31 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8ba9e9b5d45f16c0b51cbe78482c202b4541ab05`
- High-level reason: Make iPhone and Watch transcript sections seekable, keep
  Watch playback following the active section, configure spoken-audio output,
  expose the active route, and peak-normalize unusually quiet PCM for playback.

## July 27, 2026 at 12:26:49 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `b993378751a6b51d7ef4deb437729826bbfe1723`
- High-level reason: Make the Watch converge on a late-arriving paired-iPhone
  account session, automatically page the full recording library, expose its
  exact total, and remove the Watch-only eight-recording display cap.

## July 27, 2026 at 12:10:19 PM EDT

- Repository: `instant-data-swift`
- Commit: `cb1b7217f4d366fd548651e416c31b8cbea91b8f`
- High-level reason: Persist canonical live-query triples and page information
  atomically with server refreshes, restore ownership across relaunch, and
  retract only rows no longer owned by any durable query.

## July 27, 2026 at 12:08:06 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `52bab8e7605a67501d349ab67ae45199e1096097`
- High-level reason: Add strict live Apple Watch heart-rate measurement to
  active recordings using an acknowledged WatchConnectivity control channel,
  a HealthKit workout session, fresh-sample enforcement, and recording UI on
  both the Watch and paired iPhone.

## July 27, 2026 at 12:01:58 PM EDT

- Repository: `instant-data-swift`
- Commit: `c5667b402dffd792622b24b21955dbf50a74eaaa`
- High-level reason: Replace the unbounded live infinite-query subscription
  with limited starter, forward, and reverse cursor chunks; atomically apply
  authoritative page windows; freeze loaded intervals; preserve local-first
  starter rows; and cancel every replaced or final Reactor registration.

## July 27, 2026 at 11:51:49 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `96eaa15643c6d1c09f84eff7e71099b421533acc`
- High-level reason: Select direct Deepgram for physical-Watch production
  transcription so transient paired-phone reachability cannot terminate live
  PCM delivery, while preserving WatchConnectivity only for asynchronous
  companion responsibilities such as Instant identity bootstrap.

## July 27, 2026 at 11:35:59 AM EDT

- Repository: `instant-data-swift`
- Commit: `0b3183e1f45ccf870f44d35a31bde3714696da69`
- High-level reason: Record the accepted private opaque-cursor design, exact
  before/after pagination flow, local-cursor safety boundary, and remaining
  continuous page-info and bounded infinite-query ownership follow-up.

## July 27, 2026 at 11:34:56 AM EDT

- Repository: `instant-data-swift`
- Commit: `2c2117ae0ca1e84eab8b422b51629919815bf259`
- High-level reason: Preserve canonical live query page information and opaque
  Reactor cursors through decoding, persistence, one-shot materialization, and
  exact after/before re-encoding so bounded remote pagination can use server
  frontiers without reconstructing lossy client cursors.

## July 27, 2026 at 11:21:38 AM EDT

- Repository: `instant-data-swift`
- Commit: `c429e815bb0be013b76db96228a503bec7ac37bd`
- High-level reason: Expose the library-owned composite fetch request directly
  to actors and TCA effects, preserving the same transformed load,
  `combineLatest` observation, error, and cancellation behavior used by
  `@Fetch` without requiring wrapper state.

## July 27, 2026 at 11:12:45 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `cdd1f3e2fafed31e86a10f8cb3e7fe25116a1c19`
- High-level reason: Preserve the clean signed production Watch build,
  successful physical installation and launch, settled passive UI evidence,
  runtime-only Deepgram override handling, and the remaining spoken-production
  acceptance boundary in the durable Watch transcription guide.

## July 27, 2026 at 11:08:30 AM EDT

- Repository: `instant-data-swift`
- Commit: `931d4f39d5a252e636252e981433e70869401c3f`
- High-level reason: Record that the clean production `ScribeSharedWatch`
  generic build now compiles and signs for arm64/arm64_32 with strict code-sign
  verification, while preserving install and live production acceptance as
  separate remaining device work.

## July 27, 2026 at 11:02:29 AM EDT

- Repository: `instant-data-swift`
- Commit: `9ce8dccda4c67b17a7d0e3d6c7ceabe85730d431`
- High-level reason: Reconcile the durable audit with the complete physical
  Watch PCM/WAV/Deepgram/final-transcript proof, the production audio-policy
  port and watchOS build, the 447-test Scribe suite, and the remaining signed
  deployment, persistence, reliability-soak, and ReplayKit boundaries.

## July 27, 2026 at 10:58:28 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ac50d0d2603e4c45f7964e55ebfd74f801d6cde3`
- High-level reason: Carry the recording-compatible Watch audio-session policy
  proven by the physical Deepgram probe into the production transcription
  path, preserve TCA ordering invariants, and document the evidence and
  operational acceptance procedure.

## July 27, 2026 at 10:45:54 AM EDT

- Repository: `instant-data-swift`
- Commit: `f742678c8c0f51884e78eb9061a15c91c79615f1`
- High-level reason: Record the Watch auto-run readiness fix and the final
  clean Scribe package verification of 446 tests across 47 suites.

## July 27, 2026 at 10:44:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `7cabc1aad2beddd3f2f1c0f81f3572711e7dd21f`
- High-level reason: Preserve proof that blocked remote diagnostics do not
  block local credential persistence while replacing scheduler-yield sampling
  with a bounded monotonic evidence window under parallel-suite load.

## July 27, 2026 at 10:43:16 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1c5500a51b78c7c4b87ad71dd93e72648e75dcfc`
- High-level reason: Start the Watch probe's eight-second auto-run window only
  after capture, WAV append, and Deepgram streaming report active, so physical
  startup latency cannot consume the diagnostic recording window.

## July 27, 2026 at 10:40:47 AM EDT

- Repository: `instant-data-swift`
- Commit: `d8f5c2219f3751993a517e708ebeff4bf1992be7`
- High-level reason: Reconcile the final audit with the Watch probe's
  recording-compatible asynchronous activation policy and the authoritative
  Scribe package, performance-safety, and artifact-sanitization evidence.

## July 27, 2026 at 10:40:18 AM EDT

- Repository: `instant-data-swift`
- Commit: `0e2dc17922dc276630601e4e27fa88d77c2d53ab`
- High-level reason: Preserve exact final suite totals and distinguish the
  physical Watch build/install/launch/prepared evidence from the remaining
  human recording and ReplayKit broadcast acceptance interactions.

## July 27, 2026 at 10:33:55 AM EDT

- Repository: `instant-data-swift`
- Commit: `10f685d52705c14d01266c36df9b64feaab19c31`
- High-level reason: Give nonblocking utility-priority startup cookie sync a
  five-second wall-clock evidence window under parallel-suite load while
  preserving its exact request and retention assertions.

## July 27, 2026 at 10:31:57 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `18d54937308fcf140192f1d4ec0ccd89284d5acb`
- High-level reason: Keep the physical Apple Watch microphone session on the
  recording-compatible default route policy while retaining asynchronous
  activation required before opening its Deepgram WebSocket.

## July 27, 2026 at 10:30:34 AM EDT

- Repository: `instant-data-swift`
- Commit: `ef9eebdb2b96444b8db4ba61c797f33ac935f687`
- High-level reason: Wait for all automatic composite-fetch observations with
  a bounded condition before asserting recorder totals, preserving exact
  observation coverage without sampling asynchronous task registration.

## July 27, 2026 at 10:29:38 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f14b1049365dc91195c136c00a0c33109a0eb18b`
- High-level reason: Show the reproducible-build timestamp prominently on the
  Apple Watch audio probe so the installed diagnostic binary can be identified
  directly from its screen.

## July 27, 2026 at 10:26:14 AM EDT

- Repository: `instant-data-swift`
- Commit: `c238c4e7ae29154f46f923e4c7bd1eb3a01bbc65`
- High-level reason: Remove a race-prone assertion about the transient state of
  intentional live-transport auto-connect while retaining explicit WebSocket,
  connect-opened, and close-closed behavior checks.

## July 27, 2026 at 10:23:13 AM EDT

- Repository: `instant-data-swift`
- Commit: `83939c376899f6fe2b30e5c6789f2482b3f034e2`
- High-level reason: Make composite fetch fixtures independent of concurrent
  task order and prevent a load-only assertion from racing an empty automatic
  observation during the full parallel suite.

## July 27, 2026 at 10:18:42 AM EDT

- Repository: `instant-data-swift`
- Commit: `1657fba57650f1fdf4c84343ee93ef48f19120f0`
- High-level reason: Keep synthetic relaunch and migration fixtures inside the
  production cache-retention window and document the lock protecting the
  pruning cadence's unchecked `Sendable` state.

## July 27, 2026 at 10:14:50 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ee8a81d542ac62dce6268862a3d1dd013fa6b874`
- High-level reason: Reuse the already bootstrapped live Instant runtime for
  Scribe's read-only local projections, eliminating the second SQLite runtime
  while retaining live freshness semantics for ordinary one-shot queries.

## July 27, 2026 at 10:14:43 AM EDT

- Repository: `instant-data-swift`
- Commit: `0a1129fa639a416a57ce262e3be7b0a18a0f4935`
- High-level reason: Correct the deterministic offline-relaunch benchmark to
  the measured 11-hop contract after bootstrap pruning was integrated into the
  existing persistence actor call rather than adding a new hop.

## July 27, 2026 at 10:13:43 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `b7fc41134b068cb6fdaa19fd0db70091a72d353c`
- High-level reason: Authorize the physical Apple Watch recording session for
  long-form audio streaming and configure its Deepgram WebSocket to surface
  connection failures immediately on constrained or expensive networks.

## July 27, 2026 at 10:13:01 AM EDT

- Repository: `instant-data-swift`
- Commit: `d1066e817f5048abfd8eb5746eddf41b7edf3538`
- High-level reason: Prune persisted query cache rows at bootstrap and then
  every 64 successful cache writes, preserving active observations without
  adding retention work to every one-shot query.

## July 27, 2026 at 10:05:15 AM EDT

- Repository: `instant-data-swift`
- Commit: `96cc06864fe7928a3609ac3388a63451aa4a2cb1`
- High-level reason: Derive an injectable read-only local client facet from an
  existing runtime so composition roots can use ordinary query APIs over local
  state without a second SQLite bootstrap or a public `queryLocal` method.

## July 27, 2026 at 10:03:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `94cd84a7c2beae28070539c3c1bd458d4eddd736`
- High-level reason: Route Scribe's explicitly local projection loaders through
  an injected local-only Instant client sharing the live client's SQLite file,
  avoiding server acknowledgement waits without exposing `queryLocal`.

## July 27, 2026 at 9:59:16 AM EDT

- Repository: `instant-data-swift`
- Commit: `b812a2c3a1b13d0d3e90b927a1b4232afd80be7e`
- High-level reason: Avoid re-materializing flat query observers in namespaces
  untouched by a commit while preserving conservative invalidation for
  relationship paths, includes, schema changes, and unresolved entities.

## July 27, 2026 at 9:56:00 AM EDT

- Repository: `instant-data-swift`
- Commit: `a488b43452ceaf2c620775737b99a9cca0d08468`
- High-level reason: Invoke the Reactor-compatible query-cache retention policy
  after production one-shot writes, preserving active observation keys while
  bounding unloaded rows by age, count, and encoded size.

## July 27, 2026 at 9:48:11 AM EDT

- Repository: `instant-data-swift`
- Commit: `870a4083e2eb895c776bc2634e0f69a4b3de6cb6`
- High-level reason: Decode cardinality-one entity snapshot fields through
  schema-owned typed attribute paths, with centralized wire semantics and
  explicit namespace mismatch validation.

## July 27, 2026 at 9:45:23 AM EDT

- Repository: `instant-data-swift`
- Commit: `e965771ebe8b9bdb69a4fe4d96014ab0114e98dd`
- High-level reason: Add a dependency-controlled zero-argument typed ID
  initializer with canonical lowercase formatting, while preserving raw-value
  identity and keeping the core module independent of Dependencies.

## July 27, 2026 at 9:43:57 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `09e1c4c4afdc2dc679a307e300fb542ca0c6227c`
- High-level reason: Preserve the bootstrapped Instant diagnostic logger across
  the iPhone WatchConnectivity speech relay so Watch audio, Deepgram send, and
  transcript timing checkpoints reach the canonical remote log.

## July 27, 2026 at 9:42:13 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `84c41625ccf2494839ebecedaf7b4e205c003e00`
- High-level reason: Serialize live recording snapshot saves and deletes through
  a bounded tail-task coordinator so overlapping reducer effects cannot finish
  persistence mutations out of submission order.

## July 27, 2026 at 9:38:03 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a43a126035c07eaaa4437c54c76ec9b462302f60`
- High-level reason: Keep cumulative transcript text out of live persistence
  transactions while retaining normalized segment and word delivery, then
  explicitly write the complete fallback string during finalization.

## July 27, 2026 at 9:32:38 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `2a6a44c1146ec35023322b54961b4488204deb0a`
- High-level reason: Structurally redact benchmark credentials before
  performance reports reach disk and provide an atomic sanitizer with hash
  provenance for existing ignored artifacts.

## July 27, 2026 at 9:29:44 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `4a30f633912945d5cf01110370c0aa163494f996`
- High-level reason: Correlate transcript source attribution with the audio
  frames actually sent under each context and use the exact `System Audio`
  fallback whenever reliable application metadata is unavailable.

## July 27, 2026 at 9:29:36 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5e3d1c13f278c856688bfeef91dd936802e8d6ce`
- High-level reason: Load generator-produced, Git-ignored provenance into the
  SwiftPM build plugin and reject stale commits, mismatched source roots, or
  dirty worktrees before compiling reproducible build metadata.

## July 27, 2026 at 9:27:54 AM EDT

- Repository: `instant-data-swift`
- Commit: `657a74a16e5347c729d94fcc68ceaad60875e4ba`
- High-level reason: Persist only an unencodable mutation as failed, keep the
  shared live connection open, and continue sending healthy mutations behind
  it instead of poisoning every delivery attempt.

## July 27, 2026 at 9:22:10 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `02f8a08109e321e86e3b4f4e894b1bd98459f7e2`
- High-level reason: Embed clean-build commit, branch, dirty state, timestamps,
  host, source root, artifact location, configuration, platform, and
  architecture in the standalone Watch audio probe's structured startup log.

## July 27, 2026 at 9:21:59 AM EDT

- Repository: `instant-data-swift`
- Commit: `43b65eeffafff3b6a54ea8caf8943a329901ab95`
- High-level reason: Assign monotonic implicit outbox timestamps so mutations
  created in the same millisecond retain insertion order across persistence and
  relaunch without changing deliberately supplied domain timestamps.

## July 27, 2026 at 9:18:04 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d4beb51ad6f3c9c59bea3df0ea319f7a238c7cdf`
- High-level reason: Wait for the asynchronously enqueued WebSocket timeout
  diagnostic before asserting it, removing a scheduler-dependent suite flake.

## July 27, 2026 at 9:17:28 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `0d107b482fa1eb003c34d757e8d29b3c3f9d9aac`
- High-level reason: Retain only the newest 4,096 Watch relay chunk timings in a
  circular buffer and avoid false latency attribution after older timings are
  evicted.

## July 27, 2026 at 9:16:13 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3a04ad40185a8590e8777c0dd2a691d3ab8dad2a`
- High-level reason: Require explicit process opt-in before structured
  diagnostics can use the dedicated remote Instant app, while preserving local
  diagnostics by default.

## July 27, 2026 at 9:14:49 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `4f6c9a9eb463eb8fe94195c55260715aab3972b8`
- High-level reason: Restore a saved Watch credential through the phone relay,
  persist validated replacements on the phone, inject relay credential sources
  explicitly, and keep remote diagnostics off the credential critical path.

## July 27, 2026 at 9:14:44 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `7ec2bddb6c2971d0315858c58f5bc836a1b73461`
- High-level reason: Attach build provenance to structured diagnostics, record
  startup milestones locally, and preserve a privacy-safe local checkpoint when
  a remote diagnostic write fails.

## July 27, 2026 at 9:12:06 AM EDT

- Repository: `instant-data-swift`
- Commit: `fdd4c1e399f02e7e30ae967aa8b18d8fffdfc0e2`
- High-level reason: Reference-count shared live-room registrations so one
  observer leaving cannot tear down the server room while another observer is
  still consuming it.

## July 27, 2026 at 9:07:41 AM EDT

- Repository: `instant-data-swift`
- Commit: `d2b1e5c0f27a2b161f7d3346a9bdb7ae4058992a`
- High-level reason: Make automatic fetch observation generation-aware so a
  canceled or stale observer cannot supersede a newer explicit projected-value
  task and surface a spurious `CancellationError`.

## July 27, 2026 at 9:04:28 AM EDT

- Repository: `instant-data-swift`
- Commit: `62eb6067d032271c2f805dc8543543eba8b3dede`
- High-level reason: Make ordering parity fixtures use genuinely later edit
  timestamps and prove the complete local order before validating the
  infinite-query window.

## July 27, 2026 at 9:04:08 AM EDT

- Repository: `instant-data-swift`
- Commit: `8f43f3f5258da82f5d788abe854914a49450fba1`
- High-level reason: Rebase remaining optimistic mutations above the current
  server snapshot so later local writes stay visible after an earlier server
  confirmation, matching upstream Reactor overlay semantics.

## July 27, 2026 at 8:56:56 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `bfa8bc07aa607b0e6a33e6f02cb57420bbd0c1d8`
- High-level reason: Adopt the intent-ledger workflow and install reusable
  change-recording and reproducible-build provenance helpers in Scribe.

## July 27, 2026 at 8:55:43 AM EDT

- Repository: `instant-data-swift`
- Commit: `3a0c2c53cf28296ea56617d6d868dfa6a73f0383`
- High-level reason: Preserve live-error `original-event` correlation, reject
  only the affected query without reconnecting the shared socket, fail
  one-shot queries promptly, and prevent stale automatic mutation delivery
  when the runtime is configured for manual connection.

## July 27, 2026 at 8:55:21 AM EDT

- Repository: `instant-data-swift`
- Commit: `e2dba6ba9ce08a5ec107bade582bc86cfd6e4f8e`
- High-level reason: Adopt the intent-ledger workflow and install reusable
  change-recording and reproducible-build provenance helpers in Instant.

## July 27, 2026 at 8:39:12 AM EDT

- Repository: `instant-data-swift`
- Commit: `ceb22e40503aa854adb18a8c9050c59e3fc2e65d`
- High-level reason: Refresh deterministic performance evidence for the
  optimized offline-restore hop count and ensure the Reminders move fixture
  writes later than its seeded triples.

## July 27, 2026 at 8:34:03 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `95c4b3174957e2cb4c792082b8eeb9907e93f7f5`
- High-level reason: Bound the live microphone PCM stream to its 256 newest
  buffers, record dropped-buffer diagnostics, and warn once when a speech
  consumer falls behind without interrupting local capture.

## July 27, 2026 at 8:28:05 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `386a9b41c8a913039497e7e0b57475f4c47e4d2d`
- High-level reason: Close the remaining pasteboard crash path by making the
  clipboard read dependency async and isolating every live read to MainActor.

## July 27, 2026 at 8:22:56 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `46ec7179ec1d5062eb1aef39162fb425124947b9`
- High-level reason: Establish shared commit discipline in Scribe so parallel
  work is staged deliberately, journaled centrally, and handed off cleanly.

## July 27, 2026 at 8:22:28 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3ed949b13c3e5bec795081c9ae5489536f103547`
- High-level reason: Preserve the existing parallel Watch companion auth,
  speech relay, wire-format, test, and session-record work before auditing it.

## July 27, 2026 at 8:21:39 AM EDT

- Repository: `instant-data-swift`
- Commit: `099858f93f76de6dfa2ce9e41cb50386b3848176`
- High-level reason: Establish the cross-repository commit journal and require
  small verified commits plus clean parallel-agent handoffs.

## July 27, 2026 at 8:20:35 AM EDT

- Repository: `instant-data-swift`
- Commit: `7593790839f66620b4d4cf8789d20f4530c58ab3`
- High-level reason: Preserve the unedited comprehensive audit journal before
  reading or changing the audited working tree.

## July 26, 2026 at 4:41:41 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `9d65fbb201b22816a2b355675ce932e4c3480d62`
- High-level reason: Establish the Scribe baseline with the Watch companion
  speech relay and privacy-safe diagnostics checkpointed.

## July 26, 2026 at 4:41:39 PM EDT

- Repository: `instant-data-swift`
- Commit: `a9abe9d27301ac205ea6ff1e445eec9051a18913`
- High-level reason: Establish the Instant Swift baseline with startup tracing
  and hardened storage runtime behavior.
