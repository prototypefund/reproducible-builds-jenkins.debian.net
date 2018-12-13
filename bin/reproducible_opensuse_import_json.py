#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2018 Mattia Rizzolo <mattia@mapreri.org>
#
# Licensed under GPL-2
#
# Depends: python3

import json
from datetime import datetime
from urllib.request import urlopen
from sqlalchemy import select, and_, bindparam

from rblib import conn_db, query_db, db_table
from rblib.confparse import log

json_url = 'http://rb.zq1.de/compare.factory/reproducible.json'

log.info('Downloading status file…')
ofile = urlopen(json_url).read().decode('utf-8')
ostatus = json.loads(ofile)


distributions = db_table('distributions')
sources = db_table('sources')
results = db_table('results')

distro_id = query_db(
    select([distributions.c.id]).where(distributions.c.name == 'opensuse')
)[0][0]

pkgs = []
pkgs_b = {}

for pkg in ostatus:
    p = {
        'name': pkg['package'],
        'version': pkg['version'],
        'suite': 'factory',
        'architecture': pkg['architecture'],
        'distribution': distro_id
    }
    pkgs.append(p)
    data = {
        'status': pkg['status'],
        'build_date': datetime.fromtimestamp(pkg['build_date']),
        'build_duration': pkg['build_duration'],
    }
    pkgs_b[(pkg['package'], pkg['version'])] = data


# just insert everything for now

log.info('Dropping old data…')
transaction = conn_db.begin()
d = results.delete(results.c.package_id.in_(
    select([sources.c.id]).select_from(sources).where(sources.c.distribution == distro_id)
))
query_db(d)
d = sources.delete(sources.c.distribution == distro_id)
query_db(d)
transaction.commit()


log.info('Injecting new source packages…')
transaction = conn_db.begin()
conn_db.execute(sources.insert(), pkgs)
transaction.commit()


log.info('Injecting build results…')
cur_pkgs = select(
    [sources.c.id, sources.c.name, sources.c.version,
     sources.c.suite, sources.c.architecture]
).select_from(
    sources.join(distributions)
).where(
    and_(
        distributions.c.name == 'opensuse',
        sources.c.suite == bindparam('suite'),
        sources.c.architecture == bindparam('arch')
    )
)
cur_pkgs = query_db(cur_pkgs.params({'suite': 'factory', 'arch': 'x86_64'}))

builds = []
for pkg in cur_pkgs:
    # (id, name, version, suite, architecture)
    data = pkgs_b[(pkg[1], pkg[2])]
    if data['status'] == 'nobinaries':
        continue
    pkg_status = data['status'].\
        replace('unreproducible', 'FTBR').\
        replace('notforus', 'NFU').\
        replace('waitdep', 'depwait')
    p = {
        'package_id': pkg[0],
        'version': pkg[2],
        'status': pkg_status,
        'build_date': data['build_date'],
        'build_duration': data['build_duration'],
        'job': 'external',
    }
    builds.append(p)
if builds:
    transaction = conn_db.begin()
    conn_db.execute(results.insert(), builds)
transaction.commit()
