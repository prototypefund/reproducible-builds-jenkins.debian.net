#!/bin/bash
# vim: set noexpandtab:

# Copyright © 2015-2018 Holger Levsen <holger@layer-acht.org>
#           ©      2018 Mattia Rizzolo <mattia@debian.org>
# released under the GPLv2

set -e

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code for tests.reproducible-builds.org
. /srv/jenkins/bin/reproducible_common.sh

TARGET_DIR=/srv/reproducible-results/node-information/
mkdir -p $TARGET_DIR
TMPFILE_SRC=$(mktemp)
TMPFILE_NODE=$(mktemp)
# remove old node entries which are older than two weeks
find $TARGET_DIR/ -type f -mtime +14 -exec rm -v {} \;

#
# collect node information
#
echo "$(date -u) - Collecting information from nodes"
for NODE in $BUILD_NODES jenkins.debian.net ; do
	if [ "$NODE" = "jenkins.debian.net" ] ; then
		echo "$(date -u) - Trying to update $TARGET_DIR/$NODE."
		/srv/jenkins/bin/reproducible_info.sh > $TARGET_DIR/$NODE
		echo "$(date -u) - $TARGET_DIR/$NODE updated:"
		cat $TARGET_DIR/$NODE
		continue
	fi
	# call jenkins_master_wrapper.sh so we only need to track different ssh ports in one place
	# jenkins_master_wrapper.sh needs NODE_NAME and JOB_NAME
	export NODE_NAME=$NODE
	export JOB_NAME=$JOB_NAME
	echo "$(date -u) - Trying to update $TARGET_DIR/$NODE."
	set +e
	/srv/jenkins/bin/jenkins_master_wrapper.sh /srv/jenkins/bin/reproducible_info.sh > $TMPFILE_SRC
	if [ $? -eq 1 ] ; then
		echo "$(date -u) - Warning: could not update $TARGET_DIR/$NODE."
		continue
	fi
	set -e
	for KEY in $BUILD_ENV_VARS ; do
		VALUE=$(egrep "^$KEY=" $TMPFILE_SRC | cut -d "=" -f2-)
		if [ ! -z "$VALUE" ] ; then
			echo "$KEY=$VALUE" >> $TMPFILE_NODE
		fi
	done
	if [ -s $TMPFILE_NODE ] ; then
		mv $TMPFILE_NODE $TARGET_DIR/$NODE
		echo "$(date -u) - $TARGET_DIR/$NODE updated:"
		cat $TARGET_DIR/$NODE
	fi
	rm -f $TMPFILE_SRC $TMPFILE_NODE
done
echo

echo "$(date -u) - Showing node performance:"
TMPFILE1=$(mktemp)
TMPFILE2=$(mktemp)
TMPFILE3=$(mktemp)
NOW=$(date -u '+%Y-%m-%d %H:%m')
for i in $BUILD_NODES ; do
	query_db "SELECT build_date FROM stats_build AS r WHERE ( r.node1='$i' OR r.node2='$i' )" > $TMPFILE1 2>/dev/null
	j=$(wc -l $TMPFILE1|cut -d " " -f1)
	k=$(cat $TMPFILE1|cut -d " " -f1|sort -u|wc -l)
	l=$(echo "scale=1 ; ($j/$k)" | bc)
	echo "$l builds/day ($j/$k) on $i" >> $TMPFILE2
	DATE=$(date '+%Y-%m-%d %H:%M' -d "-1 days")
	m=$(query_db "SELECT count(build_date) FROM stats_build AS r WHERE ( r.node1='$i' OR r.node2='$i' ) AND r.build_date > '$DATE' " 2>/dev/null)
	if [ "$m" = "" ] ; then m=0 ; fi
	echo "$m builds in the last 24h on $i" >> $TMPFILE3
done
rm $TMPFILE1 >/dev/null
sort -g -r $TMPFILE2
echo
sort -g -r $TMPFILE3
rm $TMPFILE2 $TMPFILE3 >/dev/null
echo
