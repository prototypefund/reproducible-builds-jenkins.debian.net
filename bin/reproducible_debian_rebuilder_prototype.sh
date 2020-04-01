#!/bin/bash
# vim: set noexpandtab:

# Copyright 2020 Holger Levsen <holger@layer-acht.org>
# released under the GPLv2

cat << EOF

###########################################################################################
###											###
### the goal is to create json export to integrate in tracker.d.o and/or packages.d.o	###
###											###
### another goal (implied in the one above) is create Debian's POV on the 'practical'	###
### reproducibility status of the packages distributed via ftp.d.o. - so far		###
### tests.r-b.o/debian/ only shows the 'theoretical' reproducibility of Debian packages.###
###											###
### we'll leave out the problem of 'trust' here quite entirely. that's why it's called	###
### a Debian rebuilder 'thing', to explore technical feasibility, ductaping our way	###
### ahead, keeping our motto 'to allow anyone to independently verify...' in mind.	###
###											###
###########################################################################################

EOF


DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code for tests.reproducible-builds.org
. /srv/jenkins/bin/reproducible_common.sh
set -e

output_echo(){
	echo
	echo "$(date -u) - $1"
	echo
}

set_poolpath() {
	# FIXME: dedummy this
	POOLPATH="b"
}

# main
# basically describe the steps to use debrebuild today...
PKG='bash'
VERSION='5.0-6'
FILE="${PKG}_${VERSION}_amd64.buildinfo"
POOLPATH="" 	# declared as a global variable
set_poolpath	# set it properly
URLPATH="https://buildinfos.debian.net/buildinfo-pool/$POOLPATH/$PKG"

# use gpg here to workaround #955050 in devscripts: debrebuild: please accepted signed .buildinfo files
output_echo "downloading $URLPATH/$FILE"
# FIXME: this will fail with unsigned .buildinfo files
curl $URLPATH/$FILE | gpg > $FILE || true # we cannot validate the signature and we don't care
echo
output_echo  "$URLPATH/$FILE with gpg signature stripped:"
cat $FILE

# prepare rebuild command
DEBREBUILD=$(mktemp -t debrebuild.XXXXXXXX)
output_echo "trying to debrebuild $PKG..."
# workaround until devscripts 2.20.3 is released
/srv/jenkins/bin/rb-debrebuild $FILE | tee $DEBREBUILD

# actually run sbuild
# - workaround #955123 in devscripts: debrebuild: please provide --sbuild-output-only option
#   - using tail
# - workaround #955304 in devscripts: debrebuild: suggested sbuild command should use --no-run-lintian
#   - using sed
output_echo "trying to re-sbuild $PKG..."
SBUILD=$(tail -1 $DEBREBUILD | sed 's# sbuild # sbuild --no-run-lintian #')
output_echo "sbuild is now called as:"
echo $SBUILD
echo
eval $SBUILD

# to be continued...

# the end
rm -f $FILE $DEBREBUILD
output_echo "the end."
