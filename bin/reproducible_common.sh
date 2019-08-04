#!/bin/bash
# vim: set noexpandtab:

# Copyright 2014-2019 Holger Levsen <holger@layer-acht.org>
#         © 2015-2018 Mattia Rizzolo <mattia@mapreri.org>
# released under the GPLv=2
#
# included by all reproducible_*.sh scripts, so be quiet
set +x

# postgres database definitions
export PGDATABASE=reproducibledb

# query reproducible database
query_db() {
	psql -t --no-align -c "$@" || exit 1
}

# query reproducible database, output to csv format
query_to_csv() {
	psql -c "COPY ($@) to STDOUT with csv DELIMITER ','" || exit 1
}

# common variables
BASE="/var/lib/jenkins/userContent/reproducible"
REPRODUCIBLE_URL=https://tests.reproducible-builds.org
REPRODUCIBLE_DOT_ORG_URL=https://reproducible-builds.org
# shop trailing slash
JENKINS_URL=${JENKINS_URL:0:-1}
DBDSUITE="unstable"
BIN_PATH=/srv/jenkins/bin
TEMPLATE_PATH=/srv/jenkins/mustache-templates/reproducible
CHPATH=/srv/reproducible-results/chdist
mkdir -p "$CHPATH"

# Debian suites being tested
SUITES="stretch buster bullseye unstable experimental"
# Debian architectures being tested
ARCHS="amd64 i386 arm64 armhf"

# define Debian build nodes in use
. /srv/jenkins/bin/jenkins_node_definitions.sh
MAINNODE="jenkins" # used by reproducible_maintenance.sh only
JENKINS_OFFLINE_LIST="/var/lib/jenkins/offline_nodes"

# variables on the nodes we are interested in
BUILD_ENV_VARS="ARCH NUM_CPU CPU_MODEL DATETIME KERNEL" # these also needs to be defined in bin/reproducible_info.sh

# common settings for Debian
DEBIAN_URL=https://tests.reproducible-builds.org/debian
DEBIAN_DASHBOARD_URI=/debian/reproducible.html
DEBIAN_BASE="/var/lib/jenkins/userContent/reproducible/debian"
mkdir -p "$DEBIAN_BASE"

# existing usertags in the Debian BTS
USERTAGS="toolchain infrastructure timestamps fileordering buildpath username hostname uname randomness buildinfo cpu signatures environment umask ftbfs locale"

# common settings for testing alpine
ALPINE_REPOS="main community"
ALPINE_PKGS=/srv/reproducible-results/alpine_pkgs
ALPINE_BASE="$BASE/alpine"

# common settings for testing Arch Linux
ARCHLINUX_REPOS="core extra multilib community"
ARCHLINUX_PKGS=/srv/reproducible-results/archlinux_pkgs
ARCHBASE=$BASE/archlinux

# common settings for testing rpm based distros
RPM_BUILD_NODE=osuosl-build171-amd64
RPM_PKGS=/srv/reproducible-results/rpm_pkgs

# number of cores to be used
NUM_CPU=$(nproc)

# diffoscope memory limit in kilobytes
DIFFOSCOPE_VIRT_LIMIT=$((10*1024*1024))

# we only this array for html creation but we cannot declare them in a function
declare -A SPOKENTARGET

# to hold reproducible temporary files/directories without polluting /tmp
TEMPDIR="/tmp/reproducible"
mkdir -p "$TEMPDIR"

# create subdirs for suites
for i in $SUITES ; do
	mkdir -p "$DEBIAN_BASE/$i"
done

# table names and image names
TABLE[0]=stats_pkg_state
TABLE[1]=stats_builds_per_day
TABLE[2]=stats_builds_age
TABLE[3]=stats_bugs
TABLE[4]=stats_notes
TABLE[5]=stats_issues
TABLE[6]=stats_meta_pkg_state
TABLE[7]=stats_bugs_state
TABLE[8]=stats_bugs_sin_ftbfs
TABLE[9]=stats_bugs_sin_ftbfs_state

# package sets defined in meta_pkgsets.csv
# csv file columns: (pkgset_group, pkgset_name)
colindex=0
while IFS=, read col1 col2
do
	let colindex+=1
	META_PKGSET[$colindex]=$col2
done < $BIN_PATH/reproducible_pkgsets.csv

# mustache templates
PAGE_FOOTER_TEMPLATE=$TEMPLATE_PATH/default_page_footer.mustache
PROJECT_LINKS_TEMPLATE=$TEMPLATE_PATH/project_links.mustache
MAIN_NAVIGATION_TEMPLATE=$TEMPLATE_PATH/main_navigation.mustache

# be loud again if DEBUG
if $DEBUG ; then
	set -x
fi

# some cmomon logging functions
log_info () {
	_log "I:" "$@"
}

log_error () {
	_log "E:" "$@"
}

log_warning () {
	_log "W:" "$@"
}

log_file () {
	cat $@ | tee -a $RBUILDLOG
}

_log () {
	local prefix="$1"
	shift 1
	echo -e "$(date -u)  $prefix $*" | tee -a $RBUILDLOG
}

# sleep 1-23 secs to randomize start times
delay_start() {
	/bin/sleep $(echo "scale=1 ; $(shuf -i 1-230 -n 1)/10" | bc )
}

schedule_packages() {
	LC_USER="$REQUESTER" \
	LOCAL_CALL="true" \
	/srv/jenkins/bin/reproducible_remote_scheduler.py \
		--message "$REASON" \
		--no-notify \
		--suite "$SUITE" \
		--architecture "$ARCH" \
		$@
}

set_icon() {
	# icons taken from tango-icon-theme (0.8.90-5)
	# licenced under http://creativecommons.org/licenses/publicdomain/
	STATE_TARGET_NAME="$1"
	case "$1" in
		reproducible)		ICON=weather-clear.png
					;;
		FTBR)		ICON=weather-showers-scattered.png
					STATE_TARGET_NAME="FTBR"
					;;
		FTBFS)			ICON=weather-storm.png
					;;
		timeout)	ICON=Current_event_clock.png ;;
		depwait)		ICON=weather-snow.png
					;;
		E404)			ICON=weather-severe-alert.png
					;;
		NFU)		ICON=weather-few-clouds-night.png
					STATE_TARGET_NAME="NFU"
					;;
		blacklisted)		ICON=error.png
					;;
		*)			ICON=""
	esac
}

write_icon() {
	# ICON and STATE_TARGET_NAME are set by set_icon()
	write_page "<a href=\"/debian/$SUITE/$ARCH/index_${STATE_TARGET_NAME}.html\" target=\"_parent\"><img src=\"/static/$ICON\" alt=\"${STATE_TARGET_NAME} icon\" /></a>"
}

