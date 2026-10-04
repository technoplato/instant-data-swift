#!/usr/bin/env python3
"""Backfills the cross-repository audit ledger (docs/audits/commit-changelog.md) from git, and checks it.

Every substantive commit in Scribe or in this library gets a ledger line (AGENTS.md). Branch commits that reached
Scribe's main through merges were often never sent, so the ledger had gaps: on 2026-10-04, 2,176 of Scribe main's
3,259 non-merge commits (a first count that matched only backticked full SHAs said 2,237). This script lists the
non-merge commits reachable from a ref, skips the ones the ledger already names, and writes one line for each of the
rest, from git alone:

    ## <committer time in America/New_York, with seconds> <EDT|EST> — <label> `<full SHA>`
    <subject>

It writes nothing it did not read from git: no subject is edited. Each new entry goes before the first existing entry
whose time is equal or older, as the ledger is newest first; entries whose header has no readable time are passed over
for that comparison, so their place never moves. Running it again adds nothing.

A commit counts as recorded when its full SHA appears anywhere in the ledger, or when a backticked prefix of at least
7 hex characters appears in an entry for the same repository (older entries name commits that way).

Usage:
    python3 scripts/audit/backfill_commit_ledger.py --git-dir /Users/laptop/Sync/tools/realtime-voice \\
        --ref origin/main --label scribe --check     # report the commits the ledger lacks; exit 1 when any
    python3 scripts/audit/backfill_commit_ledger.py --git-dir /Users/laptop/Sync/tools/realtime-voice \\
        --ref origin/main --label scribe --write     # insert them
"""
import argparse
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

NEW_YORK = ZoneInfo("America/New_York")
MONTHS = {m: i + 1 for i, m in enumerate(
    "January February March April May June July August September October November December".split())}
ISO = re.compile(r"(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})")
LONG = re.compile(
    r"(%s) (\d{1,2})(?:st|nd|rd|th)?, (\d{4}) at (\d{1,2}):(\d{2}):(\d{2}) ?([AaPp])\.?[Mm]\.?" % "|".join(MONTHS))
LONG24 = re.compile(r"(%s) (\d{1,2})(?:st|nd|rd|th)?, (\d{4}) at (\d{1,2}):(\d{2}):(\d{2})" % "|".join(MONTHS))
DATE = re.compile(r"(\d{4})-(\d{2})-(\d{2})")
FULL_SHA = re.compile(r"\b[0-9a-f]{40}\b")
SHORT_SHA = re.compile(r"`([0-9a-f]{7,39})`")
# The names this ledger has used for Scribe's repository.
SCRIBE_LABELS = ("scribe", "realtime-voice", "sqlite-data")


def stamp(header):
    """The header's time in America/New_York, naive, or None when it has none."""
    m = ISO.search(header)
    if m:
        return datetime(*map(int, m.groups()))
    m = LONG.search(header)
    if m:
        month, day, year, hour, minute, second, half = m.groups()
        hour = int(hour) % 12 + (12 if half in "Pp" else 0)
        return datetime(int(year), MONTHS[month], int(day), hour, int(minute), int(second))
    m = LONG24.search(header)
    if m:
        month, day, year, hour, minute, second = m.groups()
        return datetime(int(year), MONTHS[month], int(day), int(hour), int(minute), int(second))
    m = DATE.search(header)
    if m:
        return datetime(*map(int, m.groups()))
    return None


def split_ledger(text):
    starts = [m.start() for m in re.finditer(r"(?m)^## ", text)]
    if not starts:
        return text, []
    head, body = text[:starts[0]], text[starts[0]:]
    return head, [e for e in re.split(r"(?m)^(?=## )", body) if e]


def is_scribe_entry(entry):
    first = entry.split("\n", 6)
    probe = " ".join(first[:6]).lower()
    return any(label in probe for label in SCRIBE_LABELS)


def recorded_commits(entries):
    full, short = set(), set()
    for entry in entries:
        full.update(FULL_SHA.findall(entry))
        if is_scribe_entry(entry):
            short.update(SHORT_SHA.findall(entry))
    return full, short


def git_commits(git_dir, ref):
    out = subprocess.run(
        ["git", "-C", git_dir, "-c", "core.fsmonitor=false", "log", "--no-merges", "--format=%H%x00%ct%x00%s", ref],
        capture_output=True, text=True, check=True,
    ).stdout
    commits = []
    for line in out.splitlines():
        sha, seconds, subject = line.split("\x00", 2)
        commits.append((sha, int(seconds), subject))
    return commits


def ledger_line(label, sha, seconds, subject):
    when = datetime.fromtimestamp(seconds, NEW_YORK)
    return f"## {when.strftime('%Y-%m-%d %H:%M:%S')} {when.strftime('%Z')} — {label} `{sha}`\n{subject}\n\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--git-dir", required=True, help="the repository to read commits from")
    parser.add_argument("--ref", default="origin/main", help="the ref whose non-merge commits must be recorded")
    parser.add_argument("--label", default="scribe", help="the repository name in each new line")
    parser.add_argument("--ledger", default=str(Path(__file__).resolve().parents[2] / "docs/audits/commit-changelog.md"))
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="report the missing commits and exit 1 when any")
    mode.add_argument("--write", action="store_true", help="insert the missing commits")
    args = parser.parse_args()

    ledger = Path(args.ledger)
    head, entries = split_ledger(ledger.read_text())
    full, short = recorded_commits(entries)
    commits = git_commits(args.git_dir, args.ref)
    missing = [
        c for c in commits
        if c[0] not in full and not any(c[0].startswith(s) for s in short)
    ]
    print(f"{args.ref} in {args.git_dir}: {len(commits)} non-merge commits, {len(missing)} not in the ledger "
          f"({len(entries)} entries)")
    if args.check:
        for sha, seconds, subject in missing[:20]:
            print(f"  missing {sha[:12]} {datetime.fromtimestamp(seconds, NEW_YORK):%Y-%m-%d %H:%M:%S} {subject[:80]}")
        sys.exit(1 if missing else 0)

    stamps = [stamp(e.split("\n", 1)[0]) for e in entries]
    is_new = [False] * len(entries)
    # Oldest first, so commits with equal times keep git's order, newest first, once inserted.
    for sha, seconds, subject in reversed(missing):
        line = ledger_line(args.label, sha, seconds, subject)
        t = datetime.fromtimestamp(seconds, NEW_YORK).replace(tzinfo=None)
        index = len(entries)
        for k, u in enumerate(stamps):
            if u is not None and u <= t:
                index = k
                break
        entries.insert(index, line)
        stamps.insert(index, t)
        is_new.insert(index, True)
    # Existing entries are written back exactly as read. A new entry that follows one without a blank line starts
    # with one; a new last entry ends with a single newline, as the file did.
    parts = []
    for entry, new in zip(entries, is_new):
        if new and parts and not parts[-1].endswith("\n\n"):
            entry = "\n" + entry
        parts.append(entry)
    if is_new and is_new[-1]:
        parts[-1] = parts[-1].rstrip("\n") + "\n"
    ledger.write_text(head + "".join(parts))
    print(f"inserted {len(missing)} lines; the ledger has {len(entries)} entries")


if __name__ == "__main__":
    main()
