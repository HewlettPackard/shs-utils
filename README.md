# slingshot-utils
slingshot-utils contains a small set of scripts collecting system information
to assist the SS10 and SS11 groups in triaging.
These scripts must be run as root.

## Installation
```
./runBuildPrep.sh
./build.sh
```

## Usage
```
./run_utils.sh

./bin/slingshot-utils diag

./bin/slingshot-utils snapshot
```

## Description
The script slingshot-utils is used to perform diagnostics and to
create a snapshot.

The two scripts slingshot-diag.sh and slingshot-snapshot.sh are provided
for temporary backwards compatibility.  The use 'slingshot-utils diag' and
'slingshot-utils snapshot' to carry out their actions.

#### slingshot-utils snapshot
'slingshot-utils snapshot' creates a tarball for easy uploading to JIRA. The
tarball will include information about the system it has been executed on
(env, dmesg, RPMs, device firmware versioning and configuration, etc.). We ask
bug reporters to please attach the resulting collected information to any
Slingshot networking bug that you may open.

#### slingshot-utils diag
'slingshot-utils diag' is a self-diagnostic that runs checks in search of
known/common problems. We ask bug reporters to please include any output from
this script in your ticket.

Note: This script is a WIP and is periodically updated with additional checks
as they come up to make the script as thorough as possible. If possible, please
run a git pull to ensure you have the latest modifications included in your
local repo before running the script.

#### slingshot-utils devices
'slingshot-utils devices' simply lists the SS10 (Mellanox) and SS11 (Cassini)
devices found in the system

#### slingshot-utils __devhook SHELL-ROUTINE [SHELL-ROUTINE-PARAMS...]
'slingshot-utils __devhook ...' is a method for developers allowing only
specific shell routine to run after the standard initialization.  Its
intention is to aid in development and debugging .
