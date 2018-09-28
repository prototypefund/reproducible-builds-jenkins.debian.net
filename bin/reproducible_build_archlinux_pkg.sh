#!/bin/bash

# Copyright 2015-2018 Holger Levsen <holger@layer-acht.org>
#                2017 kpcyrd <git@rxv.cc>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

set -e

cleanup_all() {
	cd
	# delete session if it still exists
	if [ "$MODE" != "master" ] ; then
		schroot --end-session -c archlinux-$SRCPACKAGE-$(basename $TMPDIR) > /dev/null 2>&1 || true
	fi
	# delete makepkg build dir
	if [ ! -z $SRCPACKAGE ] && [ -d /tmp/$SRCPACKAGE-$(basename $TMPDIR) ] ; then
		sudo rm -rf --one-file-system /tmp/$SRCPACKAGE-$(basename $TMPDIR)
	fi
	# delete main work dir (only on master)
	if [ "$MODE" = "master" ] ; then
		rm $TMPDIR -r
		echo "$(date -u) - $TMPDIR deleted."
	fi
}

update_pkg_in_db() {
	local ARCHLINUX_PKG_PATH=$ARCHBASE/$REPOSITORY/$SRCPACKAGE
	cd "$ARCHLINUX_PKG_PATH"
	BUILD_DURATION="$(cat pkg.build_duration)"
	BUILD_STATE=$(cat pkg.state)
	BUILD_VERSION="$(cat pkg.version)"
	SUITE="archlinux_$REPOSITORY"
	local SRCPKGID=$(query_db "SELECT id FROM sources WHERE name='$SRCPACKAGE' AND suite='$SUITE' AND architecture='$ARCH';")
	if [ -z "${SRCPKGID}" ] ; then
	        echo "${SRCPKGID} empty, ignoring $REPOSITORY/$SRCPACKAGE, failing hard."
		exit 1
	fi
	QUERY="INSERT into results (package_id, version, status, build_date, build_duration, node1, node2, job)
		VALUES ('${SRCPKGID}', '$BUILD_VERSION', '$BUILD_STATE', '$DATE', '$BUILD_DURATION', '$NODE1', '$NODE2', '$BUILD_URL')
		ON CONFLICT (package_id)
		DO UPDATE SET version='$BUILD_VERSION', status='$BUILD_STATE', build_date='$DATE', build_duration='$BUILD_DURATION', node1='$NODE1', node2='$NODE2', job='$BUILD_URL' WHERE results.package_id='$SRCPKGID'";
        echo "$QUERY"
	query_db "$QUERY"
        QUERY="INSERT INTO stats_build (name, version, suite, architecture, status, build_date, build_duration, node1, node2, job) 
		VALUES ('$SRCPACKAGE', '$BUILD_VERSION', '$SUITE', '$ARCH', '$BUILD_STATE', '$DATE', '$BUILD_DURATION', '$NODE1', '$NODE2', '$BUILD_URL');"
        echo "$QUERY"
	query_db "$QUERY"
        # unmark build since it's properly finished
        QUERY="DELETE FROM schedule WHERE package_id='${SRCPKGID}';"
        echo "$QUERY"
	query_db "$QUERY"
	rm pkg.build_duration pkg.state pkg.version

}

find_in_buildlogs() {
    egrep -q "$1" $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null
}

