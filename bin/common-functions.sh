#!/bin/bash
# vim: set noexpandtab:

# Copyright 2014-2019 Holger Levsen <holger@layer-acht.org>
#         © 2018      Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2

common_cleanup() {
	echo "$(date -u) - $0 stopped running as $TTT, which will now be removed."
	rm -f $TTT
}

abort_if_bug_is_still_open() {
	local TMPFILE=$(mktemp --tmpdir=/tmp jenkins-bugcheck-XXXXXXX)
	echo "$(date -u) - checking bug #$1 status."
	bts status $1 fields:done > $TMPFILE || true
	# if we get a valid response…
	if [ ! -z "$(grep done $TMPFILE)" ] ; then
		# if the bug is not done (by some email address containing a @)
		if [ -z "$(grep "@" $TMPFILE)" ] ; then
			rm $TMPFILE
			echo
			echo
			echo "########################################################################"
			echo "#                                                                      #"
			echo "#   https://bugs.debian.org/$1 is still open, aborting this job.   #"
			echo "#                                                                      #"
			echo "########################################################################"
			echo
			echo
			echo "Warning: aborting the job because of bug because #$1"
			echo
			echo "After having fixed the cause for #$1, remove the check from common_init()"
			echo "in bin/common-functions.sh and re-run the job. Close #$1 after the"
			echo "problem is indeed fixed."
			echo
			exec /srv/jenkins/bin/abort.sh
			exit 0
		fi
	fi
	rm $TMPFILE
}

#
# run ourself with the same parameter as we are running
# but run a copy from /tmp so that the source can be updated
# (Running shell scripts fail weirdly when overwritten when running,
#  this hack makes it possible to overwrite long running scripts
#  anytime...)
#
common_init() {
# check whether this script has been started from /tmp already
if [ "${0:0:5}" != "/tmp/" ] ; then
	# check that we are not root
	if [ $(id -u) -eq 0 ] ; then
		echo "Do not run this as root."
		exit 1
	fi
	# - for remote jobs we need to check against $SSH_ORIGINAL_COMMAND
	# - for local jobs this would be $JOB_NAME
	if [ -n "$JOB_NAME" ] ; then
		WHOAREWE=$JOB_NAME
	else
		WHOAREWE=${SSH_ORIGINAL_COMMAND/%\ */}
	fi
	# abort certain jobs if we know they will fail due to certain bugs…
	case $WHOAREWE in
		#chroot-installation_*_install_design-desktop-*)
		#	for BLOCKER in 869155 867695 ; do
		#		abort_if_bug_is_still_open $BLOCKER
		#	done ;;
		chroot-installation_buster_install_design*)
			# technically these two bugs dont affect design-desktop
			# but just a depends of it, however I don't think it's likely
			# design-desktop will enter buster without these two bugs being fixed
			abort_if_bug_is_still_open 890754 ;;
		chroot-installation_stretch_install_education-desktop-gnome_upgrade_to_buster|chroot-installation_stretch_install_education-desktop-xfce_upgrade_to_buster|chroot-installation_stretch_install_education-networked_upgrade_to_buster)
			abort_if_bug_is_still_open 928429 ;;
		*) ;;
	esac
	# mktemp some place for us...
	TTT=$(mktemp --tmpdir=/tmp jenkins-script-XXXXXXXX)
	if [ -z "$TTT" ] ; then
		echo "Failed to create tmpfile, aborting. (Probably due to read-only filesystem…)"
		exit 1
	fi
	# prepare cleanup
	trap common_cleanup INT TERM EXIT
	# cp $0 to /tmp and run it from there
	cp $0 $TTT
	chmod +x $TTT
	echo "===================================================================================="
	echo
	echo "$(date -u) - running $0 (for job $WHOAREWE) on $(hostname) now."
	echo
	echo "To learn to understand this, git clone https://salsa.debian.org/qa/jenkins.debian.net.git"
	echo "and then have a look at the files README, INSTALL, CONTRIBUTING and maybe TODO."
	echo
	echo "This invocation of this script, which is located in bin/$(basename $0),"
	echo "has been called using \"$@\" as arguments."
	echo
	echo "Please send feedback about jenkins to qa-jenkins-dev@lists.alioth.debian.org,"
	echo "or as a bug against the 'jenkins.debian.org' pseudo-package,"
	echo "feedback about specific job results should go to their respective lists and/or the BTS."
	echo
	echo "===================================================================================="
	echo "$(date -u) - start running \"$0\" (md5sum $(md5sum $0|cut -d ' ' -f1)) as \"$TTT\" on $(hostname)."
	echo
	# this is the "hack": call ourself as a copy in /tmp again
	$TTT "$@"
	exit $?
	# cleanup is done automatically via trap
