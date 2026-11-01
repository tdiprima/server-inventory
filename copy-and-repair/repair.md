# MongoDB Data Recovery — Repair Script

## Overview

The destination server runs **Ubuntu 24.04.5 LTS**, which does not natively support MongoDB 3.x through the original MongoDB APT repositories.

The repair process will use Docker containers running the appropriate legacy MongoDB versions, avoiding the need to install MongoDB directly on the host.

## MongoDB 3.x Compatibility

### Native Installation

Native installation is not recommended.

- MongoDB 3.x APT repositories targeted older Ubuntu releases, primarily 16.04 and 18.04.
- Legacy MongoDB packages depend on libraries such as `libssl1.0`, which are unavailable on Ubuntu 24.04.
- Installing these dependencies manually would introduce unnecessary compatibility and maintenance risks.

### Available Options

**Option 1: Docker (Preferred)**

Use legacy MongoDB Docker images:

- `mongo:3.2`
- `mongo:3.4`
- `mongo:3.6`

Mount the copied database directory into the container and execute `mongod --repair`.

Advantages:
- No native MongoDB installation required.
- Keeps legacy dependencies isolated from the host.
- Supports multiple MongoDB versions.
- Allows recovery operations against the copied data.

**Option 2: Legacy MongoDB Tarballs (Fallback)**

Use legacy generic binaries, such as:

- `mongodb-linux-x86_64-3.2.10.tgz`
- `mongodb-linux-x86_64-3.6.5.tgz`

These builds may run on newer Linux systems, depending on their runtime library requirements.

Use this approach if Docker is unavailable or unsuitable.

## Repair Script

**Location:** `Scripts/repair-mongo-copy.sh`

The script uses Docker images for MongoDB 3.2, 3.4, and 3.6.

### Prerequisites

Install Docker on the destination server:

```bash
sudo apt install docker.io
```

Ensure the Docker daemon is running and the executing user has permission to access it.

### Usage

Repair the main  database copied from `app1`:

```bash
./repair-mongo-copy.sh /path/to/your/db 3.2 27018
```

Repair the backup registry database copied from `app3`:

```bash
./repair-mongo-copy.sh /data/app3/data/backup-registry/data 3.4 27021
```

### Arguments

| Argument | Description | Example |
|---|---|---|
| `dbPath` | Absolute path to the copied MongoDB data directory | `/path/to/your/db` |
| Version | MongoDB version used for recovery | `3.2` |
| Port | Local port for the recovered MongoDB instance | `27018` |

## Script Behavior

The script performs the following operations in order.

### 1. Validate the Database Path

Refuses to operate on any path outside:

```text
/data/app*
```

This restriction is intended to prevent accidental repairs against the original database directories.

**Only copied data should be repaired.**

### 2. Detect Directory Layout

Inspects the database directory to determine whether MongoDB was configured with `directoryPerDB`.

Uses the detected layout when starting MongoDB.

### 3. Clone Into a Repair Workspace

The preserved copy at `<dbpath>` is never modified. The script clones it into a workspace it owns:

```text
<dbpath>.repair-work      (or -w <dir>)
```

The workspace must not exist beforehand; the script refuses to reuse a directory it did not create. A app.annotationser file `.repair-workspace` inside it names the source copy, and the script refuses to accept a workspace as `<dbpath>`. Any inspection container from a previous run with the same name is stopped before the clone.

Undo at any time: `rm -rf <workspace>`.

### 4. Handle Stale Lock Files

Removes a stale `mongod.lock` file left behind by an unclean shutdown, in the workspace only.

### 5. Execute MongoDB Repair

Starts a Docker container using the selected MongoDB version.

- Mounts the workspace.
- Runs as the database files' owner.
- Executes `mongod --repair`.
- Performs recovery operations against the copied data.

Journal recovery and repair may modify database files.

### 6. Start the Recovered Database

After a successful repair, starts MongoDB bound to:

```text
127.0.0.1:<port>
```

The script then:

- Prints the available databases.
- Displays commands for accessing the MongoDB shell.
- Displays commands for exporting data with `mongodump`.
- Displays commands for stopping MongoDB.
- Displays commands for undoing the repair by deleting the workspace.

## MongoDB Version Selection

Use the MongoDB version corresponding to the original database files.

| Database | MongoDB version |
|---|---|
| `db` | 3.2 |
| `tcga` | 3.4 |
| `til_maps` | 3.4 |
| `registry_project` | 3.4 |

If MongoDB 3.4 refuses to open a database directory, MongoDB 3.6 may be considered after investigating the failure and confirming compatibility.

**Do not use a MongoDB version older than the version that last wrote the database files.**

Where possible, match the original MongoDB patch version rather than relying only on the major/minor version.

## Storage Requirements

The repair workspace requires additional storage approximately equal to the size of the database being repaired, unless an appropriate copy-on-write snapshot mechanism is used.

| Database | Original size | Approximate total with workspace |
|---|---:|---:|
| `db` | 1.9 TB | 3.8 TB |
| `registry_project` | 6.1 TB | 12.2 TB |

### Low Disk Space

There is no skip-the-clone option. The script refuses a pre-existing workspace, so an empty directory cannot be passed off as a backup. If space is short, put the workspace on another filesystem with `-w`.

## Verification and Testing

### Not Yet Verified

- The script has not been tested on the actual Ubuntu 24.04.5 destination server.
- Availability of the legacy `mongo:3.2` Docker image has not been confirmed.
- Successful startup of the legacy MongoDB containers has not been tested.
- Database recovery has not been validated against the copied data.

### Known Risks

**Legacy Docker image availability**

MongoDB 3.x images are deprecated. The required tags may no longer be available or may have compatibility issues with the current Docker environment.

**Storage exhaustion**

The repair workspace can double the disk space required for each database. This is particularly significant for the 6.1 TB `registry_project` database.

**Unclean shutdown recovery**

The source databases were shut down uncleanly. Recovery may require journal replay, and successful repair is not guaranteed.

**MongoDB version compatibility**

Using a newer MongoDB version is not automatically safe. Data-file format compatibility and supported upgrade paths must be checked before attempting recovery with another version.

**Repair may modify or discard data**

`mongod --repair` is not a read-only operation. Depending on the database state and storage engine, it may rebuild structures or discard unrecoverable records.

## Recommended Recovery Sequence

1. Preserve the original MongoDB directories without starting `mongod`.
2. Complete the raw `rsync` copies to the destination server.
3. Verify the copies before attempting recovery.
4. Confirm the exact MongoDB versions and storage engines used by the original databases.
5. Validate that the required Docker images can run on Ubuntu 24.04.5.
6. Confirm free space for the repair workspace.
7. Attempt recovery on the smallest database first, using `/data/app3/data/backup-registry/data`.
8. Verify database startup, collections, and data integrity.
9. Proceed to the larger databases only after the recovery procedure has been validated.
10. Export recovered data using `mongodump` or another suitable migration method.

**Primary objective:** Recover the databases from preserved copies while keeping the original MongoDB data untouched.

<br>
