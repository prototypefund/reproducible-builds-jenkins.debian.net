#!/bin/bash
# vim: set noexpandtab:

# Copyright 2014-2019 Holger Levsen <holger@layer-acht.org>
#         © 2015-2018 Mattia Rizzolo <mattia@debian.org>
# released under the GPLv2

# Exit status of this script:
# - when run in remote mode:
#   - 2 → the build failed
#   - 3 → the build timeouted
#   - 404 → failed to download the sources

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set -e

exit_early_if_debian_is_broken() {
	# debian is fine, thanks
	if false && [ "$ARCH" = "armhf" ] ; then
		echo "Temporarily stopping the builds on armhf due to #827724… sleeping 12h now…"
		for i in $(seq 1 12) ; do
			sleep 1h
			echo "one hour passed…."
		done
		exit 0
	fi
}

create_results_dirs() {
	mkdir -vp $DEBIAN_BASE/dbd/${SUITE}/${ARCH}
	mkdir -vp $DEBIAN_BASE/dbdtxt/${SUITE}/${ARCH}
	mkdir -vp $DEBIAN_BASE/dbdjson/${SUITE}/${ARCH}
	mkdir -vp $DEBIAN_BASE/logs/${SUITE}/${ARCH}
	mkdir -vp $DEBIAN_BASE/logdiffs/${SUITE}/${ARCH}
	mkdir -vp $DEBIAN_BASE/rbuild/${SUITE}/${ARCH}
	mkdir -vp $DEBIAN_BASE/buildinfo/${SUITE}/${ARCH}
}

