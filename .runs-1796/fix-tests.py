#!/usr/bin/env python3
"""#1796: make the lane's new tests compile, in whichever commit's version of each file is checked out.

The mini's build (job 1796-check, 2026-11-05 02:02) found: CustomDump's expectNoDifference takes plain autoclosures, so
an `await` inside one is an error; and `entity.values[...]` is an `InstantMaterializedValue?`, read through `.first`.
Swift checks effects only in a closure that type-checked, so the `.string` error hid one more `await` (the long-apply
test's `applied.values`). Each replacement is asserted, and running it twice changes nothing.

Usage: fix-tests.py <repo root>
"""
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
follower = root / "Tests/InstantSwiftDataCoreTests/InstantFollowerLatencyTests.swift"
two_client = root / "Tests/InstantSwiftDataCoreTests/InstantWriterFollowerLatencyTests.swift"


def fix(path, replacements):
    if not path.exists():
        return
    text = path.read_text()
    for old, new, expected in replacements:
        count = text.count(old)
        if count == 0 and text.count(new) >= expected:
            continue  # already fixed
        assert count == expected, f"{path.name}: expected {expected} of {old!r}, found {count}"
        text = text.replace(old, new)
    path.write_text(text)
    print(f"fixed {path.relative_to(root)}")


fix(follower, [
    (
        "    expectNoDifference(\n      try await FollowerFrame.takeBuffered(from: frames),\n",
        "    let taken = try await FollowerFrame.takeBuffered(from: frames)\n    expectNoDifference(\n      taken,\n",
        4,
    ),
    (
        "    expectNoDifference(await appended.values, [true])\n",
        "    let appendedValues = await appended.values\n    expectNoDifference(appendedValues, [true])\n",
        1,
    ),
    (
        "      expectNoDifference(\n        await applied.values,\n",
        "      let appliedOps = await applied.values\n      expectNoDifference(\n        appliedOps,\n",
        1,
    ),
    (
        'guard case let .string(text)? = entity.values["text"] else',
        'guard case let .string(text)? = entity.values["text"]?.first else',
        1,
    ),
])

fix(two_client, [
    (
        'guard case let .string(text)? = entity.values["text"] else',
        'guard case let .string(text)? = entity.values["text"]?.first else',
        1,
    ),
])
