#!/usr/bin/env python3
"""#1796: a device's follower lag from the Mac collector's live.receive-summary lines (library 1.9.69+).

Each line covers one minute of the device's receive buffer: frames taken, their waits for the applier, the applier's
busy share, the frames newer refreshes replaced, and factLag: for each applied refresh-ok that carried a fact newer than
any applied before, the device's clock minus the server's time on that fact (any clock difference included).

usage: lag-report.py --device iPad [--build 260] [--since 'HH:MM'] [--until 'HH:MM'] [--log PATH] [--minutes]
Prints the hour's distribution: minutes, frames, the frame-weighted median of the minute medians, the p95 of the
minute p95s, the largest maximum; the same for the buffer waits; and the replaced frames.
"""
import argparse
import json
import pathlib


def percentile(values, fraction):
    if not values:
        return None
    values = sorted(values)
    return values[min(len(values) - 1, int(round((len(values) - 1) * fraction)))]


def weighted_median(pairs):
    pairs = sorted((value, weight) for value, weight in pairs if weight > 0)
    total = sum(weight for _, weight in pairs)
    if total == 0:
        return None
    running = 0
    for value, weight in pairs:
        running += weight
        if running * 2 >= total:
            return value
    return pairs[-1][0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", required=True)
    parser.add_argument("--build")
    parser.add_argument("--since")
    parser.add_argument("--until")
    parser.add_argument("--log", default=str(pathlib.Path.home() / "Library/Logs/Scribe/diagnostics.jsonl"))
    parser.add_argument("--minutes", action="store_true", help="print every minute's line")
    args = parser.parse_args()

    rows = []
    with open(args.log, encoding="utf-8", errors="replace") as log:
        for line in log:
            if "live.receive-summary" not in line:
                continue
            try:
                record = json.loads(line)
                entry = record["entry"]
                entry = json.loads(entry) if isinstance(entry, str) else entry
            except (ValueError, KeyError, TypeError):
                continue
            if entry.get("name") != "live.receive-summary" or entry.get("deviceName") != args.device:
                continue
            if args.build and f"({args.build})" not in entry.get("appVersion", ""):
                continue
            clock = entry.get("timestampLocal", "")[11:16]
            if args.since and clock < args.since or args.until and clock > args.until:
                continue
            metadata = {key: int(value) for key, value in entry.get("metadata", {}).items() if str(value).lstrip("-").isdigit()}
            rows.append((entry.get("timestampLocal", ""), entry.get("appVersion", ""), metadata))

    if not rows:
        print(f"no live.receive-summary lines for {args.device}")
        return
    if args.minutes:
        for stamp, version, m in rows:
            print(f"{stamp[11:19]} {version} frames {m.get('takenFrames', 0):>4} wait p50/p95/max "
                  f"{m.get('waitMedianMilliseconds', 0)}/{m.get('waitP95Milliseconds', 0)}/{m.get('waitMaxMilliseconds', 0)} ms "
                  f"deepest {m.get('deepestBuffer', 0)} busy {m.get('applyingPercent', 0)}% replaced "
                  f"{m.get('replacedFrames', 0)}/{m.get('replacedResults', 0)} lag frames {m.get('factLagFrames', 0)} "
                  f"p50/p95/max {m.get('factLagMedianMilliseconds', 0)}/{m.get('factLagP95Milliseconds', 0)}/"
                  f"{m.get('factLagMaxMilliseconds', 0)} ms")
    lagged = [m for _, _, m in rows if m.get("factLagFrames", 0) > 0]
    print(f"{args.device} {rows[0][1]}..{rows[-1][1]} {rows[0][0][11:16]}-{rows[-1][0][11:16]}: {len(rows)} minutes, "
          f"{sum(m.get('takenFrames', 0) for _, _, m in rows)} frames taken")
    if lagged:
        print("  newest server write's age when applied (factLag): "
              f"median {weighted_median([(m['factLagMedianMilliseconds'], m['factLagFrames']) for m in lagged])} ms, "
              f"p95 {percentile([m['factLagP95Milliseconds'] for m in lagged], 0.95)} ms, "
              f"max {max(m['factLagMaxMilliseconds'] for m in lagged)} ms "
              f"({sum(m['factLagFrames'] for m in lagged)} frames over {len(lagged)} minutes)")
    print("  frame wait for the applier: "
          f"median {weighted_median([(m.get('waitMedianMilliseconds', 0), m.get('takenFrames', 0)) for _, _, m in rows])} ms, "
          f"p95 {percentile([m.get('waitP95Milliseconds', 0) for _, _, m in rows], 0.95)} ms, "
          f"max {max(m.get('waitMaxMilliseconds', 0) for _, _, m in rows)} ms; deepest buffer "
          f"{max(m.get('deepestBuffer', 0) for _, _, m in rows)}; applier busy p95 "
          f"{percentile([m.get('applyingPercent', 0) for _, _, m in rows], 0.95)}%; replaced frames "
          f"{sum(m.get('replacedFrames', 0) for _, _, m in rows)}, results {sum(m.get('replacedResults', 0) for _, _, m in rows)}")


if __name__ == "__main__":
    main()
