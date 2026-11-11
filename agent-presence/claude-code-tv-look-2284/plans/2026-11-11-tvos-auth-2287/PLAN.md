# Plan 2026-11-11-tvos-auth-2287 (#2287, claude-code/tv-look-2284@halfjew22)

planId: 2026-11-11-tvos-auth-2287. agentId: claude-code/tv-look-2284@halfjew22. role: mower (a compile defect; no
behaviour change on any platform that builds today). Found by #2284, a consuming app's first tvOS build.

## The defect, measured

2026-11-11 16:59, the M5 (Xcode 27.2), a consuming app's tvOS target against v1.9.84:
`Sources/InstantSwiftData/InstantAuthProvider.swift:524:5: error: 'ASWebAuthenticationPresentationContextProviding' is
unavailable in tvOS`. The gate on the browser and Apple authorizers (lines 249, 283, 506) excludes watchOS but admits
tvOS, which has AuthenticationServices and UIKit but no web authentication presentation. Only the browser authorizer
failed; the Apple ID authorizer compiled.

## Steps

1. red: the library's tvOS compile on the M5 (xcodebuild, scheme InstantSwiftData, generic/platform=tvOS Simulator,
   through build.sh) fails at line 524. The log is the evidence.
2. green: the browser authorizer leaves the build on tvOS, with the reason beside its gate; the authorization-code path
   throws "Browser authentication is unavailable on this platform" there, as on watchOS. Sign in with Apple stays. The
   same compile passes; the macOS test bundle for InstantAuthProvider still passes.
3. release: v1.9.85 with docs/releases/v1.9.85.md and its PROGRESS.md entry; land; tag the landing; push the tag.

## Touching

- Sources/InstantSwiftData/InstantAuthProvider.swift
- docs/releases/v1.9.85.md (new), PROGRESS.md

Conflict check: InstantAuthProvider.swift's last claim is older work, landed; no release is in flight (v1.9.84 is the
newest tag, 10:20 today).
