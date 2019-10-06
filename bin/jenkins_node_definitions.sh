#!/bin/bash

# Copyright 2015-2019 Holger Levsen <holger@layer-acht.org>
# released under the GPLv2

# define Debian build nodes in use for tests.reproducible-builds.org/debian/
# 	FIXME: this is used differently in two places,
#		- bin/reproducible_html_nodes_info.sh
#		  where it *must* only contain the Debian nodes as it's used
#		  to generate the variations… and
#		- bin/reproducible_cleanup_nodes.sh where it would be
#		  nice to also include pb-build9+10, to also cleanup
#		  jobs there…
BUILD_NODES="bbx15-armhf-rb.debian.net
cb3a-armhf-rb.debian.net
cbxi4a-armhf-rb.debian.net
cbxi4b-armhf-rb.debian.net
cbxi4pro0-armhf-rb.debian.net
codethink-sled9-arm64.debian.net
codethink-sled10-arm64.debian.net
codethink-sled11-arm64.debian.net
codethink-sled12-arm64.debian.net
codethink-sled13-arm64.debian.net
codethink-sled14-arm64.debian.net
codethink-sled15-arm64.debian.net
codethink-sled16-arm64.debian.net
ff2a-armhf-rb.debian.net
ff2b-armhf-rb.debian.net
ff4a-armhf-rb.debian.net
ff64a-armhf-rb.debian.net
jtk1a-armhf-rb.debian.net
jtk1b-armhf-rb.debian.net
jtx1a-armhf-rb.debian.net
jtx1b-armhf-rb.debian.net
jtx1c-armhf-rb.debian.net
odu3a-armhf-rb.debian.net
odxu4a-armhf-rb.debian.net
odxu4b-armhf-rb.debian.net
odxu4c-armhf-rb.debian.net
opi2a-armhf-rb.debian.net
opi2b-armhf-rb.debian.net
opi2c-armhf-rb.debian.net
p64b-armhf-rb.debian.net
p64c-armhf-rb.debian.net
profitbricks-build1-amd64.debian.net
profitbricks-build2-i386.debian.net
profitbricks-build5-amd64.debian.net
profitbricks-build6-i386.debian.net
profitbricks-build11-amd64.debian.net
profitbricks-build12-i386.debian.net
profitbricks-build15-amd64.debian.net
profitbricks-build16-i386.debian.net
wbq0-armhf-rb.debian.net
osuosl-build167-amd64.debian.net
osuosl-build168-amd64.debian.net
osuosl-build169-amd64.debian.net
osuosl-build170-amd64.debian.net
osuosl-build171-amd64.debian.net
osuosl-build172-amd64.debian.net
osuosl-build173-amd64.debian.net
osuosl-build174-amd64.debian.net"

NODE_RUN_IN_THE_FUTURE=false
get_node_information() {
	local NODE_NAME=$1
	case "$NODE_NAME" in
	  profitbricks-build[56]*|profitbricks-build1[56]*)
	    NODE_RUN_IN_THE_FUTURE=true
	    ;;
	  codethink-sled9*)
	    NODE_RUN_IN_THE_FUTURE=true
	    ;;
	  codethink-sled11*)
	    NODE_RUN_IN_THE_FUTURE=true
	    ;;
	  codethink-sled13*)
	    NODE_RUN_IN_THE_FUTURE=true
	    ;;
	  codethink-sled15*)
	    NODE_RUN_IN_THE_FUTURE=true
	    ;;
	  osuosl-build170*)
	    NODE_RUN_IN_THE_FUTURE=true
	    ;;
	  osuosl-build172*)
	    NODE_RUN_IN_THE_FUTURE=true
	    ;;
	  *)
	    ;;
	esac
}
