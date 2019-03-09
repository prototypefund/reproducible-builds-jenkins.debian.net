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
# - GRAPH
# - save results in db
# - loop through all packages known in db
# - show results in 'normal pages' 
# - store date when a package was last reproduced... (and constantly do that...)
# - throw away results (if none has been|which have not) signed with a tests.r-b.o key
# - rebuilder:
#   - run on osuosl173
#   - loop randomly through unreproducible packages first, then reproducible ones. do one attempt only.
#   - one job run tests one package.
#   - use same debuild options possible? or try all sane options?
#   - submit .buildinfo file to b.d.n and then fetch the json again.
#   - debootstrap stretch and upgrade from there?
# - this is all amd64 only for a start

RELEASE=buster
MODE="$1"

echo
echo
echo -n 'this is an early prototype...'
if [ "$MODE" = "results" ] ; then
	echo 'this job will show results based on data gathered in other jobs.'
else
	echo 'this job gathers data but does not show results.'
fi
echo
echo

bdn_url="https://buildinfo.debian.net/api/v1/buildinfos/checksums/sha1"
log=$(mktemp --tmpdir=$TMPDIR sha1-log-XXXXXXX)
echo "$(date -u) - logfile used is $log"

FORCE_DATE=$(date -u -d "14 days ago" '+%Y-%m-%d')
DUMMY_FILE=$(mktemp --tmpdir=$TMPDIR sha1-date-XXXXXXX)
touch -d "$(date '+%Y-%m-%d') 00:00 UTC" $DUMMY_FILE

SHA1DIR=/srv/reproducible-results/debian-sha1
mkdir -p $SHA1DIR

PACKAGES=$(mktemp --tmpdir=$TMPDIR sha1-pkgs-XXXXXXX)
schroot --directory  $SHA1DIR -c chroot:jenkins-reproducible-${RELEASE}-diffoscope cat /var/lib/apt/lists/cdn-fastly.deb.debian.org_debian_dists_${RELEASE}_main_binary-amd64_Packages > $PACKAGES
case "$MODE" in
	random)		SORT="sort -u -R";;
	reverse)	SORT="sort -u -r" ;;
	forward)	SORT="sort -u" ;;
	*)		SORT="sort -u" ; MODE="results" ; RESULTS=$(mktemp --tmpdir=$TMPDIR sha1-results-XXXXXXX) ; find $SHA1DIR -name "*REPRODUCIBLE.buster" > $RESULTS ;;
esac
packages="$(grep ^Package: $PACKAGES| awk '{print $2}' | $SORT | xargs echo)"

reproducible_packages=
unreproducible_packages=

