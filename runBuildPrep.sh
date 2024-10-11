#!/bin/bash
#
# Copyright 2021-2023 Hewlett Packard Enterprise Development LP. All rights reserved.
#

if [[ -v SHS_NEW_BUILD_SYSTEM ]]; then
  . ${CE_INCLUDE_PATH}/load.sh

  replace_release_metadata "slingshot-utils.spec"
else
BRANCH=`git branch --show-current`

if [ -d hpc-shs-version ]; then
    git -C hpc-shs-version pull
else
    if [[ -n "${SHS_LOCAL_BUILD}" ]]; then
        git clone git@github.hpe.com:hpe/hpc-shs-version.git
    else
    	git clone https://$HPE_GITHUB_TOKEN@github.hpe.com/hpe/hpc-shs-version.git
    fi
fi

. hpc-shs-version/scripts/get-shs-version.sh
. hpc-shs-version/scripts/get-shs-label.sh

PRODUCT_VERSION=$(get_shs_version)
PRODUCT_LABEL=$(get_shs_label)

echo "INFO: Using SHS release version from BRANCH: '$BRANCH_NAME'"
echo
echo "INFO: SHS release version '$PRODUCT_VERSION'"

sed -i -e "s/Release:.*/Release: ${PRODUCT_LABEL}${PRODUCT_VERSION}_%(echo \\\${BUILD_METADATA:-1})/g"  slingshot-utils.spec
fi
