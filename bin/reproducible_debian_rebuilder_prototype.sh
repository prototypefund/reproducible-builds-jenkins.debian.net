#!/bin/bash
# vim: set noexpandtab:

# Copyright 2020 Holger Levsen <holger@layer-acht.org>
# released under the GPLv2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code for tests.reproducible-builds.org
. /srv/jenkins/bin/reproducible_common.sh

set -e

# main

# basically describe the steps to use debrebuild today...

FILE='bash_5.0-6_amd64.buildinfo'
URLPATH='https://buildinfos.debian.net/buildinfo-pool/b/bash'

# use gpg here to workaround #955050 in devscripts: debrebuild: please accepted signed .buildinfo files
curl $URLPATH/$FILE | gpg > $FILE
echo
echo this is $URLPATH/$FILE with gpg signature stripped:
cat $FILE

# prepare rebuild command
DEBREBUILD=$(mktemp -t debrebuild.XXXXXXXX)
echo now trying to rebuild bash...
rb-debrebuild $FILE | tee $DEBREBUILD

# to be continued...

# the end
rm -f $FILE $DEBREBUILD
