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
