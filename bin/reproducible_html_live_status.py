#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015-2017 Holger Levsen <holger@layer-acht.org>
#           © 2018      Mattia Rizzolo <mattia@mapreri.org>
# based on ~jenkins.d.n:~mattia/status.sh by Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2
#
# Depends: python3

from string import Template
from sqlalchemy import select, func, cast, Integer, and_, bindparam

from rblib import query_db, db_table
from rblib.confparse import log
from rblib.models import Package, Status
from rblib.utils import convert_into_hms_string
from rblib.html import tab, create_main_navigation, write_html_page
from reproducible_html_indexes import build_leading_text_section
from rblib.const import (
    DISTRO_BASE, DISTRO_URL, DISTRO_URI,
    ARCHS, SUITES,
    defaultsuite,
)

# sqlalchemy table definitions needed for queries
results = db_table('results')
sources = db_table('sources')
schedule = db_table('schedule')
stats_build = db_table('stats_build')

def convert_into_status_html(statusname):
    if statusname == 'None':
        return ''
    status = Status.get(statusname)
    return '{n} <img src="/static/{icon}" alt="{n}" title="{n}" />'.format(
            n=status.value.name, icon=status.value.icon)


def generate_schedule(arch):
    """ the schedule pages are very different than others index pages """
    log.info('Building the schedule index page for ' + arch + '...')
    title = 'Packages currently scheduled on ' + arch + ' for testing for build reproducibility'

    # 'AND h.name=s.name AND h.suite=s.suite AND h.architecture=s.architecture'
    # in this query and the query below is needed due to not using package_id
    # in the stats_build table, which should be fixed...
    averagesql = select([
        func.coalesce(func.avg(cast(stats_build.c.build_duration, Integer)), 0)
    ]).where(
        and_(
            stats_build.c.status.in_(('reproducible', 'FTBR')),
            stats_build.c.name == sources.c.name,
            stats_build.c.suite == sources.c.suite,
            stats_build.c.architecture == sources.c.architecture,
        )
    ).as_scalar()

    query = select([
        schedule.c.date_scheduled,
        sources.c.suite,
        sources.c.architecture,
        sources.c.name,
        results.c.status,
        results.c.build_duration,
        averagesql
    ]).select_from(
        sources.join(schedule).join(results, isouter=True)
    ).where(
        and_(
            schedule.c.date_build_started == None,
            sources.c.architecture == bindparam('arch'),
        )
    ).order_by(
        schedule.c.date_scheduled
    )

    text = Template('$tot packages are currently scheduled for testing on $arch:')
    html = ''
    rows = query_db(query.params({'arch': arch}))
    html += build_leading_text_section({'text': text}, rows, defaultsuite, arch)
    html += generate_live_status_table(arch)
    html += '<p><table class="scheduled">\n' + tab
    html += '<tr><th class="center">#</th><th class="center">scheduled at</th><th class="center">suite</th>'
    html += '<th class="center">arch</th><th class="center">source package</th><th class="center">previous build status</th><th class="center">previous build duration</th><th class="center">average build duration</th></tr>\n'
    for row in rows:
        # 0: date_scheduled, 1: suite, 2: arch, 3: pkg name 4: previous status 5: previous build duration 6. avg build duration
        pkg = row[3]
        duration = convert_into_hms_string(row[5])
        avg_duration = convert_into_hms_string(row[6])
        html += tab + '<tr><td>&nbsp;</td><td>' + row[0] + '</td>'
        html += '<td>' + row[1] + '</td><td>' + row[2] + '</td><td><code>'
        html += Package(pkg).html_link(row[1], row[2])
        html += '</code></td><td>'+convert_into_status_html(str(row[4]))+'</td><td>'+duration+'</td><td>' + avg_duration + '</td></tr>\n'
    html += '</table></p>\n'
    destfile = DISTRO_BASE + '/index_' + arch + '_scheduled.html'
    desturl = DISTRO_URL + '/index_' + arch + '_scheduled.html'
    suite_arch_nav_template = DISTRO_URI + '/index_{{arch}}_scheduled.html'
    left_nav_html = create_main_navigation(arch=arch, no_suite=True,
        displayed_page='scheduled', suite_arch_nav_template=suite_arch_nav_template)
    write_html_page(title=title, body=html, destfile=destfile, style_note=True,
                    refresh_every=60, left_nav_html=left_nav_html)
    log.info("Page generated at " + desturl)


