#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015-2018 Mattia Rizzolo <mattia@mapreri.org>
# Copyright © 2015-2019 Holger Levsen <holger@layer-acht.org>
# Based on various reproducible_* files © 2014-2015 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3
#
# Track the database schema and changes to it. Also allow simple creation
# and migration of it.

import re
import sys
from datetime import datetime
from sqlalchemy.orm import sessionmaker

from rblib import query_db
from rblib.confparse import log
from rblib.const import DB_ENGINE, DB_METADATA
from rblib.utils import print_critical_message

now = datetime.now().strftime("%Y-%m-%d-%H-%M-%S")

# the current schema is here:
#   https://tests.reproducible-builds.org/reproducibledb.html

# the original schema is here
db_schema = [
    {
        'name': 'rb_schema',
        'query': ['''CREATE TABLE rb_schema
                     (version INTEGER NOT NULL,
                      date TEXT NOT NULL,
                      PRIMARY KEY (version))''',
                  "INSERT INTO rb_schema VALUES (1, '" + now + "')"]
    },
    {
        'name': 'source_packages',
        'query': ['''CREATE TABLE source_packages
                     (name TEXT NOT NULL,
                      version TEXT NOT NULL,
                      status TEXT NOT NULL
                      CHECK
                        (status IN
                            ('blacklisted', 'FTBFS', 'reproducible',
                             'unreproducible', '404', 'not for us')
                        ),
                      build_date TEXT NOT NULL,
                      PRIMARY KEY (name))''']
    },
    {
        'name': 'sources_scheduled',
        'query': ['''CREATE TABLE sources_scheduled
                     (name TEXT NOT NULL,
                      date_scheduled TEXT NOT NULL,
                      date_build_started TEXT NOT NULL,
                      PRIMARY KEY (name))''']
    },
    {
        'name': 'sources',
        'query': ['''CREATE TABLE sources
                     (name TEXT NOT NULL,
                      version TEXT NOT NULL)''']
    },
    {
        'name': 'stats_pkg_state',
        'query': ['''CREATE TABLE stats_pkg_state
                     (datum TEXT NOT NULL,
                      suite TEXT NOT NULL,
                      untested INTEGER,
                      reproducible INTEGER,
                      unreproducible INTEGER,
                      FTBFS INTEGER,
                      other INTEGER,
                      PRIMARY KEY (datum))''']
    },
    {
        'name': 'stats_builds_per_day',
        'query': ['''CREATE TABLE stats_builds_per_day
                     (datum TEXT NOT NULL,
                      suite TEXT NOT NULL,
                      reproducible INTEGER,
                      unreproducible INTEGER,
                      FTBFS INTEGER,
                      other INTEGER,
                      PRIMARY KEY (datum))''']
    },
    {
        'name': 'stats_builds_age',
        'query': ['''CREATE TABLE stats_builds_age
                     (datum TEXT NOT NULL,
                      suite TEXT NOT NULL,
                      oldest_reproducible REAL,
                      oldest_unreproducible REAL,
                      oldest_FTBFS REAL,
                      PRIMARY KEY (datum))''']
    },
    {
        'name': 'stats_bugs',
        'query': ['''CREATE TABLE stats_bugs
                     (datum TEXT NOT NULL,
                      open_toolchain INTEGER,
                      done_toolchain INTEGER,
                      open_infrastructure INTEGER,
                      done_infrastructure INTEGER,
                      open_timestamps INTEGER,
                      done_timestamps INTEGER,
                      open_fileordering INTEGER,
                      done_fileordering INTEGER,
                      open_buildpath INTEGER,
                      done_buildpath INTEGER,
                      open_username INTEGER,
                      done_username INTEGER,
                      open_hostname INTEGER,
                      done_hostname INTEGER,
                      open_uname INTEGER,
                      done_uname INTEGER,
                      open_randomness INTEGER,
                      done_randomness INTEGER,
                      open_buildinfo INTEGER,
                      done_buildinfo INTEGER,
                      open_cpu INTEGER,
                      done_cpu INTEGER,
                      open_signatures INTEGER,
                      done_signatures INTEGER,
                      open_environment INTEGER,
                      one_environment INTEGER,
                      PRIMARY KEY (datum))''']
    },
    {
        'name': 'stats_notes',
        'query': ['''CREATE TABLE stats_notes
                     (datum TEXT NOT NULL,
                      packages_with_notes INTEGER,
                      PRIMARY KEY (datum))''']
    },
    {
        'name': 'stats_issues',
        'query': ['''CREATE TABLE stats_issues
                     (datum TEXT NOT NULL,
                      known_issues INTEGER,
                      PRIMARY KEY (datum))''']
    },
    {
        'name': 'stats_meta_pkg_state',
        'query': ['''CREATE TABLE stats_meta_pkg_state
                     (datum TEXT NOT NULL,
                      suite TEXT NOT NULL,
                      meta_pkg TEXT NOT NULL,
                      reproducible INTEGER,
                      unreproducible INTEGER,
                      FTBFS INTEGER,
                      other INTEGER,
                      PRIMARY KEY (datum, suite, meta_pkg))''']
    }
]

