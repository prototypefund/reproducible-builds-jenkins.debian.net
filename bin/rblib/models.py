#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015-2018 Mattia Rizzolo <mattia@debian.org>
# Copyright © 2015-2017 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2

import json
import functools
from urllib.parse import urljoin

from .const import (
    ARCHS,
    SUITES,
    defaultarch,
    defaultsuite,
    log,
    RB_PKG_URI,
)
from .bugs import Bugs
from . import query_db


def lazyproperty(fn):
    attr_name = '_' + fn.__name__

    @property
    @functools.wraps(fn)
    def _lazy(self):
        if not hasattr(self, attr_name):
            fn(self)
        return getattr(self, attr_name)

    return _lazy


class Bug:
    def __init__(self, bug):
        self.bug = bug

    def __str__(self):
        return str(self.bug)


class Issue:
    def __init__(self, name):
        self.name = name

    @lazyproperty
    def url(self):
        self._set()

    @lazyproperty
    def desc(self):
        self._set()

    def _set(self):
        query = "SELECT url, description  FROM issues WHERE name='{}'"
        result = query_db(query.format(self.name))
        try:
            self._url = result[0][0]
        except IndexError:
            self._url = ''
        try:
            self._desc = result[0][1]
        except IndexError:
            self._desc = ''


class Note:
    def __init__(self, pkg, results):
        self.issues = [Issue(x) for x in json.loads(results[0])]
        self.bugs = [Bug(x) for x in json.loads(results[1])]
        self.comment = results[2]


class Build:
    def __init__(self, package, suite, arch):
        self.package = package
        self.suite = suite
        self.arch = arch
        self._status = False
        self._version = False
        self._build_date = False

    @lazyproperty
    def status(self):
        self._get_package_status()

    @lazyproperty
    def version(self):
        self._get_package_status()

    @lazyproperty
    def build_date(self):
        self._get_package_status()

    def _get_package_status(self):
        try:
            query = """SELECT r.status, r.version, r.build_date
                       FROM results AS r JOIN sources AS s
                       ON r.package_id=s.id WHERE s.name='{}'
                       AND s.architecture='{}' AND s.suite='{}'"""
            query = query.format(self.package, self.arch, self.suite)
            result = query_db(query)[0]
        except IndexError:  # not tested, look whether it actually exists
            query = """SELECT version FROM sources WHERE name='{}'
                       AND suite='{}' AND architecture='{}'"""
            query = query.format(self.package, self.suite, self.arch)
            try:
                result = query_db(query)[0][0]
                if result:
                    result = ('untested', str(result), False)
            except IndexError:  # there is no package with this name in this
                return          # suite/arch, or none at all
        self.status = str(result[0])
        self.version = str(result[1])
        if result[2]:
            self.build_date = str(result[2]) + ' UTC'

    @lazyproperty
    def note(self):
        query = """
            SELECT n.issues, n.bugs, n.comments
            FROM sources AS s JOIN notes AS n ON s.id=n.package_id
            WHERE s.name='{}' AND s.suite='{}' AND s.architecture='{}'
        """
        result = query_db(query.format(self.package, self.suite, self.arch))
        try:
            result = result[0]
        except IndexError:
            self._note = None
        else:
            self._note = Note(self, result)


class Package:
    def __init__(self, name, no_notes=False):
        self.name = name
        self._status = {}
        self._load_status()
        try:
            self.status = self._status[defaultsuite][defaultarch].status
            self.note = self._status[defaultsuite][defaultarch].note
        except KeyError:
            self.status = False
            self.note = False
        query = "SELECT notify_maintainer FROM sources WHERE name='{}'"
        try:
            result = int(query_db(query.format(self.name))[0][0])
        except IndexError:
            result = 0
        self.notify_maint = '⚑' if result == 1 else ''
        self._history = None

    @lazyproperty
    def history(self):
        self._load_history()

    def _load_status(self):
        for suite in SUITES:
            self._status[suite] = {}
            for arch in ARCHS:
                self._status[suite][arch] = Build(self.name, suite, arch)

    def _load_history(self):
        self._history = []
        keys = [
            'build ID', 'version', 'suite', 'architecture', 'result',
            'build date', 'build duration', 'node1', 'node2', 'job',
            'schedule message'
        ]
        query = """
                SELECT id, version, suite, architecture, status, build_date,
                    build_duration, node1, node2, job
                FROM stats_build WHERE name='{}' ORDER BY build_date DESC
            """.format(self.name)
        results = query_db(query)
        for record in results:
            self._history.append(dict(zip(keys, record)))

    def get_status(self, suite, arch):
        """ This returns False if the package does not exists in this suite """
        try:
            return self._status[suite][arch].status
        except KeyError:
            return False

    def get_build_date(self, suite, arch):
        """ This returns False if the package does not exists in this suite """
        try:
            return self._status[suite][arch].build_date
        except KeyError:
            return False

    def get_tested_version(self, suite, arch):
        """ This returns False if the package does not exists in this suite """
        try:
            return self._status[suite][arch].version
        except KeyError:
            return False

    def html_link(self, suite, arch, bugs=False, popcon=None, is_popular=None):
        url = '/'.join((RB_PKG_URI, suite, arch, self.name+'.html'))
        css_classes = []
        title = ''
        if is_popular:
            css_classes.append('package-popular')
        if popcon is not None:
            title += 'popcon score: {}\n'.format(popcon)
        notes = self._status[suite][arch].note
        if notes is None:
            css_classes.append('package')
        else:
            css_classes.append('noted')
            title += '\n'.join([x.name for x in notes.issues]) + '\n'
            title += '\n'.join([str(x.bug) for x in notes.bugs]) + '\n'
            if notes.comment:
                title += notes.comment
        html = '<a href="{url}" class="{cls}" title="{title}">{pkg}</a>{icon}\n'
        bug_icon = Bugs().get_trailing_icon(self.name) if bugs else ''
        return html.format(url=url, cls=' '.join(css_classes),
                           title=title, pkg=self.name, icon=bug_icon)
