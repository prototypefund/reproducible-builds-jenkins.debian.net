#!/bin/bash

# Copyright © 2015 Holger Levsen <holger@debian.org>
# released under the GPLv2

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

cleanup_all() {
	rm -r $CODE || true
}

CODE=$(mktemp --tmpdir=/tmp gitclone-XXXXXXXXX -u)
trap cleanup_all INT TERM EXIT
# repository url doubly maintained in job-cfg/rebootstrap.yaml.py
git clone https://salsa.debian.org/helmutg/rebootstrap.git $CODE
cd $CODE
git checkout $1
shift
export LC_ALL=C
echo "$(date -u) - Now running '/srv/jenkins/bin/chroot-run.sh sid minimal ./bootstrap.sh $@'"
ionice -c 3 nice /srv/jenkins/bin/chroot-run.sh sid minimal ./bootstrap.sh $@
cd
cleanup_all
trap - INT TERM EXIT