# and here are some queries, split by update, that can be used to
# update the live schema
schema_updates = {
    1: [],
    2: [  # do a funny dance to add an id, suite and architecture values to
          # the `suites` table
        '''CREATE TABLE sources_new_tmp
           (id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            version TEXT NOT NULL,
            suite TEXT,
            architecture TEXT,
            UNIQUE (name, suite, architecture))''',
        '''CREATE TABLE sources_new
           (id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            version TEXT NOT NULL,
            suite TEXT NOT NULL,
            architecture TEXT NOT NULL,
            UNIQUE (name, suite, architecture))''',
        'INSERT INTO sources_new_tmp (name, version) SELECT * FROM sources',
        "UPDATE sources_new_tmp SET suite='sid', architecture='amd64'",
        'INSERT INTO sources_new SELECT * FROM sources_new_tmp',
        'DROP TABLE sources_new_tmp',
        'DROP TABLE sources',
        'ALTER TABLE sources_new RENAME TO sources',
        # now that we have an id in `sources` rework all tables to join
        # against this table, and avoid duplicating data
        # `schedule`:
        '''CREATE TABLE schedule
           (id INTEGER PRIMARY KEY,
            package_id INTEGER NOT NULL,
            date_scheduled TEXT NOT NULL,
            date_build_started TEXT NOT NULL,
            save_artifacts INTEGER DEFAULT 0,
            UNIQUE (package_id),
            FOREIGN KEY(package_id) REFERENCES sources(id))''',
        '''INSERT INTO schedule (package_id, date_scheduled, date_build_started)
           SELECT s.id, p.date_scheduled, p.date_build_started
           FROM sources AS s JOIN sources_scheduled AS p ON s.name = p.name''',
        'DROP TABLE sources_scheduled',
        # `results`:
        '''CREATE TABLE results
           (id INTEGER PRIMARY KEY,
            package_id INTEGER NOT NULL,
            version TEXT NOT NULL,
            status TEXT,
            build_date TEXT,
            build_duration TEXT DEFAULT '0',
            UNIQUE (package_id),
            FOREIGN KEY(package_id) REFERENCES sources(id))''',
        '''INSERT INTO results (package_id, version, status, build_date)
           SELECT s.id, r.version, r.status, r.build_date
           FROM sources AS s JOIN source_packages as r ON s.name = r.name''',
        'DROP TABLE source_packages',
        # `stats_builds`: (completely new table where we save every build)
        '''CREATE TABLE stats_build
           (id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            version TEXT NOT NULL,
            suite TEXT NOT NULL,
            architecture TEXT NOT NULL,
            status TEXT NOT NULL,
            build_date TEXT NOT NULL,
            build_duration TEXT NOT NULL,
            UNIQUE (name, version, suite, architecture, build_date))''',
    ],
    3: [  # add columns to stats_bugs for new usertag umask
        '''ALTER TABLE stats_bugs ADD COLUMN open_umask INTEGER''',
        '''ALTER TABLE stats_bugs ADD COLUMN done_umask INTEGER''',
    ],
    4: [  # stats_pkg_state needs (datum, suite) as primary key
        '''CREATE TABLE stats_pkg_state_tmp
           (datum TEXT NOT NULL,
            suite TEXT NOT NULL,
            untested INTEGER,
            reproducible INTEGER,
            unreproducible INTEGER,
            FTBFS INTEGER,
            other INTEGER,
            PRIMARY KEY (datum, suite))''',
        '''INSERT INTO stats_pkg_state_tmp (datum, suite, untested,
            reproducible, unreproducible, FTBFS, other)
            SELECT datum, suite, untested, reproducible, unreproducible,
            FTBFS, other FROM stats_pkg_state;''',
        '''DROP TABLE stats_pkg_state;''',
        '''ALTER TABLE stats_pkg_state_tmp RENAME TO stats_pkg_state;''',
    ],
    5: [  # stats_builds_per_day needs (datum, suite) as primary key
        '''CREATE TABLE stats_builds_per_day_tmp
                     (datum TEXT NOT NULL,
                      suite TEXT NOT NULL,
                      reproducible INTEGER,
                      unreproducible INTEGER,
                      FTBFS INTEGER,
                      other INTEGER,
                      PRIMARY KEY (datum, suite))''',
        '''INSERT INTO stats_builds_per_day_tmp (datum, suite,
            reproducible, unreproducible, FTBFS, other)
            SELECT datum, suite, reproducible, unreproducible,
            FTBFS, other FROM stats_builds_per_day;''',
        '''DROP TABLE stats_builds_per_day;''',
        '''ALTER TABLE stats_builds_per_day_tmp RENAME TO stats_builds_per_day;''',
    ],
    6: [  # stats_builds_age needs (datum, suite) as primary key
        '''CREATE TABLE stats_builds_age_tmp
                     (datum TEXT NOT NULL,
                      suite TEXT NOT NULL,
                      oldest_reproducible REAL,
                      oldest_unreproducible REAL,
                      oldest_FTBFS REAL,
                      PRIMARY KEY (datum, suite))''',
        '''INSERT INTO stats_builds_age_tmp (datum, suite,
            oldest_reproducible, oldest_unreproducible, oldest_FTBFS)
            SELECT datum, suite, oldest_reproducible, oldest_unreproducible,
            oldest_FTBFS FROM stats_builds_age;''',
        '''DROP TABLE stats_builds_age;''',
        '''ALTER TABLE stats_builds_age_tmp RENAME TO stats_builds_age;''',
    ],
    7: [  # change build_duration field in results and stats_build from str to int
        '''CREATE TABLE stats_build_tmp
           (id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            version TEXT NOT NULL,
            suite TEXT NOT NULL,
            architecture TEXT NOT NULL,
            status TEXT NOT NULL,
            build_date TEXT NOT NULL,
            build_duration INTEGER NOT NULL,
            UNIQUE (name, version, suite, architecture, build_date))''',
        '''INSERT INTO stats_build_tmp
            SELECT id, name, version, suite, architecture, status, build_date,
            CAST (build_duration AS INTEGER) FROM stats_build''',
        'DROP TABLE stats_build',
        'ALTER TABLE stats_build_tmp RENAME TO stats_build',
        '''CREATE TABLE results_tmp
           (id INTEGER PRIMARY KEY,
            package_id INTEGER NOT NULL,
            version TEXT NOT NULL,
            status TEXT,
            build_date TEXT,
            build_duration INTEGER DEFAULT '0',
            UNIQUE (package_id),
            FOREIGN KEY(package_id) REFERENCES sources(id))''',
        '''INSERT INTO results_tmp
            SELECT id, package_id, version, status,
            build_date, CAST (build_duration AS INTEGER) FROM results''',
        'DROP TABLE results',
        'ALTER TABLE results_tmp RENAME TO results',
    ],
    8: [  # add default value to stats_bugs to get a full 'done vs open bugs' graph
        '''CREATE TABLE stats_bugs_tmp
           (datum TEXT NOT NULL,
            open_toolchain INTEGER DEFAULT '0',
            done_toolchain INTEGER DEFAULT '0',
            open_infrastructure INTEGER DEFAULT '0',
            done_infrastructure INTEGER DEFAULT '0',
            open_timestamps INTEGER DEFAULT '0',
            done_timestamps INTEGER DEFAULT '0',
            open_fileordering INTEGER DEFAULT '0',
            done_fileordering INTEGER DEFAULT '0',
            open_buildpath INTEGER DEFAULT '0',
            done_buildpath INTEGER DEFAULT '0',
            open_username INTEGER DEFAULT '0',
            done_username INTEGER DEFAULT '0',
            open_hostname INTEGER DEFAULT '0',
            done_hostname INTEGER DEFAULT '0',
            open_uname INTEGER DEFAULT '0',
            done_uname INTEGER DEFAULT '0',
            open_randomness INTEGER DEFAULT '0',
            done_randomness INTEGER DEFAULT '0',
            open_buildinfo INTEGER DEFAULT '0',
            done_buildinfo INTEGER DEFAULT '0',
            open_cpu INTEGER DEFAULT '0',
            done_cpu INTEGER DEFAULT '0',
            open_signatures INTEGER DEFAULT '0',
            done_signatures INTEGER DEFAULT '0',
            open_environment INTEGER DEFAULT '0',
            done_environment INTEGER DEFAULT '0',
            open_umask INTEGER DEFAULT '0',
            done_umask INTEGER DEFAULT '0',
            PRIMARY KEY (datum))''',
        'INSERT INTO stats_bugs_tmp SELECT * FROM stats_bugs',
        'DROP TABLE stats_bugs',
        'ALTER TABLE stats_bugs_tmp RENAME TO stats_bugs',
    ],
    9: [  # rename 'sid' to 'unstable'
        "UPDATE sources SET suite = 'unstable' WHERE suite = 'sid'",
        "UPDATE stats_build SET suite = 'unstable' WHERE suite = 'sid'",
        "UPDATE stats_pkg_state SET suite = 'unstable' WHERE suite = 'sid'",
        "UPDATE stats_builds_per_day SET suite = 'unstable' WHERE suite = 'sid'",
        "UPDATE stats_builds_age SET suite = 'unstable' WHERE suite = 'sid'",
        "UPDATE stats_meta_pkg_state SET suite = 'unstable' WHERE suite = 'sid'",
    ],
    10: [  # add the notes and issues tables
        '''CREATE TABLE notes (
            package_id INTEGER,
            version TEXT NOT NULL,
            issues TEXT,
            bugs TEXT,
            comments TEXT,
            PRIMARY KEY (package_id),
            FOREIGN KEY(package_id) REFERENCES sources(id))''',
        '''CREATE TABLE issues (
            name TEXT NOT NULL,
            description TEXT NOT NULL,
            url TEXT,
            PRIMARY KEY (name))''',
    ],
    11: [  # table with removed packages, to enable the maintenance job to do clean up
        '''CREATE TABLE removed_packages (
            name TEXT NOT NULL,
            suite TEXT NOT NULL,
            architecture TEXT NOT NULL,
            PRIMARY KEY (name, suite, architecture))''',
    ],
    12: [  # refactor the artifacts handling, splitting artifacts saving from
           # IRC notification
        'ALTER TABLE schedule ADD COLUMN notify TEXT',
    ],
    13: [  # record manual scheduling done, to be able to limit people
        '''CREATE TABLE manual_scheduler (
            id INTEGER PRIMARY KEY,
            package_id INTEGER NOT NULL,
            requester TEXT NOT NULL,
            date_request INTEGER NOT NULL)''',
        'ALTER TABLE schedule ADD COLUMN scheduler TEXT',
    ],
    14: [  # column to enable mail notification to maintainers
        'ALTER TABLE sources ADD COLUMN notify_maintainer INTEGER NOT NULL DEFAULT 0',
    ],
    15: [  # add columns to stats_bugs for new usertag ftbfs
        '''ALTER TABLE stats_bugs ADD COLUMN open_ftbfs INTEGER''',
        '''ALTER TABLE stats_bugs ADD COLUMN done_ftbfs INTEGER''',
    ],
    16: [  # add default value to stats_bugs.(open|done)_ftbfs to get a full 'done vs open bugs' graph
        '''CREATE TABLE stats_bugs_tmp
           (datum TEXT NOT NULL,
            open_toolchain INTEGER DEFAULT '0',
            done_toolchain INTEGER DEFAULT '0',
            open_infrastructure INTEGER DEFAULT '0',
            done_infrastructure INTEGER DEFAULT '0',
            open_timestamps INTEGER DEFAULT '0',
            done_timestamps INTEGER DEFAULT '0',
            open_fileordering INTEGER DEFAULT '0',
            done_fileordering INTEGER DEFAULT '0',
            open_buildpath INTEGER DEFAULT '0',
            done_buildpath INTEGER DEFAULT '0',
            open_username INTEGER DEFAULT '0',
            done_username INTEGER DEFAULT '0',
            open_hostname INTEGER DEFAULT '0',
            done_hostname INTEGER DEFAULT '0',
            open_uname INTEGER DEFAULT '0',
            done_uname INTEGER DEFAULT '0',
            open_randomness INTEGER DEFAULT '0',
            done_randomness INTEGER DEFAULT '0',
            open_buildinfo INTEGER DEFAULT '0',
            done_buildinfo INTEGER DEFAULT '0',
            open_cpu INTEGER DEFAULT '0',
            done_cpu INTEGER DEFAULT '0',
            open_signatures INTEGER DEFAULT '0',
            done_signatures INTEGER DEFAULT '0',
            open_environment INTEGER DEFAULT '0',
            done_environment INTEGER DEFAULT '0',
            open_umask INTEGER DEFAULT '0',
            done_umask INTEGER DEFAULT '0',
            open_ftbfs INTEGER DEFAULT '0',
            done_ftbfs INTEGER DEFAULT '0',
            PRIMARY KEY (datum))''',
        'INSERT INTO stats_bugs_tmp SELECT * FROM stats_bugs',
        'DROP TABLE stats_bugs',
        'ALTER TABLE stats_bugs_tmp RENAME TO stats_bugs',
    ],
    17: [  # add column to save which builders builds what
        "ALTER TABLE schedule ADD COLUMN builder TEXT",
        "ALTER TABLE results ADD COLUMN builder TEXT NOT NULL DEFAULT ''",
        "ALTER TABLE stats_build ADD COLUMN builder TEXT NOT NULL DEFAULT ''",
    ],
    18: [  # add columns to stats_bugs for new usertag locale
        '''ALTER TABLE stats_bugs ADD COLUMN open_locale INTEGER DEFAULT 0''',
        '''ALTER TABLE stats_bugs ADD COLUMN done_locale INTEGER DEFAULT 0''',
    ],
    19: [  # add column architecture to stats_pkg_state, stats_builds_per_day
           # and stats_builds_age tables and set previous values to amd64
        "ALTER TABLE stats_pkg_state ADD COLUMN architecture TEXT NOT NULL DEFAULT 'amd64'",
        "ALTER TABLE stats_builds_per_day ADD COLUMN architecture TEXT NOT NULL DEFAULT 'amd64'",
        "ALTER TABLE stats_builds_age ADD COLUMN architecture TEXT NOT NULL DEFAULT 'amd64'",
    ],
    20: [  # use (datum, suite, architecture) as primary key for stats_pkg_state
        '''CREATE TABLE stats_pkg_state_tmp
           (datum TEXT NOT NULL,
            suite TEXT NOT NULL,
            architecture TEXT NOT NULL,
            untested INTEGER,
            reproducible INTEGER,
            unreproducible INTEGER,
            FTBFS INTEGER,
            other INTEGER,
            PRIMARY KEY (datum, suite, architecture))''',
        '''INSERT INTO stats_pkg_state_tmp (datum, suite, architecture, untested,
            reproducible, unreproducible, FTBFS, other)
            SELECT datum, suite, architecture, untested, reproducible, unreproducible,
            FTBFS, other FROM stats_pkg_state;''',
        '''DROP TABLE stats_pkg_state;''',
        '''ALTER TABLE stats_pkg_state_tmp RENAME TO stats_pkg_state;''',
    ],
    21: [  # use (datum, suite, architecture) as primary key for stats_builds_per_day
        '''CREATE TABLE stats_builds_per_day_tmp
                     (datum TEXT NOT NULL,
                      suite TEXT NOT NULL,
                      architecture TEXT NOT NULL,
                      reproducible INTEGER,
                      unreproducible INTEGER,
                      FTBFS INTEGER,
                      other INTEGER,
                      PRIMARY KEY (datum, suite, architecture))''',
        '''INSERT INTO stats_builds_per_day_tmp (datum, suite, architecture,
            reproducible, unreproducible, FTBFS, other)
            SELECT datum, suite, architecture, reproducible, unreproducible,
            FTBFS, other FROM stats_builds_per_day;''',
        '''DROP TABLE stats_builds_per_day;''',
        '''ALTER TABLE stats_builds_per_day_tmp RENAME TO stats_builds_per_day;''',
    ],
    22: [  # use (datum, suite, architecture) as primary key for stats_builds_age
        '''CREATE TABLE stats_builds_age_tmp
                     (datum TEXT NOT NULL,
                      suite TEXT NOT NULL,
                      architecture TEXT NOT NULL,
                      oldest_reproducible REAL,
                      oldest_unreproducible REAL,
                      oldest_FTBFS REAL,
                      PRIMARY KEY (datum, suite, architecture))''',
        '''INSERT INTO stats_builds_age_tmp (datum, suite, architecture,
            oldest_reproducible, oldest_unreproducible, oldest_FTBFS)
            SELECT datum, suite, architecture, oldest_reproducible, oldest_unreproducible,
            oldest_FTBFS FROM stats_builds_age;''',
        '''DROP TABLE stats_builds_age;''',
        '''ALTER TABLE stats_builds_age_tmp RENAME TO stats_builds_age;''',
    ],
    23: [  # save which builders built a package and change the name of the
           # field keeping the job name
        '''CREATE TABLE stats_build_tmp
            (id INTEGER PRIMARY KEY,
             name TEXT NOT NULL,
             version TEXT NOT NULL,
             suite TEXT NOT NULL,
             architecture TEXT NOT NULL,
             status TEXT NOT NULL,
             build_date TEXT NOT NULL,
             build_duration TEXT NOT NULL,
             node1 TEXT NOT NULL DEFAULT '',
             node2 TEXT NOT NULL DEFAULT '',
             job TEXT NOT NULL,
             UNIQUE (name, version, suite, architecture, build_date))''',
        '''INSERT INTO stats_build_tmp (id, name, version, suite, architecture,
                    status, build_date, build_duration, job)
           SELECT id, name, version, suite, architecture, status, build_date,
                    build_duration, builder FROM stats_build''',
        'DROP TABLE stats_build',
        'ALTER TABLE stats_build_tmp RENAME TO stats_build',
    ],
    24: [  # the same as #23 but for the results table
        '''CREATE TABLE results_tmp
           (id INTEGER PRIMARY KEY,
            package_id INTEGER NOT NULL,
            version TEXT NOT NULL,
            status TEXT NOT NULL,
            build_date TEXT NOT NULL,
            build_duration INTEGER DEFAULT 0,
            node1 TEXT,
            node2 TEXT,
            job TEXT NOT NULL,
            UNIQUE (package_id),
            FOREIGN KEY(package_id) REFERENCES sources(id))''',
        '''INSERT INTO results_tmp (id, package_id, version, status,
                    build_date, build_duration, job)
           SELECT id, package_id, version, status, build_date, build_duration,
                    builder FROM results''',
        'DROP TABLE results',
        'ALTER TABLE results_tmp RENAME TO results',
    ],
    25: [  # rename the builder column also in the schedule table.
        '''CREATE TABLE schedule_tmp
           (id INTEGER PRIMARY KEY,
            package_id INTEGER NOT NULL,
            date_scheduled TEXT NOT NULL,
            scheduler TEXT,
            date_build_started TEXT,
            job TEXT,
            notify TEXT NOT NULL DEFAULT '',
            save_artifacts INTEGER DEFAULT 0,
            UNIQUE (package_id),
            FOREIGN KEY(package_id) REFERENCES sources(id))''',
        '''UPDATE schedule SET notify = '' WHERE notify IS NULL''',
        '''INSERT INTO schedule_tmp (id, package_id, date_scheduled, scheduler,
                    date_build_started, job, notify, save_artifacts)
           SELECT id, package_id, date_scheduled, scheduler,
                    date_build_started, builder, notify, save_artifacts
           FROM schedule''',
        'DROP TABLE schedule',
        'ALTER TABLE schedule_tmp RENAME TO schedule',
    ],
    26: [  # add a column to the schedule table to save the schedule message
        "ALTER TABLE schedule ADD COLUMN message TEXT",
        "ALTER TABLE stats_build ADD COLUMN schedule_message TEXT NOT NULL DEFAULT ''",
    ],
    27: [  # add column architecture to stats_meta_pkg_state and set previous values to amd64
        "ALTER TABLE stats_meta_pkg_state ADD COLUMN architecture TEXT NOT NULL DEFAULT 'amd64'",
    ],
    28: [  # use (datum, suite, architecture, meta_pkg) as primary key for stats_meta_pkg_state
        '''CREATE TABLE stats_meta_pkg_state_tmp
           (datum TEXT NOT NULL,
            suite TEXT NOT NULL,
            architecture TEXT NOT NULL,
            meta_pkg TEXT NOT NULL,
            reproducible INTEGER,
            unreproducible INTEGER,
            FTBFS INTEGER,
            other INTEGER,
            PRIMARY KEY (datum, suite, architecture, meta_pkg))''',
        '''INSERT INTO stats_meta_pkg_state_tmp (datum, suite, architecture, meta_pkg,
            reproducible, unreproducible, FTBFS, other)
            SELECT datum, suite, architecture, meta_pkg, reproducible, unreproducible,
            FTBFS, other FROM stats_meta_pkg_state;''',
        '''DROP TABLE stats_meta_pkg_state;''',
        '''ALTER TABLE stats_meta_pkg_state_tmp RENAME TO stats_meta_pkg_state;''',
    ],

    # THE FOLLOWING UPDATES CAN ONLY BE PREFORMED ON POSTGRES DATABASE

    29: [  # Add auto incrementing to the id columns of some tables
        "CREATE SEQUENCE schedule_id_seq",
        "ALTER TABLE schedule ALTER id SET DEFAULT NEXTVAL('schedule_id_seq')",
        "CREATE SEQUENCE manual_scheduler_id_seq",
        """ALTER TABLE manual_scheduler ALTER id SET DEFAULT
            NEXTVAL('manual_scheduler_id_seq')""",
        "CREATE SEQUENCE sources_id_seq",
        "ALTER TABLE sources ALTER id SET DEFAULT NEXTVAL('sources_id_seq')",
        "CREATE SEQUENCE stats_build_id_seq",
        """ALTER TABLE stats_build ALTER id SET DEFAULT
            NEXTVAL('stats_build_id_seq')""",
        "CREATE SEQUENCE results_id_seq",
        "ALTER TABLE results ALTER id SET DEFAULT NEXTVAL('results_id_seq')",
    ],
    30: [  # Add new table to track diffoscope breake
        '''CREATE TABLE stats_breakages
                     (datum TEXT,
                      diffoscope_timeouts INTEGER,
                      diffoscope_crashes INTEGER,
                      PRIMARY KEY (datum))''',
    ],
    31: [  # rename the 'testing' suite into 'stretch'
        "UPDATE {} SET suite='stretch' WHERE suite='testing'".format(t)
        for t in ("sources", "stats_pkg_state", "stats_builds_per_day",
                  "stats_builds_age", "stats_meta_pkg_state", "stats_build")
    ],
    32: [  # copy stretch packages (including results) in buster
        """INSERT INTO sources (name, version, suite, architecture, notify_maintainer)
            SELECT name, version, 'buster', architecture, notify_maintainer
            FROM sources
            WHERE suite = 'stretch'""",
        """WITH buster AS (
                SELECT id, name, suite, architecture, version
                FROM sources WHERE suite = 'buster'),
            sr AS (
                SELECT s.name, s.architecture, r.id, r.version, r.status,
                    r.build_date, r.build_duration, r.node1, r.node2, r.job
                FROM sources AS s JOIN results AS r ON s.id=r.package_id
                WHERE s.suite = 'stretch')
            INSERT INTO results (package_id, version, status, build_date,
                    build_duration, node1, node2, job)
                SELECT b.id, sr.version, sr.status, sr.build_date,
                    sr.build_duration, sr.node1, sr.node2, sr.job
                FROM buster AS b JOIN sr ON b.name=sr.name
                    AND b.architecture=sr.architecture""",
    ],
    33: [  # the message columns.  They are not actually needed.
        "ALTER TABLE schedule DROP COLUMN message",
        "ALTER TABLE stats_build DROP COLUMN schedule_message",
    ],
    34: [  # rename status "not for us" to "NFU"
        "UPDATE results SET status='NFU' WHERE status='not for us'",
        "UPDATE stats_build SET status='NFU' WHERE status='not for us'",
    ],
    35: [  # rename status "unreproducible" to "FTBR"
        "UPDATE results SET status='FTBR' WHERE status='unreproducible'",
        "UPDATE stats_build SET status='FTBR' WHERE status='unreproducible'",
        "ALTER TABLE stats_pkg_state RENAME COLUMN unreproducible to FTBR",
        "ALTER TABLE stats_meta_pkg_state RENAME COLUMN unreproducible to FTBR",
        "ALTER TABLE stats_builds_per_day RENAME COLUMN unreproducible to FTBR",
        "ALTER TABLE stats_builds_age " + \
        "RENAME COLUMN oldest_unreproducible to oldest_FTBR",
    ],
    36: [  # rename status "404" to "E404"
        "UPDATE results SET status='E404' WHERE status='404'",
        "UPDATE stats_build SET status='E404' WHERE status='404'",
    ],
    37: [  # change the data type in the stats_build.build_date column
        "ALTER TABLE stats_build ALTER COLUMN build_date SET DATA TYPE timestamp"
        " USING build_date::timestamp"
    ],
    38: [  # add a distribution field to the sources tables
        """CREATE TABLE distributions (
                id SERIAL PRIMARY KEY,
                name VARCHAR)""",
        "INSERT INTO distributions (name) VALUES ('debian')",
        """ALTER TABLE sources
            ADD COLUMN distribution INTEGER DEFAULT 1
            REFERENCES distributions(id)""",
        """ALTER TABLE stats_build
            ADD COLUMN distribution INTEGER DEFAULT 1
            REFERENCES distributions(id)""",
    ],
    39: [  # fix build_duration datatype
        "ALTER TABLE stats_build ALTER COLUMN build_duration SET DATA TYPE integer"
        " USING build_duration::integer"
    ],
    40: [  # add some new distributions
        "INSERT INTO distributions (name) VALUES "
        "('opensuse'), ('archlinux'), ('alpine')"
    ],
    41: [  # mark archlinux packages as archlinx packages
        """UPDATE sources SET distribution=(
            SELECT id FROM distributions WHERE name='archlinux')
           WHERE suite LIKE 'archlinux_%%'""",
        """UPDATE stats_build SET distribution=(
            SELECT id FROM distributions WHERE name='archlinux')
           WHERE suite LIKE 'archlinux_%%'"""
    ],
    42: [  # add OpenWrt
        "INSERT INTO distributions (name) VALUES "
        "('openwrt')"
    ],
    43: [  # Arch Linux should use the same stati as Debian
        "UPDATE results SET status='reproducible' WHERE status='GOOD'",
        "UPDATE results SET status='blacklisted' WHERE status='BLACKLISTED'"
    ],
    44: [  # copy buster packages (including results) in bullseye
        """INSERT INTO sources (name, version, suite, architecture, notify_maintainer, distribution)
            SELECT name, version, 'bullseye', architecture, notify_maintainer, distribution
            FROM sources
            WHERE suite = 'buster'""",
        """WITH bullseye AS (
                SELECT id, name, suite, architecture, version
                FROM sources WHERE suite = 'bullseye'),
            sr AS (
                SELECT s.name, s.architecture, r.version, r.status,
                    r.build_date, r.build_duration, r.node1, r.node2, r.job
                FROM sources AS s JOIN results AS r ON s.id=r.package_id
                WHERE s.suite = 'buster')
            INSERT INTO results (package_id, version, status, build_date,
                    build_duration, node1, node2, job)
                SELECT b.id, sr.version, sr.status, sr.build_date,
                    sr.build_duration, sr.node1, sr.node2, sr.job
                FROM bullseye AS b JOIN sr ON b.name=sr.name
                    AND b.architecture=sr.architecture""",
    ],
    45: [  # fixup #43
        "UPDATE stats_build SET status='reproducible' WHERE status='GOOD'",
        "UPDATE stats_build SET status='blacklisted' WHERE status='BLACKLISTED'"
    ],
    46: [  # crete a build_type field
        "CREATE TYPE build_type AS ENUM ('verification', 'ci_build')",
        "ALTER TABLE results ADD COLUMN build_type build_type DEFAULT 'ci_build' NOT NULL",
        "ALTER TABLE stats_build ADD COLUMN build_type build_type DEFAULT 'ci_build' NOT NULL",
        "ALTER TABLE schedule ADD COLUMN build_type build_type",
        "UPDATE schedule SET build_type='ci_build'",
        "ALTER TABLE schedule ALTER COLUMN build_type SET NOT NULL",
    ],
    47: [  # turn timestamps into real timestamps
        "ALTER TABLE {0} ALTER COLUMN {1} TYPE timestamp without time zone "
        "USING to_timestamp({1}, 'YYYY-MM-DD HH24:MI:SS')".format(i, j) for i, j in (
            ("results", "build_date"),
            ("schedule", "date_scheduled"),
        )] + [
        "ALTER TABLE {0} ALTER COLUMN datum TYPE date "
        "USING to_date(datum, 'YYYY-MM-DD')".format(i) for i in (
            "stats_breakages", "stats_bugs", "stats_builds_age",
            "stats_builds_per_day", "stats_issues", "stats_meta_pkg_state",
            "stats_notes", "stats_pkg_state",
        )
    ],
    48: [  # normalize archlinux's suite names
        "UPDATE sources SET suite='core' WHERE suite='archlinux_core'",
        "UPDATE sources SET suite='extra' WHERE suite='archlinux_extra'",
        "UPDATE sources SET suite='community' WHERE suite='archlinux_community'",
        "UPDATE sources SET suite='multilib' WHERE suite='archlinux_multilib'",
        "UPDATE stats_build SET suite='core' WHERE suite='archlinux_core'",
        "UPDATE stats_build SET suite='extra' WHERE suite='archlinux_extra'",
        "UPDATE stats_build SET suite='community' WHERE suite='archlinux_community'",
        "UPDATE stats_build SET suite='multilib' WHERE suite='archlinux_multilib'",
    ],
    49: [  # create a dsources view
        """CREATE VIEW dsources AS
            SELECT s.id AS package_id, s.name, s.version, s.suite,
                s.architecture, s.notify_maintainer, d.name AS distribution
            FROM sources s JOIN distributions d on s.distribution=d.id""",
    ],
}