def generate_live_status_table(arch):
    averagesql = select([
        func.coalesce(func.avg(cast(stats_build.c.build_duration, Integer)), 0)
    ]).where(
        and_(
            stats_build.c.status.in_(('reproducible', 'FTBR')),
            stats_build.c.name == sources.c.name,
            stats_build.c.suite == sources.c.suite,
            stats_build.c.architecture == sources.c.architecture,
        )
    ).as_scalar()

    query = select([
        sources.c.id,
        sources.c.suite,
        sources.c.architecture,
        sources.c.name,
        sources.c.version,
        schedule.c.date_build_started,
        results.c.status,
        results.c.build_duration,
        averagesql,
        schedule.c.job,
    ]).select_from(
        sources.join(schedule).join(results, isouter=True)
    ).where(
        and_(
            schedule.c.date_build_started != None,
            sources.c.architecture == bindparam('arch'),
        )
    ).order_by(
        schedule.c.date_scheduled
    )
    html = ''
    rows = query_db(query.params({'arch': arch}))
    html += '<p><table class="scheduled">\n' + tab
    html += '<tr><th class="center">#</th><th class="center">src pkg id</th><th class="center">suite</th><th class="center">arch</th>'
    html += '<th class=\"center\">source package</th><th class=\"center\">version</th></th>'
    html += '<th class=\"center\">build started</th><th class=\"center\">previous build status</th>'
    html += '<th class=\"center\">previous build duration</th><th class=\"center\">average build duration</th><th class=\"center\">builder job</th>'
    html += '</tr>\n'
    counter = 0
    for row in rows:
        counter += 1
        suite = row[1]
        arch = row[2]
        pkg = row[3]
        duration = convert_into_hms_string(row[7])
        avg_duration = convert_into_hms_string(row[8])
        html += tab + '<tr><td>&nbsp;</td><td>' + str(row[0]) + '</td>'
        html += '<td>' + suite + '</td><td>' + arch + '</td>'
        html += '<td><code>' + Package(pkg).html_link(suite, arch, bugs=False) + '</code></td>'
        html += '<td>' + str(row[4]) + '</td><td>' + str(row[5]) + '</td>'
        html += '<td>' + convert_into_status_html(str(row[6])) + '</td><td>' + duration + '</td><td>' + avg_duration + '</td>'
        html += '<td><a href="https://tests.reproducible-builds.org/cgi-bin/nph-logwatch?' + str(row[9]) + '">' + str(row[9]) + '</a></td>'
        html += '</tr>\n'
    html += '</table></p>\n'
    return html

def generate_oldies(arch):
    log.info('Building the oldies page for ' + arch + '...')
    title = 'Oldest results on ' + arch
    html = ''
    for suite in SUITES:
        query = select([
            sources.c.suite,
            sources.c.architecture,
            sources.c.name,
            results.c.status,
            results.c.build_date
        ]).select_from(
            results.join(sources)
        ).where(
            and_(
                sources.c.suite == bindparam('suite'),
                sources.c.architecture == bindparam('arch'),
                results.c.status != 'blacklisted'
            )
        ).order_by(
            results.c.build_date
        ).limit(15)
        text = Template('Oldest results on $suite/$arch:')
        rows = query_db(query.params({'arch': arch, 'suite': suite}))
        html += build_leading_text_section({'text': text}, rows, suite, arch)
        html += '<p><table class="scheduled">\n' + tab
        html += '<tr><th class="center">#</th><th class="center">suite</th><th class="center">arch</th>'
        html += '<th class="center">source package</th><th class="center">status</th><th class="center">build date</th></tr>\n'
        for row in rows:
            # 0: suite, 1: arch, 2: pkg name 3: status 4: build date
            pkg = row[2]
            html += tab + '<tr><td>&nbsp;</td><td>' + row[0] + '</td>'
            html += '<td>' + row[1] + '</td><td><code>'
            html += Package(pkg).html_link(row[0], row[1])
            html += '</code></td><td>'+convert_into_status_html(str(row[3]))+'</td><td>' + row[4] + '</td></tr>\n'
        html += '</table></p>\n'
    destfile = DISTRO_BASE + '/index_' + arch + '_oldies.html'
    desturl = DISTRO_URL + '/index_' + arch + '_oldies.html'
    left_nav_html = create_main_navigation(arch=arch)
    write_html_page(title=title, body=html, destfile=destfile, style_note=True,
                    refresh_every=60, left_nav_html=left_nav_html)
    log.info("Page generated at " + desturl)

if __name__ == '__main__':
    for arch in ARCHS:
        generate_schedule(arch)
        generate_oldies(arch)
