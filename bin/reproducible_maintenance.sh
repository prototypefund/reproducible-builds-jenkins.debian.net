#!/bin/bash
# vim: set noexpandtab:

# Copyright 2014-2019 Holger Levsen <holger@layer-acht.org>
#         © 2015-2018 Mattia Rizzolo <mattia@debian.org>
# released under the GPLv2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

DIRTY=false
REP_RESULTS=/srv/reproducible-results


# query reproducible database, print output
query_to_print() {
	printf "$(psql -c "$@")"
}

# backup db
if [ "$HOSTNAME" = "$MAINNODE" ] ; then
	echo "$(date -u) - backup db and update public copy."
	# prepare backup
	mkdir -p $REP_RESULTS/backup

	# keep 30 days and the 1st of the month
	DAY=(date -d "30 day ago" '+%d')
	DATE=$(date -d "30 day ago" '+%Y-%m-%d')
	BACKUPFILE="$REP_RESULTS/backup/reproducible_$DATE.sql.xz"
	if [ "$DAY" != "01" ] &&  [ -f "$BACKUPFILE" ] ; then
		rm -f "$BACKUPFILE"
	fi

	# Make a daily backup of database
	DATE=$(date '+%Y-%m-%d')
	BACKUPFILE="$REP_RESULTS/backup/reproducible_$DATE.sql"
	if [ ! -f $BACKUPFILE.xz ] ; then
		# make the backup
		DATE=$(date '+%Y-%m-%d')
		pg_dump -x -O $PGDATABASE > "$BACKUPFILE"
		xz "$BACKUPFILE"

		# make the backup public
		ln -s -f "$BACKUPFILE.xz" $BASE/reproducible.sql.xz

		# recreate documentation of database
		postgresql_autodoc -d $PGDATABASE -t html -f "$BASE/reproducibledb"
	fi
fi

#
# we fail hard
#
set -e

#
# find too large files in /var/log
#
echo "$(date -u) - Looking for too large files in /var/log/"
TOOBIG=$(find /var/log -size +8G -exec ls -lah {} \; 2>/dev/null || true)
if [ ! -z "$TOOBIG" ] ; then
	echo
	echo "$(date -u) - Warning: too large files found in /var/log:"
	echo "$TOOBIG"
	echo
	DIRTY=true
	if [ -n "$(find /var/log -size +32G 2> >(grep -v 'Permission denied'))" ] ; then
		echo "$(date -u) - Error, more than 32gb is just wrong..."
		exit 1
	fi
fi

#
# delete old temp directories in $REP_RESULTS/rbuild-debian
#
echo "$(date -u) - Deleting temp directories in $REP_RESULTS/rbuild-debian, older than 3 days."
OLDSTUFF=$(find $REP_RESULTS/rbuild-debian -maxdepth 1 -type d -mtime +2 -name "tmp.*" -exec ls -lad {} \; 2>/dev/null|| true)
if [ ! -z "$OLDSTUFF" ] ; then
	echo
	echo "Old temp directories found in $REP_RESULTS/rbuild-debian"
	find $REP_RESULTS/rbuild-debian -maxdepth 1 -type d -mtime +2 -name "tmp.*" -exec rm -rv --one-file-system {} \; || true
	echo "These old directories have been deleted."
	echo
	DIRTY=true
fi

#
# delete old temp directories in /tmp (probably only useful on osuosl171+172)
#
echo "$(date -u) - Deleting temporary directories in /tmp, older than 3 days."
OLDSTUFF=$(find /tmp -maxdepth 1 -type d -mtime +2 -regextype egrep -regex '/tmp/(tmp.*|Test.*|usession-release.*|.*test.*)' -exec ls -lad {} \; || true)
if [ ! -z "$OLDSTUFF" ] ; then
	echo
	echo "Old temp directories found in /tmp"
	find /tmp -maxdepth 1 -type d -mtime +2 -regextype egrep -regex '/tmp/(tmp.*|Test.*|usession-release.*|.*test.*)' -exec sudo rm -rv --one-file-system {} \; || true
	echo "These old directories have been deleted."
	echo
	DIRTY=true
fi

#
# delete old pbuilder build directories
#
if [ -d /srv/workspace/pbuilder/ ] ; then
	echo "$(date -u) - Deleting pbuilder build directories, older than 3 days."
	OLDSTUFF=$(find /srv/workspace/pbuilder/ -maxdepth 2 -regex '.*/[0-9]+' -type d -mtime +2 -exec ls -lad {} \; || true)
	if [ ! -z "$OLDSTUFF" ] ; then
		echo
		echo "Old pbuilder build directories found in /srv/workspace/pbuilder/"
		echo -n "$OLDSTUFF"
		( find /srv/workspace/pbuilder/ -maxdepth 2 -regex '.*/[0-9]+' -type d -mtime +2 -exec sudo rm -rf --one-file-system {} \; ) || true
		echo
		DIRTY=true
	fi
