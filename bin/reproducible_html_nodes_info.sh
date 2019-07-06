#!/bin/bash
# vim: set noexpandtab:

# Copyright © 2015-2019 Holger Levsen <holger@layer-acht.org>
#           ©      2018 Mattia Rizzolo <mattia@debian.org>
# released under the GPLv=2

set -e

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

explain_nodes() {
	case $JENKINS_NODENAME in
		jenkins)	;;
		profitbricks7)	write_page "<br /><small>(buildinfos.debian.net)</small>" ;;
		profitbricks9)	write_page "<br /><small>(jenkins.d.n rebootstrap jobs)</small>" ;;
		profitbricks10)	write_page "<br /><small>(jenkins.d.n chroot-installation jobs and http-proxy)</small>" ;;
		osuosl167)	write_page "<br /><small>(http-proxy for osuosl nodes)</small>" ;;
		osuosl168)	write_page "<br /><small>(r-b F-Droid builds)</small>" ;;
		osuosl169)	write_page "<br /><small>(r-b Archlinux builds)</small>" ;;
		osuosl170)	write_page "<br /><small>(r-b Archlinux builds)</small>" ;;
		osuosl171)	write_page "<br /><small>(r-b OpenWrt, NetBSD, Coreboot builds)</small>" ;;
		osuosl172)	write_page "<br /><small>(r-b OpenWrt, Coreboot builds)</small>" ;;
		osuosl173)	write_page "<br /><small>(r-b Debian rebuilder)</small>" ;;
		osuosl174)	write_page "<br /><small>(r-b openSUSE)</small>" ;;
		profitbricks1)	write_page "<br /><small>(r-b Debian builds and http-proxy)</small>" ;;
		codethink16)	write_page "<br /><small>(r-b Debian builds and http-proxy)</small>" ;;
		*)		write_page "<br /><small>(r-b Debian builds)</small>" ;;
	esac
}

