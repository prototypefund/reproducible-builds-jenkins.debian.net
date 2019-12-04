#!/bin/bash

# Copyright 2014-2019 Holger Levsen <holger@layer-acht.org>
#                2015 anthraxx <levente@leventepolyak.net>
#                2019 kpcyrd <git@rxv.cc>
# released under the GPLv2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

#
#
# reproducible_html_alpine.sh can be called in two ways:
# - without params, then it will build all the index and dashboard pages
# - with exactly two params, $REPOSITORY and $SRCPACKAGE, in which case that packages html page will be created
#


#
# helper functions
#
get_state_from_counter() {
	local counter=$1
	case $counter in
		0)	STATE=reproducible ;;
		1)	STATE=FTBR ;;
		2)	STATE=FTBFS ;;
		3)	STATE=DEPWAIT ;;
		4)	STATE=404 ;;
		5)	STATE=blacklisted ;;
		6)	STATE=UNKNOWN ;;
	esac
}


include_pkg_html_in_page(){
	cat $ALPINE_BASE/$REPOSITORY/$SRCPACKAGE/pkg.html >> $PAGE 2>/dev/null || true
}

include_pkg_table_header_in_page(){
	write_page "    <table><tr><th>repository</th><th>source package</th><th>version</th><th>test result</th><th>test date<br />test duration</th><th>1st build log<br />2nd build log</th></tr>"
}