fi

#
# delete old temp directories $REP_RESULTS/(archlinuxrb-build|rbuild-openwrt-results)-????????
#
echo "$(date -u) - Deleting temp directories in $REP_RESULTS/rbuild-debian, older than 3 days."
OLDSTUFF=$(find $REP_RESULTS/ -maxdepth 1 -type d -mtime +2 -regextype awk -regex "$REP_RESULTS/(archlinuxrb-build|rbuild-openwrt-results)-........" -exec ls -lad {} \; 2>/dev/null|| true)
if [ ! -z "$OLDSTUFF" ] ; then
	echo
	echo "Old archlinuxrb-build and rbuild-openwrt-results temp directories found in $REP_RESULTS/"
	find $REP_RESULTS/ -maxdepth 1 -type d -mtime +2 -regextype awk -regex "$REP_RESULTS/(archlinuxrb-build|rbuild-openwrt-results)-........" -exec rm -rv --one-file-system {} \; || true
	echo "These old directories have been deleted."
	echo
	DIRTY=true
fi


#
# delete old chroot-installation directories (not related to reproducible builds)
#
if [ -d /srv/workspace/chroots/ ] ; then
	echo "$(date -u) - Deleting chroots build directories, older than 7 days."
	OLDSTUFF=$(find /srv/workspace/chroots/ -maxdepth 2 -name 'chroot-installation*' -type d -mtime +6 -exec ls -lad {} \; || true)
	if [ ! -z "$OLDSTUFF" ] ; then
		echo
		echo "Old chroot-installation directories found in /srv/workspace/chroots/"
		echo -n "$OLDSTUFF"
		( find /srv/workspace/chroots/ -maxdepth 2 -name 'chroot-installation*' -type d -mtime +6 -exec sudo rm -rf --one-file-system {} \; ) || true
		echo
		DIRTY=true
	fi
fi

#
# check for working proxy
#
echo "$(date -u) - testing whether the proxy works..."
curl http://www.debian.org > /dev/null
if [ $? -ne 0 ] ; then
	echo "Error: curl http://www.debian.org failed, probably the proxy is down for $HOSTNAME"
	exit 1
fi

if [ "$HOSTNAME" = "$MAINNODE" ] ; then
	#
	# find nodes with problems and temporarily turn them offline
	#
	echo "$(date -u) - Looking for unhealthy nodes."
	cd ~/jobs
	DUMMY_FILE=$(mktemp --tmpdir=$TMPDIR maintenance-XXXXXXX)
	SICK=""
	for i in reproducible_node_health_check_* reproducible_maintenance_* ; do
		case $i in
			reproducible_node_health_check_amd64_jenkins|reproducible_maintenance_amd64_jenkins)
				echo "Skipping $i..."
				continue
				;;
			reproducible_node_health_check_*)
				NODE_ALIAS=$(echo $i | cut -d '_' -f6)
				NODE_ARCH=$(echo $i | cut -d '_' -f5)
				FORCE_DATE=$(date -u -d "3 hour ago" '+%Y-%m-%d %H:%M')
				MAXDIFF=12
				;;
			reproducible_maintenance_*)
				NODE_ALIAS=$(echo $i | cut -d '_' -f4)
				NODE_ARCH=$(echo $i | cut -d '_' -f3)
				FORCE_DATE=$(date -u -d "8 hour ago" '+%Y-%m-%d %H:%M')
				MAXDIFF=3
				;;
		esac
		touch -d "$FORCE_DATE" $DUMMY_FILE
		case $NODE_ARCH in
			amd64)
				case "$NODE_ALIAS" in
					(profitbricks*) NODE="profitbricks-build${NODE_ALIAS#profitbricks}-amd64.debian.net" ;;
					(osuosl*) NODE="osuosl-build${NODE_ALIAS#osuosl}-amd64.debian.net" ;;
				esac ;;
			i386)	NODE="profitbricks-build${NODE_ALIAS#profitbricks}-i386.debian.net" ;;
			arm64)	NODE="codethink-sled${NODE_ALIAS#codethink}-arm64.debian.net" ;;
			armhf)	NODE="${NODE_ALIAS}-armhf-rb.debian.net" ;;
		esac
		case "$NODE" in
			profitbricks-build9-amd64.debian.net|profitbricks-build10-amd64.debian.net)
				# pb9 and pb10 are not used for r-b and sometimes are too busy
				# to run healthcheck / maintenance jobs
				echo "Skipping ${NODE}..."
				continue
				;;
		esac
		cd $i/builds
		LAST=$(ls -rt1 | tail -1)
		GOOD=$(awk '/^lastSuccessfulBuild/ {print $2}' permalinks)
		if [ "$LAST" = "$GOOD" ] ; then
			DIFF=0
		else
			let DIFF=$LAST-$GOOD || DIFF=-1
		fi
		if [ $DIFF -eq -1 ] ; then
			echo "Warning: Problems analysing $i build logs, ignoring $NODE."
		# either the diff is greater than $MAXDIFF (=the last $MAXDIFF job runs failed)
		# or the last successful run is older than an hour (=a job is still running/hanging)
		elif [ $DIFF -gt $MAXDIFF ] || [ $LAST -ot $DUMMY_FILE ] ; then
			echo -n "$i job has issues since more than an hour"
			if grep -q $NODE ~/offline_nodes >/dev/null 2>&1 ; then
				echo " and $NODE already marked as offline, good."
			else
				echo $NODE >> ~/offline_nodes
				echo " so $NODE has (temporarily) been marked as offline now."
				SICK="$SICK $NODE"
			fi
		else
			echo "$NODE is doing fine, good."
		fi
		cd ../..
	done
	if [ -n "$SICK" ] ; then
		SICK=$(echo "$SICK" | sed 's#.debian.net##g' | sed 's#-rb##g' | sed 's# ##' )
		if echo "$SICK" | grep -q ' ' 2>/dev/null ; then
			SICK=$(echo "$SICK" | sed 's# # and #g')
			MESSAGE="$SICK have health problems and have temporarily been marked as offline."
		else
			MESSAGE="$SICK has health problems and has temporarily been marked as offline."
		fi
		irc_message reproducible-builds "$MESSAGE To make this permanent, edit jenkins-home/offline_nodes in git."
	fi
	rm -f $DUMMY_FILE