create_pkg_html() {
	local ARCHLINUX_PKG_PATH=$ARCHBASE/$REPOSITORY/$SRCPACKAGE
	local HTML_BUFFER=$(mktemp -t archlinuxrb-html-XXXXXXXX)

	local blacklisted=false

	# clear files from previous builds
	cd "$ARCHLINUX_PKG_PATH"
	for file in build1.log build2.log build1.version build2.version *BUILDINFO.txt *.html; do
		if [ -f $file ] && [ pkg.build_duration -nt $file ] ; then
			rm $file
			echo "$ARCHLINUX_PKG_PATH/$file older than $ARCHLINUX_PKG_PATH/pkg.build_duration, thus deleting it."
		fi
	done

	echo "     <tr>" >> $HTML_BUFFER
	echo "      <td>$REPOSITORY</td>" >> $HTML_BUFFER
	echo "      <td>$SRCPACKAGE</td>" >> $HTML_BUFFER
	echo "      <td>$VERSION</td>" >> $HTML_BUFFER
	echo "      <td>" >> $HTML_BUFFER
	#
	#
	if [ -z "$(cd $ARCHLINUX_PKG_PATH/ ; ls *.pkg.tar.xz.html 2>/dev/null)" ] ; then
		for i in $ARCHLINUX_BLACKLISTED ; do
			if [ "$SRCPACKAGE" = "$i" ] ; then
				blacklisted=true
			fi
		done
		# this horrible if elif elif elif elif...  monster is needed because
		# https://lists.archlinux.org/pipermail/pacman-dev/2017-September/022156.html
	        # has not yet been merged yet...
		# FIXME: this has been merged, see http://jlk.fjfi.cvut.cz/arch/manpages/man/makepkg

		if $blacklisted ; then
				echo BLACKLISTED > $ARCHLINUX_PKG_PATH/pkg.state
				echo "       <img src=\"/userContent/static/error.png\" alt=\"blacklisted icon\" /> blacklisted" >> $HTML_BUFFER
		elif find_in_buildlogs '^error: failed to prepare transaction \(conflicting dependencies\)'; then
			echo DEPWAIT_0 > $ARCHLINUX_PKG_PATH/pkg.state
			echo "       <img src=\"/userContent/static/weather-snow.png\" alt=\"depwait icon\" /> could not resolve dependencies as there are conflicts" >> $HTML_BUFFER
		elif find_in_buildlogs '==> ERROR: (Could not resolve all dependencies|.pacman. failed to install missing dependencies)'; then
			if find_in_buildlogs 'error: failed to init transaction \(unable to lock database\)'; then
				echo DEPWAIT_2 > $ARCHLINUX_PKG_PATH/pkg.state
				echo "       <img src=\"/userContent/static/weather-snow.png\" alt=\"depwait icon\" /> pacman could not lock database" >> $HTML_BUFFER
			else
				echo DEPWAIT_1 > $ARCHLINUX_PKG_PATH/pkg.state
				echo "       <img src=\"/userContent/static/weather-snow.png\" alt=\"depwait icon\" /> could not resolve dependencies" >> $HTML_BUFFER
			fi
		elif find_in_buildlogs '^error: unknown package: '; then
			echo 404_0 > $ARCHLINUX_PKG_PATH/pkg.state
			echo "       <img src=\"/userContent/static/weather-severe-alert.png\" alt=\"404 icon\" /> unknown package" >> $HTML_BUFFER
		elif find_in_buildlogs '(==> ERROR: Failure while downloading|==> ERROR: One or more PGP signatures could not be verified|==> ERROR: One or more files did not pass the validity check|==> ERROR: Integrity checks \(.*\) differ in size from the source array|==> ERROR: Failure while branching|==> ERROR: Failure while creating working copy|Failed to source PKGBUILD.*PKGBUILD)'; then
			REASON="download failed"
			EXTRA_REASON=""
			echo 404_0 > $ARCHLINUX_PKG_PATH/pkg.state
			if find_in_buildlogs 'FAILED \(unknown public key'; then
				echo 404_6 > $ARCHLINUX_PKG_PATH/pkg.state
				EXTRA_REASON="to verify source with PGP due to unknown public key"
			elif find_in_buildlogs 'The requested URL returned error: 403'; then
				echo 404_2 > $ARCHLINUX_PKG_PATH/pkg.state
				EXTRA_REASON="with 403 - forbidden"
			elif find_in_buildlogs 'The requested URL returned error: 500'; then
				echo 404_4 > $ARCHLINUX_PKG_PATH/pkg.state
				EXTRA_REASON="with 500 - internal server error"
			elif find_in_buildlogs 'The requested URL returned error: 503'; then
				echo 404_5 > $ARCHLINUX_PKG_PATH/pkg.state
				EXTRA_REASON="with 503 - service unavailable"
			elif find_in_buildlogs '==> ERROR: One or more PGP signatures could not be verified'; then
				echo 404_7 > $ARCHLINUX_PKG_PATH/pkg.state
				EXTRA_REASON="to verify source with PGP signatures"
			elif find_in_buildlogs '(SSL certificate problem: unable to get local issuer certificate|^bzr: ERROR: .SSL: CERTIFICATE_VERIFY_FAILED)'; then
				echo 404_1 > $ARCHLINUX_PKG_PATH/pkg.state
				EXTRA_REASON="with SSL problem"
			elif find_in_buildlogs '==> ERROR: One or more files did not pass the validity check'; then
				echo 404_8 > $ARCHLINUX_PKG_PATH/pkg.state
				REASON="downloaded ok but failed to verify source"
			elif find_in_buildlogs '==> ERROR: Integrity checks \(.*\) differ in size from the source array'; then
				echo 404_9 > $ARCHLINUX_PKG_PATH/pkg.state
				REASON="Integrity checks differ in size from the source array"
			elif find_in_buildlogs 'The requested URL returned error: 404'; then
				echo 404_3 > $ARCHLINUX_PKG_PATH/pkg.state
				EXTRA_REASON="with 404 - file not found"
			elif find_in_buildlogs 'fatal: the remote end hung up unexpectedly'; then
				echo 404_A > $ARCHLINUX_PKG_PATH/pkg.state
				EXTRA_REASON="could not clone git repository"
			elif find_in_buildlogs 'The requested URL returned error: 504'; then
				echo 404_B > $ARCHLINUX_PKG_PATH/pkg.state
				EXTRA_REASON="with 504 - gateway timeout"
			fi
			echo "       <img src=\"/userContent/static/weather-severe-alert.png\" alt=\"404 icon\" /> $REASON $EXTRA_REASON" >> $HTML_BUFFER
		elif find_in_buildlogs '==> ERROR: (install file .* does not exist or is not a regular file|The download program wget is not installed)'; then
			echo FTBFS_0 > $ARCHLINUX_PKG_PATH/pkg.state
			echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build, requirements not met" >> $HTML_BUFFER
		elif find_in_buildlogs '==> ERROR: A failure occurred in check'; then
			echo FTBFS_1 > $ARCHLINUX_PKG_PATH/pkg.state
			echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build while running tests" >> $HTML_BUFFER
		elif find_in_buildlogs '==> ERROR: (An unknown error has occurred|A failure occurred in (build|package|prepare))'; then
			echo FTBFS_2 > $ARCHLINUX_PKG_PATH/pkg.state
			echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build" >> $HTML_BUFFER
		elif find_in_buildlogs 'makepkg was killed by timeout after'; then
			echo FTBFS_3 > $ARCHLINUX_PKG_PATH/pkg.state
			echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build, killed by timeout" >> $HTML_BUFFER
		elif find_in_buildlogs '==> ERROR: .* contains invalid characters:'; then
			echo FTBFS_4 > $ARCHLINUX_PKG_PATH/pkg.state
			echo "       <img src=\"/userContent/static/weather-storm.png\" alt=\"ftbfs icon\" /> failed to build, pkg relations contain invalid characters" >> $HTML_BUFFER
		else
			echo "       probably failed to build from source, please investigate" >> $HTML_BUFFER
			echo UNKNOWN > $ARCHLINUX_PKG_PATH/pkg.state
		fi
	else
		local STATE=GOOD
		local SOME_GOOD=false
		for ARTIFACT in $(cd $ARCHLINUX_PKG_PATH/ ; ls *.pkg.tar.xz.html) ; do
			if [ -z "$(echo $ARTIFACT | grep $VERSION)" ] ; then
				echo "deleting $ARTIFACT as version is not $VERSION"
				rm -f $ARTIFACT
				continue
			elif [ ! -z "$(grep 'build reproducible in our test framework' $ARCHLINUX_PKG_PATH/$ARTIFACT)" ] ; then
				SOME_GOOD=true
				echo "       <img src=\"/userContent/static/weather-clear.png\" alt=\"reproducible icon\" /> <a href=\"/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT\">${ARTIFACT:0:-5}</a> is reproducible in our current test framework<br />" >> $HTML_BUFFER
			else
				# change $STATE unless we have found .buildinfo differences already...
				if [ "$STATE" != "FTBR_0" ] ; then
					STATE=FTBR_1
				fi
				# this shouldnt happen, but (for now) it does, so lets mark them…
				EXTRA_REASON=""
				if [ ! -z "$(grep 'class="source">.BUILDINFO' $ARCHLINUX_PKG_PATH/$ARTIFACT)" ] ; then
					STATE=FTBR_0
					EXTRA_REASON=" with variations in .BUILDINFO"
				fi
				echo "       <img src=\"/userContent/static/weather-showers-scattered.png\" alt=\"unreproducible icon\" /> <a href=\"/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT\">${ARTIFACT:0:-5}</a> is unreproducible$EXTRA_REASON<br />" >> $HTML_BUFFER
			fi
		done
		# we only count source packages…
		case $STATE in
			GOOD)		echo GOOD > $ARCHLINUX_PKG_PATH/pkg.state	;;
			FTBR_0)		echo FTBR_0 > $ARCHLINUX_PKG_PATH/pkg.state	;;
			FTBR_1)		if $SOME_GOOD ; then
						echo FTBR_1 > $ARCHLINUX_PKG_PATH/pkg.state
					else
						echo FTBR_2 > $ARCHLINUX_PKG_PATH/pkg.state
					fi
					;;
			*)		;;
		esac
	fi
	echo "      </td>" >> $HTML_BUFFER
	echo "      <td>$DATE" >> $HTML_BUFFER
	local DURATION=$(cat $ARCHLINUX_PKG_PATH/pkg.build_duration 2>/dev/null || true)
	if [ -n "$DURATION" ]; then
		local HOUR=$(echo "$DURATION/3600"|bc)
		local MIN=$(echo "($DURATION-$HOUR*3600)/60"|bc)
		local SEC=$(echo "$DURATION-$HOUR*3600-$MIN*60"|bc)
		BUILD_DURATION="<br />${HOUR}h:${MIN}m:${SEC}s"
	else
		BUILD_DURATION=" "
	fi
	echo "       $BUILD_DURATION</td>" >> $HTML_BUFFER

	echo "      <td>" >> $HTML_BUFFER
	for LOG in build1.log build2.log ; do
		if [ -f $ARCHLINUX_PKG_PATH/$LOG ] ; then
			if [ "$LOG" = "build2.log" ] ; then
				echo "       <br />" >> $HTML_BUFFER
			fi
			get_filesize $ARCHLINUX_PKG_PATH/$LOG
			echo "       <a href=\"/archlinux/$REPOSITORY/$SRCPACKAGE/$LOG\">$LOG</a> ($SIZE)" >> $HTML_BUFFER
		fi
	done
	echo "      </td>" >> $HTML_BUFFER
	echo "     </tr>" >> $HTML_BUFFER
	mv $HTML_BUFFER $ARCHLINUX_PKG_PATH/pkg.html
	chmod 644 $ARCHLINUX_PKG_PATH/pkg.html
}

