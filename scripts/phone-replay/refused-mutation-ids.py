#!/usr/bin/env python3
"""The mutations a device saw refused, from a diagnostics journal, as the phone replay gate's refusal file.

Reads JSON lines whose `entry.metadata` carries the library's refusal fields (`InstantMutationRefusal`:
`refusedCheck`, `refusedEntityIDs`, ...), keeps the first sighting of each `mutationID` for one session, and writes
a JSON object keyed by mutation id. Each value keeps only ids, names, kinds, and stamps; `refusedValues` (which can
hold user text) is never read.

    scripts/phone-replay/refused-mutation-ids.py --journal ~/Library/Logs/Scribe/diagnostics.jsonl \
        --session 7ded00b0 --until 2026-09-30T20:47:53-04:00 > refusals.json

A journal keeps growing while the session runs, so pin `--until` (or keep the extracted file) to reproduce a run.
"""

import argparse
import datetime
import json
import sys
from collections import Counter


def milliseconds(text):
    moment = datetime.datetime.fromisoformat(text)
    if moment.tzinfo is None:
        raise argparse.ArgumentTypeError(f"{text!r} needs a UTC offset, for example 2026-09-30T20:47:53-04:00")
    return moment.timestamp() * 1000


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--journal", required=True, help="diagnostics JSONL (for example the Mac collector's)")
    parser.add_argument("--session", required=True, help="the session id or its prefix (entry.sessionID)")
    parser.add_argument("--since", type=milliseconds, help="only refusals logged at or after this ISO time")
    parser.add_argument("--until", type=milliseconds, help="only refusals logged at or before this ISO time")
    arguments = parser.parse_args()

    refusals = {}
    with open(arguments.journal, encoding="utf-8", errors="replace") as journal:
        for line in journal:
            if arguments.session not in line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue
            entry = record.get("entry") or {}
            if not str(entry.get("sessionID", "")).startswith(arguments.session):
                continue
            metadata = entry.get("metadata") or {}
            if not (metadata.get("refusedCheck") and metadata.get("refusedEntityIDs")):
                continue
            logged = record.get("timestampMs")
            if arguments.since is not None and (logged is None or logged < arguments.since):
                continue
            if arguments.until is not None and (logged is None or logged > arguments.until):
                continue
            mutation_id = metadata.get("mutationID")
            if mutation_id and mutation_id not in refusals:
                refusals[mutation_id] = dict(
                    t=logged,
                    ns=metadata.get("refusedNamespace"),
                    entity=metadata.get("refusedEntityIDs"),
                    created=metadata.get("createdAtMilliseconds"),
                    kind=metadata.get("refusalKind"),
                    attrs=metadata.get("refusedAttributes"),
                )

    json.dump(refusals, sys.stdout, indent=1)
    if refusals:
        stamps = sorted(value["t"] for value in refusals.values() if value["t"] is not None)
        local = lambda stamp: datetime.datetime.fromtimestamp(stamp / 1000).astimezone().isoformat(timespec="seconds")
        print(
            f"{len(refusals)} refused mutations, logged {local(stamps[0])} to {local(stamps[-1])}; "
            f"kinds {dict(Counter(value['kind'] for value in refusals.values()))}",
            file=sys.stderr,
        )
    else:
        print("0 refused mutations", file=sys.stderr)


if __name__ == "__main__":
    main()
