#!/bin/bash
# vim: set noexpandtab:

# Copyright 2019 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

###################################################################
###								###
### /srv/ftp-master.debian.org/buildinfo/ on coccia.debian.org	###
### is not a pool structure, but rather by year/month/day	###
### this scripts creates links turning this into an alternate	###
### pool structure.						###
### Both are accessable via https://buildinfos.debian.net	###
###								###
###################################################################

set -e
BASEPATH=~jenkins/userContent/reproducible/debian
FTPPATH=$BASEPATH/ftp-master.debian.org/buildinfo
POOLPATH=$BASEPATH/buildinfo-pool

PROBLEMS=$(mktemp -t poolize.XXXXXXXX)
mkdir -p $POOLPATH

YEAR="$(date -u +%Y)"
MONTH="$(date -u +%m)"
DAY="$(date -u +%d)"

do_day(){
	COUNTER=0
	MONTHPATH=$FTPPATH/$YEAR/$MONTH
	if [ ! -d $MONTHPATH ] ; then
		echo "$MONTHPATH does not exist, next."
		return
	fi
	cd $MONTHPATH

	if [ ! -d $DAY ] ; then
		echo "$MONTHPATH/$DAY does not exist, next."
		return
	fi
	cd $DAY
	for FILE in * ; do
		# echo $FILE
		PACKAGE=$(echo $FILE | cut -d '_' -f1)
		if [ "${PACKAGE:0:3}" = "lib" ] ; then
			POOLDIR="${PACKAGE:0:4}"
		else
			POOLDIR="${PACKAGE:0:1}"
		fi
		TARGETPATH="../../../../../buildinfo-pool/$POOLDIR/$PACKAGE"
		mkdir -p $TARGETPATH
		VERSION=$(grep ^Version: $FILE | head -1 | cut -d ' ' -f2)
		if $(echo $VERSION | grep -q ":") ; then
			#echo -n $VERSION
			VERSION=$(echo $VERSION | cut -d ':' -f2)
			#echo " becomes $VERSION"
		fi
		ARCHITECTURE=$(grep ^Architecture: $FILE | cut -d ' ' -f2-|sed 's# #-#g')
		ARCHSUFFIX=$(echo $FILE | cut -d '_' -f3)
		if [ "${ARCHITECTURE}.buildinfo" != "$ARCHSUFFIX" ] ; then
			ARCHSUFFIX="${ARCHITECTURE}.buildinfo"
			#echo $FILE is really for $ARCHITECTURE
		fi
		FULLTARGET="$TARGETPATH/${PACKAGE}_${VERSION}_${ARCHSUFFIX}"
		if [ "$(readlink -f $FULLTARGET)" = "$MONTHPATH/$DAY/$FILE" ] ; then
				#echo "$FULLTARGET already points to $MONTHPATH/$DAY/$FILE thus ignoring this...."
				:
		elif [ ! -e "$FULLTARGET" ] && [ -e "$MONTHPATH/$DAY/$FILE" ] ; then
			ln -s $MONTHPATH/$DAY/$FILE $FULLTARGET
			# echo "$MONTHPATH/$DAY/$FILE linked from $FULLTARGET"
			let COUNTER+=1
		elif [ ! -e $MONTHPATH/$DAY/$FILE ] ; then
			echo "on no $MONTHPATH/$DAY/$FILE does not exist, exiting."
			exit 1
		elif [ -e $FULLTARGET ] ; then
			if [ ! -e "$FULLTARGET.0" ] ; then
				ln -s $MONTHPATH/$DAY/$FILE $FULLTARGET.0
				echo "$MONTHPATH/$DAY/$FILE linked from $FULLTARGET.0"
				let COUNTER+=1
			elif [ "$(readlink -f $FULLTARGET.0)" = "$MONTHPATH/$DAY/$FILE" ] ; then
				# also ignoring this
				:
			else
				# so far we found three such cases...
				if [ ! -e "$FULLTARGET.1" ] ; then
					ln -s $MONTHPATH/$DAY/$FILE $FULLTARGET.1
					echo "$MONTHPATH/$DAY/$FILE linked from $FULLTARGET.1"
					let COUNTER+=1
				elif [ "$(readlink -f $FULLTARGET.1)" = "$MONTHPATH/$DAY/$FILE" ] ; then
					# also ignoring this
					:
				else
					# so far, no such case has been found
					echo "oh no $FULLTARGET.1 also exists and thus we don't know what to do, thus ignoring." >> $PROBLEMS
					echo "$MONTHPATH/$DAY/$FILE is the source of the problem" >> $PROBLEMS
					ls -l $FULLTARGET >> $PROBLEMS
					ls -l $FULLTARGET.0 >> $PROBLEMS
					echo >> $PROBLEMS
				fi
			fi
		fi
	done
	echo -n "Done processing $YEAR/$MONTH/$DAY"
	if [ $COUNTER -gt 0 ] ; then
		echo " - $COUNTER links added."
	else
		echo
	fi
	cd ..
}

loop_through_all(){
	for YEAR in $(seq 2019 -1 2016) ; do
		for MONTH in $(seq -w 12 -1 01) ; do
			for DAY in $(seq -w 31 -1 01) ; do
				do_day
			done
		done
	done
}

if [ -n "$1" ] ; then
	loop_through_all
else
	do_day
	YEAR="$(date -u -d '1 day ago' +%Y)"
	MONTH="$(date -u -d '1 day ago' +%m)"
	DAY="$(date -u -d '1 day ago' +%d)"
	do_day
fi

if [ -s $PROBLEMS ] ; then
	echo problems stored in $PROBLEMS
	cat $PROBLEMS
	cat $PROBLEMS >> $BASEPATH/buildinfo-problems
	exit 1
else
	rm $PROBLEMS
fi

