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
	psql --tuples-only buildinfo <<EOF > $DUMMY_FILE
SELECT DISTINCT p.source,p.version
FROM
      binary_packages p
WHERE
      p.suite='$SUITE'
EXCEPT
      SELECT p.source,p.version
FROM binary_packages p, builds b
WHERE
      b.source=p.source
      AND p.version=b.version
      AND ( (b.arch_all AND p.arch='all') OR
            (b.arch_$ARCH AND p.arch='$ARCH') )
ORDER BY source
EOF
}

#
# create buildinfo stats page
#
create_buildinfo_page() {
	VIEW=buildinfo
	PAGE=index_${VIEW}.html
	echo "$(date -u) - querying builtin-pho database for $SUITE/$ARCH."
	query_builtin_pho_db
	echo "$(date -u) - starting to write $PAGE page for $SUITE/$ARCH."
	write_page_header $VIEW "Overview of various statistics about .buildinfo files for $SUITE/$ARCH"
	write_page "<p>"
	cat $DUMMY_FILE | wc -l >> $PAGE
	write_page "packages without .buildinfo files in $SUITE/$ARCH:"
	write_page "<br/><small>ToDo: graph that count</small>"
	write_page "<br/><small>ToDo: trigger rsync job on success</small>"
	write_page "<br/><small>ToDo: link these pages from navigation</small>"
	write_page "<br/><small>ToDo: make buildinfo-pool links work with server side redirects</small>"
	write_page "</p>"
	write_page "<pre>"
	cat $DUMMY_FILE | tr -d ' '  | sed -E "s/([^|]*)(.*)/<a href=\"https:\/\/tracker.debian.org\/\1\">\1<\/a> <a href=\"https:\/\/packages.debian.org\/$SUITE\/\1\">binaries (\2)<\/a> <a href=\"https:\/\/buildinfos.debian.net\/\1\">.buildinfo<\/a>/g" | tr -d '|' >> $PAGE
	write_page "</pre>"
	# the end
	write_page_footer
	# copy to ~jenkins/builtin-pho-html/ for rsyncing to jenkins with another job
	mkdir -p ~jenkins/builtin-pho-html/debian/$SUITE/$ARCH
	echo "$(date -u) - $(cp -v $PAGE ~jenkins/builtin-pho-html/debian/$SUITE/$ARCH/)"
	rm $PAGE
	echo "$(date -u) - $REPRODUCIBLE_URL/debian/$SUITE/$ARCH/$PAGE will be updated (via rsync) after this job succeeded..."
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