build_nodes_health_page() {
	#
	# build node health page
	#
	VIEW=nodes_health
	PAGE=index_${VIEW}.html
	ARCH=amd64
	SUITE=unstable
	echo "$(date -u) - starting to write $PAGE page."
	write_page_header $VIEW "Nodes health overview"
	write_page "<p style=\"clear:both;\">"
	for ARCH in ${ARCHS} ; do
		write_page "<h3>$ARCH nodes</h3>"
		write_page "<table>"
		write_page "<tr><th>Name</th><th>health check</th><th>maintenance</th><th>Debian worker.log links</th>"
			for SUITE in ${SUITES} ; do
				write_page "<th>pbuilder setup $SUITE</th>"
			done
			for SUITE in ${SUITES} ; do
				if [ "$SUITE" = "experimental" ]; then
					continue
				fi
				write_page "<th>schroot setup $SUITE</th>"
			done
		write_page "</tr>"
		# the following for-loop is a hack to insert nodes which are not part of the
		# Debian Reproducible Builds node network but are using for reproducible builds
		# tests of other projects…
		REPRODUCIBLE_NODES="jenkins"

		for NODE in $BUILD_NODES ; do
			REPRODUCIBLE_NODES="$REPRODUCIBLE_NODES $NODE"
			if [ "$NODE" = "profitbricks-build6-i386.debian.net" ] ; then
				# pb9 	rebootstrap jobs
				# pb10	chroot jobs
				REPRODUCIBLE_NODES="$REPRODUCIBLE_NODES profitbricks-build7-amd64.debian.net profitbricks-build9-amd64.debian.net profitbricks-build10-amd64.debian.net"
			fi
		done
		for NODE in $REPRODUCIBLE_NODES ; do
			if [ -z "$(echo $NODE | grep $ARCH || true)" ] && [ "$NODE" != "jenkins" ] ; then
				continue
			elif [ "$NODE" = "jenkins" ] && [ "$ARCH" != "amd64" ] ; then
				continue
			fi
			if [ "$NODE" = "jenkins" ] ; then
				JENKINS_NODENAME=jenkins
				NODE="jenkins.debian.net"
			else
				case $ARCH in
					amd64|i386) 	JENKINS_NODENAME=$(echo $NODE | cut -d "-" -f1-2|sed 's#-build##' ) ;;
					arm64) 		JENKINS_NODENAME=$(echo $NODE | cut -d "-" -f1-2|sed 's#-sled##' ) ;;
					armhf) 		JENKINS_NODENAME=$(echo $NODE | cut -d "-" -f1) ;;
				esac
			fi
			write_page "<tr><td>$JENKINS_NODENAME"
			explain_nodes
			write_page "</td>"
			# health check
			URL="https://jenkins.debian.net/view/reproducible/view/Node_maintenance/job/reproducible_node_health_check_${ARCH}_${JENKINS_NODENAME}"
			BADGE="$URL/badge/icon"
			write_page "<td><a href='$URL'><img src='$BADGE' /></a></td>"
			# maintenance
			URL="https://jenkins.debian.net/view/reproducible/view/Node_maintenance/job/reproducible_maintenance_${ARCH}_${JENKINS_NODENAME}"
			BADGE="$URL/badge/icon"
			write_page "<td><a href='$URL'><img src='$BADGE' /></a></td>"
			# mark offline nodes
			JENKINS_OFFLINE_GIT_LIST=~jenkins-adm/jenkins.debian.net/jenkins-home/offline_nodes
			if [ -f "$JENKINS_OFFLINE_GIT_LIST" ] && ! grep -q "$NODE" "$JENKINS_OFFLINE_GIT_LIST" \
			 && ( [ -f "$JENKINS_OFFLINE_LIST" ] && grep -q "$NODE" "$JENKINS_OFFLINE_LIST" ) ; then
				write_page '</td><td colspan="9" style="text-align: center;"><span style="font-style: italic;">temporarily marked offline by jenkins</span></td>'
				continue
			elif [ -f "$JENKINS_OFFLINE_LIST" ] && grep -q "$NODE" "$JENKINS_OFFLINE_LIST"; then
				write_page '</td><td colspan="9" style="text-align: center;"><span style="font-style: italic;">offline</span></td>'
				continue
			fi
			# worker.log links
			case $JENKINS_NODENAME in
				jenkins)	write_page "<td></td>" ;;
				profitbricks7)	write_page "<td></td>" ;;
				profitbricks9)	write_page "<td></td>" ;;
				profitbricks10)	write_page "<td></td>" ;;
				osuosl*)	write_page "<td></td>" ;;
				*)		write_page "<td>"
						SHORTNAME=$(echo $NODE | cut -d '.' -f1)
						for WORKER in $(grep "${ARCH}_" /srv/jenkins/bin/reproducible_build_service.sh | grep -v \# |grep $SHORTNAME | cut -d ')' -f1) ; do
							write_page "<a href='https://jenkins.debian.net/userContent/reproducible/debian/build_service/${WORKER}/worker.log'>"
							write_page "$(echo $WORKER |cut -d '_' -f2)</a> "
						done
						write_page "</td>"
						;;
			esac
			# pbuilder setup
			for SUITE in ${SUITES} ; do
				case $JENKINS_NODENAME in
					jenkins)	write_page "<td></td>" ;;
					profitbricks7)	write_page "<td></td>" ;;
					profitbricks9)	write_page "<td></td>" ;;
					profitbricks10)	write_page "<td></td>" ;;
					osuosl*)	write_page "<td></td>" ;;
					*)		URL="https://jenkins.debian.net/view/reproducible/view/Debian_setup_${ARCH}/job/reproducible_setup_pbuilder_${SUITE}_${ARCH}_${JENKINS_NODENAME}"
							BADGE="$URL/badge/icon"
							write_page "<td><a href='$URL'><img src='$BADGE' /></a></td>"
							;;
				esac
			done
			# diffoscope schroot setup
			for SUITE in ${SUITES} ; do
				if [ "$SUITE" = "experimental" ]; then
					continue
				fi
				URL="https://jenkins.debian.net/view/reproducible/view/Debian_setup_${ARCH}/job/reproducible_setup_schroot_${SUITE}_diffoscope_${ARCH}_${JENKINS_NODENAME}"
				BADGE="$URL/badge/icon"
				case $JENKINS_NODENAME in
					osuosl171)
						if [ "$SUITE" = "unstable" ]; then
							write_page "<td><a href='$URL'><img src='$BADGE' /></a></td>"
						else
							write_page "<td></td>"
						fi
						;;
					osuosl173)
						if [ "$SUITE" = "buster" ]; then
							write_page "<td><a href='$URL'><img src='$BADGE' /></a></td>"
						else
							write_page "<td></td>"
						fi
						;;
					jenkins)
						write_page "<td><a href='$URL'><img src='$BADGE' /></a></td>"
						;;
					*) write_page "<td></td>" ;;
				esac
			done
			write_page "</tr>"
		done
		write_page "</table>"
	done
	write_page "</p>"
	write_page_footer
	publish_page debian
}