write_page_header() {
	# this is really quite uncomprehensible and should be killed
	# the solution is to write all HTML pages with python…
	rm -f $PAGE
	MAINVIEW="dashboard"
	write_page "<!DOCTYPE html><html><head>"
	write_page "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />"
	write_page "<meta name=\"viewport\" content=\"width=device-width\" />"
	write_page "<link href=\"/static/style.css\" type=\"text/css\" rel=\"stylesheet\" />"
	write_page "<title>$2</title></head>"
	if [ "$1" != "$MAINVIEW" ] ; then
		write_page "<body class=\"wrapper\">"
	else
		write_page "<body class=\"wrapper\" onload=\"selectSearch()\">"
	fi

	# Build context for the main_navigation mustache template.

	# Do not show package set links for "experimental" pages
	if [ "$SUITE" != "experimental" ] ; then
		# no pkg_sets are tested in experimental
		include_pkgset_link="\"include_pkgset_link\" : \"true\""
	else
		include_pkgset_link=''
	fi

	# Used to highlight the link for the current page
	if [ "$1" = "dashboard" ] \
		|| [ "$1" = "performance" ] \
		|| [ "$1" = "repositories" ] \
		|| [ "$1" = "variations" ] \
		|| [ "$1" = "suite_arch_stats" ] \
		|| [ "$1" = "bugs" ] \
		|| [ "$1" = "nodes_health" ] \
		|| [ "$1" = "job_health" ] \
		|| [ "$1" = "nodes_weekly_graphs" ] \
		|| [ "$1" = "nodes_daily_graphs" ] ; then
		displayed_page="\"$1\": \"true\""
	else
		displayed_page=''
	fi

	# Create json for suite links (a list of objects)
	suite_links="\"suite_nav\": { \"suite_list\": ["
	comma=0
	for s in $SUITES ; do
		if [ "$s" = "$SUITE" ] ; then
			class="current"
		else
			class=''
		fi
		uri="/debian/${s}/index_suite_${ARCH}_stats.html"
		if [ $comma = 1 ] ; then
			suite_links+=", {\"s\": \"${s}\", \"class\": \"$class\", \"uri\": \"$uri\"}"
		else
			suite_links+="{\"s\": \"${s}\", \"class\": \"$class\", \"uri\": \"$uri\"}"
			comma=1
		fi
	done
	suite_links+="]}"

	# Create json for arch links (a list of objects)
	arch_links="\"arch_nav\": {\"arch_list\": ["
	comma=0
	for a in ${ARCHS} ; do
		if [ "$a" = "$ARCH" ] ; then
			class="current"
		else
			class=''
		fi
		uri="/debian/$SUITE/index_suite_${a}_stats.html"
		if [ $comma = 1 ] ; then
			arch_links+=", {\"a\": \"${a}\", \"class\": \"$class\", \"uri\": \"$uri\"}"
		else
			arch_links+="{\"a\": \"${a}\", \"class\": \"$class\", \"uri\": \"$uri\"}"
			comma=1
		fi
	done
	arch_links+="]}"

	# finally, the completely formed JSON context
	context=$(printf '{
		"arch" : "%s",
		"suite" : "%s",
		"page_title" : "%s",
		"debian_uri" : "%s",
		%s,
		%s
	' "$ARCH" "$SUITE" "$2" "$DEBIAN_DASHBOARD_URI" "$arch_links" "$suite_links")
	if [[ ! -z $displayed_page ]] ; then
		context+=", $displayed_page"
	fi
	if [[ ! -z $include_pkgset_link ]] ; then
		context+=", $include_pkgset_link"
	fi
	context+="}"

	write_page "<header class=\"head\">"
	write_page "$(pystache3 $MAIN_NAVIGATION_TEMPLATE "$context")"
	write_page "$(pystache3 $PROJECT_LINKS_TEMPLATE "{}")"
	write_page "</header>"

	write_page "<div class=\"mainbody\">"
	write_page "<h2>$2</h2>"
	if [ "$1" = "$MAINVIEW" ] ; then
		write_page "<ul>"
		write_page "   Please also visit the more general website <li><a href=\"https://reproducible-builds.org\">Reproducible-builds.org</a></li> where <em>reproducible builds</em> are explained in more detail than just <em>bit by bit identical rebuilds to enable verifcation of the sources used to build</em>."
		write_page "   We think that reproducible builds should become the norm, so we wrote <li><a href=\"https://reproducible-builds.org/howto\">How to make your software reproducible</a></li>."
		write_page "   Also aimed at the free software world at large, is the first specification we have written: the <li><a href=\"https://reproducible-builds.org/specs/source-date-epoch/\">SOURCE_DATE_EPOCH specification</a></li>."
		write_page "</ul>"
		write_page "<ul>"
		write_page "   These pages are showing the <em>potential</em> of <li><a href=\"https://wiki.debian.org/ReproducibleBuilds\" target=\"_blank\">reproducible builds of Debian packages</a></li>."
		write_page "   The results shown were obtained by <a href=\"$JENKINS_URL/view/reproducible\">several jobs</a> running on"
		write_page "   <a href=\"$JENKINS_URL/userContent/about.html#_reproducible_builds_jobs\">jenkins.debian.net</a>."
		write_page "   Thanks to <a href=\"https://www.profitbricks.co.uk\">Profitbricks</a> for donating the virtual machines this is running on!"
		write_page "</ul>"
		LATEST=$(query_db "SELECT s.name FROM results AS r JOIN sources AS s ON r.package_id = s.id WHERE r.status = 'FTBR' AND s.suite = 'unstable' AND s.architecture = 'amd64' AND s.id NOT IN (SELECT package_id FROM notes) ORDER BY build_date DESC LIMIT 23"|sort -R|head -1)
		write_page "<form action=\"$REPRODUCIBLE_URL/redirect\" method=\"GET\">$REPRODUCIBLE_URL/"
		write_page "<input type=\"text\" name=\"SrcPkg\" placeholder=\"Type my friend..\" value=\"$LATEST\" />"
		write_page "<input type=\"submit\" value=\"submit source package name\" />"
		write_page "</form>"
		write_page "<ul>"
		write_page "   We are reachable via IRC (<code>#debian-reproducible</code> and <code>#reproducible-builds</code> on OFTC),"
		write_page "   or <a href="mailto:reproducible-builds@lists.alioth.debian.org">email</a>,"
		write_page "   and we care about free software in general,"
		write_page "   so whether you are an upstream developer or working on another distribution, or have any other feedback - we'd love to hear from you!"
		write_page "   Besides Debian we are also testing "
		write_page "   <li><a href=\"/coreboot/\">coreboot</a></li>,"
		write_page "   <li><a href=\"/openwrt/\">OpenWrt</a></li>, "
		write_page "   <li><a href=\"/netbsd/\">NetBSD</a></li>, "
		write_page "   <li><a href=\"/freebsd/\">FreeBSD</a></li>, "
		write_page "   and <li><a href=\"/archlinux/\">Arch Linux</a></li> "
		write_page "   though not as thoroughly as Debian yet. "
		write_page "   <li><a href=\"http://rb.zq1.de/\">openSUSE</a></li>, "
		write_page "   <li><a href=\"https://r13y.com/\">NixOS</a></li> and "
		write_page "   <li><a href=\"https://verification.f-droid.org/\">F-Droid</a></li> are also being tested, though elsewhere."
		write_page "   As far as we know, the <a href=\"https://www.gnu.org/software/guix/manual/en/html_node/Invoking-guix-challenge.html\">Guix challenge</a> is not yet run systematically anywhere."
		write_page "   Testing of "
		write_page "   <a href=\"/rpms/fedora-23.html\">Fedora</a> "
		write_page "   has sadly been suspended for now. "
		write_page " We can test more projects, if <em>you</em> contribute!"
		write_page "</ul>"
	fi
}

write_page_intro() {
	write_page "       <p><em>Reproducible builds</em> enable anyone to reproduce bit by bit identical binary packages from a given source, so that anyone can verify that a given binary derived from the source it was said to be derived."
	write_page "         There is more information about <a href=\"https://wiki.debian.org/ReproducibleBuilds\">reproducible builds on the Debian wiki</a> and on <a href=\"https://reproducible-builds.org\">https://reproducible-builds.org</a>."
	write_page "         These pages explain in more depth why this is useful, what common issues exist and which workarounds and solutions are known."
	write_page "        </p>"
	local BUILD_ENVIRONMENT=" in a Debian environment"
	local BRANCH="master"
	if [ "$1" = "coreboot" ] ; then
		write_page "        <p><em>Reproducible Coreboot</em> is an effort to apply this to coreboot. Thus each coreboot.rom is build twice (without payloads), with a few variations added and then those two ROMs are compared using <a href=\"https://tracker.debian.org/diffoscope\">diffoscope</a>. Please note that the toolchain is not varied at all as the rebuild happens on exactly the same system. More variations are expected to be seen in the wild.</p>"
		local PROJECTNAME="$1"
		local PROJECTURL="https://review.coreboot.org/p/coreboot.git"
	elif [ "$1" = "OpenWrt" ] ; then
		local PROJECTNAME="$1"
		local PROJECTURL="https://github.com/openwrt/openwrt.git"
		write_page "        <p><em>Reproducible $PROJECTNAME</em> is an effort to apply this to $PROJECTNAME. Thus each $PROJECTNAME target is build twice, with a few variations added and then the resulting images and packages from the two builds are compared using <a href=\"https://tracker.debian.org/diffoscope\">diffoscope</a>. $PROJECTNAME generates many different types of raw <code>.bin</code> files, and diffoscope does not know how to parse these. Thus the resulting diffoscope output is not nearly as clear as it could be - hopefully this limitation will be overcome eventually, but in the meanwhile the input components (uImage kernel file, rootfs.tar.gz, and/or rootfs squashfs) can be inspected. Also please note that the toolchain is not varied at all as the rebuild happens on exactly the same system. More variations are expected to be seen in the wild.</p>"
	elif [ "$1" = "NetBSD" ] ; then
		write_page "        <p><em>Reproducible NetBSD</em> is an effort to apply this to NetBSD. Thus each NetBSD target is build twice, with a few variations added and then the resulting files from the two builds are compared using <a href=\"https://tracker.debian.org/diffoscope\">diffoscope</a>. Please note that the toolchain is not varied at all as the rebuild happens on exactly the same system. More variations are expected to be seen in the wild.</p>"
		local PROJECTNAME="netbsd"
		local PROJECTURL="https://github.com/NetBSD/src"
	elif [ "$1" = "FreeBSD" ] ; then
		write_page "        <p><em>Reproducible FreeBSD</em> is an effort to apply this to FreeBSD. Thus FreeBSD is build twice, with a few variations added and then the resulting filesystems from the two builds are put into a compressed tar archive, which is finally compared using <a href=\"https://tracker.debian.org/diffoscope\">diffoscope</a>. Please note that the toolchain is not varied at all as the rebuild happens on exactly the same system. More variations are expected to be seen in the wild.</p>"
		local PROJECTNAME="freebsd"
		local PROJECTURL="https://github.com/freebsd/freebsd.git"
		local BUILD_ENVIRONMENT=", which via ssh triggers a build on a FreeBSD 11.2 system"
		local BRANCH="master"
	elif [ "$1" = "alpine" ] ; then
		local PROJECTNAME="alpine"
		write_page "        <p><em>Reproducible $PROJECTNAME</em> is an effort to apply this to $PROJECTNAME. Thus $PROJECTNAME packages are build twice, with a few variations added and then the resulting packages from the two builds are compared using <a href=\"https://tracker.debian.org/diffoscope\">diffoscope</a>."
		write_page "   Please note that this is still at an early stage. Also there are more variations expected to be seen in the wild."
		write_page "Missing bits for <em>testing</em> alpine:<ul>"
		write_page " <li>cross references to <a href=\"https://tests.reproducible-builds.org/debian/index_issues.html\">Debian notes</a> - and having alpine specific notes.</li>"
		write_page "</ul></p>"
		write_page "<p>Missing bits for alpine:<ul>"
		write_page " <li>code needs to be written to compare the packages built twice here against newly built packages from the Official alpine repositories.</li>"
		write_page " <li>user tools, for users to verify all of this easily.</li>"
		write_page "</ul></p>"
		write_page "<p>If you want to help out or discuss reproducible builds in $PROJECTNAME, please join #alpine-reproducible on freenode.</p>"
	elif [ "$1" = "Arch Linux" ] ; then
		local PROJECTNAME="Arch Linux"
		write_page "        <p><em>Reproducible $PROJECTNAME</em> is an effort to apply this to $PROJECTNAME. Thus $PROJECTNAME packages are build twice, with a few variations added and then the resulting packages from the two builds are compared using <a href=\"https://tracker.debian.org/diffoscope\">diffoscope</a>."
		write_page "   Please note that this is still at an early stage. Also there are more variations expected to be seen in the wild."
		write_page "Missing bits for <em>testing</em> Arch Linux:<ul>"
		write_page " <li>cross references to <a href=\"https://tests.reproducible-builds.org/debian/index_issues.html\">Debian notes</a> - and having Arch Linux specific notes.</li>"
		write_page "</ul></p>"
		write_page "<p>Missing bits for Arch Linux:<ul>"
		write_page " <li>code needs to be written to compare the packages built twice here against newly built packages from the Official Arch Linux repositories.</li>"
		write_page " <li>user tools, for users to verify all of this easily.</li>"
		write_page "</ul></p>"
		write_page "<p>If you want to help out or discuss reproducible builds in $PROJECTNAME, please join #archlinux-reproducible on freenode.</p>"
	elif [ "$1" = "fedora-23" ] ; then
		local PROJECTNAME="Fedora 23"
		write_page "        <p><em>Reproducible $PROJECTNAME</em> is a (currently somewhat stalled) effort to apply this to $PROJECTNAME, which is rather obvious with 23… <br/> $PROJECTNAME packages are build twice, with a few variations added and then the resulting packages from the two builds are compared using <a href=\"https://tracker.debian.org/diffoscope\">diffoscope</a>. Please note that the toolchain is not varied at all as the rebuild happens on exactly the same system. More variations are expected to be seen in the wild.</p>"
	fi
	if [ "$1" != "Arch Linux" ] && [ "$1" != "fedora-23" ] ; then
		local SMALLPROJECTNAME="$(echo $PROJECTNAME|tr '[:upper:]' '[:lower:]')"
		write_page "       <p>There is a weekly run <a href=\"https://jenkins.debian.net/view/reproducible/job/reproducible_$SMALLPROJECTNAME/\">jenkins job</a> to test the <code>$BRANCH</code> branch of <a href=\"$PROJECTURL\">$PROJECTNAME.git</a>. The jenkins job is running <a href=\"https://salsa.debian.org/qa/jenkins.debian.net/tree/master/bin/reproducible_$SMALLPROJECTNAME.sh\">reproducible_$SMALLPROJECTNAME.sh</a>$BUILD_ENVIRONMENT and this script is solely responsible for creating this page. Feel invited to join <code>#reproducible-builds</code> (on irc.oftc.net) to request job runs whenever sensible. Patches and other <a href=\"mailto:reproducible-builds@lists.alioth.debian.org\">feedback</a> are very much appreciated - if you want to help, please start by looking at the <a href=\"https://jenkins.debian.net/userContent/todo.html#_reproducible_$(echo $1|tr '[:upper:]' '[:lower:]')\">ToDo list for $1</a>, you might find something easy to contribute."
		write_page "       <br />Thanks to <a href=\"https://www.profitbricks.co.uk\">Profitbricks</a> for donating the virtual machines this is running on!</p>"
	elif [ "$1" = "fedora-23" ] ; then
		write_page "       <p><img src=\"/userContent/static/weather-storm.png\"> TODO: explain $PROJECTNAME test setup here.</p>"
	fi
}

write_page_footer() {
	if [ "$1" = "coreboot" ] ; then
		other_distro_details='The <a href=\"http://www.coreboot.org\">Coreboot</a> logo is Copyright © 2008 by Konsult Stuge and coresystems GmbH and can freely be used to refer to the Coreboot project.'
	elif [ "$1" = "NetBSD" ] ; then
		other_distro_details="NetBSD® is a registered trademark of The NetBSD Foundation, Inc."
	elif [ "$1" = "FreeBSD" ] ; then
		other_distro_details="FreeBSD is a registered trademark of The FreeBSD Foundation. The FreeBSD logo and The Power to Serve are trademarks of The FreeBSD Foundation."
	elif [ "$1" = "Arch Linux" ] ; then
		other_distro_details='The <a href=\"https://www.archlinux.org\">Arch Linux</a> name and logo are recognized trademarks. Some rights reserved. The registered trademark Linux® is used pursuant to a sublicense from LMI, the exclusive licensee of Linus Torvalds, owner of the mark on a world-wide basis.'
	elif [ "$1" = "fedora-23" ] ; then
			other_distro_details="Fedora is sponsored by Red Hat. © 2017 Red Hat, Inc. and others."
	else
		other_distro_details=''
	fi
	now=$(date +'%Y-%m-%d %H:%M %Z')

	# The context for pystache3 CLI must be json
	context=$(printf '{
		"job_url" : "%s",
		"job_name" : "%s",
		"date" : "%s",
		"other_distro_details" : "%s"
	}' "${JOB_URL:-""}" "${JOB_NAME:-""}" "$now" "$other_distro_details")

	write_page "$(pystache3 $PAGE_FOOTER_TEMPLATE "$context")"
	write_page "</div>"
	write_page "</body></html>"
 }

write_variation_table() {
	write_page "<p style=\"clear:both;\">"
	if [ "$1" = "fedora-23" ] ; then
		write_page "There are no variations introduced in the $1 builds yet. Stay tuned.</p>"
		return
	fi
	write_page "<table class=\"main\" id=\"variation\"><tr><th>variation</th><th width=\"40%\">first build</th><th width=\"40%\">second build</th></tr>"
	if [ "$1" = "debian" ] ; then
		write_page "<tr><td>hostname</td><td>one of:"
		for a in ${ARCHS} ; do
			local COMMA=""
			local ARCH_NODES=""
			write_page "<br />&nbsp;&nbsp;"
			for i in $(echo $BUILD_NODES | sed -s 's# #\n#g' | sort -u) ; do
				if [ "$(echo $i | grep $a)" ] ; then
					echo -n "$COMMA ${ARCH_NODES}$(echo $i | cut -d '.' -f1 | sed -s 's# ##g')" >> $PAGE
					if [ -z $COMMA ] ; then
						COMMA=","
					fi
				fi
			done
		done
		write_page "</td><td>i-capture-the-hostname</td></tr>"
		write_page "<tr><td>domainname</td><td>$(hostname -d)</td><td>i-capture-the-domainname</td></tr>"
	else
		if [ "$1" != "Arch Linux" ] || [ "$1" != "OpenWrt" ] ; then
			write_page "<tr><td>hostname</td><td> osuosl-build169-amd64 or osuosl-build170-amd64</td><td>the other one</td></tr>"
		else
			write_page "<tr><td>hostname</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		fi
		write_page "<tr><td>domainname</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
	fi
	if [ "$1" != "FreeBSD" ] && [ "$1" != "Arch Linux" ] && [ "$1" != "fedora-23" ] ; then
		write_page "<tr><td>env CAPTURE_ENVIRONMENT</td><td><em>not set</em></td><td>CAPTURE_ENVIRONMENT=\"I capture the environment\"</td></tr>"
	fi
	write_page "<tr><td>env TZ</td><td>TZ=\"/usr/share/zoneinfo/Etc/GMT+12\"</td><td>TZ=\"/usr/share/zoneinfo/Etc/GMT-14\"</td></tr>"
	if [ "$1" = "debian" ]  ; then
		write_page "<tr><td>env LANG</td><td>LANG=\"C\"</td><td>on amd64: LANG=\"fr_CH.UTF-8\"<br />on i386: LANG=\"de_CH.UTF-8\"<br />on arm64: LANG=\"nl_BE.UTF-8\"<br />on armhf: LANG=\"it_CH.UTF-8\"</td></tr>"
		write_page "<tr><td>env LANGUAGE</td><td>LANGUAGE=\"en_US:en\"</td><td>on amd64: LANGUAGE=\"fr_CH:fr\"<br />on i386: LANGUAGE=\"de_CH:de\"<br />on arm64: LANGUAGE=\"nl_BE:nl\"<br />on armhf: LANGUAGE=\"it_CH:it\"</td></tr>"
		write_page "<tr><td>env LC_ALL</td><td><em>not set</em></td><td>on amd64: LC_ALL=\"fr_CH.UTF-8\"<br />on i386: LC_ALL=\"de_CH.UTF-8\"<br />on arm64: LC_ALL=\"nl_BE.UTF-8\"<br />on armhf: LC_ALL=\"it_CH.UTF-8\"</td></tr>"
	elif [ "$1" = "Arch Linux" ]  ; then
		write_page "<tr><td>env LANG</td><td><em>LANG=\"en_US.UTF-8\"</em></td><td>LANG=\"fr_CH.UTF-8\"</td></tr>"
		write_page "<tr><td>env LC_ALL</td><td><em>LANG=\"en_US.UTF-8\"</em></td><td>LC_ALL=\"fr_CH.UTF-8\"</td></tr>"
		write_page "<tr><td>the build path</td><td colspan=\"2\">is not yet varied between rebuilds of Arch Linux</td></tr>"
	else
		write_page "<tr><td>env LANG</td><td>LANG=\"en_GB.UTF-8\"</td><td>LANG=\"fr_CH.UTF-8\"</td></tr>"
		write_page "<tr><td>env LC_ALL</td><td><em>not set</em></td><td>LC_ALL=\"fr_CH.UTF-8\"</td></tr>"
	fi
	if [ "$1" != "FreeBSD" ] && [ "$1" != "Arch Linux" ]  ; then
		write_page "<tr><td>env PATH</td><td>PATH=\"/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:\"</td><td>PATH=\"/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/i/capture/the/path\"</td></tr>"
	elif [ "$1" = "Arch Linux" ]  ; then
		write_page "<tr><td>env PATH</td><td colspan=\"2\">is set to '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' because that's what <i>makechrootpkg</i> is using</td>"
	else
		write_page "<tr><td>env PATH</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
	fi
	if [ "$1" = "debian" ] ; then
		write_page "<tr><td>env BUILDUSERID</td><td>BUILDUSERID=\"1111\"</td><td>BUILDUSERID=\"2222\"</td></tr>"
		write_page "<tr><td>env BUILDUSERNAME</td><td>BUILDUSERNAME=\"pbuilder1\"</td><td>BUILDUSERNAME=\"pbuilder2\"</td></tr>"
		write_page "<tr><td>env USER</td><td>USER=\"pbuilder1\"</td><td>USER=\"pbuilder2\"</td></tr>"
		write_page "<tr><td>env HOME</td><td>HOME=\"/nonexistent/first-build\"</td><td>HOME=\"/nonexistent/second-build\"</td></tr>"
		write_page "<tr><td>niceness</td><td>10</td><td>11</td></tr>"
		write_page "<tr><td>uid</td><td>uid=1111</td><td>uid=2222</td></tr>"
		write_page "<tr><td>gid</td><td>gid=1111</td><td>gid=2222</td></tr>"
		write_page "<tr><td>/bin/sh</td><td>/bin/dash</td><td>/bin/bash</td></tr>"
		write_page "<tr><td><em><a href=\"https://wiki.debian.org/UsrMerge\">usrmerge</a></em> package installed</td><td>no</td><td>yes</td></tr>"
		write_page "<tr><td>build path</td><td>/build/1st/\$pkg-\$ver <em>(not varied for stretch/buster)</em></td><td>/build/2/\$pkg-\$ver/2nd <em>(not varied for stretch/buster)</em></td></tr>"
		write_page "<tr><td>user's login shell</td><td>/bin/sh</td><td>/bin/bash</td></tr>"
		write_page "<tr><td>user's <a href="https://en.wikipedia.org/wiki/Gecos_field">GECOS</a></td><td>first user,first room,first work-phone,first home-phone,first other</td><td>second user,second room,second work-phone,second home-phone,second other</td></tr>"
		write_page "<tr><td>env DEB_BUILD_OPTIONS</td><td>DEB_BUILD_OPTIONS=\"parallel=XXX\"<br />&nbsp;&nbsp;XXX on amd64: 16 or 15<br />&nbsp;&nbsp;XXX on i386: 10 or 9<br />&nbsp;&nbsp;XXX on armhf: 8, 4 or 2</td><td>DEB_BUILD_OPTIONS=\"parallel=YYY\"<br />&nbsp;&nbsp;YYY on amd64: 16 or 15 (!= the first build)<br />&nbsp;&nbsp;YYY on i386: 10 or 9 (!= the first build)<br />&nbsp;&nbsp;YYY is the same as XXX on arm64<br />&nbsp;&nbsp;YYY on armhf: 8, 4, or 2 (not varied systematically)</td></tr>"
		write_page "<tr><td>UTS namespace</td><td><em>shared with the host</em></td><td><em>modified using</em> /usr/bin/unshare --uts</td></tr>"
	elif [ "$1" = "Arch Linux" ]  ; then
		write_page "<tr><td>env USER</td><td>jenkins</td><td>build 2</td></tr>"
		write_page "<tr><td>user/uid</td><td>jenkins/103</td><td>build2/1235</td></tr>"
		write_page "<tr><td>group/gid</td><td>jenkins/105</td><td>build2/1235</td></tr>"
	else
		write_page "<tr><td>env USER</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		write_page "<tr><td>uid</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		write_page "<tr><td>gid</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		if [ "$1" != "FreeBSD" ] ; then
			write_page "<tr><td>UTS namespace</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		fi
	fi
	if [ "$1" != "FreeBSD" ] ; then
		if [ "$1" = "debian" ] ; then
			write_page "<tr><td>kernel version</td></td><td>"
			for a in ${ARCHS} ; do
				write_page "<br />on $a one of:"
				write_page "$(cat /srv/reproducible-results/node-information/*$a* | grep KERNEL | cut -d '=' -f2- | sort -u | tr '\n' '\0' | xargs -0 -n1 echo '<br />&nbsp;&nbsp;')"
			done
			write_page "</td>"
			write_page "<td>on amd64 systematically varied, on armhf not systematically, on i386 and arm64 not at all<br />"
			for a in ${ARCHS} ; do
				write_page "<br />on $a one of:"
				write_page "$(cat /srv/reproducible-results/node-information/*$a* | grep KERNEL | cut -d '=' -f2- | sort -u | tr '\n' '\0' | xargs -0 -n1 echo '<br />&nbsp;&nbsp;')"
			done
			write_page "</td></tr>"
		elif [ "$1" != "Arch Linux" ]  ; then
			write_page "<tr><td>kernel version, modified using /usr/bin/linux64 --uname-2.6</td><td>$(uname -sr)</td><td>$(/usr/bin/linux64 --uname-2.6 uname -sr)</td></tr>"
		else
			write_page "<tr><td>kernel version</td>"
			write_page "$(cat /srv/reproducible-results/node-information/osuosl-build169* | grep KERNEL | cut -d '=' -f2- | sort -u | tr '\n' '\0' | xargs -0 -n1 echo '<br />&nbsp;&nbsp;')"
			write_page "<td colspan=\"2\"> is currently not varied between rebuilds of $1.</td></tr>"
		fi
		if [ "$1" != "OpenWrt" ] ; then
			write_page "<tr><td>umask</td><td>0022<td>0002</td></tr>"
		else
			write_page "<tr><td>umask</td><td colspan=\"2\">is always set to 0022 by the OpenWrt build system.</td></tr>"
		fi
	else
		write_page "<tr><td>FreeBSD kernel version</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		write_page "<tr><td>umask</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td><tr>"
	fi
	local TODAY=$(date +'%Y-%m-%d')
	local FUTURE=$(date --date="${TODAY}+398 days" +'%Y-%m-%d')
	if [ "$1" = "debian" ] ; then
		write_page "<tr><td>CPU type</td><td>one of: $(cat /srv/reproducible-results/node-information/* | grep CPU_MODEL | cut -d '=' -f2- | sort -u | tr '\n' '\0' | xargs -0 -n1 echo '<br />&nbsp;&nbsp;')</td><td>on i386: systematically varied (AMD or Intel CPU with different names & features)<br />on amd64: same for both builds<br />on arm64: always the same<br />on armhf: sometimes varied (depending on the build job), but only the minor CPU revision</td></tr>"
		write_page "<tr><td>year, month, date</td><td>today (${TODAY}) or (on amd64, i386 and arm64 only) also: $FUTURE</td><td>on amd64, i386 and arm64: varied (398 days difference)<br />on armhf: same for both builds (currently, work in progress)</td></tr>"
	else
		write_page "<tr><td>CPU type</td><td>$(cat /proc/cpuinfo|grep 'model name'|head -1|cut -d ":" -f2-)</td><td>same for both builds</td></tr>"
		if [ "$1" = "Arch Linux" ]; then
			write_page "<tr><td>/bin/sh</td><td>/bin/dash</td><td>/bin/bash</td></tr>"
		else
			write_page "<tr><td>/bin/sh</td><td colspan=\"2\"> is not yet varied between rebuilds of $1.</td></tr>"
		fi
		if [ "$1" != "FreeBSD" ] && [ "$1" != "Arch Linux" ] ; then
			write_page "<tr><td>year, month, date</td><td>today (${TODAY})</td><td>same for both builds (currently, work in progress)</td></tr>"
		elif [ "$1" = "Arch Linux" ] ; then
			write_page "<tr><td>year, month, date</td><td>osuosl-build169-amd64: today (${TODAY}) or osuosl-build170-amd64: 398 days in the future ($FUTURE)</td><td>the other one</td></tr>"
		else
			write_page "<tr><td>year, month, date</td><td>osuosl-build171-amd64: today (${TODAY}) or osuosl-build172-amd64: 398 days in the future ($FUTURE)</td><td>the other one</td></tr>"
		fi
	fi
	if [ "$1" != "FreeBSD" ] ; then
		if [ "$1" = "debian" ] ; then
			write_page "<tr><td>hour, minute</td><td>at least the minute will probably vary between two builds anyway...</td><td>on amd64, i386 and arm64 the \"future builds\" additionally run 6h and 23min ahead</td></tr>"
		        write_page "<tr><td>filesystem</td><td>tmpfs</td><td><em>temporarily not</em> varied using <a href=\"https://tracker.debian.org/disorderfs\">disorderfs</a> (<a href=\"https://sources.debian.org/src/disorderfs/sid/disorderfs.1.txt/\">manpage</a>)</td></tr>"
		else
			write_page "<tr><td>hour, minute</td><td>hour and minute will probably vary between two builds...</td><td>the future system actually runs 398 days, 6 hours and 23 minutes ahead...</td></tr>"
			write_page "<tr><td>Filesystem</td><td>tmpfs</td><td>same for both builds (currently, this could be varied using <a href=\"https://tracker.debian.org/disorderfs\">disorderfs</a>)</td></tr>"
		fi
	else
		write_page "<tr><td>year, month, date</td><td>today ($TODAY)</td><td>the 2nd build is done with the build node set 1 year, 1 month and 1 day in the future</td></tr>"
		write_page "<tr><td>hour, minute</td><td>hour and minute will vary between two builds</td><td>additionally the \"future build\" also runs 6h and 23min ahead</td></tr>"
		write_page "<tr><td>filesystem of the build directory</td><td>ufs</td><td>same for both builds</td></tr>"
	fi
	if [ "$1" = "debian" ] ; then
		write_page "<tr><td><em>everything else...</em></td><td colspan=\"2\">is likely the same. So far, this is just about the <em>potential</em> of <a href=\"https://wiki.debian.org/ReproducibleBuilds\">reproducible builds of Debian</a> - there will be more variations in the wild.</td></tr>"
	else
		write_page "<tr><td><em>everything else...</em></td><td colspan=\"2\">is likely the same. There will be more variations in the wild.</td></tr>"
	fi
	write_page "</table></p>"
}

publish_page() {
	if [ "$1" = "" ] ; then
		TARGET=$PAGE
	else
		TARGET=$1/$PAGE
	fi
	echo "$(date -u) - $(cp -v $PAGE $BASE/$TARGET)"
	rm $PAGE
	echo "$(date -u) - enjoy $REPRODUCIBLE_URL/$TARGET"
}

gen_package_html() {
	cd /srv/jenkins/bin
	python3 -c "import reproducible_html_packages as rep
from rblib.models import Package
pkg = Package('$1', no_notes=True)
rep.gen_packages_html([pkg], no_clean=True)" || echo "Warning: cannot update HTML pages for $1"
	cd - > /dev/null
}

calculate_build_duration() {
	END=$(date +'%s')
	DURATION=$(( $END - $START ))
}

print_out_duration() {
	if [ -z "$DURATION" ]; then
		return
	fi
	local HOUR=$(echo "$DURATION/3600"|bc)
	local MIN=$(echo "($DURATION-$HOUR*3600)/60"|bc)
	local SEC=$(echo "$DURATION-$HOUR*3600-$MIN*60"|bc)
	echo "$(date -u) - total duration: ${HOUR}h ${MIN}m ${SEC}s." | tee -a ${RBUILDLOG}
}

irc_message() {
	local CHANNEL="$1"
	shift
	local MESSAGE="$@"
	echo "Sending '$MESSAGE' to $CHANNEL now."
	kgb-client --conf /srv/jenkins/kgb/$CHANNEL.conf --relay-msg "$MESSAGE" || echo "$(date -u) - couldn't send message to $CHANNEL, continuing anyway." # don't fail the whole job
}

call_diffoscope() {
	mkdir -p $TMPDIR/$1/$(dirname $2)
	local TMPLOG=(mktemp --tmpdir=$TMPDIR)
	local msg=""
	set +e
	# remember to also modify the retry diffoscope call 15 lines below
	( ulimit -v "$DIFFOSCOPE_VIRT_LIMIT"
	  timeout "$TIMEOUT" nice schroot \
		--directory $TMPDIR \
		-c source:jenkins-reproducible-${DBDSUITE}-diffoscope \
		diffoscope -- \
			--html $TMPDIR/$1/$2.html \
			$TMPDIR/b1/$1/$2 \
			$TMPDIR/b2/$1/$2 2>&1 \
	) 2>&1 >> $TMPLOG
	RESULT=$?
	LOG_RESULT=$(grep '^E: 15binfmt: update-binfmts: unable to open' $TMPLOG || true)
	if [ ! -z "$LOG_RESULT" ] ; then
		rm -f $TMPLOG $TMPDIR/$1/$2.html
		echo "$(date -u) - schroot jenkins-reproducible-${DBDSUITE}-diffoscope not available, will sleep 2min and retry."
		sleep 2m
		# remember to also modify the retry diffoscope call 15 lines above
		( ulimit -v "$DIFFOSCOPE_VIRT_LIMIT"
		  timeout "$TIMEOUT" nice schroot \
			--directory $TMPDIR \
			-c source:jenkins-reproducible-${DBDSUITE}-diffoscope \
			diffoscope -- \
				--html $TMPDIR/$1/$2.html \
				$TMPDIR/b1/$1/$2 \
				$TMPDIR/b2/$1/$2 2>&1 \
			) 2>&1 >> $TMPLOG
		RESULT=$?
	fi
	if ! "$DEBUG" ; then set +x ; fi
	set -e
	cat $TMPLOG # print dbd output
	rm -f $TMPLOG
	case $RESULT in
		0)	echo "$(date -u) - $1/$2 is reproducible, yay!"
			;;
		1)
			echo "$(date -u) - $DIFFOSCOPE found issues, please investigate $1/$2"
			;;
		2)
			msg="$(date -u) - $DIFFOSCOPE had trouble comparing the two builds. Please investigate $1/$2"
			;;
		124)
			if [ ! -s $TMPDIR/$1.html ] ; then
				msg="$(date -u) - $DIFFOSCOPE produced no output for $1/$2 and was killed after running into timeout after ${TIMEOUT}..."
			else
				msg="$DIFFOSCOPE was killed after running into timeout after $TIMEOUT, but there is still $TMPDIR/$1/$2.html"
			fi
			;;
		*)
			# Process killed by signal exits with 128+${signal number}.
			# 31 = SIGSYS = maximum signal number in signal(7)
			if (( $RESULT > 128 )) && (( $RESULT <= 128+31 )); then
				RESULT="$RESULT (SIG$(kill -l $(($RESULT - 128))))"
			fi
			msg="$(date -u) - Something weird happened, $DIFFOSCOPE on $1/$2 exited with $RESULT and I don't know how to handle it."
			;;
	esac
	if [ ! -z "$msg" ] ; then
		echo $msg | tee -a $TMPDIR/$1/$2.html
	fi
}

