# Upstream Point-Free SQLiteData — complete test inventory

**Source:** `<package root>/upstream/sqlite-data` (github.com/pointfreeco/sqlite-data)  
**Commit:** `0c79d7a5748fc6d9ce7a1ba2b50f31b175305049`  
**Scope:** `Tests/SQLiteDataTests/**` and `Examples/*Tests/**`

Counts converged across two independent methods (hand parser + ripgrep `@Test`
association, double-checked by a separate subagent). One commented-out `@Test`
in `SharingTests.swift` is excluded; multi-line `@Test` attributes are included.

| Number | Value | Meaning |
| --- | ---: | --- |
| Test files with runtime tests | 45 | files that declare ≥1 `@Test` |
| **Runtime tests** | **261** | every runnable `@Test` function |
| Core library | 57 | `Tests/SQLiteDataTests` excluding CloudKit |
| CloudKit / SyncEngine | 186 | `Tests/SQLiteDataTests/CloudKitTests` |
| Example app tests | 18 | Reminders, SyncUps test targets |
| XCTest-style (no `@Test`) | 0 | all runtime tests are Swift Testing |

Every row is greppable. To locate a test in the upstream tree:

```sh
cd upstream/sqlite-data
grep -rn "func <greppable>" Tests Examples
```

---

## How Instant ports these

SQLiteData is single-device SQLite with optional CloudKit sync. Instant is
local-first with optimistic multi-device sync for every query. Ports are
**adapted**, not line-for-line:

- **Must match:** fetch/observe ergonomics (`@FetchAll` / `@FetchOne` /
  `@Fetch`), drafts, concurrency under load, cancellation, decode failures,
  case-study call sites, example app model behavior.
- **Must adapt:** anything that assumes a single SQLite connection is the
  source of truth — Instant always has a local cache + outbox + server.
- **Usually not applicable:** CloudKit SyncEngine plumbing, GRDB custom SQL
  functions, SQL snapshot `assertQuery`, integer→UUID primary-key migrations.

| Bucket | Port priority | Notes |
| --- | --- | --- |
| Core fetch/observe/integration | **P0** | Direct ergonomics parity |
| Example app tests | **P1** | Reminders / SyncUps already partially ported |
| AssertQuery / QueryCursor / migrations | **P2** | SQL-shaped; many `notApplicable` |
| CloudKit SyncEngine | **P2** | Domain rules may map to Instant sharing; plumbing does not |
| Compile-time / empty suites | skip | No runtime cases |

---

## 1. Core library tests (`Tests/SQLiteDataTests`, excluding CloudKit)

12 files · **57 runtime tests**.

### `Tests/SQLiteDataTests/AssertQueryTests.swift`

8 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 15 | `assertQueryBasic` | `assertQueryBasic` | swift-testing |
| 30 | `assertQueryRecord` | `assertQueryRecord` | swift-testing |
| 46 | `assertQueryBasicUpdate` | `assertQueryBasicUpdate` | swift-testing |
| 63 | `assertQueryRecordUpdate` | `assertQueryRecordUpdate` | swift-testing |
| 82 | `assertQueryEmpty` | `assertQueryEmpty` | swift-testing |
| 94 | `assertQueryFailsNoResultsNonEmptySnapshot` | `assertQueryFailsNoResultsNonEmptySnapshot` | swift-testing |
| 108 | `assertQueryBasicIncludeSQL` | `assertQueryBasicIncludeSQL` | swift-testing |
| 131 | `assertQueryRecordIncludeSQL` | `assertQueryRecordIncludeSQL` | swift-testing |

### `Tests/SQLiteDataTests/CustomFunctionTests.swift`

1 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 11 | `basics` | `basics` | swift-testing |

### `Tests/SQLiteDataTests/DatabaseFunctionTests.swift`

2 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 12 | `scalarFunction` | `scalarFunction` | swift-testing |
| 27 | `aggregateFunction` | `aggregateFunction` | swift-testing |

### `Tests/SQLiteDataTests/DateTests.swift`

1 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 11 | `roundtrip` | `roundtrip` | swift-testing |

### `Tests/SQLiteDataTests/FetchAllTests.swift`

3 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 15 | `concurrency` | `concurrency` | swift-testing |
| 51 | `fetchFailure` | `fetchFailure` | swift-testing |
| 72 | `fetchAllSelection_Deprecated` | `fetchAllSelection_Deprecated` | swift-testing |

