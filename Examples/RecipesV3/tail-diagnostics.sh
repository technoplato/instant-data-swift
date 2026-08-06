#!/bin/zsh
# Tail Tailnet diagnostics for Instant Recipes (agent-friendly).
# Source: ~/Library/Logs/Scribe/diagnostics.jsonl (WS collector on :8767).
set -euo pipefail

log="${SCRIBE_DIAGNOSTICS_LOG:-$HOME/Library/Logs/Scribe/diagnostics.jsonl}"
filter="${1:-recipes}"

if ! curl -sf -m 1 http://127.0.0.1:8767/health >/dev/null; then
  print -u2 "Collector unhealthy at 127.0.0.1:8767 — run diagnostics-ws launch agent / tailscale serve."
fi

if [[ ! -f "$log" ]]; then
  print -u2 "Missing $log"
  exit 1
fi

python3 - "$log" "$filter" <<'PY'
import json, sys, re
path, filt = sys.argv[1], sys.argv[2].lower()
pat = re.compile(filt, re.I)
with open(path, errors="ignore") as f:
    # efficient-ish tail: last ~2MB
    f.seek(0, 2)
    size = f.tell()
    f.seek(max(0, size - 2_000_000))
    if size > 2_000_000:
        f.readline()
    for line in f:
        try:
            o = json.loads(line)
        except Exception:
            continue
        entry = o.get("entry") or o
        blob = json.dumps(entry, default=str)
        if not pat.search(blob):
            continue
        ts = entry.get("timestampMs")
        print(
            f"{ts}\t{entry.get('subsystem')}\t{entry.get('category')}\t"
            f"{entry.get('name')}\t{str(entry.get('message', ''))[:200]}"
        )
        meta = entry.get("metadata") or {}
        if meta:
            interesting = {k: meta[k] for k in meta if any(
                x in k.lower() for x in ("error", "provider", "client", "code", "app", "auth")
            )}
            if interesting:
                print("  meta:", interesting)
PY
