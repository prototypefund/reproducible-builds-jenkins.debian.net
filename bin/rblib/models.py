# -*- coding: utf-8 -*-
#
# Copyright © 2015-2018 Mattia Rizzolo <mattia@debian.org>
# Copyright © 2015-2017 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2

import os
import json
import os.path
import functools
import html as HTML

from .const import (
    ARCHS,
    SUITES,
    defaultarch,
    defaultsuite,
    RB_PKG_URI,
    BUILDINFO_PATH, BUILDINFO_URI,
    RBUILD_PATH, RBUILD_URI,
)
from .bugs import Bugs
from .utils import strip_epoch
from . import query_db


def lazyproperty(fn):
    attr_name = '_l_' + fn.__name__

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
            self._l_url = result[0][0]
        except IndexError:
            self._l_url = ''
        try:
            self._l_desc = result[0][1]
        except IndexError:
            self._l_desc = ''


class Note:
    def __init__(self, pkg, results):
        self.issues = [Issue(x) for x in json.loads(results[0])]
        self.bugs = [Bug(x) for x in json.loads(results[1])]
        self.comment = results[2]


class Build:
    class __file:
        def __init__(self, pkg, path_templ, url_templ,
                     filename, formatter=None):
            fmt = {
                'pkg': pkg.package,
                'eversion': strip_epoch(pkg.version),
                'arch': pkg.arch,
                'suite': pkg.suite,
            }
            if formatter is not None:
                fmt = {**fmt, **formatter}
            if 'file' not in fmt:
                fmt['file'] = filename.format_map(fmt)
            self.path = path_templ.format_map(fmt)
            self.url = url_templ.format_map(fmt)

        def __bool__(self):
            return os.access(self.path, os.R_OK)

        @property
        def size(self):
            return os.stat(self.path).st_size

    def __init__(self, package, suite, arch):
        self.package = package
        self.suite = suite
        self.arch = arch

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
                    result = ('untested', str(result), None)
            except IndexError:  # there is no package with this name in this
                result = (None, None, None)  # suite/arch, or none at all
        self._l_status = result[0]
        self._l_version = result[1]
        self._l_build_date = str(result[2]) + ' UTC' if result[2] else None

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
            self._l_note = None
        else:
            self._l_note = Note(self, result)

    @lazyproperty
    def buildinfo(self):
        filename = '{pkg}_{eversion}_{arch}.buildinfo'
        path = os.path.join(BUILDINFO_PATH, self.suite, self.arch, filename)
        url = BUILDINFO_URI + '/{suite}/{arch}/{file}'
        self._l_buildinfo = self.__file(self, path, url, filename)

    @lazyproperty
    def rbuild(self):
        filename = '{pkg}_{eversion}.rbuild.log.gz'
        path = os.path.join(RBUILD_PATH, self.suite, self.arch, filename)
        url = RBUILD_URI + '/{suite}/{arch}/{file}'
        self._l_rbuild = self.__file(self, path, url, filename)



class _Package_cache:
    __singleton = {}

    def __init__(self):
        self.__dict__ = self.__singleton
        if not self.__singleton:
            self._cache = {}

    def get(self, pkgname):
        try:
            return self._cache[pkgname]
        except KeyError:
            self._cache[pkgname] = {}
            return self._cache[pkgname]


class Package:
    def __init__(self, name, no_notes=False):
        self.__dict__ = _Package_cache().get(name)
        self.name = name

    @lazyproperty
    def builds(self):
        self._l_builds = {}
        for suite in SUITES:
            self._l_builds[suite] = {}
            for arch in ARCHS:
                self._l_builds[suite][arch] = Build(self.name, suite, arch)

    @lazyproperty
    def status(self):
        try:
            self._l_status = self.builds[defaultsuite][defaultarch].status
        except KeyError:
            self._l_status = False

    @lazyproperty
    def note(self):
        try:
            self._l_note = self.builds[defaultsuite][defaultarch].note
        except KeyError:
            self._l_note = False

    @lazyproperty
    def notify_maint(self):
        query = "SELECT notify_maintainer FROM sources WHERE name='{}'"
        try:
            result = int(query_db(query.format(self.name))[0][0])
        except IndexError:
            result = 0
        self._l_notify_maint = '⚑' if result == 1 else ''

    @lazyproperty
    def history(self):
        self._l_history = []
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
            self._l_history.append(dict(zip(keys, record)))

    def html_link(self, suite, arch, bugs=True, popcon=None, is_popular=None):
        url = '/'.join((RB_PKG_URI, suite, arch, self.name+'.html'))
        css_classes = []
        title = ''
        if is_popular:
            css_classes.append('package-popular')
        if popcon is not None:
            title += 'popcon score: {}\n'.format(popcon)
        notes = self.builds[suite][arch].note
        if notes is None:
            css_classes.append('package')
        else:
            css_classes.append('noted')
            title += '\n'.join([x.name for x in notes.issues]) + '\n'
            title += '\n'.join([str(x.bug) for x in notes.bugs]) + '\n'
            if notes.comment:
                title += HTML.escape(notes.comment)
        html = '<a href="{url}" class="{cls}" title="{title}">{pkg}</a>{ico}\n'
        bug_icon = Bugs().get_trailing_icon(self.name) if bugs else ''
        return html.format(url=url, cls=' '.join(css_classes),
                           title=title, pkg=self.name, ico=bug_icon)
