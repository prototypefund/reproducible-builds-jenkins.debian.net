#!/bin/bash

# Copyright 2018 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

set -e

if [ "$1" = "" ] || [ "$2" = "" ] ; then
	echo "Need at least two parameters:"
	echo "$0 \$RESPOSITORY \$SOURCEPKGNAME1 \$SOURCEPKGNAME2 \$SOURCEPKGNAME3..."
	exit 1
elif [ "$1" != "core" ] && [ "$1" != "extra" ] && [ "$1" != "multilib" ] && [ "$1" != "community" ] ; then
	echo "\$RESPOSITORY needs to be one of core, extra, multilib or community."
        exit 1
fi

DATE="$(date -u +'%Y-%m-%d %H:%M' -d '21 days ago')"
REPOSITORY=$1
SUITE=archlinux_$REPOSITORY
ARCH=x86_64
shift
PACKAGES="$@"
SUCCESS=""
for PKG in $PACKAGES ; do
	echo "Now trying to reschedule $PKG in $SUITE."
	PKG_ID=$(query_db "SELECT id FROM sources WHERE name='$PKG' AND suite='$SUITE' AND architecture='$ARCH';")
	if [ ! -z "${PKG_ID}" ] ; then
		SCHEDULED=$(query_db "SELECT * FROM schedule WHERE package_id = '${PKG_ID}';")
		if [ -z "$SCHEDULED" ] ; then
			query_db "INSERT INTO schedule (package_id, date_scheduled) VALUES ('${PKG_ID}', '$DATE');"
			SUCCESS="$SUCCESS $PKG"
		else
			echo " $PKG (package_id: ${PKG_ID}) already scheduled, not scheduling again."
		fi
	else
		echo " $PKG does not exist in $SUITE, ignoring."
	fi
done

if [ ! -z "$SUCCESS" ] ; then
	MESSAGE="Manually scheduled these packages in $SUITE:$SUCCESS"
	echo "$MESSAGE"
	irc_message archlinux-reproducible "$MESSAGE"
fi

exit 0

# vim: set sw=0 noet :