build_graph_overview_pages() {
	#
	# munin nodes daily/weekly/monthly/yearly pages
	#
	for TYPE in daily weekly monthly yearly ; do
		VIEW=nodes_${TYPE}_graphs
		PAGE=index_${VIEW}.html
		ARCH=amd64
		SUITE=unstable
		echo "$(date -u) - starting to write $PAGE page."
		write_page_header $VIEW "Nodes $TYPE graphs"
		write_page "<p style=\"clear:both;\">"
		for ARCH in ${ARCHS} ; do
			write_page "<h3>$ARCH nodes</h3>"
			write_page "<table>"
			write_page "<tr><th>Name</th><th colspan='6'></th>"
			write_page "</tr>"
			for NODE in $REPRODUCIBLE_NODES ; do
				if [ -z "$(echo $NODE | grep $ARCH || true)" ] && [ "$NODE" != "jenkins" ] ; then
					continue
				elif [ "$NODE" = "jenkins" ] && [ "$ARCH" != "amd64" ] ; then
					continue
				fi
				if [ "$NODE" = "jenkins" ] ; then
					JENKINS_NODENAME=jenkins
					NODE="jenkins.debian.net"
				else
					case $ARCH in
						amd64|i386) 	JENKINS_NODENAME=$(echo $NODE | cut -d "-" -f1-2|sed 's#-build##' ) ;;
						arm64) 		JENKINS_NODENAME=$(echo $NODE | cut -d "-" -f1-2|sed 's#-sled##' ) ;;
						armhf) 		JENKINS_NODENAME=$(echo $NODE | cut -d "-" -f1) ;;
					esac
				fi
				write_page "<tr><td>$JENKINS_NODENAME"
				explain_nodes
				write_page "</td>"
				for GRAPH in jenkins_reproducible_builds cpu memory df swap load ; do
					if [ "$GRAPH" = "jenkins_reproducible_builds" ] ; then
						case $JENKINS_NODENAME in
							jenkins)	write_page "<td></td>" ; continue ;;
							profitbricks7)	write_page "<td></td>" ; continue ;;
							profitbricks9)	write_page "<td></td>" ; continue ;;
							profitbricks10)	write_page "<td></td>" ; continue ;;
							osuosl*)	write_page "<td></td>" ; continue ;;
							*)		;;
						esac
					fi
					write_page "<td><a href='https://jenkins.debian.net/munin/debian.net/$NODE/$GRAPH.html'>"
					case "$TYPE" in
						daily)		IMG=day.png ;;
						weekly)		IMG=week.png ;;
						monthly)	IMG=month.png ;;
						yearly)		IMG=year.png ;;
					esac
					write_page "<img src='https://jenkins.debian.net/munin/debian.net/$NODE/${GRAPH}-${IMG}' width='150' /></a></td>"
				done
				write_page "</tr>"
			done
			write_page "</table>"
		done
		write_page "</p>"
		write_page_footer
		publish_page debian
	done
}

build_job_health_page() {
	#
	# job health page
	#
	VIEW=job_health
	PAGE=index_${VIEW}.html
	ARCH=amd64
	SUITE=unstable
	# these are or-filters used with egrep
	FILTER[0]="(builds|spec|lfs)"
	FILTER[1]="html_(all|break|dash|dd|index|live|node|pkg|repo)"
	FILTER[2]="(reproducible_compare|pool)"
	FILTER[3]="reproducible_diffoscope"
	FILTER[4]="(reprotest|strip-nonderminism|disorderfs)"
	FILTER[5]="(json|le_scheduler|meta|le_nodes|rsync|notes)"
	FILTER[6]="archlinux"
	FILTER[7]="coreboot"
	FILTER[8]="(openwrt)"
	FILTER[9]="(le_netbsd|le_freebsd)"
	FILTER[10]="fdroid"
	FILTER[11]="fedora"
	FILTER[11]="alpine"
	echo "$(date -u) - starting to write $PAGE page."
	write_page_header $VIEW "Job health overview"
	write_page "<p style=\"clear:both;\">"
	write_page "<table>"
	for CATEGORY in $(seq 0 10) ; do
		write_page "<tr>"
		for JOB in $(cd ~/jobs ; ls -1d reproducible_* | egrep "${FILTER[$CATEGORY]}" | cut -d '_' -f2- | sort ) ; do
			SHORTNAME="$(echo $JOB \
				| sed 's#archlinux_##' \
				| sed 's#alpine_##' \
				| sed 's#builder_fedora#builder#' \
				| sed 's#_x86_64##' \
				| sed 's#_from_git_master#_git#' \
				| sed 's#setup_schroot_##' \
				| sed 's#setup_mock_fedora-##' \
				| sed 's#create_##' \
				| sed 's#fdroid_build_##' \
				| sed 's#html_archlinux#html#' \
				| sed 's#html_alpine#html#' \
				| sed 's#html_##' \
				| sed 's#builds_##' \
				| sed 's#_diffoscope_amd64##' \
				| sed 's#compare_Debian_##' \
				| sed 's#_#-#g' \
				)"
			write_page "<th>$SHORTNAME</th>"
		done
		write_page "</tr><tr>"
		for JOB in $(cd ~/jobs ; ls -1d reproducible_* | egrep "${FILTER[$CATEGORY]}" | cut -d '_' -f2- | sort ) ; do
			URL="https://jenkins.debian.net/job/reproducible_$JOB"
			BADGE="$URL/badge/icon"
			write_page "<td><a href='$URL'><img src='$BADGE' /></a></td>"
		done
		write_page "</tr>"
	done
	write_page "</table>"
	write_page "</p>"
	write_page_footer
	publish_page debian
}

#
# main
#
PAGE=""
JENKINS_NODENAME=""
build_job_health_page
build_nodes_health_page
build_graph_overview_pages