repostats(){
	#
	# gather data
	# write csv file for $REPOSITORY
	# write $HTML_REPOSTATS
	#
	for REPOSITORY in $ALPINE_REPOS ; do
		echo "$(date -u) - starting to analyse build results for '$REPOSITORY'."
		# prepare stats per repository
		SUITE="alpine_$REPOSITORY"
		TOTAL=$(query_db "SELECT count(*) FROM sources AS s WHERE s.distribution=$DISTROID AND s.architecture='x86_64' AND s.suite='$SUITE';")
		TESTED=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.distribution=$DISTROID AND s.architecture='x86_64' AND s.suite='$SUITE';")
		NR_GOOD=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.distribution=$DISTROID AND s.architecture='x86_64' AND s.suite='$SUITE' AND r.status='reproducible';")
		NR_FTBR=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.distribution=$DISTROID AND s.architecture='x86_64' AND s.suite='$SUITE' AND r.status LIKE 'FTBR_%';")
		NR_FTBFS=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.distribution=$DISTROID AND s.architecture='x86_64' AND s.suite='$SUITE' AND r.status LIKE 'FTBFS_%';")
		NR_DEPWAIT=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.distribution=$DISTROID AND s.architecture='x86_64' AND s.suite='$SUITE' AND r.status LIKE 'DEPWAIT_%';")
		NR_404=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.distribution=$DISTROID AND s.architecture='x86_64' AND s.suite='$SUITE' AND r.status LIKE '404_%';")
		NR_BLACKLISTED=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.distribution=$DISTROID AND s.architecture='x86_64' AND s.suite='$SUITE' AND r.status='blacklisted';")
		NR_UNKNOWN=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.distribution=$DISTROID AND  s.architecture='x86_64' AND s.suite='$SUITE' AND r.status LIKE 'UNKNOWN_%';")
		NR_UNTESTED=$(query_db "SELECT count(s.name) FROM sources AS s WHERE s.architecture='x86_64' AND s.distribution=$DISTROID AND s.suite='$SUITE' AND s.id NOT IN (SELECT package_id FROM results)")
		if [ $NR_UNTESTED -ne 0 ] ; then
			let NR_UNKNOWN=$NR_UNKNOWN+$NR_UNTESTED
		fi
		PERCENT_TOTAL=$(echo "scale=1 ; ($TESTED*100/$TOTAL)" | bc)
		if [ $(echo $PERCENT_TOTAL/1|bc) -lt 99 ] ; then
			NR_TESTED="$TESTED <span style=\"font-size:0.8em;\">(tested $PERCENT_TOTAL% of $TOTAL)</span>"
		else
			NR_TESTED=$TESTED
		fi
		echo "     <tr>" >> $HTML_REPOSTATS
		echo "      <td><a href='/alpine/$REPOSITORY.html'>$REPOSITORY</a></td><td><a href='/alpine/$REPOSITORY.html'>$NR_TESTED</a></td>" >> $HTML_REPOSTATS
		counter=0
		for i in $NR_GOOD $NR_FTBR $NR_FTBFS $NR_DEPWAIT $NR_404 $NR_BLACKLISTED $NR_UNKNOWN ; do
			get_state_from_counter $counter
			let counter+=1
			PERCENT_i=$(echo "scale=1 ; ($i*100/$TESTED)" | bc)
			if [ "$PERCENT_i" != "0" ] || [ "$i" != "0" ] ; then
				echo "      <td><a href='/alpine/state_${REPOSITORY}_$STATE.html'>$i ($PERCENT_i%)</a></td>" >> $HTML_REPOSTATS
			else
				echo "      <td><a href='/alpine/state_${REPOSITORY}_$STATE.html'>$i</a></td>" >> $HTML_REPOSTATS
			fi
		done
		echo "     </tr>" >> $HTML_REPOSTATS
		if [ ! -f $ALPINE_BASE/$REPOSITORY.csv ] ; then
			echo '; date, reproducible, unreproducible, ftbfs, depwait, download problems, untested' > $ALPINE_BASE/$REPOSITORY.csv
		fi
		if ! grep -q $YESTERDAY $ALPINE_BASE/$REPOSITORY.csv ; then
			let REAL_UNKNOWN=$TOTAL-$NR_GOOD-$NR_FTBR-$NR_FTBFS-$NR_DEPWAIT-$NR_404 || true
			echo $YESTERDAY,$NR_GOOD,$NR_FTBR,$NR_FTBFS,$NR_DEPWAIT,$NR_404,$REAL_UNKNOWN >> $ALPINE_BASE/$REPOSITORY.csv
		fi
		IMAGE=$ALPINE_BASE/$REPOSITORY.png
		if [ ! -f $IMAGE ] || [ $ALPINE_BASE/$REPOSITORY.csv -nt $IMAGE ] ; then
			echo "Updating $IMAGE..."
			/srv/jenkins/bin/make_graph.py $ALPINE_BASE/$REPOSITORY.csv $IMAGE 6 "Reproducibility status for alpine packages in $REPOSITORY" "Amount (total)" $WIDTH $HEIGHT
		fi
		#
		# prepare ALPINE totals
		#
		set +e
		let ALPINE_TOTAL+=$TOTAL
		let ALPINE_TESTED+=$TESTED
		let ALPINE_NR_FTBFS+=$NR_FTBFS
		let ALPINE_NR_FTBR+=$NR_FTBR
		let ALPINE_NR_DEPWAIT+=$NR_DEPWAIT
		let ALPINE_NR_404+=$NR_404
		let ALPINE_NR_GOOD+=$NR_GOOD
		let ALPINE_NR_BLACKLISTED+=$NR_BLACKLISTED
		let ALPINE_NR_UNKNOWN+=$NR_UNKNOWN
		set -e
	done
	#
	# prepare stats per repository
	#
	ALPINE_PERCENT_TOTAL=$(echo "scale=1 ; ($ALPINE_TESTED*100/$ALPINE_TOTAL)" | bc)
	if [ $(echo $ALPINE_PERCENT_TOTAL/1|bc) -lt 99 ] ; then
		NR_TESTED="$ALPINE_TESTED <span style=\"font-size:0.8em;\">(tested $ALPINE_PERCENT_TOTAL% of $ALPINE_TOTAL)</span>"
	else
		NR_TESTED=$ALPINE_TESTED
	fi
	echo "     <tr>" >> $HTML_REPOSTATS
	echo "      <td><b>all combined</b></td><td>$NR_TESTED</td>" >> $HTML_REPOSTATS
	counter=0
	for i in $ALPINE_NR_GOOD $ALPINE_NR_FTBR $ALPINE_NR_FTBFS $ALPINE_NR_DEPWAIT $ALPINE_NR_404 $ALPINE_NR_BLACKLISTED $ALPINE_NR_UNKNOWN ; do
		get_state_from_counter $counter
		let counter+=1
		PERCENT_i=$(echo "scale=1 ; ($i*100/$ALPINE_TESTED)" | bc)
		if [ "$PERCENT_i" != "0" ] || [ "$i" != "0" ] ; then
			echo "      <td><a href='/alpine/state_$STATE.html'>$i ($PERCENT_i%)</a></td>" >> $HTML_REPOSTATS
		else
			echo "      <td><a href='/alpine/state_$STATE.html'>$i</a></td>" >> $HTML_REPOSTATS
		fi
	done
	echo "     </tr>" >> $HTML_REPOSTATS
	#
	# write csv file for totals
	#
	if [ ! -f $ALPINE_BASE/alpine.csv ] ; then
		echo '; date, reproducible, unreproducible, ftbfs, depwait, download problems, untested' > $ALPINE_BASE/alpine.csv
	fi
	if ! grep -q $YESTERDAY $ALPINE_BASE/alpine.csv ; then
		let ALPINE_REAL_UNKNOWN=$ALPINE_TOTAL-$ALPINE_NR_GOOD-$ALPINE_NR_FTBR-$ALPINE_NR_FTBFS-$ALPINE_NR_DEPWAIT-$ALPINE_NR_404 || true
		echo $YESTERDAY,$ALPINE_NR_GOOD,$ALPINE_NR_FTBR,$ALPINE_NR_FTBFS,$ALPINE_NR_DEPWAIT,$ALPINE_NR_404,$ALPINE_REAL_UNKNOWN >> $ALPINE_BASE/alpine.csv
	fi
	IMAGE=$ALPINE_BASE/alpine.png
	if [ ! -f $IMAGE ] || [ $ALPINE_BASE/alpine.csv -nt $IMAGE ] ; then
		echo "Updating $IMAGE..."
		/srv/jenkins/bin/make_graph.py $ALPINE_BASE/alpine.csv $IMAGE 6 "Reproducibility status for all tested alpine packages" "Amount (total)" $WIDTH $HEIGHT
		irc_message alpine-reproducible "Daily graphs on $REPRODUCIBLE_URL/alpine/ updated, $(echo "scale=1 ; ($ALPINE_NR_GOOD*100/$ALPINE_TESTED)" | bc)% reproducible packages in our current test framework."
	fi
}