get_filesize() {
		local BYTESIZE="$(du -h -b $1 | cut -f1)"
		# numbers below 16384K are understood and more meaningful than 16M...
		if [ $BYTESIZE -gt 16777216 ] ; then
			SIZE="$(echo $BYTESIZE/1048576|bc)M"
		elif [ $BYTESIZE -gt 1024 ] ; then
			SIZE="$(echo $BYTESIZE/1024|bc)K"
		else
			SIZE="$BYTESIZE bytes"
		fi
}

cleanup_pkg_files() {
	rm -vf $DEBIAN_BASE/rbuild/${SUITE}/${ARCH}/${SRCPACKAGE}_*.rbuild.log{,.gz}
	rm -vf $DEBIAN_BASE/logs/${SUITE}/${ARCH}/${SRCPACKAGE}_*.build?.log{,.gz}
	rm -vf $DEBIAN_BASE/dbd/${SUITE}/${ARCH}/${SRCPACKAGE}_*.diffoscope.html
	rm -vf $DEBIAN_BASE/dbdtxt/${SUITE}/${ARCH}/${SRCPACKAGE}_*.diffoscope.txt{,.gz}
	rm -vf $DEBIAN_BASE/dbdjson/${SUITE}/${ARCH}/${SRCPACKAGE}_*.diffoscope.json{,.gz}
	rm -vf $DEBIAN_BASE/buildinfo/${SUITE}/${ARCH}/${SRCPACKAGE}_*.buildinfo
	rm -vf $DEBIAN_BASE/logdiffs/${SUITE}/${ARCH}/${SRCPACKAGE}_*.diff{,.gz}
}

