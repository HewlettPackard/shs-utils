#!/usr/bin/env bash

set -ex
set -v

RPMDIR=$(realpath ./RPMS)
TMPDIR=$(realpath ./workspace)

if [[ -d $TMPDIR ]] ; then
	rm -rf $TMPDIR
fi
mkdir -p $TMPDIR

pushd $TMPDIR

## START Regression Test: NETETH-2148
function check_permissions() {
  local f=${1}
  local expected=${2}
  local actual="$(stat -L -c "%A" ${f})"

  if [[ "$expected" != "$actual" ]] ; then
    echo permission check failed for $f
    echo Regression: NETETH-2148
    echo expected: $expected
    echo actual: $actual
    exit 1
  fi
}

binary_rpm=$(find $RPMDIR -name 'slingshot-utils*.rpm' | grep -v "src.rpm")

if [[ -z "$binary_rpm" ]] ; then
	echo could not find slingshot-utils rpm
	ls -al $RPMDIR
	exit 1
fi

rpm2cpio $binary_rpm | cpio -id

## expecting 0755 for scripts
expected_permissions="-rwxr-xr-x"
for entry in slingshot-diag slingshot-snapshot slingshot-utils; do
  filepath=$(find $TMPDIR -name "$entry" -type f)

  if [[ -z "$filepath" ]] ; then
    echo failed to find $entry
    exit 1
  fi
  check_permissions $filepath $expected_permissions
done

## END NETETH-2148

popd
exit 0
