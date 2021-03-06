#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015-2018 Mattia Rizzolo <mattia@maprerii.org>
# Copyright © 2015-2016 Holger Levsen <holger@layer-acht.org>
# Based on reproducible_html_indexes.sh © 2014 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3
#
# Build quite all index_* pages

import sys
from string import Template
from datetime import datetime, timedelta
from sqlalchemy import select, and_, or_, func, bindparam, desc

from rblib import query_db, db_table
from rblib.confparse import log
from rblib.models import Status, Package
from rblib.utils import print_critical_message
from rblib.html import tab, create_main_navigation, write_html_page
from rblib.const import (
    DISTRO, DISTRO_BASE, DISTRO_URI, DISTRO_URL,
    SUITES, ARCHS,
    defaultsuite, defaultarch,
    filtered_issues, filter_html,
)

"""
Reference doc for the folowing lists:

* queries is just a list of queries. They are referred further below.
  + every query must return only a list of package names (excpet count_total)
* pages is just a list of pages. It is actually a dictionary, where every
  element is a page. Every page has:
  + `title`: The page title
  + `header`: (optional) sane html to be printed on top of the page
  + `header_query`: (optional): the output of this query is put inside "tot" of
    the string above
  + `body`: a list of dicts containing every section that made up the page.
    Every section has:
    - `icon_status`: the name of a icon (see rblib.models.Status)
    - `icon_link`: a link to hide below the icon
    - `query`: query to perform against the reproducible db to get the list of
      packages to show
    - `text` a string. Template instance with $tot (total of packages listed)
      and $percent (percentage of all packages)
    - `timespan`: value set to '24' or '48' to enable to add $count, $count_total.
      $timespan_cound and $timespan_percent to the text, where:
      * $percent becomes count/count_total
      * $count_total being the number of all tested packages
      * $count being the len() of the query indicated by `query2`
      * $timespan_count is the number of packages tested in that timespan in hours
      * $timespan_percent is the percentage of $query in that timespan
    - `query2`: useful only if `timespan` is set to a value.
    - `nosuite`: if true do not iterate over the suite/archs, use only the
      current suite+arch
  + global: if true, then the page will saved on the root of rb.d.n, and:
    - the query also takes the value "status"
    - force the suite/arch to the defaults
  + notes: if true the query also takes the value "status"


Technically speaking, a page can be empty (we all love nonsense) but every
section must have at least a `query` defining what to file in.
"""

timespan_date_map = {}
timespan_date_map[24] = (datetime.now()-timedelta(hours=24)).strftime('%Y-%m-%d %H:%M')
timespan_date_map[48] = (datetime.now()-timedelta(hours=48)).strftime('%Y-%m-%d %H:%M')

# sqlalchemy table definitions needed for queries
distributions = db_table('distributions')
results = db_table('results')
sources = db_table('sources')
notes = db_table('notes')

# filtered_issues is defined in reproducible_common.py and
# can be used to excludes some FTBFS issues
filter_issues_list = []
for issue in filtered_issues:
    filter_issues_list.append(notes.c.issues.contains(issue))
if not filtered_issues:
    filter_issues_list = [None]

distro_id = query_db(select([distributions.c.id]).where(distributions.c.name == DISTRO))[0][0]

count_results = select(
    [func.count(results.c.id)]
).select_from(
    results.join(sources)
).where(
    and_(
        sources.c.distribution == distro_id,
        sources.c.suite == bindparam('suite'),
        sources.c.architecture == bindparam('arch')
    )
)

select_sources = select(
    [sources.c.name]
).select_from(
    results.join(sources)
).where(
    and_(
        sources.c.distribution == distro_id,
        sources.c.suite == bindparam('suite'),
        sources.c.architecture == bindparam('arch')
    )
)