handle_race_condition() {
	local RESULT=$(query_db "SELECT job FROM schedule WHERE package_id='$SRCPKGID'")
	local msg="Package ${SRCPACKAGE} (id=$SRCPKGID) in ${SUITE} on ${ARCH} is probably already building at $RESULT, while this is $BUILD_URL.\n"
	log_warning "$msg"
	printf "$(date -u) - $msg" >> /var/log/jenkins/reproducible-race-conditions.log
	log_warning "Terminating this build quickly and nicely..."
	if [ $SAVE_ARTIFACTS -eq 1 ] ; then
		SAVE_ARTIFACTS=0
		if [ ! -z "$NOTIFY" ] ; then NOTIFY="failure" ; fi
	fi
	exit 0
}

unregister_build() {
	# unregister this build so it will immeditiatly tried again
	if [ -n "$SRCPKGID" ] ; then
		query_db "UPDATE schedule SET date_build_started = NULL, job = NULL WHERE package_id=$SRCPKGID"
	fi
	NOTIFY=""
}

handle_remote_error() {
	MESSAGE="${BUILD_URL}console.log got remote error $1"
	echo "$(date -u ) - $MESSAGE" | tee -a /var/log/jenkins/reproducible-remote-error.log
	echo "Sleeping 5m before aborting the job."
	sleep 5m
	exit 0
}

