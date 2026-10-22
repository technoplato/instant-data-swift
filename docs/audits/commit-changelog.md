## 2026-10-22 04:50:44 EDT — scribe `6df561066e826302b562b7d5e2b05b8504eb6baf`
Merge to main for build 114 (#996): the live transcript takes its width the way Scribe Playback's lines do; Scribe's overflowing text frames 146 -> 0 (iPhone) and 1,016 -> 0 (iPad), Scribe Playback's images identical to the pixel.

## 2026-10-22 04:50:29 EDT — scribe `730060bdb73e374fe85d9fa0a96bd7bc68bbe33a`
Changelog (#996): one entry per commit of the landing.

## 2026-10-22 04:49:59 EDT — scribe `d9425677888edc49541eb5d4097a36a57032a2c8`
Docs (#996): What's New in both apps for build 114, the audit's landing section and index row, PROGRESS, the channel note.

## 2026-10-22 04:49:40 EDT — scribe `5802537a27d978d07393fc8bf5662d2d1c204bbf`
Test (#996): the text layout sweep's 48 image references, rendered once the window stops changing (Scribe Playback's player varied run to run since #992).

## 2026-10-22 03:42:25 EDT — scribe `781f3b7afdf5ec2a4c681d4f310319bfe7ad9b96`
Green (#996): the live transcript's lines take the scroll view's proposal, no measured width; the vertical stamp stops at AX1; list rows' dropped separators get no size; TranscriptLinesShareOneRowTests.

## 2026-10-22 03:42:25 EDT — scribe `bf23ac9b4fd96fcf0544f944ec1af8a3aeaf2ebb`
Red test (#996): the sweep reads every transcript line from SwiftUI's views and hosts Scribe's screens through the list; build 111's live lines run 324 pt off the screen.

## 2026-10-22 03:42:24 EDT — scribe `86e964f287b1b0a096c484885c50d68548cdab4a`
Red test (#996): the first text layout sweep (Xcode/TextLayoutSweep) and TranscriptColumnWidthTests' measured-width check.

## 2026-10-22 02:23:09 EDT — scribe `d97c5d3c9899aea9a29dd1342de9c21a0d514bd2`
Merge to main for build 114 (#992, #993): the speaker's name pinned at the top of the words and Back to Playhead's live-words bubble, one set of views for Scribe Playback and Scribe.

## 2026-10-22 02:21:51 EDT — scribe `18351b8921fa11ac2f362c417089f06deb9d3a24`
Merge of main (#1001's landing) into agent/claude/playback-ui-992-993 (#992, #993): CHANGELOG and PROGRESS keep both sides.

## 2026-10-22 02:20:33 EDT — scribe `a1e37477242ce8ef8bf5f3f0d8aec897ede69082`
Docs (#992, #993): What's New in both apps for build 114 (next), PROGRESS.

## 2026-10-22 02:07:48 EDT — scribe `a661cc5b3b0f0d5eb85ec9ccc9d693bcbb16e7da`
Green (#992): the pinned name hands over when the next name's row reaches its edge (MediaTimelinePinEdge.nameTop, both apps).

## 2026-10-22 02:05:06 EDT — scribe `1100662c7063bad50eab8605f7f442e8106d9eb6`
Red test (#992): the handoff mark is the top of the next name's row, found on the iPad simulator at AX5.

## 2026-10-22 01:47:51 EDT — scribe `c2f6a176d440dfdc7d05b8896e1d5e7c0b7d644c`
Merge of main (24 commits: build 113's hotfix, #995, #1001's plan, this plan) into agent/claude/playback-ui-992-993 (#992, #993).

## 2026-10-22 01:47:13 EDT — scribe `41f5cefa7e10fd50da6ba310f303f93def2ac469`
Green (#992, #993): MediaTimelinePinnedSpeaker and MediaTimelinePlayheadBubble in Scribe Playback and Scribe's playback; Playback's other states unchanged to the pixel.

## 2026-10-22 01:10:30 EDT — scribe `b5a643fb38d97bacd584c580a8a32454bcd2640e`
Plan (#992, #993): playback-ui-992-993's plan, claims and a channel note, landed before the merge.

## 2026-10-21 22:14:47 EDT — scribe `a542c254db32802e3a445fae5524fe19d437bf01`
Red tests (#992, #993): who is pinned, the bubble's words and its arrow, with stubs.

## 2026-10-21 22:11:55 EDT — scribe `8347d8a6d31b34b9708df2b8c983fcfb189a355e`
Before (#992, #993): Scribe Playback's whole player recorded from main 49432a5c4.

## 2026-10-21 19:14:39 EDT — scribe `12e99841958992dfb66d5f72495be2bd1a060c8a`
PROGRESS.md (#924): the schema hazard is gone; main holds #924's author fields and #974's clip slice.

## 2026-10-21 19:10:39 EDT — scribe `c6f1ac25269cbeff4d13078cf5c47e4017c915d8`
Merge to main for build 112 (#924): a text link's chapters list says "From the author's headings"; the audit's production runs and simulator check.

## 2026-10-21 19:10:14 EDT — scribe `b5e33ff4823285c916465c413896a3625ec77116`
Change log for #924's audit commits (1418af7dd, 9fd99faa8).

## 2026-10-21 19:10:05 EDT — scribe `9fd99faa88cfa8752adba4037420bbd79e01c728`
Audit (#924): Scribe Playback on the simulator (the credit on the row, the player and a copied line; the chapters' source diagnosed and fixed), One_Hashing's five figures; PROGRESS.

## 2026-10-21 19:07:55 EDT — scribe `33d054a586091e110579db01369028a401672c37`
Merge of main (192 commits, build 111's cut, #265, #839, #972) into agent/claude/text-links-924b (#924).

## 2026-10-21 19:07:27 EDT — scribe `a3fbe2cf6de889e5daec2a749e14cdc63984c2f3`
Change log for #924 (587e339ab, 482d1423b).

## 2026-10-21 19:07:01 EDT — scribe `482d1423b093a970ab224701906e2edb13c9f8d6`
Green (#924): the chapters list reads where its chapters came from off the chapters it shows (MediaTimeline.State.chapterSource); the player no longer hands in a stale source.

## 2026-10-21 18:53:04 EDT — scribe `587e339ab73682055ec8b99506304d6bf19da58c`
Red test (#924): the timeline's state says where its loaded chapters came from.

## 2026-10-21 18:41:38 EDT — scribe `642250e8831d92f6e9cff2ff59d90f75eb8fc2a3`
PROGRESS.md entry for #839.

## 2026-10-21 18:40:30 EDT — scribe `ab0cf9eadee06e3b09183b722046728e901fd92c`
#839 lands on main for build 112: "Scribe, pause playback" and the Pause Playback intent pause whatever plays (Scribe playback, Scribe Playback, other apps through Scribe's own session).

## 2026-10-21 18:14:27 EDT — scribe `42b9b23a37d3a1e3089d347ef159e0bb782c43e0`
Merge of main (build 111) into agent/claude/pause-playback-839 (#839).

## 2026-10-21 15:40:37 EDT — scribe `d1f8014d0e1340a28507ac50d91cf101b400db28`
Change log for #839 (311289f9b, 7cbd55431, 69e629f4b).

## 2026-10-21 14:42:54 EDT — scribe `69e629f4b12ce51ae817c15b1b6e5cc6258416ef`
#839 audit of what iOS allows (shortcuts, AirPod taps, pausing other apps), ADR 0011 amendment, FEATURES draft item 22, What's New 112.

## 2026-10-21 14:42:04 EDT — scribe `7cbd5543171def192d2dd1ca087615438ba2fda1`
Green (#839): the other-audio pause steps, the store's pause, the voice command on every screen, Scribe Playback's pause.

## 2026-10-21 14:42:04 EDT — scribe `311289f9ba7153a3874e49a359503b53edfc6bc9`
Red tests (#839): pausing whatever plays, with stubs.

## 2026-10-21 12:53:35 EDT — scribe `b0a97bde3d3d18e1d58ebb04fd85a3d7d6f31067`
Plan and claims for #839 (pause whatever plays).

## 2026-10-21 17:50:45 EDT — scribe `cc95ef5e2e6852bd03de516ce163e4975516d5de`
Change log for #972 (9422dbadc).

## 2026-10-21 17:48:42 EDT — scribe `9422dbadc0b2d38b2dfba6f0137f066f5c1c0fce`
Scribe Playback reads a processed book's speakers (12 Rules reads as Jordan Peterson) and marks books not processed yet; 60 tests pass (#972, build 112).

## 2026-10-21 17:48:12 EDT — scribe `fa2e263d9252f3f2b4b70219db4b6ee2de9c880c`
Red tests: the Books shelf knows which titles are processed; the list marks those not processed yet (#972).

## 2026-10-21 17:48:12 EDT — scribe `739c7d19df29fd6c8fa56185c48bab3a0f72eebb`
Red tests: a processed book's words keep each word's speaker, lines split by speaker, the book's media transcript on its words, kept words read again (#972).

## 2026-10-21 16:52:39 EDT — scribe `bff1f97b024aa2aa03bbacb482ff73466e61ee93`
PROGRESS.md entry for #972.

## 2026-10-21 13:52:02 EDT — scribe `8b7c658e0ebb78129807e102804806483784181e`
The #972 audit's afternoon section: the catalog re-key, the queue's first try, the app step.

## 2026-10-21 13:50:49 EDT — scribe `22a2d24dc6cf42e7af4a566cc99a480c07facb6a`
Claims for #972's amendment 1.

## 2026-10-21 13:41:40 EDT — scribe `f9272cd32ffed4f4da05c5930bc1baf125ca072a`
Plan amendment 1 for #972 (Scribe Playback speakers and the not-processed marker).

## 2026-10-21 16:04:37 EDT — scribe `b1e09374a837f82a375fd1a3c989a87d1fb80517`
#965 lands on main for build 111: merge of origin/main (7964d57fa) into agent/claude/active-line-965, pushed as main.

## 2026-10-21 15:02:28 EDT — scribe `3aa3339857af00a5b392d15a3aa51b867810f33f`
Merge origin/main (b511deba3) into agent/claude/active-line-965; What's New 111 keeps both sides (#965).

## 2026-10-21 15:01:29 EDT — scribe `36c2195a094f95f36ba6b2a1a81b5041e9122a85`
Change log for #965 (8443b416f); PROGRESS.

## 2026-10-21 14:33:25 EDT — scribe `4aeae8b53d24f48fb411f36fad4b1d265d6a1176`
What's New for build 111: the line you're speaking stays at the bottom of the live timeline (#965).

## 2026-10-21 14:33:09 EDT — scribe `7d37badbdb1009132f53bdc1824b41a0f65e13e9`
The one-clock audit (audits/2026-10-21-one-clock.md) and FEATURES item 2: the line being spoken is the bottom row (#965).

## 2026-10-21 14:33:00 EDT — scribe `8443b416fffa679c1d35497287aa56b4c1cb1981`
TimelineEntry.liveOrder: a line not final sorts after every row not being spoken; the recording screen and playback following a live recording use it (#965).

## 2026-10-21 14:33:00 EDT — scribe `47eed27c2ea3809bafd6c5667e51ca81cb1a02c4`
Red tests: the line being spoken stays the bottom row of every live timeline (RecordingLineBeingSpokenTests, RecordingSpeakerRunsTests, PlaybackLineBeingSpokenTests) (#965).

## 2026-10-21 14:09:52 EDT — scribe `1418af7dda34f15044dfe3a6bdf8420d74701ddc`
Audit: the production runs of calabro.io/ohbf and One_Hashing.pdf, rows per stage, word times, Kokoro right at line starts (#924).

## 2026-10-21 14:08:55 EDT — scribe `c111eb0536166fc10b8824fc14766c57edaa4069`
Merge to main: a figure MuPDF reads among a paper's references stays the document's (#924).

## 2026-10-21 14:08:36 EDT — scribe `b35f62081c994d4b8c38e566e5c79f1a5dfd14f3`
A figure MuPDF reads among a paper's references stays the document's (One_Hashing.pdf's Fig. 6) (#924).

## 2026-10-21 14:08:18 EDT — scribe `e9997a876f94f682eb3dbce1b05d40e77b9a5f04`
Red test: a figure read among the references is still the paper's (#924).

## 2026-10-21 13:42:02 EDT — scribe `11aab648608744860e624f2f50d92ca63e15907f`
Merge to main: whose words a text link's are, everywhere it shows; the reader credits feeds and papers; one library owner (#924, build 112).

## 2026-10-21 13:40:57 EDT — scribe `807fcdfa9fa9077f5f7a0a556312245f08c2793e`
Change log and PROGRESS for #924's attribution (8dabb1ea2 .. 25e4b2bb9).

## 2026-10-21 13:40:28 EDT — scribe `610f58b109b6fa5e0fa1bf1905f00b1a89fc9ff1`
ADR 0082 Text links 9, FEATURES item 20's attribution, the audit's attribution section (#924).

## 2026-10-21 13:40:28 EDT — scribe `2b0a4e825aefc507132ee9ee56ebcb521d3f495f`
Scribe's timeline says whose words a text link read aloud are: RuntimeMediaPlay author and credit, the summary's subtitle (#924).

## 2026-10-21 13:40:28 EDT — scribe `25e4b2bb9f5f53393c7333f110af36f5826e1412`
swiftui-pro review: the timeline row's own VoiceOver label reads its subtitle; one ShareLink (#924).

## 2026-10-21 13:33:56 EDT — scribe `e297da40f149fd5bcfb5d4aa02ad3369d86e4089`
Rules matrices check mediaItems.author and videoQueueItems.author (#924).

## 2026-10-21 13:28:03 EDT — scribe `bb7df3dce1009bb2612c3ea95a365d0bb8e00fda`
One library owner for every writer of a text link's rows: the laptop's SCRIBE_MAIN_ env and the mini's owner (#924).

## 2026-10-21 13:27:10 EDT — scribe `19cb7528fc2aaf32799a0a1c7f047935ad5254d4`
Red tests: one library owner for every writer (#924).

## 2026-10-21 13:22:05 EDT — scribe `2f52233f00dde59a3cfef966280ce957f896c5c4`
A paper's byline row in a shared block, small-capital sections, levels by numbering (#924).

## 2026-10-21 13:19:52 EDT — scribe `c8dc24952a1710e0275b2402e91a2a7a7ee11cd0`
Red tests: a paper's byline in its affiliation's block, small capitals, numbered depth (#924).

## 2026-10-21 13:16:33 EDT — scribe `24327e80bd540008de24a0b13f2d1e555ccb421d`
scribe-text-links skill credits the writer; installed for Claude, Grok and agents (#924).

## 2026-10-21 13:15:05 EDT — scribe `b2fff1ee0d1e3397878450cca16792211b54edfd`
Scribe Playback says whose words a text link's are: row, player, Lock Screen, copied and shared lines, chapters (#924).

## 2026-10-21 13:14:55 EDT — scribe `8dabb1ea2caac02c5f6641ccb6fc58a3622eee7b`
The reader names whose words a text link's are (JSON-LD, citation_author, the page's own feed, a paper's byline); mediaItems.author and videoQueueItems.author (#924).

## 2026-10-21 12:59:39 EDT — scribe `85afa00ab22fe906ef0f670d31524ad6e5540078`
Red tests: a text link read aloud names whose words they are, everywhere it shows (#924).

## 2026-10-21 13:38:50 EDT — scribe `f66e218f420208d58599addec383ceb2477a0398`
Change log for #972 (a185740e3).

## 2026-10-21 13:29:15 EDT — scribe `a185740e351139e80982a05bda52c87ad56e9b68`
media_catalog.py books --rekey: the three books signed under audiobook:books:<slug> move to audiobook:<rendition id>; run on the mini, the live server matches the new key (#972).

## 2026-10-21 13:28:37 EDT — scribe `7175b5c2aa5aa34ad89518b9295de6ac682ce2c8`
Red test: media_catalog.py books --rekey (#972).

## 2026-10-21 13:26:30 EDT — scribe `bd468763781293757e4a1034d08dc9f36dbf5682`
Change log for #972 (5634dcb15, 2cc934b4c, cbc585543).

## 2026-10-21 13:26:09 EDT — scribe `cbc58554334e92af5beac3910bb1568b191a7793`
The books queue as a LaunchAgent, com.knophy.scribe-books-ingest, every 30 min in #927's venv (#972).

## 2026-10-21 13:25:31 EDT — scribe `2cc934b4cd34212ffb697c86ce1713d9bec5f1cd`
Three failures in a row for one title set it aside with its reason (#972).

## 2026-10-21 13:25:21 EDT — scribe `d1842c0da87b148781cec8c22610195bdd966e6e`
Red tests: three failures in a row set a title aside (#972).

## 2026-10-21 13:25:02 EDT — scribe `5634dcb159127b000392ae8576f8dca008f904c5`
The Audible queue: one Audible title and at most one license try a pass, under #927's retry lock; the local copy goes after the catalog step (#972).

## 2026-10-21 13:23:06 EDT — scribe `40b004cb83d2679b9b99e53f33ffec3cab5c8f3e`
Red tests: the Audible queue's order, account-wide license spacing counting #927's tries, each title's ASIN (#972).

## 2026-10-21 13:21:21 EDT — scribe `e0b1b3a87f1add1fc68d7488d71164764660915c`
Change log for #972 (302b648be, dddd57470, 901e66b9f, a31e8c72a, a78c1fd18, ff8a104a9).

## 2026-10-21 13:20:32 EDT — scribe `ff8a104a92f1bbb28594a77b06d6c91c1d757a88`
The books ingest README and the #972 audit: A New Earth 9.24 h in 544 s (61 audio-hours an hour), voices 55% of a job, three books written with speakers.

## 2026-10-21 13:20:32 EDT — scribe `b4c590fef31df77c94a53313aeda93f424a3f726`
Red tests: with one credited narrator, a voice of under ten seconds in an hour piece is the narrator's (#972).

## 2026-10-21 13:20:32 EDT — scribe `a78c1fd182d395a7b25139c87a06d5fedcafe26a`
A voice of under ten seconds in a piece is the narrator's: 21 Lessons' seven such voices were chapter-start splits and Audible's closing line (#972).

## 2026-10-21 13:20:32 EDT — scribe `a31e8c72a523de1c514e3c289bfe93af9352b3a5`
write's last log line named segments twice (#972).

## 2026-10-21 13:20:32 EDT — scribe `a060bf3c7094fe6ed1ea5143a0759b62411a414b`
Red test: a book's credits outweigh a print's guess (#972).

## 2026-10-21 13:20:32 EDT — scribe `901e66b9f8b799a2cde9eb891b083f55ace7f021`
A suggestion stays only when it names a credited narrator; A New Earth's one guess was Joe List for the publisher's announcer (#972).

## 2026-10-21 13:20:31 EDT — scribe `dddd574700c55069d7f491e61543203a0502ee76`
books_ingest.py: status of every Books title, process a rendition through /v1/process in hour pieces, write its words with book-wide speakers into Books' librarySegments and the book's media transcript (#972).

## 2026-10-21 13:20:31 EDT — scribe `1c24c08b8ba3dbf37335f126d90ad62b4eed4760`
Red tests: books_ingest.py's pure core (Books' own segment ids, the priority rule, speakers across hour pieces, words on the book's clock, merged names, segment rows, the media document, status) (#972).

## 2026-10-21 12:57:57 EDT — scribe `302b648be1b8295b2abc961e74e6219af5e861ba`
Plan for #972: every Books audiobook through the mini's /v1/process, words with speakers, and which are not processed yet (plan, claims, channel note).

## 2026-10-20 07:44:36 EDT — scribe `67ee18d124ac728d6704d9e4633225d233e71d12`
Merge of #858 onto main for build 111: a reminder plays the lines that made it (the newest-first logs kept as unions).

## 2026-10-20 07:44:36 EDT — scribe `3b2e64f45324d5b9c5c8d478df6602f00e3646a2`
Change log and PROGRESS for #858 (c4ac34171).

## 2026-10-20 07:44:36 EDT — scribe `2413ee9f9e1d7cfa5ef175598dc73f77cb3b7241`
What's New for build 111: a reminder plays the lines that made it (#858).

## 2026-10-20 07:44:36 EDT — scribe `31d20c2122758a08e3c50837b976597a9bbbbd82`
ADR 0054 amendment 3 and FEATURES line 19's Play (draft) (#858).

## 2026-10-20 07:44:36 EDT — scribe `c4ac341710435a98769d8eae1dbb055a65166031`
Play plays a moment's lines where its recording is and stops at their end: playback's range, the live player's stretch (headphones only), the list's routing; the Work Log Play button's 44-point target (#858).

## 2026-10-20 07:44:36 EDT — scribe `ee25babe8b63b5dd1d0357646e3b09e2e9c0d33a`
A moment plays its lines: ReminderMoment.play, his words as heard, Play on a card and in the Work Log (#858).

## 2026-10-20 07:44:36 EDT — scribe `7d099a0a14f42cf51dd07210b136d480ed2f2600`
Red tests: a reminder's Play plays exactly the lines of its moment, in playback, in the live player, and from the Reminders screen (#858).

## 2026-10-20 07:41:16 EDT — scribe `0b7b6498ac7b5e87239cbf00e9918a7b40bf48a4`
Merge of #859 and #862 onto main for build 111: his synced words reach Parakeet on This iPhone and Your Mac, an edit reaches the running stream, and a listener adds a word.

## 2026-10-20 07:41:16 EDT — scribe `7d52ae2218aac93c7b6ec166fb566ec7c372d3e2`
Change log and PROGRESS for #859 (a789e1b60, eb6b13a67, ac364f6bf) and #862 (64c46e1b0).

## 2026-10-20 07:41:16 EDT — scribe `ae1c13d659459e1ded2e717d4c18326c11bd72a9`
What's New for build 111: his vocabulary reaches On This iPhone and Your Mac, the vocabulary model, and a listener adds a word (#859, #862).

## 2026-10-20 07:41:16 EDT — scribe `47c5249689a9d3bc470d0547dc7d133a99ae67d5`
ADR 0062 amendment C with the word error measurement, ADR 0074 amendment A, FEATURES line 12, and the audit (#859, #862).

## 2026-10-20 07:41:16 EDT — scribe `ac364f6bfc8e8e8a7ba30c062efca680a7b7a66d`
The booster leaves a phrase around a listed word (in Scribe) to the correction map; measured on his recorded audio (#859).

## 2026-10-20 07:41:16 EDT — scribe `f29136469a8d8eeb98e702bd0d3094ff9be3c1ad`
Red tests: a phrase around a listed word does not travel to the booster (#859).

## 2026-10-20 07:41:16 EDT — scribe `eb6b13a67a09236d197cbad4b7e91b46b2958361`
On This iPhone and Your Mac send his synced words as keyterms, send an edit as Configure, log the engine's answer, and download the vocabulary model after the others (#859).

## 2026-10-20 07:41:16 EDT — scribe `a5b52ca6caf43fdb6ba78448486ec2e6c04a01dc`
Red tests: the app's keyterms, the Configure frame and its outcome, and the vocabulary model download (#859).

## 2026-10-20 07:41:16 EDT — scribe `a789e1b60da20de1e82535cf8140cffebdade9f9`
The engine boosts his words from the listen request's keyterms, rebuilds on Configure, merges the Mac's file, keeps punctuation, and never needs the vocabulary model (#859).

## 2026-10-20 07:41:16 EDT — scribe `e9bb31fe4bc111e1654bb050bf702a925d62a687`
Red tests: keyterms and Configure on the wire, the merged list, the punctuation carry, the optional vocabulary model (#859).

## 2026-10-20 07:41:16 EDT — scribe `64c46e1b0e7a3642b24051b2ea54e25111fbd0da`
A listener adds a word to his vocabulary through scribe, with the line he said it in, and can undo it (#862).

## 2026-10-20 07:41:16 EDT — scribe `ac0f5fd9f0aae7be30f9ff43d3e9df49c417cff9`
Red tests: the mirror's vocabulary model, the add plan and its change row, and undo (#862).

## 2026-10-20 03:25:31 EDT — scribe `b502641ba56b854539c07e9369979f32bdd9b64f`
Changelog and PROGRESS for #815: a reminder tracks the work as it happens; the implementation commit is 6b97bfc79.

## 2026-10-20 03:33:18 EDT — scribe `d34a7e3e3b5733ac612635819f9705e666bf8604`
Change log entry for book readings matched on demand only (#922).

## 2026-10-20 03:33:18 EDT — scribe `e6e1d2cf3519a9ce6a31bc517308323fb3590b2f`
Book readings are matched on demand only: their pieces and catalogs sit beside the live folders; the live scribe-books keeps its audiobooks (#922).

## 2026-10-20 03:33:18 EDT — scribe `8e1b07a3ab9f341dcaf1486bc045bc5c2a2446f0`
Red tests: a book reading's on-demand folders, signing, build, rows and measure; every other kind stays live (#922).

## 2026-10-20 03:33:18 EDT — scribe `19ffd7dfab41d904c858852f0f90c8f5e0f95861`
Plan step 8 for #922: readings matched on demand only (their bedtime audio false-matched 3.6% of live windows); claims and channel note (#922).

## 2026-10-20 03:25:31 EDT — scribe `6b7f8a6b1623fd9e98e5e31c712169d4a55d8ef0`
Tests for the clock a check-off enters: Recording.State.liveClock(now:), LiveRecordingClock, and the live point (#815).

## 2026-10-20 03:25:31 EDT — scribe `fb61d630cabf708979781a88c451f0f9e6305a91`
ADR 0054 amendment 2, FEATURES line 19 (draft), What's New for 110, and the listener's start and progress (#815).

## 2026-10-20 03:25:31 EDT — scribe `9cb0727df257546aca1bfe758fa5dfdce077abed`
The moment snapshot test helper builds InstantMaterializedValue values, so the app suite compiles (#815).

## 2026-10-20 03:25:31 EDT — scribe `b29d6895397b75db312e4922c3b5747664f8281a`
The reminders rules matrix covers a reminder's start and context and a moment's mentionKind; 111/111 on the throwaway app (#815, #823).

## 2026-10-20 03:25:31 EDT — scribe `6b97bfc79c09dd7f32eae9b0121906b709d0f1a6`
A reminder tracks its work: Start Working, the listener's start and progress, Marked done in the recording this device captures, how long it took, a work log; schema pushed to production (#815).

## 2026-10-20 03:25:31 EDT — scribe `c92a68c7e52800df289cecc262b7cb7fc8806763`
Red tests: a reminder tracks its work, and the reminders-work schema module (#815).

## 2026-10-20 03:25:31 EDT — scribe `f9a91fb45322e133f66b8b7858021860d32e0605`
Channel note: one stretch-play action in the live player, shared by a reminder's Play and a tap on a live line (#858, #807).

## 2026-10-20 03:22:29 EDT — scribe `639f46890a5bbf0d38544704e080b24ad09701f0`
Change log for the standing listener's start through taskpolicy -a (#870).

## 2026-10-20 03:22:29 EDT — scribe `40f6128b5f1d93284cf74de69bef9acc2afe30ef`
green: the standing listener starts through taskpolicy -a, so its main thread runs at 46-47, not 31 (#870).

## 2026-10-20 03:22:29 EDT — scribe `b2db524a3a316fd437f929726f19ffbdfcb544a3`
red: the agent run-agent starts must run its main thread above priority 31 (#870).

## 2026-10-20 03:22:29 EDT — scribe `99900d0751812fba7edb8c6425f7f874b8f2849b`
plan and claims for #870 and #880 (infra-p2).

## 2026-10-20 03:20:36 EDT — scribe `a2234a936afdcd2282040c6f9119bbcbff790d73`
Change log for the retry's guarded read-back (#927).

## 2026-10-20 03:20:36 EDT — scribe `a2bde6dfe38b64a1af69b61081034d10cc56d543`
A failed read-back after an import is told on the issue instead of stopping the retry (#927).

## 2026-10-20 03:09:47 EDT — scribe `e8f3de6a8ba6734bdc563ec5f78865fdaa00f6dc`
the narration's measures run after the import; no false matches on the trial (#927).

## 2026-10-20 03:09:47 EDT — scribe `d7dd650ea97b21e65eb2eb13192999713c3cbd63`
the retry's tests, the narration's measure and its hook after the import, the audit's false-match check (c4ad78444..8ca7e75a8) (#927).

## 2026-10-20 03:09:47 EDT — scribe `8ca7e75a884d2825b15d9940c457895dc2c3df58`
the trial drew no false matches from the live catalog (0 of 40 per condition); the measures run after the import (ADR 0087 decision 9) (#927).

## 2026-10-20 03:09:47 EDT — scribe `fdc31393cef94bdab8a0e145fdf50e209b04c94e`
green: after an import the retry measures the narration and logs one line on the issue (each catalog condition, the word times, or why they did not run); the installed copy carries word_times.py (#927).

## 2026-10-20 03:09:47 EDT — scribe `d4901a25abff4766c9be7bde6cef6c91b6205e90`
green: the measure's catalog entry names its source audiobook, one of scribe-catalog's kinds (#927).

## 2026-10-20 03:09:47 EDT — scribe `6023c572e1d49457896c80d084347cd96a1d410b`
green: `audible_import.py measure` keeps the narration's two numbers in <title>/measure/: the catalog's match rate and offset error on clips from four hour-long excerpts against the live scribe-books (read only), and wor (#927).

## 2026-10-20 03:05:54 EDT — scribe `9d6eeb25c4b682b45260e765a76ce3dbda1304a0`
Merge of #701 into main: Settings > Your Mac shows the server's last heartbeat (criterion 2); the health watch tells a busy laptop from a down server.

## 2026-10-20 03:05:54 EDT — scribe `e7f5b8b46db3a7066fa798b02276095aeb687267`
Change log entries for #701's two greens (56ee10427, 311a01b1d).

## 2026-10-20 03:05:54 EDT — scribe `311a01b1d6cb3f86884a4e1ef4aaab3aab005d43`
The Mac health watch: a check whose own timer fired over a second late is 'not checked' and changes nothing; the LaunchAgent runs node through taskpolicy -a, Interactive (#701, ADR 0073 amendment D).

## 2026-10-20 03:05:54 EDT — scribe `be08504b8c4be701f936b3aa81e345c52fdded46`
Red tests for the watch: a busy laptop is not a down server (#701).

## 2026-10-20 03:05:54 EDT — scribe `56ee104270546347bede6b31cdc128ffac2a7f74`
Settings > Your Mac shows the Mac mini's last heartbeat from Instant under Last Check, followed only while on screen (#701 criterion 2).

## 2026-10-20 03:05:54 EDT — scribe `25ffb3dd6900743a62bbc55cb36cb58d19f44e55`
Red tests: Settings > Your Mac shows the server's last heartbeat (#701 criterion 2).

## 2026-10-20 03:05:54 EDT — scribe `206a753a4ab4a6dab87d6f01a784a62d85e32209`
Channel note to #861: ScribeSyncLedgerTests wants a Sync noun for speakerChanges (#701).

## 2026-10-20 03:05:54 EDT — scribe `ca879067009eb06aac0d9cb89d2f43d889acbe91`
Plan and claims 701-busy-laptop-not-down (#701).

## 2026-10-20 02:57:12 EDT — scribe `9aaf875538c532b679a759f19cc60938012c80a8`
NOW.md is the read-first page; handoff.md keeps active sections (11196dec4) (#833).

## 2026-10-20 02:56:23 EDT — scribe `d4d3bd5f3428a4a2ac2a0ecdfa39f2cb3d7990c0`
NOW.md is the read-first page; handoff.md keeps active sections; guidance, drill, audit (#833).

## 2026-10-20 02:55:58 EDT — scribe `2d7728257628ee1ebaa63f7fa235764c48d7a455`
Audit: the read-first set before and after, the archive's proof, every writer, the Background starvation, the drill (#833).

## 2026-10-20 02:53:33 EDT — scribe `11196dec4f2a6bfee639d5ba445272604e5b351f`
Green: finished sections move after 12 h idle, open ones after 48 h, no-issue ones after 24 h (#833).

## 2026-10-20 02:52:02 EDT — scribe `80b95bb821322645b681d028b912d3abf94f4dd6`
Red: a finished section moves after 12 h idle, an open one after 48 h, one with no issue after 24 h (#833).

## 2026-10-20 02:49:31 EDT — scribe `167d43239ee630b66f7912ca507789b5e22b6284`
Green: the page counts the WAITING lines it leaves out and names handoff-now --waiting --all (#833).

## 2026-10-20 02:48:17 EDT — scribe `eefbff4833448eede4507d36b6e0fbbed48d1517`
Red: the page counts the WAITING lines it leaves out and names the command that explains each (#833).

## 2026-10-20 02:47:27 EDT — scribe `7a8bb0332ed125d34eea8415c4498a7291b0a834`
Scripts/handoff-now/README.md: commands, where it runs, the lock and the archive, tests (#833).

## 2026-10-20 02:46:21 EDT — scribe `243afb6d15b0cdd0ae9c33bfa26eedd4225a8d1c`
AGENTS template: read NOW.md first, handoff.md sections on demand, and who keeps them (#833).

## 2026-10-20 02:46:11 EDT — scribe `3c4963df5c5967ce667dae9f09a06970b060ec70`
Green: the page's opening names handoff-now --add beside --section (#833).

## 2026-10-20 02:45:35 EDT — scribe `93f5af6c1e5b184b9936a155cf65e35faee667ae`
Red: the page's opening names handoff-now --add beside --section (#833).

## 2026-10-20 02:43:06 EDT — scribe `07214152e04d63d27771283655d359957568d15f`
Green: the page shows each agent's own last step, not agent-run's resume lines, and reads work-log ids as signers (#833).

## 2026-10-20 02:43:06 EDT — scribe `e81dd17ca8f64fd1ecc28badb36eaf1269a889f3`
Red: agent-run's resume lines are bookkeeping, and claude-code/<name>@<account> signs for <name> (#833).

## 2026-10-20 02:43:06 EDT — scribe `5aa886040a0c53479ea125ab07a058a919f6fe5b`
Green: handoff-now --add writes an agent's dated line into its section under the lock (#833).

## 2026-10-20 02:43:05 EDT — scribe `0fdf4aedcb221bd205a3bc52e0ac8412cd701849`
Red: handoff-now --add puts an agent's dated line in its section under the lock (#833).

## 2026-10-20 02:43:05 EDT — scribe `363815259d96b1d8a70b3cafabbc7924f247fce4`
Green: the page names each running agent's log and folder: the usual places once, the rest by name (#833).

## 2026-10-20 02:43:05 EDT — scribe `123fd0821c7bb701ada125e736dd36f0f055f081`
Red: the page says where each running agent logs and works (#833).

## 2026-10-20 02:43:05 EDT — scribe `5131068323372bc8e476a722cfd25378d0793ffe`
Green: the LaunchAgent runs as a Standard process (Nice 10), so the page's issues stay fresh under load (#833).

## 2026-10-20 02:43:05 EDT — scribe `4c6502b54bcb29179adb34f16e117772f7ad6cf9`
Red: the LaunchAgent must not run as a Background process (#833).

## 2026-10-20 02:43:05 EDT — scribe `d26f5a5fcfa93dd4c8ef6a951a969e4f139ee097`
Green: the archive compares again when the file changed after its comparison, and watches the file it replaces (#833).

## 2026-10-20 02:43:05 EDT — scribe `e59f966409516582b097a1cedf46eaa899dab802`
Red: a file renamed in between the archive's comparison and its swap loses that writer's line (#833).

## 2026-10-20 02:43:05 EDT — scribe `ab7f03182be1adfb844af6e06d4fc84d4bcb4037`
Green: the page reads the real handoff.md right: negations, a line's own issue, one row per agent (#833).

## 2026-10-20 02:43:05 EDT — scribe `a141cab6acd72bb0b0bf1d3adf19a106486d0ff1`
Red: what the real handoff.md taught: negated waiting lines, a line's own issue, one row per agent (#833).

## 2026-10-20 02:43:05 EDT — scribe `76b76293a3457f5e6bcb60def20063e63b2e3268`
Green: tools/handoff-now writes the Now page under 4,000 tokens and archives handoff.md's finished sections (#833).

## 2026-10-20 02:43:05 EDT — scribe `24b0ec1722201d816bd5d1ca708cb4b538ca840d`
Red: the Now page under 4,000 tokens and an archive that keeps handoff.md to its active sections (#833).

## 2026-10-20 01:10:25 EDT — scribe `7d021abb193deaf5cf38f43c14fc109257bb98a9`
A generated Now page read first, handoff.md archived to active sections: plan, claims, channel note (#833).

## 2026-10-20 02:57:06 EDT — scribe `c539dac0ab9907a71d0e9cff5e9f9ae15f0c51ce`
Change log entries for FoldKit Books' library in Scribe Playback (#929).

## 2026-10-20 02:58:34 EDT — scribe `04f714e1ed223d483695e492a46b70733bffd637`
Change log entry for a book reading's clip following its recording's audio (#922).

## 2026-10-20 02:58:34 EDT — scribe `d5ab62bed6a15b682458483e62350e06c18e7d3b`
The media README says a book reading's clip follows its recording's audio: the shift, the second pass, audioShiftSeconds (#922).

## 2026-10-20 02:58:34 EDT — scribe `d3d2a05e2100875584e6055e9165fadf9f0b2941`
A book reading's clip follows its recording's audio: run measures the shift from its own words after a first pass and cuts it again; five of 31 clips sat 2.96-14.9 s off (#922).

## 2026-10-20 02:58:34 EDT — scribe `343a12ec07b0b63e61fc00c6e6fa0670214cc470`
Red tests: the audio shift from paired word starts, the half-second threshold, the shifted cut span, the meta keeping the shift (#922).

## 2026-10-20 02:58:34 EDT — scribe `a08ec30a0d0443a3adcea6b38733a0efa6a70b5b`
Plan step 7 for #922: a clip follows its recording's audio; #934 filed for Recording 187's two overlapping readings (#922).

## 2026-10-20 02:58:34 EDT — scribe `d88b7f9a91e7ec6765e7eb7aeb3b0c86ffc8a8cf`
Plan and claims for a book reading on a person's page: the speaker index's kinds and list (#922).

## 2026-10-20 02:57:06 EDT — scribe `42ae263a07f93516ceda5ec0a6e7043e214c31f5`
Scribe Playback's What's New for build 110 and FEATURES.md line 18 (draft), Books, one library (#929).

## 2026-10-20 02:57:06 EDT — scribe `4acebb260146e45cc4d91f1f04e4522a118f8c49`
The live library's save takes its client, so a local Instant store proves the phone's write path (#929).

## 2026-10-20 02:57:06 EDT — scribe `349d9aa7fac0039ffdd718e38e47e88e69d9ec49`
Red: the live library on a real Instant client with a local store (shelf, a first place, the same row updated, a finish) (#929).

## 2026-10-20 02:57:06 EDT — scribe `f2d0721b850a13741143b8c3740d3a14abc162aa`
scribe-videos books: Books' shelf from the terminal with Books' own query and rules; the Books list's swiftui-pro fixes (#929).

## 2026-10-20 02:57:06 EDT — scribe `cd97cacaa67b6bcedbe3ffa4d47cfa946a0c1930`
Red: the admin client reads Books' shelf with Books' query and rules (#929).

## 2026-10-20 02:57:06 EDT — scribe `8f05c27939579a0ba08c362d10292ae5adeeaa5e`
Red: the terminal reads Books' shelf with the query Books' deployed build uses; the fixture carries it (#929).

## 2026-10-20 02:57:06 EDT — scribe `9531447e43d403f3e12354430d359ba0b1d8f29f`
Green: Books' library in Scribe Playback (core, the Books list, a book in the one player, the live library on the app's Instant client) (#929).

## 2026-10-20 02:57:06 EDT — scribe `f8eb6a1c7de3dd82f4d0f18d04c68aa574e72ea1`
Red: the library rows declared as the schema declares them; the library's answer read as Books reads it (#929).

## 2026-10-20 02:57:06 EDT — scribe `6917b468ce82b8981bc9a99e7fa50200a88cc0af`
WIP from a run that stopped: the Books list, the app's book flows, a book in the one player (made green in 9531447e4) (#929).

## 2026-10-20 02:57:06 EDT — scribe `b99775eec1aeb0543c16e24bdbf83ca41b5dd98c`
Red: the Books list, the app's book flows and a book in the one player (#929).

## 2026-10-20 02:57:06 EDT — scribe `84b5e124a6f9fb260bbfe0591a105916dd97d69b`
WIP from a run that stopped: the core's books, words and audiobook cases (made green in 9531447e4) (#929).

## 2026-10-20 02:57:06 EDT — scribe `671ce022d3fe2baef40a583bb1a479935744d980`
Red: Scribe Playback reads FoldKit Books' library as Books does, held to Books' own deployed code (#929).

## 2026-10-20 02:55:04 EDT — scribe `11201b6e9f34482bff11dfdf259465baa23eadd4`
PROGRESS entry for the Audible import (#927).

## 2026-10-20 02:55:04 EDT — scribe `3f9da32344278f6958ec879f63a4048fba43e36f`
Change log for the Audible import (#927).

## 2026-10-20 02:55:04 EDT — scribe `a6cadcf2bcadd82d0cb4febb73d2699f63421e1c`
ADR 0087 and the Audible import's README (#927).

## 2026-10-20 02:55:04 EDT — scribe `3ac9b31f7acc228aa517c480eee832a4dff40d9d`
install-launch-agent.sh: com.knophy.scribe-audible-retry every 30 minutes (#927).

## 2026-10-20 02:55:04 EDT — scribe `631fb881e7b3e3aa74bdd22c89740fc7c0562d19`
audible_import.py queue and retry: spaced retries until Audible grants the license, each try on the issue (#927).

## 2026-10-20 02:55:04 EDT — scribe `7d85f990cd4068ab013a5db7530168a8b14f7b8c`
audible_import.py check: the import's writes through production's rules as the owner, rolled back (#927).

## 2026-10-20 02:55:04 EDT — scribe `380259398dd52d96456b1376b38bb34d973fc68e`
Audit: Audible's CustomerThrottled refusals; on a public-domain trial the catalog's match rate and Parakeet's word-time bias (#927).

## 2026-10-20 02:55:04 EDT — scribe `5bcb4752997db96f3250f629545fc20d13beefed`
word_times.py: the onset looked for near the two starts at the halfway line; median signed difference (#927).

## 2026-10-20 02:55:04 EDT — scribe `2da7f81252a10f32012c9281e920d0349a473212`
install.sh --align makes the align venv (#927).

## 2026-10-20 02:55:04 EDT — scribe `02e8a423ebe8c63eeb7591c02ec48b5c1982e44a`
word_times.py: the words after a pause held against the sound's onset (#927).

## 2026-10-20 02:55:04 EDT — scribe `df3b024a03e7e863da9dd031e1817681f98b25ff`
word_times.py: Parakeet's word starts against a forced alignment (torchaudio MMS_FA) on sampled minutes (#927).

## 2026-10-20 02:55:04 EDT — scribe `108f9e8ed224dfb2cc953df0aba8b070d3ab6470`
A Books title is filed and signed under Books' own key, audiobook:<rendition id> (#927, #929).

## 2026-10-20 02:55:04 EDT — scribe `bd82580542e8f7e7a80ab70250d7bbcd9d850518`
media_catalog.py books --only <file>: one audiobook signed, its entry naming the library's rows and ASIN (#927).

## 2026-10-20 02:55:04 EDT — scribe `28065637f5dd3264f2873a05688dae844d6950de`
audible_import.py: his own Audible purchase into the Books library through Books' saved login (license, .m4b by ffmpeg -c copy, Books' importer, audio, words in hour pieces, read-along segments, catalog) (#927).

## 2026-10-20 02:44:30 EDT — scribe `dde79e52ac12bdfc1438bb0bf6e24ef4d4359609`
Change log and PROGRESS entry for Scribe Playback's full-screen split (#928).

## 2026-10-20 02:44:30 EDT — scribe `b8228d09885a86d82788c10a7025680b229989bc`
Audit of the full-screen split: the snapshots' frames, the tests on the merged code, the divider's frame-time method (#928).

## 2026-10-20 02:44:30 EDT — scribe `ac6f71a603093b4a234a92280a46c9d564c45736`
Hide Video and Show Video fold the picture without animation under Reduce Motion; the split's slot roles in their own file (#928, swiftui-pro review).

## 2026-10-20 02:44:30 EDT — scribe `9c026086395fb7c4fb2154a6297f233fef74d558`
The media timeline harness asks for portrait too, so the divider's frame times measure full screen stacked (#928).

## 2026-10-20 02:44:30 EDT — scribe `04d7cdba285ba5f5958cfaa2c16ba76ae00f88e8`
Full Screen and Exit Full Screen move the picture and the words without animation under Reduce Motion (#928).

## 2026-10-20 02:44:30 EDT — scribe `96b8e8e13db7fe968851ffb3a534b65377965e11`
ADR 0086 (the full-screen split), FEATURES.md item 15's draft line, Scribe Playback's What's New for build 110 (#928).

## 2026-10-20 02:44:30 EDT — scribe `e97d4bb2b0571d5eb197494226968b00049ef078`
The media timeline harness's split mode and autodrag, for the divider's frame times (#928; compiled on the mini before the merge).

## 2026-10-20 02:44:30 EDT — scribe `3a0fd94f8a3fcbcb7f61462faf181dfff22ae153`
Full screen in Scribe Playback's player: the video beside the words in landscape, over them with a divider in full screen (#928).

## 2026-10-20 02:44:30 EDT — scribe `30ad061d55fc592d62dbac06f9b007cfbc9bec11`
The split container in the shared read-along: one Layout keeps the picture's identity, a divider with a 44-point target (#928).

## 2026-10-20 02:44:30 EDT — scribe `b33cc598632b808b2d20e3b467671b88d7e67c3c`
Red test: Scribe Playback's full screen (opens, closes, stays for the next item, the divider kept per orientation, the pinch kept) (#928).

## 2026-10-20 02:44:30 EDT — scribe `81afa4b8e28075b1723c1c78116dd924f7fc80bc`
Red test: the split drawn, five snapshots (stacked, side by side, the column, no picture, the words' least width) (#928).

## 2026-10-20 02:44:30 EDT — scribe `d126eb2d7975ad41b53e0f48996032c22b6175fe`
The split's rules: where the picture goes for a space's shape, the divider's share kept per orientation and clamped (#928).

## 2026-10-20 02:44:30 EDT — scribe `fd71af0e42d4a0040fd270d19e8c11e5cac8d10c`
Red test: the split's rules (#928).

## 2026-10-20 02:44:30 EDT — scribe `e84c76b8eb2b6dacca3068d824e332cae48d18bd`
Channel note: the rename to Scribe Playback is on main; Build 110's What's New heading (#928).

## 2026-10-20 02:44:30 EDT — scribe `2d37c84aa6a8bc3ec87f7c4cfb08bdef23e0a06f`
Change log for the rename to Scribe Playback (#928).

## 2026-10-20 02:44:30 EDT — scribe `0fdf26314f3783dba9f550021e13a59748e13295`
Scribe Videos is Scribe Playback wherever a person reads it; bundle ids, Instant names and the scribe-videos CLI stay (#928).

## 2026-10-20 02:44:30 EDT — scribe `a1d4ed40518003ab76e623dfce4a0a8ffae8379c`
Red test: the app's name is Scribe Playback on the Home Screen, the share sheet, What's New and Scribe's timeline (#928).

## 2026-10-20 02:44:30 EDT — scribe `6fdab88c90c592233d975ad536d5c612c7191d4c`
Plan and claims for #928: the rename to Scribe Playback and the full-screen split.

## 2026-10-20 01:51:57 EDT — scribe `3c64c2e7753ed2bfa956c94e91981955a4b57bbd`
Changelog entry for the speakerChanges schema slice, pushed to production (#861).

## 2026-10-20 01:51:57 EDT — scribe `afc9364d3f79252e520cc36b68448bd5c7e641a3`
The speakers rules matrix covers speakerChanges: owner-only, closed lists, each kind's fields, never edited (#861).

## 2026-10-20 01:51:57 EDT — scribe `b529aeeacaa0b1ff4cfa31f1844b7c3fa800ff06`
speakerChanges: one append-only row per edit to a recording's speakers, with who made it and the moment he asked (#861).

## 2026-10-20 01:51:57 EDT — scribe `54024630f83486621b9d307bf5373910f99a2887`
Red test: speakerChanges in the speakers schema module (#861).

## 2026-10-20 01:47:03 EDT — scribe `31ae5fe793caa68f159ef02b2f7c7c6339b6889f`
Merged the page-onset fix onto main (#920).

## 2026-10-20 01:47:03 EDT — scribe `412094258ca9c299e3ec760c087b3bc818973e87`
Changelog for the spoken-page onset fix (#920). The implementation commit is 97294d801.

## 2026-10-20 01:47:03 EDT — scribe `97294d801db0ab55e6a3858f038a1e5f3916439f`
A spoken page starts at the page-number word, and a stored page moves onto that word (#920).

## 2026-10-20 01:47:03 EDT — scribe `cd9f7221ffde419a04ff28341a5ab4dec2998cfd`
Red test: a spoken page must start at its page-number word, not the line (#920).

## 2026-10-20 01:42:50 EDT — scribe `4665393dc712c7cf496d4f0422185445e835e47f`
Change log entry for the /v1/process bookReading media key fix (#922).

## 2026-10-20 01:42:50 EDT — scribe `72a9947e6a6e8e832847565c8e848b0207c2ff03`
/v1/process takes a camelCase media key kind as the schema's ITEM_KINDS name it, so a book reading's job is no longer refused (#922).

## 2026-10-20 01:42:50 EDT — scribe `2eb5a054c4f0867443b628d654316ff748fe07ff`
Red test: the server takes bookReading:book-readings:<reading> as a media key (#922).

## 2026-10-20 01:42:50 EDT — scribe `0fbdbe88c086257a063ecf0549e87641080e47f5`
Plan and claims for #922's server key fix and the book-reading backfill (#922).

## 2026-10-20 01:27:54 EDT — scribe `d8568dfbb127638616728e7128f53193ef5e01f8`
Changelog entries name the #922 commits as landed on main (#922).

## 2026-10-20 01:27:54 EDT — scribe `624a0f7b7ecc45093ee4dc56ffc7f5d29974dd6a`
Document the #922 implementation commits in the change log (#922).

## 2026-10-20 01:27:54 EDT — scribe `8d3c4f0b2d9b20d135242ddcf309725a055892a4`
A book reading's scribe-books catalog item carries its book, reading, recording, start and transcript ids; measure results keep match properties (#922).

## 2026-10-20 01:27:54 EDT — scribe `2d2fb7b98b8a7aabcecd4793314d4084b56db6f0`
Each book read aloud becomes a bookReading media item with its clip under the recording, /v1/process words and named speakers, and a scribe-books catalog entry naming its Instant rows; schema pushed to production (#922).

## 2026-10-20 01:27:54 EDT — scribe `c310ff2c9cc71233c2b640e5c892f0e9e00fd7d7`
Red tests for book readings as media items with catalog ids and word-level resolution (#922).

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

## 2026-08-19 13:39:38 EDT — scribe-sqlite-data `5304b4e`
Keep dest WAV recovery tests off live recording IDs so they cannot delete product files (#218).

## 2026-08-19 13:40:00 EDT — scribe-sqlite-data `2255d46644b1`
Bump Scribe SQLiteData Dev to 0.1 (45) for the #218 C1 leftover install.

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

## 2026-08-13 16:33:33 EDT — realtime-voice-sqlite-instant 81165583871549032878bcc937954139fdceddde

## 2026-08-13 18:03:31 EDT — realtime-voice-sqlite-instant 73ff8487ce53d7ecc49d8ef3ecbb9ed839b4a925

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** 73ff8487ce53d7ecc49d8ef3ecbb9ed839b4a925
- **Reason:** Debug Instant static-account sign-in so iPhone and Mac share one durable user for cross-device playback (#095).


- **Repo:** realtime-voice-sqlite-instant
- **SHA:** 81165583871549032878bcc937954139fdceddde
- **Reason:** Restore the iPhone build debug overlay so Expanded actually paints and Stop taps through (#197).

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
