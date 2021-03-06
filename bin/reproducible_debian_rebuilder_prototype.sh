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


DEBUG=false
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
	local PKG=$1
	if [ "${PKG:0:3}" = "lib" ] ; then
		POOLPATH="${PKG:0:4}"
	else
		POOLPATH="${PKG:0:1}"
	fi
}

#
# main: this is basically a description of the steps to use debrebuild today...
#
PKG='bash'
VERSION='5.0-6'
FILE="${PKG}_${VERSION}_amd64.buildinfo"
POOLPATH="" 		# declared as a global variable
set_poolpath $PKG	# so we can set it here with a function
URLPATH="https://buildinfos.debian.net/buildinfo-pool/$POOLPATH/$PKG"

# hack, should be done better, also with cleanup *after* the job run...
mkdir $PKG || (rm $PKG -r ; mkdir $PKG)
cd $PKG

# use gpg here to workaround #955050 in devscripts: debrebuild: please accepted signed .buildinfo files
output_echo "downloading $URLPATH/$FILE"
# FIXME: this will fail with unsigned .buildinfo files
curl $URLPATH/$FILE | gpg > $FILE || true # we cannot validate the signature and we don't care
echo
output_echo  "$URLPATH/$FILE with gpg signature stripped:"
cat $FILE
# a successful build might overwrite the original .buildinfo file...
cp $FILE $FILE.orig

# prepare rebuild command
DEBREBUILD=$(mktemp -t debrebuild.XXXXXXXX)
output_echo "trying to debrebuild $PKG"
# workaround until devscripts 2.20.3 is released
/srv/jenkins/bin/rb-debrebuild $FILE 2>&1 | tee $DEBREBUILD

# FIXME: file a bug like '#955123 debrebuild: please provide --sbuild-output-only option' but with --output-only-base-release
# (parsing the debrebuild output to gather this information is way to fragile)
DISTRO=bullseye
output_echo "preparing chroot for $DISTRO"
# "|| true" is dummy code for regenerating this chroot every other week or so
sudo sbuild-createchroot $DISTRO /schroots/debrebuild-$DISTRO-amd64 http://deb.debian.org/debian || true

# I'm a bit surprised this was needed, as debrebuild has code for this...
# FIXME: a bug should probably be file for this as well
echo 'Acquire::Check-Valid-Until "false";' | sudo tee /schroots/debrebuild-$DISTRO-amd64/etc/apt/apt.conf.d/23-rebuild

# I guess I think it would be nice if debrebuild would also do this:
# FIXME: file another wishlist bug?
output_echo "fetching source package $PKG"
dget https://deb.debian.org/debian/pool/main/$POOLPATH/$PKG/${PKG}_5.0-6.dsc

# actually run sbuild
# - workaround #955123 in devscripts: debrebuild: please provide --sbuild-output-only option
#   - using tail
# - workaround #955304 in devscripts: debrebuild: suggested sbuild command should use --no-run-lintian
#   - using sed
output_echo "trying to re-sbuild $PKG..."
SBUILD=$(tail -1 $DEBREBUILD | sed 's# sbuild # sbuild --no-run-lintian #')
output_echo "using this sbuild call:"
echo $SBUILD
echo
eval $SBUILD

# show what we did/created
output_echo "File artifacts:"
ls -lart
output_echo "Diff between .buildinfo files:"
diff $FILE.orig $FILE || true
output_echo "The following binary packages could be rebuilt bit-by-bit identical to the ones distributed from ftp.debian.org:"
BADDEBS=""
for DEB in $(dcmd ls *.changes|egrep 'deb$' ) ; do
	SHASUM=$(sha256sum $DEB | awk '{ print $1 }')
	if grep $SHASUM $FILE.orig ; then
		# reproducible, yay!
		:
	else
		BADDEBS="$BADDEBS $DEB"
	fi
done
if [ -n "$BADDEBS" ] ; then
	output_echo "Unreproducible binary packages found:"
	for DEB in $BADDEBS ; do
		echo " $(egrep ' [a-z0-9]{64} ' $FILE.orig|grep $DEB | awk ' { print $1 " " $3 }') from ftp.debian.org"
		echo " $(sha256sum $DEB| sed 's#  # #') from the current rebuild"
	done
fi

# the end
rm -f $FILE $DEBREBUILD
output_echo "the end."