### `Tests/SQLiteDataTests/FetchOneTests.swift`

15 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 13 | `nonTableInit` | `nonTableInit` | swift-testing |
| 19 | `tableInit` | `tableInit` | swift-testing |
| 32 | `optionalTableInit` | `optionalTableInit` | swift-testing |
| 43 | `optionalTableInit_WithDefault` | `optionalTableInit_WithDefault` | swift-testing |
| 54 | `selectStatementInit` | `selectStatementInit` | swift-testing |
| 73 | `statementInit_Representable` | `statementInit_Representable` | swift-testing |
| 92 | `statementInit_OptionalRepresentable` | `statementInit_OptionalRepresentable` | swift-testing |
| 107 | `statementInit_DoubleOptionalRepresentable` | `statementInit_DoubleOptionalRepresentable` | swift-testing |
| 122 | `statementInit` | `statementInit` | swift-testing |
| 141 | `optionalStatementInit` | `optionalStatementInit` | swift-testing |
| 156 | `optionalStatementInit_Selection` | `optionalStatementInit_Selection` | swift-testing |
| 171 | `fetchOneOptional` | `fetchOneOptional` | swift-testing |
| 178 | `fetchOneDelayedAssignment` | `fetchOneDelayedAssignment` | swift-testing |
| 184 | `fetchOneSelection` | `fetchOneSelection` | swift-testing |
| 196 | `fetchOneSelection_Deprecated` | `fetchOneSelection_Deprecated` | swift-testing |

### `Tests/SQLiteDataTests/FetchSubscriptionTests.swift`

3 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 9 | `stopSubscriptionWhenTaskCancelled` | `stopSubscriptionWhenTaskCancelled` | swift-testing |
| 31 | `completeWhenTaskExplicitlyCancelled` | `completeWhenTaskExplicitlyCancelled` | swift-testing |
| 56 | `cancellingOneFetchDoesNotCancelAnother` | `cancellingOneFetchDoesNotCancelAnother` | swift-testing |

### `Tests/SQLiteDataTests/FetchTests.swift`

6 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 10 | `bareFetchAll` | `bareFetchAll` | swift-testing |
| 19 | `fetchAllWithQuery` | `fetchAllWithQuery` | swift-testing |
| 28 | `fetchOneCountWithQuery` | `fetchOneCountWithQuery` | swift-testing |
| 37 | `fetchOneOptional` | `fetchOneOptional` | swift-testing |
| 47 | `fetchOneWithDefault` | `fetchOneWithDefault` | swift-testing |
| 60 | `fetchOneOptional_SQL` | `fetchOneOptional_SQL` | swift-testing |

### `Tests/SQLiteDataTests/IntegrationTests.swift`

2 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 12 | `fetchAll_SQLString` | `fetchAll_SQLString` | swift-testing |
| 37 | `fetch_FetchKeyRequest` | `fetch_FetchKeyRequest` | swift-testing |

### `Tests/SQLiteDataTests/MigrationTests.swift`

1 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 7 | `dates` | `dates` | swift-testing |

### `Tests/SQLiteDataTests/PrimaryKeyMigrationTests.swift`

13 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 53 | `basics` | `basics` | swift-testing |
| 190 | `rowid` | `rowid` | swift-testing |
| 229 | `primaryKeyIsAlreadyUUID` | `primaryKeyIsAlreadyUUID` | swift-testing |
| 271 | `dropUniqueConstraints` | `dropUniqueConstraints` | swift-testing |
| 350 | `primaryKeyNamedUnique` | `primaryKeyNamedUnique` | swift-testing |
| 399 | `columnConstraints` | `columnConstraints` | swift-testing |
| 531 | `topLevelConstraints` | `topLevelConstraints` | swift-testing |
| 671 | `commentsAndNewlines` | `commentsAndNewlines` | swift-testing |
| 822 | `nonIntPrimaryKey` | `nonIntPrimaryKey` | swift-testing |
| 876 | `compoundPrimaryKey` | `compoundPrimaryKey` | swift-testing |
| 902 | `addPrimaryKeyWithCustomName` | `addPrimaryKeyWithCustomName` | swift-testing |
| 953 | `recreatesIndicesAndTriggers` | `recreatesIndicesAndTriggers` | swift-testing |
| 1020 | `lowercaseNoQuotes` | `lowercaseNoQuotes` | swift-testing |

### `Tests/SQLiteDataTests/QueryCursorTests.swift`

