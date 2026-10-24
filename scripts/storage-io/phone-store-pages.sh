#!/bin/bash
# #1076: the pages one logical write dirties on a real store, measured as write-ahead-log frames (each frame is one
# 4 KiB page plus a 24-byte header; a page dirtied twice in one transaction is written once). One sqlite3 session, so
# the log is not checkpointed away when a connection closes; `.shell stat` reads the log's size after each write.
# usage: phone-store-pages.sh <copy of a store> <scratch dir>   (never the original: it rewrites its scratch copy)
set -euo pipefail
src=$1; dir=$2
mkdir -p "$dir"
db="$dir/exp.sqlite"
rm -f "$db" "$db-wal" "$db-shm"
cp "$src" "$db"
chmod 600 "$db"
cd "$dir"

seg=$(sqlite3 exp.sqlite "SELECT entity_id FROM instant_triples WHERE attribute_id='transcriptionSegments/id' ORDER BY rowid LIMIT 1 OFFSET 3000")
mid=$(sqlite3 exp.sqlite "SELECT mutation_id FROM instant_outbox WHERE length(json) BETWEEN 18000 AND 26000 ORDER BY rowid LIMIT 1")
qid=$(sqlite3 exp.sqlite "SELECT query_id FROM instant_live_query_results ORDER BY length(json) DESC LIMIT 1 OFFSET 8")
tx() { uuidgen | tr A-Z a-z; }

mark() { printf '.shell printf "%s "; stat -f %%z exp.sqlite-wal\nPRAGMA wal_checkpoint(TRUNCATE);\n' "$1"; }

