#!/bin/bash
# Polls the build job list every 60 s for up to $1 minutes; returns early when 1796-check2 or 1796-app-check2 leaves "queued".
minutes=${1:-9}
for ((i=0; i<minutes; i++)); do
  line=$(python3 /Users/laptop/Sync/tools/safe-heavy/build_jobs.py list 2>/dev/null | grep -E " 1796-(app-)?check2 " )
  running=$(python3 /Users/laptop/Sync/tools/safe-heavy/build_jobs.py list 2>/dev/null | grep running | cut -c1-110)
  echo "$(date +%H:%M) $(echo "$line" | tr -s ' ' | cut -c1-200 | tr '\n' ';') | now: $running"
  if echo "$line" | grep -q -v queued; then exit 0; fi
  sleep 60
done
