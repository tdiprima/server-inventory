#!/usr/bin/env bash
# Repair a copied MongoDB 3.x dbPath on the Ubuntu 24.04 destination box
# (192.0.2.10) using the matching legacy mongod in Docker, then start it
# read-only-ish on a local port so you can inspect with the legacy mongo shell.
#
# Usage:
#   ./repair-mongo-copy.sh <dbpath> <mongo-version> [port]
# Examples:
#   ./repair-mongo-copy.sh /path/to/your/db              3.2 27018
#   ./repair-mongo-copy.sh /data/app1/data/data         3.4 27019
#   ./repair-mongo-copy.sh /data/app1/data/home/user02/tcga/data  3.4 27020
#   ./repair-mongo-copy.sh /data/app3/data/backup-registry/data      3.4 27021
#   ./repair-mongo-copy.sh /data/app3/data/registry_project/data     3.4 27022
#
# Version per folder (from the notes): db -> 3.2 (WiredTiger 2.7.1 files).
# tcga, til_maps, registry_project -> 3.4. If 3.4 refuses to open a folder, try 3.6.
# A newer mongod can open older files; an older one cannot. Never go up more
# than one major version from what wrote the files.
#
# Native install of mongod 3.x on Ubuntu 24.04 is not possible (needs libssl1.0),
# so we use the official mongo:3.x Docker images.
#
# IMPORTANT: run this only on the COPY. --repair rewrites files in place.
# The script snapshots the copy first (hardlink-free rsync) so repair is
# reversible: <dbpath>.pre-repair
set -euo pipefail

DBPATH=${1:?dbpath}
VER=${2:?mongo version: 3.2 | 3.4 | 3.6}
PORT=${3:-27018}
NAME=mongo-repair-$(basename "$(dirname "$DBPATH")")-$(basename "$DBPATH")-$VER
IMG=mongo:$VER
LOG=$DBPATH.repair.log

[[ -d $DBPATH ]] || { echo "no such dir: $DBPATH" >&2; exit 1; }
[[ $DBPATH == /data/app* ]] || { echo "refusing: $DBPATH is not under /data/app*. Repair copies only." >&2; exit 1; }
command -v docker >/dev/null || { echo "docker not installed: sudo apt install docker.io" >&2; exit 1; }

# directoryPerDB: app1 db used it (per /etc/mongod.conf). Detect from layout:
# if the dbPath holds subdirectories containing .wt files, it is directoryPerDB.
DPD=()
if find "$DBPATH" -mindepth 2 -maxdepth 2 -name '*.wt' -print -quit | grep -q .; then
  DPD=(--directoryperdb)
fi

# mongod.lock left over from the unclean shutdown blocks startup. Remove it on the copy.
rm -f "$DBPATH/mongod.lock"

# One-time safety snapshot so a failed repair can be undone.
if [[ ! -d $DBPATH.pre-repair ]]; then
  echo "snapshot -> $DBPATH.pre-repair (needs as much free space as the dbPath)"
  rsync -a --sparse "$DBPATH/" "$DBPATH.pre-repair/"
fi

docker pull "$IMG"

echo "=== repair ($IMG, ${DPD[*]:-single dir})" | tee -a "$LOG"
# --repair runs to completion and exits. Runs as the uid that owns the files
# so no permission churn. Journal replay happens here too.
docker run --rm --name "$NAME-repair" \
  --user "$(stat -c %u:%g "$DBPATH")" \
  -v "$DBPATH":/data/db \
  "$IMG" mongod --dbpath /data/db "${DPD[@]}" --repair 2>&1 | tee -a "$LOG"

echo "=== start on 127.0.0.1:$PORT" | tee -a "$LOG"
docker rm -f "$NAME" 2>/dev/null || true
docker run -d --name "$NAME" \
  --user "$(stat -c %u:%g "$DBPATH")" \
  -p 127.0.0.1:"$PORT":27017 \
  -v "$DBPATH":/data/db \
  "$IMG" mongod --dbpath /data/db "${DPD[@]}" --bind_ip_all

sleep 5
echo "=== databases" | tee -a "$LOG"
docker exec "$NAME" mongo --quiet --eval 'db.adminCommand({listDatabases:1}).databases.forEach(function(d){print(d.name, (d.sizeOnDisk/1e9).toFixed(1)+" GB")})' | tee -a "$LOG"

cat <<MSG

Running: $NAME  (mongod $VER)  port 127.0.0.1:$PORT
Shell:   docker exec -it $NAME mongo
Dump:    docker exec $NAME mongodump --db <name> --archive --gzip > <name>.archive.gz
Stop:    docker rm -f $NAME
Undo:    docker rm -f $NAME; rm -rf $DBPATH; mv $DBPATH.pre-repair $DBPATH
Log:     $LOG
MSG