{
  echo "PRAGMA journal_mode=WAL;"
  echo "PRAGMA wal_autocheckpoint=0;"
  echo "PRAGMA cache_size=-2048;"
  echo "CREATE TEMP TABLE seg AS SELECT * FROM instant_triples WHERE entity_id='$seg';"
  echo ".print segmentFacts"
  echo "SELECT count(*) FROM temp.seg;"
  echo "PRAGMA wal_checkpoint(TRUNCATE);"
  # E1: one line re-saved as the store saves it today: the deferred text and words deleted, then every fact
  # INSERT OR REPLACE'd with the write's new transaction id and time.
  for i in 1 2 3; do
    t=$(tx)
    echo "BEGIN;"
    echo "DELETE FROM instant_triples WHERE entity_id='$seg' AND attribute_id IN ('transcriptionSegments/text','transcriptionSegments/wordsJSON');"
    echo "INSERT OR REPLACE INTO instant_triples (entity_id, attribute_id, value_json, tx_id, tx_time_ms, json) SELECT entity_id, attribute_id, value_json, '$t', tx_time_ms + $i, replace(json, tx_id, '$t') FROM temp.seg;"
    echo "COMMIT;"
    mark "e1-replace-$i"
  done
  # E1b: the same write as an in-place upsert: the row keeps its rowid and its index entry.
  for i in 1 2 3; do
    t=$(tx)
    echo "BEGIN;"
    echo "INSERT INTO instant_triples (entity_id, attribute_id, value_json, tx_id, tx_time_ms, json) SELECT entity_id, attribute_id, value_json, '$t', tx_time_ms + 10 + $i, replace(json, tx_id, '$t') FROM temp.seg WHERE true ON CONFLICT (entity_id, attribute_id, value_json) DO UPDATE SET tx_id = excluded.tx_id, tx_time_ms = excluded.tx_time_ms, json = excluded.json;"
    echo "COMMIT;"
    mark "e1-upsert-$i"
  done
  # E1c: only what changed: nothing (the values are the same), so no statement at all.
  # E2: one small column of an outbox row whose json spills to overflow pages.
  echo "BEGIN; UPDATE instant_outbox SET delivery_claim_state='claimed', delivery_claim_token='storage-io-claim-token-0001', delivery_claimant_id='storage-io-claimant', delivery_claim_deadline_ms=1792900000000 WHERE mutation_id='$mid'; COMMIT;"
  mark "e2-outbox-claim"
  echo "BEGIN; UPDATE instant_outbox SET delivery_claim_state='ready', delivery_claim_token=NULL, delivery_claimant_id=NULL, delivery_claim_deadline_ms=NULL WHERE mutation_id='$mid'; COMMIT;"
  mark "e2-outbox-release"
  echo "BEGIN; UPDATE instant_outbox SET delivery_metadata_version = delivery_metadata_version + 1 WHERE mutation_id='$mid'; COMMIT;"
  mark "e2-outbox-same-size"
  # E3: one live query result's JSON rewritten (one byte longer), and only its time changed.
  echo "BEGIN; UPDATE instant_live_query_results SET json = json || ' ', updated_at_ms = updated_at_ms + 1 WHERE query_id=$qid; COMMIT;"
  mark "e3-result-json"
  echo "BEGIN; UPDATE instant_live_query_results SET updated_at_ms = updated_at_ms + 1 WHERE query_id=$qid; COMMIT;"
  mark "e3-result-time-only"
  # E4: the fact table in other layouts, built from the phone's own rows in insertion order.
  echo "CREATE TABLE layout_today (entity_id TEXT NOT NULL, attribute_id TEXT NOT NULL, value_json TEXT NOT NULL, tx_id TEXT NOT NULL, tx_time_ms INTEGER NOT NULL, json TEXT NOT NULL, PRIMARY KEY (entity_id, attribute_id, value_json));"
  echo "INSERT INTO layout_today SELECT entity_id, attribute_id, value_json, tx_id, tx_time_ms, json FROM instant_triples ORDER BY rowid;"
  echo "CREATE TABLE layout_no_json (entity_id TEXT NOT NULL, attribute_id TEXT NOT NULL, value_json TEXT NOT NULL, tx_id TEXT NOT NULL, tx_time_ms INTEGER NOT NULL, PRIMARY KEY (entity_id, attribute_id, value_json));"
  echo "INSERT INTO layout_no_json SELECT entity_id, attribute_id, value_json, tx_id, tx_time_ms FROM instant_triples ORDER BY rowid;"
  echo "CREATE TABLE layout_no_json_without_rowid (entity_id TEXT NOT NULL, attribute_id TEXT NOT NULL, value_json TEXT NOT NULL, tx_id TEXT NOT NULL, tx_time_ms INTEGER NOT NULL, PRIMARY KEY (entity_id, attribute_id, value_json)) WITHOUT ROWID;"
  echo "INSERT INTO layout_no_json_without_rowid SELECT entity_id, attribute_id, value_json, tx_id, tx_time_ms FROM instant_triples ORDER BY rowid;"
  echo "PRAGMA wal_checkpoint(TRUNCATE);"
  # E5: one line re-saved into each layout, as today (replace) and in place (upsert).
  for t in layout_today layout_no_json layout_no_json_without_rowid; do
    for mode in replace upsert; do
      x=$(tx)
      if [ "$t" = layout_today ]; then
        cols="entity_id, attribute_id, value_json, tx_id, tx_time_ms, json"; sel="entity_id, attribute_id, value_json, '$x', tx_time_ms + 100, replace(json, tx_id, '$x')"; extra=", json = excluded.json"
      else
        cols="entity_id, attribute_id, value_json, tx_id, tx_time_ms"; sel="entity_id, attribute_id, value_json, '$x', tx_time_ms + 100"; extra=""
      fi
      echo "BEGIN;"
      if [ "$mode" = replace ]; then
        echo "INSERT OR REPLACE INTO $t ($cols) SELECT $sel FROM temp.seg;"
      else
        echo "INSERT INTO $t ($cols) SELECT $sel FROM temp.seg WHERE true ON CONFLICT (entity_id, attribute_id, value_json) DO UPDATE SET tx_id = excluded.tx_id, tx_time_ms = excluded.tx_time_ms$extra;"
      fi
      echo "COMMIT;"
      mark "e5-$mode-$t"
    done
  done
  echo "SELECT name, count(*), round(sum(pgsize)/1048576.0, 1), round(sum(unused)*100.0/sum(pgsize), 1) FROM dbstat WHERE name LIKE '%layout_%' GROUP BY name ORDER BY name;"
  echo ".print outboxRowBytes"
  echo "SELECT length(json) FROM instant_outbox WHERE mutation_id='$mid';"
  echo ".print resultJSONBytes"
  echo "SELECT length(json) FROM instant_live_query_results WHERE query_id=$qid;"
} > script.sql

sqlite3 -batch exp.sqlite < script.sql | awk -F'|' '
  /^e[0-9]/ { split($0, part, " "); size = part[2]; frames = (size > 32) ? int((size - 32) / 4120) : 0
              printf "PHONEPAGES %s walBytes=%d frames=%d\n", part[1], size, frames; next }
  /^0\|0\|0$/ || /^wal$/ { next }
  NF == 4 { printf "PHONEPAGES layout btree=%s pages=%s mb=%s unusedPct=%s\n", $1, $2, $3, $4; next }
  /^(segmentFacts|layouts|outboxRowBytes|resultJSONBytes)$/ { label = $0; next }
  label != "" && NF == 1 { printf "PHONEPAGES %s value=%s\n", label, $1; label = ""; next }
  { print "PHONEPAGES other " $0 }'
rm -f exp.sqlite exp.sqlite-wal exp.sqlite-shm script.sql
echo "PHONEPAGES done"