2 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 18 | `emptyInsert` | `emptyInsert` | swift-testing |
| 24 | `emptyUpdate` | `emptyUpdate` | swift-testing |

## 2. CloudKit / SyncEngine tests

29 files · **186 runtime tests**.

### `Tests/SQLiteDataTests/CloudKitTests/AccountLifecycleTests.swift`

5 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 17 | `signOutClearsUserDatabaseAndMetadatabase` | `signOutClearsUserDatabaseAndMetadatabase` | swift-testing |
| 44 | `signInUploadsLocalRecordsToCloudKit` | `signInUploadsLocalRecordsToCloudKit` | swift-testing |
| 132 | `signInUploadsLocalRecordsToCloudKit_SkipExistingCloudKitRecords` | `signInUploadsLocalRecordsToCloudKit_SkipExistingCloudKitRecords` | swift-testing |
| 347 | `createSharedRecordWhileSoftLoggedOut` | `createSharedRecordWhileSoftLoggedOut` | swift-testing |
| 623 | `doNotUploadExistingDataToCloudKitWhenSignedOut` | `doNotUploadExistingDataToCloudKitWhenSignedOut` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/AppLifecycleTests.swift`

3 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 20 | `sendChangesOnBackground` | `sendChangesOnBackground` | swift-testing |
| 56 | `background_whileNotRunning` | `background_whileNotRunning` | swift-testing |
| 64 | `sendSharedChanges` | `sendSharedChanges` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/AssetsTests.swift`

5 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 16 | `basics` | `basics` | swift-testing |
| 129 | `receiveAsset` | `receiveAsset` | swift-testing |
| 168 | `receiveUpdatedAsset` | `receiveUpdatedAsset` | swift-testing |
| 209 | `receiveAssetThenReceiveUpdate` | `receiveAssetThenReceiveUpdate` | swift-testing |
| 275 | `assetReceivedBeforeParentRecord` | `assetReceivedBeforeParentRecord` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/AtomicTests.swift`

2 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 16 | `editConflictAndNewRecord` | `editConflictAndNewRecord` | swift-testing |
| 109 | `editConflictAndDeleteRecord` | `editConflictAndDeleteRecord` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/AttachedMetadatabaseTests.swift`

1 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 19 | `basics` | `basics` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/CloudKitTests.swift`

11 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 16 | `setUp` | `setUp` | swift-testing |
| 408 | `tearDownAndReSetUp` | `tearDownAndReSetUp` | swift-testing |
| 453 | `addAndRemoveFunctions` | `addAndRemoveFunctions` | swift-testing |
| 494 | `insertUpdateDelete` | `insertUpdateDelete` | swift-testing |
| 584 | `remoteServerRecordUpdate` | `remoteServerRecordUpdate` | swift-testing |
| 646 | `remoteServerSendsRecordWithNoChanges` | `remoteServerSendsRecordWithNoChanges` | swift-testing |
| 691 | `remoteServerRecordUpdateWithOldRecord` | `remoteServerRecordUpdateWithOldRecord` | swift-testing |
| 746 | `remoteServerRecordDeleted` | `remoteServerRecordDeleted` | swift-testing |
| 787 | `cascadingDeletionOrder` | `cascadingDeletionOrder` | swift-testing |
| 854 | `sendChanges` | `sendChanges` | swift-testing |
| 864 | `generatedColumns` | `generatedColumns` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/FetchRecordZoneChangesTests.swift`

11 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 17 | `saveExtraFieldsToSyncMetadata` | `saveExtraFieldsToSyncMetadata` | swift-testing |
| 112 | `remoteChangeParentRelationship` | `remoteChangeParentRelationship` | swift-testing |
| 216 | `editRecordReceivedFromCloudKit` | `editRecordReceivedFromCloudKit` | swift-testing |
| 281 | `receiveNewRecordFromCloudKit_ChildBeforeParent` | `receiveNewRecordFromCloudKit_ChildBeforeParent` | swift-testing |
| 377 | `deleteMultipleRecords` | `deleteMultipleRecords` | swift-testing |
| 406 | `receiveRecord_SingleFieldPrimaryKey` | `receiveRecord_SingleFieldPrimaryKey` | swift-testing |
| 417 | `renamePrimaryKey` | `renamePrimaryKey` | swift-testing |
| 499 | `createTagLocallyThenCreateSameTagRemotely` | `createTagLocallyThenCreateSameTagRemotely` | swift-testing |
| 581 | `createTagRemotelyThenCreateSameTagLocally` | `createTagRemotelyThenCreateSameTagLocally` | swift-testing |
| 734 | `invalidRecordName` | `invalidRecordName` | swift-testing |
| 744 | `syncInvalidRecordID` | `syncInvalidRecordID` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/FetchedDatabaseChangesTests.swift`

2 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 16 | `deleteSyncEngineZone` | `deleteSyncEngineZone` | swift-testing |
| 48 | `deleteSyncEngineZone_EncryptedDataReset` | `deleteSyncEngineZone_EncryptedDataReset` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/ForeignKeyConstraintTests.swift`