alpine_page_header(){
	echo "$(date -u) - starting to write $PAGE"
	cat > $PAGE <<- EOF
	<!DOCTYPE html>
	<html lang="en-US">
	  <head>
	    <meta charset="UTF-8">
	    <title>$TITLE</title>
	    <link rel='stylesheet' href='global.css' type='text/css' media='all' />
	  </head>
	  <body>
	    <div id="logo">
	        <img src="alpinelinux-logo.svg" alt="">
	    </div>
	    <div class="content">
	      <h1><a href='/alpine/'>Reproducible alpine</a>?!</h1>
	      <div class="page-content">

	EOF
}

alpine_page_footer(){
	write_page "</div></div>"
	write_page_footer 'alpine'
	publish_page alpine
}

alpine_repostats_table(){
	write_page "    <table><tr><th>repository</th><th>all source packages</th>"
	write_page "     <th><a href='/alpine/state_reproducible.html'>reproducible</a></th>"
	write_page "     <th><a href='/alpine/state_FTBR.html'>unreproducible</a></th>"
	write_page "     <th><a href='/alpine/state_FTBFS.html'>failing to build</a></th>"
	write_page "     <th><a href='/alpine/state_DEPWAIT.html'>in depwait state</a></th>"
	write_page "     <th><a href='/alpine/state_404.html'>download problems</a></th>"
	write_page "     <th><a href='/alpine/state_blacklisted.html'>blacklisted</a></th>"
	write_page "     <th><a href='/alpine/state_UNKNOWN.html'>unknown state</a></th></tr>"
	cat $HTML_REPOSTATS >> $PAGE
	write_page "    </table>"
	write_page "    <p>("
	write_page "     <a href='/alpine/recent_builds.html'>recent builds</a>,"
	write_page "     <a href='/alpine/scheduled.html'>currently scheduled</a>"
	write_page "       )</p>"
}

