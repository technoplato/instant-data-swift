# Plan 2026-08-11-runtime-split-sil

Owner: grok-build-runtime-split
Mode: mower
Issues: #150 compile health, InstantRuntime SIL hang

## Outcome
Shrink `InstantRuntime.swift` translation unit so debug builds no longer need
`-sil-disable-pass=closure-lifetime-fixup`. Keep behavior identical.

## Steps
1. Extract free-standing infrastructure types out of InstantRuntime.swift.
2. First slice: ExactTaskOwner + LiveSession actor cluster (~1.5k lines).
3. Second slice: end-of-file VisibleWrite helpers.
4. Build InstantSwiftDataCore; try removing SIL unsafeFlags if hang gone.
5. Run focused InstantSwiftDataCoreTests / full suite as risk warrants.
6. Commit when green.

## Touching
- Sources/InstantSwiftDataCore/InstantRuntime.swift
- Sources/InstantSwiftDataCore/InstantRuntimeExactTaskOwner.swift (new)
- Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift (new)
- Sources/InstantSwiftDataCore/InstantVisibleWriteFilter.swift (new, slice 2)
- Package.swift (only when removing SIL flag)

## Conflict check
Many exhausted codex-019fe994 claims on InstantRuntime; freezes already landed.
This mower only moves types/files, no behavior change.