10 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 18 | `receiveChildBeforeParent` | `receiveChildBeforeParent` | swift-testing |
| 120 | `remoteCreatesRecordABC_localReceivesAC_remoteDeletesBC` | `remoteCreatesRecordABC_localReceivesAC_remoteDeletesBC` | swift-testing |
| 229 | `receiveChildRecordBeforeParent_ReceiveChildAndParentRecord` | `receiveChildRecordBeforeParent_ReceiveChildAndParentRecord` | swift-testing |
| 322 | `receiveChild_Relaunch_ReceiveParent` | `receiveChild_Relaunch_ReceiveParent` | swift-testing |
| 465 | `changeParentRelationshipToUnknownRecord` | `changeParentRelationshipToUnknownRecord` | swift-testing |
| 607 | `changeParentRelationship_RemotelyThenLocally` | `changeParentRelationship_RemotelyThenLocally` | swift-testing |
| 704 | `changeParentRelationship_RemoteFirstEdited_LocalSecondEdited_SendBatch_ReceiveCloudKit` | `changeParentRelationship_RemoteFirstEdited_LocalSecondEdited_SendBatch_ReceiveCloudKit` | swift-testing |
| 791 | `cascadingDeletes` | `cascadingDeletes` | swift-testing |
| 847 | `insertForeignKeyConstraintFailure` | `insertForeignKeyConstraintFailure` | swift-testing |
| 885 | `batchAssociations` | `batchAssociations` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/MergeConflictTests.swift`

7 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 18 | `merge_clientRecordUpdatedBeforeServerRecord` | `merge_clientRecordUpdatedBeforeServerRecord` | swift-testing |
| 178 | `serverRecordUpdatedBeforeClientRecord` | `serverRecordUpdatedBeforeClientRecord` | swift-testing |
| 338 | `serverAndClientEditDifferentFields` | `serverAndClientEditDifferentFields` | swift-testing |
| 409 | `serverRecordEditedAfterClientButProcessedBeforeClient` | `serverRecordEditedAfterClientButProcessedBeforeClient` | swift-testing |
| 498 | `serverRecordEditedAndProcessedBeforeClient` | `serverRecordEditedAndProcessedBeforeClient` | swift-testing |
| 569 | `serverRecordEditedBeforeClientButProcessedAfterClient` | `serverRecordEditedBeforeClientButProcessedAfterClient` | swift-testing |
| 641 | `mergeWithNullableFields` | `mergeWithNullableFields` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/MetadataTests.swift`

