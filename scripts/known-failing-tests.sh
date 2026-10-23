#!/usr/bin/env bash
# The InstantSwiftDataCoreTests bundle's known failures (#1021): run the bundle, compare a run with
# Tests/known-failing.txt, or record the list. See scripts/known-failing-tests.py for the subcommands.
set -euo pipefail
exec /usr/bin/env python3 -I "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/known-failing-tests.py" "$@"
