#!/usr/bin/env bash
# Example: copy a server's MongoDB data directories to DEST_HOST:/data/app1/
#
# Edit SRC_DIRS, SRC_FILES, DEST_ROOT and LOG for your environment, then
# run ON the source server as root (or a user who can read every dbPath).
# Run inside tmux or screen: multi-TB copies take many hours.
#
# Why raw folder copy, not mongodump: see copy-mongo-lib.sh. Repair happens
# later on the COPY with the mongod version that wrote each dbPath.
#
# Usage: ./copy-app1-mongo.sh [-H host] [-d dest_root] [-l logfile] [src_dir ...]
#   src_dir  dbPath directories to copy. Default: the list below.
DEST_ROOT=/data/app1
LOG=/var/tmp/copy-app1-mongo.log

# Source dbPath directories (from mongod.conf storage.dbPath, or ps output),
# most important first. One line per dbPath; note the mongod version for repair.
SRC_DIRS=(
  /data/db                          # main DB, mongod 3.2
  /data/secondary/data              # second mongod instance, mongod 3.4
  /data/home/USER/project/data      # per-user mongod, mongod 3.4
)
# Older copies. Add them with: INCLUDE_OLD=1 ./copy-app1-mongo.sh
if [[ "${INCLUDE_OLD:-0}" == 1 ]]; then
  SRC_DIRS+=( /data/db.old /data/secondary/data.old )
fi

# Config files that say how mongod was run. Small, copy always.
SRC_FILES=( /etc/mongod.conf )

. "$(dirname "$0")/copy-mongo-lib.sh"
