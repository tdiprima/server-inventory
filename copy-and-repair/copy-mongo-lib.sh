#!/usr/bin/env bash
# Shared copy workflow. Sourced by copy-app*-mongo.sh after the wrapper sets:
#   DEST_ROOT  destination directory on $DEST_HOST
#   LOG        rsync log file
#   SRC_DIRS   dbPath directories to copy (array)
#   SRC_FILES  small config files to copy (array)
# Wrapper may also preset DEST_HOST. Options and positional args are parsed here.
#
# Why raw folder copy, not mongodump:
#   mongod is stopped and the last shutdowns were unclean. Starting mongod
#   on the originals would replay the journal and rewrite files. A raw
#   copy of the whole dbPath (WiredTiger files + journal/ together) is the
#   only way to preserve the exact on-disk state. Repair / mongodump happens
#   later on the COPY with the matching mongod version.
#
# rsync is resumable: re-run the script after an interruption and it picks up.
set -euo pipefail

DEST_HOST=${DEST_HOST:-192.0.2.10}
DEST_USER=${DEST_USER:-root}
: "${DEST_ROOT:?wrapper must set DEST_ROOT}" "${LOG:?wrapper must set LOG}"
while getopts 'H:d:l:' o; do
  case $o in
    H) DEST_HOST=$OPTARG ;;
    d) DEST_ROOT=$OPTARG ;;
    l) LOG=$OPTARG ;;
    *) echo "usage: $0 [-H host] [-d dest_root] [-l logfile] [src_dir ...]" >&2; exit 2 ;;
  esac
done
shift $((OPTIND-1))
# Positional args replace the default list.
[[ $# -gt 0 ]] && SRC_DIRS=("$@")

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
