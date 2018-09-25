#!/bin/bash

# Copyright 2014-2018 Holger Levsen <holger@layer-acht.org>
#                2015 anthraxx <levente@leventepolyak.net>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

#
# analyse results to create the webpage
#
echo "$(date -u) - starting."
DATE=$(date -u +'%Y-%m-%d')
YESTERDAY=$(date '+%Y-%m-%d' -d "-1 day")
MEMBERS_FTBFS="0 1 2 3 4"
MEMBERS_DEPWAIT="0 1"
MEMBERS_404="0 1 2 3 4 5 6 7 8 9 A"
MEMBERS_FTBR="0 1 2"
HTML_BUFFER=$(mktemp -t archlinuxrb-html-XXXXXXXX)
HTML_REPOSTATS=$(mktemp -t archlinuxrb-html-XXXXXXXX)
ARCHLINUX_TOTAL=0
ARCHLINUX_TESTED=0
ARCHLINUX_NR_FTBFS=0
ARCHLINUX_NR_FTBR=0
ARCHLINUX_NR_DEPWAIT=0
ARCHLINUX_NR_404=0
ARCHLINUX_NR_GOOD=0
ARCHLINUX_NR_BLACKLISTED=0
ARCHLINUX_NR_UNKNOWN=0
WIDTH=1920
HEIGHT=960
PAGE=''

