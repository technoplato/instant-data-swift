#!/bin/bash
# Waits up to $1 minutes (at most 9: the tool's foreground limit is 10), one check a minute, for either 1796 job to
# start or end; prints one status line at the end.
lib=/Users/laptop/Sync/worktrees/perf-sync-1796/.runs-1796/job.log
app=/Users/laptop/Sync/worktrees/perf-sync-1796-app/.runs-1796/app-job.log
started() { grep -q '^== \|exit [0-9]' "$1" 2>/dev/null; }
for i in $(seq 1 "${1:-9}"); do
  sleep 60
  if started "$lib" || started "$app" || ! ps -p 1849 >/dev/null 2>&1 || ! ps -p 2456 >/dev/null 2>&1; then break; fi
done
bash /Users/laptop/Sync/worktrees/perf-sync-1796/.runs-1796/jobwatch.sh
