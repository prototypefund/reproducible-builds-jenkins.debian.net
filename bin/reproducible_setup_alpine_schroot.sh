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
	GIT_OPTIONS='GIT_SSL_NO_VERIFY=1'
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

echo "$(date -u) - cloning aports repo"
$USERCMD sh -c "$GIT_OPTIONS git clone --depth=1 https://git.alpinelinux.org/aports.git /var/lib/jenkins/aports"

# build and install a patched abuild
# FIXME: this abuild patch crap and must go
$USERCMD sh -c "cd /var/lib/jenkins/aports/main/abuild && base64 -d | git apply - && PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' abuild -r && sudo /sbin/apk add --allow-untrusted ~/packages/main/x86_64/abuild-3.5.0_rc2-r1.apk && git checkout ." <<-__END__
ZGlmZiAtLWdpdCBhL21haW4vYWJ1aWxkLzAwMDItcmVwcm8ucGF0Y2ggYi9tYWluL2FidWlsZC8w
MDAyLXJlcHJvLnBhdGNoCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwLi40Njc3
ODQwNgotLS0gL2Rldi9udWxsCisrKyBiL21haW4vYWJ1aWxkLzAwMDItcmVwcm8ucGF0Y2gKQEAg
LTAsMCArMSw3NyBAQAorY29tbWl0IGI1MTRhNGU1NmQ0ZDE3ZGE1M2JiZTVhMmQyMDNmNjE2Zjlh
OWYzNzEKK0F1dGhvcjoga3BjeXJkIDxnaXRAcnh2LmNjPgorRGF0ZTogICBNb24gRGVjIDIgMTg6
MDk6NTYgMjAxOSArMDEwMAorCisgICAgYWJ1aWxkOiBzZXQgZml4ZWQgYXRpbWUgYW5kIGN0aW1l
IGluIHRhcgorCitkaWZmIC0tZ2l0IGEvYWJ1aWxkLmluIGIvYWJ1aWxkLmluCitpbmRleCA1NjU0
ZDhmLi42NDRkZWE4IDEwMDY0NAorLS0tIGEvYWJ1aWxkLmluCisrKysgYi9hYnVpbGQuaW4KK0BA
IC0xNTc5LDcgKzE1NzksMTEgQEAgY3JlYXRlX2Fwa3MoKSB7CisgCQkjIG5vcm1hbGl6ZSB0aW1l
c3RhbXBzCisgCQlmaW5kIC4gLWV4ZWMgdG91Y2ggLWggLWQgIkAkU09VUkNFX0RBVEVfRVBPQ0gi
IHt9ICsKKyAKKy0JCXRhciAtLXhhdHRycyAtZiAtIC1jICIkQCIgfCBhYnVpbGQtdGFyIC0taGFz
aCB8ICRnemlwIC05ID4iJGRpciIvZGF0YS50YXIuZ3oKKysJCXRhciAtLXhhdHRycyBcCisrCQkJ
LS1mb3JtYXQ9cG9zaXggXAorKwkJCS0tcGF4LW9wdGlvbj1leHRoZHIubmFtZT0lZC9QYXhIZWFk
ZXJzLyVmLGF0aW1lOj0wLGN0aW1lOj0wIFwKKysJCQktLW10aW1lPSJAJHtTT1VSQ0VfREFURV9F
UE9DSH0iIFwKKysJCQktZiAtIC1jICIkQCIgfCBhYnVpbGQtdGFyIC0taGFzaCB8ICRnemlwIC1u
IC05ID4iJGRpciIvZGF0YS50YXIuZ3oKKyAKKyAJCW1zZyAiQ3JlYXRlIGNoZWNrc3VtLi4uIgor
IAkJIyBhcHBlbmQgdGhlIGhhc2ggZm9yIGRhdGEudGFyLmd6CitAQCAtMTU4OSw4ICsxNTkzLDEy
IEBAIGNyZWF0ZV9hcGtzKCkgeworIAorIAkJIyBjb250cm9sLnRhci5negorIAkJY2QgIiRkaXIi
CistCQl0YXIgLWYgLSAtYyAkKGNhdCAiJGRpciIvLm1ldGFmaWxlcykgfCBhYnVpbGQtdGFyIC0t
Y3V0IFwKKy0JCQl8ICRnemlwIC05ID4gY29udHJvbC50YXIuZ3oKKysJCXRhciBcCisrCQkJLS1m
b3JtYXQ9cG9zaXggXAorKwkJCS0tcGF4LW9wdGlvbj1leHRoZHIubmFtZT0lZC9QYXhIZWFkZXJz
LyVmLGF0aW1lOj0wLGN0aW1lOj0wIFwKKysJCQktLW10aW1lPSJAJHtTT1VSQ0VfREFURV9FUE9D
SH0iIFwKKysJCQktZiAtIC1jICQoY2F0ICIkZGlyIi8ubWV0YWZpbGVzKSB8IGFidWlsZC10YXIg
LS1jdXQgXAorKwkJCXwgJGd6aXAgLW4gLTkgPiBjb250cm9sLnRhci5negorIAkJYWJ1aWxkLXNp
Z24gLXEgY29udHJvbC50YXIuZ3ogfHwgZXhpdCAxCisgCisgCQltc2cgIkNyZWF0ZSAkYXBrIgor
QEAgLTE3MjQsNyArMTczMiw3IEBAIGRlZmF1bHRfZG9jKCkgeworIAkJCWZpCisgCQlkb25lCisg
CistCQlbICRpc2xpbmsgLWVxIDAgXSAmJiAkZ3ppcCAtOSAiJG5hbWUiCisrCQlbICRpc2xpbmsg
LWVxIDAgXSAmJiAkZ3ppcCAtbiAtOSAiJG5hbWUiCisgCWRvbmUKKyAKKyAJcm0gLWYgIiRzdWJw
a2dkaXIvdXNyL3NoYXJlL2luZm8vZGlyIgorCitjb21taXQgODBjYTViYmQ4OTYxNDZjODg1NDAz
ODM1MDYxYWFjY2FkMTNjYmViYgorQXV0aG9yOiBrcGN5cmQgPGdpdEByeHYuY2M+CitEYXRlOiAg
IFR1ZSBEZWMgMyAyMTozMTo0NCAyMDE5ICswMTAwCisKKyAgICBhYnVpbGQ6IGV4cGxpY2l0bHkg
c29ydCBhcGsgY29udGVudAorCitkaWZmIC0tZ2l0IGEvYWJ1aWxkLmluIGIvYWJ1aWxkLmluCitp
bmRleCA2NDRkZWE4Li5hZGQ2MWE2IDEwMDY0NAorLS0tIGEvYWJ1aWxkLmluCisrKysgYi9hYnVp
bGQuaW4KK0BAIC0xNTc3LDEzICsxNTc3LDE1IEBAIGNyZWF0ZV9hcGtzKCkgeworIAkJZmkKKyAK
KyAJCSMgbm9ybWFsaXplIHRpbWVzdGFtcHMKKy0JCWZpbmQgLiAtZXhlYyB0b3VjaCAtaCAtZCAi
QCRTT1VSQ0VfREFURV9FUE9DSCIge30gKworKwkJZmluZCAiJEAiIC1leGVjIHRvdWNoIC1oIC1k
ICJAJFNPVVJDRV9EQVRFX0VQT0NIIiB7fSArCisgCistCQl0YXIgLS14YXR0cnMgXAorKwkJIyBl
eHBsaWNpdGx5IHNvcnQgcGFja2FnZSBjb250ZW50CisrCQlmaW5kICIkQCIgLXByaW50MCB8IExD
X0FMTD1DIHNvcnQgLXogfCB0YXIgLS14YXR0cnMgXAorIAkJCS0tZm9ybWF0PXBvc2l4IFwKKyAJ
CQktLXBheC1vcHRpb249ZXh0aGRyLm5hbWU9JWQvUGF4SGVhZGVycy8lZixhdGltZTo9MCxjdGlt
ZTo9MCBcCisgCQkJLS1tdGltZT0iQCR7U09VUkNFX0RBVEVfRVBPQ0h9IiBcCistCQkJLWYgLSAt
YyAiJEAiIHwgYWJ1aWxkLXRhciAtLWhhc2ggfCAkZ3ppcCAtbiAtOSA+IiRkaXIiL2RhdGEudGFy
Lmd6CisrCQkJLS1uby1yZWN1cnNpb24gLS1udWxsIC1UIC0gXAorKwkJCS1mIC0gLWMgfCBhYnVp
bGQtdGFyIC0taGFzaCB8ICRnemlwIC1uIC05ID4iJGRpciIvZGF0YS50YXIuZ3oKKyAKKyAJCW1z
ZyAiQ3JlYXRlIGNoZWNrc3VtLi4uIgorIAkJIyBhcHBlbmQgdGhlIGhhc2ggZm9yIGRhdGEudGFy
Lmd6CmRpZmYgLS1naXQgYS9tYWluL2FidWlsZC9BUEtCVUlMRCBiL21haW4vYWJ1aWxkL0FQS0JV
SUxECmluZGV4IGM4YjlhMzBhLi5kMzExZTYwOSAxMDA2NDQKLS0tIGEvbWFpbi9hYnVpbGQvQVBL
QlVJTEQKKysrIGIvbWFpbi9hYnVpbGQvQVBLQlVJTEQKQEAgLTIyLDYgKzIyLDcgQEAgb3B0aW9u
cz0ic3VpZCAhY2hlY2siCiBwa2dncm91cHM9ImFidWlsZCIKIHNvdXJjZT0iaHR0cHM6Ly9kZXYu
YWxwaW5lbGludXgub3JnL2FyY2hpdmUvYWJ1aWxkL2FidWlsZC0kX3Zlci50YXIueHoKIAkwMDAx
LWFidWlsZC1maXgtYXBwbHlpbmctcGF0Y2hlcy1mcm9tLWh0dHBzLnBhdGNoCisJMDAwMi1yZXBy
by5wYXRjaAogCSIKIAogYnVpbGRkaXI9IiRzcmNkaXIvJHBrZ25hbWUtJF92ZXIiCkBAIC03MCw0
ICs3MSw1IEBAIF9yb290YmxkKCkgewogfQogCiBzaGE1MTJzdW1zPSI3YzMxN2Q3NWY4ZmE2NGFj
MmEwNjc0ODczZWRjOTM3YmNkOGZiM2QzMjJlNWNkZjEwODc0ZmU1ZWM4N2ZlYzBlYmUzYTFkMjlk
NTBlOTE5Mzc2YjEwMTM1ZDI1MjY1OTM3MmZmYjYyZTA4NDE4MTU4MTQ2NzM0ZmQxM2Y0NjYwMiAg
YWJ1aWxkLTMuNS4wX3JjMi50YXIueHoKLTdiNTY1NDgxYTg1YTcwOTRhOWY2MWYzOWVlNDRiYTNj
MWYzZDViZmVlZDdhNTI3OWM1N2MxNDQ0N2U5NGY2NWI2MTNkNTZkMjZkMTk3NjM5YWIyODA3NDVl
NDhjNTFmZjc5MTVmZDA1NzBhNTcwZDI5ZGQ3ZTI0OTBiMjk4ZGM3ICAwMDAxLWFidWlsZC1maXgt
YXBwbHlpbmctcGF0Y2hlcy1mcm9tLWh0dHBzLnBhdGNoIgorN2I1NjU0ODFhODVhNzA5NGE5ZjYx
ZjM5ZWU0NGJhM2MxZjNkNWJmZWVkN2E1Mjc5YzU3YzE0NDQ3ZTk0ZjY1YjYxM2Q1NmQyNmQxOTc2
MzlhYjI4MDc0NWU0OGM1MWZmNzkxNWZkMDU3MGE1NzBkMjlkZDdlMjQ5MGIyOThkYzcgIDAwMDEt
YWJ1aWxkLWZpeC1hcHBseWluZy1wYXRjaGVzLWZyb20taHR0cHMucGF0Y2gKKzQ1MWI0MjBmYjA5
ODc3YjE4OGYyOTNiYjUyNDBkMmMyMjJlOTA3MjJkMjhkMDVkZWU1NThjODMzNDYxZjJkNmM0MGRi
NzcyYWUyZmU1YzlkZmYxYWE4NTM0ZjM2MGUwZDFkNmU5MDdkYTY0ZGI3OTE5Y2FlNTNhNTlhY2Jl
ZmYwICAwMDAyLXJlcHJvLnBhdGNoIgo=
__END__

echo "============================================================================="
echo "schroot $TARGET set up successfully in $SCHROOT_BASE/$TARGET - exiting now."
echo "============================================================================="

# vim: set sw=0 noet :
