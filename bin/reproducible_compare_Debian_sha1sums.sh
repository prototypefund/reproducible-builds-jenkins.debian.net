#!/bin/bash

# as posted by Vagrant on https://lists.reproducible-builds.org/pipermail/rb-general/2018-October/001239.html

# Copyright 2019 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2+

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set -e

# TODOs:
# - ${package_file}.sha1output includes ${package_file} in the file name and contents
# - run on osuoslXXX ? harder with using db..
# - delete downloaded packages, keep sha1s, use them\
# - GRAPH
# - save results in db
# - loop through all packages
# - show results in 'normal pages' 
# - etc/a lot
# - store date when a package was last reproduced... (and constantly do that...)
# - throw away results (if none has been|which have not) signed with a tests.r-b.o key
# - json files from buildinfo.d.n are never re-downloaded

echo
echo
echo 'this is an early prototype...'
echo
echo

bdn_url="https://buildinfo.debian.net/api/v1/buildinfos/checksums/sha1"
log=$(mktemp --tmpdir=$TMPDIR sha1-comp-XXXXXXX)

SHA1DIR=/srv/reproducible-results/debian-sha1
mkdir -p $SHA1DIR
cd $SHA1DIR

# hardcode some packages to get started...
packages="adduser apt base-files base-passwd bash bsdutils coreutils dash debconf debian-archive-keyring debianutils diffutils dpkg e2fsprogs fdisk findutils gcc-8-base gpgv grep gzip hostname init-system-helpers libacl1 libapt-pkg5.0 libattr1 libaudit-common libaudit1 libblkid1 libbz2-1.0 libc-bin libc6 libcap-ng0 libcom-err2 libdb5.3 libdebconfclient0 libext2fs2 libfdisk1 libffi6 libgcc1 libgcrypt20 libgmp10 libgnutls30 libgpg-error0 libhogweed4 libidn2-0 liblz4-1 liblzma5 libmount1 libncursesw6 libnettle6 libp11-kit0 libpam-modules libpam-modules-bin libpam-runtime libpam0g libpcre3 libseccomp2 libselinux1 libsemanage-common libsemanage1 libsepol1 libsmartcols1 libss2 libstdc++6 libsystemd0 libtasn1-6 libtinfo6 libudev1 libunistring2 libuuid1 libzstd1 login mawk mount ncurses-base ncurses-bin passwd perl-base sed sysvinit-utils tar tzdata util-linux zlib1g apt-utils bsdmainutils cpio cron debconf-i18n dmidecode dmsetup gdbm-l10n ifupdown init iproute2 iptables iputils-ping isc-dhcp-client isc-dhcp-common kmod less libapparmor1 libapt-inst2.0 libargon2-1 libbsd0 libcap2 libcap2-bin libcryptsetup12 libdevmapper1.02.1 libdns-export1104 libelf1 libestr0 libfastjson4 libidn11 libip4tc0 libip6tc0 libiptc0 libisc-export1100 libjson-c3 libkmod2 liblocale-gettext-perl liblognorm5 libmnl0 libncurses6 libnetfilter-conntrack3 libnewt0.52 libnfnetlink0 libnftnl11 libpopt0 libprocps7 libslang2 libssl1.1 libtext-charwidth-perl libtext-iconv-perl libtext-wrapi18n-perl libxtables12 logrotate lsb-base nano netbase procps readline-common rsyslog sensible-utils systemd systemd-sysv tasksel tasksel-data udev vim-common vim-tiny whiptail xxd"

# all the packages is also too much, but let's prototype this...
packages="$(schroot --directory  $SHA1DIR -c chroot:jenkins-reproducible-unstable-diffoscope grep ^Package: /var/lib/apt/lists/cdn-fastly.deb.debian.org_debian_dists_unstable_main_binary-amd64_Packages| awk '{print $2}' | sort | xargs echo)"

reproducible_packages=
unreproducible_packages=

cleanup_all() {
	rm $log
	reproducible_packages=$(awk '/^REPRODUCIBLE:/{print $2}' $log)
	reproducible_count=$(echo $reproducible_packages | wc -w)
	unreproducible_packages=$(awk '/^UNREPRODUCIBLE:/{print $2}' $log)
	unreproducible_count=$(echo $unreproducible_packages | wc -w)

	percent_repro=$(echo "scale=4 ; $reproducible_count / ($reproducible_count+$unreproducible_count) * 100" | bc)
	percent_unrepro=$(echo "scale=4 ; $unreproducible_count / ($reproducible_count+$unreproducible_count) * 100" | bc)

	echo "-------------------------------------------------------------"
	echo "reproducible packages: $reproducible_count: $reproducible_packages"
	echo
	echo "unreproducible packages: $unreproducible_count: $unreproducible_packages"
	echo
	echo "reproducible packages: $reproducible_count: ($percent_repro%)"
	echo
	echo "unreproducible packages: $unreproducible_count: ($percent_unrepro%)"
	echo
	echo
	echo "$(du -sch $SHA1DIR)"
	echo
}

trap cleanup_all INT TERM EXIT

for package in $packages ; do
	schroot --directory  $SHA1DIR -c chroot:jenkins-reproducible-unstable-diffoscope apt-get download ${package} || continue
	if [ $(ls -1 ${package}_*.deb | wc -l) -ne 1 ] ; then
		DEB="$(ls -1 ${package}_*.deb | heads -1)"
		echo "deleting $DEB..."
		rm $DEB # first I thought to delete $DEB* but only deleting $DEB is better
	fi
	package_file=$(ls ${package}_*.deb)
	if [ ! -e ${package_file}.sha1output ] ; then
		SHA1SUM_OUTPUT="$(sha1sum ${package}_*.deb | tee ${package_file}.sha1output)"
	else
		SHA1SUM_OUTPUT="$(cat ${package_file}.sha1output)"
	fi
	SHA1SUM_PKG="$(echo $SHA1SUM_OUTPUT | awk '{print $1}')"
	echo "$SHA1SUM_OUTPUT" | while read checksum package_file ; do
		if [ ! -e ${package_file}.json ]; then
			wget --quiet -O ${package_file}.json ${bdn_url}/${checksum}
		fi
		count=$(fmt ${package_file}.json | grep '\.buildinfo' | wc -l)
		if [ "${count}" -ge 2 ]; then
			echo "REPRODUCIBLE: $package_file: $SHA1SUM_PKG - reproduced $count times."
		else
			echo "UNREPRODUCIBLE: $package_file: $SHA1SUM_PKG on ftp.debian.org, but nowhere else."
		fi
	done
done | tee $log

cleanup_all
trap - INT TERM EXIT
