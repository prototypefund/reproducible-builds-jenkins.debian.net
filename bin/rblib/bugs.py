#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015-2018 Mattia Rizzolo <mattia@debian.org>
# Copyright © 2015-2017 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2

import psycopg2

from .confparse import log

class Udd:
    __singleton = {}

    def __init__(self):
        self.__dict__ = self.__singleton
        if not self.__singleton:
            self._conn_udd = None

    @property
    def _conn(self):
        if self._conn_udd is not None:
            return self._conn_udd
        username = "public-udd-mirror"
        password = "public-udd-mirror"
        host = "public-udd-mirror.xvm.mit.edu"
        port = 5432
        db = "udd"
        try:
            try:
                log.debug("Starting connection to the UDD database")
                conn = psycopg2.connect(
                    dbname=db,
                    user=username,
                    password=password,
                    host=host,
                    port=port,
                    connect_timeout=5,
                )
                conn.set_client_encoding('utf8')
            except psycopg2.OperationalError as err:
                if str(err) == 'timeout expired\n':
                    log.error('Connection to the UDD database timed out.')
                    log.error('Maybe the machine is offline or unavailable.')
                    log.error('Failing nicely, all queries will return an '
                              'empty response.')
                    conn = False
                else:
                    raise
        except Exception as e:
            log.exception('Erorr connecting to the UDD database replica. '
                          'The full error is:')
            log.error('Failing nicely , all queries will return an empty '
                      'response.')
            conn = False
        self._conn_udd = conn
        return conn

    def query(self, query):
        if not self._conn:
            log.error('There has been an error connecting to UDD. '
                      'Look for a previous error for more information.')
            log.error('Failing nicely, returning an empty response.')
            return []
        try:
            cursor = self._conn.cursor()
            cursor.execute(query)
        except:
            log.exception('The UDD server encountered a issue while '
                          'executing the query.  The full error is:')
            log.error('Failing nicely, returning an empty response.')
            return []
        return cursor.fetchall()


class Bugs:
    __singleton = {}
    _query = """
        SELECT bugs.id, bugs.source, bugs.done, ARRAY_AGG(tags.tag), bugs.title
        FROM bugs JOIN bugs_usertags ON bugs.id = bugs_usertags.id
                  LEFT JOIN (
                    SELECT id, tag FROM bugs_tags
                    WHERE tag='patch' OR tag='pending'
                  ) AS tags ON bugs.id = tags.id
        WHERE bugs_usertags.email = 'reproducible-builds@lists.alioth.debian.org'
        AND bugs.id NOT IN (
            SELECT id
            FROM bugs_usertags
            WHERE email = 'reproducible-builds@lists.alioth.debian.org'
            AND (
                bugs_usertags.tag = 'toolchain'
                OR bugs_usertags.tag = 'infrastructure')
            )
        GROUP BY bugs.id, bugs.source, bugs.done
    """

    def __init__(self):
        self.__dict__ = self.__singleton
        if not self.__singleton:
            self._bugs = {}

    @property
    def bugs(self):
        """
        This function returns a dict:
        { "package_name": {
            bug1: {patch: True, done: False, title: "string"},
            bug2: {patch: False, done: False, title: "string"},
           }
        }
        """
        if self._bugs:
            return self._bugs

        log.info("Finding out which usertagged bugs have been closed or at "
                 "least have patches")
        # returns a list of tuples [(id, source, done)]
        rows = Udd().query(self._query)
        packages = {}
        for bug in rows:
            # bug[0] = bug_id
            # bug[1] = source_name
            # bug[2] = who_when_done
            # bug[3] = tag (patch or pending)
            # bug[4] = title
            if bug[1] not in packages:
                packages[bug[1]] = {}
            packages[bug[1]][bug[0]] = {
                'done': False,
                'patch': False,
                'pending': False,
                'title': bug[4],
            }
            if bug[2]:  # if the bug is done
                packages[bug[1]][bug[0]]['done'] = True
            if 'patch' in bug[3]:  # the bug is patched
                packages[bug[1]][bug[0]]['patch'] = True
            if 'pending' in bug[3]:  # the bug is pending
                packages[bug[1]][bug[0]]['pending'] = True
        self._bugs = packages
        return packages
