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
# - delete downloaded packages, keep sha1s, use them
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

bdn_url="https://buildinfo.debian.net/api/v1/buildinfos/checksums/sha1"
log=$(mktemp --tmpdir=$TMPDIR sha1-comp-XXXXXXX)

SHA1DIR=/srv/reproducible-results/debian-sha1
mkdir -p $SHA1DIR
cd $SHA1DIR

# downloading (and keeping) all the packages is also too much, but let's prototype this... (and improve later)
packages="$(schroot --directory  $SHA1DIR -c chroot:jenkins-reproducible-unstable-diffoscope grep ^Package: /var/lib/apt/lists/cdn-fastly.deb.debian.org_debian_dists_unstable_main_binary-amd64_Packages| awk '{print $2}' | sort -R | xargs echo)"

reproducible_packages=
unreproducible_packages=

cleanup_all() {
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
	rm $log
}

trap cleanup_all INT TERM EXIT

for package in $packages ; do
	echo "$(date -u) - preparing to download binary package $package"
	schroot --directory  $SHA1DIR -c chroot:jenkins-reproducible-unstable-diffoscope apt-get download ${package} || continue
	echo "$(date -u) - checking if more than one .deb exists locally"
	package_file="$(ls -1 ${package}_*.deb)"
	if [ $(echo "${package_file}" | wc -l) -ne 1 ] ; then
		OLD_DEB=$(echo "${package_file}" | head -1)
		echo "deleting $OLD_DEB..."
		rm $OLD_DEB # first I thought to delete $OLD_DEB* but only deleting $OLD_DEB is better
		package_file=$(echo "${package_file}" | tail -1 )
	fi
	echo "$(date -u) - gathering sha1sum"
	if [ ! -e ${package_file}.sha1output ] ; then
		SHA1SUM_PKG="$(sha1sum ${package_file} | tee ${package_file}.sha1output | awk '{print $1}' )"
	else
		SHA1SUM_PKG="$(cat ${package_file}.sha1output | awk '{print $1}' )"
	fi
	echo "$(date -u) - downloading .json from buildinfo.debian.net"
	if [ ! -e ${package_file}.json ]; then
		wget --quiet -O ${package_file}.json ${bdn_url}/${SHA1SUM_PKG} || echo "WARNING: failed to download ${bdn_url}/${SHA1SUM_PKG}"
	fi
	echo "$(date -u) - generating result"
	count=$(fmt ${package_file}.json | grep -c '\.buildinfo' || true)
	if [ "${count}" -ge 2 ]; then
		echo "REPRODUCIBLE: $package_file: $SHA1SUM_PKG - reproduced $count times."
	else
		echo "UNREPRODUCIBLE: $package_file: $SHA1SUM_PKG on ftp.debian.org, but nowhere else."
	fi
done | tee $log

cleanup_all
trap - INT TERM EXIT
