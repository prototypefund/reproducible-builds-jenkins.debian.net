#!/bin/bash

# Copyright 2015-2019 Holger Levsen <holger@layer-acht.org>
#           2017-2019 kpcyrd <git@rxv.cc>
#                2017 Mattia Rizzolo <mattia@debian.org>
#                Juliana Oliveira Rodrigues <juliana.orod@gmail.com>
# released under the GPLv=2

#
# downloads an alpine bootstrap chroot archive, then turns it into a schroot,
# then configures abuild.
#

set -e

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

# define alpine mirror to be used
ALPINE_MIRROR=http://dl-cdn.alpinelinux.org/alpine/edge/releases/x86_64

bootstrap() {
	echo "$(date -u) - trying to determine latest alpine edge minirootfs"
	LATEST_MINIROOT=$(curl -sSf "$ALPINE_MIRROR/" | grep -oE 'alpine-minirootfs-[0-9]+-x86_64.tar.gz' | sort | tail -1)

	if [ -z $LATEST_MINIROOT ]; then
		echo "Failed to find latest minirootfs, aborting."
		exit 1
	fi

	rm -f "./$LATEST_MINIROOT"

	echo "$(date -u) - downloading alpine minirootfs"
	curl -fO "$ALPINE_MIRROR/$LATEST_MINIROOT"

	echo "$(date -u) - extracting alpine minirootfs"
	mkdir -p "$SCHROOT_BASE/$TARGET.new"
	sudo tar xzf "./$LATEST_MINIROOT" -C "$SCHROOT_BASE/$TARGET.new"

	if [ -d "$SCHROOT_BASE/$TARGET" ]; then
		mv "$SCHROOT_BASE/$TARGET" "$SCHROOT_BASE/$TARGET.old"
		sudo rm -rf --one-file-system "$SCHROOT_BASE/$TARGET.old"
	fi
	mv "$SCHROOT_BASE/$TARGET.new" "$SCHROOT_BASE/$TARGET"

	rm -f "./$LATEST_MINIROOT"

	# write the schroot config
	echo "$(date -u ) - writing schroot configuration for $TARGET."
	sudo tee /etc/schroot/chroot.d/jenkins-"$TARGET" <<-__END__
		[jenkins-$TARGET]
		description=Jenkins schroot $TARGET
		directory=$SCHROOT_BASE/$TARGET
		type=directory
		root-users=jenkins
		source-root-users=jenkins
		union-type=overlay
	__END__
}

cleanup() {
	if [ -d "$SCHROOT_TARGET" ]; then
		rm -rf --one-file-system "$SCHROOT_TARGET" || ( echo "Warning: $SCHROOT_TARGET could not be fully removed on forced cleanup." ; ls "$SCHROOT_TARGET" -la )
	fi
	rm -f "$TMPLOG"
	exit 1
}

trap cleanup INT TERM EXIT
TARGET=reproducible-alpine
bootstrap
trap - INT TERM EXIT

ROOTCMD="schroot --directory /tmp -c source:jenkins-reproducible-alpine -u root --"
USERCMD="schroot --directory /tmp -c source:jenkins-reproducible-alpine -u jenkins --"

echo "============================================================================="
echo "Setting up schroot $TARGET on $HOSTNAME"...
echo "============================================================================="

# configure proxy everywhere
sudo tee "$SCHROOT_BASE/$TARGET/etc/profile.d/proxy.sh" <<-__END__
	export http_proxy=$http_proxy
	export https_proxy=$http_proxy
	export ftp_proxy=$http_proxy
	export HTTP_PROXY=$http_proxy
	export HTTPS_PROXY=$http_proxy
	export FTP_PROXY=$http_proxy
	export no_proxy="localhost,127.0.0.1"
	__END__

# install sdk
$ROOTCMD apk add alpine-sdk

# configure sudo
echo 'jenkins ALL= NOPASSWD: /sbin/apk *' | $ROOTCMD tee -a /etc/sudoers

# configure jenkins user
$ROOTCMD mkdir /var/lib/jenkins
$ROOTCMD chown -R jenkins:jenkins /var/lib/jenkins
if [ "$HOSTNAME" = "osuosl-build170-amd64" ] ; then
	# workaround for certificates that aren't valid in the future.
	# we might need to replace this with a mitm proxy in the future
	echo "insecure" | tee -a "$SCHROOT_BASE/$TARGET/var/lib/jenkins/.curlrc"
fi
$USERCMD gpg --check-trustdb # first run will create ~/.gnupg/gpg.conf
echo "keyserver-options auto-key-retrieve" | tee -a "$SCHROOT_BASE/$TARGET/var/lib/jenkins/.gnupg/gpg.conf"

# Disable SSL verification for future builds
if [ "$HOSTNAME" = "osuosl-build170-amd64" ] ; then
	export GIT_SSL_NO_VERIFY=1
fi

echo "============================================================================="
echo "schroot $TARGET set up successfully in $SCHROOT_BASE/$TARGET - exiting now."
echo "============================================================================="

# vim: set sw=0 noet :
