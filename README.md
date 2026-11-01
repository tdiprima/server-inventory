# server-spelunking 💡

Read-only shell scripts that map what lives on inherited legacy research servers (system, databases, imaging data, analysis results) and safely preserve stopped database files for recovery on a modern host.

## Taking Stock of Inherited Servers

Long-running research infrastructure changes hands. When a legacy server lands in your care, the first job is to build a clear picture of it before planning a migration or retirement: what hardware and storage it has, which services and databases it runs, where the multi-terabyte image collections and analysis results live, and how it all fits together.

That inventory has to be gathered carefully. Older database engines must not be started on their original data folders, because startup can rewrite files and destroy the exact state you need to preserve. Full-disk scans across millions of files can run for hours and compete with other workloads on the machine. And the tooling that ships with a current operating system often cannot talk to software several major versions behind. The scripts here are built for that situation: observe everything, change nothing, and leave a readable log behind.

## Look First, Never Touch the Originals

Every discovery script is read-only, labeled with a speed estimate (seconds to hours) and a safety color (GREEN or YELLOW), prints the exact command it runs, caps its output, and app.annotationss each finding `[FOUND]`, `[NOTE]`, or `[NONE]` so a non-expert can read the log. Scripts run under `timeout` and, for heavy disk walks, at lowest CPU and I/O priority.

- `01_system.sh` records OS, CPU, memory, disks, LVM, local and network mounts, services, installed software, users, and logs.
- `02_mongo_probe.sh` locates MongoDB binaries, configs, ports, auth settings, data folders, storage engine, and logs without connecting to or starting `mongod`.
- `03_camicroscope.sh` reads caMicroscope, , and iipsrv code and config from disk to extract database names, collections, image paths, and API endpoints.
- `04_find_data.sh` walks each local filesystem once and summarizes sizes and counts per folder and per file type (WSI, DICOM, XML, JSON, MongoDB files), keyword folders, and the 25 largest files.
- `05_annotation_probe.sh` classifies result files by their first 2 KB (Aperio ImageScope XML, caMicroscope JSON, GeoJSON,  and tumor CSVs) and matches each ImageScope XML to its `.svs` slide.
- `06_mongo_inventory.js` lists databases, collections, estimated sizes and counts, indexes, and GridFS buckets using metadata commands only. Written in ES5 so the legacy `mongo` shell can run it against an already-running server.
- `07_wt_catalog.sh` recovers `database.collection` names and on-disk sizes straight from the raw bytes of WiredTiger's `_mdb_catalog.wt`, so you get a collection inventory from a stopped database.
- `app_inv.sh` chains the fast scripts plus `locate` and Docker queries, saves every log under `logs/`, records each step's exit code in `logs/<dir>/status.txt`, and ends with `COMPLETE` (exit 0) or `PARTIAL` (exit 1). `01_system.sh` itself exits 2 when any command timed out or could not run.

The `copy-and-repair/` folder handles the next phase. The copy scripts refuse to run while `mongod` is alive, check free space on the destination, and `rsync` the whole `dbPath` including `journal/` so the exact state is preserved. The host-specific `copy-app*-mongo.sh` wrappers only list directories; the checks, transfer, and verification live once in `copy-mongo-lib.sh`. `repair-mongo-copy.sh` never modifies the preserved copy: it refuses any path outside `/data/app*`, clones the folder into a fresh workspace `<dbpath>.repair-work` that it app.annotationss as its own, then runs `mongod --repair` there from the matching `mongo:3.x` Docker image and starts it on a localhost port for inspection.

## Example: Collection Names From a Stopped Database

Running the WiredTiger catalog scanner on a server where `mongod` is down:

```
$ sudo bash 07_wt_catalog.sh /data/db

===== dbpath: /data/db =====
Total size:     1.9T
Engine version: WiredTiger 2.7.1
Last modified:  2021-03-14 02:17
Owner:          mongod
[NOTE] mongod.lock not empty: running now, or last shutdown was unclean
      SIZE  DATABASE.COLLECTION
   412.3 GB  app.annotations
   188.0 GB  app.objects
    41.7 GB  project.metadata
     9.2 GB  project.heatmap
...
37 collections, 1.1 TB (compressed on disk; real data is bigger)
[NOTE] Sizes are on-disk WiredTiger files (compressed). Doc counts need a running copy (script 06).
```

In seconds, without starting MongoDB, you know this folder was written by MongoDB 3.2, it was shut down uncleanly, and which collections hold the annotation data. That tells you which `mongo:3.2` image to use for repair and which collections to verify first.

## Usage

Copy the scripts to the target server and run the fast GREEN scripts first:

```bash
sudo bash 01_system.sh
sudo bash 02_mongo_probe.sh           # or: sudo bash 02_mongo_probe.sh /data /opt   (search roots)
sudo bash 07_wt_catalog.sh            # or: sudo bash 07_wt_catalog.sh /path/to/dbdir
sudo bash 03_camicroscope.sh [/path/to/app]
```

Then the slower YELLOW scans, inside `tmux` or `screen`:

```bash
sudo bash 04_find_data.sh                  # all local filesystems
sudo bash 04_find_data.sh /data /home      # only these folders
INCLUDE_NET=1 sudo bash 04_find_data.sh    # include NFS/CIFS mounts
sudo bash 05_annotation_probe.sh /data /home   # MAX=50000 to check more files
```

Only if script 02 showed `mongod` already running:

```bash
mongo --quiet --port 27017 06_mongo_inventory.js
mongo --quiet --eval 'var PEEK=true' 06_mongo_inventory.js   # field names and types, no values
```

Set `NO_COLOR=1` to disable color. To run the whole fast set and keep logs:

```bash
bash app_inv.sh                              # scripts in $HOME/app-inventory, logs in logs/app1
bash app_inv.sh /opt/inventory logs/app2     # custom script dir and log dir
```

To copy stopped MongoDB data, run the matching `copy-and-repair/copy-*.sh` script on the source server inside `tmux`:

```bash
./copy-app1-mongo.sh                                   # defaults: host 192.0.2.10, /data/app1, built-in dir list
./copy-app1-mongo.sh -H 10.0.0.5 -d /mnt/app1 -l /tmp/copy.log
./copy-app2-mongo.sh /data/registry_project/data       # only these source dirs
INCLUDE_OLD=1 ./copy-app1-mongo.sh                     # also copy the .old folders
```

Then on the destination host (Ubuntu 24.04), install Docker once, then repair:

```bash
sudo ./install-docker.sh            # apt docker.io, enables the service, adds you to the docker group
./repair-mongo-copy.sh /path/to/your/db 3.2 27017
./repair-mongo-copy.sh -r /mnt/app1 /mnt/app1/data/db 3.2 27017   # copies outside /data/app*
mongo --port 27017
```

Repair rewrites files, so the script works on a clone in `<dbpath>.repair-work` (or `-w dir`) and needs that much free space. It refuses to run if the workspace already exists; undo is `rm -rf` of the workspace, the preserved copy is never touched.

Requires Bash, GNU coreutils, `rsync`, and for repair Docker on the destination (`copy-and-repair/install-docker.sh` sets it up). Tested against RHEL 7 sources.
