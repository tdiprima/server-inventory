#!/usr/bin/env bash
# App discovery 05: classify annotation/result files by peeking at their first 2 KB.
# ImageScope (Aperio XML), caMicroscope/App JSON, GeoJSON, /tumor/segmentation CSVs.
# Also matches each ImageScope XML to a .svs slide with the same base name.
# SPEED: MEDIUM to SLOW. Walks the folders you give it, reads 2 KB of at most MAX files (default 20000).
#        Rough guide: 5-30 minutes. Give it the data folders found by script 04, not '/'.
# SAFETY: YELLOW. Read-only.
# Usage: sudo bash 05_annotation_probe.sh /data /home      (MAX=50000 to check more files)

if [ -z "$NO_COLOR" ]; then R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1;34m'; C=$'\e[36m'; N=$'\e[0m'; fi
warn() { printf '%s[NOTE]%s %s\n' "$Y" "$N" "$*"; }
[ $# -eq 0 ] && { echo "Usage: sudo bash $0 /data/folder [/other/folder ...]"; exit 1; }
MAX=${MAX:-20000}
NICE="nice -n 19"; command -v ionice >/dev/null && NICE="$NICE ionice -c3"
warn "Started $(date). Checking up to $MAX xml/json/csv files under: $*"

for r in "$@"; do
  $NICE find "$r" -xdev -type f \( -iname '*.svs' -o -iname '*.ndpi' -o -iname '*.tif' -o -iname '*.tiff' \
    -o -iname '*.xml' -o -iname '*.json' -o -iname '*.geojson' -o -iname '*.csv' -o -iname '*.tsv' \) 2>/dev/null
done | {
  n=0
  while IFS= read -r f; do
    base=$(basename "$f"); stem=${base%.*}; lc=$(echo "$base" | tr 'A-Z' 'a-z')
    case "$lc" in
      *.svs|*.ndpi|*.tif|*.tiff) printf 'S\t%s\t%s\n' "$stem" "$f"; continue ;;
    esac
    n=$((n+1)); [ $n -gt "$MAX" ] && continue
    h=$(head -c 2048 "$f" 2>/dev/null | tr -d '\0' | tr '\n\r' '  ' | tr 'A-Z' 'a-z')
    case "$h" in
      *"<annotations"*micronsperpixel*|*"<annotations"*"<region "*|*"<annotation "*"<regions>"*) cls="ImageScope/Aperio XML" ;;
      *"<?xml"*) cls="other XML" ;;
      *featurecollection*|*'"type"'*'"polygon"'*) cls="GeoJSON (polygons)" ;;
      *provenance*|*execution_id*|*footprint*|*case_id*|*'"geometry"'*) cls="caMicroscope/App JSON" ;;
      *lym*|*',til'*|*'til,'*|*'"til'*) [ "${lc##*.}" = json ] && cls="JSON mentions lym/til" || cls="CSV: /lymphocyte" ;;
      *tumor*|*cancer*|*probab*) cls="CSV/JSON: tumor/probability" ;;
      *areainpixels*|*polygon*|*perimeter*|*nucle*) cls="CSV: segmentation features" ;;
      *) cls="other ${lc##*.}" ;;
    esac
    printf 'A\t%s\t%s\t%s\t%s\n' "$cls" "$stem" "$f" "$(stat -c %s "$f" 2>/dev/null)"
  done
  [ $n -gt "$MAX" ] && printf 'M\t%d\n' "$n"
} | awk -F'\t' -v G="$G" -v Y="$Y" -v B="$B" -v C="$C" -v R="$R" -v N="$N" '
function human(b) { if (b>=1073741824) return sprintf("%.1f GB", b/1073741824)
  if (b>=1048576) return sprintf("%.1f MB", b/1048576); return sprintf("%.0f KB", b/1024) }
$1 == "S" { slide[$2] = $3; ns++; next }
$1 == "M" { more = $2; next }
$1 == "A" { cls = $2; cN[cls]++; cB[cls] += $5
  d = $4; sub(/\/[^\/]*$/, "", d); k = cls "\t" d; kN[k]++
  if (cN[cls] <= 3) ex[cls] = ex[cls] "\n      " $4
  if (cls ~ /ImageScope/) { xs[$3] = $4; nx++ } }
END {
  printf "\n%s===== Annotation/result files by type (from file contents) =====%s\n", B, N
  for (c in cN) { col = (c ~ /^other/) ? N : G; printf "%s%-30s%s %8d files %10s%s\n", col, c, N, cN[c], human(cB[c]), C ex[c] N }
  printf "\n%s===== Folders holding each type (top 50) =====%s\n", B, N
  for (k in kN) print kN[k] "\t" k | "sort -t\"\t\" -k1,1nr | head -50"
  close("sort -t\"\t\" -k1,1nr | head -50")
  printf "\n%s===== ImageScope XML <-> slide match (same base name) =====%s\n", B, N
  m = 0; for (s in xs) if (s in slide) m++
  printf "%sSlides (.svs/.ndpi/.tif) seen: %d   ImageScope XMLs: %d   XMLs with matching slide: %d%s\n", G, ns, nx, m, N
  shown = 0; for (s in xs) if (!(s in slide) && shown < 10) { if (!shown) printf "%sXMLs with NO matching slide (first 10):%s\n", Y, N; print "   " xs[s]; shown++ }
  if (more) printf "\n%s[NOTE]%s %d files found but only the first MAX were classified. Re-run with MAX=%d for all.\n", Y, N, more, more
}'
warn "Done $(date). Counts are EXACT for files seen. Paths may hold case IDs: redact before sharing."
