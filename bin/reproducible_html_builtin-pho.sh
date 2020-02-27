#!/bin/bash
# vim: set noexpandtab:

# Copyright 2020 Holger Levsen <holger@layer-acht.org>
# released under the GPLv2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code for tests.reproducible-builds.org
. /srv/jenkins/bin/reproducible_common.sh

#
# Many thanks to David Bremner for https://salsa.debian.org/bremner/builtin-pho.git
# on which this relies.
#

query_builtin_pho_db() {
	if [ "$SUITE" = "unstable" ] ; then
		local SUITE="sid"
	else
		local SUITE=$SUITE
	fi
 
	psql buildinfo <<EOF > $DUMMY_FILE
select distinct p.source,p.version
from
      binary_packages p
where
      p.suite='$SUITE'
except
        select p.source,p.version
from binary_packages p, builds b
where
      b.source=p.source
      and p.version=b.version
      and ( (b.arch_all and p.arch='all') or
            (b.arch_$ARCH and p.arch='$ARCH') )
order by p.source
EOF
}

#
# create buildinfo stats page
#
create_buildinfo_page() {
	VIEW=buildinfo
	PAGE=index_${VIEW}.html
	echo "$(date -u) - starting to write $PAGE page for $SUITE/$ARCH."
	write_page_header $VIEW "Overview of various statistics about .buildinfo files for $SUITE/$ARCH"
	write_page "<p>Packages without .buildinfo files in $SUITE/$ARCH:"
	write_page "<br/><small>ToDo: turn package names/versions into useful links</small>"
	write_page "</p>"
	query_builtin_pho_db
	write_page "<pre>"
	cat $DUMMY_FILE >> $PAGE
	write_page "</pre>"
	# the end
	write_page_footer
	# copy to ~jenkins/builtin-pho-html/ for rsyncing to jenkins with another job
	mkdir -p ~jenkins/builtin-pho-html/debian/$SUITE/$ARCH
	echo "$(date -u) - $(cp -v $PAGE ~jenkins/builtin-pho-html/debian/$SUITE/$ARCH/)"
	rm $PAGE
	echo "$(date -u) - $REPRODUCIBLE_URL/debian/$SUITE/$ARCH/$PAGE will be updated (via rsync) in 10min roughly..."
}

#
# main
#
DUMMY_FILE=$(mktemp -t reproducible-builtin-pho-XXXXXXXX)
for ARCH in ${ARCHS} ; do
	for SUITE in $SUITES ; do
		create_buildinfo_page
	done
done
rm -f $DUMMY_FILE
