#!/usr/bin/env bash
# App discovery 02: find MongoDB WITHOUT connecting or starting it.
# Finds binaries, versions, config, data folders, database names (from file names), port, auth.
# SPEED: FAST (1-3 minutes). SAFETY: GREEN, read-only. Never starts mongod.
# Usage: sudo bash 02_mongo_probe.sh

if [ -z "$NO_COLOR" ]; then R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1;34m'; C=$'\e[36m'; N=$'\e[0m'; fi
hdr()  { printf '\n%s===== %s =====%s\n' "$B" "$*" "$N"; }
ok()   { printf '%s[FOUND]%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s[NOTE]%s %s\n' "$Y" "$N" "$*"; }
miss() { printf '%s[NONE]%s %s\n' "$R" "$N" "$*"; }
T=""; command -v timeout >/dev/null && T="timeout 60"
# hide passwords before printing
mask() { sed -r -e 's#(mongodb://[^:/@ ]*:)[^@ ]*@#\1****@#g' \
  -e "s/((pass(word|wd)?|pwd|secret|token|api_?key|keyfile)[\"' ]*[=:>,]+[[:space:]]*[\"']?)[^\"' ,;)]+/\1****/Ig"; }

[ "$(id -u)" -ne 0 ] && warn "Not root. Data folders may be unreadable. Re-run with sudo."
ROOTS="/opt /usr/local /usr/bin /home /srv /data /var/lib /root /mnt /export /scratch"

hdr "1. MongoDB programs (PATH and common install folders)"
BINS=$( { command -v mongod mongo mongosh mongodump 2>/dev/null
  $T find $ROOTS -maxdepth 5 -type f \( -name mongod -o -name mongo -o -name mongosh -o -name mongodump \) 2>/dev/null; } | sort -u)
if [ -n "$BINS" ]; then
  for b in $BINS; do ok "$b  ->  $($T "$b" --version 2>&1 | head -1)"; done
else miss "no MongoDB programs found"; fi
warn "Legacy 'mongo' shell must roughly match server version. 'mongosh' only works with MongoDB 4.2+ (approx)."

hdr "2. Is mongod running right now?"
P=$(ps -C mongod -o pid,user,etime,args --no-headers)  # match process name only, not args of other commands
if [ -n "$P" ]; then ok "mongod running:"; echo "$P" | mask | cut -c1-250
else miss "mongod NOT running. Do not start it. Report back first."; fi

hdr "3. Ports"
(ss -ltnp 2>/dev/null || netstat -ltnp 2>/dev/null) | grep -E 'mongo|:2701[0-9]|:28017' || miss "nothing listening on MongoDB ports"

hdr "4. Config files"
CONFS=$( { ls /etc/mongod.conf /etc/mongodb.conf /etc/mongo*.conf 2>/dev/null
  echo "$P" | grep -o -E '(--config|-f) +[^ ]+' | awk '{print $2}'
  $T find $ROOTS -maxdepth 5 -type f -name 'mongo*.conf' 2>/dev/null; } | sort -u)
for f in $CONFS; do
  [ -f "$f" ] || continue
  ok "config: $f"
  grep -v -E '^[[:space:]]*(#|$)' "$f" | mask | head -40
done
[ -z "$CONFS" ] && miss "no mongo config file found"

hdr "5. Auth enabled?"
if grep -h -i -E '^[^#]*(auth *= *true|authorization *: *enabled|keyFile)' $CONFS 2>/dev/null | mask | grep . \
   || echo "$P" | grep -q -- '--auth'; then
  warn "Authentication looks ENABLED. You will need a username/password for script 06."
else ok "no auth setting found (default for old MongoDB = no password)"; fi

hdr "6. Data folders (dbpath)"
DBP=$( { grep -h -i -E '^[^#]*dbpath' $CONFS 2>/dev/null | sed -r 's/.*dbpath *[:=] *//I; s/["'\'' ]//g'
  echo "$P" | grep -o -E -- '--dbpath[= ]+[^ ]+' | sed -r 's/--dbpath[= ]+//'
  ls -d /var/lib/mongodb /var/lib/mongo /data/db 2>/dev/null
  $T find $ROOTS -maxdepth 6 \( -name mongod.lock -o -name WiredTiger -o -name 'storage.bson' \) 2>/dev/null | xargs -r -n1 dirname; } | sort -u)
[ -z "$DBP" ] && miss "no MongoDB data folder found in common places (script 04 searches everywhere)"
for d in $DBP; do
  [ -d "$d" ] || continue
  hdr "dbpath: $d"
  ok "size on disk: $($T du -sh "$d" 2>/dev/null | cut -f1)"
  ls -la "$d" | head -15
  NS=$(ls "$d" 2>/dev/null | grep -E '\.ns$')
  if [ -n "$NS" ]; then
    ok "Storage engine: MMAPv1 (old, MongoDB 3.x or earlier). Database names come from *.ns files:"
    for n in $NS; do db=${n%.ns}; printf '   %s%-30s%s %s\n' "$G" "$db" "$N" "$(du -ch "$d/$db".[0-9]* 2>/dev/null | tail -1 | cut -f1)"; done
  fi
  if [ -e "$d/WiredTiger" ]; then
    ok "Storage engine: WiredTiger (MongoDB 3.0+). Names need a connection (script 06)."
    echo "   collection files: $(ls "$d" | grep -c '^collection-')   index files: $(ls "$d" | grep -c '^index-')"
    ls "$d" | grep -E '^[a-z]' | grep -v -E '^(collection|index)-' | head -20 | sed 's/^/   /'
    echo "   largest collection files:"; ls -lS "$d"/collection-* 2>/dev/null | head -10 | awk '{print "   ", $5, $NF}'
  fi
  [ -s "$d/mongod.lock" ] && warn "mongod.lock is not empty: mongod is running OR shut down uncleanly last time."
done

hdr "7. MongoDB logs (version and dbpath at startup)"
for l in /var/log/mongodb/*.log /var/log/mongo/*.log; do
  [ -f "$l" ] || continue
  ok "$l ($(du -h "$l" | cut -f1))"
  $T grep -h -m 5 -E 'db version|dbpath|git version|options:' "$l" | mask | cut -c1-250
  echo "   last lines:"; tail -n 5 "$l" | mask | cut -c1-250
done

hdr "8. Remote MongoDB? (hosts named in configs)"
warn "Script 03 greps app code for mongodb:// hosts. A host that is not localhost/127.0.0.1 means the DB is on another machine."

printf '\n%sDone. Next: script 03 (caMicroscope).%s\n' "$G" "$N"
