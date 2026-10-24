# Verdicts for the tests on `Tests/known-failing.txt` (#1021)

What was done about every name the list held when it was first recorded (`9bbe407a`, v1.9.22: 77 names, 24 that
failed idle, 53 only under load), and about the names that failed later, in the runs of the fixed tree. A test leaves
the list when a re-recorded run passes it. No test was deleted; the measurements skip themselves in the parallel
bundle and run alone in the script's second pass, where their result counts.

Whole bundle on the Mac mini (M4, 10 cores), through `scripts/known-failing-tests.sh run`:

| Tree | Idle: failing, seconds | Beside 20 busy loops: failing, seconds (mean load) |
| --- | --- | --- |
| v1.9.22, before (fff54403, 004439da) | 19, 21 of 1,384; 217 s, 205 s | 73 (52), 28 (36); 652 s, 478 s |
| with the fixes (f44dde62 + 89be61be..ed238e19) | 1, 2, 1 of 1,388; 348-356 s + 30-38 s for the measurements | 7 (67), 5 (45), 3 (42); 680-855 s |

The idle runs had other agents' work alongside (load 5-28); a fully idle machine was not available. The bundle takes
longer with the fixes because a slow step now finishes instead of failing at 5 s.

Before the list existed, agents counted about 155 failing names; about 124 of those were how the bundle was
launched, not the code (`004439da`): 107 CLI tests ran without the `instant-swift-data` executable they launch,
12 InstantQueryExecutionParityTests read the upstream fixtures relative to the working directory, and 5
reconciliation tests had no upstream checkout at the commit they pin. `scripts/known-failing-tests.sh run` builds
the executable and checks out the pinned sources, and the parity tests now find their fixtures from their own path.

## The 77 names first recorded

### Load-timing: a fixed bound around a step it expects (30)

A 500 ms to 15 s wait, poll or fail-safe around a step the test expects; under the bundle's load the step took longer. It now waits up to InstantTestWait.hang (60 s), and a stuck step still fails with its name.

- `InstantCancelledSendTests/anObservationCancelledWhileItsAddQueryIsWrittenLeavesTheSocketOpen()` (load 1/2)
- `InstantDiagnosticFeedbackLoopTests/routineDiagnosticsStayBelowInfo()` (load 1/2)
- `InstantLiveConnectionSurvivalTests/framesThatArriveDuringALongApplyAreAppliedInArrivalOrder()` (load 1/2)
- `InstantLiveQueryErrorRecoveryTests/aTimedOutAddQueryIsSentAgainOnTheSameSocketAndRefreshes()` (load 1/2)
- `InstantLiveTestWaitsTests/reactorParityTransportConnectionWaitFailsWhenNoOtherConnectionStarts()` (load 1/2)
- `InstantLiveTransportTests/automaticMutationSendFailureLeavesReconnectToExactReceiver()` (load 1/2)
- `InstantLiveTransportTests/cancellingStandardObservationQueuedAtOperationGateReturnsFinishedWithoutLateRegistration()` (load 1/2)
- `InstantLiveTransportTests/currentRemovalFailureReconnectsAndReinstallsSurvivingQuery()` (load 1/2)
- `InstantLiveTransportTests/equivalentReregistrationPostfixesLateRemoval()` (load 1/2)
- `InstantLiveTransportTests/explicitCloseSupersedesPendingRemovalFailureWithoutReconnect()` (load 1/2)
- `InstantLiveTransportTests/preReceiverRemovalFailureCannotReturnOpenedConnection()` (load 2/2)
- `InstantLiveTransportTests/queryOnceWaitsForExactCleanupBeforeEveryTerminalPath(_:)` (load 1/2)
- `InstantLiveTransportTests/runtimeLiveQueryOnceOpensSessionAndWaitsForServerResult()` (load 1/2)
- `InstantLiveTransportTests/runtimeLiveQueryOncePreservesOpaqueServerPageInfoCursor()` (load 1/2)
- `InstantLiveTransportTests/scriptedLiveSessionReceiveRequestWaitFailsWithinItsBound()` (load 1/2)
- `InstantLiveTransportTests/scriptedLiveSessionSentMessageWaitFailsWithinItsBoundNamingWhatWasSent()` (load 1/2)
- `InstantLiveTransportTests/supersededRemovalFailureCannotOverwriteHealthyReplacementStatus()` (load 1/2)
- `InstantLiveTransportTests/unexpectedCurrentReceiverCancellationReconnectsBeforeLateSendFailure()` (load 1/2)
- `InstantObservationReleaseTests/anObservationEndsWhenItsConsumerReturnsOutOfItsLoop()` (load 1/2)
- `InstantReactorParityTests/rejectedQueryOnceFailsPromptlyWithoutClosingTheSocket()` (idle 1/2)
- `InstantReactorParityTests/runtimeReconnectBacksOffAndFlushesOnlyUnacknowledgedWork()` (idle 1/2)
- `InstantReactorParityTests/runtimeStreamAppendRetryReconnectsWithoutPublishingAppend()` (idle 1/2)
- `InstantReconnectBackoffParityTests/aFailedExplicitConnectKeepsTheBackoff()` (load 1/2)
- `InstantReconnectBackoffParityTests/aPathThatReturnsDuringTheBackoffEndsTheWait()` (load 2/2)
- `InstantReconnectBackoffParityTests/anOutageWithTheNetworkMissingFor13MinutesMakesNoAttemptsUntilItReturns()` (load 1/2)
- `InstantReconnectBackoffParityTests/noAttemptWhileThePathIsMissingAndOneAttemptWhenItReturns()` (load 2/2)
- `InstantReconnectBackoffParityTests/theDelayGrowsToTenSecondsAndOnlyAnOpenedSessionResetsIt()` (idle 1/2)
- `InstantStoreTests/automaticReconnectFailureRemainsRetryableAcrossRelaunchAndFlushesOfflineOutbox()` (load 1/2)
- `InstantStoredFileEvictionTests/evictsOnlyTheCopiesStorageHolds()` (load 1/2)
- `InstantStreamRobustnessTests/aReadersCumulativeContentEqualsTheStreamAcrossAReconnect()` (load 1/2)

