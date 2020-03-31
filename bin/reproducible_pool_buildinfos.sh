#!/bin/bash
# vim: set noexpandtab:

# Copyright 2019-2020 Holger Levsen <holger@layer-acht.org>
# released under the GPLv2

###################################################################
###								###
### /srv/ftp-master.debian.org/buildinfo/ on coccia.debian.org	###
### provides .buildinfo files in a year/month/day structure,	###
### but there is no pool structure - and it's not public.       ###
### this scripts uses links to provide an alternative pool	###
### structure and makes them both accessible on			###
### https://buildinfos.debian.net				###
###								###
###################################################################

# basic assumptions
set -e
BASEPATH=~jenkins/userContent/reproducible/debian
FTPPATH=$BASEPATH/ftp-master.debian.org/buildinfo
POOLPATH=$BASEPATH/buildinfo-pool
mkdir -p $POOLPATH

# just in case
PROBLEMS=$(mktemp -t poolize.XXXXXXXX)

# defined for today (in UTC), might be overridden later
YEAR="$(date -u +%Y)"
MONTH="$(date -u +%m)"
DAY="$(date -u +%d)"

# process all .buildinfo files for a given day
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
				# so far we found three such cases... (out of one million .buildinfo files)
				if [ ! -e "$FULLTARGET.1" ] ; then
					ln -s $MONTHPATH/$DAY/$FILE $FULLTARGET.1
					echo "$MONTHPATH/$DAY/$FILE linked from $FULLTARGET.1"
					let COUNTER+=1
				elif [ "$(readlink -f $FULLTARGET.1)" = "$MONTHPATH/$DAY/$FILE" ] ; then
					# also ignoring this
					:
				else
					# so far we found one such case...
					if [ ! -e "$FULLTARGET.2" ] ; then
						ln -s $MONTHPATH/$DAY/$FILE $FULLTARGET.2
						echo "$MONTHPATH/$DAY/$FILE linked from $FULLTARGET.2"
						let COUNTER+=1
					elif [ "$(readlink -f $FULLTARGET.2)" = "$MONTHPATH/$DAY/$FILE" ] ; then
						# also ignoring this
						:
					else
						# so far, no such case has been found
						echo "oh no $FULLTARGET.2 also exists and thus we don't know what to do, thus ignoring." >> $PROBLEMS
						echo "$MONTHPATH/$DAY/$FILE is the source of the problem" >> $PROBLEMS
						ls -l $FULLTARGET >> $PROBLEMS
						ls -l $FULLTARGET.0 >> $PROBLEMS
						ls -l $FULLTARGET.1 >> $PROBLEMS
						ls -l $FULLTARGET.2 >> $PROBLEMS
						echo >> $PROBLEMS
					fi
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

# this takes a long time and is not run by the jenkins job but manually
loop_through_all(){
	for YEAR in $(seq 2016 2019) ; do
		for MONTH in $(seq -w 01 12) ; do
			for DAY in $(seq -w 01 31) ; do
				do_day
			done
		done
	done
}

# main
if [ -n "$1" ] && [ -z "$2" ] ; then
	# only run manually: do all days
	loop_through_all
elif [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] ; then
	# only run manually: do a specific day only
	YEAR=$1
	MONTH=$2
	DAY=$3
	do_day
else
	# normal operation: do today and do yesterday
	do_day
	YEAR="$(date -u -d '1 day ago' +%Y)"
	MONTH="$(date -u -d '1 day ago' +%m)"
	DAY="$(date -u -d '1 day ago' +%d)"
	do_day
fi

# update https://buildinfos.debian.net/buildinfo-pool.list
cd $POOLPATH
LIST=$(mktemp -t poollist.XXXXXXXX)
find . -type l |sort > $LIST
sed -i 's#^\./#https://buildinfos.debian.net/buildinfo-pool/#g' $LIST
chmod 644 $LIST
mv $LIST ../buildinfo-pool.list

# output problems from main structure above
if [ -s $PROBLEMS ] ; then
	echo "Problems found, please investigate:"
	echo
	cat $PROBLEMS
	cat $PROBLEMS >> $BASEPATH/buildinfo-problems
	rm $PROBLEMS
	exit 1
else
	rm $PROBLEMS
fi

