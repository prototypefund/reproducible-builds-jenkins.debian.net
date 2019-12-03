#!/bin/bash

# Copyright 2015-2019 Holger Levsen <holger@layer-acht.org>
#           2017-2019 kpcyrd <git@rxv.cc>
#                2017 Mattia Rizzolo <mattia@debian.org>
#                Juliana Oliveira Rodrigues <juliana.orod@gmail.com>
# released under the GPLv2

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

# fix permissions
$ROOTCMD chmod 0755 /

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
$ROOTCMD apk add alpine-sdk lua-aports gnupg bash

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

mkdir -vp "$SCHROOT_BASE/$TARGET/var/lib/jenkins/.abuild"
tee "$SCHROOT_BASE/$TARGET/var/lib/jenkins/.abuild/abuild.conf" <<-__END__
PACKAGER_PRIVKEY="/var/lib/jenkins/.abuild/build-5de527c8.rsa"
__END__
# ci keys, do not use for anything important
tee "$SCHROOT_BASE/$TARGET/var/lib/jenkins/.abuild/build-5de527c8.rsa" <<-__END__
-----BEGIN RSA PRIVATE KEY-----
MIIEogIBAAKCAQEAq95i4RZ4GfLLne18xmPSwvE9vcoIISAIbJAsjz9XR+d552TS
u7rJF3JDIbWqQ53u4P4dvPHxK3wO657KtfBjM1lf8KJbdaE993AYGdbbVbTnak5h
HStPiJ7z1t6vvbs0EWqcAOWlh1L5lhMbQFLcnsPXXnZ2aeaX9Dlz6VGJFT8Pf0MV
1ABDn8po84hl0NUFIj1cjsUDibkqI6HF7hiUinUzlo8jO26PFcVJyEPNj0Oz8kuY
686K/NR6mfvKXVYwXM/mskK6XD3YjKwblDzQQxUzJuRNWSonBQ32FDQmcVfZOoTI
4mQMDkqKt6dhxiqycX1/R3m9LsE8IlIhoQ99wQIDAQABAoIBADt7mklA14xThblA
6oBXKCikCbRX6fxc881vEJz7VR/js0Msl+q1OMfOmgFeuHDyhiyEhpJQQiHEq/1M
VegmLI8nDZdg+bp6ddHfj9fRjtPY6obWXbIUvVARg18Ib1aBJgIpHZkJ4gI163/P
WQ0oIIcqTK263jzEvC6ge8dymrkpKqCtVNnpI+ToAZ//Ni0QKGZ6tSSC7lg1jENf
ghnjADUNcQivVjBqbNBd2rR5oJ5NSspUX78spYtf2mFB0wgXVsAvfpGBe6txp5sv
Pp9xYqozpZ7Wf2Z1cIYw7laIt53HE1VCziSnwivYFTdpplJFIg3Hd65fQ6MfESqZ
6yW4l4kCgYEA3yy+sZlTTfIVd3m0pdVgyHXf4Y/otonRc6WcclHYK+3ez4F+dOl8
DZnZBhhJPFHlZBm4J7wWnUY4ZdgAydzKp3YVegZdm43Xhg+aI3P8nfJykAJ01EzI
5Zd3Z0YWnqdxB1HyP0wYf315tyGM5yMD/1v6ayM+WpAH+LW+wo3CY2MCgYEAxSXM
8kRQev5zkOLZhtMLb9EC2rDwFm2LEW2ocd1uDNRS9usB7lE30EE5xJNI5+AkoCo1
j3B0CyXyRHbmhmfp7OempF7JAPROrS1gxg0naQORU2i9aiOwNGhbenkSMnUQi3of
D5YX0zk60TMFWo/hSLW9hrN97iOgF12NajsCjYsCgYAw7zy48GeltakjU1pa6liY
W9BFQyrBq6JzeyK8plmB+Fxcn4Y82F1NFijR/00/nq1vr3wDqmhC//ypyB0UJgeB
hJDc+rxXuVhCmvUvROVlNJ4OGZvIWTXLsdSKnoGjNA/CjSNS4bqVacvgbcjZfYII
4gAcsdOgQ+ibji5PtomjBQKBgDy3n58dmwvGQiFlPElhxivx20cvJ0JBCoubkj0/
TR12ZvbU+gtDyETDUd9Q3StMxPrvBP/gSl0EmtCrLeRHLKxhy9jjuFQq6fA8AYn9
kx2sk510rKF7zFDXsxTNJOWVWDscqWRLfZr4DT1Q0V1K4r9Z+bz6mtY08qE/lsYY
1nhxAoGATFF1Ng7AQMcytiT1nSQjB/A/3C5hzCula7J1ErL+wc0zOS4oenmL2ESI
IKDt71BfGgXZHy1AKMv+0x1Wk2hOXC2fSxG46lIPD0msR2207+c7ZgVuyARmSDO3
Y/5yyssrctGJ8bNs+++uUhr8yG9CXBG9uSG3gvtCXxOgwg43lTk=
-----END RSA PRIVATE KEY-----
__END__
tee "$SCHROOT_BASE/$TARGET/var/lib/jenkins/.abuild/build-5de527c8.rsa.pub" <<-__END__
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAq95i4RZ4GfLLne18xmPS
wvE9vcoIISAIbJAsjz9XR+d552TSu7rJF3JDIbWqQ53u4P4dvPHxK3wO657KtfBj
M1lf8KJbdaE993AYGdbbVbTnak5hHStPiJ7z1t6vvbs0EWqcAOWlh1L5lhMbQFLc
nsPXXnZ2aeaX9Dlz6VGJFT8Pf0MV1ABDn8po84hl0NUFIj1cjsUDibkqI6HF7hiU
inUzlo8jO26PFcVJyEPNj0Oz8kuY686K/NR6mfvKXVYwXM/mskK6XD3YjKwblDzQ
QxUzJuRNWSonBQ32FDQmcVfZOoTI4mQMDkqKt6dhxiqycX1/R3m9LsE8IlIhoQ99
wQIDAQAB
-----END PUBLIC KEY-----
__END__

# Disable SSL verification for future builds
if [ "$HOSTNAME" = "osuosl-build170-amd64" ] ; then
	GIT_OPTIONS='GIT_SSL_NO_VERIFY=1'
fi

echo "$(date -u) - cloning aports repo"
$USERCMD sh -c "$GIT_OPTIONS git clone https://git.alpinelinux.org/aports.git /var/lib/jenkins/aports"

echo "============================================================================="
echo "schroot $TARGET set up successfully in $SCHROOT_BASE/$TARGET - exiting now."
echo "============================================================================="

# vim: set sw=0 noet :
