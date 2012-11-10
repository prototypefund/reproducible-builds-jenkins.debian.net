#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

set -x
set -e
export LC_ALL=C
export MIRROR=http://ftp.de.debian.org/debian
export http_proxy="http://localhost:3128"
export

init_workspace() {
	#
	# clean
	#
	rm -fv *.deb *.dsc *_*.build *_*.changes *_*.tar.gz

	#
	# svn checkout and update is done by jenkins job
	#
	svn status
}

pdebuild_package() {
	#
	# prepare build
	#
	if [ -f /var/base.tgz ] ; then
		sudo pbuilder --create
	else
		sudo pbuilder --update
	fi

	#
	# build
	#
	cd manual
	pdebuild
}

build_language() {
	FORMAT=$2
	mkdir $FORMAT
	cd manual/build
	ARCHS=$(ls arch-options)
	for ARCH in $ARCHS ; do 
		make languages=$1 architectures=$ARCH destination=../../$FORMAT/ formats=$FORMAT
	done
}

init_workspace
#
# if $1 is not given, build the whole manual,
# else just the language $1 as html
#
if [ "$1" = "" ] ; then
	pdebuild_package
else
	build_language $1 html
fi
