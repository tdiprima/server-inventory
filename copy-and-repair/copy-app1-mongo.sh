#!/usr/bin/env bash
# Copy App 1 MongoDB data directories to 192.0.2.10:/data/app1/
#
# Run ON app1 as root (or a user who can read /data/db etc.).
# Run inside tmux or screen: 1.9 TB + 657 GB takes many hours.
#
# Why raw folder copy, not mongodump: see copy-mongo-lib.sh. Repair happens
# later on the COPY with the matching mongod version (3.2.x for db,
# 3.4.x for tcga and til_maps).
#
# Usage: ./copy-app1-mongo.sh [-H host] [-d dest_root] [-l logfile] [src_dir ...]
#   src_dir  dbPath directories to copy. Default: the list below.
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

. "$(dirname "$0")/copy-mongo-lib.sh"