fi

echo "$(date -u) - updating the chdists, schroots and pbuilder now..."
# use host architecture (only)
ARCH=$(dpkg --print-architecture)
# use host apt proxy configuration for pbuilder
if [ ! -z "$http_proxy" ] ; then
	pbuilder_http_proxy="--http-proxy $http_proxy"
fi
for s in $SUITES ; do
	if [ "${HOSTNAME:0:6}" = "osuosl" ] ; then
		# osuosl nodes are not used to do Debian rebuilds
		continue
	fi
	#
	# chdist update
	#
	distname="$s-$ARCH"
	echo "$(date -u) - updating the $s/$ARCH chdist now."
	if [ ! -d "$CHPATH/$distname" ]; then
		echo "$(date -u) - chdist not existing, creating one now..."
		if ! chdist --data-dir="$CHPATH" --arch="$ARCH" create "$distname" "$MIRROR" "$s" main ; then
			echo "Error: failed to create the $s/$ARCH chdist."
			exit 1
		fi
		. /srv/jenkins/bin/jenkins_node_definitions.sh
		get_node_information "$HOSTNAME"
		if "$NODE_RUN_IN_THE_FUTURE" ; then
			echo "This node is reported to run in the future, configuring APT to ignore the Release file expiration..."
			echo 'Acquire::Check-Valid-Until "false";' > "$CHPATH/$distname/etc/apt/apt.conf.d/398future"
		fi
	fi
	if ! chdist --data-dir="$CHPATH" apt-get "$distname" update ; then
		echo "Warning: failed to update the $s/$ARCH chdist."
		DIRTY=true
	fi
	#
	# schroot update
	#
	#echo "$(date -u) - updating the $s/$ARCH schroot now."
	#for i in 1 2 3 4 ; do
	#	[ ! -d $SCHROOT_BASE/reproducible-$s ] || schroot --directory /root -u root -c source:jenkins-reproducible-$s -- apt-get update
	#	RESULT=$?
	#	if [ $RESULT -eq 1 ] ; then
	#		# sleep 61-120 secs
	#		echo "Sleeping some time... (to workaround network problems like 'Hash Sum mismatch'...)"
	#		/bin/sleep $(echo "scale=1 ; ($(shuf -i 1-600 -n 1)/10)+60" | bc )
	#		echo "$(date -u) - Retrying to update the $s/$ARCH schroot."
	#	elif [ $RESULT -eq 0 ] ; then
	#		break
	#	fi
	#done
	#if [ $RESULT -eq 1 ] ; then
	#	echo "Warning: failed to update the $s/$ARCH schroot."
	#	DIRTY=true
	#fi
	#
	# pbuilder update
	#
	# pbuilder aint used on jenkins anymore
	if [ "$HOSTNAME" = "$MAINNODE" ] ; then
		continue
	else
		echo "$(date -u) - updating pbuilder for $s/$ARCH now."
	fi
	for i in 1 2 3 4 ; do
		[ ! -f /var/cache/pbuilder/$s-reproducible-base.tgz ] || sudo pbuilder --update $pbuilder_http_proxy --basetgz /var/cache/pbuilder/$s-reproducible-base.tgz
		RESULT=$?
		if [ $RESULT -eq 1 ] ; then
			# sleep 61-120 secs
			echo "Sleeping some time... (to workaround network problems like 'Hash Sum mismatch'...)"
			/bin/sleep $(echo "scale=1 ; ($(shuf -i 1-600 -n 1)/10)+60" | bc )
			echo "$(date -u) - Retrying to update pbuilder for $s/$ARCH."
		elif [ $RESULT -eq 0 ] ; then
			break
		fi
	done
	if [ $RESULT -eq 1 ] ; then
		echo "Warning: failed to update pbuilder for $s/$ARCH."
		DIRTY=true
	fi
