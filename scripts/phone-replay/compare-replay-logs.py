#!/usr/bin/env python3
"""Compares two phone replay logs on everything except times and print order.

    scripts/phone-replay/compare-replay-logs.py REFERENCE.log CANDIDATE.log

Exits 0 when the candidate matches or improves on the reference, 1 when it is worse, and 2 when the two runs had
different inputs (frame shape, selection, store, refusals, or window) and cannot be compared.

Worse means any of: the test failed or printed a stuck, unsupported, or unapplied-verdict line; writes were left
pending; the accepted, refused, or failed-row counts changed; more frames rebased or more bodies were replayed; a
decline reason grew; or a comparison (after the drain, or after a full restatement) shows a gap the reference lacks.
Fewer rebases, bodies, declines, or gaps are reported as better. Which attribute a `changesShadowedFact` decline
names depends on frame order in logs from before the committed tool, so declines are judged by reason.
"""

import re
import sys

PAIRS = re.compile(r'\(key: "([^"]*)", value: (\d+)\)')
DICTIONARY_PAIRS = re.compile(r'"([^"]*)": (\d+)')
DRAIN_FIELDS = [
    "pending at start", "pending at end", "frames", "rebased frames", "bodies", "accepted", "refused",
    "failed rows at start", "failed rows at end",
]
LINES = [
    ("start", re.compile(
        r"REPLAY start: (\d+) pending, (\d+) failed, (\d+) of (\d+) refusals pending, window (\d+), "
        r"newest device stamp (\d+)")),
    ("window", re.compile(
        r"REPLAY window (\d+): claimed (\d+), refused (\d+), frame (\d+) facts in \S+ seconds, bodies (\d+), "
        r"removed \+(\d+), declines (.*), pending (\d+)$")),
    ("drain", re.compile(
        r"REPLAY drain: (\d+) -> (\d+) pending in .*?, (\d+) frames, (\d+) with a component rebase, (\d+) bodies, "
        r"slowest frame .*; accepted (\d+), refused (\d+); failed rows (\d+) -> (\d+)")),
    ("reductions", re.compile(
        r"REPLAY reductions \+(\d+), reduced \+(\d+), receipt patches \+(\d+), "
        r"refused overlays removed by the reduction \+(\d+)")),
    ("frames", re.compile(r"REPLAY frames: (\S+); selection (.*)")),
    ("declines", re.compile(r"REPLAY declines: (.*)")),
    ("compared", re.compile(r"REPLAY compare \[(.*?)\]: (\d+) server entities compared")),
    ("missing", re.compile(r"REPLAY compare \[(.*?)\] missing entities by namespace: (.*)")),
    ("different", re.compile(r"REPLAY compare \[(.*?)\] fields with a different value: \d+ (.*)")),
    ("absent", re.compile(r"REPLAY compare \[(.*?)\] fields absent on the device: \d+ (.*)")),
    ("links", re.compile(r"REPLAY compare \[(.*?)\] link sets missing server links: (.*)")),
    ("example", re.compile(r"REPLAY example \[(.*?)\] (.*)")),
    ("restatement", re.compile(r"REPLAY restatement: (\d+) facts")),
    ("head", re.compile(r"LOAD-BEFORE .* head (\S+)")),
]


def by_reason(declines):
    reasons = {}
    for name, count in declines.items():
        reasons[name.split(" ")[0]] = reasons.get(name.split(" ")[0], 0) + count
    return reasons


