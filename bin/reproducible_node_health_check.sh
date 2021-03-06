#!/bin/bash
# vim: set noexpandtab:

# Copyright 2014-2020 Holger Levsen <holger@layer-acht.org>
#         © 2015-2018 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code for tests.reproducible-builds.org
. /srv/jenkins/bin/reproducible_common.sh

# to have a list of the nodes running in the future
. /srv/jenkins/bin/jenkins_node_definitions.sh

# some defaults
DIRTY=false
REP_RESULTS=/srv/reproducible-results

show_fstab_and_mounts() {
	echo "################################"
	echo "/dev/shm and /run/shm on $HOSTNAME"
	echo "################################"
	ls -lartd /run/shm /dev/shm/
	echo "################################"
	echo "/etc/fstab on $HOSTNAME"
	echo "################################"
	cat /etc/fstab
	echo "################################"
	echo "mount output on $HOSTNAME"
	echo "################################"
	mount
	echo "################################"
	DIRTY=true
}

#
# fail hard
#
set -e

#
# is the filesystem writetable?
#
echo "$(date -u) - testing whether /tmp is writable..."
TEST=$(mktemp --tmpdir=/tmp rwtest-XXXXXX)
if [ -z "$TEST" ] ; then
	echo "Failure to write a file in /tmp, assuming read-only filesystem."
	exit 1
fi
rm $TEST > /dev/null

#
# check for /dev/shm being mounted properly
#
echo "$(date -u) - testing whether /dev/shm is mounted correctly..."
mount | egrep -q "^tmpfs on /dev/shm"
if [ $? -ne 0 ] ; then
	echo "Warning: /dev/shm is not mounted correctly on $HOSTNAME, it should be a tmpfs, please tell the jenkins admins to fix this."
	show_fstab_and_mounts
fi
test "$(stat -c %a -L /dev/shm)" = 1777
if [ $? -ne 0 ] ; then
	echo "Warning: /dev/shm is not mounted correctly on $HOSTNAME, it should be mounted with 1777 permissions, please tell the jenkins admins to fix this."
	show_fstab_and_mounts
fi
#
# check for /run/shm being a link to /dev/shm
#
echo "$(date -u) - testing whether /run/shm is a link..."
if ! test -L /run/shm ; then
	echo "Warning: /run/shm is not a link on $HOSTNAME, please tell the jenkins admins to fix this."
	show_fstab_and_mounts
elif [ "$(readlink /run/shm)" != "/dev/shm" ] ; then
	echo "Warning: /run/shm is a link, but not pointing to /dev/shm on $HOSTNAME, please tell the jenkins admins to fix this."
	show_fstab_and_mounts
fi

#
# check for hanging mounts
#
echo "$(date -u) - testing whether running 'mount' takes forever..."
timeout -s 9 15 mount > /dev/null
TIMEOUT=$?
if [ $TIMEOUT -ne 0 ] ; then
	echo "$(date -u) - running 'mount' takes forever, giving up."
	exit 1
fi

#
# check for correct future
#
# (XXX: yes this is hardcoded but meh…)
echo "$(date -u) - testing whether the time is right..."
get_node_information "$HOSTNAME"
real_year=2020
year=$(date +%Y)
if "$NODE_RUN_IN_THE_FUTURE"; then
	if [ "$year" -eq "$real_year" ]; then
		echo "Warning, today $HOSTNAME came back to the present: $(date -u)."
		DIRTY=true
	elif [ "$year" -eq "$((real_year + 1))" ] || \
		 [ "$year" -eq "$((real_year + 2))" -a "$(date +%m)" -eq 1 ]; then
		echo "Good, today is the right future: $(date -u)."
	else
		echo "Warning, today is the wrong future: $(date -u)."
		DIRTY=true
	fi
else
	if [ "$year" -eq "$real_year" ]; then
		echo "Host is running in the present as it should: $(date -u)."
	else
		echo "Warning, today is the wrong present: $(date -u)."
		DIRTY=true
	fi
fi

#
# check for cleaned up kernels
# (on Ubuntu systems only, as those have free spaces issues on /boot frequently)
#
if [ "$(lsb_release -si)" = "Ubuntu" ] ; then
	echo "$(date -u) - testing whether only one kernel is installed..."
	if [ "$(ls /boot/vmlinuz-*|wc -l)" != "1" ] ; then
		echo "Warning, more than one kernel in /boot:"
		ls -lart /boot/vmlinuz-*
		df -h /boot
		echo "Running kernel: $(uname -r)"
		DIRTY=true
	fi
fi

#
# check if the latest kernel is running
#
echo "$(date -u) - testing whether the latest kernel is running..."
if ! dsa-check-running-kernel ; then
	echo "Warning: running kernel needs attention!"  # string checked with logparse
	DIRTY=true
fi

#
# check whether all services are running fine
#
echo "$(date -u) - checking whether all services are running fine..."
if ! systemctl is-system-running > /dev/null; then
	if [ -n "$(systemctl list-units --state=error,failed | grep pbuilder_build)" ] ; then
		echo "$(date -u) - resetting failed services (once) as some failed pbuilder_build have been found..."
	        sudo systemctl reset-failed
	fi
	if ! systemctl is-system-running > /dev/null; then
		systemctl status|head -5
		echo "Warning: systemd is reporting errors:"
		systemctl list-units --state=error,failed
		echo "Manual cleanup needed. If only old sessions are gone, use 'systemctl reset-failed' to cleanup state. Else probably some services actually need a restart."
		DIRTY=true
	fi
fi

# checks only for the main node
#
if [ "$HOSTNAME" = "$MAINNODE" ] ; then
	echo "$(date -u) - checking for known jenkins problems..."
	jenkins_bugs_check
fi

#
# finally
#
if ! $DIRTY ; then
	echo "$(date -u ) - Everything seems to be fine."
	echo
fi

echo "$(date -u) - the end."