else
	# this directory resides on tmpfs, so it might be gone after reboots...
	mkdir -p /srv/workspace/chroots
	# default settings used for the jenkins.debian.net environment
	if [ -z "$LC_ALL" ]; then
		export LC_ALL=C.UTF-8
	fi

	if [ -z "$MIRROR" ]; then
		case $HOSTNAME in
			jenkins|jenkins-test-vm|profitbricks-build*|osuosl*)
				export MIRROR=http://cdn-fastly.deb.debian.org/debian ;;
			bbx15|cb3*|cbxi4*|wbq0|odxu4*|odu3*|odc*|ff*|ff4*|opi2*|jt?1*|p64*)
				export MIRROR=http://cdn-fastly.deb.debian.org/debian ;;
			codethink*)
				export MIRROR=http://cdn-fastly.deb.debian.org/debian ;;
			spectrum)
				export MIRROR=none ;;
			*)
				echo "unsupported host, exiting." ; exit 1 ;;
		esac
	fi
	# force http_proxy as we want it
	case $HOSTNAME in
		jenkins|jenkins-test-vm|profitbricks-build1-a*|profitbricks-build2*|profitbricks-build9*|profitbricks-build11*|profitbricks-build12*)
			# pb datacenter in karlsruhe uses pb1 as proxy:
			export http_proxy="http://78.137.99.97:3128" ;;
		profitbricks-build5*|profitbricks-build6*|profitbricks-build7*|profitbricks-build10*|profitbricks-build15*|profitbricks-build16*)
			# pb datacenter in frankfurt uses pb10 as proxy:
			export http_proxy="http://85.184.249.68:3128" ;;
		osuosl*)
			# all nodes at OSUOSL use osuosl167 as proxy:
			export http_proxy="http://10.6.5.46:3128" ;;
		codethink*)
			export http_proxy="http://192.168.101.16:3128" ;;
		bbx15|cb3*|cbxi4*|wbq0|odxu4*|odu3*|odc*|ff*|ff4*|opi2*|jt?1*|p64*)
			export http_proxy="http://10.0.0.15:8000/" ;;
		spectrum)
			export http_proxy="http://127.0.0.1:3128" ;;
		*)
			echo "unsupported host, exiting." ; exit 1 ;;
	esac
	if [ -z "$CHROOT_BASE" ]; then
		export CHROOT_BASE=/chroots
	fi
	if [ -z "$SCHROOT_BASE" ]; then
		export SCHROOT_BASE=/schroots
	fi
	if [ ! -d "$SCHROOT_BASE" ]; then
		echo "Directory $SCHROOT_BASE does not exist, aborting."
		exit 1
	fi
	# use these settings in the scripts in the (s)chroots too
	export SCRIPT_HEADER="#!/bin/bash
	if $DEBUG ; then
		set -x
	fi
	set -e
	export DEBIAN_FRONTEND=noninteractive
	export LC_ALL=$LC_ALL
	export http_proxy=$http_proxy
	export MIRROR=$MIRROR"
	# be more verbose, maybe
	if $DEBUG ; then
		export
		set -x
	fi
	set -e
fi
}

publish_changes_to_userContent() {
	echo "Extracting contents from .deb files..."
	CHANGES=$1
	CHANNEL=$2
	SRCPKG=$(basename $CHANGES | cut -d "_" -f1)
	if [ -z "$SRCPKG" ] ; then
		exit 1
	fi
	VERSION=$(basename $CHANGES | cut -d "_" -f2)
	TARGET="/var/lib/jenkins/userContent/$SRCPKG"
	NEW_CONTENT=$(mktemp -d -t new-content-XXXXXXXX)
	for DEB in $(dcmd --deb $CHANGES) ; do
		dpkg --extract $DEB ${NEW_CONTENT} 2>/dev/null
	done
	rm -rf $TARGET
	mkdir $TARGET
	mv ${NEW_CONTENT}/usr/share/doc/${SRCPKG}* $TARGET/
	rm -r ${NEW_CONTENT}
	if [ -z "$3" ] ; then
		touch "$TARGET/${VERSION}"
		FROM=""
	else
		touch "$TARGET/${VERSION}_$3"
		FROM=" from $3"
	fi
	MESSAGE="https://jenkins.debian.net/userContent/$SRCPKG/ has been updated${FROM}."
	echo
	echo $MESSAGE
	echo
	if [ ! -z "$CHANNEL" ] ; then
		kgb-client --conf /srv/jenkins/kgb/$CHANNEL.conf --relay-msg "$MESSAGE"
	fi
}

write_page() {
	echo "$1" >> $PAGE
}

jenkins_zombie_check() {
	#
	# sometimes deleted jobs come back as zombies
	# and we dont know why and when that happens,
	# so just report those zombies here.
	#
	ZOMBIES=$(ls -1d /var/lib/jenkins/jobs/* | egrep 'strip-nondeterminism|reprotest|reproducible_(builder_(amd64|i386|armhf|arm64)|setup_(pbuilder|schroot)_testing)|chroot-installation_wheezy|aptdpkg|odc2a|stretch_install_education-thin-client-server|jessie_multiarch_versionskew|dpkg_stretch_find_trigger_cycles|sid_install_education-services|buster_install_education-services|lvc|chroot-installation_stretch_.*_upgrade_to_sid|piuparts_.*_jessie|udd_stretch|d-i_pu-build|debsums-tests_stretch|debian-archive-keyring-tests_stretch' || true)
	if [ ! -z "$ZOMBIES" ] ; then
		DIRTY=true
		figlet 'zombies!!!'
		echo "Warning, rise of the jenkins job zombies has started again, these jobs should not exist:"
		for z in $ZOMBIES ; do

			echo $(basename $z)
		done
		echo
	fi
}

jenkins_logsize_check() {
	#
	# /var/log/jenkins/jenkins.log sometimes grows very fast
	# and we don't yet know why, so let's monitor this for now.
	JENKINSLOG="$(find /var/log/jenkins -name jenkins.log -size +42G)"
	if [ -z "JENKINSLOG" ] ; then
		figlet 'jenkins.log size'
		echo "Warning, jenkins.log is larger than 42G, please fix, erroring out now."
		exit 1
	else
		JENKINSLOG="$(find /var/log/jenkins -name jenkins.log -size +23G)"
		if [ -z "JENKINSLOG" ] ; then
			DIRTY=true
			figlet 'jenkins.log size'
			echo "Warning, jenkins.log is larger than 23G, please do something…"
		fi
	fi
}