def table_exists(tablename):
    DB_METADATA.reflect()
    if tablename in DB_METADATA.tables:
        return True
    else:
        return False


def db_create_tables():
    """
    Check whether all tables are present, and create them if not.
    The check is done against sqlite_master, a reserved sqlite table
    containing all database metadata.
    """
    changed = False
    for table in db_schema:
        if not table_exists(table['name']):
            log.warning(table['name'] + ' does not exists. Creating...')
            for query in table['query']:
                log.info('\t' + re.sub(' +', ' ', query.replace('\n', ' ')))
                query_db(query)
                changed = True
    return changed


def db_update():
    """
    Update the database schema.
    Get a list of queries to perform from schema_updates.
    The need for an update is detected by checking the biggest value in the
    rb_schema table against the biggest value in the schema_updates dictionary.
    """
    current = query_db('SELECT MAX(version) FROM rb_schema')[0][0]
    if not current:
        log.warning('This is probably a new database, there are no ' +
                    'previous updates noted')
        current = 0
    last = max(schema_updates.keys())
    if current == last:
        return False
    if current > last:
        print_critical_message('The active database schema is higher than' +
                               '  the last update available.\nPlease check!')
        sys.exit(1)
    log.info('Found schema updates.')
    Session = sessionmaker(bind=DB_ENGINE, autocommit=True)
    session = Session()
    for update in range(current+1, last+1):
        log.info('Applying database update #' + str(update) + '. Queries:')
        startTime = datetime.now()
        with session.begin():
            for query in schema_updates[update]:
                log.info('\t' + query)
                session.execute(query)
            session.execute(
                "INSERT INTO rb_schema (version, date) "
                "VALUES (:ver, CURRENT_TIMESTAMP)", {'ver': update}
            )
        log.info(str(len(schema_updates[update])) + ' queries executed in ' +
                 str(datetime.now() - startTime))
    return True


if __name__ == '__main__':
    changed_created = False
    if table_exists('rb_schema'):
        if not query_db('SELECT * FROM rb_schema'):
            # table exists but there is nothing in it
            changed_create = db_create_tables()
    else:
        log.error('There is no rb_schema table in the database.')
        log.error('Will run a full db_create_tables().')
        changed_created = db_create_tables()
    changed = db_update()
    if changed or changed_created:
        log.info('Total execution time: ' + str(datetime.now() -
                 datetime.strptime(now, "%Y-%m-%d-%H-%M-%S")))
    else:
        log.info('No pending updates.')
