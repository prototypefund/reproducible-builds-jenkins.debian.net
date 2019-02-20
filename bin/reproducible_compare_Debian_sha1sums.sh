#!/bin/bash

# Copyright 2019 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2+
#
# based on an idea by Vagrant Cascadian <vagrant@debian.org>
# see https://lists.reproducible-builds.org/pipermail/rb-general/2018-October/001239.html

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set -e

# TODOs:
# - ${package_file}.sha1output includes ${package_file} in the file name and contents
# - run on osuoslXXX ? harder with using db..
# - GRAPH
# - save results in db
# - loop through all packages known in db
# - show results in 'normal pages' 
# - store date when a package was last reproduced... (and constantly do that...)
# - throw away results (if none has been|which have not) signed with a tests.r-b.o key
# - json files from buildinfo.d.n are never re-downloaded

echo
echo
echo 'this is an early prototype...'
echo
echo
RELEASE=buster

bdn_url="https://buildinfo.debian.net/api/v1/buildinfos/checksums/sha1"
log=$(mktemp --tmpdir=$TMPDIR sha1-comp-XXXXXXX)

SHA1DIR=/srv/reproducible-results/debian-sha1
mkdir -p $SHA1DIR
cd $SHA1DIR

PACKAGES=$(mktemp --tmpdir=$TMPDIR sha1-comp-XXXXXXX)
schroot --directory  $SHA1DIR -c chroot:jenkins-reproducible-${RELEASE}-diffoscope cat /var/lib/apt/lists/cdn-fastly.deb.debian.org_debian_dists_${RELEASE}_main_binary-amd64_Packages > $PACKAGES
packages="$(grep ^Package: $PACKAGES| awk '{print $2}' | sort | xargs echo)"

reproducible_packages=
unreproducible_packages=

cleanup_all() {
	reproducible_packages=$(awk '/ REPRODUCIBLE: /{print $2}' $log)
	reproducible_count=$(echo $reproducible_packages | wc -w)
	unreproducible_packages=$(awk '/ UNREPRODUCIBLE: /{print $2}' $log)
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
	rm $log $PACKAGES
}

trap cleanup_all INT TERM EXIT

for package in $packages ; do
	cd $SHA1DIR
	echo
	echo "$(date -u) - checking whether we have seen the .deb for $package before"
	version=$(grep-dctrl -X -P ${package} -s version -n $PACKAGES)
	arch=$(grep-dctrl -X -P ${package} -s Architecture -n $PACKAGES)
	package_file="${package}_$(echo $version | sed 's#:#%3a#')_${arch}.deb"
	pool_dir="$(dirname $(grep-dctrl -X -P ${package} -s Filename -n $PACKAGES))"
	mkdir -p $pool_dir
	cd $pool_dir
	if [ ! -e ${package_file}.sha1output ] ; then
		echo -n "$(date -u) - preparing to download $filename"
		( schroot --directory  $SHA1DIR/$pool_dir -c chroot:jenkins-reproducible-${RELEASE}-diffoscope apt-get download ${package}/${RELEASE} 2>&1 |xargs echo ) || continue
		echo "$(date -u) - calculating sha1sum"
		SHA1SUM_PKG="$(sha1sum ${package_file} | tee ${package_file}.sha1output | awk '{print $1}' )"
		rm ${package_file}
	else
		echo "$(date -u) - ${package_file} is known, gathering sha1sum"
		SHA1SUM_PKG="$(cat ${package_file}.sha1output | awk '{print $1}' )"
	fi
	if [ ! -e ${package_file}.json ]; then
		echo "$(date -u) - downloading .json from buildinfo.debian.net"
		wget --quiet -O ${package_file}.json ${bdn_url}/${SHA1SUM_PKG} || echo "WARNING: failed to download ${bdn_url}/${SHA1SUM_PKG}"
	else
		echo "$(date -u) - reusing local copy of .json from buildinfo.debian.net"
	fi
	echo "$(date -u) - generating result"
	count=$(fmt ${package_file}.json | grep -c '\.buildinfo' || true)
	if [ "${count}" -ge 2 ]; then
		echo "$(date -u) - REPRODUCIBLE: $package_file: $SHA1SUM_PKG - reproduced $count times."
	else
		echo "$(date -u) - UNREPRODUCIBLE: $package_file: $SHA1SUM_PKG on ftp.debian.org, but nowhere else."
	fi
done | tee $log

cleanup_all
trap - INT TERM EXIT