queries = {
    "count_total": count_results,
    "count_timespan":
        count_results.where(
                results.c.build_date > bindparam('timespan_date'),
        ),
    "reproducible_all":
        select_sources.where(
            results.c.status == Status.REPRODUCIBLE.value.name,
        ).order_by(
            desc(results.c.build_date)
        ),
    "reproducible_last24h":
        select_sources.where(
            and_(
                results.c.status == Status.REPRODUCIBLE.value.name,
                results.c.build_date > timespan_date_map[24],
            )
        ).order_by(
            desc(results.c.build_date)
        ),
    "reproducible_last48h":
        select_sources.where(
            and_(
                results.c.status == Status.REPRODUCIBLE.value.name,
                results.c.build_date > timespan_date_map[48],
            )
        ).order_by(
            desc(results.c.build_date)
        ),
    "reproducible_all_abc":
        select_sources.where(
            results.c.status == Status.REPRODUCIBLE.value.name,
        ).order_by(
            sources.c.name
        ),
    "FTBR_all":
        select_sources.where(
            results.c.status == Status.FTBR.value.name
        ).order_by(
            desc(results.c.build_date)
        ),
    "FTBR_last24h":
        select_sources.where(
            and_(
                results.c.status == Status.FTBR.value.name,
                results.c.build_date > timespan_date_map[24],
            )
        ).order_by(
            desc(results.c.build_date)
        ),
    "FTBR_last48h":
        select_sources.where(
            and_(
                results.c.status == Status.FTBR.value.name,
                results.c.build_date > timespan_date_map[48],
            )
        ).order_by(
            desc(results.c.build_date)
        ),
    "FTBR_all_abc":
        select_sources.where(
            results.c.status == Status.FTBR.value.name
        ).order_by(
            sources.c.name
        ),
    "FTBFS_all":
        select_sources.where(
            results.c.status == Status.FTBFS.value.name,
        ).order_by(
            desc(results.c.build_date)
        ),
    "FTBFS_last24h":
        select_sources.where(
            and_(
                results.c.status == Status.FTBFS.value.name,
                results.c.build_date > timespan_date_map[24],
            )
        ).order_by(
            desc(results.c.build_date)
        ),
    "FTBFS_last48h":
        select_sources.where(
            and_(
                results.c.status == Status.FTBFS.value.name,
                results.c.build_date > timespan_date_map[48],
            )
        ).order_by(
            desc(results.c.build_date)
        ),
    "FTBFS_all_abc":
        select_sources.where(
            results.c.status == Status.FTBFS.value.name,
        ).order_by(
            sources.c.name
        ),
    "FTBFS_filtered":
        select_sources.where(
            and_(
                results.c.status == Status.FTBFS.value.name,
                sources.c.id.notin_(
                    select(
                        [notes.c.package_id]
                    ).select_from(
                        notes
                    ).where(
                        or_(*filter_issues_list)
                    )
                )
            )
        ).order_by(
            desc(results.c.build_date)
        ),
    "FTBFS_caused_by_us":
        select_sources.where(
            and_(
                results.c.status == Status.FTBFS.value.name,
                sources.c.id.in_(
                    select(
                        [notes.c.package_id]
                    ).select_from(
                        notes
                    ).where(
                        or_(*filter_issues_list)
                    )
                )
            )
        ).order_by(
            desc(results.c.build_date)
        ),
    "E404_all":
        select_sources.where(
            results.c.status == Status.E404.value.name,
        ).order_by(
            desc(results.c.build_date)
        ),
    "E404_all_abc":
        select_sources.where(
            results.c.status == Status.E404.value.name,
        ).order_by(
            sources.c.name
        ),
    "depwait_all":
        select_sources.where(
            results.c.status == Status.DEPWAIT.value.name,
        ).order_by(
            desc(results.c.build_date)
        ),
    "depwait_all_abc":
        select_sources.where(
            results.c.status == Status.DEPWAIT.value.name,
        ).order_by(
            sources.c.name
        ),
    "depwait_last24h":
        select_sources.where(
            and_(
                results.c.status == Status.DEPWAIT.value.name,
                results.c.build_date > timespan_date_map[24],

            )
        ).order_by(
            desc(results.c.build_date)
        ),
    "depwait_last48h":
        select_sources.where(
            and_(
                results.c.status == Status.DEPWAIT.value.name,
                results.c.build_date > timespan_date_map[48],
            )
        ).order_by(
            desc(results.c.build_date)
        ),
    "timeout_all":
        select_sources.where(
            and_(
                results.c.status == Status.TIMEOUT.value.name
            )
        ).order_by(
            sources.c.name
        ),
    "not_for_us_all":
        select_sources.where(
            and_(
                results.c.status == Status.NFU.value.name
            )
        ).order_by(
            sources.c.name
        ),
    "blacklisted_all":
        select_sources.where(
            results.c.status == Status.BLACKLISTED.value.name,
        ).order_by(
            sources.c.name
        ),
    "notes":
        select(
            [sources.c.name]
        ).select_from(
            sources.join(results).join(notes)
        ).where(
            and_(
                sources.c.distribution == distro_id,
                results.c.status == bindparam('status'),
                sources.c.suite == bindparam('suite'),
                sources.c.architecture == bindparam('arch')
            )
        ).order_by(
            desc(results.c.build_date)
        ),
    "no_notes":
        select_sources.where(
            and_(
                results.c.status == bindparam('status'),
                sources.c.id.notin_(select([notes.c.package_id]).select_from(notes))
            )
        ).order_by(
            desc(results.c.build_date)
        ),
    "notification":
        select_sources.where(
            and_(
                results.c.status == bindparam('status'),
                sources.c.notify_maintainer == 1
            )
        ).order_by(
            desc(results.c.build_date)
        ),
}

