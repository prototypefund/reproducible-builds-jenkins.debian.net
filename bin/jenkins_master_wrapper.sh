#!/bin/bash
# vim: set noexpandtab:

# Copyright 2015-2019 Holger Levsen <holger@layer-acht.org>
#                2016 Phil Hands <phil@hands.com>
#           2018      Mattia Rizzolo <mattia@debian.org>
# released under the GPLv2
# based on an idea by Peter Palfrader (see bin/jenkins_node_wrapper.sh)

set -u
set -e

# don't try to run on test system
if [ "$HOSTNAME" = "jenkins-test-vm" ] ; then
	echo "$(date -u) - running on $HOSTNAME, exiting successfully and cleanly immediatly."
	exit 0
fi

# define Debian build nodes in use
. /srv/jenkins/bin/jenkins_node_definitions.sh

if [ "${NODE_NAME%.*}" = "$NODE_NAME" ]; then
	# The NODE_NAME variable does not contain a dot, so it is not a FQDN.
	# Fixup the value, hoping to get it right.
	# XXX really this should not happen, how this came to be is unknown.
	export NODE_NAME="${NODE_NAME}.debian.net"
fi

get_node_information $NODE_NAME

# don't try to fetch artifacts by default
RETRIEVE_ARTIFACTS=no

# add some more params if needed,
# by default we just use the job name as param
case $JOB_NAME in
	rebootstrap_*|chroot-installation_*|haskell-package-plan)
			PARAMS="$JOB_NAME $@"
			;;
	*)		PARAMS="$JOB_NAME"
			;;
esac

# pseudo job used to cleanup nodes
if [ "$JOB_NAME" = "cleanup_nodes" ] ; then
	   PARAMS="$PARAMS $@"
fi

#
# main
#
set +e
ssh -o "BatchMode = yes" $NODE_NAME /bin/true
RESULT=$?
# abort job if host is down
if [ $RESULT -ne 0 ] ; then
	#
	# this should abort (=no success, but also no status change mails…) but as
	# this somehow doesnt work anymore, rather error out to see the breakage…
	#
	#echo "$(date -u) - $NODE_NAME seems to be down, sleeping 15min before aborting this job."
	echo "$(date -u) - $NODE_NAME seems to be down, sleeping 1min before exiting with error."
	sleep 1m
	exit 1
	#exec /srv/jenkins/bin/abort.sh
fi
set -e
#
# actually run things on the target node
#
RETVAL=0
ssh -o "BatchMode = yes" $NODE_NAME "$PARAMS" || {
	# mention failures, but continue since we might want the artifacts anyway
	RETVAL=$?
	printf "\nSSH EXIT CODE: %s\n" $RETVAL
}

if [ "$RETVAL" -eq 123 ]; then
	# special code passed returned by the remote abort.sh
	exec /srv/jenkins/bin/abort.sh
fi

# grab artifacts and tidy up at the other end
if [ "$RETRIEVE_ARTIFACTS" = "yes" ] ; then
	RESULTS="$WORKSPACE/workspace/$JOB_NAME/results"
	NODE_RESULTS="/var/lib/jenkins/jobs/$JOB_NAME/workspace/results"
	echo "$(date -u) - retrieving artifacts."
	set -x
	mkdir -p "$RESULTS"
	rsync -r --delete -v -e "ssh -o 'Batchmode = yes'" "$NODE_NAME:$NODE_RESULTS/" "$RESULTS/"
	ssh -o "BatchMode = yes" $NODE_NAME "rm -r $NODE_RESULTS"
fi

#
# exit with the actual exit code from the target node
#
exit $RETVAL