choose_package() {
	echo "$(date -u ) - choosing package to be build."
	ARCH="x86_64"
	local RESULT=$(query_db "
		SELECT s.suite, s.id, s.name, s.version
		FROM schedule AS sch JOIN sources AS s ON sch.package_id=s.id
		WHERE sch.date_build_started is NULL
		AND s.architecture='$ARCH'
		ORDER BY date_scheduled LIMIT 5"|sort -R|head -1)
	if [ -z "$RESULT" ] ; then
		echo "No packages scheduled, sleeping 30m."
		sleep 30m
		exit 0
	fi
	SUITE=$(echo $RESULT|cut -d "|" -f1)
	REPOSITORY=$(echo $SUITE | cut -d "_" -f2)
	local SRCPKGID=$(echo $RESULT|cut -d "|" -f2)
	SRCPACKAGE=$(echo $RESULT|cut -d "|" -f3)
	VERSION=$(echo $RESULT|cut -d "|" -f4)
	# remove previous build attempts which didnt finish correctly:
	JOB_PREFIX="${JOB_NAME#reproducible_builder_}/"
	BAD_BUILDS=$(mktemp --tmpdir=$TMPDIR)
	query_db "SELECT package_id, date_build_started, job FROM schedule WHERE job LIKE '${JOB_PREFIX}%'" > $BAD_BUILDS
	if [ -s "$BAD_BUILDS" ] ; then
		local STALELOG=/var/log/jenkins/reproducible-archlinux-stale-builds.log
		# reproducible-archlinux-stale-builds.log is mailed once a day by reproducible_maintenance.sh
		echo -n "$(date -u) - stale builds found, cleaning db from these: " | tee -a $STALELOG
		cat $BAD_BUILDS | tee -a $STALELOG
		query_db "UPDATE schedule SET date_build_started = NULL, job = NULL WHERE job LIKE '${JOB_PREFIX}%'"
	fi
	rm -f $BAD_BUILDS
	# mark build attempt, first test if none else marked a build attempt recently
	echo "ok, let's check if $SRCPACKAGE is building anywhere yet…"
	RESULT=$(query_db "SELECT date_build_started FROM schedule WHERE package_id='$SRCPKGID'")
	if [ -z "$RESULT" ] ; then
		echo "ok, $SRCPACKAGE is not building anywhere…"
		# try to update the schedule with our build attempt, then check no else did it, if so, abort
		query_db "UPDATE schedule SET date_build_started='$DATE', job='$JOB' WHERE package_id='$SRCPKGID' AND date_build_started IS NULL"
		RESULT=$(query_db "SELECT date_build_started FROM schedule WHERE package_id='$SRCPKGID' AND date_build_started='$DATE' AND job='$JOB'")
		if [ -z "$RESULT" ] ; then
			echo "hm, seems $SRCPACKAGE is building somewhere… failed to update the schedule table with our build ($SRCPKGID, $DATE, $JOB)."
			handle_race_condition
		fi
	else
		echo "hm, seems $SRCPACKAGE is building somewhere… schedule table now listed it as building somewhere else."
		handle_race_condition
	fi

	echo "$(date -u ) - building package $SRCPACKAGE from '$REPOSITORY' now..."
}

first_build() {
	echo "============================================================================="
	echo "Building for Arch Linux on $(hostname -f) now."
	echo "Source package: ${SRCPACKAGE}"
	echo "Repository:     $REPOSITORY"
	echo "Date:           $(date -u)"
	echo "============================================================================="
	local SESSION="archlinux-$SRCPACKAGE-$(basename $TMPDIR)"
	local BUILDDIR="/tmp/$SRCPACKAGE-$(basename $TMPDIR)"
	local LOG=$TMPDIR/b1/$SRCPACKAGE/build1.log
	local FUTURE_STATE="disabled"
	local MAKEPKG_ENV_VARS="SOURCE_DATE_EPOCH='$SOURCE_DATE_EPOCH'"
	local MAKEPKG_OPTIONS="--syncdeps --noconfirm"
	if [ "$(hostname -f)" = "profitbricks-build4-amd64" ] ; then
		FUTURE_STATE="enabled"
		MAKEPKG_ENV_VARS="$MAKEPKG_ENV_VARS GIT_SSL_NO_VERIFY=1"
		MAKEPKG_OPTIONS="$MAKEPKG_OPTIONS --skippgpcheck"
	fi
	echo "Future:            $FUTURE_STATE"
	echo "SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"
	echo "makepkg env:       $MAKEPKG_ENV_VARS"
	echo "makepkg options:   $MAKEPKG_OPTIONS"
	echo "============================================================================="
	schroot --begin-session --session-name=$SESSION -c jenkins-reproducible-archlinux
	schroot --run-session -c $SESSION --directory /tmp -u root -- ln -sfT dash /usr/bin/sh
	echo "MAKEFLAGS=-j$NUM_CPU" | schroot --run-session -c $SESSION --directory /tmp -u root -- tee -a /etc/makepkg.conf
	schroot --run-session -c $SESSION --directory /tmp -- mkdir $BUILDDIR
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- env GIT_SSL_NO_VERIFY=1 asp checkout "$SRCPACKAGE" 2>&1 | tee -a $LOG || echo "Error: failed to download PKGBUILD for $SRCPACKAGE from $REPOSITORY" | tee -a $LOG
	# $SRCPACKAGE is actually the binary package
	ACTUAL_SRCPACKAGE=$(ls "$BUILDDIR")
	# modify timezone in the 1st build
	echo 'export TZ="/usr/share/zoneinfo/Etc/GMT+12"' | schroot --run-session -c $SESSION --directory /tmp -- tee -a /var/lib/jenkins/.bashrc
	# some more output for debugging
	set -x
	# remove possible lock in our local session (happens when root maintenance update running while session starts)
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -u root -- rm -f /var/lib/pacman/db.lck 2>&1 | tee -a $LOG
	# update before pulling new dependencies
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -u root -- pacman -Syu --noconfirm 2>&1 | tee -a $LOG
	# determine the version of the package being build
	source "$BUILDDIR/$ACTUAL_SRCPACKAGE/trunk/PKGBUILD" || echo "Failed to source PKGBUILD from '$BUILDDIR/$ACTUAL_SRCPACKAGE/trunk/PKGBUILD'" | tee -a $LOG
	if [ -n "$epoch" ] ; then
		epoch="$epoch:"
	fi
	VERSION="$epoch$pkgver-$pkgrel"
	echo $VERSION > $TMPDIR/b1/$SRCPACKAGE/build1.version
	# nicely run makepkg with a timeout of $TIMEOUT hours
	timeout -k $TIMEOUT.1h ${TIMEOUT}h /usr/bin/ionice -c 3 /usr/bin/nice \
		schroot --run-session -c $SESSION --directory "$BUILDDIR/$ACTUAL_SRCPACKAGE/trunk" -- bash -l -c "$MAKEPKG_ENV_VARS makepkg $MAKEPKG_OPTIONS 2>&1" | tee -a $LOG
	PRESULT=${PIPESTATUS[0]}
	if [ $PRESULT -eq 124 ] ; then
		echo "$(date -u) - makepkg was killed by timeout after ${TIMEOUT}h." | tee -a $LOG
	fi
	schroot --end-session -c $SESSION | tee -a $LOG
	PRESULT=${PIPESTATUS[0]}
	if [ $PRESULT -ne 0 ] ; then
		echo "$(date -u) - could not end schroot session, maybe some processes are still running? Sleeping 60 seconds and trying again…" | tee -a $LOG
		sleep 60
		schroot --end-session -f -c $SESSION | tee -a $LOG
		P2RESULT=${PIPESTATUS[0]}
		if [ $P2RESULT -ne 0 ] ; then
			echo "$(date -u) - could not end schroot session even with force. Sleeping 10 seconds and trying once more…" | tee -a $LOG
			sleep 10
			schroot --end-session -f -c $SESSION | tee -a $LOG
			P3RESULT=${PIPESTATUS[0]}
			if [ $P3RESULT -ne 0 ] ; then
				if [ -n "$(grep 'ERROR: One or more PGP signatures could not be verified' $LOG)" ] ; then
					# abort only
					exit 42
				else
					# fail with notification
					exit 23
				fi
			fi
		fi
	fi
	if ! "$DEBUG" ; then set +x ; fi
}

second_build() {
	echo "============================================================================="
	echo "Re-Building for Arch Linux on $(hostname -f) now."
	echo "Source package: ${SRCPACKAGE}"
	echo "Repository:     $REPOSITORY"
	echo "Date:           $(date -u)"
	echo "============================================================================="
	local SESSION="archlinux-$SRCPACKAGE-$(basename $TMPDIR)"
	local BUILDDIR="/tmp/$SRCPACKAGE-$(basename $TMPDIR)"
	local LOG=$TMPDIR/b2/$SRCPACKAGE/build2.log
	NEW_NUM_CPU=$(echo $NUM_CPU-1|bc)
	local FUTURE_STATE="disabled"
	local MAKEPKG_ENV_VARS="SOURCE_DATE_EPOCH='$SOURCE_DATE_EPOCH'"
	local MAKEPKG_OPTIONS="--syncdeps --noconfirm"
	if [ "$(hostname -f)" = "profitbricks-build4-amd64" ] ; then
		FUTURE_STATE="enabled"
		MAKEPKG_ENV_VARS="$MAKEPKG_ENV_VARS GIT_SSL_NO_VERIFY=1"
		MAKEPKG_OPTIONS="$MAKEPKG_OPTIONS --skippgpcheck"
	fi
	echo "Future:            $FUTURE_STATE"
	echo "SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"
	echo "makepkg env:       $MAKEPKG_ENV_VARS"
	echo "makepkg options:   $MAKEPKG_OPTIONS"
	echo "============================================================================="
	schroot --begin-session --session-name=$SESSION -c jenkins-reproducible-archlinux
	echo "MAKEFLAGS=-j$NEW_NUM_CPU" | schroot --run-session -c $SESSION --directory /tmp -u root -- tee -a /etc/makepkg.conf
	schroot --run-session -c $SESSION --directory /tmp -- mkdir $BUILDDIR
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -- env GIT_SSL_NO_VERIFY=1 asp checkout "$SRCPACKAGE" 2>&1 | tee -a $LOG || echo "Error: failed to download PKGBUILD for $SRCPACKAGE from $REPOSITORY" | tee -a $LOG
	# $SRCPACKAGE is actually the binary package
	ACTUAL_SRCPACKAGE=$(ls "$BUILDDIR")
	# add more variations in the 2nd build: TZ (differently), LANG, LC_ALL, umask
	schroot --run-session -c $SESSION --directory /tmp -- tee -a /var/lib/jenkins/.bashrc <<-__END__
	export TZ="/usr/share/zoneinfo/Etc/GMT-14"
	export LANG="fr_CH.UTF-8"
	export LC_ALL="fr_CH.UTF-8"
	umask 0002
	__END__
	# some more output for debugging
	set -x
	# remove possible lock in our local session (happens when root maintenance update running while session starts)
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -u root -- rm -f /var/lib/pacman/db.lck 2>&1 | tee -a $LOG
	# update before pulling new dependencies
	schroot --run-session -c $SESSION --directory "$BUILDDIR" -u root -- pacman -Syu --noconfirm 2>&1 | tee -a $LOG
	# determine the version of the package being build
	source "$BUILDDIR/$ACTUAL_SRCPACKAGE/trunk/PKGBUILD" || echo "Failed to source PKGBUILD from '$BUILDDIR/$ACTUAL_SRCPACKAGE/trunk/PKGBUILD'" | tee -a $LOG
	if [ -n "$epoch" ] ; then
		epoch="$epoch:"
	fi
	VERSION="$epoch$pkgver-$pkgrel"
	echo $VERSION > $TMPDIR/b2/$SRCPACKAGE/build2.version
	# nicely run makepkg with a timeout of $TIMEOUT hours
	timeout -k $TIMEOUT.1h ${TIMEOUT}h /usr/bin/ionice -c 3 /usr/bin/nice \
		schroot --run-session -c $SESSION --directory "$BUILDDIR/$ACTUAL_SRCPACKAGE/trunk" -- bash -l -c "$MAKEPKG_ENV_VARS makepkg $MAKEPKG_OPTIONS 2>&1" | tee -a $LOG
	PRESULT=${PIPESTATUS[0]}
	if [ $PRESULT -eq 124 ] ; then
		echo "$(date -u) - makepkg was killed by timeout after ${TIMEOUT}h." | tee -a $LOG
	fi
	schroot --end-session -c $SESSION | tee -a $LOG
	PRESULT=${PIPESTATUS[0]}
	if [ $PRESULT -ne 0 ] ; then
		echo "$(date -u) - could not end schroot session, maybe some processes are still running? Sleeping 60 seconds and trying again…" | tee -a $LOG
		sleep 60
		schroot --end-session -f -c $SESSION | tee -a $LOG
		P2RESULT=${PIPESTATUS[0]}
		if [ $P2RESULT -ne 0 ] ; then
			echo "$(date -u) - could not end schroot session even with force. Sleeping 10 seconds and trying once more…" | tee -a $LOG
			sleep 10
			schroot --end-session -f -c $SESSION | tee -a $LOG
			P3RESULT=${PIPESTATUS[0]}
			if [ $P3RESULT -ne 0 ] ; then
				exit 23
			fi
		fi
	fi
	if ! "$DEBUG" ; then set +x ; fi
}

remote_build() {
	local BUILDNR=$1
	local NODE=$2
	local FQDN=$NODE.debian.net
	local PORT=22
	set +e
	ssh -o "Batchmode = yes" -p $PORT $FQDN /bin/true
	RESULT=$?
	# abort job if host is down
	if [ $RESULT -ne 0 ] ; then
		SLEEPTIME=$(echo "$BUILDNR*$BUILDNR*5"|bc)
		echo "$(date -u) - $NODE seems to be down, sleeping ${SLEEPTIME}min before aborting this job."
		sleep ${SLEEPTIME}m
		unregister_build
		exit 0
	fi
	ssh -o "Batchmode = yes" -p $PORT $FQDN /srv/jenkins/bin/reproducible_build_archlinux_pkg.sh $BUILDNR $REPOSITORY ${SRCPACKAGE} ${TMPDIR} ${SOURCE_DATE_EPOCH}
	RESULT=$?
	if [ $RESULT -ne 0 ] ; then
		ssh -o "Batchmode = yes" -p $PORT $FQDN "rm -r $TMPDIR" || true
		if [ $RESULT -eq 23 ] ; then
			unregister_build
			handle_remote_error "job on $NODE could not end schroot session properly and sent error 23 so we could abort silently."
		elif [ $RESULT -eq 42 ] ; then
			unregister_build
			handle_remote_error "job on $NODE after not being able to verify pgp signatures. work to debug why ahead..."
		else
			unregister_build
			handle_remote_error "Warning: remote build failed with exit code $RESULT from $NODE for build #$BUILDNR for ${SRCPACKAGE} from $REPOSITORY."
		fi
	fi
	rsync -e "ssh -o 'Batchmode = yes' -p $PORT" -r $FQDN:$TMPDIR/b$BUILDNR $TMPDIR/
	RESULT=$?
	if [ $RESULT -ne 0 ] ; then
		echo "$(date -u ) - rsync from $NODE failed, sleeping 2m before re-trying..."
		sleep 2m
		rsync -e "ssh -o 'Batchmode = yes' -p $PORT" -r $FQDN:$TMPDIR/b$BUILDNR $TMPDIR/
		RESULT=$?
		if [ $RESULT -ne 0 ] ; then
			unregister_build
			handle_remote_error "when rsyncing remote build #$BUILDNR results from $NODE"
		fi
	fi
	ls -lR $TMPDIR
	ssh -o "Batchmode = yes" -p $PORT $FQDN "rm -r $TMPDIR"
	set -e
}

#
# below is what controls the world
#
TIMEOUT=12	# maximum time in hours for a single build
DATE=$(date -u +'%Y-%m-%d %H:%M')
START=$(date +'%s')
trap cleanup_all INT TERM EXIT

#
# determine mode
#
if [ "$1" = "" ] ; then
	MODE="master"
	TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results -d -t archlinuxrb-build-XXXXXXXX)  # where everything actually happens
	SOURCE_DATE_EPOCH=$(date +%s)
	cd $TMPDIR
