#!/bin/bash

# Copyright 2015-2019 Holger Levsen <holger@layer-acht.org>
#                2017 kpcyrd <git@rxv.cc>
#                2017 Mattia Rizzolo <mattia@debian.org>
#                Juliana Oliveira Rodrigues <juliana.orod@gmail.com>
# released under the GPLv2

#
# downloads an archlinux bootstrap chroot archive, then turns it into an schroot,
# then configures pacman.
#

set -e

DEBUG=true
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

# define archlinux mirror to be used
ARCHLINUX_MIRROR=http://mirror.one.com/archlinux/

bootstrap() {
	# define URL for bootstrap.tgz
	BOOTSTRAP_BASE="$ARCHLINUX_MIRROR/iso/"
	echo "$(date -u) - downloading Arch Linux latest/sha1sums.txt"
	BOOTSTRAP_DATE=$(curl -sSf $BOOTSTRAP_BASE/latest/sha1sums.txt | grep x86_64.tar.gz | cut -d " " -f3 | cut -d "-" -f3 | egrep -o '[0-9.]{10}')
	if [ -z $BOOTSTRAP_DATE ] ; then
		echo "Cannot determine version of bootstrap file, aborting."
		curl -sSf "$BOOTSTRAP_BASE/latest/sha1sums.txt" | grep x86_64.tar.gz
		exit 1
	fi

	if [ -f "archlinux-bootstrap-$BOOTSTRAP_DATE-x86_64.tar.gz" ]; then
		rm "archlinux-bootstrap-$BOOTSTRAP_DATE-x86_64.tar.gz"
	fi
	if [ ! -f "archlinux-bootstrap-$BOOTSTRAP_DATE-x86_64.tar.gz" ]; then
		BOOTSTRAP_TAR_GZ="$BOOTSTRAP_DATE/archlinux-bootstrap-$BOOTSTRAP_DATE-x86_64.tar.gz"
		echo "$(date -u) - downloading Arch Linux bootstrap.tar.gz."

		curl -fO "$BOOTSTRAP_BASE/$BOOTSTRAP_TAR_GZ"
		sudo rm -rf --one-file-system "$SCHROOT_BASE/root.x86_64/"
		sudo tar xzf archlinux-bootstrap-$BOOTSTRAP_DATE-x86_64.tar.gz -C $SCHROOT_BASE

		if [ -d "$SCHROOT_BASE/$TARGET" ] ; then
			mv "$SCHROOT_BASE/$TARGET" "$SCHROOT_BASE/$TARGET.old"
			sudo rm -rf --one-file-system "$SCHROOT_BASE/$TARGET.old"
		fi
		mv $SCHROOT_BASE/root.x86_64 $SCHROOT_BASE/$TARGET

		rm archlinux-bootstrap-$BOOTSTRAP_DATE-x86_64.tar.gz
	fi

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
	# mktemp creates directories with 700 perms
	#chmod 755 $SCHROOT_BASE/$TARGET
}

cleanup() {
	if [ -d $SCHROOT_TARGET ]; then
		rm -rf --one-file-system $SCHROOT_TARGET || ( echo "Warning: $SCHROOT_TARGET could not be fully removed on forced cleanup." ; ls $SCHROOT_TARGET -la )
	fi
	rm -f $TMPLOG
	exit 1
}

#SCHROOT_TARGET=$(mktemp -d -p $SCHROOT_BASE/ archlinuxrb-setup-$TARGET-XXXX)
trap cleanup INT TERM EXIT
TARGET=reproducible-archlinux
bootstrap
trap - INT TERM EXIT

ROOTCMD="schroot --directory /tmp -c source:jenkins-reproducible-archlinux -u root --"
USERCMD="schroot --directory /tmp -c source:jenkins-reproducible-archlinux -u jenkins --"

echo "============================================================================="
echo "Setting up schroot $TARGET on $HOSTNAME"...
echo "============================================================================="

# configure proxy everywhere
sudo tee $SCHROOT_BASE/$TARGET/etc/profile.d/proxy.sh <<-__END__
	export http_proxy=$http_proxy
	export https_proxy=$http_proxy
	export ftp_proxy=$http_proxy
	export HTTP_PROXY=$http_proxy
	export HTTPS_PROXY=$http_proxy
	export FTP_PROXY=$http_proxy
	export no_proxy="localhost,127.0.0.1"
	__END__
sudo chmod +x $SCHROOT_BASE/$TARGET/etc/profile.d/proxy.sh
sudo sed -i "s|^#XferCommand = /usr/bin/curl |XferCommand = /usr/bin/curl --proxy $http_proxy |" "$SCHROOT_BASE/$TARGET/etc/pacman.conf"