def parse(path):
    log = {"windows": {}, "compare": {}, "examples": {}, "declines": {}, "test": None, "problems": []}
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if "Test run with" in line:
                log["test"] = "passed" if " passed after " in line else "failed"
            if "recorded an issue" in line or "error:" in line or "Fatal" in line:
                log["problems"].append(line)
            for kind, pattern in LINES:
                match = pattern.match(line)
                if not match:
                    continue
                groups = match.groups()
                if kind == "start":
                    log["start"] = tuple(int(value) for value in groups)
                elif kind == "window":
                    number, claimed, refused, facts, bodies, removed, declines, pending = groups
                    reasons = by_reason({name: int(count) for name, count in DICTIONARY_PAIRS.findall(declines)})
                    log["windows"][int(number)] = (
                        int(claimed), int(refused), int(facts), int(bodies), int(removed),
                        tuple(sorted(reasons.items())), int(pending),
                    )
                elif kind == "drain":
                    log["drain"] = dict(zip(DRAIN_FIELDS, (int(value) for value in groups)))
                elif kind == "reductions":
                    log["reductions"] = tuple(int(value) for value in groups)
                elif kind == "frames":
                    log["frames"], log["selection"] = groups
                elif kind == "declines":
                    log["declines"] = {name: int(count) for name, count in PAIRS.findall(groups[0])}
                elif kind == "compared":
                    log["compare"].setdefault(groups[0], {})["entities compared"] = {"": int(groups[1])}
                elif kind in ("missing", "different", "absent", "links"):
                    log["compare"].setdefault(groups[0], {})[kind] = {
                        name: int(count) for name, count in PAIRS.findall(groups[1])
                    }
                elif kind == "example":
                    log["examples"].setdefault(groups[0], set()).add(groups[1])
                elif kind == "restatement":
                    log["restatement"] = int(groups[0])
                elif kind == "head":
                    log["head"] = groups[0]
                break
            else:
                if line.startswith("REPLAY "):
                    log["problems"].append(line)
    return log


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 64
    reference, candidate = parse(sys.argv[1]), parse(sys.argv[2])
    worse, better, notes = [], [], []

    def row(metric, old, new, status):
        print(f"{metric:<58} {str(old):<22} {str(new):<22} {status}")

    print(f"{'':<58} {'reference ' + reference.get('head', '?'):<22} {'candidate ' + candidate.get('head', '?'):<22}")
    inputs_differ = False
    for metric, key in [("frame shape", "frames"), ("selection", "selection"), ("start", "start")]:
        old, new = reference.get(key), candidate.get(key)
        same = old == new
        inputs_differ |= not same
        row(f"input: {metric}", "(same)" if same and key == "selection" else old,
            "(same)" if same and key == "selection" else new, "same" if same else "INPUTS DIFFER")

    for field in DRAIN_FIELDS:
        old, new = reference.get("drain", {}).get(field), candidate.get("drain", {}).get(field)
        if new is None:
            status = "worse (no drain line)"
        elif field == "pending at end":
            status = "same" if new == 0 and old == 0 else ("worse" if new != 0 else "better")
        elif field in ("rebased frames", "bodies"):
            status = "same" if old == new else ("worse" if old is None or new > old else "better")
        elif field == "frames":
            status = "same" if old == new else "differs"
        else:
            status = "same" if old == new else "worse"
        row(f"drain: {field}", old, new, status)
        if status.startswith("worse"):
            worse.append(f"drain: {field}")
        elif status == "better":
            better.append(f"drain: {field}")

    old, new = reference.get("reductions"), candidate.get("reductions")
    row("reductions, reduced, receipt patches, overlays removed", old, new, "same" if old == new else "differs")

    old_reasons, new_reasons = by_reason(reference["declines"]), by_reason(candidate["declines"])
    for reason in sorted(set(old_reasons) | set(new_reasons)):
        old, new = old_reasons.get(reason, 0), new_reasons.get(reason, 0)
        status = "same" if old == new else ("worse" if new > old else "better")
        row(f"declines: {reason}", old, new, status)
        if status == "worse":
            worse.append(f"declines {reason}")
        elif status == "better":
            better.append(f"declines {reason}")
    if reference["declines"] != candidate["declines"]:
        notes.append(f"decline names: reference {sorted(reference['declines'].items())}, "
                     f"candidate {sorted(candidate['declines'].items())}")

    for label in sorted(set(reference["compare"]) | set(candidate["compare"])):
        old_section, new_section = reference["compare"].get(label, {}), candidate["compare"].get(label, {})
        for kind in ("entities compared", "missing", "different", "absent", "links"):
            old, new = old_section.get(kind, {}), new_section.get(kind, {})
            keys = sorted(set(old) | set(new))
            grown = [key for key in keys if new.get(key, 0) > old.get(key, 0)]
            shrunk = [key for key in keys if new.get(key, 0) < old.get(key, 0)]
            if kind == "entities compared":
                status = "same" if old == new else "differs"
            else:
                status = "worse" if grown else ("better" if shrunk else "same")
            row(f"[{label}] {kind}", sum(old.values()), sum(new.values()), status)
            if status == "worse":
                worse.append(f"[{label}] {kind}: {', '.join(grown)}")
            elif status == "better":
                better.append(f"[{label}] {kind}: {', '.join(shrunk)}")
        old_examples = reference["examples"].get(label, set())
        new_examples = candidate["examples"].get(label, set())
        for example in sorted(new_examples - old_examples):
            notes.append(f"[{label}] only in the candidate: {example}")
        for example in sorted(old_examples - new_examples):
            notes.append(f"[{label}] only in the reference: {example}")

    old, new = reference.get("restatement"), candidate.get("restatement")
    row("restatement facts", old, new, "same" if old == new else "differs")

    common = sorted(set(reference["windows"]) & set(candidate["windows"]))
    identical = sum(1 for number in common if reference["windows"][number] == candidate["windows"][number])
    only = sorted(set(reference["windows"]) ^ set(candidate["windows"]))
    row("printed windows identical (claims, refusals, facts, bodies)", f"{identical} of {len(common)}",
        f"{len(only)} printed in one log only", "same" if identical == len(common) and not only else "differs")
    for number in [number for number in common if reference["windows"][number] != candidate["windows"][number]][:10]:
        notes.append(f"window {number}: reference {reference['windows'][number]}, candidate {candidate['windows'][number]}")

    row("test", reference["test"], candidate["test"], "same" if candidate["test"] == "passed" else "worse")
    if candidate["test"] != "passed":
        worse.append(f"test {candidate['test']}")
    for problem in candidate["problems"]:
        worse.append(problem)

    for note in notes:
        print(f"note: {note}")
    for item in better:
        print(f"better: {item}")
    for item in worse:
        print(f"WORSE: {item}")
    if inputs_differ:
        print("VERDICT: not comparable (the runs had different inputs)")
        return 2
    print("VERDICT: worse than the reference" if worse else "VERDICT: matches or improves on the reference")
    return 1 if worse else 0


if __name__ == "__main__":
    sys.exit(main())
