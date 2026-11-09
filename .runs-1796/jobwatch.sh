#!/bin/bash
# Prints one line per poll: each 1796 job's state (queued / running / finished with exit) and its log tail marker.
lib=/Users/laptop/Sync/worktrees/perf-sync-1796/.runs-1796/job.log
app=/Users/laptop/Sync/worktrees/perf-sync-1796-app/.runs-1796/app-job.log
state() { # pid log
  if ps -p "$1" >/dev/null 2>&1; then
    if [ -s "$2" ]; then echo "running($(grep -c '^== ' "$2") steps; last: $(grep '^== ' "$2" | tail -1 | cut -c1-60))"; else echo queued; fi
  else echo "ended($(tail -c 300 "$2" | tr '\n' ' ' | cut -c1-120))"; fi
}
echo "$(date +%H:%M) lib=$(state 1849 $lib) app=$(state 2456 $app)"
