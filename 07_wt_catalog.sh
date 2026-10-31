#!/usr/bin/env bash
# App discovery 07: list database.collection names and sizes from MongoDB WiredTiger data folders
# WITHOUT starting MongoDB. Reads only the small _mdb_catalog.wt file plus file sizes.
# SPEED: FAST (seconds). SAFETY: GREEN, read-only. Do not run while mongod is using the folder.
# Usage: sudo bash 07_wt_catalog.sh                 -> every folder 'locate' knows with a WiredTiger file
#        sudo bash 07_wt_catalog.sh /path/to/dbdir  -> just these folders
# Names are pulled from raw bytes: treat as PROBABLE until confirmed with a running copy.

if [ -z "$NO_COLOR" ]; then R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1;34m'; C=$'\e[36m'; N=$'\e[0m'; fi
export LC_ALL=C  # tr must treat files as raw bytes
hdr()  { printf '\n%s===== %s =====%s\n' "$B" "$*" "$N"; }
warn() { printf '%s[NOTE]%s %s\n' "$Y" "$N" "$*"; }

if [ $# -gt 0 ]; then DIRS="$*"; else DIRS=$(locate -r '/WiredTiger$' 2>/dev/null | xargs -r -n1 dirname | sort -u); fi
[ -z "$DIRS" ] && { echo "${R}No WiredTiger folders found.${N}"; exit 0; }

for d in $DIRS; do
  hdr "$d"
  [ -f "$d/_mdb_catalog.wt" ] || { warn "no _mdb_catalog.wt here; not a MongoDB data folder"; continue; }
  printf 'Total size:     %s\n' "$(du -sh "$d" 2>/dev/null | cut -f1)"
  printf 'Engine version: %s\n' "$(sed -n 2p "$d/WiredTiger" 2>/dev/null)"
  printf 'Last modified:  %s\n' "$(ls -lt --time-style=+%F "$d" | awk 'NR==2{print $6, $7}')"
  printf 'Owner:          %s\n' "$(stat -c %U "$d")"
  if [ -s "$d/mongod.lock" ]; then warn "mongod.lock not empty: running now, or last shutdown was unclean"; fi
  # catalog record order is md.ns ... ns, ident: remember last db.coll name, pair it with the next collection ident
  tr -c '[:print:]' '\n' < "$d/_mdb_catalog.wt" | awk '
    /^[A-Za-z0-9_-]+\.[A-Za-z0-9_.$ -]+$/ && $0 !~ /\.wt$/ { ns = $0; next }
    /(^|\/)collection-[0-9]+-[0-9-]+$/ { if (ns != "" && !seen[$0]++) print ns "\t" $0; ns = "" }' |
  while IFS="$(printf '\t')" read -r ns ident; do
    printf '%s\t%s\n' "$(stat -c %s "$d/$ident.wt" 2>/dev/null || echo 0)" "$ns"
  done | sort -t "$(printf '\t')" -k1,1nr | awk -F'\t' -v G="$G" -v Y="$Y" -v C="$C" -v N="$N" '
    function human(b) { if (b>=1073741824) return sprintf("%.1f GB", b/1073741824)
      if (b>=1048576) return sprintf("%.1f MB", b/1048576); return sprintf("%.0f KB", b/1024) }
    BEGIN { printf "%10s  %s\n", "SIZE", "DATABASE.COLLECTION" }
    { split($2, p, "."); db = p[1]; col = substr($2, length(db) + 2)
      if (db == "local" || db == "admin" || db == "config") next
      hl = (tolower(col) ~ /til|lym|tumor|heat|annot|app.annotations|object|metadata|image|slide|execution|segment|collection/) ? Y : G
      printf "%10s  %s%s.%s%s%s\n", human($1), C, db, hl, col, N; n++; t += $1 }
    END { printf "%s%d collections, %s (compressed on disk; real data is bigger)%s\n", G, n, human(t), N }'
  # catalog is compressed, so names can be missing; raw file sizes are always true
  printf '%sAll collection files: %s, total %s. Biggest 10 (names unknown if missing above):%s\n' "$C" \
    "$(find "$d" -name 'collection-*.wt' | wc -l)" \
    "$(find "$d" -name 'collection-*.wt' -printf '%s\n' | awk '{t+=$1} END {printf "%.1f GB", t/1073741824}')" "$N"
  find "$d" -name 'collection-*.wt' -printf '%s\t%p\n' | sort -k1,1nr | head -10 |
    awk -F'\t' '{printf "%10.1f GB  %s\n", $1/1073741824, $2}'
  printf '%sSub-folders:%s\n' "$C" "$N"
  for s in "$d"/*/; do
    big=$(ls -S "$s" 2>/dev/null | head -1)
    printf '%10s  %4s colls  %s%s%s  biggest: %s (%s)\n' "$(du -sh "$s" 2>/dev/null | cut -f1)" \
      "$(ls "$s" | grep -c '^collection-')" "$G" "$(basename "$s")" "$N" "$big" "$(du -h "$s/$big" 2>/dev/null | cut -f1)"
  done
  printf '%sCatalog file: %s%s\n' "$C" "$(ls -l "$d/_mdb_catalog.wt" | awk '{print $5}') bytes" "$N"
done
warn "Sizes are on-disk WiredTiger files (compressed). Doc counts need a running copy (script 06)."