dashboard_page(){
	PAGE=alpine.html
	TITLE="Reproducible alpine ?!"
	alpine_page_header
	write_page_intro 'alpine'
	alpine_repostats_table
	# include graphs
	write_page '<p style="clear:both;">'
	for REPOSITORY in $ALPINE_REPOS ; do
		write_page "<a href=\"/alpine/$REPOSITORY.png\"><img src=\"/alpine/$REPOSITORY.png\" class=\"overview\" alt=\"$REPOSITORY stats\"></a>"
	done
	write_page '</p><p style="clear:both;"><center>'
	write_page "<a href=\"/alpine/alpine.png\"><img src=\"/alpine/alpine.png\" alt=\"total alpine stats\"></a></p>"
	write_variation_table 'alpine'
	alpine_page_footer
}

repository_pages(){
	for REPOSITORY in $ALPINE_REPOS ; do
		PAGE=$REPOSITORY.html
		TITLE="Reproducible alpine $REPOSITORY ?!"
		alpine_page_header
		alpine_repostats_table
		SUITE="alpine_$REPOSITORY"
		TESTED=$(query_db "SELECT count(*) FROM sources AS s
					JOIN results AS r
					ON s.id=r.package_id
					WHERE s.distribution=$DISTROID
					AND s.architecture='x86_64'
					AND s.suite='$SUITE';")
		write_page "<h2>$TESTED packages in repository $REPOSITORY</h2>"
		include_pkg_table_header_in_page
		REPO_PKGS=$(query_db "SELECT s.name FROM sources
				AS s JOIN results AS r
				ON s.id=r.package_id
				WHERE s.distribution=$DISTROID
				AND s.architecture='x86_64'
				AND s.suite='$SUITE'
				ORDER BY r.status,s.name")
		for SRCPACKAGE in $REPO_PKGS ; do
			include_pkg_html_in_page
		done
		write_page "    </table>"
		alpine_page_footer
	done
}

state_pages(){
	for STATE in FTBFS FTBR DEPWAIT 404 reproducible blacklisted UNKNOWN ; do
		PAGE=state_$STATE.html
		TITLE="Reproducible alpine, packages in state $STATE"
		alpine_page_header
		alpine_repostats_table
		TESTED=$(query_db "SELECT count(*) FROM sources AS s
				JOIN results AS r
				ON s.id=r.package_id
				WHERE s.distribution=$DISTROID
				AND s.architecture='x86_64'
				AND r.status LIKE '$STATE%';")
		if [ "$STATE" = "UNKNOWN" ] ; then
			# untested packages are also state UNKNOWN...
			UNTESTED=$(query_db "SELECT count(s.name) FROM sources AS s
					WHERE s.distribution=$DISTROID
					AND s.architecture='x86_64'
					AND s.id NOT IN (SELECT package_id FROM results)")
			if [ $UNTESTED -ne 0 ] ; then
				let TESTED=$TESTED+$UNTESTED
			fi
		fi
		write_page "<h2>$TESTED packages in $STATE state</h2>"
		include_pkg_table_header_in_page
		for REPOSITORY in $ALPINE_REPOS ; do
			SUITE="alpine_$REPOSITORY"
			STATE_PKGS=$(query_db "SELECT s.name FROM sources AS s
					JOIN results AS r
					ON s.id=r.package_id
					WHERE s.distribution=$DISTROID
					AND s.architecture='x86_64'
					AND s.suite='$SUITE'
					AND r.status LIKE '$STATE%'
					ORDER BY r.status,s.name")
			for SRCPACKAGE in ${STATE_PKGS} ; do
				include_pkg_html_in_page
			done
			if [ "$STATE" = "UNKNOWN" ] ; then
				# untested packages are also state UNKNOWN...
				STATE_PKGS=$(query_db "SELECT s.name FROM sources AS s
					WHERE s.distribution=$DISTROID
					AND s.architecture='x86_64'
					AND s.suite='$SUITE'
					AND s.id NOT IN (SELECT package_id FROM results)
					ORDER BY s.name")
				for SRCPACKAGE in ${STATE_PKGS} ; do
					include_pkg_html_in_page
				done
			fi
		done
		write_page "    </table>"
		alpine_page_footer
	done
}

repository_state_pages(){
	for REPOSITORY in $ALPINE_REPOS ; do
		SUITE="alpine_$REPOSITORY"
		for STATE in FTBFS FTBR DEPWAIT 404 reproducible blacklisted UNKNOWN ; do
			PAGE=state_${REPOSITORY}_$STATE.html
			TITLE="Reproducible alpine, packages in $REPOSITORY in state $STATE"
			alpine_page_header
			alpine_repostats_table
			TESTED=$(query_db "SELECT count(*) FROM sources AS s
					JOIN results AS r
					ON s.id=r.package_id
					WHERE s.distribution=$DISTROID
					AND s.architecture='x86_64'
					AND s.suite='$SUITE'
					AND r.status LIKE '$STATE%';")
			if [ "$STATE" = "UNKNOWN" ] ; then
				# untested packages are also state UNKNOWN...
				UNTESTED=$(query_db "SELECT count(s.name) FROM sources AS s
						WHERE s.distribution=$DISTROID
						AND s.architecture='x86_64'
						AND s.suite='$SUITE'
						AND s.id NOT IN (SELECT package_id FROM results)")
				if [ $UNTESTED -ne 0 ] ; then
					let TESTED=$TESTED+$UNTESTED
				fi
			fi
			write_page "<h2>$TESTED packages in $REPOSITORY in $STATE state</h2>"
			include_pkg_table_header_in_page
			STATE_PKGS=$(query_db "SELECT s.name FROM sources AS s
					JOIN results AS r
					ON s.id=r.package_id
					WHERE s.distribution=$DISTROID
					AND s.architecture='x86_64'
					AND s.suite='$SUITE'
					AND r.status LIKE '$STATE%'
					ORDER BY r.status,s.name")
			for SRCPACKAGE in ${STATE_PKGS} ; do
				include_pkg_html_in_page
			done
			if [ "$STATE" = "UNKNOWN" ] ; then
				# untested packages are also state UNKNOWN...
				STATE_PKGS=$(query_db "SELECT s.name FROM sources AS s
					WHERE s.distribution=$DISTROID
					AND s.architecture='x86_64'
					AND s.suite='$SUITE'
					AND s.id NOT IN (SELECT package_id FROM results)
					ORDER BY s.name")
				for SRCPACKAGE in ${STATE_PKGS} ; do
					include_pkg_html_in_page
				done
			fi
			write_page "    </table>"
			alpine_page_footer
		done
	done
}

recent_builds_page(){
	PAGE=recent_builds.html
	TITLE="Reproducible alpine, builds in the last 24h"
	alpine_page_header
	alpine_repostats_table
	MAXDATE="$(date -u +'%Y-%m-%d %H:%M' -d '24 hours ago')"
	RECENT=$(query_db "SELECT count(s.name) FROM sources AS s
				JOIN results AS r
				ON s.id=r.package_id
				WHERE s.distribution=$DISTROID
				AND s.architecture='x86_64'
				AND r.build_date > '$MAXDATE'")
	write_page "<h2>$RECENT builds of alpine packages in the last 24h</h2>"
	include_pkg_table_header_in_page
	STATE_PKGS=$(query_db "SELECT s.name, s.suite FROM sources AS s
				JOIN results AS r
				ON s.id=r.package_id
				WHERE s.distribution=$DISTROID
				AND s.architecture='x86_64'
				AND r.build_date > '$MAXDATE'
				ORDER BY r.build_date
				DESC")
	for LINE in ${STATE_PKGS} ; do
		SRCPACKAGE=$(echo "$LINE" | cut -d "|" -f1)
		REPOSITORY=$(echo "$LINE" | cut -d "|" -f2 | sed 's#alpine_##')
		include_pkg_html_in_page
	done
	write_page "    </table>"
	alpine_page_footer
}

currently_scheduled_page(){
	PAGE=scheduled.html
	TITLE="Reproducible alpine, packages currently scheduled"
	alpine_page_header
	alpine_repostats_table
	TESTED=$(query_db "SELECT count(*)
			FROM sources AS s
			JOIN schedule AS sch
			ON s.id=sch.package_id
			WHERE s.distribution=$DISTROID
			AND s.architecture='x86_64'
			AND sch.date_build_started IS NULL")
	write_page "<h2>Currently $TESTED scheduled builds of alpine packages</h2>"
	write_page "    <table><tr><th>source package</th><th>repository</th><th>version</th><th>scheduled</th></tr>"
	STATE_PKGS=$(query_db "SELECT s.name, s.suite, s.version, sch.date_scheduled
			FROM sources AS s
			JOIN schedule AS sch
			ON s.id=sch.package_id
			WHERE s.distribution=$DISTROID
			AND s.architecture='x86_64'
			AND sch.date_build_started IS NULL
			ORDER BY sch.date_scheduled, s.name")
	OIFS=$IFS
	IFS=$'\012'
	for LINE in ${STATE_PKGS} ; do
		SRCPACKAGE=$(echo "$LINE" | cut -d "|" -f1)
		REPOSITORY=$(echo "$LINE" | cut -d "|" -f2 | sed 's#alpine_##')
		VERSION=$(echo "$LINE" | cut -d "|" -f3)
		SCH_DATE=$(echo "$LINE" | cut -d "|" -f4-)
		write_page "     <tr><td>$SRCPACKAGE</td><td>$REPOSITORY</td><td>$VERSION</td><td>$SCH_DATE</td></tr>"
	done
	IFS=$OIFS
	write_page "    </table>"
	alpine_page_footer
}

#
# main
#
echo "$(date -u) - starting."
YESTERDAY=$(date '+%Y-%m-%d' -d "-1 day")
PAGE=""
TITLE=""
STATE=""
REPOSITORY=""
SRCPACKAGE=""
DISTROID=$(query_db "SELECT id FROM distributions WHERE name='alpine'")

if [ -z "$1" ] ; then
	MEMBERS_FTBFS="0 1 2 3 4"
	MEMBERS_DEPWAIT="0 1 2"
	MEMBERS_404="0 1 2 3 4 5 6 7 8 9 A B C"
	MEMBERS_FTBR="0 1 2"
	HTML_REPOSTATS=$(mktemp -t alpinerb-html-XXXXXXXX)
	ALPINE_TOTAL=0
	ALPINE_TESTED=0
	ALPINE_NR_FTBFS=0
	ALPINE_NR_FTBR=0
	ALPINE_NR_DEPWAIT=0
	ALPINE_NR_404=0
	ALPINE_NR_GOOD=0
	ALPINE_NR_BLACKLISTED=0
	ALPINE_NR_UNKNOWN=0
	WIDTH=1920
	HEIGHT=960
	# variables related to the stats we update
	# FIELDS[0]="datum, reproducible, FTBR, FTBFS, other, untested" # for this alpine still uses a .csv file...
	FIELDS[1]="datum"
	for i in reproducible FTBR FTBFS other ; do
	        for j in $SUITES ; do
	                FIELDS[1]="${FIELDS[1]}, ${i}_${j}"
	        done
	done
	FIELDS[2]="datum, oldest"

	repostats
	dashboard_page
	currently_scheduled_page
	recent_builds_page
	repository_pages
	state_pages
	repository_state_pages

	rm $HTML_REPOSTATS > /dev/null
elif [ -z "$2" ] ; then
	echo "$(date -u) - $0 needs two params or none, exiting."
	# add code here to also except core, extra, multilib or community...
	exit 1
else
	REPOSITORY=$1
	SRCPACKAGE=$2
	if [ ! -d $ALPINE_BASE/$REPOSITORY/$SRCPACKAGE ] ; then
		echo "$(date -u) - $ALPINE_BASE/$REPOSITORY/$SRCPACKAGE does not exist, exiting."
		exit 1
	fi
	HTML_BUFFER=''
	create_pkg_html
fi
echo "$(date -u) - all done."

# vim: set sw=0 noet :
