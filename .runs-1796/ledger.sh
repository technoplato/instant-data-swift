#!/bin/bash
# #1796: the change-log entries for the lane's implementation commits, oldest first so the newest ends on top. Run from
# the worktree once the checks pass and the branch has landed (land never rebases, so these SHAs stay valid).
set -eu
cd /Users/laptop/Sync/worktrees/perf-sync-1796
SPEC='headless claude -p run (tools/agent-run, perf-sync-1796 on pp and halfjew22); no SpecStory capture'
Q1='So my transcript is about six. minutes behind'
Q2="We're not going to remove any features or functionality from the application. We're going to fix everything at the source."
rc() { python3 scripts/change-log/record_change.py "$@" --specstory-note "$SPEC"; }

rc --commit bd5d9017 \
  --summary 'red(#1796): a follower applies every buffered refresh, and a one-shot read fails behind a busy applier' \
  --detail 'A tablet following a live recording, 8,240 of its own writes pending, applied every server frame in arrival order at about 1.5 s each, superseded list refreshes included, and showed the recording about six minutes late; its one-shot reads failed at a fixed 5 s while its socket was open (Mac diagnostics collector, 2026-11-04 17:09-17:33).' \
  --detail 'InstantFollowerLatencyTests: the buffer tests, a follower held in a long apply behind twelve list refreshes and three acknowledgements, and a one-shot read answered 6.5 s behind a held frame; liveFrameBeingAppliedForTesting and the stall and limit configuration values the tests set.' \
  --file 'Tests/InstantSwiftDataCoreTests/InstantFollowerLatencyTests.swift::#1796 the failing follower tests' \
  --file 'Sources/InstantSwiftDataCore/InstantRuntime.swift::#1796 the test hook for the frame being applied' \
  --quote "$Q1"

rc --commit 3f66c955 \
  --summary 'green(#1796): a waiting refresh loses what a newer one restates, and a one-shot read waits while the applier works' \
  --detail 'InstantLiveReceivedFrames: when a refresh-ok arrives, older waiting ones lose the results it restates and one left with none leaves the buffer; frames carrying attrs or reflecting a later transaction keep everything (the server combines queued refreshes the same way, session.clj combine [:refresh :refresh]).' \
  --detail 'queryOnceThroughLive waits for its answer while the connection receives or applies frames, up to upstream 30 s QUERY_ONCE_TIMEOUT, and fails after 5 s with neither; it waited a fixed 5 s. live.receive-summary logs a minute of buffer waits, depth, applier busy share and replaced frames.' \
  --file 'Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift::#1796 the buffer replaces restated results; the receive meter and summary; receiveProgress' \
  --file 'Sources/InstantSwiftDataCore/InstantRuntime.swift::#1796 the progress-based answer wait; the stall and limit configuration values' \
  --quote "$Q2"

rc --commit 25923d45 \
  --summary 'red(#1796): a one-shot read sent on a socket that just died fails at once and is never sent again' \
  --detail 'At the 17:33 resume (229 s suspended) the tablet socket was dead (POSIX 53) for 12 s while its connection read as open; a recordingAttachments read failed in 0 ms and dropped its registration, so the reconnect never sent it.' \
  --file 'Tests/InstantSwiftDataCoreTests/InstantFollowerLatencyTests.swift::#1796 aOneShotReadSentOnASocketThatJustDiedIsAnsweredAfterTheReconnect' \
  --quote "$Q1"

rc --commit 1fd79eb8 \
  --summary 'green(#1796): a one-shot read whose add-query met a dead socket waits for the reconnect' \
  --detail 'queryOnceThroughLive keeps its registration when its add-query meets a socket whose receiver owns the failure; the next session init sends it with every registered query, as an observer registration is sent and as upstream Reactor.js sends a queryOnce add-query from _flushPendingMessages on the next init-ok.' \
  --file 'Sources/InstantSwiftDataCore/InstantRuntime.swift::#1796 InstantReceiverOwnedLiveSessionSendFailure leaves the registration for the next session' \
  --quote "$Q2"

rc --commit 882448d2 \
  --summary 'red(#1796): nothing measures how old the newest server write is when a follower applies it' \
  --detail 'The tablet behind #1796 logged no lag; about six minutes was the user reading two screens. The tests ask the buffer for the age of the newest fact of each refresh it applies and the summary for its median, p95 and maximum.' \
  --file 'Tests/InstantSwiftDataCoreTests/InstantFollowerLatencyTests.swift::#1796 theBufferMeasuresHowOldTheNewestServerWriteIsWhenItIsApplied, theReceiveSummaryReportsHowOldTheNewestWritesWere' \
  --file 'Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift::#1796 the test accessors the lag tests read' \
  --quote "$Q1"

rc --commit 75915233 \
  --summary 'green(#1796): the receive summary measures how old the newest server write is when it is applied' \
  --detail 'For each applied refresh-ok carrying a fact newer than any applied before: wall clock minus the newest fact server time (the join-row triple fourth element, child nodes included); add-query answers only move the mark. live.receive-summary adds factLag median, p95 and maximum a minute and is a notice at 10 s or more.' \
  --file 'Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift::#1796 the newest-fact lag in the receive meter and summary' \
  --quote "$Q1"

rc --commit 076ed107 \
  --summary "test(#1796): a writer's lines reach a slow follower within seconds, and the lag stays flat" \
  --detail 'A writer and a follower runtime over scripted sockets, the test as the server, the tablet measured minute (29 list refreshes and 31 own acknowledgements a minute, about 1.5 s an apply) replayed for two minutes on the test clock; each line lag at most 20 s, the last at most 8 s. It must fail on red1 sources (the job runs it there).' \
  --file 'Tests/InstantSwiftDataCoreTests/InstantWriterFollowerLatencyTests.swift::#1796 the two-client latency guard' \
  --quote "$Q1"

rc --commit a5b5174d \
  --summary "test(#1796): the two-client test prints its lag distribution when it passes" \
  --detail 'A passing #expect prints nothing, so the job that ran the guard on the fixed sources reported no number; the release record needs the distribution on both sides (the red run failure message carries the before).' \
  --file 'Tests/InstantSwiftDataCoreTests/InstantWriterFollowerLatencyTests.swift::#1796 print the lag distribution' \
  --quote "$Q1"

rc --commit fac02655 \
  --summary "red(#1796): an observer's registration holds the gate without naming its query" \
  --detail "The tablet's launch (2026-11-04 21:40:47) logged an observer registration holding the operation gate 4,583 ms with 7 callers queued, its connect among them, and an infinite query page's registration holding it 2,852 ms a minute later, both without a phase. aRegistrationsHoldNamesItsQuerysNamespace reads the phase each registration's hold named when it left the gate." \
  --file "Tests/InstantSwiftDataCoreTests/InstantObserverRegistrationGateTests.swift::#1796 the phase test and InstantGateReleasePhases" \
  --quote "$Q1"

rc --commit d7502832 \
  --summary "green(#1796): an observer's registration names its query's namespace in the gate's phase" \
  --detail "A standard query's and an infinite query page's registration mark the gate's phase reload <namespace> before a closed result's reload under the hold and answer <namespace> before the store's first answer (markHolderPhase, lock only): a stall or wait report names the query and the part that held the gate." \
  --file "Sources/InstantSwiftDataCore/InstantRuntime.swift::#1796 the registration's phase marks" \
  --quote "$Q2"
