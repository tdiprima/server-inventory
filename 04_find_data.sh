#!/usr/bin/env bash
# App discovery 04: walk the filesystems ONCE and summarize where the data is.
# Sizes and counts per folder, per file type (WSI, DICOM, XML, JSON, Mongo files...), keyword folders
# (til, tumor, heatmap, annot...), and the 25 biggest files. Prints a summary, not every file.
# SPEED: SLOW. Minutes to HOURS. Rough guide: 1 minute per 300,000 files (see 'df -i' IUsed).
# SAFETY: YELLOW. Read-only, but heavy disk reads. Runs at lowest CPU/disk priority.
# Usage: sudo bash 04_find_data.sh                -> all LOCAL filesystems
#        sudo bash 04_find_data.sh /data /home    -> only these folders
#        INCLUDE_NET=1 sudo bash 04_find_data.sh  -> also NFS/CIFS mounts (slower, loads other servers)
#        DEPTH=4 ...                              -> group by deeper folders (default 3, e.g. /data/images/x)

if [ -z "$NO_COLOR" ]; then R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1;34m'; C=$'\e[36m'; N=$'\e[0m'; fi
hdr()  { printf '\n%s===== %s =====%s\n' "$B" "$*" "$N"; }
warn() { printf '%s[NOTE]%s %s\n' "$Y" "$N" "$*"; }
DEPTH=${DEPTH:-3}

NICE="nice -n 19"; command -v ionice >/dev/null && NICE="$NICE ionice -c3"
if [ $# -gt 0 ]; then ROOTS="$*"; else
  FS='ext2|ext3|ext4|xfs|btrfs|jfs|reiserfs|zfs|vfat'
  [ -n "$INCLUDE_NET" ] && FS="$FS|nfs|nfs4|cifs|smbfs|glusterfs"
  ROOTS=$(awk -v fs="^($FS)\$" '$3 ~ fs {print $2}' /proc/mounts | sort -u)
fi
[ "$(id -u)" -ne 0 ] && warn "Not root. Unreadable folders will be skipped silently."
warn "Scanning: $(echo $ROOTS)"
warn "Estimated files (inodes used):"; df -iP $ROOTS 2>/dev/null | awk 'NR>1{print "   ", $3, "files on", $6}' | sort -u
warn "Started $(date). Safe to Ctrl-C. Nothing is changed."
START=$(date +%s)

# One pass: "size<TAB>path" for every file, then awk summarizes.
for r in $ROOTS; do $NICE find "$r" -xdev -type f -printf '%s\t%p\n' 2>/dev/null; done |
awk -F'\t' -v depth="$DEPTH" \
  -v KW='(^|[^a-z])(til|tils|lym|lymph|lymphocyte|tumor|tumour|cancer|heatmap|heatmaps|annot|annotation|annotations|app.annotationsup|app.annotations|segment|seg|segmentation|nuclei|imagescope|aperio|camic|camicroscope|app||mongo|mongodb|tcga|tcia|execution)([^a-z]|$)' '
function human(b) { if (b>=1099511627776) return sprintf("%.2f TB", b/1099511627776)
  if (b>=1073741824) return sprintf("%.1f GB", b/1073741824)
  if (b>=1048576) return sprintf("%.1f MB", b/1048576); return sprintf("%.0f KB", b/1024) }
function cat_of(name,   e, n) {
  n = tolower(name); e = n; sub(/.*\//, "", e)
  if (e == "wiredtiger" || e == "mongod.lock" || e == "storage.bson") return "MONGO (WiredTiger/lock)"
  if (e ~ /^(collection|index)-.*\.wt$/) return "MONGO (WiredTiger/lock)"
  if (e !~ /\./) return "no extension"
  sub(/.*\./, "", e)
  if (e ~ /^(svs|ndpi|scn|mrxs|vms|vmu|bif|svslide|czi|qptiff)$/) return "WSI slide"
  if (e ~ /^(tif|tiff)$/) return "TIFF (slide or tile)"
  if (e ~ /^(dcm|dicom)$/) return "DICOM"
  if (e == "xml") return "XML (ImageScope?)"
  if (e ~ /^(json|geojson)$/) return "JSON/GeoJSON"
  if (e ~ /^(csv|tsv)$/) return "CSV/TSV"
  if (e ~ /^(jpg|jpeg|png|gif|bmp|jp2)$/) return "small image/tile"
  if (e == "dzi") return "DZI pyramid"
  if (e ~ /^(h5|hdf5|npy|npz|pkl|pickle|mat)$/) return "array (heatmap/feature?)"
  if (e ~ /^(pth|pt|ckpt|t7|caffemodel|pb|onnx|hdf)$/) return "AI model"
  if (e == "ns") return "MONGO (MMAPv1 .ns)"
  if (e ~ /^[0-9]+$/) return "numbered (MMAPv1 data?)"
  if (e == "wt") return "MONGO (WiredTiger/lock)"
  if (e == "bson") return "BSON (mongodump)"
  if (e ~ /^(tar|gz|tgz|zip|bz2|xz|7z|rar)$/) return "archive"
  if (e ~ /^(sql|sqlite|db|mdb)$/) return "other database"
  if (e ~ /^(log|out|err)$/) return "log"
  if (e ~ /^(php|js|py|java|sh|c|cpp|m|r|ipynb)$/) return "code"
  return "other" }
{ size = $1; path = $2; nf = split(path, p, "/")
  key = ""; for (i = 2; i <= depth + 1 && i < nf; i++) key = key "/" p[i]; if (key == "") key = "/"
  c = cat_of(path)
  dB[key] += size; dN[key]++
  cB[c] += size; cN[c]++
  ck = c "\t" key; ckB[ck] += size; ckN[ck]++
  if (!(c in sample)) sample[c] = path
  # keyword folder = shallowest folder whose name matches a keyword
  acc = ""; for (i = 2; i < nf; i++) { acc = acc "/" p[i]; if (tolower(p[i]) ~ KW) { kB[acc] += size; kN[acc]++; break } }
  tot += size; files++
  # keep 25 biggest files
  if (nb < 25) { bigS[++nb] = size; bigP[nb] = path; if (nb == 25) { mi = 1; for (j = 2; j <= 25; j++) if (bigS[j] < bigS[mi]) mi = j } }
  else if (size > bigS[mi]) { bigS[mi] = size; bigP[mi] = path; mi = 1; for (j = 2; j <= 25; j++) if (bigS[j] < bigS[mi]) mi = j }
}
END {
  printf "A\t%.0f\t%d\n", tot, files
  for (k in dB) printf "D\t%.0f\t%d\t%s\n", dB[k], dN[k], k
  for (k in cB) printf "C\t%.0f\t%d\t%s\t%s\n", cB[k], cN[k], k, sample[k]
  for (k in ckB) printf "X\t%.0f\t%d\t%s\n", ckB[k], ckN[k], k
  for (k in kB) printf "K\t%.0f\t%d\t%s\n", kB[k], kN[k], k
  for (j = 1; j <= nb; j++) printf "B\t%.0f\t1\t%s\n", bigS[j], bigP[j]
}' | sort -t "$(printf '\t')" -k1,1 -k2,2nr | awk -F'\t' -v G="$G" -v Y="$Y" -v B="$B" -v C="$C" -v R="$R" -v N="$N" '
function human(b) { if (b>=1099511627776) return sprintf("%.2f TB", b/1099511627776)
  if (b>=1073741824) return sprintf("%.1f GB", b/1073741824)
  if (b>=1048576) return sprintf("%.1f MB", b/1048576); return sprintf("%.0f KB", b/1024) }
$1 == "A" { printf "%s===== TOTAL: %d files, %s =====%s\n", B, $3, human($2), N; next }
$1 != last { last = $1; n = 0
  if ($1 == "B") printf "\n%s===== 25 biggest files =====%s\n", B, N
  if ($1 == "C") printf "\n%s===== By file type (all locations) =====%s\n%-28s %10s %10s  %s\n", B, N, "TYPE", "SIZE", "FILES", "EXAMPLE"
  if ($1 == "D") printf "\n%s===== Top 40 folders by size =====%s\n%10s %10s  %s\n", B, N, "SIZE", "FILES", "FOLDER"
  if ($1 == "K") printf "\n%s===== Top 40 keyword folders (til/tumor/heatmap/annot/mongo/...) =====%s\n%10s %10s  %s\n", B, N, "SIZE", "FILES", "FOLDER"
  if ($1 == "X") printf "\n%s===== Where each data type lives (top 60) =====%s\n%-28s %10s %10s  %s\n", B, N, "TYPE", "SIZE", "FILES", "FOLDER" }
{ n++ }
$1 == "B" { printf "%10s  %s\n", human($2), $4 }
$1 == "C" { col = ($4 ~ /WSI|DICOM|XML|JSON|MONGO|BSON|heatmap|TIFF|CSV|model/) ? G : N
            printf "%s%-28s%s %10s %10d  %s\n", col, $4, N, human($2), $3, $5 }
$1 == "D" && n <= 40 { printf "%10s %10d  %s%s%s\n", human($2), $3, C, $4, N }
$1 == "K" && n <= 40 { printf "%10s %10d  %s%s%s\n", human($2), $3, Y, $4, N }
$1 == "X" && n <= 60 && $4 !~ /^(other|code|log|no extension)$/ { printf "%s%-28s%s %10s %10d  %s\n", G, $4, N, human($2), $3, $5 }
'
END=$(date +%s)
printf '\n%sDone in %d minutes. Sizes are EXACT byte sums of files seen (unreadable folders skipped).%s\n' "$G" $(( (END-START)/60 )) "$N"
warn "Example paths may contain patient/case IDs. Redact before sharing."