repostats(){
	#
	# gather data
	# write csv file for $REPOSITORY
	# write $HTML_REPOSTATS
	#
	for REPOSITORY in $ARCHLINUX_REPOS ; do
		echo "$(date -u) - starting to analyse build results for '$REPOSITORY'."
		# prepare stats per repository
		SUITE="archlinux_$REPOSITORY"
		TOTAL=$(query_db "SELECT count(*) FROM sources AS s WHERE s.architecture='x86_64' AND s.suite='$SUITE';")
		TESTED=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.architecture='x86_64' AND s.suite='$SUITE';")
		NR_GOOD=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.architecture='x86_64' AND s.suite='$SUITE' AND r.status='GOOD';")
		NR_FTBR=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.architecture='x86_64' AND s.suite='$SUITE' AND r.status LIKE 'FTBR_%';")
		NR_FTBFS=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.architecture='x86_64' AND s.suite='$SUITE' AND r.status LIKE 'FTBFS_%';")
		NR_DEPWAIT=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.architecture='x86_64' AND s.suite='$SUITE' AND r.status LIKE 'DEPWAIT_%';")
		NR_404=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.architecture='x86_64' AND s.suite='$SUITE' AND r.status LIKE '404_%';")
		NR_BLACKLISTED=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.architecture='x86_64' AND s.suite='$SUITE' AND r.status='BLACKLISTED';")
		NR_UNKNOWN=$(query_db "SELECT count(*) FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.architecture='x86_64' AND s.suite='$SUITE' AND r.status LIKE 'UNKNOWN_%';")
		let NR_UNKNOWN=$NR_UNKNOWN+$(query_db "SELECT count(s.name) FROM sources AS s WHERE s.architecture='x86_64' AND s.id NOT IN (SELECT package_id FROM results)")
	PERCENT_TOTAL=$(echo "scale=1 ; ($TESTED*100/$TOTAL)" | bc)
		if [ $(echo $PERCENT_TOTAL/1|bc) -lt 99 ] ; then
			NR_TESTED="$TESTED <span style=\"font-size:0.8em;\">(tested $PERCENT_TOTAL% of $TOTAL)</span>"
		else
			NR_TESTED=$TESTED
		fi
		echo "     <tr>" >> $HTML_REPOSTATS
		echo "      <td><a href='/archlinux/$REPOSITORY.html'>$REPOSITORY</a></td><td>$NR_TESTED</td>" >> $HTML_REPOSTATS
		for i in $NR_GOOD $NR_FTBR $NR_FTBFS $NR_DEPWAIT $NR_404 $NR_BLACKLISTED $NR_UNKNOWN ; do
			PERCENT_i=$(echo "scale=1 ; ($i*100/$TESTED)" | bc)
			if [ "$PERCENT_i" != "0" ] || [ "$i" != "0" ] ; then
				echo "      <td>$i ($PERCENT_i%)</td>" >> $HTML_REPOSTATS
			else
				echo "      <td>$i</td>" >> $HTML_REPOSTATS
			fi
		done
		echo "     </tr>" >> $HTML_REPOSTATS
		if [ ! -f $ARCHBASE/$REPOSITORY.csv ] ; then
			echo '; date, reproducible, unreproducible, ftbfs, depwait, download problems, untested' > $ARCHBASE/$REPOSITORY.csv
		fi
		if ! grep -q $YESTERDAY $ARCHBASE/$REPOSITORY.csv ; then
			let REAL_UNKNOWN=$TOTAL-$NR_GOOD-$NR_FTBR-$NR_FTBFS-$NR_DEPWAIT-$NR_404 || true
			echo $YESTERDAY,$NR_GOOD,$NR_FTBR,$NR_FTBFS,$NR_DEPWAIT,$NR_404,$REAL_UNKNOWN >> $ARCHBASE/$REPOSITORY.csv
		fi
		IMAGE=$ARCHBASE/$REPOSITORY.png
		if [ ! -f $IMAGE ] || [ $ARCHBASE/$REPOSITORY.csv -nt $IMAGE ] ; then
			echo "Updating $IMAGE..."
			/srv/jenkins/bin/make_graph.py $ARCHBASE/$REPOSITORY.csv $IMAGE 6 "Reproducibility status for Arch Linux packages in $REPOSITORY" "Amount (total)" $WIDTH $HEIGHT
		fi
		#
		# prepare ARCHLINUX totals
		#
		set +e
		let ARCHLINUX_TOTAL+=$TOTAL
		let ARCHLINUX_TESTED+=$TESTED
		let ARCHLINUX_NR_FTBFS+=$NR_FTBFS
		let ARCHLINUX_NR_FTBR+=$NR_FTBR
		let ARCHLINUX_NR_DEPWAIT+=$NR_DEPWAIT
		let ARCHLINUX_NR_404+=$NR_404
		let ARCHLINUX_NR_GOOD+=$NR_GOOD
		let ARCHLINUX_NR_BLACKLISTED+=$NR_BLACKLISTED
		let ARCHLINUX_NR_UNKNOWN+=$NR_UNKNOWN
		set -e
	done
	#
	# prepare stats per repository
	#
	ARCHLINUX_PERCENT_TOTAL=$(echo "scale=1 ; ($ARCHLINUX_TESTED*100/$ARCHLINUX_TOTAL)" | bc)
	if [ $(echo $ARCHLINUX_PERCENT_TOTAL/1|bc) -lt 99 ] ; then
		NR_TESTED="$ARCHLINUX_TESTED <span style=\"font-size:0.8em;\">(tested $ARCHLINUX_PERCENT_TOTAL% of $ARCHLINUX_TOTAL)</span>"
	else
		NR_TESTED=$ARCHLINUX_TESTED
	fi
	echo "     <tr>" >> $HTML_REPOSTATS
	echo "      <td><b>all combined</b></td><td>$NR_TESTED</td>" >> $HTML_REPOSTATS
	for i in $ARCHLINUX_NR_GOOD $ARCHLINUX_NR_FTBR $ARCHLINUX_NR_FTBFS $ARCHLINUX_NR_DEPWAIT $ARCHLINUX_NR_404 $ARCHLINUX_NR_BLACKLISTED $ARCHLINUX_NR_UNKNOWN ; do
		PERCENT_i=$(echo "scale=1 ; ($i*100/$ARCHLINUX_TESTED)" | bc)
		if [ "$PERCENT_i" != "0" ] || [ "$i" != "0" ] ; then
			echo "      <td>$i ($PERCENT_i%)</td>" >> $HTML_REPOSTATS
		else
			echo "      <td>$i</td>" >> $HTML_REPOSTATS
		fi
	done
	echo "     </tr>" >> $HTML_REPOSTATS
	#
	# write csv file for totals
	#
	if [ ! -f $ARCHBASE/archlinux.csv ] ; then
		echo '; date, reproducible, unreproducible, ftbfs, depwait, download problems, untested' > $ARCHBASE/archlinux.csv
	fi
	if ! grep -q $YESTERDAY $ARCHBASE/archlinux.csv ; then
		let ARCHLINUX_REAL_UNKNOWN=$ARCHLINUX_TOTAL-$ARCHLINUX_NR_GOOD-$ARCHLINUX_NR_FTBR-$ARCHLINUX_NR_FTBFS-$ARCHLINUX_NR_DEPWAIT-$ARCHLINUX_NR_404 || true
		echo $YESTERDAY,$ARCHLINUX_NR_GOOD,$ARCHLINUX_NR_FTBR,$ARCHLINUX_NR_FTBFS,$ARCHLINUX_NR_DEPWAIT,$ARCHLINUX_NR_404,$ARCHLINUX_REAL_UNKNOWN >> $ARCHBASE/archlinux.csv
	fi
	IMAGE=$ARCHBASE/archlinux.png
	if [ ! -f $IMAGE ] || [ $ARCHBASE/archlinux.csv -nt $IMAGE ] ; then
		echo "Updating $IMAGE..."
		/srv/jenkins/bin/make_graph.py $ARCHBASE/archlinux.csv $IMAGE 6 "Reproducibility status for all tested Arch Linux packages" "Amount (total)" $WIDTH $HEIGHT
		irc_message archlinux-reproducible "Daily graphs on $REPRODUCIBLE_URL/archlinux/ updated, $(echo "scale=1 ; ($ARCHLINUX_NR_GOOD*100/$ARCHLINUX_TESTED)" | bc)% reproducible packages in our current test framework."
	fi
}

