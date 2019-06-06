#!/bin/bash

# Copyright 2018 Holger Levsen <holger@layer-acht.org>
#           2019 kpcyrd <git@rxv.cc>
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
elif [ "$1" != "main" ] && [ "$1" != "community" ] ; then
	echo "\$RESPOSITORY needs to be one of main or community."
        exit 1
fi

DATE="$(date -u +'%Y-%m-%d %H:%M' -d '21 days ago')"
REPOSITORY=$1
SUITE=alpine_$REPOSITORY
ARCH=x86_64
shift
PACKAGES="$@"
SUCCESS=""
ALREADY_SCHEDULED=""
NOT_EXISTING=""
DISTROID=$(query_db "SELECT id FROM distributions WHERE name='alpine'")
for PKG in $PACKAGES ; do
	echo "Now trying to reschedule $PKG in $SUITE."
	PKG_ID=$(query_db "SELECT id FROM sources WHERE distribution=$DISTROID AND name='$PKG' AND suite='$SUITE' AND architecture='$ARCH';")
	if [ ! -z "${PKG_ID}" ] ; then
		SCHEDULED=$(query_db "SELECT * FROM schedule WHERE package_id = '${PKG_ID}';")
		if [ -z "$SCHEDULED" ] ; then
			query_db "INSERT INTO schedule (package_id, date_scheduled) VALUES ('${PKG_ID}', '$DATE');"
			SUCCESS="$SUCCESS $PKG"
		else
			echo " $PKG (package_id: ${PKG_ID}) already scheduled, not scheduling again."
			ALREADY_SCHEDULED="$ALREADY_SCHEDULED $PKG"
		fi
	else
		echo " $PKG does not exist in $SUITE, ignoring."
		NOT_EXISTING="$NOT_EXISTING $PKG"
	fi
done

echo
if [ ! -z "$SUCCESS" ] ; then
	AMOUNT=$(echo $SUCCESS | sed 's# #\n#g' | wc -l)
	if [ $AMOUNT -gt 3 ] ; then
		MANY=" $AMOUNT packages"
	else
		MANY=""
	fi
	MESSAGE="Manually scheduled$MANY in $REPOSITORY:$SUCCESS"
	# shorten irc message if longer then 256 characters
	if [ ${#MESSAGE} -gt 256 ] ; then
		MESSAGE="${MESSAGE:0:256}✂…"
	fi
	echo "$MESSAGE"
	irc_message alpine-reproducible "$MESSAGE"
fi
if [ ! -z "$ALREADY_SCHEDULED" ] || [ ! -z "$NOT_EXISTING" ] ; then
	echo
	if [ ! -z "$ALREADY_SCHEDULED" ] ; then
		echo "$ALREADY_SCHEDULED were already scheduled..."
	fi
	if [ ! -z "$NOT_EXISTING" ] ; then
		echo "$NOT_EXISTING were not found in $SUITE, so ignored."
	fi
fi
echo

exit 0

# vim: set sw=0 noet :
