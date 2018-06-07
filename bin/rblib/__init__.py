#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015-2018 Mattia Rizzolo <mattia@debian.org>
# Copyright © 2015-2017 Holger Levsen <holger@layer-acht.org>
# Based on the reproducible_common.sh by © 2014 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# This is included by all reproducible_*.py scripts, it contains common functions

import os
import re
import sys
import csv
import json
import errno
import hashlib
import logging
import argparse
import pystache
import configparser
import html as HTML
from string import Template
from urllib.parse import urljoin
from traceback import print_exception
from subprocess import call, check_call
from tempfile import NamedTemporaryFile
from datetime import datetime, timedelta
from sqlalchemy import MetaData, Table, sql, create_engine
from sqlalchemy.exc import NoSuchTableError, OperationalError


# don't try to run on test system
if os.uname()[1] == 'jenkins-test-vm':
    sys.exit()

# temp while moving stuff around
from .confparse import *
from .const import *

# needed by the functions below
from .utils import (
    print_critical_message,
    strip_epoch,
)

def create_default_page_footer(date):
    return renderer.render(default_page_footer_template, {
            'date': date,
            'job_url': JOB_URL,
            'job_name': JOB_NAME,
            'jenkins_url': JENKINS_URL,
        })

# filter used on the index_FTBFS pages and for the reproducible.json
filtered_issues = (
    'ftbfs_in_jenkins_setup',
    'ftbfs_build_depends_not_available_on_amd64',
    'ftbfs_build-indep_not_build_on_some_archs'
)
filter_query = ''
for issue in filtered_issues:
    if filter_query == '':
        filter_query = "n.issues LIKE '%%" + issue + "%%'"
        filter_html = '<a href="' + REPRODUCIBLE_URL + ISSUES_URI + '/$suite/' + issue + '_issue.html">' + issue + '</a>'
    else:
        filter_query += " OR n.issues LIKE '%%" + issue + "%%'"
        filter_html += ' or <a href="' + REPRODUCIBLE_URL + ISSUES_URI + '/$suite/' + issue + '_issue.html">' + issue + '</a>'


class bcolors:
    BOLD = '\033[1m' if sys.stdout.isatty() else ''
    UNDERLINE = '\033[4m' if sys.stdout.isatty() else ''
    RED = '\033[91m' if sys.stdout.isatty() else ''
    GOOD = '\033[92m' if sys.stdout.isatty() else ''
    WARN = '\033[93m' + UNDERLINE if sys.stdout.isatty() else ''
    FAIL = RED + BOLD + UNDERLINE
    ENDC = '\033[0m' if sys.stdout.isatty() else ''


def gen_suite_arch_nav_context(suite, arch, suite_arch_nav_template=None,
                               ignore_experimental=False, no_suite=None,
                               no_arch=None):
    # if a template is not passed in to navigate between suite and archs the
    # current page, we use the "default" suite/arch summary view.
    default_nav_template = '/{{distro}}/{{suite}}/index_suite_{{arch}}_stats.html'
    if not suite_arch_nav_template:
        suite_arch_nav_template = default_nav_template

    suite_list = []
    if not no_suite:
        for s in SUITES:
            include_suite = True
            if s == 'experimental' and ignore_experimental:
                include_suite = False
            suite_list.append({
                's': s,
                'class': 'current' if s == suite else '',
                'uri': renderer.render(suite_arch_nav_template,
                                       {'distro': conf_distro['distro_root'],
                                        'suite': s, 'arch': arch})
                if include_suite else '',
            })

    arch_list = []
    if not no_arch:
        for a in ARCHS:
            arch_list.append({
                'a': a,
                'class': 'current' if a == arch else '',
                'uri': renderer.render(suite_arch_nav_template,
                                       {'distro': conf_distro['distro_root'],
                                        'suite': suite, 'arch': a}),
            })
    return (suite_list, arch_list)