# configure root user to use this for shells and login shells…
echo ". /etc/profile.d/proxy.sh" | sudo tee -a $SCHROOT_BASE/$TARGET/root/.bashrc

# configure pacman
$ROOTCMD bash -l -c 'pacman-key --init'
$ROOTCMD bash -l -c 'pacman-key --populate archlinux'
# use a specific mirror
echo "Server = $ARCHLINUX_MIRROR/\$repo/os/\$arch" | $ROOTCMD tee -a /etc/pacman.d/mirrorlist
# enable multilib (by uncommenting the first two lines starting with the [multilib] section header)
sudo sed -i '/\[multilib\]/,+1{s/^#//}' $SCHROOT_BASE/$TARGET/etc/pacman.conf
if [ "$HOSTNAME" = "osuosl-build170-amd64" ] ; then
	# disable signature verification so packages won't fail to install when setting the time to +$x years
	sudo sed -i -E 's/^#?SigLevel\s*=.*/SigLevel = Never/g' "$SCHROOT_BASE/$TARGET/etc/pacman.conf"
	sudo sed -i "/^XferCommand = /{s|/usr/bin/curl |/usr/bin/curl --insecure |}" "$SCHROOT_BASE/$TARGET/etc/pacman.conf"
fi

echo "============================================================================="
echo "Current configuration values follow:"
echo "============================================================================="
$ROOTCMD cat /etc/pacman.conf
echo "============================================================================="
$ROOTCMD cat /etc/makepkg.conf
echo "============================================================================="

$ROOTCMD bash -l -c 'pacman -Syu --noconfirm'
$ROOTCMD bash -l -c 'pacman -S --noconfirm --needed base-devel multilib-devel devtools fakechroot asciidoc asp expac dash'
# configure sudo
echo 'jenkins ALL= NOPASSWD: /usr/sbin/pacman *' | $ROOTCMD tee -a /etc/sudoers

# configure jenkins user
$ROOTCMD mkdir /var/lib/jenkins
$ROOTCMD chown -R jenkins:jenkins /var/lib/jenkins
echo ". /etc/profile.d/proxy.sh" | tee -a $SCHROOT_BASE/$TARGET/var/lib/jenkins/.bashrc
if [ "$HOSTNAME" = "osuosl-build170-amd64" ] ; then
	# workaround for certificates that aren't valid in the future.
	# we might need to replace this with a mitm proxy in the future
	echo "insecure" | tee -a $SCHROOT_BASE/$TARGET/var/lib/jenkins/.curlrc
fi
$USERCMD bash -l -c 'gpg --check-trustdb' # first run will create ~/.gnupg/gpg.conf
echo "keyserver-options auto-key-retrieve" | tee -a $SCHROOT_BASE/$TARGET/var/lib/jenkins/.gnupg/gpg.conf

# Disable SSL verification for future builds
if [ "$HOSTNAME" = "osuosl-build170-amd64" ] ; then
	export GIT_SSL_NO_VERIFY=1
fi

$ROOTCMD sed -i 's/^#PACKAGER\s*=.*/PACKAGER="Reproducible Arch Linux tests <reproducible@archlinux.org>"/' /etc/makepkg.conf

$ROOTCMD sed -i "s|^#XferCommand = /usr/bin/curl |XferCommand = /usr/bin/curl --proxy $http_proxy |" /etc/pacman.conf
if [ "$HOSTNAME" = "osuosl-build170-amd64" ] ; then
	# disable signature verification so packages won't fail to install when setting the time to +$x years
	$ROOTCMD sed -i -E 's/^#?SigLevel\s*=.*/SigLevel = Never/g' /etc/pacman.conf
	$ROOTCMD sed -i "/^XferCommand = /{s|/usr/bin/curl |/usr/bin/curl --insecure |}" /etc/pacman.conf
	# Disable SSL cert checking for future builds
	$ROOTCMD sed -i "s|/usr/bin/curl |/usr/bin/curl -k |" /etc/makepkg.conf
fi

echo "============================================================================="
echo "Final configuration values follow:"
echo "============================================================================="
$ROOTCMD cat /etc/pacman.conf
echo "============================================================================="
$ROOTCMD cat /etc/makepkg.conf
echo "============================================================================="
echo "schroot $TARGET set up successfully in $SCHROOT_BASE/$TARGET - exiting now."
echo "============================================================================="

# vim: set sw=0 noet :
