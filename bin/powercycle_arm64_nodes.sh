#!/bin/bash
# vim: set noexpandtab:

# Copyright 2019 Holger Levsen <holger@layer-acht.org>
# released under the GPLv2

# validate input
for i in $@ ; do
	case $i in
		9|10|11|12|13|14|15|16)	: ;;
		*) 	echo 'invalid parameter.'
			exit 1
			;;
	esac
done

# delegate work
ssh jumpserv.colo.codethink.co.uk ./sled-power-cycle.sh $@