pages = {
    'reproducible': {
        'title': 'Packages in {suite}/{arch} which built reproducibly',
        'body': [
            {
                'icon_status': Status.REPRODUCIBLE.value.icon,
                'icon_link': '/index_reproducible.html',
                'query': 'reproducible_all',
                'text': Template('$tot ($percent%) packages which built reproducibly in $suite/$arch:')
            }
        ]
    },
    'FTBR': {
        'title': 'Packages in {suite}/{arch} which failed to build reproducibly',
        'body': [
            {
                'icon_status': Status.FTBR.value.icon,
                'query': 'FTBR_all',
                'text': Template('$tot ($percent%) packages which failed to build reproducibly in $suite/$arch:')
            }
        ]
    },
    'FTBFS': {
        'title': 'Packages in {suite}/{arch} which failed to build from source',
        'body': [
            {
                'icon_status': Status.FTBFS.value.icon,
                'query': 'FTBFS_filtered',
                'text': Template('$tot ($percent%) packages which failed to build from source in $suite/$arch: (this list is filtered and only shows unexpected ftbfs issues - see the list below for expected failures.)')
            },
            {
                'icon_status': Status.FTBFS.value.icon,
                'query': 'FTBFS_caused_by_us',
                'text': Template('$tot ($percent%) packages which failed to build from source in $suite/$arch due to our changes in the toolchain or due to our setup.\n This list includes packages tagged ' + filter_html + '.'),
            }
        ]
    },
    '404': {
        'title': 'Packages in {suite}/{arch} where the sources failed to download',
        'body': [
            {
                'icon_status': Status.E404.value.icon,
                'query': 'E404_all',
                'text': Template('$tot ($percent%) packages where the sources failed to download in $suite/$arch:')
            }
        ]
    },
    'depwait': {
        'title': 'Packages in {suite}/{arch} where the build dependencies failed to be satisfied',
        'body': [
            {
                'icon_status': Status.DEPWAIT.value.icon,
                'query': 'depwait_all',
                'text': Template('$tot ($percent%) packages where the build dependencies failed to be satisfied. Note that temporary failures (eg. due to network problems) are automatically rescheduled every 4 hours.')
            }
        ]
    },
    'not_for_us': {
        'title': 'Packages in {suite}/{arch} which should not be build on "{arch}"',
        'body': [
            {
                'icon_status': Status.NFU.value.icon,
                'query': 'not_for_us_all',
                'text': Template('$tot ($percent%) packages which should not be build in $suite/$arch:')
            }
        ]
    },
    'timeout': {
        'title': 'Packages in {suite}/{arch} where the build timed out',
        'body': [
            {
                'icon_status': Status.TIMEOUT.value.icon,
                'query': 'timeout_all',
                'text': Template('$tot ($percent%) packages where the build timed out:')
            }
        ]
    },
    'blacklisted': {
        'title': 'Packages in {suite}/{arch} which have been blacklisted',
        'body': [
            {
                'icon_status': Status.BLACKLISTED.value.icon,
                'query': 'blacklisted_all',
                'text': Template('$tot ($percent%) packages which have been blacklisted in $suite/$arch: (If you see packages listed here without a bug filed against them, it \'s probably a good idea to file one.)')
            }
        ]
    },
    'all_abc': {
        'title': 'Alphabetically sorted overview of all tested packages in {suite}/{arch}',
        'body': [
            {
                'icon_status': Status.FTBR.value.icon,
                'icon_link': '/index_unreproducible.html',
                'query': 'FTBR_all_abc',
                'text': Template('$tot packages ($percent%) failed to build reproducibly in total in $suite/$arch:')
            },
            {
                'icon_status': Status.FTBFS.value.icon,
                'icon_link': '/index_FTBFS.html',
                'query': 'FTBFS_all_abc',
                'text': Template('$tot packages ($percent%) failed to build from source in total $suite/$arch:')
            },
            {
                'icon_status': Status.NFU.value.icon,
                'icon_link': '/index_not_for_us.html',
                'query': 'not_for_us_all',
                'text': Template('$tot ($percent%) packages which should not be build in $suite/$arch:')
            },
            {
                'icon_status': Status.TIMEOUT.value.icon,
                'icon_lnk': '/index_timeout.html',
                'query': 'timeout_all',
                'text': Template('$tot ($percent%) packages which build timed out in $suite/$arch:')
            },
            {
                'icon_status': Status.E404.value.icon,
                'icon_link': '/index_404.html',
                'query': 'E404_all_abc',
                'text': Template('$tot ($percent%) source packages could not be downloaded in $suite/$arch:')
            },
            {
                'icon_status': Status.DEPWAIT.value.icon,
                'icon_link': '/index_depwait.html',
                'query': 'depwait_all_abc',
                'text': Template('$tot ($percent%) source packages failed to satisfy their build-dependencies:')
            },
            {
                'icon_status': Status.BLACKLISTED.value.icon,
                'icon_link': '/index_blacklisted.html',
                'query': 'blacklisted_all',
                'text': Template('$tot ($percent%) packages are blacklisted and will not be tested in $suite/$arch:')
            },
            {
                'icon_status': Status.REPRODUCIBLE.value.icon,
                'icon_link': '/index_reproducible.html',
                'query': 'reproducible_all_abc',
                'text': Template('$tot ($percent%) packages successfully built reproducibly in $suite/$arch:')
            },
        ]
    },
    'last_24h': {
        'title': 'Packages in {suite}/{arch} tested in the last 24h for build reproducibility',
        'body': [
            {
                'icon_status': Status.FTBR.value.icon,
                'icon_link': '/index_unreproducible.html',
                'query': 'FTBR_last24h',
                'query2': 'FTBR_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to build reproducibly in total, $tot ($timespan_percent% of $timespan_count) of them in the last 24h in $suite/$arch:'),
                'timespan': 24
            },
            {
                'icon_status': Status.FTBFS.value.icon,
                'icon_link': '/index_FTBFS.html',
                'query': 'FTBFS_last24h',
                'query2': 'FTBFS_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to build from source in total, $tot ($timespan_percent% of $timespan_count) of them  in the last 24h in $suite/$arch:'),
                'timespan': 24
            },
            {
                'icon_status': Status.DEPWAIT.value.icon,
                'icon_link': '/index_depwait.html',
                'query': 'depwait_last24h',
                'query2': 'depwait_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to satisfy their build-dependencies, $tot ($timespan_percent% of $timespan_count) of them  in the last 24h in $suite/$arch:'),
                'timespan': 24
            },
            {
                'icon_status': Status.REPRODUCIBLE.value.icon,
                'icon_link': '/index_reproducible.html',
                'query': 'reproducible_last24h',
                'query2': 'reproducible_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'successfully built reproducibly in total, $tot ($timespan_percent% of $timespan_count) of them in the last 24h in $suite/$arch:'),
                'timespan': 24
            },
        ]
    },
    'last_48h': {
        'title': 'Packages in {suite}/{arch} tested in the last 48h for build reproducibility',
        'body': [
            {
                'icon_status': Status.FTBR.value.icon,
                'icon_link': '/index_unreproducible.html',
                'query': 'FTBR_last48h',
                'query2': 'FTBR_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to build reproducibly in total, $tot ($timespan_percent% of $timespan_count) of them in the last 48h in $suite/$arch:'),
                'timespan': 48
            },
            {
                'icon_status': Status.FTBFS.value.icon,
                'icon_link': '/index_FTBFS.html',
                'query': 'FTBFS_last48h',
                'query2': 'FTBFS_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to build from source in total, $tot ($timespan_percent% of $timespan_count) of them  in the last 48h in $suite/$arch:'),
                'timespan': 48
            },
            {
                'icon_status': Status.DEPWAIT.value.icon,
                'icon_link': '/index_depwait.html',
                'query': 'depwait_last48h',
                'query2': 'depwait_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'failed to satisfy their build-dependencies, $tot ($timespan_percent% of $timespan_count) of them  in the last 48h in $suite/$arch:'),
                'timespan': 48
            },
            {
                'icon_status': Status.REPRODUCIBLE.value.icon,
                'icon_link': '/index_reproducible.html',
                'query': 'reproducible_last48h',
                'query2': 'reproducible_all',
                'text': Template('$count packages ($percent% of ${count_total}) ' +
                                 'successfully built reproducibly in total, $tot ($timespan_percent% of $timespan_count) of them in the last 48h in $suite/$arch:'),
                'timespan': 48
            },
        ]
    },
    'notes': {
        'notes': True,
        'title': 'Packages with notes',
        'header': '<p>There are {tot} packages with notes in {suite}/{arch}.</p>',
        'header_query': "SELECT count(*) FROM (SELECT s.name FROM sources AS s JOIN notes AS n ON n.package_id=s.id WHERE s.distribution={distro} AND s.suite='{suite}' AND s.architecture='{arch}' GROUP BY s.name) AS tmp",
        'body': [
            {
                'status': Status.FTBR,
                'icon_link': '/index_FTBR.html',
                'query': 'notes',
                'nosuite': True,
                'text': Template('$tot unreproducible packages in $suite/$arch, ordered by build date:')
            },
            {
                'status': Status.FTBFS,
                'icon_link': '/index_FTBFS.html',
                'query': 'notes',
                'nosuite': True,
                'text': Template('$tot FTBFS packages in $suite/$arch, ordered by build date:')
            },
            {
                'status': Status.DEPWAIT,
                'icon_link': '/index_depwait.html',
                'query': 'depwait_all_abc',
                'text': Template('$tot ($percent%) source packages failed to satisfy their build-dependencies, ordered by build date:')
            },
            {
                'status': Status.NFU,
                'icon_link': '/index_not_for_us.html',
                'query': 'notes',
                'nosuite': True,
                'text': Template('$tot not for us packages in $suite/$arch:')
            },
            {
                'status': Status.TIMEOUT,
                'icon_link': '/index_timeout.html',
                'query': 'notes',
                'nosuite': True,
                'text': Template('$tot timing out packages in $suite/$arch:')
            },
            {
                'status': Status.BLACKLISTED,
                'icon_link': '/index_blacklisted.html',
                'query': 'notes',
                'nosuite': True,
                'text': Template('$tot blacklisted packages in $suite/$arch:')
            },
            {
                'status': Status.REPRODUCIBLE,
                'icon_link': '/index_reproducible.html',
                'query': 'notes',
                'nosuite': True,
                'text': Template('$tot reproducible packages in $suite/$arch:')
            }
        ]
    },
    'no_notes': {
        'notes': True,
        'notes_hint': True,
        'title': 'Packages without notes',
        'header': '<p>There are {tot} faulty packages without notes in {suite}/{arch}.{hint}</p>',
        'header_query': "SELECT COUNT(*) FROM (SELECT s.id FROM sources AS s JOIN results AS r ON r.package_id=s.id WHERE s.distribution={distro} AND r.status IN ('FTBR', 'FTBFS', 'blacklisted') AND s.id NOT IN (SELECT package_id FROM notes) AND s.suite='{suite}' AND s.architecture='{arch}') AS tmp",
        'body': [
            {
                'status': Status.FTBR,
                'icon_link': '/index_FTBR.html',
                'query': 'no_notes',
                'text': Template('$tot unreproducible packages in $suite/$arch, ordered by build date:')
            },
            {
                'status': Status.FTBFS,
                'icon_link': '/index_FTBFS.html',
                'query': 'no_notes',
                'text': Template('$tot FTBFS packages in $suite/$arch, ordered by build date:')
            },
            {
                'status': Status.BLACKLISTED,
                'icon_link': '/index_blacklisted.html',
                'query': 'no_notes',
                'text': Template('$tot blacklisted packages in $suite/$arch, ordered by name:')
            }
        ]
    },
    'notify': {
        'global': True,
        'limit': ['debian'],
        'notes': True,
        'nosuite': True,
        'title': 'Packages with notification enabled',
        'header': '<p>The following {tot} packages have notifications enabled. (This page only shows packages in {suite}/{arch} though notifications are send for these packages in unstable and experimental in all tested architectures.) On status changes (e.g. reproducible → unreproducible) the system notifies the maintainer and relevant parties via an email to $srcpackage@packages.debian.org. Notifications are collected and send once a day to avoid flooding.<br />Please ask us to enable notifications for your package(s) in our IRC channel #debian-reproducible or via <a href="mailto:reproducible-builds@lists.alioth.debian.org">mail</a> - but ask your fellow team members first if they want to receive such notifications.</p>',
        'header_query': "SELECT COUNT(*) FROM sources WHERE distribution={distro} AND suite='{suite}' AND architecture='{arch}' AND notify_maintainer = 1",
        'body': [
            {
                'status': Status.FTBR,
                'icon_link': '/index_FTBR.html',
                'query': 'notification',
                'text': Template('$tot unreproducible packages in $suite/$arch:'),
                'nosuite': True
            },
            {
                'status': Status.FTBFS,
                'icon_link': '/index_FTBFS.html',
                'query': 'notification',
                'text': Template('$tot FTBFS packages in $suite/$arch:'),
                'nosuite': True
            },
            {
                'status': Status.REPRODUCIBLE,
                'icon_link': '/index_reproducible.html',
                'query': 'notification',
                'text': Template('$tot reproducible packages in $suite/$arch:'),
                'nosuite': True
            }
        ]
    }
}


