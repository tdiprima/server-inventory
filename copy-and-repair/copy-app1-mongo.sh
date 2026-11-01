#!/usr/bin/env bash
# Copy App 1 MongoDB data directories to 192.0.2.10:/data/app1/
#
# Run ON app1 as root (or a user who can read /data/db etc.).
# Run inside tmux or screen: 1.9 TB + 657 GB takes many hours.
#
# Why raw folder copy, not mongodump:
#   mongod is stopped and the last shutdowns were unclean. Starting mongod
#   3.2 on the originals would replay the journal and rewrite files. A raw
#   copy of the whole dbPath (WiredTiger files + journal/ together) is the
#   only way to preserve the exact on-disk state. Repair / mongodump happens
#   later on the COPY with the matching mongod version (3.2.x for db,
#   3.4.x for tcga and til_maps).
#
# rsync is resumable: re-run the script after an interruption and it picks up.
set -euo pipefail

DEST_HOST=192.0.2.10
DEST_USER=${DEST_USER:-root}
DEST_ROOT=/data/app1
LOG=/var/tmp/copy-app1-mongo.log

# Source dbPath directories (from the data-location notes), most important first.
SRC_DIRS=(
  /data/db                 # 1.9 TB  main  DB , mongod 3.2
  /data/data            # 23 GB    maps DB, mongod 3.4, unclean shutdown
  /data/home/user02/tcga/data     # 657 GB  app.app.objects etc., mongod 3.4, unclean shutdown
)
# Older copies. Add them with: INCLUDE_OLD=1 ./copy-app1-mongo.sh
if [[ "${INCLUDE_OLD:-0}" == 1 ]]; then
  SRC_DIRS+=( /data/db.old /data/data.old )
fi

# Config files that say how mongod was run. Small, copy always.
SRC_FILES=( /etc/mongod.conf )

# Safety: never copy a dbPath while mongod is running on it.
if pgrep -x mongod >/dev/null; then
  echo "mongod is running. Stop it cleanly first, then re-run." >&2
  exit 1
fi

ssh "$DEST_USER@$DEST_HOST" "mkdir -p $DEST_ROOT && df -h $DEST_ROOT"

RSYNC=(ionice -c3 nice -n 19 rsync -aH --sparse --partial --info=progress2
       --log-file="$LOG" -e "ssh -o ServerAliveInterval=60")

for d in "${SRC_DIRS[@]}"; do
  [[ -d $d ]] || { echo "skip, missing: $d" | tee -a "$LOG"; continue; }
  echo "=== $d" | tee -a "$LOG"
  # Trailing slash on source: contents of $d land in $DEST_ROOT$d (path mirrored).
  "${RSYNC[@]}" --rsync-path="mkdir -p '$DEST_ROOT$d' && rsync" "$d/" "$DEST_USER@$DEST_HOST:$DEST_ROOT$d/"
done

for f in "${SRC_FILES[@]}"; do
  [[ -f $f ]] && "${RSYNC[@]}" --rsync-path="mkdir -p '$DEST_ROOT$(dirname "$f")' && rsync" "$f" "$DEST_USER@$DEST_HOST:$DEST_ROOT$f"
done

# Verify: a second dry-run pass must list zero files to transfer.
echo "=== verify" | tee -a "$LOG"
fail=0
for d in "${SRC_DIRS[@]}"; do
  [[ -d $d ]] || continue
  if ! out=$(rsync -aHn --sparse --out-format='%n' "$d/" "$DEST_USER@$DEST_HOST:$DEST_ROOT$d/"); then
    echo "$d: verify rsync FAILED" | tee -a "$LOG"; fail=1; continue
  fi
  n=$(grep -vc '/$' <<<"$out" || true)
  echo "$d: $n files differ" | tee -a "$LOG"
  [[ $n -eq 0 ]] || fail=1
done
if [[ $fail -ne 0 ]]; then echo "VERIFY FAILED. log: $LOG" | tee -a "$LOG"; exit 1; fi
echo "done. log: $LOG"