done
set -e

# for alpine
set +e
case $HOSTNAME in
	osuosl-build169*|osuosl-build170*|jenkins)
		echo "$(date -u) - updating alpine schroot now."
		schroot --directory /tmp -c source:jenkins-reproducible-alpine -u root -- apk update
		RESULT=$?
		if [ $RESULT -eq 1 ] ; then
			echo "Warning: failed to update alpine schroot."
			DIRTY=true
		else
			echo "$(date -u) - updating alpine schroot done."
		fi
		;;
	*)	;;
esac
set -e

# for Arch Linux
set +e
case $HOSTNAME in
	osuosl-build169*|osuosl-build170*|jenkins)
		echo "$(date -u) - updating Arch Linux schroot now."
		schroot --directory /tmp -c source:jenkins-reproducible-archlinux -u root -- pacman -Syu --noconfirm
		RESULT=$?
		if [ $RESULT -eq 1 ] ; then
			echo "Warning: failed to update Arch Linux schroot."
			echo "Let's see if /var/lib/pacman/db.lck exists in the schroot."
			schroot --directory /tmp -c source:jenkins-reproducible-archlinux -u root -- ls /var/lib/pacman/db.lck
			DIRTY=true
		else
			echo "$(date -u) - updating Arch Linux schroot done."
		fi
		;;
	*)	;;
esac
set -e

# delete build services logfiles
if [ "$HOSTNAME" = "$MAINNODE" ] ; then
	if [ -d /var/lib/jenkins/userContent/reproducible/debian/build_service/ ] ; then
		echo "$(date -u) - Deleting logfiles from build services directories, older than a day."
		OLDSTUFF=$(find /var/lib/jenkins/userContent/reproducible/debian/build_service/ -maxdepth 2 -regex '.*/[0-9]+' -type d -mtime +0 -exec ls -lad {} \; || true)
		if [ ! -z "$OLDSTUFF" ] ; then
			echo
			echo "Old logfiles cleaned in /var/lib/jenkins/userContent/reproducible/debian/build_service/"
			echo -n "$OLDSTUFF"
			# we make sure to actually only delete console.log.gz older than a day
			# other stuff we only delete after two days (in case a build is running more than 24h...)
			find /var/lib/jenkins/userContent/reproducible/debian/build_service/ -maxdepth 2 -regex '.*/[0-9]+' -type d -mtime +0 -name console.log.gz -exec rm -rf --one-file-system {} \; || true
			find /var/lib/jenkins/userContent/reproducible/debian/build_service/ -maxdepth 2 -regex '.*/[0-9]+' -type d -mtime +1 -exec rm -rf --one-file-system {} \; || true
			echo
		fi
	fi
fi

# remove too old schroot sessions
echo "$(date -u) - Removing schroot sessions older than 3 days."
dir=/var/lib/schroot/unpack/
OLDSTUFF=$(find "$dir" -mindepth 1 -maxdepth 1 -type d -mtime +2 -exec ls -lad {} \;)
if [ ! -z "$OLDSTUFF" ]; then
	echo
	echo "schroot sessions older than 3 days found, which will be deleted:"
	echo "$OLDSTUFF"
	echo
	for s in $(find "$dir" -mindepth 1 -maxdepth 1 -type d -mtime +2 -print0 | xargs -0 -r basename -a); do
		echo "$(date -u) - removing schroot session $s..."
		schroot -c "$s" --end-session
	done
	OLDSTUFF=$(find "$dir" -mindepth 1 -maxdepth 1 -type d -mtime +2 -exec ls -lad {} \;)
	if [ ! -z "$OLDSTUFF" ]; then
		echo
		echo "Warning: Tried, but failed to delete these:"
		echo "$OLDSTUFF"
		echo "Manual cleanup needed"
	fi
	echo
	DIRTY=true