def build_leading_text_section(section, rows, suite, arch):
    html = '<p>\n' + tab
    total = len(rows)
    count_total = int(query_db(queries['count_total'].params({'suite': suite, 'arch': arch}))[0][0])
    try:
        percent = round(((total/count_total)*100), 1)
    except ZeroDivisionError:
        log.error('Looks like there are either no tested package or no ' +
                  'packages available at all. Maybe it\'s a new database?')
        percent = 0.0
    try:
        html += '<a href="' + section['icon_link'] + '" target="_parent">'
        no_icon_link = False
    except KeyError:
        no_icon_link = True  # to avoid closing the </a> tag below
    if section.get('icon_status'):
        html += '<img src="/static/' + section['icon_status']
        html += '" alt="reproducible icon" />'
    if not no_icon_link:
        html += '</a>'
    html += '\n' + tab
    if section.get('text') and section.get('timespan'):
        count = len(query_db(queries[section['query2']].params(
            {'suite': suite, 'arch': arch})))
        percent = round(((count/count_total)*100), 1)
        timespan = section['timespan']
        timespan_date = timespan_date_map[timespan]
        timespan_count = int(query_db(queries['count_timespan'].params(
            {'suite': suite, 'arch': arch, 'timespan_date': timespan_date}))[0][0])
        try:
            timespan_percent = round(((total/timespan_count)*100), 1)
        except ZeroDivisionError:
            log.error('Looks like there are either no tested package or no ' +
                      'packages available at all. Maybe it\'s a new database?')
            timespan_percent = 0

        html += section['text'].substitute(tot=total, percent=percent,
                                           timespan_percent=timespan_percent,
                                           timespan_count=timespan_count,
                                           count_total=count_total,
                                           count=count, suite=suite, arch=arch)
    elif section.get('text'):
        html += section['text'].substitute(tot=total, percent=percent,
                                           suite=suite, arch=arch)
    else:
        log.warning('There is no text for this section')
    html += '\n</p>\n'
    return html


