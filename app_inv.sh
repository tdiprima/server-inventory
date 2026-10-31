cd $HOME/app-inventory || exit 1

mkdir -p logs/app1
L=logs/app1

# ============================================================
# 1. System and MongoDB
# ============================================================

echo "=== System inventory ==="
sudo bash ./01_system.sh 2>&1 | tee "$L/01.log"

echo "=== MongoDB probe ==="
sudo bash ./02_mongo_probe.sh 2>&1 | tee "$L/02.log"

echo "=== WiredTiger catalog ==="
sudo bash ./07_wt_catalog.sh 2>&1 | tee "$L/07.log"


# ============================================================
# 2. File index and image counts
# ============================================================

{
    echo "=== Locate database ==="
    ls -l /var/lib/mlocate/mlocate.db

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

} 2>&1 | tee "$L/locate.log"


# ============================================================
# 3. Docker, , and App
# ============================================================

{
    echo "=== Docker root directory ==="
    sudo docker info 2>/dev/null \
        | grep -i "root dir"

    echo "=== Docker containers ==="
    sudo docker ps -a

    echo "=== Docker volumes ==="
    sudo docker volume ls

    echo "===  project files ==="
    locate -r '/projects/.*\.project$' \
        | head -20

    echo "=== App container scripts ==="
    locate run_containers \
        | head

} 2>&1 | tee "$L/docker.log"


# ============================================================
# Done
# ============================================================

echo "=== App 1 inventory complete ==="
echo "Logs saved to:"
echo "$HOME/app-inventory/logs/app1/"
