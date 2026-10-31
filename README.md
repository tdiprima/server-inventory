# server-spelunking 💡

Read-only Bash and legacy `mongo` shell scripts that inventory aging RHEL 7 caMicroscope servers (system, MongoDB, whole-slide images, annotations) and safely copy and repair their stopped MongoDB 3.x data on a modern host.

## Inheriting a Server Nobody Documented

Research imaging servers outlive the people who built them. You get root on a box running RHEL 7, a few terabytes of pathology slides, several MongoDB 3.x data folders left by unclean shutdowns, a caMicroscope viewer in Docker, and no notes. Before anyone can migrate or retire the machine, someone has to answer basic questions: What is on the disks? Which MongoDB versions wrote which folders? What databases and collections exist, and how big are they? Where are the slides and the , tumor, and annotation results?

The obvious shortcuts are dangerous. Starting `mongod` on the originals replays the journal and rewrites files, so you can lose the exact on-disk state you need for recovery. A naive `find /` across millions of files can take hours and starve the other tenants on the machine. Modern `mongosh` does not speak to MongoDB 3.x, and MongoDB 3.x does not install on a current Ubuntu because it needs `libssl1.0`.

## Look First, Never Touch the Originals

Every discovery script is read-only, labeled with a speed estimate (seconds to hours) and a safety color (GREEN or YELLOW), prints the exact command it runs, caps its output, and app.annotationss each finding `[FOUND]`, `[NOTE]`, or `[NONE]` so a non-expert can read the log. Scripts run under `timeout` and, for heavy disk walks, at lowest CPU and I/O priority.

- `01_system.sh` records OS, CPU, memory, disks, LVM, local and network mounts, services, installed software, users, and logs.
- `02_mongo_probe.sh` locates MongoDB binaries, configs, ports, auth settings, data folders, storage engine, and logs without connecting to or starting `mongod`.
- `03_camicroscope.sh` reads caMicroscope, , and iipsrv code and config from disk to extract database names, collections, image paths, and API endpoints.
- `04_find_data.sh` walks each local filesystem once and summarizes sizes and counts per folder and per file type (WSI, DICOM, XML, JSON, MongoDB files), keyword folders, and the 25 largest files.
- `05_annotation_probe.sh` classifies result files by their first 2 KB (Aperio ImageScope XML, caMicroscope JSON, GeoJSON,  and tumor CSVs) and matches each ImageScope XML to its `.svs` slide.
- `06_mongo_inventory.js` lists databases, collections, estimated sizes and counts, indexes, and GridFS buckets using metadata commands only. Written in ES5 so the legacy `mongo` shell can run it against an already-running server.
- `07_wt_catalog.sh` recovers `database.collection` names and on-disk sizes straight from the raw bytes of WiredTiger's `_mdb_catalog.wt`, so you get a collection inventory from a stopped database.
- `app_inv.sh` chains the fast scripts plus `locate` and Docker queries and saves every log under `logs/`.

The `copy-and-repair/` folder handles the next phase. The copy scripts refuse to run while `mongod` is alive, check free space on the destination, and `rsync` the whole `dbPath` including `journal/` so the exact state is preserved. `repair-mongo-copy.sh` runs only on the copy, refuses any path outside `/data/app*`, snapshots the folder to `<dbpath>.pre-repair` before touching it, then runs `mongod --repair` from the matching `mongo:3.x` Docker image and starts it on a localhost port for inspection.

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
sudo bash 02_mongo_probe.sh
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

Set `NO_COLOR=1` to disable color. Edit the paths at the top of `app_inv.sh` to run the whole fast set and keep logs.

To copy and repair stopped MongoDB data, run the matching `copy-and-repair/copy-*.sh` script on the source server inside `tmux`, then on the destination host:

```bash
./repair-mongo-copy.sh /path/to/your/db 3.2 27018
mongo --port 27018
```

Repair rewrites files, so run it only on the copy. The script snapshots to `<dbpath>.pre-repair` first and needs that much free space.

Requires Bash, GNU coreutils, `rsync`, and for repair Docker on the destination. Tested against RHEL 7 sources and an Ubuntu 24.04 destination.
