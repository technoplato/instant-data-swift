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
