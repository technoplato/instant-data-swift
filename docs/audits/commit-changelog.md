## 2026-11-04 22:09:50 EST — scribe `73460479af02a0e8e8900cf3098289a76a96b92b`
Cut (#1652): Scribe 0.1 (258) from main after landing B of #1652; the build number 257 to 258, build 258's plain block and four stories.

## 2026-11-04 22:06:36 EST — scribe `03ed6805878ca87dcf03404ae55bb3c60a84a35d`
Feature (#1652): an agent's chat has a message box (agentCommands message-agent, carried out by the mirror through tools/agent-run --steer); a long-press holds or resumes a session's issue (Backlog, with the recording and moment noted on the issue); Agent chats sorts by most recent, cost or needing you and can show only agents needing you; an open brief shows his linked lines.

## 2026-11-04 22:06:53 EST — instant-data-swift `995043755a97f26d268100262c9ef91630579dbd`
Release (#1513, #1480, #1109): v1.9.68 tagged on 99504375 (ledger bd929885), from main merge 0df9d697: #1513 a final's publication splices the rows it reaches (red a0dee714, greens f8b7c453 428411d9; a final's publication p50 17.6-18.2 -> 15.6-16.0 ms on the Mac mini, materialized snapshots -43%), #1480 a restated result compared with its stored rows once (red 322c3993, green ca9dd8d2; 192 -> 96 rows read for a 32-line page), #1109 no identity set when the nested limit kept every fact (4fff7e5c). No API or storage change. Debug bundle: 1,669 tests, only the three failing on main since 1.9.64-1.9.67.

## 2026-11-04 22:05:06 EST — scribe `a4f2cd2860d765651d79ed491b1388cdc32c2801`
Tooling (#1776): build.sh's pass-over of an old waiter that leaves a free slot unused now counts only time it was watched (a look over 120 s after the last restarts the clock; live, a 5-min-old look passed over an old P0 waiter), and an old-code waiter's resubmit keeps its place from its own journal line (red e9ed47495).

## 2026-11-04 21:20:41 EST — scribe `896de971e768950b223ac290f9dc496c3252ec4c`
Cut (#1423): Scribe 0.1 (256) from main after the list's sealed summary (ADR 0128, #1423, #1195, #1506); CURRENT_PROJECT_VERSION to 256 and build 256's plain block and stories.

## 2026-11-04 21:18:33 EST — scribe `5c293a67a4551cc0fc67d368838ae9acd5b2a474`
Performance (#1423, #1195, #1506): the recordings list follows no line being recorded. A final links no preview slot and the list's page includes no transcriptions and no newest image (ADR 0128); Stop seals the two slots and the new recordings.wordCount (schema pushed, 550 rows backfilled with backup); a live take's row reads its newest two lines and count from the take or from two small queries per recording another device records, while the list shows in front; the map reads its pins' pictures while it shows, and an image's write leaves updatedAtMs to the heartbeat; a recording's chapters follow a live window of the newest 8 plus one read, with the drawn fields. Before (build 248): the page restated 144.8 KB 1,552 times in 88 minutes (0.98 per final), chapters 869 KB a frame.

## 2026-11-04 19:51:28 EST — scribe `d763b77be632f66cff4c1e419ae09ad433eabc9a`
Fix (#1803): the Watch app fits App Store Connect again (ITMS-90389 refused 249 and 250 at 76.1 MB, arm64_32): the Watch app and its widget link without their 3.66 MB of export tables, watchOS compiles at -Osize under -O device builds (other platforms keep -O), each production cut measures its kept Watch app and fails over 70 MB after every install, and each TestFlight upload measures its IPA and stops only at a size Apple refused; red b650b38c9, landed dfbdbceec, changelog 5a8d16af2.

## 2026-11-04 19:53:54 EST — scribe `3c34c4b88b2f1b4b78869e5689490cdd90ef693c`
Performance (#1422, #1502): the recording screen draws when something changed. The floating bar's comb visualizer rests in quiet: its TimelineView pauses while every frame a draw reads is too quiet to lift a tick past its 1-point floor (with VoiceOver on, too quiet to leave Silent), and the meter's new loudFrame wait wakes it off the main thread, keeping capture analyzing; on build 249 those identical frames were a third of the recording screen's main thread (SwiftUI's display link 16.0%, RenderBox's Metal render 16.4%). The Live Activity's excerpt walks back from the timeline's end instead of copying it every tick (162 ms a minute). The bar's record symbol breathes through Styleguide.BreathingSymbol (Core Animation) instead of SwiftUI's per-frame effect (the list in front turned the main run loop 161 times a second against the recording screen's 91 on build 248). Same pixels, same breath, same words; changelog 8ea93259e.

## 2026-11-04 19:44:13 EST — scribe `be00c65e31e95709c60f2fd7f35639a69b712210`
Feature (#1790): scribe decision amend says an open question's own lines again in what he can open (a WAITING line's file and line becomes whose note it was), adds drafts and links, keeps his words byte for byte and sends no notice.

## 2026-11-04 19:26:58 EST — scribe `29e42144ea489ae00b51387918ac04d910938010`
Fix (#1751): in-app requests outlive the app store's listener. Start or Resume Recording (the Action button), the Home Screen quick actions, the Live Activity's and Control Center's recording controls, the timers' Live Activity presses (#612) and Pause Playback each went to the store through one process-wide AsyncStream; the store listens in an effect of the app view's .task, and an AsyncStream finishes for good when its one consumer is cancelled, so after the view went away once every later press only brought the app to the front. A new RequestMailbox target gives each listener its own stream (the newest takes each request, the newest N wait while none listens, it never finishes), the four listeners run per window without cancelInFlight, and each link and control logs system-surface.request.sent (delivered or waiting). Red 1b7b4e81b and d2b992fec, test stub 8699bdd82, changelog 94ea7e627, landed as b8523e940; measured on the mini (1751-redgreen, 1751-stub).

## 2026-11-04 19:09:58 EST — scribe `5d7d280231a8ba7361e2c49712bbe47ef5c5fe4e`
Tooling (#1776): build.sh orders queued builds by their issue's P level (P0 before P1 before P2 and lower; the agent's flag only breaks ties; low last), read through build_jobs.py class (a 5-s tracker timeout, a cache every waiter shares, the last level or the flag when it cannot answer, P2 with no issue), aged one class per 3 h from the real queue time; waiters queued before the install keep the old code and are held back by a blocker and a gate; BUILD_QUEUED_AT only for a resubmit; reaps from one listing; holders yield to a higher class (green 5d7d28023, fix 349eab915, merge 67561d79d).

## 2026-11-04 19:05:28 EST — scribe `0995399f1af21ef05e7cca795a79f216760461cd`
Cut (#1674): Scribe 0.1 (252) from main after 003ca2598 (#1393 batches 2 and 3: the now-playing card that seeks Scribe Playback, Photos' own live, his UI asks); CURRENT_PROJECT_VERSION 251 to 252 and build 252's plain block and stories.

## 2026-11-04 19:02:41 EST — scribe `003ca259829bd367f79bf059a12caafcdb579008`
Feature (#1393, #1674, #1716): his UI asks from Recordings 349-365, batches 2 and 3: what plays now as a Lock Screen-like card whose bar seeks Scribe Playback on this phone through the App Group, Photos' own live, the New Message pill out of the way, the home card's last four sentences, frames without a gray flash, hold a thread's bar to mute, everything copied in one place, and a catch-up deck of unread answers; What's New build 252.

## 2026-11-04 18:41:26 EST — scribe `73987de4649214ee7190c750f1392f9b2ccf7e89`
Feature (#1790): a decision question carries the draft it names (scribe decision ask --draft) and a link to the place it names (--link, https or the app's own scribe-shared link), and refuses one that shows a file he cannot open; the WAITING gatherer names whose note a line was; the door's evidence link takes scribe-shared://.

## 2026-11-04 18:19:14 EST — scribe `e82bf7c56648ce3ea3465cb9aeabe6bb3d0219f9`
Tooling (#1799): scripts/perf/metrics.py prints his five metrics (size of the recording, size per minute, usage per minute, CPU per minute by state, heat) per build and per recording, each number with its source (energy ledger, a sysdiagnose powerlog read over unplugged minutes only, iOS hang reports, the recording's Instant rows), --compare A B with a scenario check, and --trend --write one row per build in ~/Sync/audit/perf-metrics/trend.jsonl; it keeps the collector's ledger lines by day (the 64 MB journal prunes). Nothing new runs on the phone (#1285). Red eb2d95791, green 808312e2a, changelog 538abc916; 39 tests.

## 2026-11-04 17:34:54 EST — scribe `a64e397d13287bd481ee16714c3b717824ce6a67`
Tooling (#1793): agent-run ranks the eligible Claude Max logins by the week most at risk of going unused (weekly % left per hour until that login's weekly reset, highest first; ties to more 5-hour left; no reset read after, by weekly % left), not the fixed accountOrder; the interactive login and --spare stay last; --quota says each login's place and why. Red 85aa7eef0, green c65c4d950, installed into ~/Scribe/tools 17:30; changelog c46543758. Live 17:31: pp (100% left, 11h28m: 8.7%/h) then halfjew22.

## 2026-11-04 17:10:48 EST — scribe `aa5b33a2e1e11700d6d5f29558393945dfe735ef`
Feature (#1592): "Scribe, stop recording" in the owner's own voice (a named speaker or a voice print without a question mark) stops the recording at once, in front and in the background: a fixed grammar reads the sentence, never the model (0 model calls a try, was 1 at 1.5 s median); an unknown voice is asked in front and refused aloud in the background; another person, system audio and Scribe's own voice never stop it; every try logs #1592. The grammar over 90,758 mirrored lines reads 4 as a stop, all real asks.

## 2026-11-04 16:33:42 EST — scribe `208757feafefb095b5cc838e03966b6f14e68980`
Feature (#1777): the Mac and the mini keep only each recording's compressed copy (phase 1): one range reader of it (Apple's decoder, only the segments a stretch needs, one encoder run at a time); the mirror writes no live.wav from the copy and keeps its index; the cutter, book_readings, transcribe-gap, the scrubber and the ShazamKit catalog read the copy; a window read from it is within one step of a 16-bit sample of the Mac's old decode (Recording 340); changelog 78089ecd3.

## 2026-11-04 15:33:30 EST — scribe `63b4869f2795682f37cbfc970a593aeab53ebe3e`
Cut (#1748): Scribe 0.1 (248) from main after the 1.9.66 pin: the full-rebase server apply no longer walks every fact for each pending write it replays; CURRENT_PROJECT_VERSION 247 to 248 and build 248's plain block.

## 2026-11-04 15:32:52 EST — scribe `0f0a41abd46903bab8a541a89e6bed30564b8b92`
Fix (#1748): pin instant-data-swift 1.9.66 (tag on df3ef358): the store's newest transaction time is kept in time-ordered counts, not walked (the replay scaling test 68.920 s -> 0.368 s).

## 2026-11-04 13:05:18 EST — scribe `090dcc070cd74903f17d30a12ea30514521c1d49`
Fix (#1616): behind another app, a microphone restart that iOS refuses right after a call's end, an interruption's end or an audio device change tries again 1, 3 and 5 s after the refusal, on the audio session the failed start keeps, instead of waiting until the app comes to the front (measured waits before: 28 s, 40 s, 71 s and 68 min); red and green on the build machine (nothing fails only in green, six fail only in red), the iOS app core compiled; changelog 1bbc83870.

## 2026-11-04 12:54:46 EST — scribe `b3d26898ef0ad770cb0994ea9bf09945734c1bf6`
Cut (#1652): Scribe 0.1 (246) from main after landing A of #1652; the build number 245 to 246, build 246's plain block and two stories.

## 2026-11-04 12:53:32 EST — scribe `a04d25dc032b1c9b0bd911c1aebde37198fa2070`
Fix (#1652): every page Settings > Playground pushes, and each agent's chat, give the floating recording bar its room; a chat reads its rows by its session alone (duo-panels-1578's chat timed out after 30 s on production with the account beside the session; 67 ms alone); claude runs take a message after each tool call through agent-run's inbox hook.

## 2026-11-04 12:16:04 EST — scribe `b3e4dfba6a985f25041c4faa58547f7406615718`
Feature (#1678): Claude work per day (llmUsageDays) from the session logs since 2026-07-14, each reply once by message id at list price (514,156 replies on 47 days, $70,696.07); the quota command folds only new log bytes every five minutes (1.5 s at load 348).

## 2026-11-04 11:51:24 EST — scribe `23371c912d995c90d8bce336aeeca56bb381b669`
Feature (#1678): the quota history: llmQuotaDays (one row per account per local day of 5-minute reads and a summary) and llmUsageDays pushed to production 11:50-11:51 (drift 0); the quota command keeps each read by day, and its printed log since 2026-10-29 14:20 was backfilled (10,034 reads, 49 rows).

## 2026-11-03 10:14:00 EST — scribe `4acdc7d06aeec9e37aa481d0ea3171624bbf15d3`
Feature (#1652): Agent chats in the Playground: every agent session (running first, with its issue, model, account, status, counts, tokens and API-equivalent cost) and its chat as one timeline in file order, thinking and tool calls folded until tapped, read live from the agent activity rows only while shown; days named once, a run bar with every count.

## 2026-11-03 09:09:51 EST — scribe `fc45bd34975e8500d85934a038677d972d25c3ed`
Feature (#1207): in Scribe Playback the spoken word stays on one line and the words move up a row at a time: following scrolls to the playing line with the anchor that puts the spoken row on the reading line (simulators: 341-346 points on an iPhone 17 Pro and 458-466 on an iPad Pro 12.9 for 20 of 20 seconds, main 453-583 and 428-511); landed in fc45bd349 (green b8830dcfe, e30b513f9), changelog 4a95a1134.

## 2026-11-03 09:08:06 EST — scribe `f295386d95aef30c19c5d9016b4b9d371d4bf392`
Fix (#1671): the Mac mirror decodes the phone's compressed copy one encoder run at a time, so a recording's Mac audio goes on after the app relaunches mid-recording (Recording 353: live.wav 138 s -> 348 s).

## 2026-11-03 08:32:27 EST — scribe `da9f6b8ea946dd72ae587ffbef9a2675e54972d3`
Cut (#1482, #1528): Scribe 0.1 (242) from main after the #1591 landing (a speaker whose lines are clearly not his voice gets no name of his, live and in both learners); the build number 241 to 242, and Build 242's plain note says words, not lines.

## 2026-11-03 07:57:05 EST — scribe `b1cc6003c750082871a839ae8f8d015e79218ec7`
Fix (#1591): a recording number the diarizer mixed keeps no name of the account holder: the stream checks a matched speaker's lines one at a time against his print (half or more of the line time under 0.25 is not him), and the evidence rides on the voice summary so both learners take the name off; measured on 19 numbers in 7 recordings (mixed 0.87, his own 0.00-0.31).

## 2026-11-03 07:30:14 EST — scribe `efd0e8eb9a3dc6af587a3100e0548931cc2c85c1`
Cut (#1482, #1528): Scribe 0.1 (241) from main after the #1661 and #1591 landings (a late answer sits at its thread's line in playback; a voice that starts as another stops is its own speaker); the build number 240 to 241, and Build 241's plain note reworded so each Try works for a tester with no recordings.

## 2026-11-03 07:27:24 EST — scribe `177f124c0d29e3a842e54aaf1d6f272e9e4a6a51`
Fix (#1591): a final's first phrase keeps the last speaker only while the diarizer still hears that speaker, so a show that starts as Michael stops is its own (Recording 343: Ms. Rachel on the backseat iPad under his number), and each word's speaker confidence is its own again, so another voice's words stop feeding a voice's print audio.

## 2026-11-03 06:06:37 EST — scribe `e97fe1ff36075fb46455dfb353b5eefaec81eaba`
Fix (#1661): in playback, an agent's answer given after the recording ended sits at the line its thread hangs on, not at the end.

## 2026-11-03 05:46:39 EST — scribe `c97e550f0d4ecc79b3872f5f4931db7581cfd1bd`
Docs (#1057): the CPU-load gate held on three consecutive installs on his iPad (236-238 skipped the CPU load and compiled for the Neural Engine in 89.2-89.5 s); build 233's 47.6-minute iPhone compile ran about 11.6 minutes with the app awake (36 minutes suspended); the change's tests confirmed on the Mac mini on what shipped as 236 (SpeechClientLiveTests 212 of 212, the hand-over's recording tests).

## 2026-11-03 05:31:57 EST — scribe `88ee5d2373761b167b9180f5a847f3fb5a359b94`
Feature (#1627): Start or Resume Recording, an App Shortcut beside Brainstorm for Siri, Shortcuts and the Action button: it hands the app scribe-shared://recording/live inside its process (the quick actions' buffered stream, renamed linkRequests), and the list resumes a paused recording, keeps one that records, or starts one as Record does, then shows the newest line (Back to Live); the link's web form opens nothing. Landed on main as 5c94ae809.

## 2026-11-03 04:56:31 EST — scribe `5031e01d24693814d4d15cba40b026f32998cec1`
Fix (#1606): the listener watch's stderr note names the command its background listing waits on; installed and checked on his Mac (six lines printed 61-913 ms after a separate writer appended them while a listing ran past 5 s), and a second ps stall seen live (04:51:40-04:54:30, load up to 917) where the bounded runner returned at 2,006 ms.

## 2026-11-03 04:49:01 EST — scribe `f7e420cff59808bed5119011ff451e7ec3713538`
Fix (#1606): no ps, lsof or cmux call holds the listener's line watch or a scribe command: on 2026-11-01 the mirror wrote Recording 344 #263-#290 on time, but the watch re-read the process table on its loop and scribe decision add named its agent from ps, and both sat 3 minutes in a ps that stopped answering; every listing now has a 2 s limit that holds (a shell between: 2,005 ms against 2,000, 6,070 on main) and the watch lists in the background, printing each line at once (within 1 s against 3,054 ms with a 4 s hang).

## 2026-11-03 04:34:28 EST — scribe `412aa262a4b4386dbf4921c543dadfcdf7719c10`
Feature (#1518): what the phone that records plays shows once on its live recording, from the source its audio route gives (PlayedSoundCapture, keyed on the output route and on what plays): over the phone's speaker the microphone is the one source (Scribe Playback's lines from this phone are not streamed in from Instant, the broadcast's system-audio lines are not shown); in his headphones Scribe Playback's own lines stream in and the broadcast's copy is not shown; AirPlay, CarPlay, other Bluetooth, another device's play and a moment before the route was read keep every source with the shown-once rule. Measured: out loud the microphone repeated the played book in every stretch (228 finals in 19), in AirPods Pro 2 finals in 20. Display only.

## 2026-11-03 04:16:54 EST — scribe `a3f6f0b617eef28e24389876545bdd6157e34709`
Cut (#1482, #1528): Scribe 0.1 (238) from main after the #1393 landing (the views of a recording, playback's views and 25 UI asks); the build number 237 to 238, and Build 238's plain note reworded so each Try works for a tester with no recordings.

## 2026-11-03 03:51:12 EST — scribe `8995bf8290729c6a56a38f04aeb5583d4bc69ae5`
Merge (#1393, #1457): the views of a recording no longer double the screen's layouts (navigation stack 8.08 to 4.49 a second), playback has the same Lines, Notes, Photos and Chat through RecordingViewsFeature, and 25 of his UI asks from Recordings 321-349 (#1634 answers led by his lines, #1645 times in the speaker's color, #1628, #1629, #1630, #1563, #1564, #1520, #1519, #1603, #1589, #1611-#1615, #1639, #1459, #1633); What's New Build 238.

## 2026-11-03 03:19:53 EST — scribe `6034940dd43840852f258d3aea427df6274d3f26`
Docs (#1057): build 236's gate confirmed on his iPad (it skipped the CPU load on Your Mac and compiled for the Neural Engine in 89.3 s); his iPhone, unplugged and not recording, went 35% to 1% overnight while installs 233, 234 and 235 each started a compile and only 233's finished (47.6 min including suspension); proposal (e) for Michael: whether the CPU should stand in for Your Mac's offline fallback during the compile.

## 2026-11-03 02:22:06 EST — scribe `4fbfb707ceeaf1e599024c55a82417ec580b224e`
Fix (#1057): only a device whose provider is On This iPhone loads the models on the CPU after an update (his iPhone, on Your Mac, spent 23.6 s of CPU at thermal serious on it in build 235 for nothing); the audit gains build 235's device numbers (ready on the CPU 8.6 s iPad, 23.6 s iPhone).

## 2026-11-03 01:48:42 EST — scribe `3d725204b65a22fec32f15adf16947830e29b73e`
Fix (#966, #846): the Your Mac fallback's Apple stand-in hands over to On This iPhone (Parakeet with speaker labels) as soon as its models are ready (after an install's compile or a download) instead of keeping Apple until the Mac answers, at Apple's next final with no word lost or repeated, and a session no engine could transcribe starts On This iPhone; Settings > Recording names the engine writing the words, with why it stands in for Your Mac; a poor signal is proven to fall back to On This iPhone. Change log ac117902c.

## 2026-11-03 01:18:47 EST — scribe `76bd9069a7b7e4ef5fff3cc9907215f375e629b4`
Fix (#1057): On This iPhone writes the words on the CPU while the Neural Engine compiles after an update (iOS discards the compiled programs at every install; Apple DTS, forum thread 853157): a CPU-only model host (readyOnCPU), the session reports computeUnit cpu, and the recording hands it to the Neural Engine when ready; on the Mac the CPU loaded in 14.0 s against 152.8 s and wrote 516 of 520 words the same; for build 235.

## 2026-11-03 01:07:20 EST — scribe `10471bc4ec2a1895101ce8d6683963c0f3bb9807`
Fix (#1621): spotter 0.2.1 and 0.2.2: the speech helper keeps one name across releases (an update that brings the same helper compiles nothing; measured 1.2 s against 119.5 s after a new signature), and models remove takes spotter's own helper and compiled copies, keeping models Scribe for Mac shares.

## 2026-11-03 01:07:17 EST — scribe `2746bda9de07a227526b8f630abdb3af307c41f6`
Docs (#1482, #1528): build 234's TestFlight note works for a tester who installed the app today: its plain block is one Nothing to see line and a Try any new tester can do, instead of a Try that sent testers to a recording only an agent can make; stories unchanged.

## 2026-11-03 00:46:31 EST — scribe `f6c5831bb05757774fcb43d0435e1cc6e2db34d1`
Feature (#1619): scribe-catalog signs a growing recording from its last unfinished part (sign --from) and measures its newest minutes (measure --from); on real audio a grown piece signed in 2.3 s and 249 MB where the whole took 5.8 s and 577 MB; the catalog worker's steps run within deadlines; ADR 0083 amendment B, FEATURES item 30, the audit. MediaCatalogTests 19/19 on the mini. Change log e67bf9592.

## 2026-11-03 00:44:21 EST — scribe `9b0dfd785d2e20d16d0fd5174e49f34441c3bd43`
Docs (#1482, #1528): build 233's TestFlight note works for a tester who installed the app today: its plain block is one Nothing to see line and a Try any new tester can do, instead of a Try that sent testers to one person's recording; stories unchanged.

## 2026-11-03 00:33:27 EST — scribe `a4a129a4ae76e9685bd1a0534896aa3706a409f7`
Feature (#1621): spotter, the CLI in Homebrew, downloads Scribe's speech models in its setup (832 MB, shared with Scribe for Mac's copy) and transcribes a file on the Mac through spotter-speech, a helper built from TranscriptionEngine; the publisher ships it as its own archive. A clean home on the Mac mini reached its first transcript in 159.9 s.

## 2026-11-02 23:58:21 EST — scribe `6c77f6124c05f87f80601eebc7214f4b6260beda`
Feature (#1050): the card an agent's answer carries is drawn under it with its idea's moments, read live; cut Scribe 0.1 (233).

## 2026-11-02 23:47:54 EST — scribe `fc30632617e382e5f84f10243e64b7ba150bed86`
Feature (#1204): Scribe Playback fills the iPad's screen (a full-screen cover where a sheet would be a form sheet, the iPhone's sheet unchanged), its lines in one centered reading column of about 100 characters; landed in 5ec7e4016.

## 2026-11-02 22:58:25 EST — scribe `6d08acd7b7888a83e6ebdb47d556890ec43b34db`
Fix (#1619): the recording catalog worker queues a just-finished copy's last stretch at once (Recording 349's waited 86.6 s for the listing), checks every 15 s, downloads four at a time, logs every value a memory hold tested, and its installer waits for launchd to let the old job go (error 5 left it unloaded). Change log 40d20da40.

## 2026-11-02 22:52:14 EST — scribe `4dcde02577206bda64ef0b9b0c31538edd91f30d`
Fix (#1643): route evidence counts a session as having received the spoken words only when the session log marks them typed by a person (origin human, outside a claude -p run); a headless run's prompt, a scheduled prompt, another session's message and a compaction summary no longer count. On one evening's recording, lines naming a session went from 1,114 of 1,281 (1,089 of them the 5-minute sweep's own runs) to 4 of 1,291, all real; the sweep's open lines carrying the false evidence from 1,031 of 1,129 to 1. Installed in the mirror's app folder (discover.ts).

## 2026-11-02 22:15:00 EST — scribe `cc4e8a69423d76458c535cbad1286b267eb86259`
Feature (#1619): the recording catalog on the mini runs from a durable job queue (one SQLite file, one job per recording, a recording being recorded first, retries at 1, 5, 30 min, 2 h, daily, resumed after a stop) with a kept-alive worker that queues recordings being recorded every 30 s and signs them again a minute of audio and 90 s on; the copy is decoded a window at a time; the mini's 2 GB memory rule. Before: passes grew from 15 s to 448 s over 71 minutes of live Recording 349. Change log 97da816be.

## 2026-11-02 22:12:06 EST — scribe `a3791376b9ccbf9881f42b2bf948362c39c877fd`
Feature (#1299): FEATURES item 24 and ADR 0091 amendment C for the words page's live copy; the #1299 privacy test runs the words site's own tests; the copy's rules matrix shows a recording's reader gets none of the copy (30 of 30). Landed a3791376b.

## 2026-11-02 22:12:06 EST — foldkit `d95194b926f19f137e3798d520fff9b1ecf3ca50`
Feature (Scribe #1299): the words page plays a recording while it is still recording, from the phone's compressed copy (Scribe ADR 0091) through Media Source Extensions (ManagedMediaSource in WebKit), only to the recording's owners; it joins 12 s behind the copy's end, measured 24 to 33 s behind the recording's clock in Chrome and WebKit. Commits 7acf2925c to d95194b92, deployed at 22:09.

## 2026-11-02 21:46:39 EST — scribe `c4964b6b3e0fa52d504a6cd40c8a95396227c0b5`
Audit (#1618): the last sections: NOW.md's device line (fixed in 2ef2d3594) and the installed working sync's hourly sweep on 1.18.0 (1,637 issues in 27 s, 4 real changes). Landed 25f8b36c2.

## 2026-11-02 21:38:31 EST — scribe `7d30492cd8ad14f97267d77b9478c4a5a98fecbf`
Fix (#1619): the recording catalog's cache sweep keeps a live recording's compressed copy (it judged caches by chunks.json, which the copy's cache never writes), so each 5-minute pass on the mini stops downloading all of the copy again (Recording 349: 436 of 712 segments re-fetched three minutes into a pass that took 318 s). Change log a9eb80548; landed 920a51b54.

## 2026-11-02 21:29:38 EST — scribe `2ef2d35947a021cf20c502af95c9da7fe7fe36c6`
Fix (#1618): NOW.md's device line also reads the session-health lane, so a device that has no recording open still shows its build (it said iPad 223 and Mac 213 while both ran 232); installed as ~/Scribe/tools/handoff-now. Change log ea4e4e116; landed bade6c3bf.

## 2026-11-02 21:25:28 EST — scribe `d1512ff15ce8503eb327bcea8e8a606e0b08bdbd`
Audit (#1618): claims whose agent is gone and silent for a week are released by the working sync (foldkit c1f2fef26, issues CLI 1.18.0); claims 761 to 28, of agents not running 753 to 13, and no open P0 shows a stale claim. Change log d776ba12f; landed 7545cca5c.

## 2026-11-02 21:25:28 EST — foldkit `c1f2fef263db6fd458813ef9e4049cc9337e6f8a`
Fix (Scribe #1618): the issues CLI's working sync releases a claim whose agent nothing shows running and that wrote nothing on the issue for 7 days, with a line naming its last entry (439 such claims on the live catalog); status and work in progress stay. Installed as issues CLI 1.18.0.

## 2026-11-02 21:08:48 EST — scribe `7ffd3859ddd63bca62ab8cc5328a73b2dc8d108c`
Audit (#1618): the 36 open P0s with no running agent checked read only against build 232, production rows, telemetry and his words: 16 Verified with proof, #969 closed as superseded, 13 PartiallyDone with what is missing, #645 Open, 5 in one Decisions question; open P0s 42 to 25. Change log b813347b4; landed d441cf4a9.

## 2026-11-02 21:08:48 EST — foldkit `63e7290be0d9d8e969b6b921318f2e613c56c83d`
Fix (Scribe #1618): the issues CLI's working sync stops saying agents run when none do: the hourly sweep reads every issue (22 kept "running" for ended runs), a finished issue's claim is released once its agent no longer runs, and a fresh claim is no longer flipped to VerificationNeeded by the last run's landing record (5 times); installed as issues CLI 1.17.0.

## 2026-11-02 20:57:37 EST — scribe `eed350ef57bed681b5a3d7f9c464f4aa6cb41589`
Feature (#1050): a post that names an older recording follows it first, so an answer lands at the line he asked about; the listener's recipe for linking every recording an idea came up in.

## 2026-11-02 20:45:45 EST — scribe `c256b6751064276b95c472ce8e55575ecf41f8d8`
Audit (#1484): TCA 2 and Point-Free's newest episodes read against Scribe and instant-data-swift; spawning bounded at 0.04-0.16% of a core from the phone's ledger; #1622-#1626 filed for Opus 5.5 Max, none claimed.

## 2026-11-02 20:43:50 EST — scribe `fa2534739c9040ee634393cb795b7546d8a3d43e`
Fix (#1573): the clip check's record keeps the mute from before the extra hearings (audio.mutedSeconds.beforeRehearings) and its log lines say how many ran and how much they muted; before, what they added to a broadcast could only be bounded (at least 19.25 s of Recording 343's 215 s). Installed on the mini (scrubber and private stream service), rollback install.sh --rollback 20261102-204047.

## 2026-11-02 20:39:11 EST — scribe `6f59c24cb4c73a53e2eb248385bff748eec73b02`
Feature (#1050): scribe sources add links an idea's moments in any recording, one moment per stretch; older recordings are read from their transcript files.

## 2026-11-02 20:33:49 EST — scribe `9399fc419fc0c69b88c2347d3c6fa2d6c3103bb3`
Test (#1573): the clip that goes out is silent where the muted clip still said a word, padded as every mute is, and a last hearing still not clean uploads nothing (red on the pre-fix code and three throwaway changes); the audio check in real use since its install: 7 of 7 passed, the two broadcasts since went up by themselves, digital zero inside every mute range.

## 2026-11-02 15:38:36 EST — scribe `abb92d41b945a77d28298c993bc508e83a5c3d63`
Fix (#1460): the real cause of the Your Mac drops: build 222's ping timer slept with try?, so the pong's cancel() woke it into "unanswered"; now it returns when cancelled (a copy of the shipped code: 110 of 2,000 answered pings reported unanswered, fixed 0).

## 2026-11-02 14:54:19 EST — scribe `334d1d216d6c4c838ec0245c1e8acb878f388c98`
Fix (#1460): the iPhone reads its Your Mac socket apart from the transcript, from URLSession's own queue (bounded at 1,024 messages), so build 222's 5 s ping check no longer ends a stream whose Mac answered: URLSessionWebSocketTask hands a pong over only when receive() reaches it, and on 2026-11-02 the phone ended 56 of 58 streams while the Mac answered in 0.3 ms.

## 2026-11-02 05:47:13 EST — scribe `f12a111391f647cdf65537800f9bb31529c8a4b6`
Docs (#1530): the flip's audit section and progress: links agents and the issues CLI hand out are og's, installed from main and proved on a real agent reply; the tap on his phone stays open. Change log e337ee726; landed 81e37774e.

## 2026-11-02 05:31:46 EST — scribe `f8dd7619abc1ef6ce42b2d053954fb9663e29f08`
Fix (#1530): the search and videos installers copy links.ts, which the flip's model.ts imports (a hand-written file list lacked it; a scratch copy failed to load without it); both services reinstalled from main and print og links. Plan amendment E 528164576; change log f790e2fdd.

## 2026-11-02 05:26:28 EST — scribe `3d74ab2879ff0161d71c3220f8d2308f9baff418`
Wallet (#1604): one wallet for every device on his iCloud account (14fc7a9b6 reverted; one keychain group for the iPhone and iPad, Mac and Vision Pro apps; the key made first is the wallet, any other an extra account), and one sentence two devices hear signs once, claimed in Instant by two unique keys. ADR 0113 amendment G; walletSendRequests.spokenKeyEven and spokenKeyOdd pushed to production 05:26 EST.

## 2026-11-02 05:19:02 EST — scribe `5a2f3d4442f70c8b1e3836f24d12a198580d4118`
Feature (#1530): the script builders and scribe reply hand out og links, now that his iPhone opens them (build 229): the mirror's commands, scribe search, the videos site, triage import and provenance build every link with links.ts on og.pisspoursoftware.xyz, and a words or issues link an agent typed goes out as its og link. Change log 7929a1882.

## 2026-11-02 05:20:28 EST — scribe `a2542468f20a505d7c13732e3602ade74d139162`
Feature (#1543): his purpose in his own words on the drawer's Purpose page, and a gold star on each line where he says it, live and in playback (ADR 0115).

## 2026-11-02 02:47:08 EST — scribe `5f8da30084ddb31ee4bb037bc61ccb8cceb04e66`
Feature (#1457): Lines, Notes, Photos and Chat at the top of a live recording (design A, round 3); the picture viewer's strip drag selects by its offset; a scroll frame monitor that outlived its screen stops (a 60 Hz display link, older than this work); Scribe 0.1 (229). The build note fix is 93a26179a.

## 2026-11-02 01:53:14 EST — scribe `7cd155188e52e66c8b04bb7d3976c5a210ad7076`
Wallet (#1533): what its first run on a simulator showed: the screen says where the key is, a quote reads a node's refusal to estimate for a wallet that cannot pay as its answer, a slow first activity read is read once more before a banner, and "an Ethereum".

## 2026-11-02 01:16:47 EST — scribe `2c1300ae372b72594246f6fcca80d37164b4165c`
Fix (#1599): build 227's plain note fits the 30 words a line.

## 2026-11-02 01:15:50 EST — scribe `64feaeda8eb2c09a2d5d63a5fa6024824b73ecfc`
Cut (#1599): Scribe 0.1 (227): a link opens the Playground on one session, design, variant or attempt.

## 2026-11-02 01:15:19 EST — scribe `88e2e9b0ee62bb4b85e256063f62183c86cadcc8`
Feature (#1599): a link opens Scribe on a Playground session, design, variant or attempt, over any screen, through the reads its screens already make.

## 2026-11-01 23:04:04 EST — scribe `f9e335c750140efb37cb785e5eb4dac638bb39ee`
Fix (#1576): spotter no longer runs code from the folder it starts in: Bun's autoloads off, a release stops if they come back, and the installer runs an old copy from the root.

## 2026-11-01 22:29:31 EST — scribe `42bdd3d8bf3d5909d1ec2b7215e36cd87c7485b1`
Feature (#1599): the Playground's link on og and in the site files, scribe design prints it, and spotter's formula names its version.

## 2026-11-01 22:08:58 EST — scribe `a7681612d7eebb832516bfeb37183682cc91139e`
Fix (#1576): spotter's onboarding: help on every command, commands that run as printed, the Home Screen hint, the download on free static files with GitHub second, and /install pinned to its release.

## 2026-11-02 00:48:49 EST — scribe `2d99c2faf5c28283495a6183155aa27170b14fc2`
Fix (#1604): a device restores only a wallet key its own kind of device backed up, so his iPad keeps its own wallet (or none) and one spoken send heard by both devices can never pay twice from one wallet; a new iPhone still takes the old iPhone's. Red 2e84c33f9, green 14fc7a9b6 (147 package tests); cut as build 226 (8219f50b2). The simslim proof (17792e4b4) held 19 of 19 claims on a simulator's real Keychain.

## 2026-11-02 00:15:40 EST — scribe `3ac36c38a0fa50de784f0c44baf330f43e891ce7`
Docs (#1601): the RE-USE audit timed Apple's Voice Isolation on the same Mac mini (0.0102-0.0106x real time), so RE-USE at 16 kHz is about 60 times as long, not the 40 times a laptop-vs-mini comparison gave; the card and the 5 GB of working copies removed are recorded. Landed in 446f9bee1.

## 2026-11-02 00:12:34 EST — scribe `24b3b2afc3a62daf7b424997842bd485d181439c`
Audit (#1601): NVIDIA NemotronLabs RE-USE (9.6M, OpenMDW-1.1, bidirectional) measured as a speech cleanup option on his audio, with a checked Apple-silicon port (PyTorch + Metal kernels, 4.1e-7 vs NVIDIA's code) and the prototype stage in scripts/speech-cleanup; PESQ 1.28 to 2.55 with no thinner tone, but his own words do not improve, it deletes TV lines and merges speakers, and it costs 0.61x real time on the mini. Proposal: never before the transcriber. Landed in 1f53332ad.

## 2026-11-02 00:00:56 EST — scribe `80ccdf2277508a7a0db826bbcce13ae234b71df6`
Test (#1550): Decisions' reference pictures from the simulator, recorded and repeated on the landed code; an option's cost reads at 7.07:1, from 2.40:1.

## 2026-11-01 23:37:09 EST — scribe `6e44a303efc06cd032ced3403b90d02e02f4c215`
Docs (#1596): the after numbers of the listener's one watch, measured the same way as the before (lines 0.2-0.5 s from the mirror, no empty wakes from the watch, busy ~20M tokens an hour against 65-188M), and the listener's other loops wait as background commands between recordings too.

## 2026-11-01 23:37:09 EST — scribe `95912688971f6c502754aade94f1ed01f9944cb1`
Fix (#1596): in the listener watch a mirror that is only slow wakes no one (it went to stderr); a mirror that is down, and its return, still print. The guide's coverage test is green again.

## 2026-11-01 23:36:10 EST — scribe `c092ab3596df8ede60cf46089e438f0953f48f05`
Feature (#1604): the voice wallet's keys are backed up in iCloud Keychain, end to end encrypted: one synchronizable item per key, named by its address, never updated or deleted; build 223's this-device-only item kept for good; a new phone takes the backed-up key with the same addresses and never makes a second; backed up at every launch and logged per chain. Red 1427e2fd0, green 64e0544df (146 package tests); ADR 0113 amendment E. Cut as build 225 (5a4b69e30).

## 2026-11-01 23:08:28 EST — scribe `bf5ff442e4cc56ad0653d6f70a37228f2a14120e`
Tooling (#1605): agent-run and agent-progress-check, with their tests, now live in scripts/agent-run (imported exactly as installed, a1d1804c4) and reach ~/Scribe/tools only through install.py, which installs a commit on origin/main, records it in agent-run.installed.json, and refuses, naming the file, to write over a copy edited in place. Installed this commit at 22:56: each installed file's sha256 equals the commit's, and both suites pass from the repo and from ~/Scribe/tools.

## 2026-11-01 22:50:28 EST — scribe `5871fe2233704c9f6b727b8277f4c920fe7455b6`
Feature (#1530): plain links say what they are and when, with no words ("Scribe · Claude’s answer · Nov 1, 9:52 pm", "Scribe · Recording 344 · Nov 1 · 48 min", "Scribe · Issue 1530") and an 800x420 picture of the same words, from one facts record per recording of his that the card service keeps within 300 KV writes a day.

## 2026-11-01 22:44:42 EST — scribe `97709ad9c81ac7e0f55624fb4521916cf7bb69cc`
Fix (#1545): the eviction probe rides a public feed; an outbound socket held an object 15 minutes, then it vanished with no close event.

## 2026-11-01 22:22:29 EST — scribe `b7d966e70b4862e77037a846ee45514a72c400a8`
Fix (#478): a held osascript waits out a napping Safari instead of killing it at 30 s, because a kill started macOS's check over and added work for a starved Safari.

## 2026-11-01 22:20:32 EST — scribe `60a685ab1e56b7b3881fa1e11e92f41cc3e8c252`
Measure (#1596): tail_cost.py reads a rotating listener's chain of session files as one (the listener now clears itself into a new session at about 120K tokens), so the before and after of the listener's watch are measured the same way.

## 2026-11-01 22:20:32 EST — scribe `12aaf935a0460f6e18296588d029919a61e63f5f`
Fix (#1596): the daemon's status row says a listener stopped reading, not that its process ended, while that process still runs; on 2026-11-01 at 18:59 it had said process 10675 ended while it ran. Live at the mirror's next start.

## 2026-11-01 22:13:53 EST — scribe `4764dc9455d2ee2535aeeb65cf91bc11f59dc91e`
Feature (#1596): the listener's one watch, `scribe capture watch --mode listener`: every line as it lands (p50 0.09 s after the mirror vs 7.67 s, side by side on 39 lines), his typed messages and photos from every recording in the same stream, its own cursors, evidence through a cache instead of a per-batch scan of every session log, and a wait between recordings that wakes only for something new; push from the file system, not a 500 ms poll; the mirror untouched.

## 2026-11-01 22:08:31 EST — scribe `6c780b7cc8fa76e3e6781073e3303668cc3b3806`
Fix (#478): the YouTube companion's Safari scans share one held osascript, and a failure line says Safari's priority and the load. App Nap keeps a Safari not in front at priority 4, and build load starves that band; the grant was fine since 10-04.

## 2026-11-01 21:52:29 EST — scribe `e51dba1e046af7d3f67374aad5d5f74b1e3b2ab1`
Feature (#1598): the listener clears and rereads at 120K tokens instead of growing to 966K, with a lease so there is never a second listener.

## 2026-11-01 21:52:12 EST — scribe `e17b711b261231a99b9fb7939bc15fb6bd64fba5`
Feature (#1530): every link the app hands out is on og.pisspoursoftware.xyz, a share's link waits on the privacy check and its preview, and an og link opens the app at its moment, proved on an iOS simulator.

## 2026-11-01 21:49:21 EST — scribe `b77eaf271fab5be875026530f8055d12ea43102a`
Link previews (#1530): words and issues links preview through og: one Cloudflare redirect rule, which runs before Access, sends only link-preview fetchers with no Access cookie to the same page on og, so Messages reads "Scribe" or a share's scrubbed quote instead of the Access sign-in.

## 2026-11-01 21:44:34 EST — scribe `72662f2fa96099a9da7877190fdcf56e98c6bdc2`
Fix (#1576): the release tool reads the publisher's own sign-in by name, which neither uses nor changes the active account, so the next release needs no new sign-in; the Homebrew formula drops a redundant version line and passes brew audit; the audit records what went public and what is not yet proven.

## 2026-11-01 21:26:47 EST — scribe `897e20b0dee0cc2610bfd16db47ebc2db7ad0e44`
Fix (#1576): a public release runs on Macs older than the build machine and one commit builds identical bytes: the Apple Silicon program comes from the runtime vendor's own build, checked against the registry, instead of the local Homebrew copy (minimum macOS 13.0, not 26.0), a release stops above that floor, and the archive holds no time.

## 2026-11-01 21:40:52 EST — scribe `7cb8df400b51ebd8d1b6dbe2c04034879eb2956f`
Fix (#1597): the mirror stamps the agent rows it carries over or closes a millisecond before the beat, so a new recording's live agents rank first in At work's 60 freshest rows (a heartbeat tie, broken by entity id, had kept 2 of 16 in).

## 2026-11-01 21:37:40 EST — scribe `317af746e7028e7d1324387fb9073b50831d024c`
Fix (#1597): the mirror's agent rows retry a write with no answer at the next beat instead of in 10 minutes, 20 rows a transaction, live first, keeping what landed; a new recording's one 154-row transaction had passed the 5 s bound 27 times since 2026-10-17, 263 minutes of a stale At work.

## 2026-11-01 21:38:26 EST — scribe `173be4ee4820c1d67ce7741664a5c42189a8618b`
Wallet (#1533): send money by voice, a wallet in the drawer and the terminal, addresses and emoji on named speakers; the wallet reads the line the recording kept, so one spoken sentence pays once.

## 2026-11-01 20:39:39 EST — scribe `578b8b5ed8b2e06e80cd12f2651b3e09a3620487`
Feature (#1550): Decisions in the drawer: everything waiting on his answer, drawn by native SwiftUI from typed rows, answered in one tap; the app's write goes through the Instant client in one transaction, and a live test proves it through the real rules.

## 2026-11-01 19:15:08 EST — scribe `1f97f77570301a0ea08969520c09924de756bbc1`
Feature (#1235): the iPhone's live stream to Your Mac travels as Opus, AudioToolbox's on both ends, at 48 kHz and 50 kbps (about 20 MB an hour instead of 345.6; gold WER +0.20, AMI -0.11, voice prints within 0.008), fed as Float32 so nothing waits past a capture buffer; the server takes encoding=opus and keeps linear16; each KeepAlive pings the Mac and no pong in 5 s ends the stream. Server 34bb4754f deployed on the mini.

## 2026-11-01 19:08:37 EST — scribe `ba33e02af003fd4fef0ff2f75b005284725a4da5`
Fix (#1535): InstantBuildNotes lists the 8 attributes #1538 added to builds, so the schema-match test passes again (landed in e9761a6aa).

## 2026-11-01 18:51:07 EST — scribe `f67df399fd5e2b3229a21881bab5907110ffd8ec`
Fix (#1588): a short clip's library item, made before its words and with no show, is written with its show before its link to the show; Instant checks a link from a row that exists against both rows as they were before the transaction, so the words of three short videos from new channels had never landed (landed in 31824f780).

## 2026-11-01 18:46:24 EST — scribe `e83af706a24c253928fcf8e5b7ddd64014f29852`
Docs (#1588): ADR 0123 amendment A and one sentence on FEATURES item 36: an uploaded broadcast plays inside Scribe Playback, still unlisted (landed in 57e15c6aa).

## 2026-11-01 18:32:59 EST — scribe `c5c4395bee3a82327025a0e191064e1289d93b06`
Fix (#1588): uploaded broadcasts are embeddable, through one status part for the upload and the takedown, so they play in Scribe Playback's YouTube player; privacy stays unlisted (landed in 57e15c6aa).

## 2026-11-01 18:38:05 EST — scribe `53432385b1820ba2692813b9f4f20ecf7b03a592`
Feature (#1576): spotter's publisher can push to GitHub, but only as the PissPour account, from its own gh folder or a token he made; never this Mac's usual login, through which every agent pushes Scribe. Tag, release files, then main, then the tap; it refuses a public history that names anyone else (landed in 44ed59d84).

## 2026-11-01 18:30:12 EST — scribe `08d499efca083f15a89695212454e1a54dd0be24`
Feature (#1576): spotter's page and install redirect as a Worker with no binding and no fetch, deployed so the public bypass is created only after the name points at the Worker, and a before/after of every setting and name a stranger can reach (landed in d2822f37d).

## 2026-11-01 18:24:47 EST — scribe `fab90b90ba4b58b5cd22db5442936f93e252404f`
Rename (#1576): the watcher prototype is spotter, his name for it; every name in one file, and answers' ids under a namespace that never follows a later rename (landed in d2822f37d).

## 2026-11-01 18:32:17 EST — scribe `8f77f3c6ed65d8a9c3fc1065fefcadba4db29ed7`
Fix (#1538): an agent's files start the agents graph sync alone (com.scribe.graph-sync-agents, about 2 s of CPU a run) and origin/main starts the full one; a run that finds the other's lock waits up to 2 minutes instead of skipping its change. One job watching everything had run back to back at 6 s of CPU a run (landed in 6b43b0ae8).

## 2026-11-01 18:20:43 EST — scribe `5257187d5659d878e6a75957bd218b24441d81c5`
Docs (#1538): the issues site audit and ADR 0121 section 9 record what the adversarial review proved and what was fixed: Issue writes name the read they were based on, and no Instant rule is a lock (landed in ba4c6390c).

## 2026-11-01 18:20:43 EST — scribe `c85e5e641045ac022e520f2737dad4331123eb4e`
Feature (#1538): graph rows start when a file their syncs read changes (launchd WatchPaths), not only every 5 minutes; findings in work logs and the product catalog still wait for the 5-minute run (landed in ba4c6390c).

## 2026-11-01 18:20:36 EST — scribe `5d4c6f61d841df6c08ff162f3339c3ff71571d06`
Fix (#1586): a name nothing serves on pisspoursoftware.xyz or knophy.com answers a small PissPour Software page, "This name is not set up yet", still 404, instead of "unknown knophy host" (the Mac mini router's catch-all, router commit 720cebd; the sweep's fixture carries it; landed in 520c8e22f).

## 2026-11-01 17:54:53 EST — scribe `fdb62c378e97c9216f813850173497e75b10bd0c`
The watcher (#1576): a tool anyone can install to follow and answer their own recording with their own sign-in, on main as a prototype; a snapshot publisher that keeps this repository's history out of the public one; nothing published.

## 2026-11-01 17:43:10 EST — scribe `1d751a0974f9e845cc4da04434c7c1edb7dc3723`
Docs (#1578): the iPhone Duo layouts audit, each of his friend's build 217 screenshots read against the code, and 28 ASCII designs for every pose posted to the Playground for his pick; no app code changed.

## 2026-11-01 17:34:31 EST — scribe `91d64379c13b6a99164fc451605be1f5288db1e4`
Release (#1482, #1528, #1536): Scribe 0.1 (221) cut; testers' first recordings stop showing Not Synced (a fencepost waits up to a minute for its recording's row) and a new person's Vocabulary starts empty.

## 2026-11-01 17:34:31 EST — scribe `573ece144ae0cfda378257d199a4603daecd0034`
Fix (#1482, #1538): landings lists its ids in bounded pages, so the upload's own landings run finishes at high load (it timed out on 219 and 220).

## 2026-11-01 17:28:30 EST — scribe `84316ed9bfaa82762553da09747dc8184bcc250e`
Feature (#1577): recording_frames.py puts a screen recording's frames into one of his recordings as screen frames at their times; TJ's call video is 720 frames of Watch Voice Memo 441, aligned by TJ's on-screen clock since the video has no sound (landed in 194ae1c89).

## 2026-11-01 17:09:48 EST — scribe `c3806fe02e831bb8891ff2cb8ec7e9e287f24efd`
Fix (#1535): What's New reads Instant's list on the Mac too: the Mac's own composition root never set the reader, so build 219's Mac app showed its bundled file and said nothing (landed in 616919d01).

## 2026-11-01 17:09:48 EST — scribe `7cd843bbfefcedd5280abd284fd1f5f42bff1cf1`
Fix (#1535): an upload failure that wrote nothing says how it ended: build 219's first export was killed in the queue and journaled an empty reason (landed in 616919d01).

## 2026-11-01 16:17:24 EST — scribe `249dc8508059b4ac6235fd57e3cb7d8716d5f402`
Fix (#1536): a fencepost waits up to a minute, since a first recording's row waits on the permission prompts.

## 2026-11-01 15:09:22 EST — scribe `dd1fe9d680fd989091d3fbbd74f25eb6b2c16c32`
Fix (#1536): a fencepost waits for its recording's row, so a tester's recording stops reading "Not Synced".

## 2026-11-01 15:09:22 EST — scribe `a46dbb0339426f87029668db17cc0557b65a3337`
Fix (#1536): a person with no list starts with no words, so nobody's family or developer words are anyone's default.

## 2026-11-01 15:09:22 EST — scribe `e1728726b7609e9994d83b3808b46102cb0d43db`
Fix (#1536): transcriptions and transcriptionWords take the recording-child rule, so nobody but a recording's owners and shared writers writes them.

## 2026-11-01 15:00:48 EST — scribe `e2112b43a743770eb5efb35602ef7ca197303f1c`
Release (#1482, #1528): Scribe 0.1 (220), the first TestFlight upload started by the install itself (from the iPad, the iPhone away); VALID, Internal and Friends, note guarded; 219's clearer notes bundled.

## 2026-11-01 14:26:13 EST — scribe `7d907c39620e31f63cba6f6ffd7b8cd403691c65`
Feature (#1559, #1573): when a broadcast ends, the Mac uploads its scrubbed frames and sound to his YouTube channel unlisted, with every line deep linked, captions and the link back in Scribe; only the one picture plan's scrub counts; the audio check mutes what it heard and hears again. Proved on his newest broadcast.

## 2026-11-01 13:18:38 EST — scribe `b065ff541`
Feature (#1565): one picture path for shares and the private stream; a screen shows only what a rule let through, the output is read again, and scribe stream private shows his broadcast on the Mac mini to him alone.

## 2026-11-01 13:12:20 EST — scribe `a495cf9b12b09f270e37abce6b1e8aee2132f728`
Fix (#1482, #1528): with the iPhone away from a whole run, the iPad's install starts the TestFlight upload and What's New, so a phone off home Wi-Fi never holds testers.

## 2026-11-01 12:54:52 EST — scribe `824dfda4918a5662dac9cda5b92033b05b66a1d1`
Fix (#1528): the TestFlight export runs in the release lane, so it no longer waits in the shared queue.

## 2026-11-01 12:54:03 EST — scribe `e5519a536bea3416a88dabdfda12299a97f63274`
Docs (#1566): the publishing skill follows his decisions on public routes and shares.

## 2026-11-01 12:49:17 EST — scribe `ad5358af91e98fdd59dc8dd6e83b1d051557e348`
Feature (#1566): scribe-publish, a skill that turns his lines into a post, a thread and audio with gaps proved silent, public only on his go for that exact draft and only under PissPour Software accounts.

## 2026-11-01 12:50:39 EST — scribe `64a8e05f5b5fc4533b8d2400c4774cf0dacc2ce9`
Docs (#1535): build 219's TestFlight note reworded after three cold reads, the audit's correction that 219 carries the scrub, and Instant's whole list of 129 sections (landed in 63b6803d3).

## 2026-11-01 12:38:07 EST — scribe `bdaa25573039e08b907ab1cb4b8f40ac89b7522c`
Fix (#1545): the chain listener hears Solana through Vibe Station, a canary catches a deaf socket, a 10-minute read backs up the push, and backfill stops at its cursor without until.

## 2026-11-01 12:26:21 EST — scribe `afd28dc3ca295ceddd27d6b9844a854be17475d7`
Docs (#1546): pass 4 on what the fixes broke: 42 findings applied, no fake authority, onboarding paths hold for agents, companies and minors (landed in 0e977b6c5).

## 2026-11-01 12:06:31 EST — scribe `0b743fde8fc2794bee4e6285fa5c287f43a9f067`
Fix (#1536): an account may write and read the fenceposts of a recording it owns, so a tester's recording stops reading "Not synced".

## 2026-11-01 12:06:31 EST — scribe `745946612c78015b2196602dd8413d3cb73cd21d`
Fix (#1536): only his identities append to Brandon dot's open log.

## 2026-11-01 12:06:31 EST — scribe `3c8fcc74bc85cd795d993f72c3edefe0b8a41a47`
Fix (#1536): a refused microphone stops with the Settings notice instead of retrying forever.

## 2026-11-01 12:06:31 EST — scribe `f968600706dcf156be054533789cb9a249b117fd`
Fix (#1536): the follow-along keeps a room feed's row only when it names the followed recording.

## 2026-11-01 12:06:31 EST — scribe `1862112ff209724033c51ac7bd1e461f311e0ed3`
Fix (#1536): a device with no account keeps asking for one until it has it, so a first launch with no network recovers.

## 2026-11-01 12:00:23 EST — scribe `7dc6196d6ac5938b229d00173afa59012e947267`
Docs (#1546): adversarial pass 3 on the final text: 176 findings applied, no fake authority, 340 authorities cited, 36 questions with age and consent before anything is kept (landed in d27f2b264).

## 2026-11-01 12:00:23 EST — scribe `e0eae438501cacaa4dc026bc742215d274cba09e`
Docs (#1546): a final read against the brief: 18 authorities added or newly cited (landed in d27f2b264).

## 2026-11-01 11:57:08 EST — scribe `4082fa869d9813fffeb4ae2d1942d73a4e64ed1c`
Fix (#1535): WHATS-NEW.md ships in every copy of the app, so no story names a private person, and the cut reads every line for an address or a name from the private mapping, refusing by line without saying the word (landed in b452c5ce6, with build 219 and 205 plain-note wording).

## 2026-11-01 11:20:21 EST — scribe `d815a790eaa5`
Fix (#1482, #1528): production builds with the released Xcode whatever the caller set; the upload refuses a beta's app before it leaves the Mac, so no number is used.

## 2026-11-01 11:20:21 EST — scribe `8e57ba98276c`
Cut (#1482, #1528): Scribe 0.1 (219), the first build from the install lane with the released Xcode.

## 2026-11-01 11:20:09 EST — scribe `d7a53eedd32bd7cd9185ea322c0ae23f9e50eb68`
Docs (#1535): the plain build notes reworded after a stranger's reading (1 clear of 15 before, 5 after, all 15 say what to look for), the rules and the cut's refusal say what it taught, and the audit says why build 218 never reached TestFlight.

## 2026-11-01 10:58:01 EST — scribe `137035fa1349292152bee363135edec22467167b`
Docs (#1546): adversarial pass 2 applied: one lawful-as-possible forfeit design, 70 authority fixes, 167 sentence fixes, #1549's market read against the memo (landed in 46cad73ec).

## 2026-11-01 10:58:01 EST — scribe `4b7b808ca88cdf4edd1ef39441c40e7e5c486792`
Docs (#1546): first reviewer fixes; every onboarding question says why, what a no does, and how it is recorded (landed in 46cad73ec).

## 2026-11-01 10:58:01 EST — scribe `416048a3dea4062da134b0ff7fc977fbf77ebf9c`
Docs (#1546): ELI5 names the law behind each worry; a stake is a pledge, never a "bond" (landed in 46cad73ec).

## 2026-11-01 10:58:01 EST — scribe `582af9a7d7d09a3993ab28f5188065672cee2805`
Docs (#1546): legal memo, onboarding, rules draft and ELI5, with 296 verified authorities (checkpoint before adversarial pass 2) (landed in 46cad73ec).

## 2026-11-01 10:58:01 EST — scribe `3cce1ee10b27699b02e8b3719d7babad72888252`
Feature (#1546): legal. site: an authority cited for several points shows each pinpoint, quote and use (green) (landed in 46cad73ec).

## 2026-11-01 10:58:01 EST — scribe `e36679e0f8094b9dc84de4c83eff835ec46129a0`
Test (#1546): legal. site: an authority cited for several points shows each pinpoint, quote and use (red) (landed in 46cad73ec).

## 2026-11-01 10:58:01 EST — scribe `cc6bbbed8a97cd1850348ae85b5aac156dedaee4`
Feature (#1546): legal. site: a citation placeholder left in a page stops the build (green) (landed in 46cad73ec).

## 2026-11-01 10:58:01 EST — scribe `8e0f11c1e5e45106843602ac831f94f7a5d766d0`
Test (#1546): legal. site: a citation placeholder left in a page stops the build (red); docs/legal README (landed in 46cad73ec).

## 2026-11-01 10:58:01 EST — scribe `76003966ae9606723757fa111a6765eae3a5c984`
Feature (#1546): legal. site: links to a missing section or page stop the build (green) (landed in 46cad73ec).

## 2026-11-01 10:58:01 EST — scribe `09e78b889fba5547f5fe3aba0ad8761a02bf9a64`
Test (#1546): legal. site: a link to a missing section or page stops the build (red); deploy script and README (landed in 46cad73ec).

## 2026-11-01 10:58:01 EST — scribe `64661219c3850ddf4d1b3ffe41acb43e8e1c0ffd`
Feature (#1546): legal. site builder and loopback server (green) (landed in 46cad73ec).

## 2026-11-01 10:58:01 EST — scribe `58cef87a79f28c41d64da9a648c399af65f6186b`
Test (#1546): legal. site: the source header, the draft notice on every page, references, privacy stops and the loopback server (red) (landed in 46cad73ec).

## 2026-11-01 10:53:23 EST — scribe `875dbd7bdbb4663b6f9c1b253c1f7e93ad049a96`
Fix (#1536): a companion request names a recording its writer owns, so no stranger can put one into his follow-along's feed.

## 2026-11-01 10:52:43 EST — scribe `ca8ba1d6745f0031a5ab24d47bc4b4bec98edf16`
Merge (#1530): scribe share shares lines in one action (the app's own row, a named state for every wait, the card the moment it passes, the og link; no link for a share that cannot pass), proved on 10 of his real lines (family names, the client's name, addresses, a phone number, spoken emails all scrubbed); a guard on protected links in scripts; the audit.

## 2026-11-01 10:47:31 EST — scribe `6d4a095503889540d112f1d73cb91bc4dc7d2783`
Docs (#1544): scribe-agent-faq's open questions quote his 08:53 word sending securities and betting to the law agent (#1546); the classification still waits for its memo and his ruling.

## 2026-11-01 10:43:15 EST — scribe `5e345d87888d41f6a839771ad4a1cda1eedc5df5`
Fix (#1542): the emoji sale's Solana memo is 24 hex characters, because the old memo cost 36,695 compute units where the reference x402 client gives a whole payment 20,000; proved end to end on a local validator (agent and person, one transfer of exactly 14280000 per sale) and redeployed.

## 2026-11-01 10:41:24 EST — scribe `0e84e9f67dd771fbae0cbd993dd08ce925989ac3`
Fix (#1535): the cut's What's New check refuses the cut cleanly when it hangs instead of raising a traceback, and its 30 s bound carries its measured reason (0.25 to 2.1 s at load 230-270 under utility QoS and nice 10) (landed in 30e0c16fc).

## 2026-11-01 10:40:03 EST — scribe `985fd2a35d0235959ff7378dd8f8d31bf01dfb64`
Decisions (#1550, ADR 0118): no agent changes what he decided. A doubt is a question for him with his words, argued against by an independent model first; one list of what waits on his answer (the asks entity, live in production), one notice carrying its question id, his answer applied in his words, and a forged tap changes nothing.

## 2026-11-01 10:30:11 EST — scribe `01c49b76033f246765c33fcc03a4ef966b09757d`
Fix (#1536): a recording's lines, lines in progress and attachments are written only by its owner set and shared writers; any signed-in account could write them under another person's recording id.

## 2026-11-01 10:34:02 EST — scribe `91560bc823652e1dc5898ebd8ac23e36371d6b8a`
Merge (#1530): og.pisspoursoftware.xyz carries every protected words, tracker and books path with a wordless card; his passed shares are public scrubbed pages (indexed, sitemap, IndexNow, 410 when unshared) kept in step by the card service (a 2 s look, a 10-minute sweep, a second leak check); a sealed line left the page 0.7 s after the seal on the throwaway proof.

## 2026-11-01 10:32:25 EST — scribe `08f9b40becc7243b40adf53567105b5513b291d4`
Merge (#1551): the Vakyume install page drafted behind Cloudflare Access at vakyume.pisspoursoftware.xyz (a KeepAlive page server on the mini, his login only; the #1547 header sweep passes; nothing public); implementation 385ef98c0.

## 2026-11-01 10:29:20 EST — scribe `d731041f717bf2963f90d9b0ea481811aefc5d2e`
Merge (#1551): why a stranger installs Vakyume ("did you say that?", from the Halloween party's own words), the first run walked from the TestFlight link (3 to 6 minutes, estimated), a draft install page with the #1547 header, and Health's heart-rate sheet skipped on an iPhone with no Apple Watch paired (red then green on the mini; What's New 219); implementation def69348c, 29f1d0ad4, baa91b482, 0759940c7.

## 2026-11-01 10:24:38 EST — scribe `a703524c47a710627bac8472c05f6024880d3829`
Feature (#1542): sell an emoji for exactly $14.28 over x402 from a Cloudflare Worker (devnet and Base Sepolia; mainnet shut), the emoji schema in production, and a reconciler that writes each sale to Instant only after its own chain read; 512e43550 lands its lazy schema import.

## 2026-11-01 10:19:40 EST — scribe `3c1225ac824a07edde2e90549afc46e4caf24392`
Merge (#1549): proof of now landed on main: Scribe's recursive frames as a protocol a stranger can check (ADR 0117, docs/proof-of-now/, scripts/proof-of-now/, 48 tests); no app code, schema or FEATURES.md change.

## 2026-11-01 10:18:19 EST — scribe `19976dae220c8ffe815ef3768c75edf8ebcc3591`
Docs (#1549): ADR 0117 and the pon/0 format: spec, threat model as eight user stories, challenges ranked, a live game end to end, the market (design only), and the audit of every measurement (landed in 3c1225ac8).

## 2026-11-01 10:12:10 EST — scribe `cc88a59c1dc3d3dd3b663455d4f33bca1d440c64`
Fix (#1549): rung 4 only from a checked App Attest attestation and an assertion over every link; the first checker read the bundle's own attested flag (landed in 3c1225ac8).

## 2026-11-01 10:08:56 EST — scribe `c8176e13866c4499a6a328060458e4b720d4f4b3`
Feature (#1549): witnesses cite each other's real links both ways, and a market's window policy fails a late commit by name (landed in 3c1225ac8).

## 2026-11-01 10:05:17 EST — scribe `79aef277a922617e2e9dd5d23a2cb6fa7aa494be`
Feature (#1549): a public run, frames drawn with Solana mainnet blocks (read only) and batches logged in Sigstore's staging Rekor, passes a stranger's checker at rung 3 (landed in 3c1225ac8).

## 2026-11-01 10:00:55 EST — scribe `bc0cbee0a57fa8fdd440922f90e237905f6634fe`
Feature (#1549): a transparency log as the public commit (Rekor entries checked offline against the pinned key) and moments on two clocks (landed in 3c1225ac8).

## 2026-11-01 09:56:01 EST — scribe `dea0d3c2a0c833843dd51a280cebb1b2c216db44`
Feature (#1549): a recording's audio clock through its capture gaps, and two witnesses of one room measured (audio r 0.964, words 93.2%, against low controls) (landed in 3c1225ac8).

## 2026-11-01 09:35:04 EST — scribe `9ed80484bd7744d97d823d9fc84ad18c23823b92`
Feature (#1549): App Attest checked offline with Node crypto only; Apple's sample attestation verifies at its own time against the pinned root (landed in 3c1225ac8).

## 2026-11-01 09:31:30 EST — scribe `cf7073a74acfadd4340d78638ab436316b47ceba`
Feature (#1549): verify a whole moment, the stranger's CLI, and a live interlock run (landed in 3c1225ac8).

## 2026-11-01 09:27:56 EST — scribe `02a79287818ac2a4d628154aa9b9bcd1de1b71a8`
Feature (#1549): Solana as the public clock: the newest block as the beacon, a hand-built memo as the commit, mainnet writes refused (landed in 3c1225ac8).

## 2026-11-01 09:26:08 EST — scribe `0922ff3eed7a4082de261c66732c6acc125cfaa2`
Feature (#1549): the coded border measured on Recording 337's 144 real frames: a 2 px ring reads back with 0 errors (landed in 3c1225ac8).

## 2026-11-01 09:16:22 EST — scribe `9715ca5eb150119c69f655f0e6c4d456bb43f30b`
Feature (#1549): the coded border, a 256-bit challenge as a ring of colored cells (landed in 3c1225ac8).

## 2026-11-01 09:14:59 EST — scribe `2c3ff5a53bf30b66e79f9705e5675d970bfc89c9`
Feature (#1549): Recording 337's real frames chained and attacked seven ways, each caught (landed in 3c1225ac8).

## 2026-11-01 09:12:46 EST — scribe `12d09152db932425cd8fad0158869f09bd2b8a9d`
Feature (#1549): the proof-of-now core: links, chain, RFC 9162 Merkle, commit-reveal, color challenge, interlock, confidence ladder (landed in 3c1225ac8).

## 2026-11-01 10:12:43 EST — scribe `3a138d9cb066626c7cfd4bdf1886bbaa270fc12a`
Docs (#1544): scribe-agent-faq's filing step says to give every --segment line its recording (a bare line is read in the live recording, #1553) and that unlabeled or "speaker N" lines need --voice-reading.

## 2026-11-01 10:09:43 EST — scribe `44b7197a91906a8c7591fb3b5d7d380931936e9b`
Fix (#1544): scribe faq finds an entry by its key: agents copy keys from the list and the pre-plan pointer, and the BM25 scorer read a hyphenated key as one word no entry holds.

## 2026-11-01 09:18:31 EST — scribe `c40c14475468badd8ece3a234618b03fbe085bd8`
Fix (#1544): scribe faq names its reader the way the mirror's socket accepts (1 to 40 letters, digits, spaces, dots, dashes).

## 2026-11-01 09:17:41 EST — scribe `e9058629ad185e2d0ee8fdf9f96c04568b8ef3f3`
Docs (#1544): the scribe-agent-faq skill, the core guide's "Look here first" pointer, ADR 0116 (the FAQ derived from the decision log and the feedback store, readings in the row's note, no schema push), his words in the feedback history.

## 2026-11-01 09:13:03 EST — scribe `459d3dd0c07d0ae4a7ba2bf6f650032d3a7c830f`
Feature (#1544): scribe faq, the agent FAQ: what agents flag to Michael and how he answered, read from the decision log and the feedback store (ask, list, show, add, check, export); the 5-minute round writes ~/Scribe/faq/index.md; pre-plan verdicts end with the consult line.

## 2026-11-01 10:13:10 EST — scribe `4bf299df7242644389840ae6abba94812ae1ef11`
Fix (#1545): the Durable Object chain listener keeps one reconnect pending per network (heartbeats and failures had multiplied retry chains against providers refusing Cloudflare egress) and no longer hears a socket it dropped (landed in 719596202).

## 2026-11-01 10:11:15 EST — scribe `2b865af3418857770baafd06430b025126000bac`
Docs (#1535): build 218's TestFlight Try works for a tester with no recordings yet ("Open a recording, or record for a minute and stop"), and the build skill's rule says a Try must (landed in e4ceba0ec).

## 2026-11-01 10:11:15 EST — scribe `837fbdf3081cffc07f3f6172cb4fe067e914b6a6`
Docs (#1535): the plain-block rules in scribe-builds and scribe-install, the audit of why the TestFlight page showed build 3's note on 217.1 (a stale page; App Store Connect held 217.1's own), and ADR 0064 section 3's generated file withdrawn by ADR 0114 (landed in c8bedfede).

## 2026-11-01 10:11:15 EST — scribe `01311d61abce03bc52a24be4770ffc562ed51043`
Feature (#1535): every build's plain block in WHATS-NEW.md (what a tester sees, or that nothing looks different, and what to try), required at the cut before compiling from build 218; TestFlight's What to Test from it as "Vakyume build N" after a guard against names, emails, addresses, links and issue numbers; Instant's copy on builds.whatsNewJSON, shown by What's New over the bundled file (landed in c8bedfede).

## 2026-11-01 10:11:15 EST — scribe `0a15afc96211597407acc20f5e81c63a77ccd4fe`
Test (#1535): red: a build's plain note in WhatsNewCore, its copy in Instant, and What's New's list of both (landed in c8bedfede).

## 2026-11-01 09:58:53 EST — foldkit `1e8c5473558e1e8c93a4b1dd7cb7cf8416a8f65b`
Feature (#1547): siteSourceHeader() on technoplato/foldkit main: books and casino name where their code lives in their first line, and their READMEs link back; casino's live pages carry the line.

## 2026-11-01 09:58:53 EST — scribe `b3c8b90228f31637612309dc7c1dc83e831da8b0`
Fix (#1547): the daily site-headers sweep runs under launchd (tunnels from plists, children at application policy, a slow gh read retried once and never read as a missing README); 4 sites pass, issues. pending #1538 (landed in 93248126a and fae2a5ae4).

## 2026-11-01 09:55:55 EST — scribe `5d2e851075959fb57bbf938cdffa6654715e8a53`
Fix (#1545): the Durable Object chain listener backs off properly from providers that refuse Cloudflare egress: one backfill retry per address, and the reconnect backoff starts over only after a socket holds its subscriptions 60 s (it had opened 209 sockets in 20 minutes) (landed in d12bcce76).

## 2026-11-01 09:51:15 EST — scribe `11c4583b209c66dbd052b9128a1a3eb41cc111e9`
Fix (#1545): the chain listener makes a Solana subscription again when publicnode ends it ("Subscription timed out") and backfills that address from its cursor; Ethereum reconnects. The code the 24-hour run measures (landed in 4ec1d95d1).

## 2026-11-01 09:31:33 EST — scribe `2236752e7d0870a452776f31894698d1ee580770`
Test (#1545): a Durable Object as the always-on chain listener, first pass: its own Worker (scribe-chain-do) and the same listener on the mini; an always-on object is billed 60 s a minute (11,059 GB-s of 13,000 a day), deploys reach it after 300 s, the Solana Foundation RPC answers Workers 403 and publicnode rate-limits them; ten live defects fixed; 24-hour run under way.

## 2026-11-01 09:19:00 EST — scribe `7c5306015199118793e0d9dafb0a8c5e7dd77aac`
Schema (#1543): purposes, what he wants his life and work to be, his words or a reading he confirms, owner-only and never deleted; sourceMoments gains the subject purpose and the role wanted, one gold-star moment per line. Pushed to production under his standing approval, drift 0; ADR 0115 (landed in c12fd4b01).

## 2026-11-01 08:50:42 EST — scribe `cada3ce515d42fab56fb90d094b269d073e2b2bd`
Docs (#1537): the audit of reviewing Point-Free's Designing for Isolation episodes (ep380-384) against the pointfree-isolation skill: 16 candidate rules, 16 Swift 6.4 probes, an independent adversarial review; 4 kept, 12 rejected with reasons (landed in 25c6d3ff3).

## 2026-11-01 08:47:57 EST — pointfree-research `dc2dae1f171ff8d71715c4f16d9b0a76bb6478de`
Skill (#1537): pointfree-isolation v2: a Task {} made in a nonisolated(nonsending) function does not inherit the caller's actor (capture isolation: isolated (any Actor)? = #isolation); start a Task.immediate after the state change it shares; store the actor, never an UnownedSerialExecutor; a test of an isolation mechanism needs work that really suspends. pfpipe points preview-only episodes at the full transcripts.

## 2026-11-01 08:42:46 EST — scribe `882efc58c027943ba3d03950e5ccd70fdbf53550`
Fix (#1536): the follow-along's live window asks only for allowlisted owners, so TestFlight testers' recordings cannot push his live one out of its newest eight.

## 2026-11-01 08:41:09 EST — scribe `60d364949dff22feb81398aa39707858c0a8551b`
Feature (#1530): public link previews at og.pisspoursoftware.xyz, a Worker with no secret and no outbound call; cards only from shares the scrubber passed, a generic card otherwise; every other path a bare 404.

## 2026-11-01 08:08:17 EST — scribe `140f665d502d8eba34aeb794c9c610c5be17d001`
Fix (#1536): the media-plays projector catalogs only his owner set's YouTube plays; a TestFlight tester's play no longer downloads into his library.

## 2026-11-01 07:48:31 EST — scribe `47067e96ede7634d6dc141f0d6055aa1dd24f58c`
TestFlight (#1528): the upload works end to end: own App Store profiles with manual signing, a stripped upload copy that fits Apple's 75 MB Watch limit, and N.1 after a refused number.

## 2026-11-01 00:46:24 EDT — scribe `a354854e028b03060578bbea73b01d59e734d6b4`
Feature (#1528): each production iPhone install also uploads that build to TestFlight in the background; blocked until a distribution certificate exists.

## 2026-11-01 00:03:52 EDT — scribe `7d9931b6f812b0330aa2f68cc0ee37d0e7235cff`
Merge #1515, #1526: a build's details and a recording's copies leave the rows lists read; Playback plays real word times

## 2026-11-01 00:03:49 EDT — scribe `ee055c94cff692933fc81432ef09493cea1b1c29`
test(#1515, #1506): the scan lists the line labels' narrow query, which fails on main (landed in 7d9931b6f)

## 2026-11-01 00:03:46 EDT — scribe `afb997beecd383d778665bdbb5f410ab79ff1cf9`
fix(#1515): every reader reports an older build's recording; a damaged copy costs only that copy (landed in 7d9931b6f)

## 2026-11-01 00:03:42 EDT — scribe `087f5468288b6746867c67b6f414d443d63397c9`
fix(#1515): the board keeps the owner its where names, and names itself a known narrow query; WHATS-NEW for the next build (landed in 7d9931b6f)

## 2026-11-01 00:03:39 EDT — scribe `9b478e04505c75a1e942e1a7541781b78c78a832`
fix(#1515): the architecture scan reads the list's and the board's selections: named paths and one literal list (landed in 7d9931b6f)

## 2026-11-01 00:03:36 EDT — scribe `dfdfd52241049527898ea17738d3d856cc55fe33`
fix(#1515): a window's entry keeps its own id; only the comparison with a row's folds case (landed in 7d9931b6f)

## 2026-11-01 00:03:34 EDT — scribe `bf0f68757961c29430effe80b6011cdf9e066c18`
audit(#1515): every attribute measured from production, what lists and live queries send, the fixes and what is left (landed in 7d9931b6f)

## 2026-11-01 00:03:30 EDT — scribe `6fc802e49315b7057004f39541f35ee77dc6fa56`
fix(#1526): green: a finished recording plays from its lines' own word times (landed in 7d9931b6f)

## 2026-11-01 00:03:27 EDT — scribe `73fa2abff9d02948419eb71fff98b2dd904123f3`
feat(#1515): green: a copy writes a row of its own, the list reads no copy, and Playback and follow-along read the rows and the window (landed in 7d9931b6f)

## 2026-11-01 00:03:24 EDT — scribe `c1e177162d10413eaad85f42bb7acb2be855c91d`
mirror(#1515): green: the mirror reads a recording's clipboard rows beside its window, and shows each copy once (landed in 7d9931b6f)

## 2026-11-01 00:03:22 EDT — scribe `d54939aaaefc748cd6ed38981323ba359d12f68e`
schema(#1515): green: recordingClipboardEntries, a copy a row, and its backfill from the recording row's window (landed in 7d9931b6f)

## 2026-11-01 00:03:19 EDT — scribe `6eeb9ed22834df53a7a3f101113d7fd5626dde8d`
fix(#1515): green: the home board selects what its rows decode, and Playback's and Recently Deleted's transcription rows too (landed in 7d9931b6f)

## 2026-11-01 00:03:16 EDT — scribe `14bfa3b509bd9c205950cf05964f4846e9359000`
feat(#1515): green: a recording's create is the one write that names its build; lines, the list and the recording's own queries carry none (landed in 7d9931b6f)

## 2026-10-31 22:57:37 EDT — scribe `96a09bf420ba7c0e62653e8134eef20366e576d5`
Release (#1482): Scribe 0.1 (217): instant-data-swift pinned exactly at 1.9.64 (plan 067c58e95, #1510 bridge 526dfad7d, pin 95e2ab528, cut 5f2cb7814, change log 8ee334f52), carrying #1510/#1463's compressed outbox body and #1510's write recorder; #1507 (b, c) and #1506 line labels ride along from main.

## 2026-10-31 22:57:37 EDT — instant-data-swift `477797eeeeba61750257d4b94e09256503b5a85f`
Release (#1482): v1.9.64 tagged on 5067e0fe (release document faae749d, change log 5067e0fe), from main b2156d7d: #1510/#1463 compressed outbox body (cb95ef5d) and #1510's write recorder with its cost fixed (9922c9bd). Forward-only storage; no API change. Focused suites: 139 tests in 10 suites passed (mini).

## 2026-10-31 22:46:10 EDT — scribe `d5a41fff48a6b3b73930e03732788282368df84e`
Perf (#1507, #1506): landing 2 of perf-waste-fixes. Every energy-ledger minute row carries the process's memory (footprint, lifetime peak, Neural Engine footprint) from the proc_pid_rusage read it already makes; the interface bytes come from the kernel's 64-bit counters with each interface's index, so a VPN tunnel made again counts from zero (55,128 of the VPN's 58,119 MB on the 10-31 pull were 18 such restarts read as 32-bit wraps) (red f7aa36d60, green ef4ac5b34, test fix 5398cf32b). A recording's line labels select what a chip reads, 186 of 423 bytes a row (red 3d2e6aeda, green 1fe01dd57). The wasted-work audit's addendum (7db8fc4c0). 168 + 16 tests pass on the merged branch.

## 2026-10-31 22:04:26 EDT — instant-data-swift `9922c9bded0c9811866e47bc855c1fc96d9cb61d`
Perf (#1510, #1285): the write recorder explains a statement shape once a process for each schema signature, not once a store (red 7495e6aa, green f63de075; switches 527b6b8d). perf-gate-1491's bisect had put the recorder at +0.26 ms on the cross-SDK runtime benchmark's write (a new store each iteration); switches found all of it in the statement counting's per-store EXPLAINs. Mini, release, three rounds, on against off: a store's first write 0.645 -> 0.459 ms (0.384 off), relaunch 1.41 -> 1.26 (1.14), reconnect drain 0.90 -> 0.81 (0.76). Ready for a build with the compressed outbox body (cb95ef5d).

## 2026-10-31 21:58:17 EDT — scribe `ddf8cc6f7dee449fa27238aa5d5e61293fba4514`
Release (#1482): Scribe 0.1 (216): instant-data-swift pinned exactly at 1.9.63 (plan c3cea8acb, pin 3bb2d2eb1, cut d7e938345, change log fff6a628a), carrying #1491 amendment 3; nothing else on Scribe main since 215.

## 2026-10-31 21:58:17 EDT — instant-data-swift `b92da3bdd82601d9862ac174b9ac090bddc97739`
Release (#1482): v1.9.63 tagged on ae52f3d7 (perf dcbdc3b3, release document 4cc67655, change log ae52f3d7), a release branch off v1.9.62 with the source and test diff of main's 15629f06 (#1491 amendment 3: the outbox tail is one entry of a creation-order index, not a sort of every row; transact hold p50 2.70 -> 2.60 ms, plan hold 1.35 -> 1.04 ms) applied, merged here (main's code kept over cb95ef5d). Leaves out the #1510 write recorder (d3b08d41) and compressed body (cb95ef5d). No API or conversion change; the store adds one index on open.

## 2026-10-31 21:19:30 EDT — instant-data-swift `cb95ef5dceafd0cc6aba71ddc350a324880243cd`
Perf (#1510, #1463): a live write's outbox body is stored compressed in its leaf (a format byte, its JSON's length, raw deflate) and its lifecycle derived from it, so on the phone's 10-31 store 6 of 8 live cells fit the 1,002-byte leaf where each took two to four overflow pages (red ef3862c9, green a6debcdf, fixes 4bb6ddc0 9b2b25ce 6efccd91; change log 5778f111). StorageIOExercises.aLiveWritesStepsByBTree (48 overlapping Scribe writes, one job): a save 16.3 -> 13.2 log frames (65.5 -> 53.1 KB), an echo 18.9 -> 17.5 (76.1 -> 70.6 KB). Budgets count JSON bytes; text bodies still read. Whole bundle on the merge with main: 1,641 tests, only load-timing failures, each passing alone on the mini; 154 tests in 10 suites at the final merge. Cost A/B (mini): transact hold within noise. An older build cannot read a compressed body.

## 2026-10-31 21:05:06 EDT — scribe `dae81af750452d32ac5942b1e7cf89121a3457d9`
Release (#1482): Scribe 0.1 (215): instant-data-swift pinned exactly at 1.9.62 (plan 7387dbacf, pin d6e5f9a0a, cut 052c2b7c2, change log 6c79ab166), carrying #1494; #1515 and #1525 on main ride along.

## 2026-10-31 21:05:06 EDT — instant-data-swift `1432f5cc5495eeeb7325109f4ec93813754856b2`
Release (#1482): v1.9.62 tagged on c85a9531 (perf e2fb5be2, release document ff86efd1, change log c85a9531), a release branch off v1.9.61 with the source and test diff of main's c17bf998 (#1494: a server frame plans in fewer persistence turns, 12 -> 6 for a 50-row refresh; a retried apply names its stale stages) applied, merged here. Leaves out the #1510 write recorder (d3b08d41). No API, storage or conversion change.

## 2026-10-31 21:03:54 EDT — instant-data-swift `15629f06d86a0a95fc630203fd656b3a7b43c881`
Perf (#1491 amendment 3): the outbox tail, which every local write reads inside the operation gate and every server apply's plan reads twice, is the last entry of a creation-order index instead of a scan and sort of every outbox row (red e10668ae, green e712d3e3); the plan guard (no statement a live write runs reads more of the outbox) and #1115's frame budget 24 -> 25 for the index's page on the save and the echo (7a67778d); ab-commits.sh resolves its trees one at a time (d8185dde). One job on the Mac mini (release): beside load the transact hold 2.70 -> 2.60 ms and the plan's 1.35 -> 1.04 ms; the plan's CPU a call alone 852 -> 807 us. After merging main: 236 tests in 23 suites passed (laptop, debug, 17 known issues).

## 2026-10-31 20:54:23 EDT — scribe `43d47ca00a0022b32e66181e01c6cc06aab443ec`
Release (#1482): Scribe 0.1 (214): instant-data-swift pinned exactly at 1.9.61 (plan 199c87bd9, pin 78f05acb2, cut 335d40599, change log e460ce467), carrying #1504, #1497 and #1496; #1515 on main rides along.

## 2026-10-31 20:54:23 EDT — instant-data-swift `73a28f2b4ab34f09733c6513481f92313ff54e9f`
Release (#1482): v1.9.61 tagged on fb930584 (release document ee13ba65, change log fb930584), a release branch off v1.9.60 with the source and test diffs of main's 3374ba97 (#1504: temporary structures in memory) and b60a2c09 (#1497/#1496: the kept receipt fingerprint, one task per frame) applied, merged here. Leaves out the #1510 write recorder (d3b08d41). No API, storage or conversion change; 32 tests in 6 suites pass on the release tree.

## 2026-10-31 20:24:31 EDT — instant-data-swift `c17bf9980adf56b3c076fb0719c4bc0f1a27f025`
Perf (#1494): a server frame plans in two persistence turns after its seed (the planning reads with the reduction's context in one turn, the plan's begin with its first reverse body page, no empty trailing pages, the plan's end with the status read) and a retried apply names where each earlier attempt went stale (part 1 red b27bca3f, green 4f2e76e9; stale stages red 47f0573b, green 3f04436d; turns red 670758fa, green 5922e9af; docs 278806cc, 26ad0b2c; change log 73738de5): a 50-row refresh's persistence turns 12 -> 6, over a pending write 13 -> 8; Mac mini, release, interleaved: library CPU and write latency unchanged, attempts per frame 1.116 -> 1.159, whose sources are #1524.

## 2026-10-31 19:31:14 EDT — instant-data-swift `b60a2c093ac47ef23378dfa75444f1769bb8e764`
Perf (#1497, #1496): the delivery claim and the acknowledgement reuse the receipt fingerprint the save computed, keyed by a hash of its six inputs (red 13699326, green a55a0912, inputs key ca5c830e), and a send starts one task where it started three, with one deadline watcher per socket and no timer per send (red af675e6b, bench 7d024be3, writer 0a7a9595, 4bd0f806, 66d372e8, 40e83b28; change log 848d72e9). Mac mini, release: acknowledgement CPU per call 834 -> 506 us alone and 613 -> 419 us loaded, outboxClaim 2,278 -> 2,051 us loaded, localSave 1,733 -> 1,914 us loaded (the key's hash; #1523 carries the rest), save, claim and acknowledgement together -5% loaded (recording exercise against main 62c16ebf, interleaved in one job); CPU per send 24.58 -> 20.69 us, tasks 63,000 -> 21,001 for 21,000 sends, the 5.5 s timer tail 0.60 -> 0.35 ms (measureTheSendPath against 7d024be3).

## 2026-10-31 19:08:57 EDT — scribe `e14305ded95347015e7136a6d1cd8a240092e790`
Schema (#1515): buildDetails, one immutable row per owner and content hash, linked from recordings, transcriptions and sharedRecordings (ADR 0109).

## 2026-10-31 19:03:07 EDT — scribe `2cb05b71e53b4c732aa6361cc9c85088215ece38`
Release (#1482): Scribe 0.1 (213) cut from main 97fb01384 (plan dfb5695b0, cut 83dc64994, change log 3869847b5), carrying #1503, #1506 (landing 1), #1508 and #1507/#1510's Scribe side; instant-data-swift stays pinned exactly at 1.9.60 (no library fix after it has a READY FOR BUILD line).

## 2026-10-31 19:02:52 EDT — instant-data-swift `3374ba97eaf69ab94061a5656f7ad44fdfd7ebde`
Perf (#1504): every store connection keeps SQLite's temporary structures in memory: the writer from the end of its bootstrap (after the one-time migrations, before the server apply's staging tables) and when it reopens, every read connection at open (red 6ec56cba, green a92b8ca4; change log c843402c). A device's ledger counted 34,124-36,677 temporary-file writes an hour of recording (19-49 MB/h) and 470,007 across eight launches; expected 0. 40 tests in 8 suites pass on the branch merged with main. Plan amendment 3: #1500 waits for #1165 (a local write to an entity on disk but not in memory erases its other facts; red test confirmed).

## 2026-10-31 16:08:46 EDT — scribe `655e5f00eb2fe4eff2ab8a0a9bb4059b43520ce2`
Fix (#1508): the recording Live Activity drops its 60 s keep-alive and its 90 s stale date (Michael chose option 1); new words still go every 5 s behind and 30 s in front and state at once, the clock counts on the device by itself, and about 60 of the 107 updates an hour go away.

## 2026-10-31 18:34:51 EDT — scribe `85839caa580e8b53eaa0b6b08984543dfbd42391`
Telemetry (#1507 a) and recovery (#1510, #1463): a diagnostics spool's compaction counts the bytes it rewrites under diagnostics.spool in the energy ledger (red 1b9914513, green 2b5961326; on build 208 the collector lane's compactions wrote 1.29 MB a minute that no writer named), and scripts/recovery/recover-recording-from-outbox.mjs inflates a body instant-data-swift stores compressed, text bodies still read (red c070c27b4, green 6ade1b1c9). Change log e335051c6.

## 2026-10-31 17:58:36 EDT — scribe `334c150a2256dff65a8d82e71d3d1d9a4350c4ef`
Perf (#1503, #1506): landing 1 of perf-waste-fixes. Each audio chunk sent and each server message on the live transcription socket is counted in the energy ledger (speech.stream-send, speech.stream-receive) instead of a device-log line: 82% and 8.4% of the phone's 10-31 log, 63-70 MB an hour of recording (red 682941c7d, green 10fa5b026). The chapters query filters retiredAtMs null on the server, 225 KB -> 25 KB a restated frame for the recording chaptered live, and a held audio-keeper pass reads no audio rows (red c21743187, green b5e8b37bd). #1507 (e) documented (dcb21c180).

## 2026-10-31 17:48:43 EDT — scribe `046ce3d54fc28b6875c485e70f2bf81131241649`
Release (#1482): Scribe 0.1 (212): instant-data-swift pinned exactly at 1.9.60 (pin 8a137eb52, cut 1489bdecd, change log 4c18f316a), carrying #1491; What's New 210 gets #1495's interleaved A/B.

## 2026-10-31 17:48:43 EDT — instant-data-swift `26c43bccc99b246b4a015f2d1b37be9b0f64b186`
Release (#1482): v1.9.60 tagged on a00c1618 (release document cbda8b88, change log a00c1618), a release branch off v1.9.59 with #1491's four commits cherry-picked from main (99a46951), merged here: a local write does less hashing, tight-loop transact p50 0.476 -> 0.389 ms. Leaves out the #1510 write recorder (d3b08d41). No API, storage or conversion change.

## 2026-10-31 17:39:13 EDT — instant-data-swift `99a46951afc3d9e270e679190f6a6358a5cdf889`
Perf (#1491): a save's two SHA-256 digests write their hex into one string (red cd3faf28, green d564a099), and a new write's row write no longer computes a forward wire-intent fingerprint it never reads (red aa18c4af, green 4ff5e5c4); ab-commits.sh builds its trees side by side and runs a test filter at each commit; docs/audits/2026-10-31-transact-hold-1491.md. One job on the Mac mini (release): tight-loop transact 0.476 -> 0.389 ms (-18%); after merging main, 638 tests in 31 suites passed (laptop, debug, 20 known issues).

## 2026-10-31 16:18:36 EDT — scribe `bf0364538cb2998fb275d337b48b62bb10477475`
Release (#1482): Scribe 0.1 (211): instant-data-swift pinned exactly at 1.9.59 (pin db21c0a90, cut d8f028b3f, change log d40dc5a42), carrying #1493; with #1501 since 210.

## 2026-10-31 16:16:26 EDT — instant-data-swift `62c16ebf20eb70958de2263cd23ae4da63a178cd`
Release (#1482): v1.9.59 tagged on 1d9ba2ba (release document 0d24c626, change log 1d9ba2ba), cut from main at 81c07e43 and merged here: #1493, a query observation is one stream. Leaves out the #1510 write recorder (d3b08d41). No API, storage or conversion change.

## 2026-10-31 16:12:31 EDT — instant-data-swift `d3b08d41fe307215643f74463b1a3b857d01c213`
Feat (#1510): the write recorder, InstantSQLiteWriteRecorder: every page the store's log takes and every checkpoint copy, by table or index, by write statement (runs, rows, pages, the b-trees it writes) and by store call, over time, learned from the pages SQLite already reads and writes (red 6434d6e2, green cb989369, fixes 07156001 be771453). Mac mini: its tests 8/8, one checked frame by frame against the log file and dbstat; the audit docs/audits/2026-10-31-writes-1510.md (a save 24.4 pages across 17 b-trees). Its own cost is queued; READY FOR BUILD waits for it.

## 2026-10-31 15:56:21 EDT — instant-data-swift `dffd9a0629b07bf718c467f175203083fde4606e`
Perf (#1493): a query observation is one stream, written by the store and the live query's server error under one lock and read in its consumer's own pull (red 02ef83f5, green 6256949a, exercise c5f7c882, doc b00e2d04; change log b6a3274e): library tasks per open live FetchAll 7 -> 1, the process's alive tasks with 48 live observers 290 -> 50 (xctrace), publication -> wrapper value p50 2,631 -> 681 us (Mac mini, release).

## 2026-10-31 15:22:44 EDT — scribe `e565fa39a8a0edd0adf89dbc70428a604ede5edb`
Perf (#1501): the recordings list's page carries no build provenance: the list selects no buildInfo on recordings or on its transcriptions include, and a line's final writes its transcription's counts without buildInfo, which the create sets once (red 8e71fdad3, green d1d1d0a43); stored list pages on the 10-30 iPhone store copy 617/594/471/108 KB, buildInfo 74/80/72/96% of each.

## 2026-10-31 15:14:30 EDT — scribe `cef2d9a7d9269aede44ca8f4c22d3b144d835906`
Release (#1482): Scribe 0.1 (210): instant-data-swift pinned exactly at 1.9.58 (pin 000210f5f, cut 83dec0324, change log 6813cf9e7), carrying #1495; with #1510's app half and #1499's heads-up wording since 209.

## 2026-10-31 15:12:35 EDT — instant-data-swift `97241036e8284525b9ac05957cd9af12f72c2622`
Release (#1482): v1.9.58 tagged on this merge (release document 02566ad4, change log 3431e78b): #1495, an observer keeps the ids its result shows, collected once per result. No API, storage or conversion change.

## 2026-10-31 15:06:17 EDT — scribe `b87c51f61a34bf590b9a185e78b5076dfe6585fd`
Feat (#1510): each minute row of the energy ledger names the store's SQLite pages by table or index (at most 16, each with its three largest store calls) and by write statement (at most 12: shape, runs, rows, pages), counted between two reads of instant-data-swift's write recorder (red 8d0bf7a4, green 2fdd4522; change log 27448522f). Empty until the library tag that carries the recorder is pinned.

## 2026-10-31 14:54:08 EDT — instant-data-swift `e6e719134d2a754bf08489781ed5052d46642fc9`
Perf (#1495): an observer keeps the set of ids its result shows, collected once per result and kept while it holds that result, so a publication no longer rebuilds it for every change it judges and again for the splice (red 3cce5ca1, green 9051d75e; a phone-shaped publication fan-out exercise ff8fb803; change log 8ccd5d57). Measured before on the Mac mini (release): a final's publication p50 18.4 ms, of which re-materialization 92%, the id sets about 1%, wasLastHanded's equality about 0.1% (so no fingerprint was added).

## 2026-10-31 13:51:10 EDT — instant-data-swift `4ba76de7f91ae84b30b7a2ccd72bd27b3701d12c`
Perf (#1492): the live session keeps one attribute resolver per server schema instead of indexing all 2,283 attributes for every mutation it sends (red 8b5a4584, green 14ee7622); mutationEncode CPU per send 2,650.1 -> 14.5 us on the Mac mini (release, recording exercise, 90 sends).

## 2026-10-31 13:45:14 EDT — instant-data-swift `c9dc143dd60615479083b7a24522c0c5844ba86d`
Perf (#1498): a one-shot read writes its answer to the query cache only when it changed, and never encodes it on the persistence actor: the row keeps its answer's digest and, in columns, the last read's time, revisions and sequence, which readers lay over its JSON (red 38c426f6, green 2c1c003d; change log f07f53fc). A fresh store's first answer takes one more persistence turn (relaunch pins 14 to 15). Before on the Mac mini (release, the recording exercise sampled 60 s at 1 ms): queryOnce 802 ms of CPU, saveQueryCache 553 of it.

## 2026-10-31 13:32:48 EDT — scribe `20b7467ed46e247ffbca5f918e9b4856f08d42d2`
Audit (#1509): the whole system, not one cause: the phone's cost mapped by state and subsystem from the 10-30 powerlog, MetricKit and the 10-30 and 10-31 energy ledgers; the floating bar's breathing symbol behind the lock with the screen on (#1502, +8.5 points of a core for 85 of 122 background minutes); 1.9.56's write fixes verified on the phone per event (claim -67%, ack -47%, apply -56%) while the save stays at 103 KB; #1491's 4.6x was the mini's clock state; filed #1511 #1512, queued six fixes. Landed as merge e5fe2a29051aec4ee41098ba14ef43f6337f36f3.

## 2026-10-31 13:01:39 EDT — instant-data-swift `1e1ba548d0b25b1c5ae439a894ba9a94dbc07474`
Perf (#1491): a new local write encodes its body once, its 8 MiB bound read from the bytes the save writes (red efc0656f, green 02b7cf8a); scripts/contention-exercises/ab-commits.sh compares commits in one job on one machine, alone and beside a CPU load (the 10-24 baseline run alone on the Mac mini holds 5.02 ms, so the #1482 audit's 4.6x is mostly machine state).

## 2026-10-31 12:46:23 EDT — scribe `e00f51ba8d5738403a09e59a7ac714ba8e0ca8d9`
Audit (#1481): wasted work in instant-data-swift and Scribe after the night's fixes, nine findings filed and queued (#1500-#1508): closed results kept as 207 MB of duplicate, dead value copies; list pages carrying each row's build provenance; the floating bar's per-frame breathe on every screen; the device log at 22 lines a second; a never-analyzed store; the Codable wrapper on stored values; whole-library screen windows; the ledger's unattributed writes and missing footprint; the Live Activity keep-alive as a proposal.

## 2026-10-31 12:43:05 EDT — scribe `5bf97955c537`
Audit (#1482): what this pass did not measure, and the one-job recipe for the task and actor counts (change log fbeca0780).

## 2026-10-31 12:40:54 EDT — scribe `cfe947808dabe72e837ccca7250d57709de1caaa`
Audit (#1482): Swift concurrency, scheduling and isolation in instant-data-swift first, Scribe second, measured (landed bd29efea2 with its change log 65b24b771; issues #1491-#1498).

## 2026-10-31 12:39:25 EDT — instant-data-swift `524bf6e1b2a0d2a9ea021bdd6cb7144d698a9e2e`
Tools (#1482): the recording exercise profiled under sample and xctrace, and an A/B of the writer's SQLite mutex (merge of aa325f311; no difference between FULLMUTEX and NOMUTEX, 0.456 against 0.458 ms per transact).

## 2026-10-31 12:25:02 EDT — scribe `b41e6f2a80fea5a22fd01b0735397ed730c8b762`
Fix (#1489): a library list keeps an episode with no file of its own when its page can be resolved, and an empty list says so.

## 2026-10-31 11:04:21 EDT — scribe `516f163fcd51bd5b0f47720562607b4a6eb38cfd`
Cut (#1393, #1452): Scribe 0.1 (208): a long press on a picture offers Comment again.

## 2026-10-31 11:03:42 EDT — scribe `c71540072b85c93c126583ed70a5e37319d01e39`
Feature (#1457): the image viewer follows the newest picture, offers the newest again, and groups its grid by chapter.

## 2026-10-31 11:03:41 EDT — scribe `a7d01c6bbbfe26e54e70dae38b90387fd28f4cc7`
Test (#1393): 34 layout snapshot references re-recorded after review; 61 repeat with no difference.

## 2026-10-31 11:03:41 EDT — scribe `a8a58df1bdfbdbd07c0b3075b44e63c520c5b94a`
Fix (#1452, #1466): the Comment item returns to a picture long press, and the surface test accepts the drag before the menu.

## 2026-10-31 11:03:41 EDT — scribe `67bde57f2b61a028c69d216752fef866344c9b44`
Fix (#1393): a narrow link card stacks its words under its code.

- 2026-10-31 10:13:50 EDT · realtime-voice · `0b3fac6fd7f2` · #1487: any speech to text runs the full pipeline; Point-Free gets chapters

## 2026-10-31 12:02:29 EDT — scribe `062307a97378ff95013e197a02c33bd27469d331`
Feature (#1490): each device writes its notification settings (authorization, alerts, lock screen, Notification Center, sound, time sensitive, scheduled summary, previews) to its push row at launch and on a change seen in front; scribe notify says Apple accepted a notice, never that a device received it, and --state lists each device. Schema `e093919726c18ae193dee5bff2de3af4bbaf177d` (one optional attribute, pushed to production, drift 0); landed in merge `a4f05db2ee6c7a5045b1ed1e314e2ff63f82bdff`.

## 2026-10-31 10:30:48 EDT — scribe `d44a055efb6e9c2b5a7cbb0c9043bc85e8633b43`
Merge (#1457): the Photos-style design playground, rounds 2 and 3, and the audit with its winners; the playground compiles at the package's iOS 18 floor.

## 2026-10-31 10:30:08 EDT — scribe `8daf8c4bf29cc848b75c23d62cee662106197d35`
Docs (#1457): audit of four blind-critic design rounds: winners, every score, specs with round 3's corrections, 22 pictures.

## 2026-10-31 10:30:00 EDT — scribe `374ebe4ede50ec623225bd9f1ee3bc229e1a9b88`
Fix (#1457): playground round 3: list rows keep their own colors; the paused phase symbol holds 4.4:1 in light.

## 2026-10-31 10:30:00 EDT — scribe `2ec2d200dfb5ba27c0efda41762f8353651f7cc2`
Feat (#1457): playground round 3, every round 2 blocker and high answered; the harness compiles at the iOS 18 floor.

## 2026-10-31 10:30:00 EDT — scribe `18a3dcb400f18a480a61a9ff477fb70e86a07e76`
Feat (#1457): playground round 2, the round 1 leaders revised; no Show All labels, every tap has its VoiceOver action.

## 2026-10-31 10:13:56 EDT — scribe `74679e9a9f4e7a500c80fef04fc151aa569b41d0`
Merge (#1465): the chapters zoom level proven on the simulator, live and in playback, 8 of 8 UI tests; no app code changed.

## 2026-10-31 10:12:53 EDT — scribe `3daf96f0c8504fcbda68485fc6b45c911afdbb62`
Test (#1465): ChaptersZoomUITests pinch playback on its words, read the store's state on failure, and see the share sheet list the recording's own lines.

## 2026-10-31 09:51:16 EDT — scribe `cf3193a0fcf344582d7d844dc15b655cc18d5897`
Merge (#1486): land-1486's presence: ~/Scribe/tools/land installed, 13 hand landing copies forward to it, claims released.

## 2026-10-31 09:51:02 EDT — scribe `35680e99d607689407a483b9cb52c165a06977c5`
Docs (#1486): the landing audit's install section, its index row and the PROGRESS entry.

## 2026-10-31 09:47:58 EDT — scribe `062f7a347d654a2ba1693d82b5ffb0e5ad2242fb`
Merge (#1486): land --prepend, one ledger entry on main from one read of it; landed by the tool itself.

## 2026-10-31 09:47:44 EDT — scribe `0fdbd13b5bb8d4a147282aaa70789eed122d3ad5`
Docs (#1486): land --prepend in AGENTS.md and the audit; about 35 hand scripts read origin/main up to three times.

## 2026-10-31 09:47:01 EDT — scribe `61839ec45ee56c8636d486995d3ce6f7dbb4d01b`
Fix (#1486): land --prepend on the same loop as a branch's landing: one read of main, a fast-forward push, a retry.

## 2026-10-31 09:45:13 EDT — scribe `8b47b088ddb3e477b12bc76d7f68a37de27f4659`
Test (#1486): red: an entry above the newest, a landing between its read and its commit survives, two entries racing.

## 2026-10-31 09:40:21 EDT — scribe `cf3bec32c14661883a401e195a51573996fe3209`
Merge (#1486): a landing never silently undoes another: one read of main, a fast-forward push, a retry; landed by the tool itself.

## 2026-10-31 09:39:41 EDT — scribe `5c06ffeba8b839dae1c28ba4fbfa9244785761dc`
Docs (#1486): the landing race's audit (one drop in 656 commits, already restored), its index row, and AGENTS.md's rule.

## 2026-10-31 09:38:08 EDT — scribe `77607f8ae6162c4a7ef55d6bb475c71bb6d2759d`
Fix (#1486): scripts/land/land.py: the merge tree and its first parent from one read of main; never forced; diff3-base unions.

## 2026-10-31 09:26:42 EDT — scribe `ee16b2584cc2baa4a02562cfc7e97c7f847762f3`
Test (#1486): red: two landings racing on a fake remote lose a file with today's land.sh (7 of 10 fail).

## 2026-10-31 09:31:46 EDT — scribe `3cee0837c549b8c78ec3c4113dbce168011b9629`
Cut (#1393, #1465, #1457, #1449, #1469): Scribe 0.1 (207): the Mac View menu moves between lines and chapters, the image viewer title fits, a map applies its first frame at once.

## 2026-10-31 08:57:11 EDT — scribe `02880730351739bbc13e9e12a89987a2a5f91ed9`
Test (#1453, #1437): the row checks press a line on screen, and the first-line check starts with the layout harness notice closed.

## 2026-10-31 08:23:40 EDT — scribe `fe49cd6ea74b05467180ab637881d8c37732deca`
Merge (#1469): each broadcast frame's JPEG is written once on the phone; the spool takes the extension's file by rename and the recording's copy is a synced hard link.

## 2026-10-31 07:47:40 EDT — scribe `81a5fc58dec386b538d7f5119cd421a828e01458`
Docs (#1469): the audit's section 7 and ADR 0108 amendment A.

## 2026-10-31 07:47:40 EDT — scribe `db5e5e9da6e80bf98d785599b79d25cbf2a9536f`
Fix (#1469): the frame spool renames the extension's file in and the drain's sink links the recording's copy, forced to flash once.

## 2026-10-31 07:47:40 EDT — scribe `18d5f4a7c7e14b11e6b3b6979d009e6a42b47a2c`
Test (#1469): red: a frame's JPEG written once; FileWrites gains move and link; a vanished frame file is skipped by name.

## 2026-10-31 08:05:24 EDT — scribe `ef70f3c978e5cb4b54fa6f97d80bca3ec8e6b4cf`
Feature (#1465): the Mac View menu moves a recording between its lines and its chapters, with one value shared by both menus.

## 2026-10-31 08:05:23 EDT — scribe `c7d50eedf3b11d23ff4457174c6c5791177d9c30`
Test (#1393): the layout harness scrolls to the first line itself, and each UI check starts where it claims to.

## 2026-10-31 08:05:23 EDT — scribe `203eb2b1dd86809474da39bde53976f28b553afc`
Fix (#1457, #1449): the image viewer title fits beside its buttons, and a map applies its first frame without an animation.

## 2026-10-31 06:25:06 EDT — scribe `9dfdf4580f85bd26da9981414b5cb18359998210`
Merge (#1393, #1209): one clock, one chapter type and the seek track shared between the two apps.

## 2026-10-31 07:48:20 EDT — scribe `18ba5013b28c1bf836725ea18727c09d56dd6bb3`
Cut (#1426): Scribe 0.1 (206): instant-data-swift 1.9.56, a stored live result is its rows and nothing waits to be written.

## 2026-10-31 07:27:14 EDT — scribe `e1c5f62f133a1debae4ae02443fe381af3f74398`
Fix (#1426): pin instant-data-swift 1.9.56 in the app, both local packages, the installer and two docs.

## 2026-10-31 05:54:56 EDT — scribe `bcf560de15f8c12048af9e6b6dfa647423b799b8`
Fix (#1426): green: query-plans sizes a stored result by its ownership rows in the rows layout.

## 2026-10-31 01:42:25 EDT — scribe `d19215c91f71c84773b131dd7fe3e37363a1e458`
Test (#1426): red: query-plans sizes a stored result by its rows when the library keeps it as its rows.

## 2026-10-31 07:47:28 EDT — instant-data-swift `1e2153a99449887936ac1e682b1f0c6659a4684f`
Docs (#1426): v1.9.56's checks after the tag: the whole core bundle, 1,613 tests, 2 unlisted timing failures under load that pass alone.

## 2026-10-31 07:42:26 EDT — scribe `b1e262b4dcd420a5fbea2fa8b8463101819a6934`
Merge (#1459): the Playground's harness references, default and AX5, after the restack.

## 2026-10-31 07:42:26 EDT — scribe `4fc707fdffd92e4d9f0388df8a63774d203fbc92`
Test (#1459): the Playground's harness references on the iPhone 17 Pro simulator, default and AX5.

## 2026-10-31 07:29:29 EDT — scribe `9b7514db679ec272c645313c1a782efe4dcfe7c6`
Presence (#1468): landed; progress entry; claims released.

## 2026-10-31 07:29:29 EDT — scribe `49a3cb311a3edb78301a22b851ba64aa5e00f6fd`
Docs (#1468): What's New 205, the camera feed opens and closes without freezing.

## 2026-10-31 07:29:29 EDT — scribe `c264803acf438158ce288dd4d4204069d295912b`
Fix (#1468): the camera panel's preview joins and leaves the capture session on the session's queue, never the main thread.

## 2026-10-31 07:29:29 EDT — scribe `8aa78abc6d41d05f314eba7a3801f9a1d08c451a`
Test (#1468): red, the preview links the capture session on the main thread.

## 2026-10-31 07:20:53 EDT — scribe `dbd6f05a5d41d51736e17a56b215cb75fff94da0`
Server (#1460): re-applies the read fix a concurrent landing dropped (#1486).

## 2026-10-31 07:18:45 EDT — scribe `a2bd09ec1515b0e595dce6164144ef83cd585649`
Server (#1460): lands the WebSocket read fix, its tests and docs.

## 2026-10-31 05:52:37 EDT — scribe `20bdf30cbf133e3771dd29c5ae0352979566c5ef`
Server (#1460): past 120 s of audio not yet decoded the read paces the client instead of refusing it.

## 2026-10-31 05:51:53 EDT — scribe `470625127bc6a2e21afba5f4cc5f373e358d9a6a`
Server (#1460): the WebSocket listen route reads its socket in a task of its own, so its 5 s ping never waits for the decode.

## 2026-10-31 05:51:53 EDT — scribe `362f02b44a68b704b914fa730965fd064d20c3d9`
Test (#1460): a listen stream slower than its audio keeps its socket (live server, URLSession WebSocket).

## 2026-10-31 02:29:46 EDT — scribe `62c6382abf6af2ef2e93e70dc3c6b1face29b57b`
Server (#1460): the transcription server's LaunchAgent leaves launchd's utility clamp (ProcessType Interactive).

## 2026-10-31 07:19:26 EDT — scribe `f401bc9bfe507b2f6b43ed080391d8566aa9020d`
Merge (#1459): scribe design post reads its attempt beside the render and uploads beside the chat's write.

## 2026-10-31 07:19:26 EDT — scribe `5824ddcf74673e18c3785db78268991c3919deee`
Fix (#1459): green: a post reads its attempt while the drawing renders and uploads the picture while the chat's row is written; a chat from client work is refused before the upload.

## 2026-10-31 07:19:26 EDT — scribe `b757bf04f045b120fd7bc3e6841df98161912904`
Test (#1459): red: a post's attempt read runs beside the render and its upload beside the chat's write.

## 2026-10-31 04:02:48 EDT — scribe `bd7b9057264cc21de7385dc84cce94ef2eaff580`
Fix (#1467): the launch reads isProtectedDataAvailable in App.init itself, before the dependencies closure.

## 2026-10-31 01:54:26 EDT — scribe `59396227471f579e5a93fa7923ba69e143c3f182`
Fix (#1467): Scribe Videos' ledger holds its saves after a refused read and joins the file once it reads.

## 2026-10-31 01:53:35 EDT — scribe `c436164d058dda11f53c5135b3562b8305a66d1a`
Test (#1467): red: Scribe Videos' ledger file refused at launch is not written over.

## 2026-10-31 01:51:49 EDT — scribe `78f09f96a4db1347ddf32b0492c22df454c19c29`
Fix (#1467): the launch's app-storage choices wait for the first unlock instead of taking their defaults.

## 2026-10-31 01:50:09 EDT — scribe `77a41d7f7bad257180200bd5164b24729d7bf6c9`
Test (#1467): red: the launch's app-storage choices are not written over before the first unlock.

## 2026-10-31 01:37:32 EDT — scribe `c3959f78cc1987c9b8c0006da8b49d10af471966`
Feature (#1467): a stretch the file key could not use its file reaches the app's lanes when it ends.

## 2026-10-31 01:36:51 EDT — scribe `87a28d041bdf1200fd99cd771ba5b6a91e15978d`
Test (#1467): red: that stretch is reported once when it ends.

## 2026-10-31 03:35:53 EDT — scribe `ae2adcded8131866095d92c25d689f8ffad65ba1`
Fix (#1467): the locked-file test counts ten minutes as .seconds(600).

## 2026-10-31 01:32:13 EDT — scribe `0f36cfada3d52ced4129d2feabc5721fb8186f42`
Fix (#1467): ScribeSharedApplication imports UIKit for the launch's isProtectedDataAvailable.

## 2026-10-31 01:15:38 EDT — scribe `9b2da1c6c26011f4e8b84a24cf0a7d3941fa0e3f`
Fix (#1467): the first unlock reads a locked file at once, a refused read logs why, the watch starts again.

## 2026-10-31 01:15:29 EDT — scribe `6553c8603d55e903d3acf3b62e7b25ab42a15c54`
Test (#1467): red: the first unlock reads a locked file at once, and a refused read names its error.

## 2026-10-31 01:05:54 EDT — scribe `5902ba9185c81fdf0176382c6ff9eaf5eb1cc2f1`
Fix (#1467): a locked file's rereads wait on the injected clock; a key that subscribes late restarts them.

## 2026-10-31 01:02:24 EDT — scribe `8bdaa1e4f6510090fa6136e7f81008a8e8f18cd3`
Test (#1467): red: a file iOS keeps locked for ten minutes is never written over, and its values win.

## 2026-10-31 07:12:47 EDT — scribe `5adac1946a58beea9ce575ca54d44f16c95c638b`
Merge (#1459): the Playground restacks at AX5, its reads select every required field, and its arrival line counts only new posts.

## 2026-10-31 07:12:47 EDT — scribe `3babf10afd97f572496e7449297e8294767f7d34`
Fix (#1459): the Playground's rows restack at accessibility text sizes and titles wrap by words; AX5 broke words letter by letter beside a score or thumbnail.

## 2026-10-31 07:12:47 EDT — scribe `a2bdfcfc0aefe47a1ead110807f15de6ada8c10b`
Fix (#1459, #1466): every Playground list selects the attempt's required fields (FieldLimitedInstantQueryTests); an attempt's picture drags out with its link.

## 2026-10-31 07:12:47 EDT — scribe `3f5766fc888a7dba79fa9ad73f7c3142fd205872`
Fix (#1459): the Playground's arrival line counts only attempts posted since the screen began following.

## 2026-10-31 06:53:51 EDT — scribe `fdc519631edfa91cd84891b1b74a44da0126d217`
Docs (#1478): audit: an APFS clone of warm derived data at a new worktree path recompiles every target (probe, Xcode 27A5194q); builds 199-203 took 19.5-27 min to the iPhone.

## 2026-10-31 06:53:51 EDT — scribe `83104b562067cdf4bdae3788199cbb827e4afcd3`
Fix (#1478): a warm tree left without a branch still checks out the next cut; the installer's dated history header.

## 2026-10-31 06:52:25 EDT — scribe `1682fb0e767f15600de985df37b079b81f988d5b`
Fix (#1478): every cut builds in one warm git worktree per Xcode build at a fixed path, so Xcode recompiles only what changed; busy or refused builds cold in the cut; a failed warm build retries cold once.

## 2026-10-31 06:50:24 EDT — scribe `d58f57013fb95f281dfde3e3d2ad28e349930673`
Test (#1478): red: the warm tree's path, commit, branch, unchanged mtimes, busy lock and new-Xcode cleanup; main's warm build and cold retry.

## 2026-10-31 05:44:32 EDT — scribe `85e69c6c4673f5888e999b2a0e7ee122b7313f83`
Fix (#1478): a locked device refusing the launch after a verified install is a warning in the summary, not exit 1; a failed install still fails.

## 2026-10-31 05:44:32 EDT — scribe `9f745a1ccc0d21495c863185011352b41011aed1`
Test (#1478): red: a locked device refusing the launch after an install is a warning, not exit 1.

## 2026-10-31 06:51:09 EDT — scribe `e99a8eb59d48e3029609ff676fec553d8c5330c2`
Fix (#1465, #1459): the voice-command coverage test's reasons for the chapter controls and the drawer's Playground; no behavior change.

## 2026-10-31 06:43:40 EDT — scribe `4c58567e2c950b8dbed8bcefe8ed751852ffd273`
Fix (#1465): the chapters service asks the model only about recordings the owner's sign-in may write, and keeps a refused write with its reason instead of asking again every scan.

## 2026-10-31 06:42:46 EDT — scribe `fb5583d50666c1c380c7b8ab00fd022f85d4f211`
Test (#1465): red: the chapters service skips recordings outside the rules' owner set before any question, and remembers a refused write.

## 2026-10-31 06:32:41 EDT — scribe `60906ef873c02c1f4022628899dd17d7e69c2e6f`
Fix (#1466): every drag sits inside its row's menu, so a press that moves lifts it; a drag applied after the menu never lifted on iOS.

## 2026-10-31 05:27:40 EDT — instant-data-swift `da073db4dc6ef975ac4248fa5b4fe071a4941dcf`
Fix (#1426, #1440): a stored live-query result is its ownership rows, its facts and a narrow header; every refresh writes exactly its diff, no result's JSON waits, and the header's update reads no JSON. Ships as 1.9.56.

## 2026-10-31 00:17:19 EDT — instant-data-swift `d331eb02bf592547620d593179829fa27514e1ec`
Test (#1426): red: a stored result is what the store holds in a running process and after a kill; its header holds no JSON.

## 2026-10-31 05:25:34 EDT — scribe `764026d3b6d257925244c2da7f6f8a95e1220ffa`
Docs (#1477): ADR 0079 section 12.1: the second path to the model, the loud stop, and the backfill: 99.89% of the missed lines labeled.

## 2026-10-31 05:25:34 EDT — scribe `e8d5c21b6b139ab2e0c7c5f0b682fd2b7129b43a`
Fix (#1477): an id prefix of digits only finds its recording when no recording has that number.

## 2026-10-31 05:25:33 EDT — scribe `b9efdb4d8af100a161b2d54ad05339326db4e023`
Test (#1477): red: a digits-only id prefix was read as a recording number.

## 2026-10-31 03:48:52 EDT — scribe `a7cb7937df4d33eec1a8779837e70404cb800c61`
Feature (#1477): the agents' Now page warns when the topic tagger has stopped (10 minutes of failed looks, or 5 with none).

## 2026-10-31 03:48:52 EDT — scribe `848e490c3cf3ad3b67423e9418b1e6cdd3c921cd`
Fix (#1477): the Mac health check shows the topic tagger's line from its status; never a notice.

## 2026-10-31 03:48:52 EDT — scribe `64254f00d369488f4ca12ba8506bf616ce14baa6`
Test (#1477): red: the Mac health check has no topic tagger line.

## 2026-10-31 03:48:52 EDT — scribe `4a1a25a68f45ecda73b39b86567de768e525de55`
Fix (#1477): the tagger's follow says a repeated failure once, and leaves a status for its watchers.

## 2026-10-31 03:48:52 EDT — scribe `9d8025c866976828ebccad4d9d953e5ac8685d76`
Test (#1477): red: a failure repeated every 15 s is said once; a status is left.

## 2026-10-31 03:34:02 EDT — scribe `d666a567dc6a7f7f82dd42789d167a6f45ce8c50`
Fix (#1477): the tagger's LaunchAgent runs Interactive: as Standard its claude child ran at priority 20 (50 s a call against 3 s).

## 2026-10-31 03:27:15 EDT — scribe `785c3bfb702952e4d275edb7a8bad0618dc2f1b8`
Fix (#1477): the topic tagger reaches the model through the Max logins when every prepaid credit lane is out; same model, schema and rows.

## 2026-10-31 03:27:15 EDT — scribe `52d409d0de6caee842908e89032ed123e3b36dd7`
Test (#1477): red: with every credit lane out of credit the tagger still answers, and says the switch once.

## 2026-10-31 05:21:45 EDT — scribe `20e8ffbb0e47e33122f0ce4386c5f8a627390f01`
Cut (#1393): build 204: the image viewer, thumbs on answers, a marked-up image in its original's place, comments on pictures.

## 2026-10-31 05:21:45 EDT — scribe `4713db659848fd67a450bc8cb2efa43e5e70632c`
Merge (#1393): the image viewer, thumbs on answers, a marked-up image in its original's place, comments on pictures, and layout fixes.

## 2026-10-31 05:06:05 EDT — scribe `77bc308f4cc49fbb45e36e572fa728b956d6bc24`
Merge (#1456): small per-event files are written, never forced to flash; a broadcast minute goes from 654 syncs to 0 with the same writes.

## 2026-10-31 03:41:16 EDT — scribe `dbbe7c8acb0637e88916bb3e0ef6584a559de890`
Docs (#1456): the file-sync decision is ADR 0108.

## 2026-10-31 03:39:24 EDT — scribe `525d3deed411834a35edb9d2f1e3dcad36c4ca61`
Docs (#1456): the sync audit, the file-sync ADR and the budget's file-sync line.

## 2026-10-31 03:39:12 EDT — scribe `6a94040f57eee3cd02de03e77d69382a02a4b184`
Test (#1456): a broadcast minute makes about 287 audio chunks.

## 2026-10-31 03:39:12 EDT — scribe `b5b95d91302b40cf890c4b2cb8af93d373c3cb85`
Fix (#1456): the broadcast extension's chunk, frame and heartbeat files, the frame spool and the recording clock file are written without fsync; renames only where a reader may read at any time.

## 2026-10-31 03:39:12 EDT — scribe `286f2d772e488aa7c4c3c0d9f87cc27aaf6ea7be`
Test (#1456): red: a FileWrites dependency routes six per-event writes, still synced, and three tests count each event's syncs.

## 2026-10-31 03:39:12 EDT — scribe `06fc4d6afc57e9a6773e7bf3eede9857a1c7122d`
Test (#1456): a broadcast minute through the twin, the harness that measures each file path's syncs.

## 2026-10-31 04:26:19 EDT — scribe `3f93488deab9d6170e248d88161c13914d54d0fe`
Audit (#1427): the suites at the change and at its base fail the same tests; the change adds none.

## 2026-10-31 04:16:38 EDT — scribe `d97fb51087f29dce6c2b80701f86174210f90535`
Test (#1465): the live pass of a recording's chapters, running: a new final line asks at once, nothing asks without one.

## 2026-10-31 03:47:13 EDT — scribe `4ae5cc569f9ac373cd994b1bf5ac8e755b312439`
Fix (#1465): the chapters' delegate and helper no longer read as a share entry to the audience guard.

## 2026-10-31 03:33:14 EDT — scribe `7d7dd6f4ba479e92dd2552b1cb749f9e18116b55`
Cut (#1465): Scribe 0.1 (202).

## 2026-10-31 03:18:03 EDT — scribe `af4f04a8525a78326e274eb89cae7c9794da3548`
Feature (#1465): a recording's chapters as the next zoom level out from its lines, on the live screen and in playback, and one share of them.

## 2026-10-31 00:54:58 EDT — scribe `b7a3c85d03368ae6c2cf37213cd727bd6900ad9c`
Feature (#1465): a service keeps a recording's chapters live as it grows and makes them whole when it ends.

## 2026-10-31 00:42:12 EDT — scribe `bad744e6899147731894300d7ee22a035288405b`
Feature (#1465): recordingChapters in the one schema.

## 2026-10-31 03:08:24 EDT — scribe `40ec3dd0fb0863054ca108d3d4d8a773e14ce1f9`
Docs (#1427): the measured before and after: recognizer to another device p50 454 to 62 ms, p95 1,060 to 154 ms.

## 2026-10-31 01:35:23 EDT — scribe `805fa48770eedf08457a4dda0b554d7985a721a9`
Docs (#1427): ADR 0094 amendment B and its audit: the line in progress goes to the room in the recognizer's own pass.

## 2026-10-31 01:27:16 EDT — scribe `dc6adfa8b96d7b259d79da2c88afb02e194d6278`
Feature (#1427): each in-progress line reaches the live room the moment it is heard; saves unchanged; stamps keep order.

## 2026-10-31 01:17:32 EDT — scribe `4b962ee3ba1c9cea2258ad0b5af3e89c61f3ad95`
Test (#1427): red: the line reaches the room with no clock advance and in order; a stale or ended copy never wins.

## 2026-10-31 01:57:46 EDT — scribe `b5a55ab31a7442666fd9116b1c93a231c913c6b1`
Fix (#1473): scribe settings list no longer crashes on the side bars.

## 2026-10-31 02:51:39 EDT — scribe `f2020f41faccbff8024bce7044d3508d2127144f`
Audit (#1455): last week's 9 rejected plans: 5 caught at the time, 5 of 5 the second time; 2 of 128 held-out briefs refused.

## 2026-10-31 01:51:11 EDT — scribe `c8b7473f61caf347bb2d82782e5027114701822f`
Docs (#1455): ADR 0105 and the guide: what he rejects goes in the store; the check before any agent starts.

## 2026-10-31 02:22:45 EDT — scribe `5fbabcbd79a6217fa1d3283751f6b45b1316ec6c`
Fix (#1455): the pre-plan check refuses only what he would recognize at once; an argument is at most a rewrite.

## 2026-10-31 01:48:48 EDT — scribe `5b9175d2b8d8c5fe433304c74625480fe6d59170`
Feature (#1455): the pre-plan check as a red team (Haiku) and a judge (Opus 5.5).

## 2026-10-31 00:44:09 EDT — scribe `9d6dff39071531963d1c496bd512a346c01ddb93`
Feature (#1455): scribe preplan check: read a plan against what he rejected and decided, before any agent starts.

## 2026-10-31 01:05:53 EDT — scribe `fbb9e902f83355095ee0c379da5db6bebc5b2397`
Feature (#1455): the extractor and the scan: each thumbs-down or negative remark becomes one plain rule.

## 2026-10-31 00:44:09 EDT — scribe `86a3832b806c101e3c9f52e498ad59fe2a5fb5fe`
Feature (#1455): scribe feedback: his rejections beside the decision log.

## 2026-10-31 00:22:45 EDT — scribe `b3c17e6436f1d9bff9ca1e1f979a0a0ebd5a7891`
Feature (#1455): scribe decision takes a comment he typed in a Scribe thread.

## 2026-10-31 00:16:04 EDT — scribe `83820239d3e08a30699c6f8be4686ee953985faa`
Schema (#1455): the feedback entity, on production; a Scribe thread is a source of typed words.

## 2026-10-31 02:49:30 EDT — scribe `d59867e2dcf466b9e231f9037842526c89c9d093`
Docs (#1419): the pictures' final counts.

## 2026-10-31 02:48:03 EDT — scribe `44241b6f6dc547301ca69b991e46cd20d2a44586`
Fix (#1419): wrongly attributed change-log entries removed.

## 2026-10-31 02:47:09 EDT — scribe `a5a8fc1ca15e4decdbb7cba2bf8eaaaf8d8ba030`
Docs (#1419): the ADR's final numbers.

## 2026-10-31 02:45:02 EDT — scribe `f1d33d619c78a5d4c1345b54351c5b7922e1f842`
Feat (#1419): green: a stricter evaluation, and more of the app's own frames left out.

## 2026-10-31 01:56:02 EDT — scribe `4c211a16f3ce8661b4320c09bdabb7f117524def`
Fix (#1419): the picture reader's errors never echo their input.

## 2026-10-31 01:44:52 EDT — scribe `c99c5d7f6a9325db3f51432dee39b45f454cea22`
Docs (#1419): the lag measured with the live recording always read.

## 2026-10-31 01:34:05 EDT — scribe `0533b8eb8a8d91530489aa38aa2dd96c1aeff1f6`
Fix (#1419): a hit's picture is its whole path.

## 2026-10-31 01:32:48 EDT — scribe `44ae6f236326df7822117b9a5cee5badb0bc8a72`
Docs (#1419): ADR 0106: local search in one SQLite file.

## 2026-10-31 01:32:10 EDT — scribe `550f414344107615a3368bfb27d4d152054dcc5a`
Refactor (#1419): pseudo-relevance feedback and a trigram index removed: measured no gain.

## 2026-10-31 01:29:06 EDT — scribe `c4721d072475fe09284a4f3e51330ca6e23475f1`
Feat (#1419): green: results named for the question fold into one.

## 2026-10-31 01:17:21 EDT — scribe `f972b8aff4f26f7ede73c50d209063d602fa6e19`
Chore (#1419): plain type names, and two empty tests removed.

## 2026-10-31 00:51:25 EDT — scribe `435a62a5849027bc63fa96d2c08dfaf597c641dd`
Fix (#1419): a picture whose file is gone never reaches the reader.

## 2026-10-31 00:40:16 EDT — scribe `817a58bb5a45eee6271a32c4ae51697468d7f9ab`
Feat (#1419): green: the model and picture reader run on a second machine, with fallback.

## 2026-10-31 00:38:08 EDT — scribe `eb2837074490fb49f97e1ed40dd8f8e2ebd4fa28`
Perf (#1419): green: an idle pass scans no documents, through a partial index.

## 2026-10-31 00:34:05 EDT — scribe `1d80c61d7b368dc9e2e8d8198b7c92359bb796dc`
Feat (#1419): green: the live recording is read on every pass.

## 2026-10-31 00:30:49 EDT — scribe `9a337b90bc1b08ab3db2ae4c3530b060a7798593`
Feat (#1419): green: frames of the app's own screen stay out of the index.

## 2026-10-31 00:28:39 EDT — scribe `5aeb1e8fd7a0b4ef2bf6f379648e803c318d5e2a`
Fix (#1419): the service runs at nice 20: background QoS did not start under load.

## 2026-10-31 00:26:06 EDT — scribe `12af35ef90ac5efc6cf1cc515076b191b7fe22cf`
Chore (#1419): a test script, and the installer uses the node that runs the service.

## 2026-10-31 00:25:16 EDT — scribe `9dab2993d20786dfe4d505a3f07d1015f0602c7f`
Feat (#1419): green: a stuck helper is stopped, and the real service process survives SIGKILL.

## 2026-10-31 00:25:16 EDT — scribe `4c0e42a9953ea3cc77d1702f3113d6659b845667`
Feat (#1419): green: CPU per line measured, no writes when idle, a backfill on a second machine.

## 2026-10-31 00:25:15 EDT — scribe `feb554cbcb6bf8f4f343d4f4ab439bf856a1cb98`
Feat (#1419): green: a local embedding model, a picture reader, per-kind lists and labeled queries.

## 2026-10-31 00:25:15 EDT — scribe `d98b07e9ce9552d4db3ab03580ea171dfaf7742f`
Feat (#1419): green: a search index, its service loop and its ranking, on a fixture.

## 2026-10-31 00:25:15 EDT — scribe `b3ddeec2f8291fbd4cb6482cc1ec284cd979db55`
Test (#1419): red: a search over a fixture recording.

## 2026-10-31 01:43:20 EDT — scribe `d2820ba1adf6e9152df2cb9fd2fb8fbb5bd23971`
Feature (#1466): a line or a picture dragged out of a recording and let go on it again adds nothing; another recording's moment becomes a link.

## 2026-10-31 01:43:20 EDT — scribe `bab27dbdec987cc42a5a06dadc27da59f532d130`
Feature (#1466): lines, selections, pictures and recordings drag out of Scribe with their words or picture and the deep link; a thread takes dropped pictures and words.

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