6 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 18 | `parentRecordNameUpdatesAfterMovingReminderToDifferentList` | `parentRecordNameUpdatesAfterMovingReminderToDifferentList` | swift-testing |
| 112 | `noParentRecordForRecordsWithMultipleForeignKeys` | `noParentRecordForRecordsWithMultipleForeignKeys` | swift-testing |
| 189 | `metadataFields` | `metadataFields` | swift-testing |
| 544 | `hasMetadataHelper` | `hasMetadataHelper` | swift-testing |
| 629 | `observation` | `observation` | swift-testing |
| 658 | `observation_GeneratedColumn` | `observation_GeneratedColumn` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/MockCloudDatabaseTests.swift`

24 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 29 | `fetchRecordInUnknownZone` | `fetchRecordInUnknownZone` | swift-testing |
| 42 | `fetchUnknownRecord` | `fetchUnknownRecord` | swift-testing |
| 50 | `assetsUseTemporaryDirectory` | `assetsUseTemporaryDirectory` | swift-testing |
| 74 | `saveTransaction_ChildBeforeParent` | `saveTransaction_ChildBeforeParent` | swift-testing |
| 115 | `saveTransaction_ChildNoParent` | `saveTransaction_ChildNoParent` | swift-testing |
| 148 | `saveInUnknownZone` | `saveInUnknownZone` | swift-testing |
| 183 | `deleteTransaction_ParentBeforeChild` | `deleteTransaction_ParentBeforeChild` | swift-testing |
| 211 | `deleteUnknownRecord` | `deleteUnknownRecord` | swift-testing |
| 236 | `deleteRecordInUnknownZone` | `deleteRecordInUnknownZone` | swift-testing |
| 267 | `deleteTransaction_DeleteParentButNotChild` | `deleteTransaction_DeleteParentButNotChild` | swift-testing |
| 311 | `deleteUnknownZone` | `deleteUnknownZone` | swift-testing |
| 323 | `accountTemporarilyAvailable` | `accountTemporarilyAvailable` | swift-testing |
| 346 | `noAccount` | `noAccount` | swift-testing |
| 369 | `accountNotDetermined` | `accountNotDetermined` | swift-testing |
| 392 | `restrictedAccount` | `restrictedAccount` | swift-testing |
| 415 | `saveShareWithoutRootRecord` | `saveShareWithoutRootRecord` | swift-testing |
| 426 | `saveShareAndRootThenSaveShareAlone` | `saveShareAndRootThenSaveShareAlone` | swift-testing |
| 439 | `saveRecordThatWasPreviouslyDeleted` | `saveRecordThatWasPreviouslyDeleted` | swift-testing |
| 452 | `saveSharedRecordWithoutParent` | `saveSharedRecordWithoutParent` | swift-testing |
| 462 | `deletingShareOwnedByCurrentUserDeletesShareAndDoesNotDeleteAssociatedData` | `deletingShareOwnedByCurrentUserDeletesShareAndDoesNotDeleteAssociatedData` | swift-testing |
| 549 | `deletingShareNotOwnedByCurrentUserDeletesOnlyShareAndNotAssociatedRecords` | `deletingShareNotOwnedByCurrentUserDeletesOnlyShareAndNotAssociatedRecords` | swift-testing |
| 637 | `batchRequestFailed` | `batchRequestFailed` | swift-testing |
| 677 | `limitExceeded_modifyRecords` | `limitExceeded_modifyRecords` | swift-testing |
| 708 | `records_limitExceeded` | `records_limitExceeded` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/NewTableSyncTests.swift`

1 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 29 | `initialSync` | `initialSync` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/NextRecordZoneChangeBatchTests.swift`

8 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 16 | `noMetadataForRecord` | `noMetadataForRecord` | swift-testing |
| 39 | `nonExistentTable` | `nonExistentTable` | swift-testing |
| 74 | `cloudKitSendsNonExistentTable` | `cloudKitSendsNonExistentTable` | swift-testing |
| 114 | `metadataRowWithNoCorrespondingRecordRow` | `metadataRowWithNoCorrespondingRecordRow` | swift-testing |
| 146 | `saveRecord` | `saveRecord` | swift-testing |
| 180 | `saveRecordWithParent` | `saveRecordWithParent` | swift-testing |
| 225 | `savePrivateRecord` | `savePrivateRecord` | swift-testing |
| 272 | `editBetweenBatchAndSentRecordZoneChanges` | `editBetweenBatchAndSentRecordZoneChanges` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/PreviewTests.swift`

2 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 14 | `autoSyncChangesInPreviews` | `autoSyncChangesInPreviews` | swift-testing |
| 47 | `delete` | `delete` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/RecordTypeTests.swift`

5 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 14 | `setUp` | `setUp` | swift-testing |
| 406 | `tearDownErasesMetadata` | `tearDownErasesMetadata` | swift-testing |
| 427 | `reSetUp` | `reSetUp` | swift-testing |
| 443 | `migration` | `migration` | swift-testing |
| 553 | `migrationAddTableForgetToAddToSyncEngine` | `migrationAddTableForgetToAddToSyncEngine` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/ReferenceViolationTests.swift`

