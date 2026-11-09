## 2026-11-05 <HH:MM:SS> EST — perf-sync-1796 (#1796): v1.9.71, a follower applies each list's newest result and its reads survive a busy applier and a dying socket

- **Why:** on 2026-11-04 the tablet followed the phone's live recording about six minutes late (the user's reading at
  17:33). It held 8,240-11,035 of its own writes, spent about 1.5 s on each server frame and received 29 `refresh-ok`
  of the recording list and 31 `transact-ok` a minute, applied in arrival order; every one-shot read failed at a fixed
  5 s ("Network or live transport failed", on the playback screen), and at a resume a read sent on a dead socket failed
  in 0 ms and was never sent again. Nothing measured the lag.
- **Landed:** merge `<MERGE>` (rebuilt 2026-11-05 on main `3d0dfdfa` after the first check found the tests had never
  compiled; red `bd5d9017`, green `3f66c955`: waiting refreshes lose what a newer one restates, a
  one-shot read waits while the connection moves, up to 30 s; red `25923d45`, green `1fd79eb8`: a read whose
  `add-query` met a dead socket waits for the reconnect; red `882448d2`, green `75915233`: `live.receive-summary`
  reports how old the newest server writes were when applied; guard `076ed107` (+ `a5b5174d`, it prints its lags): a writer and a follower runtime
  under the tablet's measured load; red `fac02655`, green `d7502832`: an observer's registration names its query in the
  gate's phase).
- **Checked:** <from .runs-1796/{red1,red2,red3,red4,red5,green}.log and bundle-compare.log>.
- **Measured on devices before:** iPad build 253 (1.9.67), launch 21:40:41: 26 one-shot reads failed at the fixed 5 s
  in 50 s; the transcript of a 3,428-line live recording took 72.3 s; one observer registration held the operation
  gate 4,583 ms. Phone write -> server -> Mac mirror for live Recording 367: p50 918 ms, p95 2,144 ms, max 3,345 ms.
- **Released:** v1.9.71 (docs/releases/v1.9.71.md). Scribe pins it exactly next (build <N>).
- **Next:** install on the iPhone and the iPad; an hour of `live.receive-summary` from the iPad following a live
  recording (`.runs-1796/lag-report.py --device iPad --build <N>`), written on #1796 and #1797; the observer
  registration's named phase at the next launch stall (#1131, #1137).
