# MongoDB Data Recovery — Copy Scripts

## Scripts

Two thin wrappers plus one shared implementation (`copy-mongo-lib.sh`, which holds the safety checks, transfer, and verification) are located in `Scripts/`:

| Script | Run on | Destination |
|---|---|---|
| `copy-app1-mongo.sh` | `app1` | `192.0.2.10:/data/app1/` |
| `copy-app3-mongo.sh` | `app3` | `192.0.2.10:/data/app3/` |

## Copy Method

**Copy the entire `dbPath` directory, not a `mongodump`.**

MongoDB (`mongod`) is stopped on both servers, and the last shutdowns were unclean.

- Starting `mongod` on the original servers would replay the journal and rewrite files.
- A raw `rsync` of the entire directory, including WiredTiger files and `journal/` together, preserves the existing on-disk state.
- Recovery and repair will be performed later on the copies using the matching MongoDB version.

## Data to Copy

### app1

| Source path | Size | Description |
|---|---|---|
| `/data/db` | 1.9 TB | Main , MongoDB 3.2 |
| `/data/data` | 23 GB | , MongoDB 3.4 |
| `/data/home/user02/tcga/data` | 657 GB | `app.app.objects`, MongoDB 3.4 |
| `/etc/mongod.conf` | — | MongoDB configuration |

**Optional:** Copy `db.old` and `data.old` only when `INCLUDE_OLD=1`.

### app3

| Source path | Size | Description |
|---|---|---|
| `/data/backup-registry/data` | 6 GB | Copy first as a test |
| `/data/registry_project/data` | 6.1 TB | Main registry |
| `/data/home/user07/app1/data` | 32 GB | Additional MongoDB data |
| `/data/home/docker/volumes/_data/bin/projects` | — | Database and collection names |
| `/etc/mongod.conf` | — | MongoDB configuration |

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

On `app3`:

```bash
DEST_USER=root ./copy-app3-mongo.sh
```

### Prerequisites

- SSH key authentication to `192.0.2.10`.
- More than **2.6 TB** of free space for `app1`.
- More than **6.2 TB** of free space for `app3`.

Destination paths mirror the original source directory structure.

For example:

```text
Source:
  app1:/data/db

Destination:
  192.0.2.10:/path/to/your/db
```

## Verification

Each script finishes with an `rsync` dry-run verification pass.

**Expected result: 0 files differ.**

A nonzero difference count requires investigation before considering the copy complete.

### Checksum Manifest

A separate SHA-256 checksum manifest was intentionally omitted.

- Hashing approximately 8 TB would be time-consuming.
- The `rsync` dry-run verification pass serves as the copy check.

## Outstanding Checks and Risks

### Not Yet Verified

- SSH username and key authentication to `192.0.2.10`.
- Actual free disk space on `192.0.2.10`.

### Known Risks

**Filesystem layout on app3**

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
