#!/bin/bash
# vim: set noexpandtab:

# Copyright © 2017 Holger Levsen (holger@layer-acht.org)
#           © 2018 Mattia Rizolo <mattia@debian.org>
# released under the GPLv=2

set -e

WORKER_NAME=$1
NODE1=$2
NODE2=$3

# normally defined by jenkins and used by reproducible_common.sh
JENKINS_URL=https://jenkins.debian.net

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

notify_log_of_failure() {
	tee -a /var/log/jenkins/reproducible-builder-errors.log <<-END

		$WORKER_NAME/$BUILD_ID exited with an error.  Return code: $RETCODE
		Check out the log at $BUILD_URL

		END
}

# endless loop
while true ; do
	#
	# check if we really should be running
	#
	RUNNING=$(ps fax|grep -v grep|grep "$0 $1 ")
	if [ -z "$RUNNING" ] ; then
		echo "$(date --utc) - '$0 $1' already running, thus stopping this."
		break
	fi
	SERVICE="reproducible_build@startup.service"
	# try systemctl twice, but only output and thus log the 2nd attempt…
	RUNNING=$(systemctl show $SERVICE 2>/dev/null |grep ^SubState|cut -d "=" -f2)
	if [ "$RUNNING" != "running" ] ; then
		# sometimes systemctl requests time out… handle that gracefully
		sleep 23
		RUNNING=$(systemctl show $SERVICE|grep ^SubState|cut -d "=" -f2)
		if [ "$RUNNING" != "running" ] ; then
			echo "$(date --utc) - '$SERVICE' not running, thus stopping this."
			break
		fi
	fi
	LOCKFILE="/var/lib/jenkins/NO-RB-BUILDERS-PLEASE"
	if [ -f "$LOCKFILE" ]; then
		echo "The lockfile $LOCKFILE is present, thus stopping this"
		break
	fi
	JENKINS_OFFLINE_LIST="/var/lib/jenkins/offline_nodes"
	if [ -f "$JENKINS_OFFLINE_LIST" ]; then
		for n in "$NODE1" "$NODE2"; do
			if grep -q "$n" "$JENKINS_OFFLINE_LIST"; then
				echo "$n is currently marked as offline, stopping the worker."
				break
			fi
		done
	fi

	# sleep up to 2.3 seconds (additionally to the random sleep reproducible_build.sh does anyway)
	/bin/sleep $(echo "scale=1 ; $(shuf -i 1-23 -n 1)/10" | bc )

	#
	# increment BUILD_ID
	#
	BUILD_BASE=/var/lib/jenkins/userContent/reproducible/debian/build_service/$WORKER_NAME
	OLD_ID=$(ls -1rt $BUILD_BASE|egrep -v "(latest|worker.log)" |sort -n|tail -1)
	let BUILD_ID=OLD_ID+1
	mkdir -p $BUILD_BASE/$BUILD_ID
	rm -f $BUILD_BASE/latest
	ln -sf $BUILD_ID $BUILD_BASE/latest

	#
	# prepare variables for export
	#
	export BUILD_URL=https://jenkins.debian.net/userContent/reproducible/debian/build_service/$WORKER_NAME/$BUILD_ID/
	export BUILD_ID=$BUILD_ID
	export JOB_NAME="reproducible_builder_$WORKER_NAME"
	export

	#
	# actually run reproducible_build.sh
	#
	echo
	echo "================================================================================================"
	echo "$(date --utc) - running build #$BUILD_ID for $WORKER_NAME on $NODE1 and $NODE2."
	echo "                               see https://tests.reproducible-builds.org/cgi-bin/nph-logwatch?$WORKER_NAME/$BUILD_ID"
	echo "================================================================================================"
	echo
	RETCODE=0
	/srv/jenkins/bin/reproducible_build.sh $NODE1 $NODE2 >$BUILD_BASE/$BUILD_ID/console.log 2>&1 || RETCODE=$?
	echo

	[ "$RETCODE" -eq 0 ] || notify_log_of_failure

done