fi

# find old schroots
echo "$(date -u) - Removing schroots older than 3 days."
regex="/schroots/(reproducible-.+-[0-9]{1,5}|schroot-install-.+)"
OLDSTUFF=$(find /schroots/ -maxdepth 1 -type d -regextype posix-extended -regex "$regex" -mtime +2 -exec ls -lad {} \; || true)
if [ ! -z "$OLDSTUFF" ] ; then
	echo
	echo "schroots older than 3 days found in /schroots, which will be deleted:"
	find /schroots/ -maxdepth 1 -type d -regextype posix-extended -regex "$regex" -mtime +2 -exec sudo rm -rf --one-file-system {} \; || true
	echo "$OLDSTUFF"
	OLDSTUFF=$(find /schroots/ -maxdepth 1 -type d -regextype posix-extended -regex "$regex" -mtime +2 -exec ls -lad {} \; || true)
	if [ ! -z "$OLDSTUFF" ] ; then
		echo
		echo "Warning: Tried, but failed to delete these:"
		echo "$OLDSTUFF"
		echo "Manual cleanup needed!"
	fi
	echo
	DIRTY=true
fi

# find very old schroots
echo "$(date -u) - Detecting schroots older than 1 month"
# the reproducible-archlinux schroot is ignored because its ment to be long living
OLDSTUFF=$(find /schroots/ -mindepth 1 -maxdepth 1 -mtime +30 -exec ls -lad {} \; | grep -v reproducible-archlinux | true)
if [ ! -z "$OLDSTUFF" ]; then
	echo
	echo "Warning: schroots older than 1 month found in /schroot:"
	echo "$OLDSTUFF"
	echo
	echo "Manual cleanup needed!"
	echo
	DIRTY=true
fi