cleanup_all() {
	if [ "$MODE" = "results" ]; then
		unknown_packages=$(awk '/ UNKNOWN: /{print $9}' $log)
		unknown_count=$(echo $unknown_packages | wc -w)
		reproducible_packages=$(awk '/ REPRODUCIBLE: /{print $9}' $log)
		reproducible_count=$(echo $reproducible_packages | wc -w)
		unreproducible_packages=$(awk '/ UNREPRODUCIBLE: /{print $9}' $log)
		unreproducible_count=$(echo $unreproducible_packages | wc -w)
		reproducible_binnmu=$((find $SHA1DIR -type f || echo ) | egrep -c '+b._(all|amd64).deb.REPRODUCIBLE.buster' || true)
		unreproducible_binnmu=$((find $SHA1DIR -type f || echo ) | egrep -c '+b._(all|amd64).deb.UNREPRODUCIBLE.buster' || true)
		reproducible_arch_all=$((find $SHA1DIR -type f || echo ) | egrep -c '_all.deb.REPRODUCIBLE.buster' || true)
		unreproducible_arch_all=$((find $SHA1DIR -type f || echo ) | egrep -c '_all.deb.UNREPRODUCIBLE.buster' || true)
		reproducible_arch_amd64=$((find $SHA1DIR -type f || echo ) | egrep -c '_amd64.deb.REPRODUCIBLE.buster' || true)
		unreproducible_arch_amd64=$((find $SHA1DIR -type f || echo ) | egrep -c '_amd64.deb.UNREPRODUCIBLE.buster' || true)
		percent_unknown=$(echo "scale=4 ; $unknown_count / ($reproducible_count+$unreproducible_count+$unknown_count) * 100" | bc)
		percent_repro=$(echo "scale=4 ; $reproducible_count / ($reproducible_count+$unreproducible_count+$unknown_count) * 100" | bc)
		percent_unrepro=$(echo "scale=4 ; $unreproducible_count / ($reproducible_count+$unreproducible_count+$unknown_count) * 100" | bc)
		percent_binnmu_repro=$(echo "scale=4 ; $reproducible_binnmu / ($reproducible_count+$unreproducible_count+$unknown_count) * 100" | bc)
		percent_binnmu_unrepro=$(echo "scale=4 ; $unreproducible_binnmu / ($reproducible_count+$unreproducible_count+$unknown_count) * 100" | bc)
		percent_arch_all_repro=$(echo "scale=4 ; $reproducible_arch_all / ($reproducible_count+$unreproducible_count+$unknown_count) * 100" | bc)
		percent_arch_all_unrepro=$(echo "scale=4 ; $unreproducible_arch_all / ($reproducible_count+$unreproducible_count+$unknown_count) * 100" | bc)
		percent_arch_amd64_repro=$(echo "scale=4 ; $reproducible_arch_amd64 / ($reproducible_count+$unreproducible_count+$unknown_count) * 100" | bc)
		percent_arch_amd64_unrepro=$(echo "scale=4 ; $unreproducible_arch_amd64 / ($reproducible_count+$unreproducible_count+$unknown_count) * 100" | bc)
		echo "-------------------------------------------------------------"
		echo
		echo "ftp.debian.org package reproducibility statistics"
		echo "-------------------------------------------------------------"
		echo "packages in unknown reproducibility state in $RELEASE/amd64: $unknown_count: ($percent_unknown%)"
		echo "reproducible packages in $RELEASE/amd64: $reproducible_count: ($percent_repro%)"
		echo "unreproducible packages in $RELEASE/amd64: $unreproducible_count: ($percent_unrepro%)"
		echo "total number of packages in $RELEASE/amd64: $(echo $reproducible_count+$unreproducible_count+$unknown_count | bc)"
		echo
		echo
		echo "reproducible binNMUs in $RELEASE/amd64: $reproducible_binnmu: ($percent_binnmu_repro%)"
		echo "unreproducible binNMU in $RELEASE/amd64: $unreproducible_binnmu: ($percent_binnmu_unrepro%)"
		echo
		echo "reproducible arch:all packages in $RELEASE/amd64: $reproducible_arch_all: ($percent_arch_all_repro%)"
		echo "unreproducible arch:all packages in $RELEASE/amd64: $unreproducible_arch_all: ($percent_arch_all_unrepro%)"
		echo "reproducible arch:amd64 packages in $RELEASE/amd64: $reproducible_arch_amd64: ($percent_arch_amd64_repro%)"
		echo "unreproducible arch:amd64 packages in $RELEASE/amd64: $unreproducible_arch_amd64: ($percent_arch_amd64_unrepro%)"
		echo
		echo
		echo "$(du -sch $SHA1DIR 2>/dev/null)"
		echo
		rm $RESULTS
	fi
	rm $log $PACKAGES
}

trap cleanup_all INT TERM EXIT

