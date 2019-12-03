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
$USERCMD sh -c "cd /var/lib/jenkins/aports/main/abuild && base64 -d | git apply - && PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' abuild -r && sudo /sbin/apk add ~/packages/main/x86_64/abuild-3.5.0_rc2-r1.apk && git checkout ." <<-__END__
ZGlmZiAtLWdpdCBhL21haW4vYWJ1aWxkLzAwMDItcmVwcm8ucGF0Y2ggYi9tYWluL2FidWlsZC8w
MDAyLXJlcHJvLnBhdGNoCm5ldyBmaWxlIG1vZGUgMTAwNjQ0CmluZGV4IDAwMDAwMDAwLi41ZmYy
MjAxMwotLS0gL2Rldi9udWxsCisrKyBiL21haW4vYWJ1aWxkLzAwMDItcmVwcm8ucGF0Y2gKQEAg
LTAsMCArMSw1MyBAQAorRnJvbSBiNTE0YTRlNTZkNGQxN2RhNTNiYmU1YTJkMjAzZjYxNmY5YTlm
MzcxIE1vbiBTZXAgMTcgMDA6MDA6MDAgMjAwMQorRnJvbToga3BjeXJkIDxnaXRAcnh2LmNjPgor
RGF0ZTogTW9uLCAyIERlYyAyMDE5IDE4OjA5OjU2ICswMTAwCitTdWJqZWN0OiBbUEFUQ0hdIGFi
dWlsZDogc2V0IGZpeGVkIGF0aW1lIGFuZCBjdGltZSBpbiB0YXIKKworLS0tCisgYWJ1aWxkLmlu
IHwgMTYgKysrKysrKysrKysrLS0tLQorIDEgZmlsZSBjaGFuZ2VkLCAxMiBpbnNlcnRpb25zKCsp
LCA0IGRlbGV0aW9ucygtKQorCitkaWZmIC0tZ2l0IGEvYWJ1aWxkLmluIGIvYWJ1aWxkLmluCitp
bmRleCA1NjU0ZDhmLi42NDRkZWE4IDEwMDY0NAorLS0tIGEvYWJ1aWxkLmluCisrKysgYi9hYnVp
bGQuaW4KK0BAIC0xNTc5LDcgKzE1NzksMTEgQEAgY3JlYXRlX2Fwa3MoKSB7CisgCQkjIG5vcm1h
bGl6ZSB0aW1lc3RhbXBzCisgCQlmaW5kIC4gLWV4ZWMgdG91Y2ggLWggLWQgIkAkU09VUkNFX0RB
VEVfRVBPQ0giIHt9ICsKKyAKKy0JCXRhciAtLXhhdHRycyAtZiAtIC1jICIkQCIgfCBhYnVpbGQt
dGFyIC0taGFzaCB8ICRnemlwIC05ID4iJGRpciIvZGF0YS50YXIuZ3oKKysJCXRhciAtLXhhdHRy
cyBcCisrCQkJLS1mb3JtYXQ9cG9zaXggXAorKwkJCS0tcGF4LW9wdGlvbj1leHRoZHIubmFtZT0l
ZC9QYXhIZWFkZXJzLyVmLGF0aW1lOj0wLGN0aW1lOj0wIFwKKysJCQktLW10aW1lPSJAJHtTT1VS
Q0VfREFURV9FUE9DSH0iIFwKKysJCQktZiAtIC1jICIkQCIgfCBhYnVpbGQtdGFyIC0taGFzaCB8
ICRnemlwIC1uIC05ID4iJGRpciIvZGF0YS50YXIuZ3oKKyAKKyAJCW1zZyAiQ3JlYXRlIGNoZWNr
c3VtLi4uIgorIAkJIyBhcHBlbmQgdGhlIGhhc2ggZm9yIGRhdGEudGFyLmd6CitAQCAtMTU4OSw4
ICsxNTkzLDEyIEBAIGNyZWF0ZV9hcGtzKCkgeworIAorIAkJIyBjb250cm9sLnRhci5negorIAkJ
Y2QgIiRkaXIiCistCQl0YXIgLWYgLSAtYyAkKGNhdCAiJGRpciIvLm1ldGFmaWxlcykgfCBhYnVp
bGQtdGFyIC0tY3V0IFwKKy0JCQl8ICRnemlwIC05ID4gY29udHJvbC50YXIuZ3oKKysJCXRhciBc
CisrCQkJLS1mb3JtYXQ9cG9zaXggXAorKwkJCS0tcGF4LW9wdGlvbj1leHRoZHIubmFtZT0lZC9Q
YXhIZWFkZXJzLyVmLGF0aW1lOj0wLGN0aW1lOj0wIFwKKysJCQktLW10aW1lPSJAJHtTT1VSQ0Vf
REFURV9FUE9DSH0iIFwKKysJCQktZiAtIC1jICQoY2F0ICIkZGlyIi8ubWV0YWZpbGVzKSB8IGFi
dWlsZC10YXIgLS1jdXQgXAorKwkJCXwgJGd6aXAgLW4gLTkgPiBjb250cm9sLnRhci5negorIAkJ
YWJ1aWxkLXNpZ24gLXEgY29udHJvbC50YXIuZ3ogfHwgZXhpdCAxCisgCisgCQltc2cgIkNyZWF0
ZSAkYXBrIgorQEAgLTE3MjQsNyArMTczMiw3IEBAIGRlZmF1bHRfZG9jKCkgeworIAkJCWZpCisg
CQlkb25lCisgCistCQlbICRpc2xpbmsgLWVxIDAgXSAmJiAkZ3ppcCAtOSAiJG5hbWUiCisrCQlb
ICRpc2xpbmsgLWVxIDAgXSAmJiAkZ3ppcCAtbiAtOSAiJG5hbWUiCisgCWRvbmUKKyAKKyAJcm0g
LWYgIiRzdWJwa2dkaXIvdXNyL3NoYXJlL2luZm8vZGlyIgorLS0gCisyLjIyLjAKKwpkaWZmIC0t
Z2l0IGEvbWFpbi9hYnVpbGQvQVBLQlVJTEQgYi9tYWluL2FidWlsZC9BUEtCVUlMRAppbmRleCBj
OGI5YTMwYS4uOGU5MWM0MDEgMTAwNjQ0Ci0tLSBhL21haW4vYWJ1aWxkL0FQS0JVSUxECisrKyBi
L21haW4vYWJ1aWxkL0FQS0JVSUxECkBAIC0yMiw2ICsyMiw3IEBAIG9wdGlvbnM9InN1aWQgIWNo
ZWNrIgogcGtnZ3JvdXBzPSJhYnVpbGQiCiBzb3VyY2U9Imh0dHBzOi8vZGV2LmFscGluZWxpbnV4
Lm9yZy9hcmNoaXZlL2FidWlsZC9hYnVpbGQtJF92ZXIudGFyLnh6CiAJMDAwMS1hYnVpbGQtZml4
LWFwcGx5aW5nLXBhdGNoZXMtZnJvbS1odHRwcy5wYXRjaAorCTAwMDItcmVwcm8ucGF0Y2gKIAki
CiAKIGJ1aWxkZGlyPSIkc3JjZGlyLyRwa2duYW1lLSRfdmVyIgpAQCAtNzAsNCArNzEsNSBAQCBf
cm9vdGJsZCgpIHsKIH0KIAogc2hhNTEyc3Vtcz0iN2MzMTdkNzVmOGZhNjRhYzJhMDY3NDg3M2Vk
YzkzN2JjZDhmYjNkMzIyZTVjZGYxMDg3NGZlNWVjODdmZWMwZWJlM2ExZDI5ZDUwZTkxOTM3NmIx
MDEzNWQyNTI2NTkzNzJmZmI2MmUwODQxODE1ODE0NjczNGZkMTNmNDY2MDIgIGFidWlsZC0zLjUu
MF9yYzIudGFyLnh6Ci03YjU2NTQ4MWE4NWE3MDk0YTlmNjFmMzllZTQ0YmEzYzFmM2Q1YmZlZWQ3
YTUyNzljNTdjMTQ0NDdlOTRmNjViNjEzZDU2ZDI2ZDE5NzYzOWFiMjgwNzQ1ZTQ4YzUxZmY3OTE1
ZmQwNTcwYTU3MGQyOWRkN2UyNDkwYjI5OGRjNyAgMDAwMS1hYnVpbGQtZml4LWFwcGx5aW5nLXBh
dGNoZXMtZnJvbS1odHRwcy5wYXRjaCIKKzdiNTY1NDgxYTg1YTcwOTRhOWY2MWYzOWVlNDRiYTNj
MWYzZDViZmVlZDdhNTI3OWM1N2MxNDQ0N2U5NGY2NWI2MTNkNTZkMjZkMTk3NjM5YWIyODA3NDVl
NDhjNTFmZjc5MTVmZDA1NzBhNTcwZDI5ZGQ3ZTI0OTBiMjk4ZGM3ICAwMDAxLWFidWlsZC1maXgt
YXBwbHlpbmctcGF0Y2hlcy1mcm9tLWh0dHBzLnBhdGNoCisxMThhYzUxMjU4OGRkZWUzMTJkNmZm
YTZhMjU3ZTFjMjUyNDcxNDMzY2I5N2VjMzJmN2Q3YmY4MzljNDU2MGQ4ZWM5ZTM2Zjc1NzMxMDli
YTU2ZWI3YTAyZmMyMjYyYWNkZDNjNzg1ZTEwMDg5MzVmYWM1OTlkNzNlMmZlOTkzMCAgMDAwMi1y
ZXByby5wYXRjaCIK
__END__

echo "============================================================================="
echo "schroot $TARGET set up successfully in $SCHROOT_BASE/$TARGET - exiting now."
echo "============================================================================="

# vim: set sw=0 noet :