archlinux_page_header(){
	echo "$(date -u) - starting to build $PAGE"
	cat > $PAGE <<- EOF
	<!DOCTYPE html>
	<html lang="en-US">
	  <head>
	    <meta charset="UTF-8">
	    <title>Reproducible Arch Linux ?!</title>
	    <link rel='stylesheet' href='global.css' type='text/css' media='all' />
	  </head>
	  <body>
	    <div id="archnavbar">
		    <div id="logo"></div>
	    </div>
	    <div class="content">
	      <h1>Reproducible Arch Linux?!</h1>
	      <div class="page-content">
	
	EOF
}

archlinux_page_footer(){
	write_page "</div></div>"
	write_page_footer 'Arch Linux'
	echo "$(date -u) - enjoy $REPRODUCIBLE_URL/archlinux/$PAGE"
	publish_page archlinux
}

archlinux_page_repostats(){
	write_page "    <table><tr><th>repository</th><th>all source packages</th>"
	write_page "     <th><a href='/archlinux/state_GOOD.html'>reproducible packages</a></th>"
	write_page "     <th><a href='/archlinux/state_FTBR.html'>unreproducible packages</a></th>"
	write_page "     <th><a href='/archlinux/state_FTBFS.html'>packages failing to build</a></th>"
	write_page "     <th><a href='/archlinux/state_DEPWAIT.html'>packages in depwait state</a></th>"
	write_page "     <th><a href='/archlinux/state_404.html'>packages download problems</a></th>"
	write_page "     <th><a href='/archlinux/state_BLACKLISTED.html'>blacklisted</a></th>"
	write_page "     <th><a href='/archlinux/state_UNKNOWN.html'>unknown state</a></th></tr>"
	cat $HTML_REPOSTATS >> $PAGE
	write_page "    </table>"
}

single_main_page(){
	#
	# write out the actual webpage
	#
	PAGE=archlinux.html
	archlinux_page_header
	write_page_intro 'Arch Linux'
	archlinux_page_repostats
	# include graphs
	write_page '<p style="clear:both;">'
	for REPOSITORY in $ARCHLINUX_REPOS ; do
		write_page "<a href=\"/archlinux/$REPOSITORY.png\"><img src=\"/archlinux/$REPOSITORY.png\" class=\"overview\" alt=\"$REPOSITORY stats\"></a>"
	done
	write_page '</p><p style="clear:both;"><center>'
	write_page "<a href=\"/archlinux/archlinux.png\"><img src=\"/archlinux/archlinux.png\" alt=\"total Arch Linux stats\"></a></p>"
	write_variation_table 'Arch Linux'
	archlinux_page_footer
}

repository_pages(){
	for REPOSITORY in $ARCHLINUX_REPOS ; do
		PAGE=$REPOSITORY.html
		echo "$(date -u) - starting to write page for $REPOSITORY'."
		archlinux_page_header
		archlinux_page_repostats
		write_page "<h2>Packages in repository $REPOSITORY</h2>"
		write_page "    <table><tr><th>repository</th><th>source package</th><th>version</th><th>test result</th><th>test date<br />test duration</th><th>1st build log<br />2nd build log</th></tr>"
		SUITE="archlinux_$REPOSITORY"
		REPO_PKGS=$(query_db "SELECT s.name FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.architecture='x86_64' AND s.suite='$SUITE' ORDER BY r.status")
		for PKG in $REPO_PKGS ; do
			cat $ARCHBASE/$REPOSITORY/$PKG/pkg.html >> $PAGE 2>/dev/null || true
		done
		write_page "    </table>"
		archlinux_page_footer
	done
}

state_pages(){
	for STATE in FTBFS FTBR DEPWAIT 404 GOOD BLACKLISTED UNKNOWN ; do
		PAGE=state_$STATE.html
		echo "$(date -u) - starting to write page for state $STATE'."
		archlinux_page_header
		archlinux_page_repostats
		write_page "<h2>Packages in $STATE state</h2>"
		write_page "    <table><tr><th>repository</th><th>source package</th><th>version</th><th>test result</th><th>test date<br />test duration</th><th>1st build log<br />2nd build log</th></tr>"
		for REPOSITORY in $ARCHLINUX_REPOS ; do
			SUITE="archlinux_$REPOSITORY"
			STATE_PKGS=$(query_db "SELECT s.name FROM sources AS s JOIN results AS r ON s.id=r.package_id WHERE s.architecture='x86_64' AND s.suite='$SUITE' AND r.status LIKE '$STATE%' ORDER BY s.suite,r.status")
			for PKG in $STATE_PKGS ; do
				cat $ARCHBASE/$REPOSITORY/$PKG/pkg.html >> $PAGE 2>/dev/null || true
			done
			STATE_PKGS=$(query_db "SELECT s.name FROM sources AS s WHERE s.architecture='x86_64' AND s.id NOT IN (SELECT package_id FROM results)")
			for PKG in $STATE_PKGS ; do
				cat $ARCHBASE/$REPOSITORY/$PKG/pkg.html >> $PAGE 2>/dev/null || true
			done
		done
		write_page "    </table>"
		archlinux_page_footer
	done
}

repostats
single_main_page
repository_pages
state_pages
rm $HTML_REPOSTATS > /dev/null
echo "$(date -u) - all done."

# vim: set sw=0 noet :
