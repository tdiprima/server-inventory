#!/usr/bin/env bash
# App discovery 03: read caMicroscope code/config from disk (never runs it).
# Finds DB names, collections, image paths, API endpoints, , iipsrv.
# SPEED: FAST (1-5 minutes; depends on code size). SAFETY: GREEN, read-only. Passwords NOT masked.
# Usage: sudo bash 03_camicroscope.sh [/path/to/app]   (default /opt/ViewerDockerContainer)

if [ -z "$NO_COLOR" ]; then R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1;34m'; C=$'\e[36m'; N=$'\e[0m'; fi
hdr()  { printf '\n%s===== %s =====%s\n' "$B" "$*" "$N"; }
ok()   { printf '%s[FOUND]%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s[NOTE]%s %s\n' "$Y" "$N" "$*"; }
miss() { printf '%s[NONE]%s %s\n' "$R" "$N" "$*"; }
T=""; command -v timeout >/dev/null && T="timeout 120"
mask() { cat; }  # passwords shown unmasked
# grep code files only, skip library folders, short lines, capped output
cgrep() { $T grep -r -I -n -i -E "$1" "$APP" \
  --include='*.php' --include='*.js' --include='*.json' --include='*.py' --include='*.conf' --include='*.ini' \
  --include='*.yml' --include='*.yaml' --include='*.xml' --include='*.properties' --include='*.sh' --include='*.env' --include='Dockerfile*' \
  --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=bower_components --exclude-dir=.git --exclude='*.min.js' \
  --exclude-dir=FlexTables --exclude-dir=dataTableScripts --exclude-dir=bootstrap --exclude-dir=fancytree --exclude-dir=dependencies \
  --exclude-dir=openseadragon --exclude='bundle.js' --exclude='jquery*.js' 2>/dev/null \
  | mask | cut -c1-220 | head -n "${2:-60}"; }

APP=${1:-/opt/ViewerDockerContainer}

hdr "1. App folder"
if [ -d "$APP" ]; then ok "$APP exists"; else miss "$APP missing. Searching for camicroscope folders..."; fi
$T find / /data -xdev -maxdepth 6 -type d -iname '*camicroscope*' 2>/dev/null | head -20
[ -d "$APP" ] || { warn "Re-run with the right path: sudo bash 03_camicroscope.sh /that/path"; exit 0; }
ls -la "$APP" "$APP/html" "$APP/html/camicroscope" 2>/dev/null | head -60
warn "Folder tree (3 levels):"
find "$APP" -maxdepth 3 -type d -not -path '*/node_modules*' -not -path '*/.git/*' | head -80

hdr "2. Live or abandoned? (newest files)"
find "$APP" -type f -not -path '*/.git/*' -printf '%TY-%Tm-%Td  %p\n' 2>/dev/null | sort -r | head -10
warn "Check: does Apache DocumentRoot/Alias point here? (section 8)"

hdr "3. Version clues"
for g in $(find "$APP" -maxdepth 4 -name .git -type d 2>/dev/null); do
  ok "git repo: $g  HEAD=$(cat "$g/HEAD")"; grep -A2 '\[remote' "$g/config" | mask
done
find "$APP" -maxdepth 4 -not -path '*/node_modules/*' \( -iname '*version*' -o -name package.json -o -name composer.json -o -iname 'CHANGELOG*' -o -iname 'README*' \) 2>/dev/null | head -20
for f in $(find "$APP" -maxdepth 4 -not -path '*/node_modules/*' \( -name 'Dockerfile*' -o -name 'docker-compose*.yml' \) 2>/dev/null | head -5); do
  ok "$f"; grep -v '^#' "$f" | mask | head -30
done

hdr "4. The TCIA entry point: osdCamicroscope.php"
for f in $($T find "$APP" / -xdev -maxdepth 7 -name 'osdCamicroscope.php' 2>/dev/null | sort -u | head -5); do
  ok "$f ($(date -r "$f" +%F 2>/dev/null))"
  grep -n -i -E 'include|require|src=|\$_GET|\$_REQUEST|url|api|tile|iip|fcgi|mongo|' "$f" | mask | cut -c1-200 | head -40
done

hdr "5. Config files"
find "$APP" -maxdepth 7 -type f -size -200k -not -path '*/node_modules/*' -not -path '*/vendor/*' \
  \( -iname '*config*' -o -iname '*.ini' -o -iname '*.env' -o -iname 'settings*' -o -iname '*.conf' -o -iname '*.properties' \) 2>/dev/null | head -40

hdr "6. Database references (mongo, db names, collections)"
cgrep 'mongodb://|MongoClient|mongo|27017|dbname|database|selectDB|collection' 80
warn "Possible collection names seen in code (hints only, unverified):"
cgrep "(selectCollection|getCollection|collection)[ (=:>]*[\"'][a-zA-Z_.]+[\"']" 200 | grep -o -i -E "(selectCollection|getCollection|collection)[ (=:>]*[\"'][a-zA-Z_.]+[\"']" | sort | uniq -c | sort -rn | head -30

hdr "7. Data service / API endpoints"
cgrep '|/api/|/services/|:9099|/data/|annotations|app.annotationsup|heatmap|execution_id|provenance|app.objects|metadata' 80

hdr "8. Image serving (iipsrv, OpenSlide, image paths)"
cgrep 'iipsrv|fcgi|openslide|FIF=|DeepZoom|\.svs|\.tif|imagepath|image_path|/data/images' 60
grep -r -h -i -E '^[^#]*(DocumentRoot|Alias|ProxyPass|fcgi|iipsrv|camicroscope)' /etc/apache2 /etc/httpd /etc/nginx 2>/dev/null | sort -u | head -30

hdr "9.  (old caMicroscope data API, often holds Mongo query configs)"
BD=$($T find /opt /home /usr/local /srv /root /data/home/docker/volumes "$APP" -maxdepth 5 -type d -iname '**' 2>/dev/null | head -10)
if [ -n "$BD" ]; then
  for d in $BD; do ok "$d"; find "$d" -maxdepth 4 -type d -iname 'projects' 2>/dev/null | while read -r p; do ls -la "$p" | head -30; done; done
  warn " project files list Mongo host, db and collection names:"
  for d in $BD; do $T grep -r -h -o -i -E '"(host|port|db|database|collection)"[^,}]{1,80}' "$d" 2>/dev/null | mask | sort | uniq -c | sort -rn | head -30; done
else miss "no  folder found"; fi

printf '\n%sDone. Next: script 04 (find data, SLOW).%s\n' "$G" "$N"