rm -f $SHA1DIR/*.lock	# this is a tiny bit hackish, but also an elegant way to get rid of old locks...
			# (locks are held for 30s only anyway and there is an 3/60000th chance of a race condition only anyway)

if [ "$MODE" = "results" ] ; then
	for package in $packages ; do
		result=$(grep "/${package}_" $RESULTS || true)
		if [ -n "$result" ] ; then
			if $(echo $result | grep -q UNREPRODUCIBLE) ; then
				#package_file=$(echo $result | sed 's#\.deb\.UNREPRODUCIBLE\.buster$#.deb#' )
				#count=1
				#SHA1SUM_PKG="$(cat ${package_file}.sha1output | awk '{print $1}' )"
				#package_file=$(basename $package_file)
				#echo "$(date -u) - UNREPRODUCIBLE: $package_file ($SHA1SUM_PKG) only on ftp.debian.org."
				echo "$(date -u) - UNREPRODUCIBLE: $package"
			else
				#package_file=$(echo $result | sed 's#\.deb\.REPRODUCIBLE\.buster$#.deb#' )
				#count=$(cat ${package_file}.REPRODUCIBLE.$RELEASE)
				#SHA1SUM_PKG="$(cat ${package_file}.sha1output | awk '{print $1}' )"
				#package_file=$(basename $package_file)
				#echo "$(date -u) - REPRODUCIBLE: $package_file ($SHA1SUM_PKG) - reproduced $count times."
				echo "$(date -u) - REPRODUCIBLE: $package"
			fi
			continue
		fi
		echo "$(date -u) - UNKNOWN: $package"
	done | tee $log
	exit
fi

# only used by the runners
for package in $packages ; do
	LOCK="$SHA1DIR/${package}.lock"
	if [ -e $LOCK ] ; then
		echo "$(date -u) - skipping locked package $package"
		continue
	else
		touch $LOCK
	fi
	version=$(grep-dctrl -X -P ${package} -s Version -n $PACKAGES | head -1)
	arch=$(grep-dctrl -X -P ${package} -s Architecture -n $PACKAGES | head -1)
	package_file="${package}_$(echo $version | sed 's#:#%3a#')_${arch}.deb"
	pool_dir="$SHA1DIR/$(dirname $(grep-dctrl -X -P ${package} -s Filename -n $PACKAGES | head -1))"
	mkdir -p $pool_dir
	cd $pool_dir
	if [ ! -e ${package_file}.sha1output ] ; then
		echo -n "$(date -u) - downloading... "
		( schroot --directory $pool_dir -c chroot:jenkins-reproducible-${RELEASE}-diffoscope apt-get download ${package}/${RELEASE} 2>&1 |xargs echo ) || continue
		echo "$(date -u) - calculating sha1sum for ${package_file}"
		SHA1SUM_PKG="$(sha1sum ${package_file} | tee ${package_file}.sha1output | awk '{print $1}' )"
		rm ${package_file}
		if [ -n "$(ls ${package}_*REPRODUCIBLE.$RELEASE 2>/dev/null)" ] ; then
			echo "$(date -u) - $package was updated, deleting results for old version."
			rm ${package}_*REPRODUCIBLE.$RELEASE
		fi
	fi
	# download .json if non existing or older than $DUMMY_FILE
	if [ ! -e ${package_file}.json ] || [ ${package_file}.json -ot $DUMMY_FILE ]; then
		echo "$(date -u) - downloading .json for ${package_file} (${SHA1SUM_PKG}) from buildinfo.debian.net"
		wget --quiet -O ${package_file}.json ${bdn_url}/${SHA1SUM_PKG} || echo "WARNING: failed to download ${bdn_url}/${SHA1SUM_PKG}"
		count=$(fmt ${package_file}.json | grep -c '\.buildinfo' || true)
		SHA1SUM_PKG="$(cat ${package_file}.sha1output | awk '{print $1}' )"
		if [ "${count}" -ge 2 ]; then
			echo $count > ${package_file}.REPRODUCIBLE.$RELEASE
			echo "$(date -u) - REPRODUCIBLE: $package_file ($SHA1SUM_PKG) - reproduced $count times."
		else
			echo 1 > ${package_file}.UNREPRODUCIBLE.$RELEASE
			echo "$(date -u) - UNREPRODUCIBLE: $package_file ($SHA1SUM_PKG) only on ftp.debian.org."
		fi
	else
		echo "$(date -u) - not updating data about ${package_file}"
	fi
	rm -f $LOCK
done | tee -a $log

cleanup_all
trap - INT TERM EXIT
