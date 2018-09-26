#!/bin/bash
# vim: set noexpandtab:

# Copyright © 2015-2018 Holger Levsen <holger@layer-acht.org>
#           ©      2018 Mattia Rizzolo <mattia@debian.org>
# released under the GPLv=2

set -e

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

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
			if [ "$NODE" = "profitbricks-build2-i386.debian.net" ] ; then
				REPRODUCIBLE_NODES="$REPRODUCIBLE_NODES profitbricks-build3-amd64.debian.net profitbricks-build4-amd64.debian.net profitbricks-build7-amd64.debian.net"
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
			write_page "</td>"
			# health check
			URL="https://jenkins.debian.net/view/reproducible/view/Node_maintenance/job/reproducible_node_health_check_${ARCH}_${JENKINS_NODENAME}"
			BADGE="$URL/badge/icon"
			write_page "<td><a href='$URL'><img src='$BADGE' /></a></td>"
			# mark offline nodes
			if [ -f "$JENKINS_OFFLINE_LIST" ]; then
				if grep -q "$NODE" "$JENKINS_OFFLINE_LIST"; then
					write_page '</td><td colspan="10" style="text-align: center;"><span style="font-style: italic;">offline</span></td>'
					continue
				fi
			fi
			# maintenance
			URL="https://jenkins.debian.net/view/reproducible/view/Node_maintenance/job/reproducible_maintenance_${ARCH}_${JENKINS_NODENAME}"
			BADGE="$URL/badge/icon"
			write_page "<td><a href='$URL'><img src='$BADGE' /></a></td>"
			# worker.log links
			case $JENKINS_NODENAME in
				jenkins)	write_page "<td></td>" ;;
				profitbricks3)	write_page "<td></td>" ;;
				profitbricks4)	write_page "<td></td>" ;;
				profitbricks7)	write_page "<td></td>" ;;
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
					profitbricks3)	write_page "<td></td>" ;;
					profitbricks4)	write_page "<td></td>" ;;
					profitbricks7)	write_page "<td></td>" ;;
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
					profitbricks3)
						if [ "$SUITE" = "unstable" ]; then
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
	# munin nodes daily/weekly pages
	#
	for TYPE in daily weekly ; do
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
				write_page "<tr><td>$JENKINS_NODENAME</td>"
				for GRAPH in jenkins_reproducible_builds cpu memory df swap load ; do
					if [ "$GRAPH" = "jenkins_reproducible_builds" ] ; then
						case $JENKINS_NODENAME in
							jenkins)	write_page "<td></td>" ; continue ;;
							profitbricks3)	write_page "<td></td>" ; continue ;;
							profitbricks4)	write_page "<td></td>" ; continue ;;
							profitbricks7)	write_page "<td></td>" ; continue ;;
							*)		;;
						esac
					fi
					write_page "<td><a href='https://jenkins.debian.net/munin/debian.net/$NODE/$GRAPH.html'>"
					if [ "$TYPE" = "daily" ] ; then
						IMG=day.png
					else
						IMG=week.png
					fi
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
	FILTER[0]="(builds|spec|lfs)"
	FILTER[1]="html_(all|break|dash|dd|index|live|node|pkg|repo)"
	FILTER[2]="le_diffoscope"
	FILTER[3]="(reprotest|strip-nonderminism|disorderfs)"
	FILTER[4]="(json|le_scheduler|meta|le_nodes|rsync|notes)"
	FILTER[5]="archlinux"
	FILTER[6]="coreboot"
	FILTER[7]="(openwrt|lede)"
	FILTER[8]="(le_netbsd|le_freebsd)"
	FILTER[9]="fdroid"
	FILTER[10]="fedora"
	echo "$(date -u) - starting to write $PAGE page."
	write_page_header $VIEW "Job health overview"
	write_page "<p style=\"clear:both;\">"
	write_page "<table>"
	for CATEGORY in $(seq 0 10) ; do
		write_page "<tr>"
		for JOB in $(cd ~/jobs ; ls -1d reproducible_* | egrep "${FILTER[$CATEGORY]}" | cut -d '_' -f2- | sort ) ; do
			SHORTNAME="$(echo $JOB \
				| sed 's#archlinux_##' \
				| sed 's#builder_fedora#builder#' \
				| sed 's#_x86_64##' \
				| sed 's#_from_git_master#_git#' \
				| sed 's#setup_schroot_##' \
				| sed 's#setup_mock_fedora-##' \
				| sed 's#create_##' \
				| sed 's#fdroid_build_##' \
				| sed 's#html_archlinux#html#' \
				| sed 's#html_##' \
				| sed 's#builds_##' \
				| sed 's#_diffoscope_amd64##' \
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
build_job_health_page
build_nodes_health_page
build_graph_overview_pages
