#!/bin/bash

# Copyright 2014-2019 Holger Levsen <holger@layer-acht.org>
# released under the GPLv2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code (used for irc_message)
. /srv/jenkins/bin/reproducible_common.sh

send_irc_warning() {
	local WARNING=$1
	if [ -n "$2" ] ; then
		local CHANNEL=$2
	else
		local CHANNEL"reproducible-builds"
	fi
	irc_message $CHANNEL "$WARNING"
	echo "Warning: $WARNING"
}

check_pypi() {
	TMPPYPI=$(mktemp -t diffoscope-distribution-XXXXXXXX)
	# the following two lines are a bit fragile…
	curl https://pypi.org/project/diffoscope/ -o $TMPPYPI
	DIFFOSCOPE_IN_PYPI=$(sed -ne 's@.*diffoscope \([0-9][0-9]*\).*@\1@gp' $TMPPYPI)
	rm -f $TMPPYPI > /dev/null
	echo
	echo
	if [ "$DIFFOSCOPE_IN_DEBIAN" = "$DIFFOSCOPE_IN_PYPI" ] ; then
		echo "Yay. diffoscope in Debian has the same version as on PyPI: $DIFFOSCOPE_IN_DEBIAN"
	elif dpkg --compare-versions "$DIFFOSCOPE_IN_DEBIAN" gt "$DIFFOSCOPE_IN_PYPI" ; then
		echo "Fail: diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
		echo "Fail: diffoscope in PyPI:   $DIFFOSCOPE_IN_PYPI"
		send_irc_warning "It seems diffoscope $DIFFOSCOPE_IN_DEBIAN is not available on PyPI, which only has $DIFFOSCOPE_IN_PYPI."
		exit 0
	else
		echo "diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
		echo "diffoscope in PyPI:   $DIFFOSCOPE_IN_PYPI"
		echo
		echo "Failure is the default action…"
		exit 1
	fi
}

check_github_macports() {
	TMPPORT=$(mktemp -t diffoscope-distribution-XXXXXXXX)
	# the following two lines are a bit fragile…
	curl https://raw.githubusercontent.com/macports/macports-ports/master/sysutils/diffoscope/Portfile -o $TMPPORT
	DIFFOSCOPE_IN_MACPORTS=$(grep ^version $TMPPORT | sed -E 's#version( )+##' )
	rm -f $TMPPORT > /dev/null
	echo
	echo
	if [ "$DIFFOSCOPE_IN_DEBIAN" = "$DIFFOSCOPE_IN_MACPORTS" ] ; then
		echo "Yay. diffoscope in Debian has the same version as on MacPorts: $DIFFOSCOPE_IN_DEBIAN"
	elif dpkg --compare-versions "$DIFFOSCOPE_IN_DEBIAN" gt "$DIFFOSCOPE_IN_MACPORTS" ; then
		echo "Fail: diffoscope in Debian:   $DIFFOSCOPE_IN_DEBIAN"
		echo "Fail: diffoscope on MacPorts: $DIFFOSCOPE_IN_MACPORTS"
		send_irc_warning "It seems diffoscope $DIFFOSCOPE_IN_DEBIAN is not available on MacPorts, which only has $DIFFOSCOPE_IN_MACPORTS."
		exit 0
	else
		echo "diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
		echo "diffoscope in MacPorts:   $DIFFOSCOPE_IN_MACPORTS"
		echo
		echo "Failure is the default action…"
		exit 1
	fi
}


check_whohas() {
	# the following is "broken" (but good enough for now)
	# as sort doesn't do proper version comparison
	case $DISTRIBUTION in
		Arch)	DIFFOSCOPE_IN_WHOHAS=$(whohas -d $DISTRIBUTION diffoscope | grep -v "href=" | awk '{print $2}' | cut -d '>' -f2 | cut -d '<' -f1 | sort -n | tail -1)
			CHANNEL="archlinux-reproducible"
			;;
		*)	DIFFOSCOPE_IN_WHOHAS=$(whohas -d $DISTRIBUTION diffoscope | grep -v "href=" | awk '{print $3}' | sort -n | tail -1)
			CHANNEL=""
			;;
	esac
	echo
	echo
	if [ "$DIFFOSCOPE_IN_DEBIAN" = "$DIFFOSCOPE_IN_WHOHAS" ] ; then
		echo "Yay. diffoscope in Debian has the same version as $DISTRIBUTION has: $DIFFOSCOPE_IN_DEBIAN"
	elif dpkg --compare-versions "$DIFFOSCOPE_IN_DEBIAN" gt "$DIFFOSCOPE_IN_WHOHAS" ; then
		echo "Fail: diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
		echo "Fail: diffoscope in $DISTRIBUTION: $DIFFOSCOPE_IN_WHOHAS"
		send_irc_warning "It seems diffoscope $DIFFOSCOPE_IN_DEBIAN is not available on $DISTRIBUTION, which only has $DIFFOSCOPE_IN_WHOHAS." "$CHANNEL"
		exit 0
	elif [ "${DIFFOSCOPE_IN_DEBIAN}-1" = "$DIFFOSCOPE_IN_WHOHAS" ] ; then
		# archlinux package version can greater than Debian: 52-1 vs 52
		# workaround this above...
		echo "Yay. diffoscope in Debian has the same version as $DISTRIBUTION has: $DIFFOSCOPE_IN_DEBIAN (Debian) and $DIFFOSCOPE_IN_WHOHAS ($DISTRIBUTION)"
	else
		echo "diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
		echo "diffoscope in $DISTRIBUTION: $DIFFOSCOPE_IN_WHOHAS"
		echo
		echo "Failure is the default action…"
		exit 1
	fi
}


#
# main
#
for SUITE in 'experimental' 'unstable|sid'
do
	DIFFOSCOPE_IN_DEBIAN=$(rmadison diffoscope|egrep " ${SUITE} "| awk '{print $3}' | sort -r | head -1 || true)

	if [ "$DIFFOSCOPE_IN_DEBIAN" != "" ] ; then
		break
	fi
done

case $1 in
	PyPI)	check_pypi
		;;
	FreeBSD|NetBSD|Arch)
		DISTRIBUTION=$1
		check_whohas
		# missing tests: Fedora, openSUSE, maybe OpenBSD, Guix…
		;;
	MacPorts)
		check_github_macports
		;;
	*)
		echo "Unsupported distribution."
		exit 1
		;;
esac
