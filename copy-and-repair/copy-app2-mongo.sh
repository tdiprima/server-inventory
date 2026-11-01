#!/usr/bin/env bash
# Example: copy a server's MongoDB data directories to DEST_HOST:/data/app2/
#
# Edit SRC_DIRS, SRC_FILES, DEST_ROOT and LOG for your environment, then
# run ON the source server as root (or a user who can read every dbPath).
# Run inside tmux or screen: multi-TB copies take a day or more.
#
# Why raw folder copy, not mongodump: see copy-mongo-lib.sh. Repair happens
# later on the COPY with the mongod version that wrote each dbPath
# (check for mongod binaries in home dirs if the version is unknown).
#
# Usage: ./copy-app2-mongo.sh [-H host] [-d dest_root] [-l logfile] [src_dir ...]
#   src_dir  dbPath directories to copy. Default: the list below.
DEST_ROOT=/data/app2
LOG=/var/tmp/copy-app2-mongo.log

# Source dbPath directories (from mongod.conf storage.dbPath, or ps output),
# most important first. Put a small one first as a test of the pipeline.
SRC_DIRS=(
  /data/backup-small/data           # small, readable: do first as a test
  /data/main_project/data           # main DB, largest, unclean shutdown
  /data/home/USER/project/data      # per-user mongod
)

# Config: files that name the DBs and collections an app uses. Small, copy always.
SRC_FILES=( /etc/mongod.conf )
SRC_DIRS+=( /var/lib/docker/volumes/APP_VOLUME/_data/projects )

. "$(dirname "$0")/copy-mongo-lib.sh"
