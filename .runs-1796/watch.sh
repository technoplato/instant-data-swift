#!/bin/bash
# Prints the job log's step lines as they arrive; returns after $1 minutes or when the job has ended.
log=/Users/laptop/Sync/worktrees/perf-sync-1796/.runs-1796/job.log
minutes=${1:-9}
for ((i=0; i<minutes*2; i++)); do
  if ! ps -p 40076 >/dev/null 2>&1; then echo "$(date +%H:%M) job ended"; grep -E '^== ' "$log" | tail -20; exit 0; fi
  sleep 30
done
echo "$(date +%H:%M) still running"; grep -E '^== ' "$log" | tail -12