# See bash equivelent: reproducible_common.sh's "write_page_header()"
def create_main_navigation(suite=defaultsuite, arch=defaultarch,
                           displayed_page=None, suite_arch_nav_template=None,
                           ignore_experimental=False, no_suite=None,
                           no_arch=None):
    suite_list, arch_list = gen_suite_arch_nav_context(suite, arch,
        suite_arch_nav_template, ignore_experimental, no_suite, no_arch)
    context = {
        'suite': suite,
        'arch': arch,
        'project_links_html': renderer.render(project_links_template),
        'suite_nav': {
            'suite_list': suite_list
        } if len(suite_list) else '',
        'arch_nav': {
            'arch_list': arch_list
        } if len(arch_list) else '',
        'debian_uri': DISTRO_DASHBOARD_URI,
        'cross_suite_arch_nav': True if suite_arch_nav_template else False,
    }
    if suite != 'experimental':
        # there are not package sets in experimental
        context['include_pkgset_link'] = True
    # the "display_page" argument controls which of the main page navigation
    # items will be highlighted.
    if displayed_page:
       context[displayed_page] = True
    return renderer.render(main_navigation_template, context)


def write_html_page(title, body, destfile, no_header=False, style_note=False,
                    noendpage=False, refresh_every=None, displayed_page=None,
                    left_nav_html=None):
    meta_refresh_html = '<meta http-equiv="refresh" content="%d"></meta>' % \
        refresh_every if refresh_every is not None else ''
    if style_note:
        body += renderer.render(pkg_legend_template, {})
    if not noendpage:
        now = datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')
        body += create_default_page_footer(now)
    context = {
        'page_title': title,
        'meta_refresh_html': meta_refresh_html,
        'navigation_html': left_nav_html,
        'main_header': title if not no_header else "",
        'main_html': body,
        'style_dot_css_sha1sum': REPRODUCIBLE_STYLE_SHA1,
    }
    html = renderer.render(basic_page_template, context)

    try:
        os.makedirs(destfile.rsplit('/', 1)[0], exist_ok=True)
    except OSError as e:
        if e.errno != errno.EEXIST:  # that's 'File exists' error (errno 17)
            raise
    log.debug("Writing " + destfile)
    with open(destfile, 'w', encoding='UTF-8') as fd:
        fd.write(html)


def db_table(table_name):
    """Returns a SQLAlchemy Table objects to be used in queries
    using SQLAlchemy's Expressive Language.

    Arguments:
        table_name: a string corrosponding to an existing table name
    """
    try:
        return Table(table_name, DB_METADATA, autoload=True)
    except NoSuchTableError:
        log.error("Table %s does not exist or schema for %s could not be loaded",
                  table_name, PGDATABASE)
        raise


def query_db(query, *args, **kwargs):
    """Excutes a raw SQL query. Return depends on query type.

    Returns:
        select:
            list of tuples
        update or delete:
            the number of rows affected
        insert:
            None
    """
    try:
        result = conn_db.execute(query, *args, **kwargs)
    except OperationalError as ex:
        print_critical_message('Error executing this query:\n' + query)
        raise

    if result.returns_rows:
        return result.fetchall()
    elif result.supports_sane_rowcount() and result.rowcount > -1:
        return result.rowcount
    else:
        return None


def package_has_notes(package):
    # not a really serious check, it'd be better to check the yaml file
    path = NOTES_PATH + '/' + package + '_note.html'
    if os.access(path, os.R_OK):
        return True
    else:
        return False


def link_package(package, suite, arch, bugs={}, popcon=None, is_popular=None):
    url = RB_PKG_URI + '/' + suite + '/' + arch + '/' + package + '.html'
    query = """SELECT n.issues, n.bugs, n.comments
               FROM notes AS n JOIN sources AS s ON s.id=n.package_id
               WHERE s.name='{pkg}' AND s.suite='{suite}'
               AND s.architecture='{arch}'"""
    css_classes = []
    if is_popular:
        css_classes += ["package-popular"]
    title = ''
    if popcon is not None:
        title += 'popcon score: ' + str(popcon) + '\n'
    try:
        notes = query_db(query.format(pkg=package, suite=suite, arch=arch))[0]
    except IndexError:  # no notes for this package
        css_classes += ["package"]
    else:
        css_classes += ["noted"]
        for issue in json.loads(notes[0]):
            title += issue + '\n'
        for bug in json.loads(notes[1]):
            title += '#' + str(bug) + '\n'
        if notes[2]:
            title += notes[2]
    html = '<a href="' + url + '" class="' + ' '.join(css_classes) \
         + '" title="' + HTML.escape(title.strip()) + '">' + package + '</a>' \
         + get_trailing_icon(package, bugs) + '\n'
    return html


def link_packages(packages, suite, arch, bugs=None):
    if bugs is None:
        bugs = get_bugs()
    html = ''
    for pkg in packages:
        html += link_package(pkg, suite, arch, bugs)
    return html


