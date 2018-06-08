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
from .bugs import Bugs

# needed by the functions below
from .utils import (
    print_critical_message,
    strip_epoch,
)

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