if [ "$HOSTNAME" = "$MAINNODE" ] ; then
	#
	# find failed builds due to network problems and reschedule them
	#
	# only grep through the last 5h (300 minutes) of builds...
	# (ignore "*None.rbuild.log" because these are build which were just started)
	# this job runs every 4h
	echo "$(date -u) - Rescheduling failed builds due to network issues."
	FAILED_BUILDS=$(find $DEBIAN_BASE/rbuild -type f ! -name "*None.rbuild.log" ! -mmin +300 -exec zgrep -l -E 'E: Failed to fetch.*(Unable to connect to|Connection failed|Size mismatch|Cannot initiate the connection to|Bad Gateway|Service Unavailable)' {} \; 2>/dev/null || true)
	if [ ! -z "$FAILED_BUILDS" ] ; then
		echo
		echo "The following builds have failed due to network problems and will be rescheduled now:"
		echo "$FAILED_BUILDS"
		echo
		echo "Rescheduling packages: "
		REQUESTER="jenkins maintenance job"
		REASON="maintenance reschedule: reschedule builds which failed due to network errors"
		for SUITE in $(echo $FAILED_BUILDS | sed "s# #\n#g" | cut -d "/" -f9 | sort -u) ; do
			for ARCH in $(echo $FAILED_BUILDS | sed "s# #\n#g" | cut -d "/" -f10 | sort -u) ; do
				CANDIDATES=$(for PKG in $(echo $FAILED_BUILDS | sed "s# #\n#g" | grep "/$SUITE/$ARCH/" | cut -d "/" -f11 | cut -d "_" -f1) ; do echo "$PKG" ; done)
				# double check those builds actually failed
				TO_SCHEDULE=""
				for pkg in $CANDIDATES ; do
					QUERY="SELECT s.name FROM sources AS s JOIN results AS r ON r.package_id=s.id
						   WHERE s.suite='$SUITE' AND s.architecture='$ARCH' AND (r.status='FTBFS' OR r.status='depwait') AND s.name='$pkg'"
					TO_SCHEDULE=${TO_SCHEDULE:+"$TO_SCHEDULE "}$(query_db "$QUERY")
				done
				schedule_packages $TO_SCHEDULE
			done
		done
		DIRTY=true
	fi

	#
	# find failed builds due to diffoscope schroot problems and reschedule them
	#
	# only grep through the last 5h (300 minutes) of builds...
	# (ignore "*None.rbuild.log" because these are build which were just started)
	# this job runs every 4h
	echo "$(date -u) - Rescheduling failed builds due to diffoscope schroot issues."
	FAILED_BUILDS=$(find $DEBIAN_BASE/rbuild -type f ! -name "*None.rbuild.log" ! -mmin +300 -exec zgrep -l -F 'E: 10mount: error: Directory' {} \; 2>/dev/null|| true)
	if [ ! -z "$FAILED_BUILDS" ] ; then
		echo
		echo "Warning: The following builds have failed due to diffoscope schroot problems and will be rescheduled now:"
		echo "$FAILED_BUILDS"
		echo
		echo "Rescheduling packages: "
		REQUESTER="jenkins maintenance job"
		REASON="maintenance reschedule: reschedule builds which failed due to diffoscope schroot errors"
		for SUITE in $(echo $FAILED_BUILDS | sed "s# #\n#g" | cut -d "/" -f9 | sort -u) ; do
			for ARCH in $(echo $FAILED_BUILDS | sed "s# #\n#g" | cut -d "/" -f10 | sort -u) ; do
				CANDIDATES=$(echo $FAILED_BUILDS | sed "s# #\n#g" | grep "/$SUITE/$ARCH/" | cut -d "/" -f11 | cut -d "_" -f1 | xargs)
				if [ ! -z "$CANDIDATES" ]; then
					schedule_packages $CANDIDATES
				fi
			done
		done
		DIRTY=true
	fi

	#
	# find packages which build didnt end correctly
	#
	echo "$(date -u) - Rescheduling builds which didn't end correctly."
	DATE=$(date '+%Y-%m-%d %H:%M' -d "-2 days")
	QUERY="
		SELECT s.id, s.name, p.date_scheduled, p.date_build_started
			FROM schedule AS p JOIN sources AS s ON p.package_id=s.id
			WHERE p.date_scheduled != ''
			AND p.date_build_started IS NOT NULL
			AND p.date_build_started < '$DATE'
			ORDER BY p.date_scheduled
		"
	PACKAGES=$(mktemp --tmpdir=$TEMPDIR maintenance-XXXXXXXXXXXX)
	query_db "$QUERY" > $PACKAGES 2> /dev/null || echo "Warning: SQL query '$QUERY' failed."
	if grep -q '|' $PACKAGES ; then
		echo
		echo "Packages found where the build was started more than 48h ago:"
		query_to_print "$QUERY" 2> /dev/null || echo "Warning: SQL query '$QUERY' failed."
		echo
		for PKG in $(cat $PACKAGES | cut -d "|" -f1) ; do
			echo "query_db \"UPDATE schedule SET date_build_started = NULL, job = NULL WHERE package_id = '$PKG';\""
			query_db "UPDATE schedule SET date_build_started = NULL, job = NULL WHERE package_id = '$PKG';"
		done
		echo "Packages have been rescheduled."
		echo
		DIRTY=true
	fi
	rm $PACKAGES

	#
	# find packages which have been removed from the archive
	#
	echo "$(date -u) - Looking for packages which have been removed from the archive."
	PACKAGES=$(mktemp --tmpdir=$TEMPDIR maintenance-XXXXXXXXXX)
	QUERY="SELECT name, suite, architecture FROM removed_packages
			LIMIT 25"
	query_db "$QUERY" > $PACKAGES 2> /dev/null || echo "Warning: SQL query '$QUERY' failed."
	if grep -q '|' $PACKAGES ; then
		DIRTY=true
		echo
		echo "Found files relative to old packages, no more in the archive:"
		echo "Removing these removed packages from database:"
		query_to_print "$QUERY" 2> /dev/null || echo "Warning: SQL query '$QUERY' failed."
		echo
		for pkg in $(cat $PACKAGES) ; do
			PKGNAME=$(echo "$pkg" | cut -d '|' -f 1)
			SUITE=$(echo "$pkg" | cut -d '|' -f 2)
			ARCH=$(echo "$pkg" | cut -d '|' -f 3)
			QUERY="DELETE FROM removed_packages
				WHERE name='$PKGNAME' AND suite='$SUITE' AND architecture='$ARCH'"
			query_db "$QUERY"
			cd $DEBIAN_BASE
			find rb-pkg/$SUITE/$ARCH rbuild/$SUITE/$ARCH dbd/$SUITE/$ARCH dbdtxt/$SUITE/$ARCH buildinfo/$SUITE/$ARCH logs/$SUITE/$ARCH logdiffs/$SUITE/$ARCH -name "${PKGNAME}_*" 2>/dev/null | xargs -r rm -v || echo "Warning: couldn't delete old files from ${PKGNAME} in $SUITE/$ARCH"
		done
		cd - > /dev/null
	fi
	rm $PACKAGES

	#
	# delete jenkins html logs from reproducible_builder_(fedora|archlinux)* jobs as they are mostly redundant
	# (they only provide the extended value of parsed console output, which we dont need here.)
	#
	OLDSTUFF=$(find /var/lib/jenkins/jobs/reproducible_builder_* -maxdepth 3 -mtime +0 -name log_content.html  -exec rm -v {} \; 2>/dev/null | wc -l)
	if [ ! -z "$OLDSTUFF" ] ; then
		echo
		echo "Removed $OLDSTUFF jenkins html logs."
		echo
	fi