5 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 18 | `moveReminderToList_RemoteDeletesList` | `moveReminderToList_RemoteDeletesList` | swift-testing |
| 87 | `deleteList_RemoteAddsReminderToList` | `deleteList_RemoteAddsReminderToList` | swift-testing |
| 169 | `deleteList_RemoteAddsReminderToList_Variation` | `deleteList_RemoteAddsReminderToList_Variation` | swift-testing |
| 251 | `moveChildToParent_RemoteDeletesParent_CascadeSetNull` | `moveChildToParent_RemoteDeletesParent_CascadeSetNull` | swift-testing |
| 333 | `moveChildToParent_RemoteDeletesParent_CascadeSetDefault` | `moveChildToParent_RemoteDeletesParent_CascadeSetDefault` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/SchemaChangeTests.swift`

13 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 14 | `addColumnToRemindersAndRemindersLists` | `addColumnToRemindersAndRemindersLists` | swift-testing |
| 118 | `oldSchemaUpdatesNewSchemaRecord` | `oldSchemaUpdatesNewSchemaRecord` | swift-testing |
| 206 | `addColumn_OldRecordsSyncToNewSchema` | `addColumn_OldRecordsSyncToNewSchema` | swift-testing |
| 256 | `addNullableColumn_OldRecordsSyncToNewSchema` | `addNullableColumn_OldRecordsSyncToNewSchema` | swift-testing |
| 305 | `addNullableColumn_OldDeviceSyncsMissingColor` | `addNullableColumn_OldDeviceSyncsMissingColor` | swift-testing |
| 383 | `addNullableColumn_NewDeviceSyncsNullColor` | `addNullableColumn_NewDeviceSyncsNullColor` | swift-testing |
| 462 | `newSchemaUpdatesOldSchemaRecord` | `newSchemaUpdatesOldSchemaRecord` | swift-testing |
| 551 | `runWithNewSchema_oldSchemaSavesRecord_NewSchemaUpdatesRecord` | `runWithNewSchema_oldSchemaSavesRecord_NewSchemaUpdatesRecord` | swift-testing |
| 703 | `addAssetToRemindersList` | `addAssetToRemindersList` | swift-testing |
| 761 | `addAssetToRemindersList_Redownload` | `addAssetToRemindersList_Redownload` | swift-testing |
| 832 | `newTable` | `newTable` | swift-testing |
| 911 | `outsideRecord` | `outsideRecord` | swift-testing |
| 928 | `outsideRecordWithColon` | `outsideRecordWithColon` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/ScopedTableSyncTests.swift`

5 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 15 | `outgoingSaveLookupIncludesScopedOutRow` | `outgoingSaveLookupIncludesScopedOutRow` | swift-testing |
| 45 | `zoneDeletionRemovesScopedOutRow` | `zoneDeletionRemovesScopedOutRow` | swift-testing |
| 67 | `encryptedDataResetReuploadsScopedOutRow` | `encryptedDataResetReuploadsScopedOutRow` | swift-testing |
| 92 | `serverDeleteRemovesScopedOutRow` | `serverDeleteRemovesScopedOutRow` | swift-testing |
| 113 | `serverModificationMergesScopedOutRow` | `serverModificationMergesScopedOutRow` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/SharingPermissionsTests.swift`

5 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 16 | `insertRecordInReadOnlyRemindersList` | `insertRecordInReadOnlyRemindersList` | swift-testing |
| 93 | `deleteReminderInReadOnlyRemindersList` | `deleteReminderInReadOnlyRemindersList` | swift-testing |
| 197 | `editReminderInReadOnlyRemindersList` | `editReminderInReadOnlyRemindersList` | swift-testing |
| 303 | `createRecordWhenLocalHasPermissionsButCloudKitDoesNot` | `createRecordWhenLocalHasPermissionsButCloudKitDoesNot` | swift-testing |
| 390 | `editRecordWhenLocalHasPermissionsButCloudKitDoesNot` | `editRecordWhenLocalHasPermissionsButCloudKitDoesNot` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/SharingTests.swift`

