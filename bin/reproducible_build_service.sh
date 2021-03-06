#!/bin/bash
# vim: set noexpandtab:

# Copyright © 2017-2018 Holger Levsen (holger@layer-acht.org)
# released under the GPLv2

set -e

# those should be global variables
NODE1=""
NODE2=""

#
# this function defines which builds take place on which nodes
#
choose_nodes() {
	case $1 in
		#
		# amd64, i386 and arm64 nodes are chosen in a way that one build always runs
		# on a node running in the future, the other on a node with correct date.
		# armhf builds are distributed by the build capacity of the nodes, see below.
		#
		amd64_1)	NODE1=profitbricks-build1-amd64		NODE2=profitbricks-build5-amd64 ;;
		amd64_2)	NODE1=profitbricks-build5-amd64		NODE2=profitbricks-build1-amd64 ;;
		amd64_3)	NODE1=profitbricks-build1-amd64		NODE2=profitbricks-build15-amd64 ;;
		amd64_4)	NODE1=profitbricks-build15-amd64	NODE2=profitbricks-build1-amd64 ;;
		amd64_5)	NODE1=profitbricks-build11-amd64	NODE2=profitbricks-build5-amd64 ;;
		amd64_6)	NODE1=profitbricks-build5-amd64		NODE2=profitbricks-build11-amd64 ;;
		amd64_7)	NODE1=profitbricks-build11-amd64	NODE2=profitbricks-build15-amd64 ;;
		amd64_8)	NODE1=profitbricks-build15-amd64	NODE2=profitbricks-build11-amd64 ;;
		amd64_9)	NODE1=profitbricks-build1-amd64		NODE2=profitbricks-build5-amd64 ;;
		amd64_10)	NODE1=profitbricks-build5-amd64		NODE2=profitbricks-build1-amd64 ;;
		amd64_11)	NODE1=profitbricks-build1-amd64		NODE2=profitbricks-build15-amd64 ;;
		amd64_12)	NODE1=profitbricks-build15-amd64	NODE2=profitbricks-build1-amd64 ;;
		amd64_13)	NODE1=profitbricks-build11-amd64	NODE2=profitbricks-build5-amd64 ;;
		amd64_14)	NODE1=profitbricks-build5-amd64		NODE2=profitbricks-build11-amd64 ;;
		amd64_15)	NODE1=profitbricks-build11-amd64	NODE2=profitbricks-build15-amd64 ;;
		amd64_16)	NODE1=profitbricks-build15-amd64	NODE2=profitbricks-build11-amd64 ;;
		amd64_17)	NODE1=profitbricks-build1-amd64		NODE2=profitbricks-build5-amd64 ;;
		amd64_18)	NODE1=profitbricks-build5-amd64		NODE2=profitbricks-build1-amd64 ;;
		amd64_19)	NODE1=profitbricks-build1-amd64		NODE2=profitbricks-build15-amd64 ;;
		amd64_20)	NODE1=profitbricks-build15-amd64	NODE2=profitbricks-build1-amd64 ;;
		amd64_21)	NODE1=profitbricks-build11-amd64	NODE2=profitbricks-build5-amd64 ;;
		amd64_22)	NODE1=profitbricks-build5-amd64		NODE2=profitbricks-build11-amd64 ;;
		amd64_23)	NODE1=profitbricks-build11-amd64	NODE2=profitbricks-build15-amd64 ;;
		amd64_24)	NODE1=profitbricks-build15-amd64	NODE2=profitbricks-build11-amd64 ;;
		amd64_25)	NODE1=profitbricks-build1-amd64		NODE2=profitbricks-build5-amd64 ;;
		amd64_26)	NODE1=profitbricks-build5-amd64		NODE2=profitbricks-build1-amd64 ;;
		amd64_27)	NODE1=profitbricks-build1-amd64		NODE2=profitbricks-build15-amd64 ;;
		amd64_28)	NODE1=profitbricks-build15-amd64	NODE2=profitbricks-build1-amd64 ;;
		amd64_29)	NODE1=profitbricks-build11-amd64	NODE2=profitbricks-build5-amd64 ;;
		amd64_30)	NODE1=profitbricks-build5-amd64		NODE2=profitbricks-build11-amd64 ;;
		amd64_31)	NODE1=profitbricks-build11-amd64	NODE2=profitbricks-build15-amd64 ;;
		amd64_32)	NODE1=profitbricks-build15-amd64	NODE2=profitbricks-build11-amd64 ;;
		#amd64_33)	NODE1=profitbricks-build1-amd64		NODE2=profitbricks-build5-amd64 ;;
		#amd64_34)	NODE1=profitbricks-build5-amd64		NODE2=profitbricks-build1-amd64 ;;
		#amd64_35)	NODE1=profitbricks-build1-amd64		NODE2=profitbricks-build15-amd64 ;;
		#amd64_36)	NODE1=profitbricks-build15-amd64	NODE2=profitbricks-build1-amd64 ;;
		#amd64_37)	NODE1=profitbricks-build11-amd64	NODE2=profitbricks-build5-amd64 ;;
		#amd64_38)	NODE1=profitbricks-build5-amd64		NODE2=profitbricks-build11-amd64 ;;
		#amd64_39)	NODE1=profitbricks-build11-amd64	NODE2=profitbricks-build15-amd64 ;;
		#amd64_40)	NODE1=profitbricks-build15-amd64	NODE2=profitbricks-build11-amd64 ;;

		# i386
		i386_1)		NODE1=profitbricks-build2-i386	NODE2=profitbricks-build6-i386 ;;
		i386_2)		NODE1=profitbricks-build6-i386	NODE2=profitbricks-build2-i386 ;;
		i386_3)		NODE1=profitbricks-build2-i386	NODE2=profitbricks-build16-i386 ;;
		i386_4)		NODE1=profitbricks-build16-i386	NODE2=profitbricks-build2-i386 ;;
		i386_5)		NODE1=profitbricks-build12-i386	NODE2=profitbricks-build6-i386 ;;
		i386_6)		NODE1=profitbricks-build6-i386	NODE2=profitbricks-build12-i386 ;;
		i386_7)		NODE1=profitbricks-build12-i386	NODE2=profitbricks-build16-i386 ;;
		i386_8)		NODE1=profitbricks-build16-i386	NODE2=profitbricks-build12-i386 ;;
		i386_9)		NODE1=profitbricks-build2-i386	NODE2=profitbricks-build6-i386 ;;
		i386_10)	NODE1=profitbricks-build6-i386	NODE2=profitbricks-build2-i386 ;;
		i386_11)	NODE1=profitbricks-build2-i386	NODE2=profitbricks-build16-i386 ;;
		i386_12)	NODE1=profitbricks-build16-i386	NODE2=profitbricks-build2-i386 ;;
		i386_13)	NODE1=profitbricks-build12-i386	NODE2=profitbricks-build6-i386 ;;
		i386_14)	NODE1=profitbricks-build6-i386	NODE2=profitbricks-build12-i386 ;;
		i386_15)	NODE1=profitbricks-build12-i386	NODE2=profitbricks-build16-i386 ;;
		i386_16)	NODE1=profitbricks-build16-i386	NODE2=profitbricks-build12-i386 ;;
		i386_17)	NODE1=profitbricks-build2-i386	NODE2=profitbricks-build6-i386 ;;
		i386_18)	NODE1=profitbricks-build6-i386	NODE2=profitbricks-build2-i386 ;;
		i386_19)	NODE1=profitbricks-build2-i386	NODE2=profitbricks-build16-i386 ;;
		i386_20)	NODE1=profitbricks-build16-i386	NODE2=profitbricks-build2-i386 ;;
		i386_21)	NODE1=profitbricks-build12-i386	NODE2=profitbricks-build6-i386 ;;
		i386_22)	NODE1=profitbricks-build6-i386	NODE2=profitbricks-build12-i386 ;;
		i386_23)	NODE1=profitbricks-build12-i386	NODE2=profitbricks-build16-i386 ;;
		i386_24)	NODE1=profitbricks-build16-i386	NODE2=profitbricks-build12-i386 ;;

		# arm64
		arm64_1)	NODE1=codethink-sled9-arm64		NODE2=codethink-sled10-arm64 ;;
		arm64_2)	NODE1=codethink-sled9-arm64		NODE2=codethink-sled12-arm64 ;;
		arm64_3)	NODE1=codethink-sled9-arm64		NODE2=codethink-sled14-arm64 ;;
		arm64_4)	NODE1=codethink-sled9-arm64		NODE2=codethink-sled16-arm64 ;;
		arm64_5)	NODE1=codethink-sled10-arm64	NODE2=codethink-sled9-arm64 ;;
		arm64_6)	NODE1=codethink-sled10-arm64	NODE2=codethink-sled11-arm64 ;;
		arm64_7)	NODE1=codethink-sled10-arm64	NODE2=codethink-sled13-arm64 ;;
		arm64_8)	NODE1=codethink-sled10-arm64	NODE2=codethink-sled15-arm64 ;;
		arm64_9)	NODE1=codethink-sled11-arm64	NODE2=codethink-sled10-arm64 ;;
		arm64_10)	NODE1=codethink-sled11-arm64	NODE2=codethink-sled12-arm64 ;;
		arm64_11)	NODE1=codethink-sled11-arm64	NODE2=codethink-sled14-arm64 ;;
		arm64_12)	NODE1=codethink-sled11-arm64	NODE2=codethink-sled16-arm64 ;;
		arm64_13)	NODE1=codethink-sled12-arm64	NODE2=codethink-sled9-arm64 ;;
		arm64_14)	NODE1=codethink-sled12-arm64	NODE2=codethink-sled11-arm64 ;;
		arm64_15)	NODE1=codethink-sled12-arm64	NODE2=codethink-sled13-arm64 ;;
		arm64_16)	NODE1=codethink-sled12-arm64	NODE2=codethink-sled15-arm64 ;;
		arm64_17)	NODE1=codethink-sled13-arm64	NODE2=codethink-sled10-arm64 ;;
		arm64_18)	NODE1=codethink-sled13-arm64	NODE2=codethink-sled12-arm64 ;;
		arm64_19)	NODE1=codethink-sled13-arm64	NODE2=codethink-sled14-arm64 ;;
		arm64_20)	NODE1=codethink-sled13-arm64	NODE2=codethink-sled16-arm64 ;;
		arm64_21)	NODE1=codethink-sled14-arm64	NODE2=codethink-sled9-arm64 ;;
		arm64_22)	NODE1=codethink-sled14-arm64	NODE2=codethink-sled11-arm64 ;;
		arm64_23)	NODE1=codethink-sled14-arm64	NODE2=codethink-sled13-arm64 ;;
		arm64_24)	NODE1=codethink-sled14-arm64	NODE2=codethink-sled15-arm64 ;;
		arm64_25)	NODE1=codethink-sled15-arm64	NODE2=codethink-sled10-arm64 ;;
		arm64_26)	NODE1=codethink-sled15-arm64	NODE2=codethink-sled12-arm64 ;;
		arm64_27)	NODE1=codethink-sled15-arm64	NODE2=codethink-sled14-arm64 ;;
		arm64_28)	NODE1=codethink-sled15-arm64	NODE2=codethink-sled16-arm64 ;;
		arm64_29)	NODE1=codethink-sled16-arm64	NODE2=codethink-sled9-arm64 ;;
		arm64_30)	NODE1=codethink-sled16-arm64	NODE2=codethink-sled11-arm64 ;;
		arm64_31)	NODE1=codethink-sled16-arm64	NODE2=codethink-sled13-arm64 ;;
		arm64_32)	NODE1=codethink-sled16-arm64	NODE2=codethink-sled15-arm64 ;;
		# to choose new armhf jobs:
            #   for i in cb3a bbx15 cbxi4pro0 ff2a ff2b ff64a jtk1a jtk1b odxu4a odxu4b odxu4c odu3a opi2a opi2b opi2c p64b p64c wbq0 cbxi4a cbxi4b ff4a jtx1a jtx1b jtx1c; do echo "$i: " ; grep NODE1 bin/reproducible_build_service.sh|grep armhf|grep $i-armhf ; done
	        #       6 jobs for quad-cores with 4 gb ram
	        #       4 jobs for octo-cores with 2 gb ram
	        #       4 jobs for hexa-cores with 2 gb ram
	        #       4 jobs for quad-cores with 2 gb ram
	        #       4 jobs for dual-cores with 2 gb ram
		#
		# Don't forget to update README with the number of builders…!
		#
		armhf_1)	NODE1=bbx15-armhf-rb		NODE2=jtx1a-armhf-rb ;;
		armhf_2)	NODE1=bbx15-armhf-rb		NODE2=ff4a-armhf-rb ;;
		armhf_3)	NODE1=cb3a-armhf-rb			NODE2=jtx1a-armhf-rb ;;
		armhf_4)	NODE1=cb3a-armhf-rb			NODE2=jtx1c-armhf-rb ;;
		armhf_5)	NODE1=cbxi4a-armhf-rb		NODE2=p64c-armhf-rb ;;
		armhf_6)	NODE1=jtx1a-armhf-rb		NODE2=ff4a-armhf-rb ;;
		armhf_7)	NODE1=ff4a-armhf-rb			NODE2=cbxi4b-armhf-rb ;;
		armhf_8)	NODE1=ff64a-armhf-rb		NODE2=cbxi4a-armhf-rb ;;
		armhf_9)	NODE1=ff64a-armhf-rb		NODE2=cbxi4pro0-armhf-rb ;;
		armhf_10)	NODE1=cbxi4pro0-armhf-rb	NODE2=ff4a-armhf-rb ;;
		armhf_11)	NODE1=cbxi4pro0-armhf-rb	NODE2=jtx1a-armhf-rb ;;
		armhf_12)	NODE1=ff2a-armhf-rb			NODE2=wbq0-armhf-rb ;;
		armhf_13)	NODE1=ff2a-armhf-rb			NODE2=p64c-armhf-rb ;;
		armhf_14)	NODE1=ff2b-armhf-rb			NODE2=p64b-armhf-rb ;;
		armhf_15)	NODE1=ff2b-armhf-rb			NODE2=opi2c-armhf-rb ;;
		armhf_16)	NODE1=jtx1b-armhf-rb		NODE2=p64b-armhf-rb ;;
		armhf_17)	NODE1=jtx1b-armhf-rb		NODE2=jtk1b-armhf-rb ;;
		armhf_18)	NODE1=jtk1b-armhf-rb		NODE2=opi2c-armhf-rb ;;
		armhf_19)	NODE1=jtk1b-armhf-rb		NODE2=opi2b-armhf-rb ;;
		armhf_20)	NODE1=odxu4a-armhf-rb		NODE2=jtk1b-armhf-rb ;;
		armhf_21)	NODE1=odxu4a-armhf-rb		NODE2=opi2a-armhf-rb ;;
		armhf_22)	NODE1=odxu4b-armhf-rb		NODE2=odu3a-armhf-rb ;;
		armhf_24)	NODE1=odxu4c-armhf-rb		NODE2=jtx1c-armhf-rb ;;
		armhf_26)	NODE1=odu3a-armhf-rb		NODE2=odxu4a-armhf-rb ;;
		armhf_27)	NODE1=odu3a-armhf-rb		NODE2=jtx1b-armhf-rb ;;
		armhf_28)	NODE1=opi2a-armhf-rb		NODE2=odxu4c-armhf-rb ;;
		armhf_29)	NODE1=opi2a-armhf-rb		NODE2=cbxi4b-armhf-rb ;;
		armhf_30)	NODE1=opi2b-armhf-rb		NODE2=odxu4c-armhf-rb ;;
		armhf_31)	NODE1=opi2b-armhf-rb		NODE2=jtx1b-armhf-rb ;;
		armhf_32)	NODE1=opi2c-armhf-rb		NODE2=odxu4b-armhf-rb ;;
		armhf_33)	NODE1=opi2c-armhf-rb		NODE2=ff2a-armhf-rb ;;
		armhf_34)	NODE1=p64b-armhf-rb			NODE2=odxu4b-armhf-rb ;;
		armhf_35)	NODE1=p64b-armhf-rb			NODE2=ff2a-armhf-rb ;;
		armhf_36)	NODE1=p64c-armhf-rb			NODE2=ff2b-armhf-rb ;;
		armhf_37)	NODE1=p64c-armhf-rb			NODE2=cbxi4pro0-armhf-rb ;;
		armhf_38)	NODE1=wbq0-armhf-rb			NODE2=ff2b-armhf-rb ;;
		armhf_39)	NODE1=wbq0-armhf-rb			NODE2=cbxi4a-armhf-rb ;;
		armhf_40)	NODE1=cbxi4a-armhf-rb		NODE2=jtx1b-armhf-rb ;;
		armhf_41)	NODE1=cbxi4a-armhf-rb		NODE2=cb3a-armhf-rb ;;
		armhf_42)	NODE1=cbxi4b-armhf-rb		NODE2=bbx15-armhf-rb ;;
		armhf_43)	NODE1=cbxi4b-armhf-rb		NODE2=cb3a-armhf-rb ;;
		armhf_44)	NODE1=cbxi4b-armhf-rb		NODE2=ff64a-armhf-rb ;;
		armhf_45)	NODE1=ff4a-armhf-rb			NODE2=jtk1a-armhf-rb ;;
		armhf_46)	NODE1=ff4a-armhf-rb			NODE2=jtx1c-armhf-rb ;;
		armhf_47)	NODE1=jtx1a-armhf-rb		NODE2=cbxi4b-armhf-rb ;;
		armhf_48)	NODE1=jtx1a-armhf-rb		NODE2=odxu4a-armhf-rb ;;
		armhf_49)	NODE1=jtx1b-armhf-rb		NODE2=bbx15-armhf-rb ;;
		armhf_50)	NODE1=jtx1c-armhf-rb		NODE2=jtk1a-armhf-rb ;;
		armhf_51)	NODE1=jtx1c-armhf-rb		NODE2=cbxi4a-armhf-rb ;;
		armhf_52)	NODE1=jtx1c-armhf-rb		NODE2=odu3a-armhf-rb ;;
		armhf_53)	NODE1=jtk1a-armhf-rb		NODE2=wbq0-armhf-rb ;;
		armhf_54)	NODE1=jtk1a-armhf-rb		NODE2=ff64a-armhf-rb ;;
		*)		NODE1=undefined
				;;
	esac
}

