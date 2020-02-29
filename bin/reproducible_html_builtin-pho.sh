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

# ToDo:
# - create graphs
# - import the data from the database on pb7 into the one on jenkins
# - fix off by one error
# - include data for stretch and experimental

get_localsuite() {
	if [ "$SUITE" = "unstable" ] ; then
		LOCALSUITE="sid"
	else
		LOCALSUITE=$SUITE
	fi
}

sed_db_output_to_html() {
	cat $1 | tr -d ' '  | sed -E "s/([^|]*)(.*)/<a href=\"https:\/\/tracker.debian.org\/\1\">\1<\/a> <a href=\"https:\/\/packages.debian.org\/$SUITE\/\1\">binaries (\2)<\/a> <a href=\"https:\/\/buildinfos.debian.net\/\1\">.buildinfo<\/a>/g" | tr -d '|' > $2

}

query_builtin_pho_db_hits() {
	psql --tuples-only buildinfo <<EOF > $RAW_HITS
SELECT DISTINCT p.source,p.version
FROM
      binary_packages p, builds b
WHERE
      p.suite='$LOCALSUITE'
      AND b.source=p.source
      AND p.version=b.version
      AND ( (b.arch_all AND p.arch='all') OR
            (b.arch_$ARCH AND p.arch='$ARCH') )
ORDER BY source
EOF
	sed_db_output_to_html $RAW_HITS $HTML_HITS
	HITS=$(cat $RAW_HITS | wc -l)
}

query_builtin_pho_db_misses() {
	psql --tuples-only buildinfo <<EOF > $RAW_MISSES
SELECT DISTINCT p.source,p.version
FROM
      binary_packages p
WHERE
      p.suite='$LOCALSUITE'
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
	sed_db_output_to_html $RAW_MISSES $HTML_MISSES
	MISSES=$(cat $RAW_MISSES | wc -l)
}

#
# create buildinfo stats page
#
create_buildinfos_page() {
	VIEW=buildinfos
	PAGE=index_${VIEW}.html
	echo "$(date -u) - starting to write $PAGE page for $SUITE/$ARCH."
	write_page_header $VIEW "Overview of .buildinfo files for $SUITE/$ARCH"
	write_page "<p>"
	write_page "$HITS sources with .buildinfo files found:"
	write_page "<br/><small>(While we also know about $MISSES sources without .buildinfo files in $SUITE/$ARCH.)</small></p>"
	write_page "<pre>"
	cat $HTML_HITS >> $PAGE
	write_page "</pre>"
	# the end
	write_page_footer
	# copy to ~jenkins/builtin-pho-html/ for rsyncing to jenkins with another job
	mkdir -p ~jenkins/builtin-pho-html/debian/$SUITE/$ARCH
	cp $PAGE ~jenkins/builtin-pho-html/debian/$SUITE/$ARCH/
	rm $PAGE
	echo "$(date -u) - $REPRODUCIBLE_URL/debian/$SUITE/$ARCH/$PAGE will be updated (via rsync) after this job succeeded..."
}

#
# create no buildinfo stats page
#
create_no_buildinfos_page() {
	VIEW=no_buildinfos
	PAGE=index_${VIEW}.html
	echo "$(date -u) - starting to write $PAGE page for $SUITE/$ARCH."
	write_page_header $VIEW "Overview of missing .buildinfo files for $SUITE/$ARCH"
	write_page "<p>"
	write_page "$MISSES sources without .buildinfo files found:"
	write_page "<br/><small>(While we also know about $HITS sources with .buildinfo files in $SUITE/$ARCH.)</small></p>"
	write_page "<pre>"
	cat $HTML_MISSES >> $PAGE
	write_page "</pre>"
	# the end
	write_page_footer
	# copy to ~jenkins/builtin-pho-html/ for rsyncing to jenkins with another job
	mkdir -p ~jenkins/builtin-pho-html/debian/$SUITE/$ARCH
	cp -v $PAGE ~jenkins/builtin-pho-html/debian/$SUITE/$ARCH/
	rm $PAGE
	echo "$(date -u) - $REPRODUCIBLE_URL/debian/$SUITE/$ARCH/$PAGE will be updated (via rsync) after this job succeeded..."
}

#
# main
#
RAW_HITS=$(mktemp -t reproducible-builtin-pho-XXXXXXXX)
RAW_MISSES=$(mktemp -t reproducible-builtin-pho-XXXXXXXX)
HTML_HITS=$(mktemp -t reproducible-builtin-pho-XXXXXXXX)
HTML_MISSES=$(mktemp -t reproducible-builtin-pho-XXXXXXXX)
HITS=0
MISSES=0
LOCALSUITE=""
for ARCH in ${ARCHS} ; do
	for SUITE in $SUITES ; do
		get_localsuite
		query_builtin_pho_db_hits
		query_builtin_pho_db_misses
		create_buildinfos_page
		create_no_buildinfos_page
	done
done
rm -f $RAW_HITS $RAW_MISSES $HTML_HITS $HTML_MISSES
