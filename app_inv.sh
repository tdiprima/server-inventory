#!/usr/bin/env bash
# Usage: bash app_inv.sh [inventory_dir] [log_dir]
#   inventory_dir  folder holding the 0N_*.sh scripts (default $HOME/app-inventory)
#   log_dir        where logs go, relative to inventory_dir (default logs/app1)
#
# Exit contract: 0 = every step exited 0 (COMPLETE), 1 = some step failed or
# timed out (PARTIAL). Per-step exit codes are in <log_dir>/status.txt.
INV=${1:-$HOME/app-inventory}
L=${2:-logs/app1}
cd "$INV" || exit 1

mkdir -p "$L"
STATUS=$L/status.txt
: > "$STATUS"
RESULT=0

# step <logname> <cmd...>: run, tee to <log_dir>/<logname>.log, record the exit status.
step() {
    local name=$1; shift
    "$@" 2>&1 | tee "$L/$name.log"
    local rc=${PIPESTATUS[0]}
    echo "$name rc=$rc" >> "$STATUS"
    [ "$rc" -eq 0 ] || { RESULT=1; echo "*** $name exited $rc" >&2; }
}

# ============================================================
# 1. System and MongoDB
# ============================================================

echo "=== System inventory ==="
step 01 sudo bash ./01_system.sh

echo "=== MongoDB probe ==="
step 02 sudo bash ./02_mongo_probe.sh

echo "=== WiredTiger catalog ==="
step 07 sudo bash ./07_wt_catalog.sh


# ============================================================
# 2. File index and image counts
# ============================================================

locate_inv() {
    echo "=== Locate database ==="
    ls -l /var/lib/mlocate/mlocate.db || return 1

    echo "=== WiredTiger directories ==="
    locate -r '/WiredTiger$'

    echo "=== Old MongoDB .ns files ==="
    locate -r '\.ns$' \
        | grep -v -E '\.(js|py|cc|h)$' \
        | head -20

    echo "=== caMicroscope viewer code ==="
    locate osdCamicroscope.php \
        | grep -v '\.sw' \
        | head -30

    echo "=== Image and annotation counts ==="
    for e in svs ndpi tif tiff dcm xml; do
        echo "$e: $(locate -i -r "\.$e\$" | wc -l)"
    done
}
step locate locate_inv


# ============================================================
# 3. Docker, , and App
# ============================================================

docker_inv() {
    echo "=== Docker root directory ==="
    sudo docker info 2>/dev/null \
        | grep -i "root dir"

    echo "=== Docker containers ==="
    sudo docker ps -a || return 1

    echo "=== Docker volumes ==="
    sudo docker volume ls

    echo "===  project files ==="
    locate -r '/projects/.*\.project$' \
        | head -20

    echo "=== App container scripts ==="
    locate run_containers \
        | head
    return 0
}
step docker docker_inv


# ============================================================
# Done
# ============================================================

echo "Logs saved to:"
echo "$INV/$L/"
if [ "$RESULT" -eq 0 ]; then
    echo "=== App 1 inventory COMPLETE ==="
else
    echo "=== App 1 inventory PARTIAL. Failed steps (see $STATUS):"
    grep -v 'rc=0$' "$STATUS"
fi
exit $RESULT