save_artifacts() {
		local random=$(head /dev/urandom | tr -cd '[:alnum:]'| head -c5)
		local ARTIFACTS="artifacts/r00t-me/${SRCPACKAGE}_${SUITE}_${ARCH}_tmp-${random}"
		local URL="$DEBIAN_URL/$ARTIFACTS/"
		local HEADER="$DEBIAN_BASE/$ARTIFACTS/.HEADER.html"
		mkdir -p $DEBIAN_BASE/$ARTIFACTS
		cp -r $TMPDIR/* $DEBIAN_BASE/$ARTIFACTS/ || true
		local msg="Artifacts from this build have been preserved. They will be available for 24h only, so download them now.\n"
		msg="${msg}WARNING: You shouldn't trust packages downloaded from this host, they can contain malware or the worst of your fears, packaged nicely in debian format.\n"
		msg="${msg}If you are aware of this and just want to use these artifacts to investigate why $DIFFOSCOPE had issues, you can download the artifacts from the following location: $URL\n"
		log_info "$msg"
		echo "<p>" > $HEADER
		printf "$msg" | sed 's#$#<br />#g' >> $HEADER
		echo "Package page: <a href=\"$DEBIAN_URL/${SUITE}/${ARCH}/${SRCPACKAGE}\">$DEBIAN_URL/${SUITE}/${ARCH}/${SRCPACKAGE}</a><br />" >> $HEADER
		echo "</p>" >> $HEADER
		chmod 644 $HEADER
		# irc message
		if [ ! -z "$NOTIFY" ] ; then
			local MESSAGE="Artifacts for ${SRCPACKAGE}, $STATUS in ${SUITE}/${ARCH}: $URL"
			if [ "$NOTIFY" = "diffoscope_err" ] ; then
				irc_message debian-reproducible-changes "$DEBIAN_URL/$SUITE/$ARCH/$SRCPACKAGE $STATUS and $DIFFOSCOPE failed"
				irc_message debian-reproducible-changes "$MESSAGE (error running $DIFFOSCOPE)"
				MESSAGE="$MESSAGE (error running $DIFFOSCOPE)"
			else
				# somebody explicitly asked for artifacts, so give them the artifacts
				irc_message debian-reproducible "$MESSAGE"
			fi
		fi
}

notification() {
	if [ "$SAVE_ARTIFACTS" = "1" ] ; then
		save_artifacts  # this will also notify IRC as needed
	else
		case "$NOTIFY" in  # the diffoscope_err case is handled by save_artifacts()
			''|0) ;;
			1|2)
				irc_message debian-reproducible "$DEBIAN_URL/$SUITE/$ARCH/$SRCPACKAGE done: $STATUS"
				;;
			diffoscope_timeout)
				irc_message debian-reproducible-changes "$DEBIAN_URL/$SUITE/$ARCH/$SRCPACKAGE $STATUS and $DIFFOSCOPE timed out"
				;;
			*)
				# a weird value of $NOTIFY that we don't know about
				irc_message debian-reproducible-changes "$DEBIAN_URL/$SUITE/$ARCH/$SRCPACKAGE done: '$STATUS' debug: '$NOTIFY'"
				;;
		esac
	fi
	# final compress, the RBUILDLOG is already in place.
	[ ! -f $RBUILDLOG ] || gzip -9fvn $RBUILDLOG
	# XXX quite ugly: this is just needed to update the sizes of the
	# compressed files in the html. It's cheap and quite safe so, *shrugs*...
	gen_package_html $SRCPACKAGE
}

cleanup_all() {
	echo "Starting cleanup."
	cd  # move out of $TMPDIR, if we are still inside
	if [ "$MODE" = "master" ] ; then
		notification
		# the TMPDIR in the remote nodes is removed by a later ssh call
		# from master after the artifacts have been copied out.
		rm -r $TMPDIR || true
	fi
	echo "All cleanup done."
	print_out_duration
}

update_db_and_html() {
	#
	# save everything as status of this package in the db
	#
	STATUS="$@"
	local OLD_STATUS=$(query_db "SELECT status FROM results WHERE package_id='${SRCPKGID}'" || \
			   query_db "SELECT status FROM results WHERE package_id='${SRCPKGID}'")
	# irc+mail notifications for changing status in unstable and experimental
	if [ "$SUITE" = "unstable" ] || [ "$SUITE" = "experimental" ] ; then
		if ([ "$OLD_STATUS" = "reproducible" ] && ( [ "$STATUS" = "FTBR" ] || [ "$STATUS" = "FTBFS" ] || [ "$STATUS" = "timeout" ])) || \
			([ "$OLD_STATUS" = "FTBR" ] && [ "$STATUS" = "FTBFS" ] ); then
			MESSAGE="${DEBIAN_URL}/${SUITE}/${ARCH}/${SRCPACKAGE} : ${OLD_STATUS} ➤ ${STATUS}"
			log_info "$MESSAGE"
			irc_message debian-reproducible-changes "$MESSAGE"
		fi
		if [ "$OLD_STATUS" != "$STATUS" ] && [ "$NOTIFY_MAINTAINER" -eq 1 ] && \
		  [ "$OLD_STATUS" != "depwait" ] && [ "$STATUS" != "depwait" ] && \
		  [ "$OLD_STATUS" != "E404" ] && [ "$STATUS" != "E404" ]; then
			# spool notifications and mail them once a day
			mkdir -p /srv/reproducible-results/notification-emails
			echo "$(date -u +'%Y-%m-%d %H:%M') $DEBIAN_URL/$SUITE/$ARCH/$SRCPACKAGE changed from $OLD_STATUS -> $STATUS" >> /srv/reproducible-results/notification-emails/$SRCPACKAGE
		fi
	fi
	# Insert or update existing entry in results table
	query_db "INSERT INTO results (package_id, version, status, build_date, build_duration, node1, node2, job) VALUES ('$SRCPKGID', '$VERSION', '$STATUS', '$DATE', '$DURATION', '$NODE1', '$NODE2', '$JOB') ON CONFLICT (package_id) DO UPDATE SET version='$VERSION', status='$STATUS', build_date='$DATE', build_duration='$DURATION', node1='$NODE1', node2='$NODE2', job='$JOB' WHERE results.package_id='$SRCPKGID'"
	query_db "INSERT INTO stats_build (name, version, suite, architecture, status, build_date, build_duration, node1, node2, job) VALUES ('$SRCPACKAGE', '$VERSION', '$SUITE', '$ARCH', '$STATUS', '$DATE', '$DURATION', '$NODE1', '$NODE2', '$JOB')"
	# unmark build since it's properly finished
	query_db "DELETE FROM schedule WHERE package_id='$SRCPKGID' AND build_type='ci_build';"
	gen_package_html $SRCPACKAGE
	echo
	echo "$(date -u) - successfully updated the database and updated $DEBIAN_URL/rb-pkg/${SUITE}/${ARCH}/$SRCPACKAGE.html"
	echo
}

update_rbuildlog() {
	chmod 644 $RBUILDLOG
	mv $RBUILDLOG $DEBIAN_BASE/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_${EVERSION}.rbuild.log
	RBUILDLOG=$DEBIAN_BASE/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_${EVERSION}.rbuild.log
}

diff_copy_buildlogs() {
	local DIFF="$DEBIAN_BASE/logdiffs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.diff"
	if [ -f b1/build.log ] ; then
		if [ -f b2/build.log ] ; then
			printf "Diff of the two buildlogs:\n\n--\n" | tee -a $DIFF
			LOCALDIFFTIMEOUT="30m"
			timeout $LOCALDIFFTIMEOUT diff -u b1/build.log b2/build.log | tee -a $DIFF
			if [ ${PIPESTATUS[0]} -eq 0 ] ; then
				echo "The two build logs are identical! \o/" | tee -a $DIFF
			elif [ ${PIPESTATUS[0]} -eq 124 ] ; then
				echo "Diffing the two build logs ran into timeout after $LOCALDIFFTIMEOUT, sorry." | tee -a $DIFF
			fi
			echo -e "\nCompressing the 2nd log..."
			gzip -9vn $DIFF
			gzip -9cvn b2/build.log > $DEBIAN_BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build2.log.gz
			chmod 644 $DEBIAN_BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build2.log.gz
		elif [ "${1:-}" = "ftbfs" ] ; then
			log_warning "No second build log, what happened?"
		fi
		echo "Compressing the 1st log..."
		gzip -9cvn b1/build.log > $DEBIAN_BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build1.log.gz
		chmod 644 $DEBIAN_BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build1.log.gz
	else
		log_error "No first build log, not even looking for the second"
	fi
}

handle_E404() {
	log_warning "Download of ${SRCPACKAGE} sources from ${SUITE} failed."
	ls -l ${SRCPACKAGE}* | log_file -
	log_warning "Maybe there was a network problem, or ${SRCPACKAGE} is not a source package in ${SUITE}, or it was removed or renamed. Please investigate. Sleeping 30m as this should not happen."
	DURATION=0
	update_rbuildlog
	update_db_and_html "E404"
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=0 ; fi
	if [ ! -z "$NOTIFY" ] ; then NOTIFY="failure" ; fi
	sleep 30m
	exit 0 # RBUILDLOG and SAVE_ARTIFACTS and NOTIFY are used in cleanup_all called at exit
}

handle_depwait() {
	log_warning "Downloading the build dependencies failed"
	log_warning "Maybe there was a network problem, or the build dependencies are currently uninstallable; consider filing a bug in the last case."
	log_warning "Network problems are automatically rescheduled after some hours."
	calculate_build_duration
	update_db_and_html "depwait"
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=0 ; fi
	if [ -n "$NOTIFY" ] ; then NOTIFY="depwait" ; fi
	exit 0
}

handle_NFU() {
	# a list of valid architecture for this package should be passed to this function
	log_info "Package ${SRCPACKAGE} (${VERSION}) shall only be build on \"$(echo "$@" | xargs echo )\" and thus was skipped."
	DURATION=0
	update_rbuildlog
	update_db_and_html "NFU"
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=0 ; fi
	if [ ! -z "$NOTIFY" ] ; then NOTIFY="failure" ; fi
	exit 0 # RBUILDLOG and SAVE_ARTIFACTS and NOTIFY are used in cleanup_all called at exit
}

handle_timeout() {
	echo "${SRCPACKAGE} build timed out"
	cleanup_pkg_files
	diff_copy_buildlogs
	update_rbuildlog
	calculate_build_duration
	update_db_and_html "timeout"
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=0 ; fi
	if [ ! -z "$NOTIFY" ] ; then NOTIFY="timeout" ; fi
	exit 0
}

handle_ftbfs() {
	echo "${SRCPACKAGE} failed to build from source."
	cleanup_pkg_files
	diff_copy_buildlogs ftbfs
	update_rbuildlog
	local BUILD NEEDLE
	for BUILD in "1" "2"; do
		local nodevar="NODE$BUILD"
		local node=""
		# eval is needed here, because we want the value of $node1 or $node2
		eval node=\$$nodevar
		if [ ! -f "$DEBIAN_BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build${BUILD}.log.gz" ] ; then
			continue
		fi
		if zgrep -q -F "E: pbuilder-satisfydepends failed." "$DEBIAN_BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build${BUILD}.log.gz" ; then
			handle_depwait
		fi
		for NEEDLE in \
			'^tar:.*Cannot write: No space left on device' \
			'fatal error: error writing to .* No space left on device' \
			'./configure: line .* printf: write error: No space left on device' \
			'cat: write error: No space left on device' '^dpkg-deb.*No space left on device' \
			'^cp: (erreur|impossible).*No space left on device' '^tee: .* No space left on device' \
			'^zip I/O error: No space left on device' \
			'^mkdir .*: No space left on device' \
			'exceeds available storage space.*\(No space left on device\)$' \
			'^dpkg-source: error: cannot create directory .* No space left on device$' \
			'Requested size .* exceeds available storage space .*\(No space left on device\)$' \
			; do
			if zgrep -q -e "$NEEDLE" "$DEBIAN_BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build${BUILD}.log.gz" ; then
				handle_enospace $node
			fi
		done
		# notify about unkown diskspace issues where we are not 100% sure yet those are diskspace issues
		# ignore syslinux, clisp, klibc and glibc which are false positives…
		if zgrep -e "No space left on device" "$DEBIAN_BASE/logs/$SUITE/$ARCH/${SRCPACKAGE}_${EVERSION}.build${BUILD}.log.gz" && [ "$SRCPACKAGE" != "syslinux" ] && [ "$SRCPACKAGE" != "clisp" ] && [ "$SRCPACKAGE" != "klibc" ] && [ "$SRCPACKAGE" != "glibc" ]; then
			MESSAGE="${BUILD_URL}console.log for ${SRCPACKAGE} (ftbfs in $SUITE/$ARCH) _probably_ had a diskspace issue on $node. Please check, tune handle_ftbfs() and reschedule the package."
			echo $MESSAGE | tee -a /var/log/jenkins/reproducible-diskspace-issues.log
			irc_message debian-reproducible "$MESSAGE"
		fi
	done
	calculate_build_duration
	update_db_and_html "FTBFS"
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then SAVE_ARTIFACTS=0 ; fi
	if [ ! -z "$NOTIFY" ] ; then NOTIFY="failure" ; fi
	exit 0
}

handle_ftbr() {
	# a ftbr explaination message could be passed
	local FTBRmessage="$@"
	log_error "${SRCPACKAGE} failed to build reproducibly in ${SUITE} on ${ARCH}."
	cp b1/${BUILDINFO} $DEBIAN_BASE/buildinfo/${SUITE}/${ARCH}/ > /dev/null 2>&1 || true  # will fail if there is no .buildinfo
	if [ ! -z "$FTRmessage" ] ; then
		log_error "${FTBRmessage}."
	fi
	if [ -f ./${DBDREPORT} ] ; then
		mv ./${DBDREPORT} $DEBIAN_BASE/dbd/${SUITE}/${ARCH}/
	else
		log_warning "$DIFFOSCOPE produced no output (which is strange)."
	fi
	if [ -f ./$DBDTXT ] ; then
		mv ./$DBDTXT $DEBIAN_BASE/dbdtxt/$SUITE/$ARCH/
		gzip -9n $DEBIAN_BASE/dbdtxt/$SUITE/$ARCH/$DBDTXT
	fi
	if [ -f ./$DBDJSON ] ; then
		mv ./$DBDJSON $DEBIAN_BASE/dbdjson/$SUITE/$ARCH/
		gzip -9n $DEBIAN_BASE/dbdjson/$SUITE/$ARCH/$DBDJSON
	fi
	calculate_build_duration
	update_db_and_html "FTBR"
}

handle_reproducible() {
	if [ ! -f ./${DBDREPORT} ] && [ -f b1/${BUILDINFO} ] ; then
		cp b1/${BUILDINFO} $DEBIAN_BASE/buildinfo/${SUITE}/${ARCH}/ > /dev/null 2>&1
		figlet ${SRCPACKAGE}
		log_info "$DIFFOSCOPE found no differences in the changes files, and a .buildinfo file also exists."
		log_info "${SRCPACKAGE} from $SUITE built successfully and reproducibly on ${ARCH}."
		calculate_build_duration
		update_db_and_html "reproducible"
	elif [ -f ./$DBDREPORT ] ; then
		log_warning "Diffoscope claims the build is reproducible, but there is a diffoscope file. Please investigate."
		handle_ftbr
	elif [ ! -f b1/$BUILDINFO ] ; then
		log_warning "Diffoscope claims the build is reproducible, but there is no .buildinfo file. Please investigate."
		handle_ftbr
	fi
}

handle_env_changes() {
	unregister_build
	MESSAGE="$(date -u ) - ${BUILD_URL}console.log encountered a problem: $1"
	echo -e "$MESSAGE" | tee -a /var/log/jenkins/reproducible-env-changes.log
	# no need to slow down
	exit 0
}

handle_enospace() {
	unregister_build
	MESSAGE="${BUILD_URL}console.log hit diskspace issues with $SRCPACKAGE on $SUITE/$ARCH on $1, sleeping 60m."
	echo "$MESSAGE"
	echo "$MESSAGE" | mail -s "$JOB on $1 ran into diskspace problems" qa-jenkins-scm@lists.alioth.debian.org
	echo "Sleeping 60m before aborting the job."
	sleep 60m
	exit 0
}

dbd_timeout() {
	local msg="$DIFFOSCOPE was killed after running into timeout after $1"
	if [ ! -s ./${DBDREPORT} ] ; then
		echo "$(date -u) - $DIFFOSCOPE produced no output and was killed after running into timeout after ${1}..." >> ${DBDREPORT}
	else
		msg="$msg, but there is still $DEBIAN_URL/dbd/$SUITE/$ARCH/$DDBREPORT"
	fi
	SAVE_ARTIFACTS=0
	NOTIFY="diffoscope_timeout"
	handle_ftbr "$msg"
}

call_diffoscope_on_changes_files() {
	# filter lines describing .buildinfo files from .changes file
	sed -i -e '/^ [a-f0-9]\{32,64\} .*\.buildinfo$/d' b{1,2}/$CHANGES
	local TMPLOG=$(mktemp --tmpdir=$TMPDIR)
	local TIMEOUT="120m"  # note that below there is another instance of this + 5 minutes
	DBDSUITE=$SUITE
	if [ "$SUITE" = "experimental" ] ; then
		# there is no extra diffoscope-schroot for experimental ( because we specical case ghc enough already )
		DBDSUITE="unstable"
	fi
	# diffoscope temporary files are going to end up in this
	local TEMP=$(mktemp --tmpdir=$TMPDIR -d dbd-tmp-XXXXXXX)
	local session="$(schroot --begin-session -c "chroot:jenkins-reproducible-$DBDSUITE-diffoscope")"
	DIFFOSCOPE="$(schroot --directory $TMPDIR --run-session -c "$session" diffoscope -- --version 2>&1 || true)"
	log_info "$DIFFOSCOPE will be used to compare the two builds:"
	set +e
	set -x
	( timeout 125m nice schroot \
		--directory $TMPDIR \
		--run-session \
		-c "$session" \
		-- sh -c "export TMPDIR=$TEMP ; timeout $TIMEOUT diffoscope \
			--html $TMPDIR/${DBDREPORT} \
			--text $TMPDIR/$DBDTXT \
			--json $TMPDIR/$DBDJSON \
			--profile=- \
			$TMPDIR/b1/${CHANGES} \
			$TMPDIR/b2/${CHANGES}" \
	2>&1 ) >> $TMPLOG
	RESULT=$?
	if ! "$DEBUG" ; then set +x ; fi
	set -e
	log_file $TMPLOG  # print dbd output
	schroot --end-session -c "$session"
	rm $TMPLOG
	case $RESULT in
		0)
			handle_reproducible
			;;
		1)
			handle_ftbr "$DIFFOSCOPE found issues, please check $DEBIAN_URL/dbd/${SUITE}/${ARCH}/${DBDREPORT}"
			;;
		2)
			SAVE_ARTIFACTS=1
			NOTIFY="diffoscope_err"
			handle_ftbr "$DIFFOSCOPE had trouble comparing the two builds. Please investigate $DEBIAN_URL/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_${EVERSION}.rbuild.log"
			;;
		124)
			dbd_timeout $TIMEOUT
			;;
		*)
			# Process killed by signal exits with 128+${signal number}.
			# 31 = SIGSYS = maximum signal number in signal(7)
			if (( $RESULT > 128 )) && (( $RESULT <= 128+31 )); then
				RESULT="$RESULT (SIG$(kill -l $(($RESULT - 128))))"
			fi
			local MSG_PART1="Something weird happened, $DIFFOSCOPE exited with $RESULT and I don't know how to handle it."
			handle_ftbr "$MSG_PART1"
			irc_message debian-reproducible-changes "$MSG_PART1 Please check $RBUILDLOG and $DEBIAN_URL/$SUITE/$ARCH/$SRCPACKAGE"
			;;
	esac
}

choose_package() {
	DISTROID=$(query_db "SELECT id FROM distributions WHERE name='debian'")
	local RESULT=$(query_db "
		SELECT s.suite, s.id, s.name, s.version, sch.save_artifacts, sch.notify, s.notify_maintainer, sch.date_scheduled
		FROM schedule AS sch JOIN sources AS s ON sch.package_id=s.id
		WHERE sch.date_build_started is NULL
		AND sch.build_type='ci_build'
		AND s.distribution=$DISTROID
		AND s.architecture='$ARCH'
		ORDER BY date_scheduled LIMIT 5"|sort -R|head -1)
	if [ -z "$RESULT" ] ; then
		echo "No packages scheduled, sleeping 30m."
		sleep 30m
		exit 0
	fi
	SUITE=$(echo $RESULT|cut -d "|" -f1)
	SRCPKGID=$(echo $RESULT|cut -d "|" -f2)
	SRCPACKAGE=$(echo $RESULT|cut -d "|" -f3)
	VERSION=$(echo $RESULT|cut -d "|" -f4)
	SAVE_ARTIFACTS=$(echo $RESULT|cut -d "|" -f5)
	NOTIFY=$(echo $RESULT|cut -d "|" -f6)
	NOTIFY_MAINTAINER=$(echo $RESULT|cut -d "|" -f7)
	# remove previous build attempts which didnt finish correctly:
	JOB_PREFIX="${JOB_NAME#reproducible_builder_}/"
	BAD_BUILDS=$(mktemp --tmpdir=$TMPDIR)
	query_db "SELECT package_id, date_build_started, job FROM schedule WHERE job LIKE '${JOB_PREFIX}%'" > $BAD_BUILDS
	if [ -s "$BAD_BUILDS" ] ; then
		local STALELOG=/var/log/jenkins/reproducible-stale-builds.log
		# reproducible-stale-builds.log is mailed once a day by reproducible_maintenance.sh
		echo -n "$(date -u) - stale builds found, cleaning db from these: " | tee -a $STALELOG
		cat $BAD_BUILDS | tee -a $STALELOG
		query_db "UPDATE schedule SET date_build_started = NULL, job = NULL WHERE job LIKE '${JOB_PREFIX}%'"
	fi
	rm -f $BAD_BUILDS
	# mark build attempt, first test if none else marked a build attempt recently
	echo "ok, let's check if $SRCPACKAGE is building anywhere yet…"
	RESULT=$(query_db "SELECT date_build_started FROM schedule WHERE package_id='$SRCPKGID' AND build_type='ci_build'")
	if [ -z "$RESULT" ] ; then
		echo "ok, $SRCPACKAGE is not building anywhere…"
		# try to update the schedule with our build attempt, then check no else did it, if so, abort
		query_db "UPDATE schedule SET date_build_started='$DATE', job='$JOB' WHERE package_id='$SRCPKGID' AND build_type='ci_build' AND date_build_started IS NULL"
		RESULT=$(query_db "SELECT date_build_started FROM schedule WHERE package_id='$SRCPKGID' AND date_build_started='$DATE' AND job='$JOB' AND build_type='ci_build'")
		if [ -z "$RESULT" ] ; then
			echo "hm, seems $SRCPACKAGE is building somewhere… failed to update the schedule table with our build ($SRCPKGID, $DATE, $JOB)."
			handle_race_condition
		fi
	else
		echo "hm, seems $SRCPACKAGE is building somewhere… schedule table now listed it as building somewhere else."
		handle_race_condition
	fi
	local ANNOUNCE=""
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then
		ANNOUNCE="Artifacts will be preserved."
	fi
	create_results_dirs
	echo "============================================================================="
	echo "Initialising reproducibly build of ${SRCPACKAGE} in ${SUITE} on ${ARCH} on $(hostname) now. $ANNOUNCE"
	echo "1st build will be done on $NODE1."
	echo "2nd build will be done on $NODE2."
	echo "============================================================================="
	# force debug mode for certain packages
	case $SRCPACKAGE in
		xxxxxxx)
			export DEBUG=true
			set -x
			irc_message debian-reproducible "$SRCPACKAGE/$SUITE/$ARCH started building at ${BUILD_URL}console.log"
			;;
		*)      ;;
	esac
	if [ "$NOTIFY" = "2" ] ; then
		irc_message debian-reproducible "$SRCPACKAGE/$SUITE/$ARCH started building at ${BUILD_URL}console.log"
	elif [ "$NOTIFY" = "0" ] ; then  # the build script has a different idea of notify than the scheduler,
		NOTIFY=''                  # the scheduler uses integers, build.sh uses strings.
	fi
	log_info "starting to build ${SRCPACKAGE}/${SUITE}/${ARCH} on $(hostname) on '$DATE'"
	log_info "The jenkins build log is/was available at ${BUILD_URL}console.log"
}

download_source() {
	log_info "Downloading source for ${SUITE}/${SRCPACKAGE}=${VERSION}"
	set +e
	local TMPLOG=$(mktemp --tmpdir=$TMPDIR)
	if [ "$MODE" != "master" ] ; then
		chdist --data-dir="$CHPATH" apt-get "$SUITE-$ARCH" --download-only --only-source source ${SRCPACKAGE}=${VERSION} 2>&1 | tee ${TMPLOG}
	else
		# the build master only needs to the the .dsc file
		chdist --data-dir="$CHPATH" apt-get "$SUITE-$(dpkg --print-architecture)" --download-only --only-source --print-uris source ${SRCPACKAGE}=${VERSION} | grep \.dsc|cut -d " " -f1|xargs -r wget --timeout=180 --tries=3 2>&1 | tee ${TMPLOG}
	fi
	local ENGLISH_RESULT=$(egrep 'E: (Unable to find a source package for|Failed to fetch.*(Unable to connect to|Connection failed|Size mismatch|Cannot initiate the connection to|Bad Gateway|Service Unavailable))' ${TMPLOG})
	local FRENCH_RESULT=$(egrep 'E: (Unable to find a source package for|impossible de récupérer.*(Unable to connect to|Échec de la connexion|Size mismatch|Cannot initiate the connection to|Bad Gateway|Service Unavailable))' ${TMPLOG})
	PARSED_RESULT="${ENGLISH_RESULT}${FRENCH_RESULT}"
	log_file ${TMPLOG}
	rm ${TMPLOG}
	set -e
}

download_again_if_needed() {
	if [ "$(ls ${SRCPACKAGE}_${EVERSION}.dsc 2> /dev/null)" = "" ] || [ ! -z "$PARSED_RESULT" ] ; then
		# sometimes apt-get cannot download a package for whatever reason.
		# if so, wait some time and try again. only if that fails, give up.
		log_error "Download of ${SRCPACKAGE}=${VERSION} sources (for ${SUITE}) failed."
		ls -l ${SRCPACKAGE}* | log_file -
		log_error "Sleeping 5m before re-trying..."
		sleep 5m
		download_source
	fi
}

get_source_package() {
	PARSED_RESULT=""
	EVERSION="$(echo $VERSION | cut -d ':' -f2)"  # EPOCH_FREE_VERSION is too long
	DBDREPORT="${SRCPACKAGE}_${EVERSION}.diffoscope.html"
	DBDTXT="${SRCPACKAGE}_${EVERSION}.diffoscope.txt"
	DBDJSON="${SRCPACKAGE}_${EVERSION}.diffoscope.json"
	BUILDINFO="${SRCPACKAGE}_${EVERSION}_${ARCH}.buildinfo"
	BUILDINFO_SIGNED="${BUILDINFO}.asc"

	download_source
	download_again_if_needed
	download_again_if_needed
	download_again_if_needed # yes, this is called three times. this should really not happen
	if [ "$(ls ${SRCPACKAGE}_${EVERSION}.dsc 2> /dev/null)" = "" ] || [ ! -z "$PARSED_RESULT" ] ; then
		if [ "$MODE" = "master" ] ; then
			handle_E404
		else
			exit 404
		fi
	fi
}

check_suitability() {
	log_info "Checking whether the package is not for us"

	local SUITABLE=false
	local ARCHITECTURES=$(grep "^Architecture: " ${SRCPACKAGE}_*.dsc| cut -d " " -f2- | sed -s "s# #\n#g" | sort -u)

	# packages that are *only* arch:all can be tried on any arch
	if [ "$ARCHITECTURES" = "all" ]; then
		ARCHITECTURES="any"
	fi

	for arch in ${ARCHITECTURES} ; do
		if [ "$arch" = "any" ] || [ "$arch" = "$ARCH" ] || [ "$arch" = "linux-any" ] || [ "$arch" = "linux-$ARCH" ] || [ "$arch" = "any-$ARCH" ] ; then
			SUITABLE=true
			break
		fi
		# special case arm…
		if ( [ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ] ) && [ "$arch" = "any-arm" ] ; then
			SUITABLE=true
			break
		fi

	done
	if ! $SUITABLE ; then handle_NFU $ARCHITECTURES ; fi
}

first_build() {
	echo "============================================================================="
	echo "Building ${SRCPACKAGE} in ${SUITE} on ${ARCH} on $(hostname) now."
	echo "Date:     $(date)"
	echo "Date UTC: $(date -u)"
	echo "============================================================================="
	if [ "${ARCH}" = "armhf" ]; then
		# Reduce parallelism on armhf systems with a lot of cores to
		# reduce swapping on highly parallel builds. Also ensure first
		# build is always an odd number of CPUs for good measure.
		case $NUM_CPU in
			2|4) NUM_CPU=3 ;;
			*) NUM_CPU=5 ;;
		esac
	fi
	local TMPCFG=$(mktemp -t pbuilderrc_XXXX --tmpdir=$TMPDIR)
	cat > "$TMPCFG" << EOF
BUILDUSERID=1111
export BUILDUSERNAME=pbuilder1
export BUILDUSERGECOS="first user,first room,first work-phone,first home-phone,first other"
# pbuilder sets HOME to the value of BUILD_HOME…
BUILD_HOME=/nonexistent/first-build
export DEB_BUILD_OPTIONS="buildinfo=+all reproducible=+all parallel=$NUM_CPU"
export TZ="/usr/share/zoneinfo/Etc/GMT+12"
export LANG="C"
unset LC_ALL
export LANGUAGE="en_US:en"
EOF
	# build path is only varied on unstable and experimental
	if [ "${SUITE}" = "unstable" ] || [ "$SUITE" = "experimental" ]; then
		echo "BUILDDIR=/build/1st" >> "$TMPCFG"
	else
		echo "BUILDDIR=/build" >> "$TMPCFG"
	fi
	if [ "$SRCPACKAGE" = "debian-installer" -o "$SRCPACKAGE" = "debian-installer-netboot-images" ] ; then
		# d-i needs to access to a debian-archive.  this is not possible in
		# pbuilder, so grant complete network access to it.
		echo "USENETWORK=yes" >> "$TMPCFG"
	fi
	DEBBUILDOPTS="-b"
	BINARYTARGET=""
	if [ "${ARCH}" = "armhf" ] && [ "${SRCPACKAGE}" = "u-boot" ]; then
		# u-boot dependencies for arch:all on armhf are not available,
		# as it uses cross-compilers for several architectures.
		DEBBUILDOPTS="-B"
		BINARYTARGET="--binary-arch"
	fi
	set +e
	# remember to change the sudoers setting if you change the following command
	sudo timeout -k 18.1h 18h /usr/bin/ionice -c 3 /usr/bin/nice \
	  /usr/sbin/pbuilder --build \
		--configfile $TMPCFG \
		--debbuildopts "$DEBBUILDOPTS" \
		$BINARYTARGET \
		--basetgz /var/cache/pbuilder/$SUITE-reproducible-base.tgz \
		--buildresult $TMPDIR/b1 \
		--logfile b1/build.log \
		${SRCPACKAGE}_${EVERSION}.dsc
	local PRESULT=$?
	set -e
	if ! "$DEBUG" ; then set +x ; fi
	rm $TMPCFG
	case $PRESULT in
		124)
			echo "$(date -u) - pbuilder was killed by timeout after 18h." | tee -a b1/build.log
			exit 3
			;;
		1)  # FTBFS, for whatever reason.
			exit 2
			;;
	esac
}

second_build() {
	echo "============================================================================="
	echo "Re-Building ${SRCPACKAGE} in ${SUITE} on ${ARCH} on $(hostname) now."
	echo "Date:     $(date)"
	echo "Date UTC: $(date -u)"
	echo "============================================================================="
	set -x
	local TMPCFG=$(mktemp -t pbuilderrc_XXXX --tmpdir=$TMPDIR)
	# on amd64+i386 we vary this based on node choices (by design)
	if [ "${ARCH}" = "armhf" ]; then
		# Reduce parallelism on armhf systems with a lot of cores to
		# reduce swapping on highly parallel builds. Keep second build
		# with even number of cores.
		case $NUM_CPU in
			8) NUM_CPU=6 ;;
		esac
	fi
	# differ locale+language depending on the architecture (mostly for readability by different people…)
	case $ARCH in
		armhf)	locale=it_CH
			language=it
			;;
		arm64)	locale=nl_BE
			language=nl
			;;
		i386)	locale=de_CH
			language=de
			;;
		*)	locale=et_EE
			language=et
			;;
	esac
	cat > "$TMPCFG" << EOF
BUILDUSERID=2222
export BUILDUSERNAME=pbuilder2
export BUILDUSERGECOS="second user,second room,second work-phone,second home-phone,second other"
# pbuilder sets HOME to the value of BUILD_HOME…
BUILD_HOME=/nonexistent/second-build
export DEB_BUILD_OPTIONS="buildinfo=+all reproducible=+all parallel=$NUM_CPU"
export TZ="/usr/share/zoneinfo/Etc/GMT-14"
export LANG="$locale.UTF-8"
export LC_ALL="$locale.UTF-8"
export LANGUAGE="$locale:$language"
umask 0002
EOF
	# build path is only varied on unstable and experimental
	if [ "${SUITE}" = "unstable" ] || [ "$SUITE" = "experimental" ]; then
		local src_dir_name="$(perl -mDpkg::Source::Package -e '$_ = Dpkg::Source::Package->new(filename => $ARGV[0])->get_basename; s/_/-/g; print' -- "${SRCPACKAGE}_${EVERSION}.dsc")"
		echo "BUILDDIR=/build/2/$src_dir_name" >> "$TMPCFG"
		echo "BUILDSUBDIR=2nd" >> "$TMPCFG"
	else
		echo "BUILDDIR=/build" >> "$TMPCFG"
	fi
	if [ "$SRCPACKAGE" = "debian-installer" -o "$SRCPACKAGE" = "debian-installer-netboot-images" ] ; then
		# d-i needs to access to a debian-archive.  this is not possible in
		# pbuilder, so grant complete network access to it.
		echo "USENETWORK=yes" >> "$TMPCFG"
	fi

	local pbuilder_options=()
	case "${SUITE}" in
		(unstable|experimental|bullseye)
			pbuilder_options+=(--extrapackages usrmerge)
			;;
	esac
	DEBBUILDOPTS="-b"
	BINARYTARGET=""
	if [ "${ARCH}" = "armhf" ] && [ "${SRCPACKAGE}" = "u-boot" ]; then
		# u-boot dependencies for arch:all on armhf are not
		# available, as it uses cross-compilers for several
		# architectures.
		DEBBUILDOPTS="-B"
		BINARYTARGET="--binary-arch"
	fi
	set +e
	# remember to change the sudoers setting if you change the following command
	# (the 2nd build gets a longer timeout trying to make sure the first build
	# aint wasted when then 2nd happens on a highly loaded node)
	sudo timeout -k 24.1h 24h /usr/bin/ionice -c 3 /usr/bin/nice -n 11 \
		/usr/bin/unshare --uts -- \
		/usr/sbin/pbuilder --build \
			--configfile $TMPCFG \
			--hookdir /etc/pbuilder/rebuild-hooks \
			--debbuildopts "$DEBBUILDOPTS" \
			$BINARYTARGET \
			--basetgz /var/cache/pbuilder/$SUITE-reproducible-base.tgz \
			--buildresult $TMPDIR/b2 \
			--logfile b2/build.log \
			"${pbuilder_options[@]}" \
			${SRCPACKAGE}_${EVERSION}.dsc
	local PRESULT=$?
	set -e
	if ! "$DEBUG" ; then set +x ; fi
	rm $TMPCFG
	case $PRESULT in
		124)
			echo "$(date -u) - pbuilder was killed by timeout after 24h." | tee -a b2/build.log
			exit 3
			;;
		1)  # FTBFS, for whatever reason.
			exit 2
			;;
	esac

}

check_node_is_up() {
	# this actually tests three things:
	# - the node is not listed in ~/offline_nodes
	# - ssh login works
	# - /tmp is not mounted in read-only mode
	local NODE=$1
	local SLEEPTIME=$2
	set +e
	echo "$(date -u) - checking ~/offline_nodes if $NODE is marked as down."
	if grep -q $NODE ~/offline_nodes >/dev/null 2>&1 ; then
		echo "$(date -u) - $NODE seems to marked as down, sleeping ${SLEEPTIME}min before aborting this job."
		unregister_build
		sleep ${SLEEPTIME}.1337m
		exit 0
	fi
	echo "$(date -u) - checking via ssh if $NODE is up."
	ssh -o "BatchMode = yes" $NODE 'rm -v $(mktemp --tmpdir=/tmp read-only-fs-test-XXXXXX)'
	RESULT=$?
	# abort job if host is down
	if [ $RESULT -ne 0 ] ; then
		echo "$(date -u) - $NODE seems to be down, sleeping ${SLEEPTIME}min before aborting this job."
		unregister_build
		sleep ${SLEEPTIME}.1337m
		exit 0
	fi
	set -e
}

check_nodes_are_up() {
	local SLEEPTIME=30
	get_node_information $NODE1
	check_node_is_up $NODE1 $SLEEPTIME
	get_node_information $NODE2
	check_node_is_up $NODE2 $SLEEPTIME
}

remote_build() {
	local BUILDNR=$1
	local NODE=$2
	log_info "Preparing to do remote build '$BUILDNR' on $NODE."
	get_node_information $NODE
	# sleep 15min if first node is down
	# but 1h if the 2nd node is down
	local SLEEPTIME=$(echo "$BUILDNR*$BUILDNR*15"|bc)
	check_node_is_up $NODE $SLEEPTIME
	set +e
	ssh -o "BatchMode = yes" $NODE /srv/jenkins/bin/reproducible_build.sh $BUILDNR ${SRCPACKAGE} ${SUITE} ${TMPDIR} "$VERSION"
	local BUILD_RESULT=$?
	rsync -e "ssh -o 'BatchMode = yes'" -r $NODE:$TMPDIR/b$BUILDNR $TMPDIR/
	local RSYNC_RESULT=$?
	if [ $RSYNC_RESULT -ne 0 ] ; then
		log_warning "rsync from $NODE failed, sleeping 2m before re-trying..."
		sleep 2m
		rsync -e "ssh -o 'BatchMode = yes'" -r $NODE:$TMPDIR/b$BUILDNR $TMPDIR/
		local RSYNC_RESULT=$?
		if [ $RSYNC_RESULT -ne 0 ] ; then
			unregister_build
			handle_remote_error "when rsyncing remote build #$BUILDNR results from $NODE"
		fi
	fi
	ls -lR $TMPDIR
	log_info "Deleting \$TMPDIR on $NODE."
	ssh -o "BatchMode = yes" $NODE "rm -r $TMPDIR"
	set -e
	if [ $BUILDNR -eq 1 ] ; then
		log_file $TMPDIR/b1/build.log
	fi
	case $BUILD_RESULT in
		148)  # 404-256=148... (ssh 'really' only 'supports' exit codes below 255...)
			handle_E404
			;;
		2)
			handle_ftbfs
			;;
		3)
			handle_timeout
			;;
		0)  # build succcessfully completed
			;;
		*)
			unregister_build
			handle_remote_error "with exit code $RESULT from $NODE for build #$BUILDNR for ${SRCPACKAGE} on ${SUITE}/${ARCH}"
			;;
	esac
}

check_installed_build_depends() {
	local TMPFILE1=$(mktemp --tmpdir=$TMPDIR)
	local TMPFILE2=$(mktemp --tmpdir=$TMPDIR)
	grep-dctrl -s Installed-Build-Depends -n ${SRCPACKAGE} ./b1/$BUILDINFO > $TMPFILE1
	grep-dctrl -s Installed-Build-Depends -n ${SRCPACKAGE} ./b2/$BUILDINFO > $TMPFILE2
	set +e
	diff $TMPFILE1 $TMPFILE2
	RESULT=$?
	set -e
	if [ $RESULT -eq 1 ] ; then
		printf "$(date -u) - $BUILDINFO in ${SUITE} on ${ARCH} varies, probably due to mirror updates. Doing the first build again, please check ${BUILD_URL}console.log for now...\n" >> /var/log/jenkins/reproducible-env-changes.log
		echo
		echo "============================================================================="
		echo "$(date -u) - The installed build depends vary according to the two .buildinfo files, probably due to mirror updates. Doing the first build on $NODE1 again."
		echo "============================================================================="
		echo
		remote_build 1 $NODE1
		grep-dctrl -s Installed-Build-Depends -n ${SRCPACKAGE} ./b1/$BUILDINFO > $TMPFILE1
		set +e
		diff $TMPFILE1 $TMPFILE2
		RESULT=$?
		rm $TMPFILE1 $TMPFILE2
		set -e
		if [ $RESULT -eq 1 ] ; then
			handle_env_changes "different packages were installed in the 1st+2nd builds and also in the 2nd+3rd build.\n$(ls -l ./b1/$BUILDINFO) on $NODE1\n$(ls -l ./b2/$BUILDINFO) on $NODE2\n"
		fi
	fi
	rm -f $TMPFILE1 $TMPFILE2
}

sign_buildinfo() {
	local BUILDPATH="./$1"
	log_info "Signing $BUILDPATH/$BUILDINFO as $BUILDINFO_SIGNED"
	gpg --output=$BUILDPATH/$BUILDINFO_SIGNED --clearsign $BUILDPATH/$BUILDINFO || log_error "Could not sign $PWD/$BUILDPATH/$BUILDINFO"
	log_info "Signed $BUILDPATH/$BUILDINFO as $BUILDPATH/$BUILDINFO_SIGNED"
}

share_buildinfo() {
	# Submit the -buildinfo files to third-party archives:
	log_info "Submitting .buildinfo files to external archives:"

	# Disabled as that mail address bounces.
	## buildinfo.kfreebsd.eu administered by Steven Chamberlain <steven@pyro.eu.org>
	#for X in b1 b2
	#do
	#	mail -s "${X}/$BUILDINFO_SIGNED" submit@buildinfo.kfreebsd.eu < ./${X}/$BUILDINFO_SIGNED || log_error "Could not submit ${X}/$BUILDINFO_SIGNED to submit@buildinfo.kfreebsd.eu."
	#done
	#log_info "Done submitting .buildinfo files to submit@buildinfo.kfreebsd.eu."

	# buildinfo.debian.net administred by Chris Lamb <lamby@debian.org>
	local TMPFILE=$(mktemp --tmpdir=$TMPDIR)
	for X in b1 b2
	do
		log_info "Submitting $(du -h ${X}/$BUILDINFO_SIGNED)"
		curl -s -X PUT --max-time 30 --data-binary @- "https://buildinfo.debian.net/api/submit" < ./${X}/$BUILDINFO_SIGNED > $TMPFILE || log_error "Could not submit buildinfo from ${X} to http://buildinfo.debian.net/api/submit"
		cat $TMPFILE
		if grep -q "500 Internal Server Error" $TMPFILE ; then
			MESSAGE="$(date -u ) - ${BUILD_URL}console.log got error code 500 from buildinfo.debian.net for $(du -h ${X}/$BUILDINFO_SIGNED)"
			echo -e "$MESSAGE" | tee -a /var/log/jenkins/reproducible-submit2buildinfo.debian.net.log
		fi
		rm $TMPFILE
	done
	log_info "Done submitting .buildinfo files to http://buildinfo.debian.net/api/submit."

	log_info "Done submitting .buildinfo files."
	log_info "Removing signed $BUILDINFO_SIGNED files:"
	rm -vf ./b1/$BUILDINFO_SIGNED ./b2/$BUILDINFO_SIGNED | tee -a "$RBUILDLOG"
}

build_rebuild() {
	CHANGES="${SRCPACKAGE}_${EVERSION}_${ARCH}.changes" # changes file with expected version
	mkdir b1 b2
	log_info "Starting 1st build on remote node $NODE1."
	remote_build 1 $NODE1
	log_info "1st build successful. Starting 2nd build on remote node $NODE2."
	remote_build 2 $NODE2
	# at this point, both builds were fine, i.e., they did not FTBFS.
	log_info "$CHANGES:"
	log_file b1/$CHANGES
	check_installed_build_depends
	# save the build:
	cleanup_pkg_files
	diff_copy_buildlogs
	update_rbuildlog
	call_diffoscope_on_changes_files  # defines DIFFOSCOPE, update_db_and_html defines STATUS
	share_buildinfo
}

#
# below is what controls the world
#

mkdir -p /srv/reproducible-results/rbuild-debian
TMPDIR=$(mktemp --tmpdir=/srv/reproducible-results/rbuild-debian -d)  # where everything actually happens
trap cleanup_all INT TERM EXIT
cd $TMPDIR

DATE=$(date -u +'%Y-%m-%d %H:%M')
START=$(date +'%s')
RBUILDLOG=$(mktemp --tmpdir=$TMPDIR)
JOB="${JOB_NAME#reproducible_builder_}/${BUILD_ID}"

#
# determine mode
#
if [ "$1" = "" ] ; then
	echo "Error, needs at least one parameter."
	exit 1
elif [ "$1" = "1" ] || [ "$1" = "2" ] ; then
	MODE="$1"
	SRCPACKAGE="$2"
	SUITE="$3"
	ARCH="$(dpkg --print-architecture)"
	SAVE_ARTIFACTS="0"
	TMPDIR="$4"
	VERSION="$5"
	[ -d $TMPDIR ] || mkdir -p $TMPDIR
	cd $TMPDIR
	get_source_package
	mkdir b$MODE
	if [ "$MODE" = "1" ] ; then
		first_build
	else
		second_build
	fi
	sign_buildinfo "b$MODE"
	echo "$(date -u) - build #$MODE for $SRCPACKAGE/$SUITE/$ARCH on $HOSTNAME done."
	exit 0
elif [ "$2" != "" ] ; then
	MODE="master"
	NODE1="$(echo $1 | cut -d ':' -f1).debian.net"
	NODE2="$(echo $2 | cut -d ':' -f1).debian.net"
	# overwrite ARCH for remote builds
	for i in $ARCHS ; do
		# try to match ARCH in nodenames
		if [[ "$NODE1" =~ .*-$i.* ]] ; then
			ARCH=$i
		fi
	done
	if [ -z "$ARCH" ] ; then
		echo "Error: could not detect architecture, exiting."
		exit 1
	fi
fi

#
# main - only used in master-mode
#
exit_early_if_debian_is_broken
check_nodes_are_up
delay_start
choose_package  # defines SUITE, SRCPKGID, SRCPACKAGE, VERSION, SAVE_ARTIFACTS, NOTIFY
get_source_package

log_info "${SRCPACKAGE}_${EVERSION}.dsc"
log_file ${SRCPACKAGE}_${EVERSION}.dsc

check_suitability
build_rebuild