def build_page_section(page, section, suite, arch):
    try:
        if pages[page].get('global') and pages[page]['global']:
            suite = defaultsuite
            arch = defaultarch
        if pages[page].get('notes') and pages[page]['notes']:
            db_status = section['status'].value.name
            query = queries[section['query']].params({
                'status': db_status,
                'suite': suite, 'arch': arch
            })
            section['icon_status'] = section['status'].value.icon
        else:
            query = queries[section['query']].params({'suite': suite, 'arch': arch})
        rows = query_db(query)
    except:
        print_critical_message('A query failed: %s' % query)
        raise
    html = ''
    footnote = True if rows else False
    if not rows: # there are no package in this set, do not output anything
        log.debug('empty query: %s' %
            query.compile(compile_kwargs={"literal_binds": True}))
        return (html, footnote)
    html += build_leading_text_section(section, rows, suite, arch)
    html += '<p>\n' + tab + '<code>\n'
    for row in rows:
        pkg = row[0]
        html += tab*2 + Package(pkg).html_link(suite, arch)
    else:
        html += tab + '</code>\n'
        html += '</p>'
    if section.get('bottom'):
        html += section['bottom']
    html = (tab*2).join(html.splitlines(True))
    return (html, footnote)


def build_page(page, suite=None, arch=None):
    if 'limit' in pages[page] and DISTRO not in pages[page]['limit']:
        return
    gpage = False
    if pages[page].get('global') and pages[page]['global']:
        gpage = True
        suite = defaultsuite
        arch = defaultarch
    if not gpage and suite and not arch:
        print_critical_message('The architecture was not specified while ' +
                               'building a suite-specific page.')
        sys.exit(1)
    if gpage:
        log.debug('Building the ' + page + ' global index page...')
        title = pages[page]['title']
    else:
        log.debug('Building the ' + page + ' index page for ' + suite + '/' +
                 arch + '...')
        title = pages[page]['title'].format(suite=suite, arch=arch)
    page_sections = pages[page]['body']
    html = ''
    footnote = False
    if pages[page].get('header'):
        if pages[page].get('notes_hint') and pages[page]['notes_hint'] and suite == defaultsuite:
            hint = ' <em>These</em> are the packages with failures that <em>still need to be investigated</em>.'
        else:
            hint = ''
        if pages[page].get('header_query'):
            result = query_db(pages[page]['header_query'].format(distro=distro_id, suite=suite, arch=arch))
            html += pages[page]['header'].format(tot=result[0][0], suite=suite, arch=arch, hint=hint)
        else:
            html += pages[page].get('header')
    for section in page_sections:
        if gpage:
            if section.get('nosuite') and section['nosuite']:  # only defaults
                html += build_page_section(page, section, suite, arch)[0]
            else:
                for suite in SUITES:
                    for arch in ARCHS:
                        log.debug('global page §' + section['status'].name +
                                  ' in ' + page + ' for ' + suite + '/' + arch)
                        html += build_page_section(page, section, suite, arch)[0]
            footnote = True
        else:
            html1, footnote1 = build_page_section(page, section, suite, arch)
            html += html1
            footnote = True if footnote1 else footnote
    suite_arch_nav_template = None
    if gpage:
        destfile = DISTRO_BASE + '/index_' + page + '.html'
        desturl = DISTRO_URL + '/index_' + page + '.html'
        suite = defaultsuite  # used for the links in create_main_navigation
    else:
        destfile = DISTRO_BASE + '/' + suite + '/' + arch + '/index_' + \
                   page + '.html'
        desturl = DISTRO_URL + '/' + suite + '/' + arch + '/index_' + \
                  page + '.html'
        suite_arch_nav_template = DISTRO_URI + '/{{suite}}/{{arch}}/index_' + \
                                  page + '.html'
    left_nav_html = create_main_navigation(
        suite=suite,
        arch=arch,
        displayed_page=page,
        suite_arch_nav_template=suite_arch_nav_template,
    )
    write_html_page(title=title, body=html, destfile=destfile, style_note=True,
                    left_nav_html=left_nav_html)
    log.info('"' + title + '" now available at ' + desturl)


if __name__ == '__main__':
    for arch in ARCHS:
        for suite in SUITES:
            for page in pages.keys():
                if 'global' not in pages[page] or not pages[page]['global']:
                    build_page(page, suite, arch)
    for page in pages.keys():
        if 'global' in  pages[page] and pages[page]['global']:
            build_page(page)
