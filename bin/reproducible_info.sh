#!/bin/bash

# Copyright 2015-2018 Holger Levsen <holger@layer-acht.org>
# released under the GPLv2

DEBUG=false
set -e
# common code defining BUILD_ENV_VARS
. /srv/jenkins/bin/reproducible_common.sh

# these variables also need to be in bin/reproducible_common.sh where they define $BUILD_ENV_VARS (see right below)
ARCH=$(dpkg --print-architecture)
NUM_CPU=$(nproc)
CPU_MODEL=$(cat /proc/cpuinfo |grep "model name"|head -1|cut -d ":" -f2|xargs echo)
DATETIME=$(date +'%Y-%m-%d %H:%M %Z')
KERNEL=$(uname -smrv)
for i in $BUILD_ENV_VARS ; do
	echo "$i=${!i}"
done