### Load-timing: the harness called the list settled too early (9)

The infinite-query harness inferred "settled" from 20 ms of quiet, which under load happened before the first answer. It now also needs a chunk subscription that has its answer, a window that shows rows, and it re-checks until the hang bound instead of 0.75 s.

- `InstantInfiniteQueryDuplicateRowsTests/aRowThatLeavesAChunkBeingReplacedIsNeverListedTwice()` (idle 2/2)
- `InstantInfiniteQueryDuplicateRowsTests/aRowThatMovesBetweenChunksInOneRefreshIsNeverListedTwice()` (idle 1/2)
- `InstantInfiniteQueryDuplicateRowsTests/theWindowKeepsItsRowsWhileTheKickstartWaitsForItsFirstForwardChunk()` (load 2/2)
- `InstantInfiniteQueryLeadingRowsTests/aFullWindowWithALeadingRowKeepsLoadingTheNextPage()` (idle 2/2)
- `InstantInfiniteQueryLeadingRowsTests/aPreviousPageWaitsForTheServerInsteadOfAnEarlierQuerysStoredResult()` (load 1/2)
- `InstantInfiniteQueryLeadingRowsTests/aRowThatMovesAboveTheTopAfterTheWindowSlidDoesNotBreakTheWindow()` (load 2/2)
- `InstantInfiniteQueryLeadingRowsTests/aRowThatMovesAboveTheTopWhileTheTopIsEvictedShowsItsOldValuesUntilTheWindowReturns()` (load 1/2)
- `InstantInfiniteQueryLeadingRowsTests/aWindowLoadedPastOnePageBeforeTheServerAnswersKeepsItsPagesAtTheKickstart()` (idle 2/2)
- `InstantInfiniteQueryLeadingRowsTests/theWindowFollowsALiveHeadWithinItsPageBound()` (load 1/2)

### Load-timing: a wall-clock assertion (8)

It asserted that a call returned within 250 ms to 1.5 s, to show it did not wait for something slow. It now holds that something until the call returns and asserts on state: the work it abandoned is still suspended.

- `InstantFailedMutationRetryWindowTests/connectReturnsBeforeRetryWindowsAndDeliveryAlternatesAfterEachWindow()` (idle 2/2)
- `InstantLiveTransportTests/boundedGracefulCloseAbortsCancellationInsensitiveClose()` (idle 2/2)
- `InstantLiveTransportTests/cancellingLiveTimeoutDoesNotAwaitEitherCancellationInsensitiveChild()` (load 1/2)
- `InstantLiveTransportTests/connectTimeoutAbortsCancellationInsensitiveAttemptAndLateSession()` (idle 2/2)
- `InstantLiveTransportTests/failedOpenAbortsWithoutAwaitingGracefulClose()` (idle 2/2)
- `InstantLiveTransportTests/liveTimeoutDoesNotAwaitCancellationInsensitiveWork()` (idle 2/2)
- `InstantLiveTransportTests/parentCancellationAbortsCancellationInsensitiveRuntimeConnect()` (idle 1/2)
- `InstantOperationGateAwaitTests/aMainActorCallerCannotHoldTheOperationGateWhileMainIsBusy()` (load 2/2)

