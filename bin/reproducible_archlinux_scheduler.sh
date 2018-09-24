#!/bin/bash

# Copyright 2015-2018 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

set -e

update_archlinux_repositories() {
	#
	# init
	#
	local UPDATED=$(mktemp -t archlinuxrb-scheduler-XXXXXXXX)
	local NEW=$(mktemp -t archlinuxrb-scheduler-XXXXXXXX)
	local KNOWN=$(mktemp -t archlinuxrb-scheduler-XXXXXXXX)
	local BLACKLIST="/($(echo $ARCHLINUX_BLACKLISTED | sed "s# #|#g"))/"
	local TOTAL=$(cat ${ARCHLINUX_PKGS}_* | wc -l)
	echo "$(date -u ) - $TOTAL Arch Linux packages were previously known to Arch Linux."
	query_db "select suite, name, version FROM sources WHERE architecture='$ARCH';" > $KNOWN
	echo "$(date -u ) - $(cat $KNOWN | wc -l) Arch Linux packages are known in our database."
	# init session
	local SESSION="archlinux-scheduler-$RANDOM"
	schroot --begin-session --session-name=$SESSION -c jenkins-reproducible-archlinux
	echo "$(date -u ) - updating pacman's knowledge of Arch Linux repositories (by running pacman -Syu --noconform')."
	schroot --run-session -c $SESSION --directory /var/tmp -- sudo pacman -Syu --noconfirm

	#
	# Get a list of unique package bases.  Non-split packages don't have a pkgbase set
	# so we need to use the pkgname for them instead.
	#
	echo "$(date -u ) - exporting pacman's knowledge of Arch Linux repositories to the filesystem (by running 'expac -S...')."
	schroot --run-session -c $SESSION --directory /var/tmp -- expac -S '%r %e %n %v' | \
		while read repo pkgbase pkgname version; do
			if [[ "$pkgbase" = "(null)" ]]; then
				printf '%s %s %s\n' "$repo" "$pkgname" "$version"
			else
				printf '%s %s %s\n' "$repo" "$pkgbase" "$version"
			fi
		done | sort -u -R > "$ARCHLINUX_PKGS"_full_pkgbase_list
	TOTAL=$(cat ${ARCHLINUX_PKGS}_full_pkgbase_list | wc -l)
	echo "$(date -u ) - $TOTAL Arch Linux packages are now known to Arch Linux."
	local total=$(query_db "SELECT count(*) FROM sources AS s JOIN schedule AS sch ON s.id=sch.package_id WHERE s.architecture='x86_64' and sch.date_build_started is NULL;")
	echo "$(date -u) - updating Arch Linux repositories, currently $total packages scheduled."

	#
	# remove packages which are gone (only when run between 21:00 and 23:59)
	#
	#if [ $(date +'%H') -gt 21 ] ; then
	#FIXME: the next lines actually disables this code block...
	#if [ $(date +'%H') -gt 25 ] ; then
		REMOVED=0
		REMOVE_LIST=""
		for REPO in $ARCHLINUX_REPOS ; do
			echo "$(date -u ) - dropping removed packages from filesystem in repository '$REPO':"
			for i in $(find $BASE/archlinux/$REPO -type d -wholename "$BASE/archlinux/$REPO/*" | sort) ; do
				PKG=$(basename $i)
				if ! grep -q "$REPO $PKG" ${ARCHLINUX_PKGS}_full_pkgbase_list > /dev/null ; then
					let REMOVED=$REMOVED+1
					REMOVE_LIST="$REMOVE_LIST $REPO/$PKG"
					rm -r --one-file-system $BASE/archlinux/$REPO/$PKG
				        echo "$REPO/$PKG removed as it's gone from the Archlinux repositories."
					# FIXME: we actually need to drop them from the db now...
					# from results
					# from scheduled
					# from sources
				fi
			done
		done
		MESSAGE="deleted $REMOVED packages: $REMOVE_LIST"
		echo "$(date -u ) - $MESSAGE"
		if [ $REMOVED -ne 0 ] ; then
			irc_message archlinux-reproducible "$MESSAGE"
		fi
	#fi
	
	#
	# schedule packages
	#

	for REPO in $ARCHLINUX_REPOS ; do
		TMPPKGLIST=$(mktemp -t archlinuxrb-scheduler-XXXXXXXX)
		echo "$(date -u ) - updating database with available packages in repository '$REPO'."
		DATE="$(date -u +'%Y-%m-%d %H:%M')"
		grep "^$REPO" "$ARCHLINUX_PKGS"_full_pkgbase_list | \
			while read repo pkgbase version; do
				PKG=$pkgbase
				SUITE="archlinux_$repo"
				PKG_IN_DB=$(grep "^archlinux_$repo|$pkgbase|" $KNOWN | head -1) # FIXME: why oh why is head -1 needed here?
				VERSION=$(echo ${PKG_IN_DB} | cut -d "|" -f3)
			        if [ -z "${PKG_IN_DB}" ] ; then
					# new package, add to db and schedule
					echo "new package found: $repo/$pkgbase $version "
					query_db "INSERT into sources (name, version, suite, architecture) VALUES ('$PKG', '$version', '$SUITE', '$ARCH');"
					PKG_ID=$(query_db "SELECT id FROM sources WHERE name='$PKG' AND suite='$SUITE' AND architecture='$ARCH';")
					query_db "INSERT INTO schedule (package_id, date_scheduled) VALUES ('${PKG_ID}', '$DATE');"
				elif [ "$VERSION" != "$version" ] ; then
					VERCMP="$(schroot --run-session -c $SESSION --directory /var/tmp -- vercmp $version $VERSION || true)"
					if [ "$VERCMP" = "1" ] ; then
						# known package with new version, so update db and schedule
						echo $REPO/$pkgbase >> $UPDATED
						echo "$REPO/$pkgbase $VERSION is known in the database, but repo now has $version which is newer, so rescheduling... "
						query_db "UPDATE sources SET version = '$version' WHERE name = '$PKG' AND suite = '$SUITE' AND architecture='$ARCH';"
						if [ -z $(echo $PKG | egrep -v "$BLACKLIST") ] ; then
							echo "$PKG is blacklisted, so not scheduling it."
						else
							PKG_ID=$(query_db "SELECT id FROM sources WHERE name='$PKG' AND suite='$SUITE' AND architecture='$ARCH';")
							echo " SELECT * FROM schedule WHERE package_id = '${PKG_ID}';"
							SCHEDULED=$(query_db "SELECT * FROM schedule WHERE package_id = '${PKG_ID}';")
							if [ -z "$SCHEDULED" ] ; then
								echo " INSERT INTO schedule (package_id, date_scheduled) VALUES ('${PKG_ID}', '$DATE');"
								query_db "INSERT INTO schedule (package_id, date_scheduled) VALUES ('${PKG_ID}', '$DATE');" ||true
							else
								echo " $PKG (package_id: ${PKG_ID}) already scheduled, not scheduling again."
							fi
						fi
					elif [ "$VERCMP" = "-1" ] ; then
						# our version is higher than what's in the repo because we build trunk
						echo "$REPO/$pkgbase $VERSION in db is higher than $version in repo because we build trunk."
					else
						echo " Boom boom boom boom boom."
						echo " This should never happen: we know about $pkgbase with $VERSION, but repo has $version. VERCMP=$VERCMP"
						echo " PKG_IN_DB=${PKG_IN_DB}"
					fi
				fi

				printf '%s %s\n' "$pkgbase" "$version" >> $TMPPKGLIST
			done
		mv $TMPPKGLIST "$ARCHLINUX_PKGS"_"$REPO"
		#new=$(grep -c ^$REPO $NEW || true)
		#updated=$(grep -c ^$REPO $UPDATED || true)
		#FIXME echo "$(date -u ) - scheduled $new/$updated packages in repository '$REPO'."
	done
	schroot --end-session -c $SESSION

	#
	# schedule up to $MAX packages we already know about
	# (only if less than $THRESHOLD packages are currently scheduled)
	#
	old=""
	local MAX=350
	local THRESHOLD=450
	#FIXME add actual code here :)

	#
	# output stats
	#
	total=$(query_db "SELECT count(*) FROM sources AS s JOIN schedule AS sch ON s.id=sch.package_id WHERE s.architecture='x86_64' and sch.date_build_started is NULL;")
	rm "$ARCHLINUX_PKGS"_full_pkgbase_list
	new=$(cat $NEW | wc -l 2>/dev/null|| true)
	updated=$(cat $UPDATED 2>/dev/null| wc -l || true)
	if [ $new -ne 0 ] || [ $updated -ne 0 ] || [ -n "$old" ] ; then
		message="scheduled"
		if [ $new -ne 0 ] ; then
			message="$message $new entirely new packages"
		fi
		if [ $new -ne 0 ] && [ $updated -ne 0 ] ; then
			message="$message and"
		fi
		if [ $updated -ne 0 ] ; then
			message="$message $updated packages with newer versions"
		fi
		if [ -n "$old" ] && ( [ $new -ne 0 ] || [ $updated -ne 0 ] ) ; then
			old=", plus$old"
		fi
		MESSAGE="${message}$old, for $total scheduled out of $TOTAL."
		#FIXME irc_message archlinux-reproducible "$MESSAGE"
		#echo "$(date -u ) - $MESSAGE"
	#else
		#echo "$(date -u ) - didn't schedule any packages."
	fi
	rm $NEW $UPDATED $KNOWN > /dev/null
	echo "$(date -u) - done updating Arch Linux repositories and scheduling, $TOTAL packages known and $total packages scheduled."
}

ARCH="x86_64"
update_archlinux_repositories

# vim: set sw=0 noet :
