#!/usr/bin/env bash
# Repair a copied MongoDB 3.x dbPath on the Ubuntu 24.04 destination box
# (192.0.2.10) using the matching legacy mongod in Docker, then start it
# read-only-ish on a local port so you can inspect with the legacy mongo shell.
#
# Usage:
#   ./repair-mongo-copy.sh [-r allowed_root] [-w workdir] <dbpath> <mongo-version> [port]
#   -r  only dbpaths under this prefix are accepted (default /data/app)
#   -w  repair workspace (default <dbpath>.repair-work). Must not exist yet.
# Examples:
#   ./repair-mongo-copy.sh /path/to/your/db              3.2 27018
#   ./repair-mongo-copy.sh /data/app1/data/data         3.4 27019
#   ./repair-mongo-copy.sh /data/app1/data/home/user02/tcga/data  3.4 27020
#   ./repair-mongo-copy.sh /data/app2/data/backup-registry/data      3.4 27021
#   ./repair-mongo-copy.sh /data/app2/data/registry_project/data     3.4 27022
#
# Version per folder (from the notes): db -> 3.2 (WiredTiger 2.7.1 files).
# tcga, til_maps, registry_project -> 3.4. If 3.4 refuses to open a folder, try 3.6.
# A newer mongod can open older files; an older one cannot. Never go up more
# than one major version from what wrote the files.
#
# Native install of mongod 3.x on Ubuntu 24.04 is not possible (needs libssl1.0),
# so we use the official mongo:3.x Docker images.
#
# IMPORTANT: <dbpath> is the preserved rsync copy and is NEVER modified.
# The script clones it into a workspace it owns (<dbpath>.repair-work),
# removes the stale lock and runs --repair there. The workspace carries a
# app.annotationser file (.repair-workspace) so it can never be mistaken for a preserved
# copy. Undo = delete the workspace; the preserved copy is untouched.
set -euo pipefail

ALLOWED_ROOT=/data/app
WORK=
while getopts 'r:w:' o; do
  case $o in
    r) ALLOWED_ROOT=$OPTARG ;;
    w) WORK=$OPTARG ;;
    *) echo "usage: $0 [-r allowed_root] [-w workdir] <dbpath> <mongo-version> [port]" >&2; exit 2 ;;
  esac
done
shift $((OPTIND-1))

DBPATH=${1:?dbpath}
VER=${2:?mongo version: 3.2 | 3.4 | 3.6}
PORT=${3:-27018}
DBPATH=${DBPATH%/}
WORK=${WORK:-$DBPATH.repair-work}
WORK=${WORK%/}
MARK=.repair-workspace
NAME=mongo-repair-$(basename "$(dirname "$DBPATH")")-$(basename "$DBPATH")-$VER
IMG=mongo:$VER
LOG=$WORK.log

[[ -d $DBPATH ]] || { echo "no such dir: $DBPATH" >&2; exit 1; }
[[ $DBPATH == "$ALLOWED_ROOT"* ]] || { echo "refusing: $DBPATH is not under $ALLOWED_ROOT*. Repair copies only." >&2; exit 1; }
[[ -e $DBPATH/$MARK ]] && { echo "refusing: $DBPATH is a repair workspace, not a preserved copy. Give the original copy as dbpath." >&2; exit 1; }
[[ $WORK != "$DBPATH" ]] || { echo "refusing: workdir equals dbpath" >&2; exit 1; }
if [[ -e $WORK ]]; then
  echo "refusing: workspace $WORK already exists. Undo: docker rm -f $NAME; rm -rf $WORK   (or pass -w otherdir)" >&2; exit 1
fi
command -v docker >/dev/null || { echo "docker not installed: sudo apt install docker.io" >&2; exit 1; }

# A previous run may still be serving a workspace under this name. Stop it
# before touching anything, never after.
docker rm -f "$NAME" "$NAME-repair" 2>/dev/null || true

# directoryPerDB: app1 db used it (per /etc/mongod.conf). Detect from layout:
# if the dbPath holds subdirectories containing .wt files, it is directoryPerDB.
DPD=()
if find "$DBPATH" -mindepth 2 -maxdepth 2 -name '*.wt' -print -quit | grep -q .; then
  DPD=(--directoryperdb)
fi

# Clone the preserved copy into the workspace. Copy into .partial and rename
# only on success, so an interrupted clone is never mistaken for a complete one.
echo "clone $DBPATH -> $WORK (needs as much free space as the dbPath)"
rsync -a --sparse "$DBPATH/" "$WORK.partial/"
echo "$DBPATH" > "$WORK.partial/$MARK"
mv "$WORK.partial" "$WORK"
chown --reference="$DBPATH" "$WORK" "$WORK/$MARK"

# mongod.lock left over from the unclean shutdown blocks startup. Remove it in the workspace only.
rm -f "$WORK/mongod.lock"

docker pull "$IMG"

echo "=== repair ($IMG, ${DPD[*]:-single dir})" | tee -a "$LOG"
# --repair runs to completion and exits. Runs as the uid that owns the files
# so no permission churn. Journal replay happens here too.
docker run --rm --name "$NAME-repair" \
  --user "$(stat -c %u:%g "$WORK")" \
  -v "$WORK":/data/db \
  "$IMG" mongod --dbpath /data/db "${DPD[@]}" --repair 2>&1 | tee -a "$LOG"

echo "=== start on 127.0.0.1:$PORT" | tee -a "$LOG"
docker run -d --name "$NAME" \
  --user "$(stat -c %u:%g "$WORK")" \
  -p 127.0.0.1:"$PORT":27017 \
  -v "$WORK":/data/db \
  "$IMG" mongod --dbpath /data/db "${DPD[@]}" --bind_ip 0.0.0.0  # --bind_ip_all needs 3.6+

sleep 5
echo "=== databases" | tee -a "$LOG"
docker exec "$NAME" mongo --quiet --eval 'db.adminCommand({listDatabases:1}).databases.forEach(function(d){print(d.name, (d.sizeOnDisk/1e9).toFixed(1)+" GB")})' | tee -a "$LOG"

cat <<MSG

Running: $NAME  (mongod $VER)  port 127.0.0.1:$PORT
Data:    $WORK  (repaired workspace; preserved copy $DBPATH untouched)
Shell:   docker exec -it $NAME mongo
Dump:    docker exec $NAME mongodump --db <name> --archive --gzip > <name>.archive.gz
Stop:    docker rm -f $NAME
Undo:    docker rm -f $NAME; rm -rf $WORK
Log:     $LOG
MSG
