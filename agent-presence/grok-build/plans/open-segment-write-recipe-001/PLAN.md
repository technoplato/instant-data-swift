# PLAN open-segment-write-recipe-001

- planId: open-segment-write-recipe-001
- agentId: grok-build
- role: grower (user-ordered ADR 0015 S2 / #155 / overview 10 recipe)
- outcome: First-class open-segment write recipe + compile-checked example + unit tests + ADR cross-links
- Instant issue: #155

## Steps
1. Write recipe doc under ADR 0015 folder
2. Add InstantSwiftDataCore OpenSegmentWriteRecipe example (words JSON + mutation builders)
3. Add unit tests (encode/decode + mutation shape)
4. Cross-link plan.md + overview 10
5. Commit on named branch

## Touching
- docs/adr/0015-sqlite-data-parity-ergonomics/open-segment-write-recipe.md (new)
- docs/adr/0015-sqlite-data-parity-ergonomics/plan.md
- docs/adr/0015-sqlite-data-parity-ergonomics/overviews/10-facade-deletion-inventory-and-target-write.md
- docs/adr/0015-sqlite-data-parity-ergonomics/findings.md
- Sources/InstantSwiftDataCore/OpenSegmentWriteRecipe.swift (new)
- Sources/InstantSwiftData/OpenSegmentWriteRecipeEntities.swift (new, typed InstantEntityModel)
- Tests/InstantSwiftDataCoreTests/OpenSegmentWriteRecipeTests.swift (new)
- Tests/InstantSwiftDataTests/OpenSegmentWriteRecipeTypedTests.swift (new)
