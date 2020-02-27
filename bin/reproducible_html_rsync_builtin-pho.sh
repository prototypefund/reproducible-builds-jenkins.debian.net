#!/bin/bash
# vim: set noexpandtab:

# Copyright 2020 Holger Levsen <holger@layer-acht.org>
# released under the GPLv2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code for tests.reproducible-builds.org
. /srv/jenkins/bin/reproducible_common.sh

# rsync builtin-pho results from pb7
rsync -av profitbricks-build7-amd64.debian.net:/var/lib/jenkins/builtin-pho-html/debian/* $BASE/debian/

