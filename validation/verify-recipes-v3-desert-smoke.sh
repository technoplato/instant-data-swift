#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${INSTANT_SWIFT_DATA_RECIPES_V3_DESERT_SMOKE_RESULTS_DIR:-/tmp/instant-data-swift-recipes-v3-desert-smoke-$(date -u +%Y%m%dT%H%M%SZ)}"
if [[ "${RESULTS_DIR}" != /* ]]; then
  RESULTS_DIR="${PWD}/${RESULTS_DIR}"
fi

TEST_LOG="${RESULTS_DIR}/swift-test.log"
EVIDENCE_JSONL="${RESULTS_DIR}/recipes-v3-desert-smoke.jsonl"

if ! command -v swift >/dev/null 2>&1; then
  echo "swift is required to run the Recipes V3 desert smoke tests." >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to validate the Recipes V3 desert smoke evidence." >&2
  exit 1
fi

mkdir -p "${RESULTS_DIR}"
: >"${TEST_LOG}"
: >"${EVIDENCE_JSONL}"

test_status=0
if (
  cd "${ROOT}"
  CI=1 NO_COLOR=1 swift test --filter RecipesV3DesertSmokeTests
) 2>&1 | tee "${TEST_LOG}"; then
  :
else
  test_status=$?
fi

evidence_status=0
if TEST_LOG="${TEST_LOG}" EVIDENCE_JSONL="${EVIDENCE_JSONL}" python3 <<'PY'
import collections
import json
import os
import pathlib
import re
import sys

prefix = "INSTANT_RECIPES_DESERT_SMOKE "
expected_recipes = [
    "todos",
    "cursors",
    "custom-cursors",
    "reactions",
    "typing-indicator",
    "avatar-stack",
    "merge-tile-game",
    "auth",
]
blocked_outcomes = {"unsupported", "skip", "skipped", "not-run", "notrun"}
test_log = pathlib.Path(os.environ["TEST_LOG"])
evidence_jsonl = pathlib.Path(os.environ["EVIDENCE_JSONL"])

payloads = []
with test_log.open(encoding="utf-8", errors="replace") as lines:
    for line in lines:
        marker = line.find(prefix)
        if marker >= 0:
            payloads.append(line[marker + len(prefix):].strip())

# Keep every prefixed payload as a diagnostic artifact even when validation fails.
with evidence_jsonl.open("w", encoding="utf-8", newline="\n") as output:
    for payload in payloads:
        output.write(payload)
        output.write("\n")

errors = []
records = []


def object_without_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key {key!r}")
        result[key] = value
    return result


for index, payload in enumerate(payloads, start=1):
    if not payload:
        errors.append(f"Evidence line {index} has an empty JSON payload.")
        continue
    try:
        record = json.loads(payload, object_pairs_hook=object_without_duplicate_keys)
    except (json.JSONDecodeError, ValueError) as error:
        errors.append(f"Evidence line {index} is not valid strict JSON: {error}.")
        continue
    if not isinstance(record, dict):
        errors.append(f"Evidence line {index} must be a JSON object.")
        continue
    records.append((index, record))

if len(payloads) != len(expected_recipes):
    errors.append(
        "Expected exactly "
        f"{len(expected_recipes)} prefixed evidence lines, captured {len(payloads)}."
    )

recipe_counts = collections.Counter(
    record.get("recipe") for _, record in records if isinstance(record.get("recipe"), str)
)
missing = [recipe for recipe in expected_recipes if recipe_counts[recipe] == 0]
duplicates = [recipe for recipe in expected_recipes if recipe_counts[recipe] > 1]
unexpected = sorted(recipe for recipe in recipe_counts if recipe not in expected_recipes)
if missing:
    errors.append(f"Missing recipe evidence: {', '.join(missing)}.")
if duplicates:
    errors.append(f"Duplicate recipe evidence: {', '.join(duplicates)}.")
if unexpected:
    errors.append(f"Unexpected recipe evidence: {', '.join(unexpected)}.")


def normalized_outcome(value):
    return re.sub(r"[-_\s]+", "-", value.strip().lower())


def blocked_values(value, path="$"):
    if isinstance(value, dict):
        for key, child in value.items():
            yield from blocked_values(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from blocked_values(child, f"{path}[{index}]")
    elif isinstance(value, str) and normalized_outcome(value) in blocked_outcomes:
        yield path, value


for line_number, record in records:
    recipe = record.get("recipe")
    label = recipe if isinstance(recipe, str) and recipe else f"line {line_number}"
    if record.get("ok") is not True:
        errors.append(f"{label}: expected ok=true.")
    if record.get("route") != "desert":
        errors.append(f"{label}: expected route='desert'.")
    if record.get("hostAdapter") != "network-framework-host":
        errors.append(f"{label}: expected hostAdapter='network-framework-host'.")
    if record.get("peerAdapter") != "network-framework-peer":
        errors.append(f"{label}: expected peerAdapter='network-framework-peer'.")
    if record.get("hostTransport") != "in-process":
        errors.append(f"{label}: expected hostTransport='in-process'.")
    if record.get("peerTransport") != "network-framework":
        errors.append(f"{label}: expected peerTransport='network-framework'.")
    phase = record.get("phase")
    if not isinstance(phase, str) or not phase.strip():
        errors.append(f"{label}: expected a nonempty phase.")
    for path, value in blocked_values(record):
        errors.append(f"{label}: disallowed outcome {value!r} at {path}.")

if errors:
    for error in errors:
        print(f"Recipes V3 desert smoke evidence failure: {error}", file=sys.stderr)
    print(f"Captured evidence: {evidence_jsonl}", file=sys.stderr)
    print(f"Swift test log: {test_log}", file=sys.stderr)
    raise SystemExit(1)

print(
    f"Validated {len(expected_recipes)} Recipes V3 desert smoke results: "
    f"{evidence_jsonl}"
)
PY
then
  :
else
  evidence_status=$?
fi

if (( test_status != 0 )); then
  echo "Recipes V3 desert smoke Swift test failed with exit code ${test_status}." >&2
  echo "Swift test log: ${TEST_LOG}" >&2
  exit "${test_status}"
fi
if (( evidence_status != 0 )); then
  exit "${evidence_status}"
fi
