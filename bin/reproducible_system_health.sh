#!/bin/bash
# vim: set noexpandtab:

# Copyright 2020 Holger Levsen <holger@layer-acht.org>
# released under the GPLv2

###
###
###
###  calculate a number between 0 and 255 representing the health status
###  of https://tests.reproducible-builds.org for usage with
###  https://github.com/jelly/reproduciblebuilds-display/
### 
###
###

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"
# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh
# we fail hard
set -e

# define some variables
HEALTH_FILE=$BASE/trbo.status
STATUS=-1
INPUTS=0
SCORE=0
# gather data
echo "$(date -u) - starting up."
cd /var/lib/jenkins/jobs/
for JOB in reproducible_* ; do
	let INPUTS+=1
	FILE=$JOB/builds/permalinks
	LAST=$(grep lastCompletedBuild $FILE|awk '{print $2}')
	STABLE=$(grep lastStableBuild $FILE|awk '{print $2}')
	UNSTABLE=$(grep lastUnstableBuild $FILE|awk '{print $2}')
	if [ "$LAST" = "$STABLE" ] ; then
		echo "  stable job: $JOB"
		let SCORE+=3
	elif [ "$LAST" = "$UNSTABLE" ] ; then
		echo "unstable job: $JOB"
		let SCORE+=1
	else
		echo "  failed job: $JOB"
		let SCORE-=1
		:
	fi
done
# represent data
STATUS=$(echo "scale=3 ; $SCORE / ( $INPUTS * 3 ) * 255" | bc | cut -d '.' -f1)
GREEN=$STATUS
RED=$(echo 255-$STATUS|bc)
echo "$(date -u) - INPUTS = $INPUTS"
echo "$(date -u) - SCORE  = $SCORE"
echo "$(date -u) - STATUS = $STATUS"
echo $STATUS > $HEALTH_FILE
echo "$(date -u) - $HEALTH_FILE updated."
cat > $HEALTH_FILE.html <<- EOF
<html><head></head><body style="background-color: rgb($RED, $GREEN, 0);">
<h1>tests.reproducible-builds.org Status</h1>
Status: $STATUS (between 0 and 255)
<br/>
Score: $SCORE (a stable jobs adds 3, an unstable job adds 1 and a failed job substracts 1)<br/>
Inputs considered: $INPUTS
</body></html>
EOF
echo "$(date -u) - $(basename $HEALTH_FILE).html updated, visible at $REPRODUCIBLE_URL/$(basename $HEALTH_FILE).html."
echo "$(date -u) - the end."