28 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 16 | `shareNonRootRecord` | `shareNonRootRecord` | swift-testing |
| 59 | `syncEngineStopped` | `syncEngineStopped` | swift-testing |
| 88 | `shareUnrecognizedTable` | `shareUnrecognizedTable` | swift-testing |
| 116 | `sharePrivateTable` | `sharePrivateTable` | swift-testing |
| 155 | `privateTableNotShared` | `privateTableNotShared` | swift-testing |
| 207 | `privateTablesStayInPrivateDatabase` | `privateTablesStayInPrivateDatabase` | swift-testing |
| 294 | `shareRecordBeforeSync` | `shareRecordBeforeSync` | swift-testing |
| 322 | `createRecordInExternallySharedRecord` | `createRecordInExternallySharedRecord` | swift-testing |
| 404 | `shareDeliveredBeforeRecord` | `shareDeliveredBeforeRecord` | swift-testing |
| 514 | `shareeCreatesMultipleChildModels` | `shareeCreatesMultipleChildModels` | swift-testing |
| 714 | `deleteRecordInExternallySharedRecord` | `deleteRecordInExternallySharedRecord` | swift-testing |
| 792 | `share` | `share` | swift-testing |
| 857 | `createParentThenChildThenShare` | `createParentThenChildThenShare` | swift-testing |
| 932 | `shareTwice` | `shareTwice` | swift-testing |
| 1001 | `unshareNonSharedRecord` | `unshareNonSharedRecord` | swift-testing |
| 1023 | `shareUnshareShareAgain` | `shareUnshareShareAgain` | swift-testing |
| 1095 | `acceptShare` | `acceptShare` | swift-testing |
| 1178 | `acceptShareCreateReminder` | `acceptShareCreateReminder` | swift-testing |
| 1340 | `deleteRootSharedRecord_CurrentUserOwnsRecord` | `deleteRootSharedRecord_CurrentUserOwnsRecord` | swift-testing |
| 1420 | `deleteRootSharedRecord_CurrentUserNotOwner` | `deleteRootSharedRecord_CurrentUserNotOwner` | swift-testing |
| 1582 | `deleteRootSharedRecord_CurrentUserNotOwner_DoNotCascade` | `deleteRootSharedRecord_CurrentUserNotOwner_DoNotCascade` | swift-testing |
| 1692 | `syncDeletedRootSharedRecord_CurrentUserNotOwner` | `syncDeletedRootSharedRecord_CurrentUserNotOwner` | swift-testing |
| 1826 | `movesChildRecordFromPrivateParentToSharedParent` | `movesChildRecordFromPrivateParentToSharedParent` | swift-testing |
| 2108 | `movesChildRecordFromPrivateParentToSharedParent_ReceiveDeleteBeforeSave` | `movesChildRecordFromPrivateParentToSharedParent_ReceiveDeleteBeforeSave` | swift-testing |
| 2413 | `movesChildRecordFromPrivateParentToSharedParent_ReceiveSaveBeforeDelete` | `movesChildRecordFromPrivateParentToSharedParent_ReceiveSaveBeforeDelete` | swift-testing |
| 2718 | `movesChildRecordFromSharedParentToPrivateParent` | `movesChildRecordFromSharedParentToPrivateParent` | swift-testing |
| 2960 | `movesChildRecordFromPrivateParentToSharedParentWhileSyncEngineStopped` | `movesChildRecordFromPrivateParentToSharedParentWhileSyncEngineStopped` | swift-testing |
| 3246 | `deleteShare` | `deleteShare` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/SyncEngineDelegateTests.swift`

2 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 20 | `accountChanged` | `accountChanged` | swift-testing |
| 179 | `accountChanged_DefaultImplementation` | `accountChanged_DefaultImplementation` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/SyncEngineLifecycleTests.swift`

7 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 24 | `stopAndReStart` | `stopAndReStart` | swift-testing |
| 142 | `writeStopDeleteStart` | `writeStopDeleteStart` | swift-testing |
| 183 | `addRemindersList_StopSyncEngine_EditTitle_StartSyncEngine` | `addRemindersList_StopSyncEngine_EditTitle_StartSyncEngine` | swift-testing |
| 257 | `getSharedRecord_StopSyncEngine_WriteToSharedRecord_StartSyncing` | `getSharedRecord_StopSyncEngine_WriteToSharedRecord_StartSyncing` | swift-testing |
| 414 | `externalSharedRecord_StopSyncEngine_DeleteSharedRecord_StartSyncEngine` | `externalSharedRecord_StopSyncEngine_DeleteSharedRecord_StartSyncEngine` | swift-testing |
| 513 | `sharedRecord_StopSyncEngine_DeleteSharedRecord_StartSyncEngine` | `sharedRecord_StopSyncEngine_DeleteSharedRecord_StartSyncEngine` | swift-testing |
| 586 | `writeAndThenStart` | `writeAndThenStart` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/SyncEngineTests.swift`

7 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 15 | `inMemory` | `inMemory` | swift-testing |
| 24 | `inMemoryUserDatabase` | `inMemoryUserDatabase` | swift-testing |
| 47 | `inMemoryUserDatabase_LiveContext` | `inMemoryUserDatabase_LiveContext` | swift-testing |
| 67 | `metadatabaseMismatch` | `metadatabaseMismatch` | swift-testing |
| 97 | `isSynchronizingTriggerWarning` | `isSynchronizingTriggerWarning` | swift-testing |
| 126 | `testSyncEngine` | `testSyncEngine` | swift-testing |
| 132 | `previewSyncEngine` | `previewSyncEngine` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/SyncEngineValidationTests.swift`