#
# create the png (and query the db to populate a csv file...) for Debian
#
create_debian_png_from_table() {
	echo "Checking whether to update $2..."
	# $1 = id of the stats table
	# $2 = image file name
	echo "${FIELDS[$1]}" > ${TABLE[$1]}.csv
	# prepare query
	WHERE_EXTRA="WHERE suite = '$SUITE'"
	if [ "$ARCH" = "armhf" ] ; then
		# armhf was only build since 2015-08-30
		WHERE2_EXTRA="WHERE s.datum >= '2015-08-30'"
	elif [ "$ARCH" = "i386" ] ; then
		# i386 was only build since 2016-03-28
		WHERE2_EXTRA="WHERE s.datum >= '2016-03-28'"
	elif [ "$ARCH" = "arm64" ] ; then
		# arm63 was only build since 2016-12-23
		WHERE2_EXTRA="WHERE s.datum >= '2016-12-23'"
	else
		WHERE2_EXTRA=""
	fi
	if [ $1 -eq 3 ] || [ $1 -eq 4 ] || [ $1 -eq 5 ] || [ $1 -eq 8 ] ; then
		# TABLE[3+4+5] don't have a suite column: (and TABLE[8] (and 9) is faked, based on 3)
		WHERE_EXTRA=""
	fi
	if [ $1 -eq 0 ] || [ $1 -eq 2 ] ; then
		# TABLE[0+2] have a architecture column:
		WHERE_EXTRA="$WHERE_EXTRA AND architecture = '$ARCH'"
		if [ "$ARCH" = "armhf" ]  ; then
			if [ $1 -eq 2 ] ; then
				# unstable/armhf was only build since 2015-08-30 (and experimental/armhf since 2015-12-19 and stretch/armhf since 2016-01-01)
				WHERE_EXTRA="$WHERE_EXTRA AND datum >= '2015-08-30'"
			fi
		elif [ "$ARCH" = "i386" ]  ; then
			if [ $1 -eq 2 ] ; then
				# i386 was only build since 2016-03-28
				WHERE_EXTRA="$WHERE_EXTRA AND datum >= '2016-03-28'"
			fi
		elif [ "$ARCH" = "arm64" ]  ; then
			if [ $1 -eq 2 ] ; then
				# arm64 was only build since 2016-12-23
				WHERE_EXTRA="$WHERE_EXTRA AND datum >= '2016-12-23'"
			fi
		fi
		# stretch/amd64 was only build since...
		# WHERE2_EXTRA="WHERE s.datum >= '2015-03-08'"
		# experimental/amd64 was only build since...
		# WHERE2_EXTRA="WHERE s.datum >= '2015-02-28'"
	fi
	# run query
	if [ $1 -eq 1 ] ; then
		# not sure if it's worth to generate the following query...
		WHERE_EXTRA="AND architecture='$ARCH'"

		# This query became much more obnoxious when gaining
		# compatibility with postgres
		query_to_csv "SELECT stats.datum,
			 COALESCE(reproducible_stretch,0) AS reproducible_stretch,
			 COALESCE(reproducible_bullseye,0) AS reproducible_bullseye,
			 COALESCE(reproducible_buster,0) AS reproducible_buster,
			 COALESCE(reproducible_unstable,0) AS reproducible_unstable,
			 COALESCE(reproducible_experimental,0) AS reproducible_experimental,
			 COALESCE(FTBR_stretch,0) AS FTBR_stretch,
			 COALESCE(FTBR_buster,0) AS FTBR_buster,
			 COALESCE(FTBR_bullseye,0) AS FTBR_bullseye,
			 COALESCE(FTBR_unstable,0) AS FTBR_unstable,
			 COALESCE(FTBR_experimental,0) AS FTBR_experimental,
			 COALESCE(FTBFS_stretch,0) AS FTBFS_stretch,
			 COALESCE(FTBFS_buster,0) AS FTBFS_buster,
			 COALESCE(FTBFS_bullseye,0) AS FTBFS_bullseye,
			 COALESCE(FTBFS_unstable,0) AS FTBFS_unstable,
			 COALESCE(FTBFS_experimental,0) AS FTBFS_experimental,
			 COALESCE(other_stretch,0) AS other_stretch,
			 COALESCE(other_buster,0) AS other_buster,
			 COALESCE(other_bullseye,0) AS other_bullseye,
			 COALESCE(other_unstable,0) AS other_unstable,
			 COALESCE(other_experimental,0) AS other_experimental
			FROM (SELECT s.datum,
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e WHERE s.datum=e.datum AND suite='stretch' $WHERE_EXTRA),0) AS reproducible_stretch,
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e WHERE s.datum=e.datum AND suite='buster' $WHERE_EXTRA),0) AS reproducible_buster,
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e WHERE s.datum=e.datum AND suite='bullseye' $WHERE_EXTRA),0) AS reproducible_bullseye,
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e WHERE s.datum=e.datum AND suite='unstable' $WHERE_EXTRA),0) AS reproducible_unstable,
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e WHERE s.datum=e.datum AND suite='experimental' $WHERE_EXTRA),0) AS reproducible_experimental,
			 (SELECT e.FTBR FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='stretch' $WHERE_EXTRA) AS FTBR_stretch,
			 (SELECT e.FTBR FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='buster' $WHERE_EXTRA) AS FTBR_buster,
			 (SELECT e.FTBR FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='bullseye' $WHERE_EXTRA) AS FTBR_bullseye,
			 (SELECT e.FTBR FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='unstable' $WHERE_EXTRA) AS FTBR_unstable,
			 (SELECT e.FTBR FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental' $WHERE_EXTRA) AS FTBR_experimental,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='stretch' $WHERE_EXTRA) AS FTBFS_stretch,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='buster' $WHERE_EXTRA) AS FTBFS_buster,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='bullseye' $WHERE_EXTRA) AS FTBFS_bullseye,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='unstable' $WHERE_EXTRA) AS FTBFS_unstable,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental' $WHERE_EXTRA) AS FTBFS_experimental,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='stretch' $WHERE_EXTRA) AS other_stretch,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='buster' $WHERE_EXTRA) AS other_buster,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='bullseye' $WHERE_EXTRA) AS other_bullseye,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='unstable' $WHERE_EXTRA) AS other_unstable,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental' $WHERE_EXTRA) AS other_experimental
			 FROM stats_builds_per_day AS s $WHERE2_EXTRA GROUP BY s.datum) as stats
			ORDER BY datum" >> ${TABLE[$1]}.csv
	elif [ $1 -eq 2 ] ; then
		# just make a graph of the oldest reproducible build (ignore FTBFS and FTBR)
		query_to_csv "SELECT datum, oldest_reproducible FROM ${TABLE[$1]} ${WHERE_EXTRA} ORDER BY datum" >> ${TABLE[$1]}.csv
	elif [ $1 -eq 7 ] ; then
		query_to_csv "SELECT datum, $SUM_DONE, $SUM_OPEN from ${TABLE[3]} ORDER BY datum" >> ${TABLE[$1]}.csv
	elif [ $1 -eq 8 ] ; then
		query_to_csv "SELECT ${FIELDS[$1]} from ${TABLE[3]} ${WHERE_EXTRA} ORDER BY datum" >> ${TABLE[$1]}.csv
	elif [ $1 -eq 9 ] ; then
		query_to_csv "SELECT datum, $REPRODUCIBLE_DONE, $REPRODUCIBLE_OPEN from ${TABLE[3]} ORDER BY datum" >> ${TABLE[$1]}.csv
	else
		query_to_csv "SELECT ${FIELDS[$1]} from ${TABLE[$1]} ${WHERE_EXTRA} ORDER BY datum" >> ${TABLE[$1]}.csv
	fi
	# this is a gross hack: normally we take the number of colors a table should have...
	#  for the builds_age table we only want one color, but different ones, so this hack:
	COLORS=${COLOR[$1]}
	if [ $1 -eq 2 ] ; then
		case "$SUITE" in
			stretch)	COLORS=40 ;;
			buster)		COLORS=41 ;;
			bullseye)	COLORS=42 ;;
			unstable)	COLORS=43 ;;
			experimental)	COLORS=44 ;;
		esac
	fi
	local WIDTH=1920
	local HEIGHT=960
	# only generate graph if the query returned data
	if [ $(cat ${TABLE[$1]}.csv | wc -l) -gt 1 ] ; then
		echo "Updating $2..."
		DIR=$(dirname $2)
		mkdir -p $DIR
		echo "Generating $2."
		/srv/jenkins/bin/make_graph.py ${TABLE[$1]}.csv $2 ${COLORS} "${MAINLABEL[$1]}" "${YLABEL[$1]}" $WIDTH $HEIGHT
		mv $2 $DEBIAN_BASE/$DIR
		[ "$DIR" = "." ] || rmdir $(dirname $2)
	# create empty dummy png if there havent been any results ever
	elif [ ! -f $DEBIAN_BASE/$DIR/$(basename $2) ] ; then
		DIR=$(dirname $2)
		mkdir -p $DIR
		echo "Creating $2 dummy."
		convert -size 1920x960 xc:#aaaaaa -depth 8 $2
		mv $2 $DEBIAN_BASE/$DIR
		[ "$DIR" = "." ] || rmdir $(dirname $2)
	fi
	rm ${TABLE[$1]}.csv
}