fi

# find+terminate processes which should not be there
echo "$(date -u) - Looking for processes which should not be there."
HAYSTACK=$(mktemp --tmpdir=$TEMPDIR maintenance-XXXXXXXXXXX)
RESULT=$(mktemp --tmpdir=$TEMPDIR maintenance-XXXXXXXXXXX)
TOKILL=$(mktemp --tmpdir=$TEMPDIR maintenance-XXXXXXXXXXX)
PBUIDS="1234 1111 2222"
ps axo pid,user,size,pcpu,cmd > $HAYSTACK
for i in $PBUIDS ; do
	for PROCESS in $(pgrep -u $i -P 1 || true) ; do
		# faked-sysv comes and goes...
		grep ^$PROCESS $HAYSTACK | grep -v faked-sysv >> $RESULT 2> /dev/null || true
	done
done
if [ -s $RESULT ] ; then
	for PROCESS in $(cat $RESULT | cut -d " " -f1 | grep -v ^UID | xargs echo) ; do
		AGE=$(ps -p $PROCESS -o etimes= || echo 0)
		# a single build may take day, so... (first build: 18h, 2nd: 24h)
		if [ $AGE -gt $(( 24*60*60 )) ] ; then
			echo "$PROCESS" >> $TOKILL
		fi
	done
	if [ -s $TOKILL ] ; then
		DIRTY=true
		PSCALL=""
		echo
		echo "Info: processes found which should not be there, killing them now:"
		for PROCESS in $(cat $TOKILL) ; do
			PSCALL=${PSCALL:+"$PSCALL,"}"$PROCESS"
		done
		ps -F -p $PSCALL
		echo
		for PROCESS in $(cat $TOKILL) ; do
			sudo kill -9 $PROCESS 2>&1
			echo "'kill -9 $PROCESS' done."
		done
		echo
	fi
fi
rm $HAYSTACK $RESULT $TOKILL
# There are naughty processes spawning childs and leaving them to their grandparents
PSCALL=""
for i in $PBUIDS ; do
	for p in $(pgrep -u $i) ; do
		AGE=$(ps -p $p -o etimes= || echo 0)
		# let's be generous and consider 26 hours here...
		if [ $AGE -gt $(( 26*60*60 )) ] ; then
			sudo kill -9 $p 2>&1 || (echo "Could not kill:" ; ps -F -p "$p")
			sleep 2
			# check it's gone
			AGE=$(ps -p $p -o etimes= || echo 0)
			if [ $AGE -gt $(( 14*60*60 )) ] ; then
				PSCALL=${PSCALL:+"$PSCALL,"}"$p"
			fi
		fi
	done
done
if [ ! -z "$PSCALL" ] ; then
	echo -e "Warning: processes found which should not be there and which could not be killed. Please fix up manually:"
	ps -F -p "$PSCALL"
	echo
fi

# find builds which should not be there
# (not on i386 as we start builds differently here… work in progress)
if [ "$ARCH" != "i386" ] ; then
	RESULTS=$(pgrep -f reproducible_build.sh --parent 1 || true)
	if [ ! -z "$RESULTS" ] ; then
		DIRTY=true
		echo "Warning: found reproducible_build.sh processes which have pid 1 as parent (and not sshd), thus something went wrong… please investigate."
		echo -e "$RESULTS"
	fi
fi