elif [ "$1" = "1" ] || [ "$1" = "2" ] ; then
	MODE="$1"
	REPOSITORY="$2"
	SRCPACKAGE="$3"
	TMPDIR="$4"
	SOURCE_DATE_EPOCH="$5"
	[ -d $TMPDIR ] || mkdir -p $TMPDIR
	cd $TMPDIR
	mkdir -p b$MODE/$SRCPACKAGE
	if [ "$MODE" = "1" ] ; then
		first_build
	else
		second_build
	fi

	# preserve results and delete build directory
	if [ -n "$(ls /tmp/$SRCPACKAGE-$(basename $TMPDIR)/*/trunk/*.pkg.tar.xz)" ] ; then
		mv -v /tmp/$SRCPACKAGE-$(basename $TMPDIR)/*/trunk/*.pkg.tar.xz $TMPDIR/b$MODE/$SRCPACKAGE/
	else
		echo "$(date -u) - build #$MODE for $SRCPACKAGE on $HOSTNAME didn't build a package!"
		# debug
		echo "ls $TMPDIR/b$MODE/$SRCPACKAGE/"
		ls -Rl
	fi

	sudo rm -rf --one-file-system /tmp/$SRCPACKAGE-$(basename $TMPDIR)
	echo "$(date -u) - build #$MODE for $SRCPACKAGE on $HOSTNAME done."
	exit 0
fi

#
# main - only used in master-mode
#
delay_start # randomize start times
# first, we need to choose a package from a repository…
REPOSITORY=""
SRCPACKAGE=""
VERSION=""
SIZE=""
choose_package
mkdir -p $BASE/archlinux/$REPOSITORY/$SRCPACKAGE
# build package twice
mkdir b1 b2
# currently there are two Arch Linux build nodes… let's keep things simple
N1="profitbricks-build3-amd64"
N2="profitbricks-build4-amd64"
# if random number between 0 and 99 is greater than 60…
# (because pb4 is generally less loaded than pb3)
if [ $(( ( $RANDOM % 100 ) )) -gt 60 ] ; then
	NODE1=$N1
	NODE2=$N2
else
	NODE1=$N2
	NODE2=$N1
fi
echo "============================================================================="
echo "Initialising reproducibly build of ${SRCPACKAGE} in ${REPOSITORY} on ${ARCH} now."
echo "1st build will be done on $NODE1."
echo "2nd build will be done on $NODE2."
echo "============================================================================="
#
# do 1st build
#
remote_build 1 ${NODE1}
#
# only do the 2nd build if the 1st produced results
#
if [ ! -z "$(ls $TMPDIR/b1/$SRCPACKAGE/*.pkg.tar.xz 2>/dev/null|| true)" ] ; then
	remote_build 2 ${NODE2}
	cd $TMPDIR/b1/$SRCPACKAGE
	for ARTIFACT in *.pkg.tar.xz ; do
		[ -f $ARTIFACT ] || continue
		echo "$(date -u) - comparing results now."
		if diff -q $TMPDIR/b1/$SRCPACKAGE/$ARTIFACT $TMPDIR/b2/$SRCPACKAGE/$ARTIFACT ; then
			echo "$(date -u) - YAY - $SRCPACKAGE/$ARTIFACT build reproducible in our test framework!"
			mkdir -p $BASE/archlinux/$REPOSITORY/$SRCPACKAGE
			tar xJvf $TMPDIR/b1/$SRCPACKAGE/$ARTIFACT .BUILDINFO && mv .BUILDINFO $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT-b1.BUILDINFO.txt
			tar xJvf $TMPDIR/b2/$SRCPACKAGE/$ARTIFACT .BUILDINFO && mv .BUILDINFO $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT-b2.BUILDINFO.txt
			(
				echo "<html><body><p>$SRCPACKAGE/$ARTIFACT build reproducible in our test framework:<br />"
				(cd $TMPDIR/b1/$SRCPACKAGE ; sha256sum $ARTIFACT)
				echo "<br />"
				(sha256sum $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT-b1.BUILDINFO.txt | cut -d " " -f1)
				echo " <a href=\"$ARTIFACT-b1.BUILDINFO.txt\">$ARTIFACT-b1.BUILDINFO.txt</a><br />"
				(sha256sum $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT-b2.BUILDINFO.txt | cut -d " " -f1)
				echo " <a href=\"$ARTIFACT-b2.BUILDINFO.txt\">$ARTIFACT-b2.BUILDINFO.txt</a><br />"
				echo "</p></body>"
			) > "$BASE/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT.html"
		elif [ -f $TMPDIR/b1/$SRCPACKAGE/$ARTIFACT ] && [ -f $TMPDIR/b2/$SRCPACKAGE/$ARTIFACT ] ; then
			# run diffoscope on the results
			TIMEOUT="30m"
			DIFFOSCOPE="$(schroot --directory /tmp -c chroot:jenkins-reproducible-${DBDSUITE}-diffoscope diffoscope -- --version 2>&1)"
			echo "$(date -u) - Running $DIFFOSCOPE now..."
			call_diffoscope $SRCPACKAGE $ARTIFACT
		else
			# some packages define the package version based on the build date
			# so our two builds end up with different package versions…
			echo "$(date -u) - something is fishy with $SRCPACKAGE/$ARTIFACT."
			ls $TMPDIR/b1/$SRCPACKAGE
			ls $TMPDIR/b2/$SRCPACKAGE
			( echo "<html><body><p>$SRCPACKAGE/$ARTIFACT built in a strange unreproducible way:<br />"
			ls $TMPDIR/b1/$SRCPACKAGE
			ls $TMPDIR/b2/$SRCPACKAGE
			echo "</p></body>"
			) > "$BASE/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT.html"
		fi
		# publish page
		if [ -f $TMPDIR/$SRCPACKAGE/$ARTIFACT.html ] ; then
			cp $TMPDIR/$SRCPACKAGE/$ARTIFACT.html $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/
			#irc_message archlinux-reproducible "$REPRODUCIBLE_URL/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT.html - unreproducible"
		fi
	done
else
	echo "$(date -u) - build1 didn't create a package, skipping build2!"
fi
# publish logs
calculate_build_duration
cd $TMPDIR/b1/$SRCPACKAGE
cp build1.log $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/
[ ! -f $TMPDIR/b2/$SRCPACKAGE/build2.log ] || cp $TMPDIR/b2/$SRCPACKAGE/build2.log $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/
echo $DURATION > $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/pkg.build_duration || true
# make pkg.build_duration the oldest of this build, so we can use it as reference later
touch --date="@$START" $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/pkg.build_duration
if [ -f $TMPDIR/b2/$SRCPACKAGE/build2.version ] ; then
	cp $TMPDIR/b2/$SRCPACKAGE/build2.version $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/
	cp $TMPDIR/b2/$SRCPACKAGE/build2.version $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/pkg.version
elif [ -f build1.version ] ; then
	cp build1.version $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/
	cp $TMPDIR/b1/$SRCPACKAGE/build1.version $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/pkg.version
else
	# this should not happen but does, so deal with it
	echo "$VERSION" > $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/pkg.version
fi

echo "$(date -u) - $REPRODUCIBLE_URL/archlinux/$REPOSITORY/$SRCPACKAGE/ updated."
# force update of HTML snipplet in reproducible_html_archlinux.sh
[ ! -f $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/pkg.state ] || rm $BASE/archlinux/$REPOSITORY/$SRCPACKAGE/pkg.state
create_pkg_html
update_pkg_in_db

cd
cleanup_all
trap - INT TERM EXIT

# vim: set sw=0 noet :