#
# create the png (and query the db to populate a csv file...) for Arch Linux
#
create_archlinux_png_from_table() {
	echo "Checking whether to update $2..."
	# $1 = id of the stats table
	# $2 = image file name
	echo "${FIELDS[$1]}" > ${TABLE[$1]}.csv
	# prepare query
	WHERE_EXTRA="WHERE suite = '$SUITE'"
	if [ $1 -eq 0 ] || [ $1 -eq 2 ] ; then
		# TABLE[0+2] have a architecture column:
		WHERE_EXTRA="$WHERE_EXTRA AND architecture = '$ARCH'"
	fi
	# run query
	if [ $1 -eq 1 ] ; then
		# not sure if it's worth to generate the following query...
		WHERE_EXTRA="AND architecture='$ARCH'"

		# This query became much more obnoxious when gaining
		# compatibility with postgres
		query_to_csv "SELECT stats.datum,
			 COALESCE(reproducible_stretch,0) AS reproducible_stretch,
			 COALESCE(reproducible_buster,0) AS reproducible_buster,
			 COALESCE(reproducible_unstable,0) AS reproducible_unstable,
			 COALESCE(reproducible_experimental,0) AS reproducible_experimental,
			 COALESCE(FTBR_stretch,0) AS FTBR_stretch,
			 COALESCE(FTBR_buster,0) AS FTBR_buster,
			 COALESCE(FTBR_unstable,0) AS FTBR_unstable,
			 COALESCE(FTBR_experimental,0) AS FTBR_experimental,
			 COALESCE(FTBFS_stretch,0) AS FTBFS_stretch,
			 COALESCE(FTBFS_buster,0) AS FTBFS_buster,
			 COALESCE(FTBFS_unstable,0) AS FTBFS_unstable,
			 COALESCE(FTBFS_experimental,0) AS FTBFS_experimental,
			 COALESCE(other_stretch,0) AS other_stretch,
			 COALESCE(other_buster,0) AS other_buster,
			 COALESCE(other_unstable,0) AS other_unstable,
			 COALESCE(other_experimental,0) AS other_experimental
			FROM (SELECT s.datum,
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e WHERE s.datum=e.datum AND suite='stretch' $WHERE_EXTRA),0) AS reproducible_stretch,
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e WHERE s.datum=e.datum AND suite='buster' $WHERE_EXTRA),0) AS reproducible_buster,
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e WHERE s.datum=e.datum AND suite='unstable' $WHERE_EXTRA),0) AS reproducible_unstable,
			 COALESCE((SELECT e.reproducible FROM stats_builds_per_day AS e WHERE s.datum=e.datum AND suite='experimental' $WHERE_EXTRA),0) AS reproducible_experimental,
			 (SELECT e.FTBR FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='stretch' $WHERE_EXTRA) AS FTBR_stretch,
			 (SELECT e.FTBR FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='buster' $WHERE_EXTRA) AS FTBR_buster,
			 (SELECT e.FTBR FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='unstable' $WHERE_EXTRA) AS FTBR_unstable,
			 (SELECT e.FTBR FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental' $WHERE_EXTRA) AS FTBR_experimental,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='stretch' $WHERE_EXTRA) AS FTBFS_stretch,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='buster' $WHERE_EXTRA) AS FTBFS_buster,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='unstable' $WHERE_EXTRA) AS FTBFS_unstable,
			 (SELECT e.FTBFS FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental' $WHERE_EXTRA) AS FTBFS_experimental,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='stretch' $WHERE_EXTRA) AS other_stretch,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='buster' $WHERE_EXTRA) AS other_buster,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='unstable' $WHERE_EXTRA) AS other_unstable,
			 (SELECT e.other FROM stats_builds_per_day e WHERE s.datum=e.datum AND suite='experimental' $WHERE_EXTRA) AS other_experimental
			 FROM stats_builds_per_day AS s GROUP BY s.datum) as stats
			ORDER BY datum" >> ${TABLE[$1]}.csv
	elif [ $1 -eq 2 ] ; then
		# just make a graph of the oldest reproducible build (ignore FTBFS and FTBR)
		query_to_csv "SELECT datum, oldest_reproducible FROM ${TABLE[$1]} ${WHERE_EXTRA} ORDER BY datum" >> ${TABLE[$1]}.csv
	else
		query_to_csv "SELECT ${FIELDS[$1]} from ${TABLE[$1]} ${WHERE_EXTRA} ORDER BY datum" >> ${TABLE[$1]}.csv
	fi
	# this is a gross hack: normally we take the number of colors a table should have...
	#  for the builds_age table we only want one color, but different ones, so this hack:
	COLORS=${COLOR[$1]}
	if [ $1 -eq 2 ] ; then
		case "$SUITE" in
			stretch)	COLORS=40 ;;
			buster)		COLORS=41 ;;
			unstable)	COLORS=42 ;;
			experimental)	COLORS=43 ;;
		esac
	fi
	local WIDTH=1920
	local HEIGHT=960
	# only generate graph if the query returned data
	if [ $(cat ${TABLE[$1]}.csv | wc -l) -gt 1 ] ; then
		echo "Updating $2..."
		DIR=$(dirname $2)
		mkdir -p $DIR
		echo "Generating $2."
		/srv/jenkins/bin/make_graph.py ${TABLE[$1]}.csv $2 ${COLORS} "${MAINLABEL[$1]}" "${YLABEL[$1]}" $WIDTH $HEIGHT
		mv $2 $ARCHBASE/$DIR
		[ "$DIR" = "." ] || rmdir $(dirname $2)
	# create empty dummy png if there havent been any results ever
	elif [ ! -f $ARCHBASE/$DIR/$(basename $2) ] ; then
		DIR=$(dirname $2)
		mkdir -p $DIR
		echo "Creating $2 dummy."
		convert -size 1920x960 xc:#aaaaaa -depth 8 $2
		mv $2 $ARCHBASE/$DIR
		[ "$DIR" = "." ] || rmdir $(dirname $2)
	fi
	rm ${TABLE[$1]}.csv
}


