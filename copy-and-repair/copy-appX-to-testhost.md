# MongoDB Data Recovery — Copy Scripts

## Scripts

Two thin wrappers plus one shared implementation (`copy-mongo-lib.sh`, which holds the safety checks, transfer, and verification) are located in `Scripts/`:

| Script | Run on | Destination |
|---|---|---|
| `copy-app1-mongo.sh` | `app1` | `DEST_HOST:/data/app1/` |
| `copy-app2-mongo.sh` | `app2` | `DEST_HOST:/data/app2/` |

Both are example configurations. Edit `SRC_DIRS`, `SRC_FILES`, `DEST_ROOT` and `LOG` for your environment. `DEST_HOST` defaults to `192.0.2.10`; override with `-H` or the `DEST_HOST` variable.

## Copy Method

**Copy the entire `dbPath` directory, not a `mongodump`.**

MongoDB (`mongod`) is stopped on both servers, and the last shutdowns were unclean.

- Starting `mongod` on the original servers would replay the journal and rewrite files.
- A raw `rsync` of the entire directory, including WiredTiger files and `journal/` together, preserves the existing on-disk state.
- Recovery and repair will be performed later on the copies using the matching MongoDB version.

## Data to Copy

### app1

| Source path | Description |
|---|---|
| `/data/db` | Main DB, MongoDB 3.2 |
| `/data/secondary/data` | Second `mongod` instance, MongoDB 3.4 |
| `/data/home/USER/project/data` | Per-user `mongod`, MongoDB 3.4 |
| `/etc/mongod.conf` | MongoDB configuration |

**Optional:** Copy `db.old` and `data.old` only when `INCLUDE_OLD=1`.

### app2

| Source path | Description |
|---|---|
| `/data/backup-small/data` | Small and readable, copy first as a test |
| `/data/main_project/data` | Main DB, largest |
| `/data/home/USER/project/data` | Per-user `mongod` |
| `/var/lib/docker/volumes/APP_VOLUME/_data/projects` | App config naming the databases and collections |
| `/etc/mongod.conf` | MongoDB configuration |

Find every `dbPath` with `storage.dbPath` in each `mongod.conf`, or from `ps` output while `mongod` was running. Note the `mongod` version that wrote each one; repair needs it.

## Script Behavior

Both scripts:

- Refuse to run if `mongod` is running.
- Print available free space on the destination.
- Use `rsync -aH --sparse --partial`.
- Run with `ionice` and `nice` to reduce I/O and CPU priority.
- Write logs to `/var/tmp`.
- Support resuming after interruption by rerunning the script.
- Finish with a dry-run verification pass, which must report **0 files differ**.

## Execution

Start a persistent `tmux` session:

```bash
tmux new -s copy
```

On `app1`:

```bash
DEST_USER=root ./copy-app1-mongo.sh
```

On `app2`:

```bash
DEST_USER=root ./copy-app2-mongo.sh
```

### Prerequisites

- SSH key authentication to the destination host.
- Free space on the destination larger than the sum of the source directories (`du -sh` each one first).

Destination paths mirror the original source directory structure.

For example:

```text
Source:
  app1:/data/db

Destination:
  DEST_HOST:/data/app1/data/db
```

## Verification

Each script finishes with an `rsync` dry-run verification pass.

**Expected result: 0 files differ.**

A nonzero difference count requires investigation before considering the copy complete.

### Checksum Manifest

A separate SHA-256 checksum manifest was intentionally omitted.

- Hashing multi-TB copies would be time-consuming.
- The `rsync` dry-run verification pass serves as the copy check.

## Outstanding Checks and Risks

### Not Yet Verified

- SSH username and key authentication to the destination host.
- Actual free disk space on the destination host.

### Known Risks

**Filesystem layout on app2**

Confirm whether `/data` resides on the expected filesystem before starting the copy.

**Corrupt or unreadable files**

If `rsync` encounters read errors on corrupt files:

- It may continue copying other files.
- It will exit with a nonzero status.
- The log must be reviewed to identify failures.

**Recovery considerations**

The raw copies preserve the existing database files, including the journal, but do not guarantee that the databases will recover successfully.

Recovery should be attempted on working copies using the corresponding MongoDB versions, leaving the original data untouched.

<br>
