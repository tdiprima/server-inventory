#!/usr/bin/env bash
# Copy App 3 MongoDB data directories to 192.0.2.10:/data/app2/
#
# Run ON app2 as root (or a user who can read /data/registry_project etc.).
# Run inside tmux or screen: 6.1 TB takes a day or more.
#
# Why raw folder copy, not mongodump: see copy-mongo-lib.sh. Repair happens
# later on the COPY with the matching mongod version (3.4.x era for
# registry_project; binaries 3.2.4 / 3.4.4 / 3.6.5 exist in home dirs).
#
# Usage: ./copy-app2-mongo.sh [-H host] [-d dest_root] [-l logfile] [src_dir ...]
#   src_dir  dbPath directories to copy. Default: the list below.
DEST_ROOT=/data/app2
LOG=/var/tmp/copy-app2-mongo.log

# Source dbPath directories (from the data-location notes), most important first.
SRC_DIRS=(
  /data/backup-registry/data         # 6 GB    small, readable catalog, do first as a test
  /data/registry_project/data        # 6.1 TB  main registry DB (app, app_comp), unclean shutdown
  /data/home/user07/app1/data    # 32 GB   app.*, registry.images, camicWebapp.*
)

# Config:  data-API project files name the DBs and collections. Small, copy always.
SRC_FILES=( /etc/mongod.conf )
SRC_DIRS+=( /data/home/docker/volumes/_data/bin/projects )

. "$(dirname "$0")/copy-mongo-lib.sh"