### Load-timing: the runtime's acknowledgement deadline on the wall clock (5)

The scripted server never answers some writes; their deadline (claim + 6 s x place in flight) passed under load and the runtime replaced the one scripted socket. The test now owns the clock (holdingAcknowledgementDeadlines, #1020's locked clock).

- `InstantFailedMutationRetryWindowTests/oneHealthyConnectionRetriesOneHundredOneRowsAsFiftyFiftyOne()` (idle 2/2)
- `InstantLiveTransportTests/runtimeLiveMutationEncodingFailureDoesNotBlockTheFollowingMutation()` (load 1/2)
- `InstantLiveTransportTests/staleAcknowledgementCannotAdoptAClaimTokenReofferedDuringResponseRecording()` (load 1/2)
- `InstantOutboxRevisionGateTests/localWritesDuringEveryAttemptToRecordARefusalGetOneExclusiveAttempt()` (load 1/2)
- `InstantSupersededReplayTests/aRefusalThatAnAcceptedLaterWriteCoversResolvesAsAcceptedNotFailed()` (load 1/2)

### Load-timing: a sleep or a count of yields instead of the event (4)

It slept 50-300 ms or yielded 100 times and then checked. It now waits for the event itself.

- `InstantOutboxDeliveryStallTests/quarantinedMutationDeliversAfterTheSchemaIsDeployed()` (load 1/2)
- `InstantOutboxDeliveryStallTests/queryThatInitiatesReconnectPrecedesPersistedMutations()` (idle 2/2)
- `InstantOutboxDeliveryStallTests/undeliverableMutationDoesNotBlockLaterMutations()` (idle 1/2)
- `InstantReactorParityTests/upstreamPythonSubscriptionPostInitFailureSilentlyRetriesAndResubscribes()` (idle 2/2)

### Load-timing: a negative wait assertion on the wall clock (1)

AsyncSerialGate timed waits with Date(); a quick handoff took over the 1 s threshold under load. The gate takes a clock (now:), and the test passes one that stands still.

- `AsyncSerialGateTests/quickHandoffReportsNoWait()` (load 1/2)

### Harness defect: the CLI tests' pipe capture raced the result (8)

A readabilityHandler's last callback could still hold output after waitUntilExit returned, so under load the result had an empty stderr or JSON cut short. Both pipes are now read to their end before the result.

- `InstantStoreTests/cliMalformedAdminArgumentsDoNotBootstrapState()` (load 1/2)
- `InstantStoreTests/cliMalformedQueryAndValidationArgumentsDoNotBootstrapState()` (load 1/2)
- `InstantStoreTests/cliMalformedTodoLinksArgumentsDoNotBootstrapState()` (load 1/2)
- `InstantStoreTests/cliQueryTodosPrintsDecodedLocalResults()` (load 1/2)
- `InstantStoreTests/cliReactionsRecipePublishesAndWatchesTopicMessagesAcrossLaunches()` (load 1/2)
- `InstantStoreTests/cliRoundTripsCanonicalMergeTileGameArtifacts()` (load 1/2)
- `InstantStoreTests/cliSharesCreateAcceptListAndRevokePersistAcrossLaunches()` (load 1/2)
- `InstantStoreTests/cliStreamsAppendAndReadPersistAcrossLaunches()` (load 1/2)

### Harness defect: the test deleted a store its hydration still read (2)

The cache directory went while a deferred hydration read it (SQLite 6922, the file gone), and the library reported that as an issue after the test ended. The test now waits for the reader to end.

- `InstantDeferredTranscriptPayloadMemoryTests/deferredCorpusLeavesTranscriptPayloadsOutOfTheHotStore()` (idle 2/2)
- `InstantOperationGatePriorityTests/aHydrationsSQLiteReadDoesNotHoldTheOperationGate()` (idle 2/2)

### Measurement: it measures the whole process (4)

CPU percent, physical footprint, the process-wide diagnostics hub, or a wall-clock latency: beside 1,384 tests in parallel it measured them. Marked .measurement, it runs alone, serially, in the second pass of scripts/known-failing-tests.sh.

- `InstantDiagnosticFeedbackLoopTests/infoHandlerDoesNotAmplifyLargeTransactVolume()` (idle 2/2)
- `InstantMediaStreamOptimizationTests/sustainedAudioStreamHasBoundedResources()` (idle 2/2)
- `InstantResourceCitizenshipTests/nativeMediaPrimitiveReportsBurstAndRealtimeEquivalentResources()` (idle 2/2)
- `InstantServerApplyOperationGateTests/localTransactsDoNotWaitBehindAServerApplyOverAHubComponent()` (load 1/2)

### Open: a held refusal resolves on the wall-clock acknowledgement deadline (1)

Under load the refused re-send ended failed instead of accepted. Owning the clock (as for the other scripted-server tests) made every test in its suite time out: a held refusal is re-checked, and its wait ends, only on the acknowledgement-deadline wake, so a deterministic version needs a deadline wake the test drives. Not fixed here; #1027 carries it.

- `InstantRefusalHeldByServerTests/aRefusedReSendWhoseValuesTheServersResultShowsResolvesAsAccepted()` (load 1/2)

### Owner: #1006 (2)

A wall-clock threshold in a #1006 measurement; left to transcript-open-1006 (told on #1006).

- `InstantLocalReadTests/nineHundredEightySixLinesOnDiskReadAtOnceWhileAServerApplyHoldsTheGate()` (load 1/2)
- `InstantStoredResultReloadTests/aTranscriptOfNineHundredEightySixLinesOpensAndReopens(answerDelay:)` (load 2/2)

### Owner: #1007 (1)

A thread-CPU ratio whose bound sat near the fixed code under load; #1007 widened it to 20 on main (210def0e).

- `InstantManyCardinalitySortCostTests/materializingALinkSetBuildsAboutOneSortKeyPerValue()` (idle 1/2)

### Open: an exact count of actor hops changes under load (2)

Under heavy load one workload's first sample made one more persistence call (5 for 4; 28 hops for 27); they pass idle, alone, and under lighter load. #1026 carries the evidence and the questions.

- `InstantCrossSDKRuntimeBenchmarkTests/runtimeWorkloadsPinEveryActorHop()` (load 1/2)
- `InstantStoreTests/localTodoBenchmarkProducesDeterministicMetrics()` (load 1/2)

## Found in the runs of the fixed tree

Names that failed only after the first fixes, mostly at heavier load than the first recording saw.

- `InstantMediaStreamOptimizationTests/binaryCodecRemovesBase64AndJSONCPU()`: #1028: the binary/JSON encode time ratio is 0.58-1.38 over 26 runs (median 0.98); "smaller" always holds, "faster" is a coin flip.
- `InstantLiveConnectionSurvivalTests/framesTakenBeforeAFailedSendAreNotApplied()`: #1029: at load ~67 the writes were never offered on one replacement within 60 s (inference: the library's 5 s connect/open timeout on the wall clock, against a test server that cannot recover).
- `InstantLiveConnectionSurvivalTests/aScheduledReconnectReusesASessionThatOpenedAfterTheLoss()`: #1029: the reconnect never parked in its backoff within 60 s; the test's backoff gate parks only the first wait, so a cancelled first wait hides the rest.
- `InstantInfiniteQueryLeadingRowsTests/aFullWindowWithALeadingRowKeepsLoadingTheNextPage()`: #1029: at load ~67 the query had no chunk subscription after 60 s (its opening never connected).
- `InstantInfiniteQueryDuplicateRowsTests/aRowThatLeavesAChunkBeingReplacedIsNeverListedTwice()`: #1030: with the opening fixed, under load the leading watcher never showed the moved row while the old subscription was held retiring (60 s).
- `InstantStoreTests/automaticReconnectFailureRemainsRetryableAcrossRelaunchAndFlushesOfflineOutbox()`: #1029 (inference): with its polls bounded at 60 s, the relaunch still read errored under load.
- `InstantPrepareCopyCostTests/preparingAWriteCostsAboutTheSameWhateverTheStoresSize()`: #1007 owns it: a thread-CPU ratio (< 3) measured 5.0 under load; told on #1007.
- `InstantOutboxHydrationTests/sameProcessAutomaticLiveDeliverySendsExactTransactionSteps()`: Fixed: owns the acknowledgement clock (it failed only at load ~67).
- `InstantOutboxDeliveryStallTests/queryThatInitiatesReconnectPrecedesPersistedMutations()`: Fixed twice: it waits for the query's registration instead of 100 yields, and owns the acknowledgement clock (at load ~67 the deadline passed next).