7 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 19 | `tableNameValidation` | `tableNameValidation` | swift-testing |
| 50 | `foreignKeyActionValidation_NoAction` | `foreignKeyActionValidation_NoAction` | swift-testing |
| 109 | `foreignKeyActionValidation_Restrict` | `foreignKeyActionValidation_Restrict` | swift-testing |
| 175 | `foreignKeyPointsToOtherSynchronizedTable` | `foreignKeyPointsToOtherSynchronizedTable` | swift-testing |
| 234 | `doNotValidateTriggersOnNonSyncedTables` | `doNotValidateTriggersOnNonSyncedTables` | swift-testing |
| 285 | `uniquenessConstraint` | `uniquenessConstraint` | swift-testing |
| 328 | `cycleValidation` | `cycleValidation` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/TopologicalTableSortingTests.swift`

1 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 10 | `tablesByOrder` | `tablesByOrder` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/TriggerTests.swift`

1 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 13 | `triggers` | `triggers` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/UnattachedSyncEngineTests.swift`

1 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 12 | `start` | `start` | swift-testing |

### `Tests/SQLiteDataTests/CloudKitTests/UserlandTests.swift`

1 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 8 | `basics` | `basics` | swift-testing |

## 3. Example app tests

4 files · **18 runtime tests**.

### `Examples/RemindersTests/RemindersDetailsTests.swift`

10 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 14 | `basics` | `basics` | swift-testing |
| 120 | `ordering` | `ordering` | swift-testing |
| 166 | `showCompleted` | `showCompleted` | swift-testing |
| 213 | `move` | `move` | swift-testing |
| 244 | `all` | `all` | swift-testing |
| 263 | `completed` | `completed` | swift-testing |
| 277 | `flagged` | `flagged` | swift-testing |
| 290 | `scheduled` | `scheduled` | swift-testing |
| 308 | `today` | `today` | swift-testing |
| 321 | `tagged` | `tagged` | swift-testing |

### `Examples/RemindersTests/RemindersListsTests.swift`

3 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 16 | `basics` | `basics` | swift-testing |
| 83 | `move` | `move` | swift-testing |
| 109 | `share` | `share` | swift-testing |

### `Examples/RemindersTests/SearchRemindersTests.swift`

3 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 17 | `basics` | `basics` | swift-testing |
| 62 | `showCompleted` | `showCompleted` | swift-testing |
| 123 | `deleteCompleted` | `deleteCompleted` | swift-testing |

### `Examples/SyncUpTests/SyncUpFormTests.swift`

2 runtime tests

| Line | Test name | Greppable | Kind |
| ---: | --- | --- | --- |
| 21 | `saveNew` | `saveNew` | swift-testing |
| 40 | `updateExisting` | `updateExisting` | swift-testing |

## 4. Non-test files under the test trees

Scanned but containing zero runtime tests:

- `Examples/CaseStudiesTests/CaseStudiesTests.swift`
- `Examples/RemindersTests/Internal.swift`
- `Examples/SyncUpTests/Internal.swift`
- `Tests/SQLiteDataTests/CompileTimeTests.swift`
- `Tests/SQLiteDataTests/Internal/BaseCloudKitTests.swift`
- `Tests/SQLiteDataTests/Internal/CloudKit+CustomDump.swift`
- `Tests/SQLiteDataTests/Internal/CloudKitTestHelpers.swift`
- `Tests/SQLiteDataTests/Internal/ResultExtensions.swift`
- `Tests/SQLiteDataTests/Internal/Schema.swift`
- `Tests/SQLiteDataTests/Internal/UserDatabaseHelpers.swift`

---

## 5. Reproducing this inventory

```sh
# Active @Test attributes (excludes // comments)
rg -n '^\\s*@Test\\b' upstream/sqlite-data/Tests upstream/sqlite-data/Examples --glob '*Tests*.swift'
```

Reconciliation against `InstantParityCoverage.swift` lives in
`docs/porting/swift-sqlitedata-port-gap-analysis.md`.

