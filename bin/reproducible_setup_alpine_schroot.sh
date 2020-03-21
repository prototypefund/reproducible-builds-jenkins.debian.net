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
$USERCMD sh -c "cd /var/lib/jenkins/aports/main/abuild && git apply - && PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' abuild -r && sudo /sbin/apk add --allow-untrusted ~/packages/main/x86_64/abuild-3.5.0_rc2-r1.apk && git checkout ." <<-__END__
diff --git a/main/abuild/0002-repro.patch b/main/abuild/0002-repro.patch
new file mode 100644
index 00000000..46778406
--- /dev/null
+++ b/main/abuild/0002-repro.patch
@@ -0,0 +1,77 @@
+commit b514a4e56d4d17da53bbe5a2d203f616f9a9f371
+Author: kpcyrd <git@rxv.cc>
+Date:   Mon Dec 2 18:09:56 2019 +0100
+
+    abuild: set fixed atime and ctime in tar
+
+diff --git a/abuild.in b/abuild.in
+index 5654d8f..644dea8 100644
+--- a/abuild.in
++++ b/abuild.in
+@@ -1579,7 +1579,11 @@ create_apks() {
+ 		# normalize timestamps
+ 		find . -exec touch -h -d "@\$SOURCE_DATE_EPOCH" {} +
+ 
+-		tar --xattrs -f - -c "\$@" | abuild-tar --hash | \$gzip -9 >"\$dir"/data.tar.gz
++		tar --xattrs \
++			--format=posix \
++			--pax-option=exthdr.name=%d/PaxHeaders/%f,atime:=0,ctime:=0 \
++			--mtime="@\${SOURCE_DATE_EPOCH}" \
++			-f - -c "\$@" | abuild-tar --hash | \$gzip -n -9 >"\$dir"/data.tar.gz
+ 
+ 		msg "Create checksum..."
+ 		# append the hash for data.tar.gz
+@@ -1589,8 +1593,12 @@ create_apks() {
+ 
+ 		# control.tar.gz
+ 		cd "\$dir"
+-		tar -f - -c \$(cat "\$dir"/.metafiles) | abuild-tar --cut \
+-			| \$gzip -9 > control.tar.gz
++		tar \
++			--format=posix \
++			--pax-option=exthdr.name=%d/PaxHeaders/%f,atime:=0,ctime:=0 \
++			--mtime="@\${SOURCE_DATE_EPOCH}" \
++			-f - -c \$(cat "\$dir"/.metafiles) | abuild-tar --cut \
++			| \$gzip -n -9 > control.tar.gz
+ 		abuild-sign -q control.tar.gz || exit 1
+ 
+ 		msg "Create \$apk"
+@@ -1724,7 +1732,7 @@ default_doc() {
+ 			fi
+ 		done
+ 
+-		[ \$islink -eq 0 ] && \$gzip -9 "\$name"
++		[ \$islink -eq 0 ] && \$gzip -n -9 "\$name"
+ 	done
+ 
+ 	rm -f "\$subpkgdir/usr/share/info/dir"
+
+commit 80ca5bbd896146c885403835061aaccad13cbebb
+Author: kpcyrd <git@rxv.cc>
+Date:   Tue Dec 3 21:31:44 2019 +0100
+
+    abuild: explicitly sort apk content
+
+diff --git a/abuild.in b/abuild.in
+index 644dea8..add61a6 100644
+--- a/abuild.in
++++ b/abuild.in
+@@ -1577,13 +1577,15 @@ create_apks() {
+ 		fi
+ 
+ 		# normalize timestamps
+-		find . -exec touch -h -d "@\$SOURCE_DATE_EPOCH" {} +
++		find "\$@" -exec touch -h -d "@\$SOURCE_DATE_EPOCH" {} +
+ 
+-		tar --xattrs \
++		# explicitly sort package content
++		find "\$@" -print0 | LC_ALL=C sort -z | tar --xattrs \
+ 			--format=posix \
+ 			--pax-option=exthdr.name=%d/PaxHeaders/%f,atime:=0,ctime:=0 \
+ 			--mtime="@\${SOURCE_DATE_EPOCH}" \
+-			-f - -c "\$@" | abuild-tar --hash | \$gzip -n -9 >"\$dir"/data.tar.gz
++			--no-recursion --null -T - \
++			-f - -c | abuild-tar --hash | \$gzip -n -9 >"\$dir"/data.tar.gz
+ 
+ 		msg "Create checksum..."
+ 		# append the hash for data.tar.gz
diff --git a/main/abuild/APKBUILD b/main/abuild/APKBUILD
index c8b9a30a..d311e609 100644
--- a/main/abuild/APKBUILD
+++ b/main/abuild/APKBUILD
@@ -22,6 +22,7 @@ options="suid !check"
 pkggroups="abuild"
 source="https://dev.alpinelinux.org/archive/abuild/abuild-\$_ver.tar.xz
 	0001-abuild-fix-applying-patches-from-https.patch
+	0002-repro.patch
 	"
 
 builddir="\$srcdir/\$pkgname-\$_ver"
@@ -70,4 +71,5 @@ _rootbld() {
 }
 
 sha512sums="7c317d75f8fa64ac2a0674873edc937bcd8fb3d322e5cdf10874fe5ec87fec0ebe3a1d29d50e919376b10135d252659372ffb62e08418158146734fd13f46602  abuild-3.5.0_rc2.tar.xz
-7b565481a85a7094a9f61f39ee44ba3c1f3d5bfeed7a5279c57c14447e94f65b613d56d26d197639ab280745e48c51ff7915fd0570a570d29dd7e2490b298dc7  0001-abuild-fix-applying-patches-from-https.patch"
+7b565481a85a7094a9f61f39ee44ba3c1f3d5bfeed7a5279c57c14447e94f65b613d56d26d197639ab280745e48c51ff7915fd0570a570d29dd7e2490b298dc7  0001-abuild-fix-applying-patches-from-https.patch
+451b420fb09877b188f293bb5240d2c222e90722d28d05dee558c833461f2d6c40db772ae2fe5c9dff1aa8534f360e0d1d6e907da64db7919cae53a59acbeff0  0002-repro.patch"
__END__

echo "============================================================================="
echo "schroot $TARGET set up successfully in $SCHROOT_BASE/$TARGET - exiting now."
echo "============================================================================="

# vim: set sw=0 noet :