startup_workers() {
	#
	# loop through all archs
	#
	for ARCH in amd64 i386 arm64 armhf ; do
		case $ARCH in
			amd64)	MAX=32 ;;
			i386)	MAX=16 ;;
			arm64)	MAX=32 ;;
			armhf)	MAX=59 ;;
			*)	;;
		esac
		#
		# startup as many workers as defined above
		#
		for i in $(seq 1 $MAX) ; do
			#
		        # sleep up to 2.3 seconds (additionally to the random sleep reproducible_build.sh does anyway)
			#
		        /bin/sleep $(echo "scale=1 ; $(shuf -i 1-23 -n 1)/10" | bc )

			#
			# continue loop if the worker to be started is already running
			#
			WORKER_NAME=${ARCH}_$i
			WORKER_BIN=/srv/jenkins/bin/reproducible_worker.sh
			RUNNING=$(ps fax|grep -v grep|grep "$WORKER_BIN $WORKER_NAME" 2>/dev/null||true)
			if [ ! -z "$RUNNING" ] ; then
				echo "$(date --utc) - '$(basename $WORKER_BIN) $WORKER_NAME' already running, thus moving on to the next."
				continue
			fi

			#
			# actually start the worker
			#
			choose_nodes $WORKER_NAME
			if [ "$NODE1" != "undefined" ] ; then
				BUILD_BASE=/var/lib/jenkins/userContent/reproducible/debian/build_service/$WORKER_NAME
				mkdir -p $BUILD_BASE
				echo "$(date --utc) - Starting $WORKER_NAME"
				$WORKER_BIN $WORKER_NAME $NODE1 $NODE2 >$BUILD_BASE/worker.log 2>&1 &
			fi
		done
	done
}

#
# main, keep running forever…
#
while true ; do
	#
	# this is all we do
	#
	startup_workers
	#
	# now sleep, but allow wakeup calls
	#
	set +e
	sleep 133.7m
	set -e
done


