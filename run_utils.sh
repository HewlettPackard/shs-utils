#!/bin/bash
#
# Copyright 2021 Hewlett Packard Enterprise Development LP. All rights reserved.
#

if [ ${EUID} -ne 0 ]
then
    printf 'please run this script as root. Exiting.\n'
    exit 1
fi

printf '==Running slingshot-utils diag==\n'
./bin/slingshot-utils diag
printf '\ndone.\n'

printf '\n==Running slingshot-utils snapshot==\n'
./bin/slingshot-utils snapshot
printf '\ndone.\n'

exit 0
