#!/bin/bash

# Copyright 2014-2018 Holger Levsen <holger@layer-acht.org>
#         © 2015 Reiner Herrmann <reiner@reiner-h.de>
#           2016-2018 Alexander Couzens <lynxis@fe80.eu>
# released under the GPLv=2

# configuration
GENERIC_NODE1=profitbricks-build3-amd64.debian.net
GENERIC_NODE2=profitbricks-build4-amd64.debian.net
OPENWRT_GIT_REPO=https://git.openwrt.org/openwrt/staging/lynxis.git
OPENWRT_GIT_BRANCH=master
DEBUG=false
OPENWRT_CONFIG=
OPENWRT_TARGET=

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh
set -e

# run on jenkins master
node_debug() {
	ls -al "$1" || true
	ls -al "$1/" || true
	ls -al "$1/download" || true
}

# only called direct on a remote build node
node_cleanup_tmpdirs() {
	export TMPBUILDDIR=$1
	cd
	# (very simple) check we are deleting the right stuff
	if [ "${TMPBUILDDIR:0:23}" != "/srv/workspace/chroots/" ] || [ ${#TMPBUILDDIR} -le 23 ] ; then
		echo "Something very strange with \$TMPBUILDDIR=$TMPBUILDDIR exiting instead of doing cleanup."
		exit 1
	fi
	echo "$(date -u) - deleting \$TMPBUILDDIR $TMPBUILDDIR"
	rm -rf "$TMPBUILDDIR"
}

node_create_tmpdirs() {
	export TMPBUILDDIR=$1
	# (very simple) check what we are creating
	if [ "${TMPBUILDDIR:0:23}" != "/srv/workspace/chroots/" ] || [ ${#TMPBUILDDIR} -le 23 ] ; then
		echo "Something very strange with \$TMPBUILDDIR=$TMPBUILDDIR exiting instead of doing create."
		exit 1
	fi
	mkdir -p "$TMPBUILDDIR/download"
}

# called as trap handler and also to cleanup after a success build
master_cleanup_tmpdirs() {
	# we will save the logs in case we got called as trap handler
	# in a success build the logs are saved on a different function
	if [ "$1" != "success" ] ; then
		# job failed
		ssh "$GENERIC_NODE1" "reproducible_openwrt" node node_save_logs "$TMPBUILDDIR" || true
		ssh "$GENERIC_NODE2" "reproducible_openwrt" node node_save_logs "$TMPBUILDDIR" || true
		# save failure logs
		mkdir -p "$WORKSPACE/results/"
		rsync -av "$GENERIC_NODE1:$RESULTSDIR/build_logs.tar.xz" "$WORKSPACE/results/build_logs_b1.tar.xz" || true
		rsync -av "$GENERIC_NODE2:$RESULTSDIR/build_logs.tar.xz" "$WORKSPACE/results/build_logs_b2.tar.xz" || true
	fi

	ssh "$GENERIC_NODE1" "reproducible_openwrt" node node_cleanup_tmpdirs "$TMPBUILDDIR" || true
	ssh "$GENERIC_NODE2" "reproducible_openwrt" node node_cleanup_tmpdirs "$TMPBUILDDIR" || true

	cd
	# (very simple) check we are deleting the right stuff
	if [ "${RESULTSDIR:0:26}" != "/srv/reproducible-results/" ] || [ ${#RESULTSDIR} -le 26 ] || \
	   [ "${TMPBUILDDIR:0:23}" != "/srv/workspace/chroots/" ] || [ ${#TMPBUILDDIR} -le 23 ] ; then
		echo "Something very strange with \$RESULTSDIR=$RESULTSDIR or \$TMPBUILDDIR=$TMPBUILDDIR, exiting instead of doing cleanup."
		exit 1
	fi
	rm -rf "$RESULTSDIR"
	rm -rf "$TMPBUILDDIR"
	if [ -f "$BANNER_HTML" ] ; then
		rm -f "$BANNER_HTML"
	fi
}

node_document_environment() {
	local tmpdir=$1
	local toolchain_html=$tmpdir/toolchain.html

	cd "$tmpdir/build/source"
	cat /dev/null > "$toolchain_html"
	echo "     <table><tr><th>git commit built</th></tr><tr><td><code>" >> "$toolchain_html"
	git log -1 >> "$toolchain_html"
	echo "     </code></td></tr></table>" >> "$toolchain_html"

	echo "<table><tr><th>Target toolchains built</th></tr>" >> "$toolchain_html"
	for i in $(ls -1d staging_dir/toolchain*|cut -d "-" -f2-|xargs echo) ; do
		echo " <tr><td><code>$i</code></td></tr>" >> "$toolchain_html"
	done
	echo "</table>" >> "$toolchain_html"
	echo "<table><tr><th>Contents of <code>build_dir/host/</code></th></tr>" >> "$toolchain_html"
	for i in $(ls -1 build_dir/host/) ; do
		echo " <tr><td>$i</td></tr>" >> "$toolchain_html"
	done
	echo "</table>" >> "$toolchain_html"
	echo "<table><tr><th>Downloaded software</th></tr>" >> "$toolchain_html"
	for i in $(ls -1 dl/) ; do
		echo " <tr><td>$i</td></tr>" >> "$toolchain_html"
	done
	echo "</table>" >> "$toolchain_html"
	echo "<table><tr><th>Debian $(cat /etc/debian_version) package on $(dpkg --print-architecture)</th><th>installed version</th></tr>" >> "$toolchain_html"
	for i in gcc binutils bzip2 flex python perl make findutils grep diffutils unzip gawk util-linux zlib1g-dev libc6-dev git subversion ; do
		echo " <tr><td>$i</td><td>" >> "$toolchain_html"
		dpkg -s $i|grep '^Version'|cut -d " " -f2 >> "$toolchain_html"
		echo " </td></tr>" >> "$toolchain_html"
	done
	echo "</table>" >> "$toolchain_html"
	cd -
}

# node_save_logs can be called over ssh OR called within openwrt_build
# it's always only run on a remote host.
node_save_logs() {
	local tmpdir=$1

	if [ "${tmpdir:0:23}" != "/srv/workspace/chroots/" ] || [ ${#tmpdir} -le 23 ] ; then
		echo "Something very strange with \$TMPDIR=$tmpdir exiting instead of doing node_save_logs."
		exit 1
	fi

	if [ ! -d "$tmpdir/build/source/logs" ] ; then
		# we create an empty tar.xz instead of failing
		touch "$tmpdir/build_logs.tar.xz"
	else
		echo "$(date -u) - saving \$tmpdir/build/source in $tmpdir/build_logs.tar.xz"
		tar cJf "$tmpdir/build_logs.tar.xz" -C "$tmpdir/build/source" ./logs
		echo "$(date -u) - $(ls -lh $tmpdir/build_logs.tar.xz)"
		local result_tar="/srv/reproducible-results/$(echo $BUILD_URL | cut -d '/' -f5- | sed 's#/#_#g')_build_logs.tar.xz"
		cp $tmpdir/build_logs.tar.xz ${result_tar}
		echo "$(date -u) - saving \$tmpdir/build_logs.tar.xz in ${result_tar} on $(hostname)"
	fi

	node_document_environment "$tmpdir"
}

# RUN - is b1 or b2. b1 for first run, b2 for second
# save the images and packages under $TMPDIR/$RUN
# run on the master
save_openwrt_results() {
	local RUN=$1

	# first save all images and target specific packages
	pushd bin/targets
	for target in * ; do
		pushd "$target" || continue
		for subtarget in * ; do
			pushd "$subtarget" || continue

			# save firmware images
			mkdir -p "$TMPDIR/$RUN/targets/$target/$subtarget/"
			for image in $(find * -name "*.bin" -o -name "*.squashfs") ; do
				cp -p "$image" "$TMPDIR/$RUN/targets/$target/$subtarget/"
			done

			# save subtarget specific packages
			if [ -d packages ] ; then
				pushd packages
				for package in $(find * -name "*.ipk") ; do
					mkdir -p $TMPDIR/$RUN/packages/$target/$subtarget/$(dirname $package) || ( echo $TMPDIR/$RUN/packages/$target/$subtarget/$(dirname $package) ; continue )
					cp -p $package $TMPDIR/$RUN/packages/$target/$subtarget/$(dirname $package)/
				done
				popd
			fi
			popd
		done
		popd
	done
	popd

	# save all generic packages
	# arch is like mips_34kc_dsp
	pushd bin/packages/
	for arch in * ; do
		pushd "$arch" || continue
		for feed in * ; do
			pushd "$feed" || continue
			for package in $(find * -name "*.ipk") ; do
				mkdir -p "$TMPDIR/$RUN/packages/$arch/$feed/$(dirname "$package")"
				cp -p "$package" "$TMPDIR/$RUN/packages/$arch/$feed/$(dirname "$package")/"
			done
			popd
		done
		popd
	done
	popd
}

# apply variations change the environment for
# the subsequent run
# RUN - b1 or b2. b1 for first run, b2 for the second
openwrt_apply_variations() {
	local RUN=$1

	if [ "$RUN" = "b1" ] ; then
		export TZ="/usr/share/zoneinfo/Etc/GMT+12"
		export MAKE=make
	else
		export TZ="/usr/share/zoneinfo/Etc/GMT-14"
		export LANG="fr_CH.UTF-8"
		export LC_ALL="fr_CH.UTF-8"
		export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/i/capture/the/path"
		export CAPTURE_ENVIRONMENT="I capture the environment"
		# use allmost all cores for second build
		export NEW_NUM_CPU=$(echo "$NUM_CPU-1" | bc)
		export MAKE=make
	fi
}


openwrt_config() {
	CONFIG=$1

	printf "$CONFIG\n" | grep '^[^ ]' > .config
	printf "CONFIG_ALL=y\n" >> .config
	printf "CONFIG_AUTOREMOVE=y\n" >> .config
	printf "CONFIG_BUILDBOT=y\n" >> .config
	printf "CONFIG_CLEAN_IPKG=y\n" >> .config
	printf "CONFIG_TARGET_ROOTFS_TARGZ=y\n" >> .config
	printf 'CONFIG_KERNEL_BUILD_USER="openwrt"\n' >> .config
	printf 'CONFIG_KERNEL_BUILD_DOMAIN="buildhost"\n' >> .config
	make defconfig
}

openwrt_build_toolchain() {
	echo "============================================================================="
	echo "$(date -u) - Building the toolchain."
	echo "============================================================================="

	OPTIONS="-j $NUM_CPU IGNORE_ERRORS=ym BUILD_LOG=1"

	ionice -c 3 make $OPTIONS tools/install
	ionice -c 3 make $OPTIONS toolchain/install
}

# RUN - b1 or b2. b1 means first run, b2 second
# TARGET - a target including subtarget. E.g. ar71xx_generic
openwrt_compile() {
	local RUN=$1
	local TARGET=$2

	OPTIONS="-j $NUM_CPU IGNORE_ERRORS=ym BUILD_LOG=1"

	# make $RUN more human readable
	[ "$RUN" = "b1" ] && RUN="first"
	[ "$RUN" = "b2" ] && RUN="second"

	echo "============================================================================="
	echo "$(date -u) - Building OpenWrt ${OPENWRT_VERSION} ($TARGET) - $RUN build run."
	echo "============================================================================="
	ionice -c 3 $MAKE $OPTIONS
}

openwrt_create_signing_keys() {
	echo "============================================================================="
	cat <<- EOF
# OpenWrt signs the release with a signing key, but generate the signing key if not
# present. To have a reproducible release we need to take care of signing keys.

# OpenWrt will also put the key-build.pub into the resulting image (pkg: base-files)!
# At the end of the build it will use the key-build to sign the Packages repo list.
# Use a workaround this problem:

# key-build.pub contains the pubkey of OpenWrt buildbot
# key-build     contains our build key

# Meaning only signed files will be different but not the images.
# Packages.sig is unreproducible.

# here is our random signing key
# chosen by fair dice roll.
# guaranteed to be random.

# private key
EOF
	echo -e 'untrusted comment: Local build key\nRWRCSwAAAAB12EzgExgKPrR4LMduadFAw1Z8teYQAbg/EgKaN9SUNrgteVb81/bjFcvfnKF7jS1WU8cDdT2VjWE4Cp4cxoxJNrZoBnlXI+ISUeHMbUaFmOzzBR7B9u/LhX3KAmLsrPc=' | tee key-build
	echo "\n# public key"
	echo -e 'untrusted comment: Local build key\nRWQ/EgKaN9SUNja2aAZ5VyPiElHhzG1GhZjs8wUewfbvy4V9ygJi7Kz3' | tee key-build.pub

	echo "# override the pubkey with 'OpenWrt usign key for unattended build jobs' to have the same base-files pkg and images"
	echo -e 'untrusted comment: OpenWrt usign key for unattended build jobs\nRWS1BD5w+adc3j2Hqg9+b66CvLR7NlHbsj7wjNVj0XGt/othDgIAOJS+' | tee key-build.pub
	echo "============================================================================="
}

# called by openwrt_two_times
# ssh $GENERIC_NODE1 reproducible_openwrt node openwrt_download $TARGET $CONFIG $TMPDIR
openwrt_download() {
	local TARGET=$1
	local CONFIG=$2
	local TMPBUILDDIR=$3
	local tries=5

	cd "$TMPBUILDDIR/download"

	# checkout the repo
	echo "================================================================================"
	echo "$(date -u) - Cloning git repository from $OPENWRT_GIT_REPO $OPENWRT_GIT_BRANCH. "
	echo "================================================================================"
	git clone -b "$OPENWRT_GIT_BRANCH" "$OPENWRT_GIT_REPO" source
	cd source

	echo "================================================================================"
	echo "$(date -u) - received git version $(git log -1 --pretty=oneline)"
	echo "================================================================================"

	# otherwise OpenWrt will generate new release keys every build
	openwrt_create_signing_keys

	# update feeds
	./scripts/feeds update
	./scripts/feeds install -a

	# configure openwrt because otherwise it wont download everything
	openwrt_config "$CONFIG"
	while ! make tools/tar/compile download -j "$NUM_CPU" IGNORE_ERRORS=ym BUILD_LOG=1 ; do
		tries=$((tries - 1))
		if [ $tries -eq 0 ] ; then
			echo "================================================================================"
			echo "$(date -u) - Failed to download sources"
			echo "================================================================================"
			exit 1
		fi
	done
}

openwrt_get_banner() {
	local TMPDIR=$1
	cd "$TMPDIR/build/source"
	echo "===bannerbegin==="
	find staging_dir/ -name banner | grep etc/banner|head -1| xargs cat /dev/null
	echo "===bannerend==="
}

# openwrt_build is run on a remote host
# RUN - b1 or b2. b1 means first run, b2 second
# TARGET - a target including subtarget. E.g. ar71xx_generic
# CONFIG - a simple basic .config as string. Use \n to seperate lines
# TMPPATH - is a unique path generated with mktmp
openwrt_build() {
	local RUN=$1
	local TARGET=$2
	local CONFIG=$3
	export TMPDIR=$4
	export TMPBUILDDIR=$TMPDIR/build/

	mv "$TMPDIR/download" "$TMPBUILDDIR"

	# openwrt is checked out under /download
	cd "$TMPBUILDDIR/source"

	# set tz, date, core, ..
	openwrt_apply_variations "$RUN"

	openwrt_build_toolchain
	# build images and packages
	openwrt_compile "$RUN" "$TARGET"

	# save the results
	save_openwrt_results "$RUN"

	# copy logs
	node_save_logs "$TMPDIR"
}

# build openwrt/openwrt on two different hosts
# TARGET a target including subtarget. E.g. ar71xx_generic
# CONFIG - a simple basic .config as string. Use \n to seperate lines
build_two_times() {
	local TARGET=$1
	local CONFIG=$2

	# create openwrt
	ssh "$GENERIC_NODE1" "reproducible_openwrt" node node_create_tmpdirs "$TMPBUILDDIR"
	ssh "$GENERIC_NODE2" "reproducible_openwrt" node node_create_tmpdirs "$TMPBUILDDIR"
	mkdir -p "$TMPBUILDDIR/download/"

	# create results directory saved by jenkins as artifacts
	mkdir -p "$WORKSPACE/results/"

	# download and prepare openwrt on node b1
	ssh "$GENERIC_NODE1" "reproducible_openwrt" node openwrt_download "$TARGET" "$CONFIG" "$TMPBUILDDIR"

	echo "== master"
	ls -la "$TMPBUILDDIR/download/" || true
	echo "== node1"
	ssh "$GENERIC_NODE1" "reproducible_openwrt" node node_debug "$TMPBUILDDIR"
	echo "== node2"
	ssh "$GENERIC_NODE2" "reproducible_openwrt" node node_debug "$TMPBUILDDIR"

	rsync -a "$GENERIC_NODE1:$TMPBUILDDIR/download/" "$TMPBUILDDIR/download/"
	rsync -a "$TMPBUILDDIR/download/" "$GENERIC_NODE2:$TMPBUILDDIR/download/"

	## first run
	local RUN=b1
	ssh "$GENERIC_NODE1" "reproducible_openwrt" node openwrt_build "$RUN" "$TARGET" "$CONFIG" "$TMPBUILDDIR"
	ssh "$GENERIC_NODE1" "reproducible_openwrt" node openwrt_get_banner "$TMPBUILDDIR" > "$BANNER_HTML"
	# cut away everything before begin and after the end…
	# (thats noise generated by the way we run this via reproducible_common.sh)
	cat "$BANNER_HTML" | sed '/===bannerend===/,$d' | tac | sed '/===bannerbegin===/,$d' | tac > "$BANNER_HTML.out"
        mv "$BANNER_HTML".out "$BANNER_HTML"

	# rsync back logs and images
	rsync -av "$GENERIC_NODE1:$TMPBUILDDIR/$RUN/" "$RESULTSDIR/$RUN/"
	rsync -av "$GENERIC_NODE1:$TMPBUILDDIR/build_logs.tar.xz" "$WORKSPACE/results/build_logs_b1.tar.xz"
	rsync -av "$GENERIC_NODE1:$TMPBUILDDIR/toolchain.html" "$RESULTSDIR/toolchain.html"
	ssh "$GENERIC_NODE1" "reproducible_openwrt" node node_cleanup_tmpdirs "$TMPBUILDDIR"

	## second run
	local RUN=b2
	ssh "$GENERIC_NODE2" "reproducible_openwrt" node openwrt_build "$RUN" "$TARGET" "$CONFIG" "$TMPBUILDDIR"

	# rsync back logs and images
	rsync -av "$GENERIC_NODE2:$TMPBUILDDIR/$RUN/" "$RESULTSDIR/$RUN/"
	rsync -av "$GENERIC_NODE2:$TMPBUILDDIR/build_logs.tar.xz" "$WORKSPACE/results/build_logs_b2.tar.xz"
	ssh "$GENERIC_NODE2" "reproducible_openwrt" node node_cleanup_tmpdirs "$TMPBUILDDIR"
}



echo "$0 got called with '$*'"
# this script is called from positions
# * it's called from the reproducible_wrapper when running on the master
# * it's called from reproducible_opewnrt_common when doing remote builds
case $1 in
	node)
		shift
		case $1 in
			openwrt_build |\
			openwrt_download |\
			openwrt_get_banner |\
			node_create_tmpdirs |\
			node_debug |\
			node_save_logs |\
			node_cleanup_tmpdirs) ;; # this is the allowed list
			*)
				echo "Unsupported remote node function $*"
				exit 1
				;;
		esac
		"$@"
		trap - INT TERM EXIT
		exit 0
	;;
	master)
		# master code following
		OPENWRT_TARGET=$2
		OPENWRT_CONFIG=$3
	;;
	*)
		echo "Unsupported mode $1. Arguments are $*"
		exit 1
	;;
esac

#
# main
#
DATE=$(date -u +'%Y-%m-%d')
START=$(date +'%s')
TMPBUILDDIR=$(mktemp --tmpdir=/srv/workspace/chroots/ -d -t "rbuild-openwrt-build-${DATE}-XXXXXXXX")  # used to build on tmpfs
RESULTSDIR=$(mktemp --tmpdir=/srv/reproducible-results -d -t rbuild-openwrt-results-XXXXXXXX)  # accessable in schroots, used to compare results
BANNER_HTML=$(mktemp "--tmpdir=$RESULTSDIR")
trap master_cleanup_tmpdirs INT TERM EXIT

cd "$TMPBUILDDIR"

mkdir -p "$BASE/openwrt/dbd"


build_two_times "$OPENWRT_TARGET" "$OPENWRT_CONFIG"

#
# create html about toolchain used
#
echo "============================================================================="
echo "$(date -u) - Creating Documentation HTML"
echo "============================================================================="

# created & copied by build_two_times()
TOOLCHAIN_HTML=$RESULTSDIR/toolchain.html

# clean up builddir to save space on tmpfs
rm -rf "$TMPBUILDDIR/openwrt"

# run diffoscope on the results
# (this needs refactoring rather badly)
TIMEOUT="30m"
DIFFOSCOPE="$(schroot --directory /tmp -c "chroot:jenkins-reproducible-${DBDSUITE}-diffoscope" diffoscope -- --version 2>&1)"
echo "============================================================================="
echo "$(date -u) - Running $DIFFOSCOPE on OpenWrt images and packages."
echo "============================================================================="
DBD_HTML=$(mktemp "--tmpdir=$RESULTSDIR")
DBD_GOOD_PKGS_HTML=$(mktemp "--tmpdir=$RESULTSDIR")
DBD_BAD_PKGS_HTML=$(mktemp "--tmpdir=$RESULTSDIR")
# run diffoscope on the images
GOOD_IMAGES=0
ALL_IMAGES=0
SIZE=""
cd "$RESULTSDIR/b1/targets"
tree .

# call_diffoscope requires TMPDIR
TMPDIR=$RESULTSDIR

# iterate over all images (merge b1 and b2 images into one list)
# call diffoscope on the images
for target in * ; do
	cd "$target"
	for subtarget in * ; do
		cd "$subtarget"

		# search images in both paths to find non-existing ones
		IMGS1=$(find -- * -type f -name "*.bin" -o -name "*.squashfs" | sort -u )
		pushd "$RESULTSDIR/b2/targets/$target/$subtarget"
		IMGS2=$(find -- * -type f -name "*.bin" -o -name "*.squashfs" | sort -u )
		popd

		echo "       <table><tr><th>Images for <code>$target/$subtarget</code></th></tr>" >> "$DBD_HTML"
		for image in $(printf "%s\n%s" "$IMGS1" "$IMGS2" | sort -u ) ; do
			let ALL_IMAGES+=1
			if [ ! -f "$RESULTSDIR/b1/targets/$target/$subtarget/$image" ] || [ ! -f "$RESULTSDIR/b2/targets/$target/$subtarget/$image" ] ; then
				echo "         <tr><td><img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> $image (${SIZE}) failed to build.</td></tr>" >> "$DBD_HTML"
				rm -f "$BASE/openwrt/dbd/targets/$target/$subtarget/$image.html" # cleanup from previous (unreproducible) tests - if needed
				continue
			fi

			if [ "$(sha256sum "$RESULTSDIR/b1/targets/$target/$subtarget/$image" "$RESULTSDIR/b2/targets/$target/$subtarget/$image" \
				| cut -f 1 -d ' ' | uniq -c  | wc -l)" != "1" ] ; then
				call_diffoscope "targets/$target/$subtarget" "$image"
			else
				echo "$(date -u) - targets/$target/$subtarget/$image is reproducible, yip!"
			fi
			get_filesize "$image"
			if [ -f "$RESULTSDIR/targets/$target/$subtarget/$image.html" ] ; then
				mkdir -p "$BASE/openwrt/dbd/targets/$target/$subtarget"
				mv "$RESULTSDIR/targets/$target/$subtarget/$image.html" "$BASE/openwrt/dbd/targets/$target/$subtarget/$image.html"
				echo "         <tr><td><a href=\"dbd/targets/$target/$subtarget/$image.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $image</a> (${SIZE}) is unreproducible.</td></tr>" >> "$DBD_HTML"
			else
				SHASUM=$(sha256sum "$image" |cut -d " " -f1)
				echo "         <tr><td><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $image ($SHASUM, $SIZE) is reproducible.</td></tr>" >> "$DBD_HTML"
				let GOOD_IMAGES+=1
				rm -f "$BASE/openwrt/dbd/targets/$target/$subtarget/$image.html" # cleanup from previous (unreproducible) tests - if needed
			fi
		done
		cd ..
		echo "       </table>" >> "$DBD_HTML"
	done
	cd ..
done
GOOD_PERCENT_IMAGES=$(echo "scale=1 ; ($GOOD_IMAGES*100/$ALL_IMAGES)" | bc | grep -qs . || echo 0.00)
# run diffoscope on the packages
GOOD_PACKAGES=0
ALL_PACKAGES=0
cd "$RESULTSDIR/b1"
for i in * ; do
	cd "$i"

	# search packages in both paths to find non-existing ones
	PKGS1=$(find -- * -type f -name "*.ipk" | sort -u )
	pushd "$RESULTSDIR/b2/$i"
	PKGS2=$(find -- * -type f -name "*.ipk" | sort -u )
	popd

	for j in $(printf "%s\n%s" "$PKGS1" "$PKGS2" | sort -u ) ; do
		let ALL_PACKAGES+=1
		if [ ! -f "$RESULTSDIR/b1/$i/$j" ] || [ ! -f "$RESULTSDIR/b2/$i/$j" ] ; then
			echo "         <tr><td><img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> $j (${SIZE}) failed to build.</td></tr>" >> "$DBD_BAD_PKGS_HTML"
			rm -f "$BASE/openwrt/dbd/$i/$j.html" # cleanup from previous (unreproducible) tests - if needed
			continue
		fi

		if [ "$(sha256sum "$RESULTSDIR/b1/$i/$j" "$RESULTSDIR/b2/$i/$j" | cut -f 1 -d ' ' | uniq -c  | wc -l)" != "1" ] ; then
			call_diffoscope "$i" "$j"
		else
			echo "$(date -u) - $i/$j is reproducible, yip!"
		fi
		get_filesize "$j"
		if [ -f "$RESULTSDIR/$i/$j.html" ] ; then
			mkdir -p "$BASE/openwrt/dbd/$i/$(dirname "$j")"
			mv "$RESULTSDIR/$i/$j.html" "$BASE/openwrt/dbd/$i/$j.html"
			echo "         <tr><td><a href=\"dbd/$i/$j.html\"><img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> $j</a> ($SIZE) is unreproducible.</td></tr>" >> "$DBD_BAD_PKGS_HTML"
		else
			SHASUM=$(sha256sum "$j" |cut -d " " -f1)
			echo "         <tr><td><img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> $j ($SHASUM, $SIZE) is reproducible.</td></tr>" >> "$DBD_GOOD_PKGS_HTML"
			let GOOD_PACKAGES+=1
			rm -f "$BASE/openwrt/dbd/$i/$j.html" # cleanup from previous (unreproducible) tests - if needed
		fi
	done
	cd ..
done
echo "       <table><tr><th>Unreproducible and otherwise broken packages</th></tr>" >> "$DBD_HTML"
cat "$DBD_BAD_PKGS_HTML" >> "$DBD_HTML"
echo "       </table>" >> "$DBD_HTML"
echo "       <table><tr><th>Reproducible packages</th></tr>" >> "$DBD_HTML"
cat "$DBD_GOOD_PKGS_HTML" >> "$DBD_HTML"
echo "       </table>" >> "$DBD_HTML"
GOOD_PERCENT_PACKAGES=$(echo "scale=1 ; ($GOOD_PACKAGES*100/$ALL_PACKAGES)" | bc | grep -qs . || echo 0.00)
# are we there yet?
if [ "$GOOD_PERCENT_IMAGES" = "100.0" ] || [ "$GOOD_PERCENT_PACKAGES" = "100.0" ]; then
	MAGIC_SIGN="!"
else
	MAGIC_SIGN="?"
fi

write_openwrt_page_header(){
	cat > "$PAGE" <<- EOF
<!DOCTYPE html>
<html lang="en-US">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width">
    <title>Reproducible OpenWrt ?</title>
    <link rel='stylesheet' id='kamikaze-style-css'  href='cascade.css?ver=4.0' type='text/css' media='all'>
  </head>
  <body>
    <div id="content">
        <pre>
EOF
	cat "$BANNER_HTML" >> "$PAGE"
	write_page "       </pre>"
	write_page "     </div><div id=\"main-content\">"
	write_page "       <h1>OpenWrt - <em>reproducible</em> wireless freedom$MAGIC_SIGN</h1>"
}
#
#  create landing age
#
cd "$RESULTSDIR" ; mkdir openwrt
PAGE=openwrt/openwrt.html
write_openwrt_page_header
write_page_intro OpenWrt
write_page "     <p>"
write_page "     <ul>"
for i in ar71xx ramips x86 ; do
	write_page "            <li><a href="openwrt_$i.html">$i</a></li>"
done
write_page "     </ul>"
write_page "     </p>"
write_page "    </div>"
write_page_footer OpenWrt
publish_page

#
#  finally create the target webpage
#
PAGE=openwrt/openwrt_$OPENWRT_TARGET.html
write_openwrt_page_header
write_page "       <p>$GOOD_IMAGES ($GOOD_PERCENT_IMAGES%) out of $ALL_IMAGES built images and $GOOD_PACKAGES ($GOOD_PERCENT_PACKAGES%) out of $ALL_PACKAGES built packages were reproducible in our test setup."
write_page "        These tests were last run on $DATE for version ${OPENWRT_VERSION} using ${DIFFOSCOPE}.</p>"
write_variation_table OpenWrt
cat "$DBD_HTML" >> "$PAGE"
cat "$TOOLCHAIN_HTML" >> "$PAGE"
write_page "    </div>"
write_page_footer OpenWrt
publish_page
rm -f "$DBD_HTML" "$DBD_GOOD_PKGS_HTML" "$DBD_BAD_PKGS_HTML" "$TOOLCHAIN_HTML" "$BANNER_HTML"

# the end
calculate_build_duration
print_out_duration
for CHANNEL in reproducible-builds openwrt-devel ; do
	irc_message $CHANNEL "$REPRODUCIBLE_URL/$PAGE has been updated. ($GOOD_PERCENT_IMAGES% images and $GOOD_PERCENT_PACKAGES% packages reproducible in our current test framework.)"
done
echo "============================================================================="

# remove everything, we don't need it anymore...
master_cleanup_tmpdirs success
trap - INT TERM EXIT