# remove artifacts older than a day
echo "$(date -u) - Checking for artifacts older than a day."
ARTIFACTS=$(find $DEBIAN_BASE/artifacts/r00t-me/* -maxdepth 1 -type d -mtime +1 -exec ls -lad {} \; 2>/dev/null|| true)
if [ ! -z "$ARTIFACTS" ] ; then
	echo
	echo "Removed old artifacts:"
	find $DEBIAN_BASE/artifacts/r00t-me/* -maxdepth 1 -type d -mtime +1 -exec rm -rv --one-file-system {} \; || true
	echo
fi

# find + chmod files with bad permissions
echo "$(date -u) - Checking for files with bad permissions."
# automatically fix rbuild files with wrong permissions...
# (we know it happens (very rarely) but... shrugs.)
[ ! -d $DEBIAN_BASE/rbuild ] || find $DEBIAN_BASE/rbuild ! -perm 644 -type f -exec chmod -v 644 {} \; 2>/dev/null|| true
BADPERMS=$(find $DEBIAN_BASE/{buildinfo,dbd,artifacts,stretch,buster,bullseye,unstable,experimental,rb-pkg} ! -perm 644 -type f 2>/dev/null|| true)
if [ ! -z "$BADPERMS" ] ; then
    DIRTY=true
    echo
    echo "Warning: Found files with bad permissions (!=644):"
    echo "Please fix permission manually"
    echo "$BADPERMS" | xargs echo chmod -v 644
    echo
fi

# daily mails
if [ "$HOSTNAME" = "$MAINNODE" ] && [ $(date -u +%H) -eq 0 ]  ; then
	# once a day, send mail about builder problems
	files_to_mail=(
		/var/log/jenkins/reproducible-builder-errors.log
		/var/log/jenkins/reproducible-stale-builds.log
		/var/log/jenkins/reproducible-archlinux-stale-builds.log
		/var/log/jenkins/reproducible-race-conditions.log
		/var/log/jenkins/reproducible-diskspace-issues.log
		/var/log/jenkins/reproducible-remote-error.log
		/var/log/jenkins/reproducible-scheduler.log
		/var/log/jenkins/reproducible-env-changes.log
		/var/log/jenkins/reproducible-submit2buildinfo.debian.net.log
		/var/log/postgresql/postgresql-9.6-main.log
	)
	for PROBLEM in "${files_to_mail[@]}" ; do
		if [ -s $PROBLEM ] ; then
			TMPFILE=$(mktemp --tmpdir=$TEMPDIR maintenance-XXXXXXXXXXXX)
			if [ "$(dirname $PROBLEM)" = "/var/log/jenkins" ] ; then
				if [ "$(basename $PROBLEM)" = "reproducible-diskspace-issues.log" ]; then
					echo "diskspace issues should always be investigated." > $TMPFILE
				fi
				if grep -q https $PROBLEM ; then
					echo "$(grep -c https $PROBLEM) entries found:"
					if [ "$(basename $PROBLEM)" != "reproducible-remote-error.log" ] && [ "$(basename $PROBLEM)" != "reproducible-race-conditions.log" ] ; then
						OTHERPROJECTS=""
					else
						OTHERPROJECTS="archlinux fedora"
					fi
					echo "$(grep -c https $PROBLEM || echo 0) entries found:" >> $TMPFILE
					for a in $ARCHS $OTHERPROJECTS; do
						echo "- $(grep https $PROBLEM|grep -c ${a}_) from $a." >> $TMPFILE
					done
				elif grep -q 'stale builds found' $PROBLEM ; then
					echo "$(grep -c 'stale builds found' $PROBLEM || echo 0) entries found:" >> $TMPFILE
					for a in $ARCHS ; do
							echo "- $(grep -c ${a}_ $PROBLEM) from $a." >> $TMPFILE
					done
				fi
				echo >> $TMPFILE
				# maybe we should use logrotate for our jenkins logs too…
				cat $PROBLEM >> $TMPFILE
				rm $PROBLEM
			else
				# regular logfile, logrotate is used (and the file ain't owned by jenkins)
				# only care for yesterday's entries:
				( grep $(date -u -d "1 day ago" '+%Y-%m-%d') $PROBLEM || echo "no problems yesterday…" ) > $TMPFILE
			fi
			# send mail if we found issues
			if [ -s $TMPFILE ] && ! grep -q "no problems yesterday…" $TMPFILE ; then
				if [ "$(basename $PROBLEM)" = "reproducible-submit2buildinfo.debian.net.log" ]; then
					CC="-c lamby@debian.org"
				fi
				cat $TMPFILE | mail -s "$(basename $PROBLEM) found" ${CC:-} qa-jenkins-scm@lists.alioth.debian.org
				CC=""
			fi
			rm -f $TMPFILE
		fi
	done
	# once a day, send notifications to package maintainers
	cd $REP_RESULTS/notification-emails
	for NOTE in $(find . -type f) ; do
			TMPFILE=$(mktemp --tmpdir=$TEMPDIR maintenance-XXXXXXXXXXXX)
			PKG=$(basename $NOTE)
			mv $NOTE $TMPFILE
			cat $TMPFILE | mail -s "$PKG: status change on tests.reproducible-builds.org/debian" \
				-a "From: Reproducible builds folks <reproducible-builds@lists.alioth.debian.org>" \
				-a "X-Reproducible-Builds-Pkg: $PKG" \
				 $PKG@packages.debian.org
			rm -f $TMPFILE
	done
fi

if ! $DIRTY ; then
	echo "$(date -u ) - Everything seems to be fine."
	echo
fi

echo "$(date -u) - the end."
