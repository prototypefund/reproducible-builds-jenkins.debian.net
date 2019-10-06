#!/bin/bash
# vim: set noexpandtab:

# Copyright 2012-2019 Holger Levsen <holger@layer-acht.org>
#           © 2018 Mattia Rizzolo <mattia@debian.org>
# released under the GPLv2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

cleanup_workspace() {
	#
	# clean
	#
	cd $WORKSPACE
	cd ..
	rm -fv *.deb *.udeb *.dsc *_*.build *_*.changes *_*.tar.gz *_*.tar.bz2 *_*.tar.xz *_*.buildinfo
	cd $WORKSPACE
	#
	# git clone and pull is done by jenkins job
	#
	if [ -d .git ] ; then
		echo "git status:"
		git status
	fi
}

pdebuild_package() {
	#
	# only used to build the installation-guide package
	#
	SOURCE=installation-guide
	#
	# prepare build
	#
	# use host apt proxy configuration for pbuilder too
	if [ ! -z "$http_proxy" ] ; then
		pbuilder_http_proxy="--http-proxy $http_proxy"
	fi
	# prepare setting up base.tgz
	if [ ! -f /var/cache/pbuilder/base.tgz ] ; then
		sudo pbuilder --create $pbuilder_http_proxy
		TMPFILE=$(mktemp)
		cat >> $TMPFILE <<- EOF
# Preseeding man-db/auto-update to false
echo "man-db man-db/auto-update boolean false" | debconf-set-selections
echo "Configuring dpkg to not fsync()"
echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/02speedup
EOF
		# using host apt proxy settings too
		if [ ! -z "$http_proxy" ] ; then
			echo "echo '$(cat /etc/apt/apt.conf.d/80proxy)' > /etc/apt/apt.conf.d/80proxy" >> ${TMPFILE}
		fi
		#
		sudo pbuilder --execute $pbuilder_http_proxy --save-after-exec -- ${TMPFILE}
		rm ${TMPFILE}
	else
		ls -la /var/cache/pbuilder/base.tgz
		file /var/cache/pbuilder/base.tgz
		sudo pbuilder --update $pbuilder_http_proxy || ( sudo rm /var/cache/pbuilder/base.tgz ; sudo pbuilder --create $pbuilder_http_proxy)
	fi
	#
	# build
	#
	cd manual
	NUM_CPU=$(nproc)
	pdebuild --use-pdebuild-internal --debbuildopts "-J$NUM_CPU" -- --http-proxy $http_proxy
	#
	# publish and cleanup
	#
	CHANGES=$(ls /var/cache/pbuilder/result/${SOURCE}_*changes)
	publish_changes_to_userContent $CHANGES debian-boot "git commit $(git describe --always)"
	echo
	cat $CHANGES
	echo
	sudo dcmd rm $CHANGES
	cd ..
}

po2xml() {
	#
	# This needs a schroot called jenkins-d-i-sid with the
	# build-depends for the installation-guide package installed.
	# The d-i_schroot-sid-create job creates it.
	#
	local SESSION="d-i-manual-$RANDOM"
	schroot --begin-session "--session-name=$SESSION" -c jenkins-d-i-sid
	schroot --directory "$BUILDDIR/manual" --run-session -c "$SESSION" sh ./scripts/merge_xml en
	schroot --directory "$BUILDDIR/manual" --run-session -c "$SESSION" sh ./scripts/update_pot
	schroot --directory "$BUILDDIR/manual" --run-session -c "$SESSION" sh ./scripts/update_po $1
	schroot --directory "$BUILDDIR/manual" --run-session -c "$SESSION" sh ./scripts/revert_pot
	schroot --directory "$BUILDDIR/manual" --run-session -c "$SESSION" sh ./scripts/create_xml $1
	schroot --end-session -c "$SESSION"
}

build_language() {
	FORMAT=$2
	mkdir $FORMAT
	echo "Building the $FORMAT version of the $1 manual now."
	cd manual/build
	ARCHS=$(ls arch-options)
	for ARCH in $ARCHS ; do
		# ignore kernel architectures
		if [ "$ARCH" != "hurd" ] && [ "$ARCH" != "kfreebsd" ] && [ "$ARCH" != "linux" ] ; then
			#
			# This needs a schroot called jenkins-d-i-sid with the
			# build-depends for the installation-guide package installed.
			# The d-i_schroot-sid-create job creates it.
			#
			set -x
			schroot --directory $BUILDDIR/manual/build -c chroot:jenkins-d-i-sid make languages=$1 architectures=$ARCH destination=$BUILDDIR/manual/build/$FORMAT/ formats=$FORMAT
			set +x
			if ( [ "$FORMAT" = "pdf" ] && [ ! -f pdf/$1.$ARCH/install.$1.pdf ] ) || \
				( [ "$FORMAT" = "html" ] && [ ! -f html/$1.$ARCH/index.html ] ) ; then
					echo
					echo "Failed to build $1 $FORMAT for $ARCH, exiting."
					echo
					exit 1
			fi
		fi
	done
	cd ../..
	# remove directories if they are empty and in the case of pdf, leave a empty pdf
	# maybe it is indeed better not to create these jobs in the first place...
	# this is due to "Warning: pdf and ps formats are currently not supported for Chinese, Greek, Japanese and Vietnamese"
	(rmdir $FORMAT/* 2>/dev/null && rmdir $FORMAT 2>/dev/null ) || true
	if [ "$FORMAT" = "pdf" ] && [ ! -d $FORMAT ] ; then
		mkdir -p pdf/dummy
		touch pdf/dummy/dummy.pdf
	fi
	echo
}

cleanup_srv() {
	if [ "${BUILDDIR:0:9}" = "/srv/d-i/" ] && [ ${#BUILDDIR} -ge 10 ] ; then
		echo "Removing $BUILDDIR now."
		rm -rf $BUILDDIR
	fi
}


cleanup_workspace
#
# if $1 is not given, build the whole manual,
# else just the language $1 in format $2
#
# $1 = LANG
# $2 = FORMAT
# $3 if set, manual is translated using po files (else xml files are the default)
if [ "$1" = "" ] ; then
	pdebuild_package
else
	rm -rf html pdf
	if [ "$2" = "" ] ; then
		echo "Error: need format too."
		exit 1
	fi
	trap cleanup_srv INT TERM EXIT
	BUILDDIR=$(mktemp -d -p /srv/d-i d-i-manual-XXXX)
	echo "Copying $WORKSPACE/manual to $BUILDDIR now."
	cp -r $WORKSPACE/manual $BUILDDIR/
	cd $BUILDDIR
	if [ "$3" = "" ] ; then
		build_language $1 $2
	else
		po2xml $1
		build_language $1 $2
	fi
	echo "Copying back results from $BUILDDIR/manual/build/$2 to $WORKSPACE/"
	cp -r $BUILDDIR/manual/build/$2 $WORKSPACE/
	trap - INT TERM EXIT
	cleanup_srv
fi
cleanup_workspace