def get_status_icon(status):
    table = {'reproducible' : 'weather-clear.png',
             'FTBFS': 'weather-storm.png',
             'FTBR' : 'weather-showers-scattered.png',
             '404': 'weather-severe-alert.png',
             'depwait': 'weather-snow.png',
             'not for us': 'weather-few-clouds-night.png',
             'not_for_us': 'weather-few-clouds-night.png',
             'untested': 'weather-clear-night.png',
             'blacklisted': 'error.png'}
    spokenstatus = status
    if status == 'unreproducible':
            status = 'FTBR'
    elif status == 'not for us':
            status = 'not_for_us'
    try:
        return (status, table[status], spokenstatus)
    except KeyError:
        log.error('Status ' + status + ' not recognized')
        return (status, '', spokenstatus)


def gen_status_link_icon(status, spokenstatus, icon, suite, arch):
    """
    Returns the html for "<icon> <spokenstatus>" with both icon and status
    linked to the appropriate index page for the status, arch and suite.

    If icon is set to None, the icon will be ommited.
    If spokenstatus is set to None, the spokenstatus link be ommited.
    """
    context = {
        'status': status,
        'spokenstatus': spokenstatus,
        'icon': icon,
        'suite': suite,
        'arch': arch,
        'untested': True if status == 'untested' else False,
    }
    return renderer.render(status_icon_link_template, context)


def pkg_has_buildinfo(package, version=False, suite=defaultsuite, arch=defaultarch):
    """
    if there is no version specified it will use the version listed in
    reproducible db
    """
    if not version:
        query = """SELECT r.version
                   FROM results AS r JOIN sources AS s ON r.package_id=s.id
                   WHERE s.name='{}' AND s.suite='{}' AND s.architecture='{}'"""
        query = query.format(package, suite, arch)
        version = str(query_db(query)[0][0])
    buildinfo = BUILDINFO_PATH + '/' + suite + '/' + arch + '/' + package + \
                '_' + strip_epoch(version) + '_' + arch + '.buildinfo'
    if os.access(buildinfo, os.R_OK):
        return True
    else:
        return False


def pkg_has_rbuild(package, version=False, suite=defaultsuite, arch=defaultarch):
    if not version:
        query = """SELECT r.version
                   FROM results AS r JOIN sources AS s ON r.package_id=s.id
                   WHERE s.name='{}' AND s.suite='{}' AND s.architecture='{}'"""
        query = query.format(package, suite, arch)
        version = str(query_db(query)[0][0])
    rbuild = RBUILD_PATH + '/' + suite + '/' + arch + '/' + package + '_' + \
             strip_epoch(version) + '.rbuild.log'
    if os.access(rbuild, os.R_OK):
        return (rbuild, os.stat(rbuild).st_size)
    elif os.access(rbuild+'.gz', os.R_OK):
        return (rbuild+'.gz', os.stat(rbuild+'.gz').st_size)
    else:
        return ()


def get_trailing_icon(package, bugs):
    html = ''
    if package in bugs:
        for bug in bugs[package]:
            html += '<a href="https://bugs.debian.org/{bug}">'.format(bug=bug)
            html += '<span class="'
            if bugs[package][bug]['done']:
                html += 'bug-done" title="#' + str(bug) + ', done">#</span>'
            elif bugs[package][bug]['pending']:
                html += 'bug-pending" title="#' + str(bug) + ', pending">P</span>'
            elif bugs[package][bug]['patch']:
                html += 'bug-patch" title="#' + str(bug) + ', with patch">+</span>'
            else:
                html += 'bug" title="#' + str(bug) + '">#</span>'
            html += '</a>'
    return html


def get_trailing_bug_icon(bug, bugs, package=None):
    html = ''
    if not package:
        for pkg in bugs.keys():
            if get_trailing_bug_icon(bug, bugs, pkg):
                return get_trailing_bug_icon(bug, bugs, pkg)
    else:
        try:
            if bug in bugs[package].keys():
                html += '<span class="'
                if bugs[package][bug]['done']:
                    html += 'bug-done" title="#' + str(bug) + ', done">#'
                elif bugs[package][bug]['pending']:
                    html += 'bug-pending" title="#' + str(bug) + ', pending">P'
                elif bugs[package][bug]['patch']:
                    html += 'bug-patch" title="#' + str(bug) + ', with patch">+'
                else:
                    html += 'bug">'
                html += '</span>'
        except KeyError:
            pass
    return html


from .models import *
