#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015-2018 Mattia Rizzolo <mattia@debian.org>
# Copyright © 2015-2017 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2

import json
import rblib
from .const import (
    ARCHS,
    SUITES,
    defaultarch,
    defaultsuite,
    log,
)
from . import query_db


class Bug:
    def __init__(self, bug):
        self.bug = bug

    def __str__(self):
        return str(self.bug)


class Issue:
    def __init__(self, name):
        self.name = name
        query = "SELECT url, description  FROM issues WHERE name='{}'"
        result = query_db(query.format(self.name))
        try:
            self.url = result[0][0]
        except IndexError:
            self.url = ''
        try:
            self.desc = result[0][0]
        except IndexError:
            self.desc = ''


class Note:
    def __init__(self, pkg, results):
        log.debug(str(results))
        self.issues = [Issue(x) for x in json.loads(results[0])]
        self.bugs = [Bug(x) for x in json.loads(results[1])]
        self.comment = results[2]


class NotedPkg:
    def __init__(self, package, suite, arch):
        self.package = package
        self.suite = suite
        self.arch = arch
        query = """
            SELECT n.issues, n.bugs, n.comments
            FROM sources AS s JOIN notes AS n ON s.id=n.package_id
            WHERE s.name='{}' AND s.suite='{}' AND s.architecture='{}'
        """
        result = query_db(query.format(self.package, self.suite, self.arch))
        try:
            result = result[0]
        except IndexError:
            self.note = None
        else:
            self.note = Note(self, result)


class Build:
    def __init__(self, package, suite, arch):
        self.package = package
        self.suite = suite
        self.arch = arch
        self.status = False
        self.version = False
        self.build_date = False
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


class Package:
    def __init__(self, name, no_notes=False):
        self.name = name
        self._status = {}
        self._load_status()
        try:
            self.status = self._status[defaultsuite][defaultarch].status
        except KeyError:
            self.status = False
        query = "SELECT notify_maintainer FROM sources WHERE name='{}'"
        try:
            result = int(query_db(query.format(self.name))[0][0])
        except IndexError:
            result = 0
        self.notify_maint = '⚑' if result == 1 else ''
        self._history = None

    @property
    def history(self):
        if self._history is None:
            self._load_history()
        return self._history

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