find_in_buildlogs() {
    egrep -q "$1" $ARCHLINUX_PKG_PATH/build1.log $ARCHLINUX_PKG_PATH/build2.log 2>/dev/null
}

include_icon(){
	local STATE=$1
	local TEXT=$2
	local ALT=${STATE%%_*}
	local PNG=
	ALT=${ALT,,}
	case $STATE in
		blacklisted)
			PNG=error;;
		DEPWAIT_*)
			PNG=weather-snow;;
		404_*)
			PNG=weather-severe-alert;;
		FTBFS_*)
			PNG=weather-storm;;
		FTBR_*)
			PNG=weather-showers-scattered ALT=unreproducible ;;
		reproducible)
			PNG=weather-clear ALT=reproducible ;;
	esac
	echo "       <img src=\"/userContent/static/$PNG.png\" alt=\"$ALT icon\" /> $TEXT" >> $HTML_BUFFER
}

create_pkg_html() {
	local ARCHLINUX_PKG_PATH=$ARCHBASE/$REPOSITORY/$SRCPACKAGE
	local HTML_BUFFER=$(mktemp -t archlinuxrb-html-XXXXXXXX)
	local buffer_message
	local STATE

	# clear files from previous builds
	cd "$ARCHLINUX_PKG_PATH"
	for file in build1.log build2.log build1.version build2.version *BUILDINFO.txt *.html; do
		if [ -f $file ] && [ pkg.build_duration -nt $file ] ; then
			rm $file
			echo "$ARCHLINUX_PKG_PATH/$file older than $ARCHLINUX_PKG_PATH/pkg.build_duration, thus deleting it."
		fi
	done

	echo "     <tr>" >> $HTML_BUFFER
	echo "      <td>$REPOSITORY</td>" >> $HTML_BUFFER
	echo "      <td>$SRCPACKAGE</td>" >> $HTML_BUFFER
	echo "      <td>$VERSION</td>" >> $HTML_BUFFER
	echo "      <td>" >> $HTML_BUFFER
	#
	#
	if [ -z "$(cd $ARCHLINUX_PKG_PATH/ ; ls *.pkg.tar.xz.html 2>/dev/null)" ] ; then
		# this horrible if elif elif elif elif...  monster should be replaced
		# by using pacman's exit code which is possible since sometime in 2018

		# check different states and figure out what the page should look like
		if find_in_buildlogs '^error: failed to prepare transaction \(conflicting dependencies\)'; then
			STATE=DEPWAIT_0
			buffer_message='could not resolve dependencies as there are conflicts'
		elif find_in_buildlogs '==> ERROR: (Could not resolve all dependencies|.pacman. failed to install missing dependencies)'; then
			if find_in_buildlogs 'error: failed to init transaction \(unable to lock database\)'; then
				STATE=DEPWAIT_2
				buffer_message='pacman could not lock database'
			else
				STATE=DEPWAIT_1
				buffer_message='could not resolve dependencies'
			fi
		elif find_in_buildlogs '^error: unknown package: '; then
			STATE=404_0
			buffer_message='unknown package'
		elif find_in_buildlogs '(==> ERROR: Failure while downloading|==> ERROR: One or more PGP signatures could not be verified|==> ERROR: One or more files did not pass the validity check|==> ERROR: Integrity checks \(.*\) differ in size from the source array|==> ERROR: Failure while branching|==> ERROR: Failure while creating working copy|Failed to source PKGBUILD.*PKGBUILD)'; then
			REASON="download failed"
			EXTRA_REASON=""
			STATE=404_0
			if find_in_buildlogs 'FAILED \(unknown public key'; then
				STATE=404_6
				EXTRA_REASON="to verify source with PGP due to unknown public key"
			elif find_in_buildlogs 'The requested URL returned error: 403'; then
				STATE=404_2
				EXTRA_REASON="with 403 - forbidden"
			elif find_in_buildlogs 'The requested URL returned error: 500'; then
				STATE=404_4
				EXTRA_REASON="with 500 - internal server error"
			elif find_in_buildlogs 'The requested URL returned error: 503'; then
				STATE=404_5
				EXTRA_REASON="with 503 - service unavailable"
			elif find_in_buildlogs '==> ERROR: One or more PGP signatures could not be verified'; then
				STATE=404_7
				EXTRA_REASON="to verify source with PGP signatures"
			elif find_in_buildlogs '(SSL certificate problem: unable to get local issuer certificate|^bzr: ERROR: .SSL: CERTIFICATE_VERIFY_FAILED)'; then
				STATE=404_1
				EXTRA_REASON="with SSL problem"
			elif find_in_buildlogs '==> ERROR: One or more files did not pass the validity check'; then
				STATE=404_8
				REASON="downloaded ok but failed to verify source"
			elif find_in_buildlogs '==> ERROR: Integrity checks \(.*\) differ in size from the source array'; then
				STATE=404_9
				REASON="Integrity checks differ in size from the source array"
			elif find_in_buildlogs 'The requested URL returned error: 404'; then
				STATE=404_3
				EXTRA_REASON="with 404 - file not found"
			elif find_in_buildlogs 'fatal: the remote end hung up unexpectedly'; then
				STATE=404_A
				EXTRA_REASON="could not clone git repository"
			elif find_in_buildlogs 'The requested URL returned error: 504'; then
				STATE=404_B
				EXTRA_REASON="with 504 - gateway timeout"
			elif find_in_buildlogs '==> ERROR: Failure while downloading .* git repo'; then
				STATE=404_C
				EXTRA_REASON="from git repo"
			fi
			buffer_message="$REASON $EXTRA_REASON"
		elif find_in_buildlogs '==> ERROR: (install file .* does not exist or is not a regular file|The download program wget is not installed)'; then
			STATE=FTBFS_0
			buffer_message='failed to build, requirements not met'
		elif find_in_buildlogs '==> ERROR: A failure occurred in check'; then
			STATE=FTBFS_1
			buffer_message='failed to build while running tests'
		elif find_in_buildlogs '==> ERROR: (An unknown error has occurred|A failure occurred in (build|package|prepare))'; then
			STATE=FTBFS_2
			buffer_message='failed to build'
		elif find_in_buildlogs 'makepkg was killed by timeout after'; then
			STATE=FTBFS_3
			buffer_message='failed to build, killed by timeout'
		elif find_in_buildlogs '==> ERROR: .* contains invalid characters:'; then
			STATE=FTBFS_4
			buffer_message='failed to build, pkg relations contain invalid characters'
		else
			STATE=$(query_db "SELECT r.status FROM results AS r
				JOIN sources as s on s.id=r.package_id
				WHERE s.architecture='x86_64'
				AND s.name='$SRCPACKAGE'
				AND s.suite='archlinux_$REPOSITORY';")
			if [ "$STATE" = "blacklisted" ] ; then
				buffer_message='blacklisted'
			else
				STATE=UNKNOWN
				buffer_message='probably failed to build from source, please investigate'
			fi
		fi
		# print build failures
		if [ "$STATE" = "UNKNOWN" ]; then
			echo "       $buffer_message" >> $HTML_BUFFER
		else
			include_icon $STATE "$buffer_message"
		fi
	else
		local STATE=reproducible
		local SOME_GOOD=false
		for ARTIFACT in $(cd $ARCHLINUX_PKG_PATH/ ; ls *.pkg.tar.xz.html) ; do
			if [ -z "$(echo $ARTIFACT | grep $VERSION)" ] ; then
				echo "deleting $ARTIFACT as version is not $VERSION"
				rm -f $ARTIFACT
				continue
			elif [ ! -z "$(grep 'build reproducible in our test framework' $ARCHLINUX_PKG_PATH/$ARTIFACT)" ] ; then
				SOME_GOOD=true
				include_icon $STATE "<a href=\"/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT\">${ARTIFACT:0:-5}</a> is reproducible in our current test framework<br />"
			else
				# change $STATE unless we have found .buildinfo differences already...
				if [ "$STATE" != "FTBR_0" ] ; then
					STATE=FTBR_1
				fi
				# this shouldnt happen, but (for now) it does, so lets mark them…
				EXTRA_REASON=""
				if [ ! -z "$(grep 'class="source">.BUILDINFO' $ARCHLINUX_PKG_PATH/$ARTIFACT)" ] ; then
					STATE=FTBR_0
					EXTRA_REASON=" with variations in .BUILDINFO"
				fi
				include_icon $STATE "<a href=\"/archlinux/$REPOSITORY/$SRCPACKAGE/$ARTIFACT\">${ARTIFACT:0:-5}</a> is unreproducible$EXTRA_REASON<br />"
			fi
		done
		# we only count source packages…
		if [[ $STATE = FTBR_1 && $SOME_GOOD = true ]]; then
			STATE=FTBR_2
		fi
	fi
	echo "      </td>" >> $HTML_BUFFER
	echo "      <td>$DATE" >> $HTML_BUFFER
	local DURATION=$(cat $ARCHLINUX_PKG_PATH/pkg.build_duration 2>/dev/null || true)
	if [ -n "$DURATION" ]; then
		local HOUR=$(echo "$DURATION/3600"|bc)
		local MIN=$(echo "($DURATION-$HOUR*3600)/60"|bc)
		local SEC=$(echo "$DURATION-$HOUR*3600-$MIN*60"|bc)
		BUILD_DURATION="<br />${HOUR}h:${MIN}m:${SEC}s"
	else
		BUILD_DURATION=" "
	fi
	echo "       $BUILD_DURATION</td>" >> $HTML_BUFFER

	echo "      <td>" >> $HTML_BUFFER
	for LOG in build1.log build2.log ; do
		if [ -f $ARCHLINUX_PKG_PATH/$LOG ] ; then
			if [ "$LOG" = "build2.log" ] ; then
				echo "       <br />" >> $HTML_BUFFER
			fi
			get_filesize $ARCHLINUX_PKG_PATH/$LOG
			echo "       <a href=\"/archlinux/$REPOSITORY/$SRCPACKAGE/$LOG\">$LOG</a> ($SIZE)" >> $HTML_BUFFER
		fi
	done
	echo "      </td>" >> $HTML_BUFFER
	echo "     </tr>" >> $HTML_BUFFER
	mv $HTML_BUFFER $ARCHLINUX_PKG_PATH/pkg.html
	chmod 644 $ARCHLINUX_PKG_PATH/pkg.html
	echo $STATE > $ARCHLINUX_PKG_PATH/pkg.state
}

create_alpine_pkg_html() {
	local ALPINE_PKG_PATH=$ALPINE_BASE/$REPOSITORY/$SRCPACKAGE
	local HTML_BUFFER=$(mktemp -t alpinerb-html-XXXXXXXX)
	local buffer_message
	local STATE

	# clear files from previous builds
	cd "$ALPINE_PKG_PATH"
	for file in build1.log build2.log build1.version build2.version *BUILDINFO.txt *.html; do
		if [ -f $file ] && [ pkg.build_duration -nt $file ] ; then
			rm $file
			echo "$ALPINE_PKG_PATH/$file older than $ALPINE_PKG_PATH/pkg.build_duration, thus deleting it."
		fi
	done

	echo "     <tr>" >> $HTML_BUFFER
	echo "      <td>$REPOSITORY</td>" >> $HTML_BUFFER
	echo "      <td>$SRCPACKAGE</td>" >> $HTML_BUFFER
	echo "      <td>$VERSION</td>" >> $HTML_BUFFER
	echo "      <td>" >> $HTML_BUFFER
	#
	#
	if [ -z "$(cd $ALPINE_PKG_PATH/ ; ls *.apk.html 2>/dev/null)" ] ; then
		# this horrible if elif elif elif elif...  monster should be replaced
		# by using pacman's exit code which is possible since sometime in 2018

		# check different states and figure out what the page should look like
		if find_in_buildlogs '^error: failed to prepare transaction \(conflicting dependencies\)'; then
			STATE=DEPWAIT_0
			buffer_message='could not resolve dependencies as there are conflicts'
		elif find_in_buildlogs '==> ERROR: (Could not resolve all dependencies|.pacman. failed to install missing dependencies)'; then
			if find_in_buildlogs 'error: failed to init transaction \(unable to lock database\)'; then
				STATE=DEPWAIT_2
				buffer_message='pacman could not lock database'
			else
				STATE=DEPWAIT_1
				buffer_message='could not resolve dependencies'
			fi
		elif find_in_buildlogs '^error: unknown package: '; then
			STATE=404_0
			buffer_message='unknown package'
		elif find_in_buildlogs '(==> ERROR: Failure while downloading|==> ERROR: One or more PGP signatures could not be verified|==> ERROR: One or more files did not pass the validity check|==> ERROR: Integrity checks \(.*\) differ in size from the source array|==> ERROR: Failure while branching|==> ERROR: Failure while creating working copy|Failed to source PKGBUILD.*PKGBUILD)'; then
			REASON="download failed"
			EXTRA_REASON=""
			STATE=404_0
			if find_in_buildlogs 'FAILED \(unknown public key'; then
				STATE=404_6
				EXTRA_REASON="to verify source with PGP due to unknown public key"
			elif find_in_buildlogs 'The requested URL returned error: 403'; then
				STATE=404_2
				EXTRA_REASON="with 403 - forbidden"
			elif find_in_buildlogs 'The requested URL returned error: 500'; then
				STATE=404_4
				EXTRA_REASON="with 500 - internal server error"
			elif find_in_buildlogs 'The requested URL returned error: 503'; then
				STATE=404_5
				EXTRA_REASON="with 503 - service unavailable"
			elif find_in_buildlogs '==> ERROR: One or more PGP signatures could not be verified'; then
				STATE=404_7
				EXTRA_REASON="to verify source with PGP signatures"
			elif find_in_buildlogs '(SSL certificate problem: unable to get local issuer certificate|^bzr: ERROR: .SSL: CERTIFICATE_VERIFY_FAILED)'; then
				STATE=404_1
				EXTRA_REASON="with SSL problem"
			elif find_in_buildlogs '==> ERROR: One or more files did not pass the validity check'; then
				STATE=404_8
				REASON="downloaded ok but failed to verify source"
			elif find_in_buildlogs '==> ERROR: Integrity checks \(.*\) differ in size from the source array'; then
				STATE=404_9
				REASON="Integrity checks differ in size from the source array"
			elif find_in_buildlogs 'The requested URL returned error: 404'; then
				STATE=404_3
				EXTRA_REASON="with 404 - file not found"
			elif find_in_buildlogs 'fatal: the remote end hung up unexpectedly'; then
				STATE=404_A
				EXTRA_REASON="could not clone git repository"
			elif find_in_buildlogs 'The requested URL returned error: 504'; then
				STATE=404_B
				EXTRA_REASON="with 504 - gateway timeout"
			elif find_in_buildlogs '==> ERROR: Failure while downloading .* git repo'; then
				STATE=404_C
				EXTRA_REASON="from git repo"
			fi
			buffer_message="$REASON $EXTRA_REASON"
		elif find_in_buildlogs '==> ERROR: (install file .* does not exist or is not a regular file|The download program wget is not installed)'; then
			STATE=FTBFS_0
			buffer_message='failed to build, requirements not met'
		elif find_in_buildlogs '==> ERROR: A failure occurred in check'; then
			STATE=FTBFS_1
			buffer_message='failed to build while running tests'
		elif find_in_buildlogs '==> ERROR: (An unknown error has occurred|A failure occurred in (build|package|prepare))'; then
			STATE=FTBFS_2
			buffer_message='failed to build'
		elif find_in_buildlogs 'makepkg was killed by timeout after'; then
			STATE=FTBFS_3
			buffer_message='failed to build, killed by timeout'
		elif find_in_buildlogs '==> ERROR: .* contains invalid characters:'; then
			STATE=FTBFS_4
			buffer_message='failed to build, pkg relations contain invalid characters'
		else
			STATE=$(query_db "SELECT r.status FROM results AS r
				JOIN sources as s on s.id=r.package_id
				WHERE s.architecture='x86_64'
				AND s.name='$SRCPACKAGE'
				AND s.suite='alpine_$REPOSITORY';")
			if [ "$STATE" = "blacklisted" ] ; then
				buffer_message='blacklisted'
			else
				STATE=UNKNOWN
				buffer_message='probably failed to build from source, please investigate'
			fi
		fi
		# print build failures
		if [ "$STATE" = "UNKNOWN" ]; then
			echo "       $buffer_message" >> $HTML_BUFFER
		else
			include_icon $STATE "$buffer_message"
		fi
	else
		local STATE=reproducible
		local SOME_GOOD=false
		for ARTIFACT in $(cd $ALPINE_PKG_PATH/ ; ls *.apk.html) ; do
			if [ -z "$(echo $ARTIFACT | grep $VERSION)" ] ; then
				echo "deleting $ARTIFACT as version is not $VERSION"
				rm -f $ARTIFACT
				continue
			elif [ ! -z "$(grep 'build reproducible in our test framework' $ALPINE_PKG_PATH/$ARTIFACT)" ] ; then
				SOME_GOOD=true
				include_icon $STATE "<a href=\"/alpine/$REPOSITORY/$SRCPACKAGE/$ARTIFACT\">${ARTIFACT:0:-5}</a> is reproducible in our current test framework<br />"
			else
				# change $STATE unless we have found .buildinfo differences already...
				if [ "$STATE" != "FTBR_0" ] ; then
					STATE=FTBR_1
				fi
				# this shouldnt happen, but (for now) it does, so lets mark them…
				EXTRA_REASON=""
				if [ ! -z "$(grep 'class="source">.BUILDINFO' $ALPINE_PKG_PATH/$ARTIFACT)" ] ; then
					STATE=FTBR_0
					EXTRA_REASON=" with variations in .BUILDINFO"
				fi
				include_icon $STATE "<a href=\"/alpine/$REPOSITORY/$SRCPACKAGE/$ARTIFACT\">${ARTIFACT:0:-5}</a> is unreproducible$EXTRA_REASON<br />"
			fi
		done
		# we only count source packages…
		if [[ $STATE = FTBR_1 && $SOME_GOOD = true ]]; then
			STATE=FTBR_2
		fi
	fi
	echo "      </td>" >> $HTML_BUFFER
	echo "      <td>$DATE" >> $HTML_BUFFER
	local DURATION=$(cat $ALPINE_PKG_PATH/pkg.build_duration 2>/dev/null || true)
	if [ -n "$DURATION" ]; then
		local HOUR=$(echo "$DURATION/3600"|bc)
		local MIN=$(echo "($DURATION-$HOUR*3600)/60"|bc)
		local SEC=$(echo "$DURATION-$HOUR*3600-$MIN*60"|bc)
		BUILD_DURATION="<br />${HOUR}h:${MIN}m:${SEC}s"
	else
		BUILD_DURATION=" "
	fi
	echo "       $BUILD_DURATION</td>" >> $HTML_BUFFER

	echo "      <td>" >> $HTML_BUFFER
	for LOG in build1.log build2.log ; do
		if [ -f $ALPINE_PKG_PATH/$LOG ] ; then
			if [ "$LOG" = "build2.log" ] ; then
				echo "       <br />" >> $HTML_BUFFER
			fi
			get_filesize $ALPINE_PKG_PATH/$LOG
			echo "       <a href=\"/alpine/$REPOSITORY/$SRCPACKAGE/$LOG\">$LOG</a> ($SIZE)" >> $HTML_BUFFER
		fi
	done
	echo "      </td>" >> $HTML_BUFFER
	echo "     </tr>" >> $HTML_BUFFER
	mv $HTML_BUFFER $ALPINE_PKG_PATH/pkg.html
	chmod 644 $ALPINE_PKG_PATH/pkg.html
	echo $STATE > $ALPINE_PKG_PATH/pkg.state
}
