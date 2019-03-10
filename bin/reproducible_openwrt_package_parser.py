#!/usr/bin/env python
# Copyright Alexander Couzens <lynxis@fe80.eu> 2018
#
# under the GPL2
#
# Parse two Packages.manifest or Packages list from two builds and
# fill the database of reproducible-builds with the results

import email.parser

def download_manifest():
    import requests

    url = "https://downloads.openwrt.org/releases/18.06.1/targets/ramips/mt76x8/packages/Packages.manifest"
    response = requests.get(url)
    return str(response.content, 'utf-8')

def parse_packages(package_list_fp):
    linebuffer = ""
    packages = []

    for line in package_list_fp:
        if line == '\n':
            parser = email.parser.Parser()
            package = parser.parsestr(linebuffer)
            packages.append(package)
            linebuffer = ""
        else:
            linebuffer += line
    return packages

def show_list_difference(list_a, list_b):
    """ get two list of manifest and generate a result """
    pkg_a = parse_packages(list_a)
    pkg_b = parse_packages(list_b)

    # packages which does not have the same pkg in B
    alone_a = {}

    # packages which does not have the same pkg in A
    alone_b = {}

    # package which are not reproducible
    differ = {}
    same = {}

    dict_a = {}
    dict_b = {}

    for pkg in pkg_a:
        dict_a[pkg['Package']] = pkg

    for pkg in pkg_b:
        dict_b[pkg['Package']] = pkg

    for name in dict_a:
        if name not in dict_b:
            alone_a[name] = dict_a[name]
        else:
            if dict_a[name]['SHA256sum'] != dict_b[name]['SHA256sum']:
                differ[name] = [dict_a[name], dict_b[name]]
            else:
                same[name] = [dict_a[name], dict_b[name]]
            del dict_b[name]

    for name in dict_b:
        alone_b[name] = dict_b[name]

    return (same, alone_a, alone_b, differ)

def insert_into_db(result, suite='trunk'):
    """ takes the result tuple and insert it into the database """
    from sqlalchemy import select, and_, bindparam
    from rblib import conn_db, query_db, db_table
    from rblib.confparse import log
    from datetime import datetime

    same, alone_a, alone_b, differ = result

    distributions = db_table('distributions')
    results = db_table('results')
    sources = db_table('sources')

    distro_id = query_db(
        select([distributions.c.id]).where(distributions.c.name == 'openwrt')
        )[0][0]

    # Delete all old data
    transaction = conn_db.begin()
    d = results.delete(results.c.package_id.in_(
        select([sources.c.id]).select_from(sources).where(sources.c.distribution == distro_id)
    ))
    query_db(d)
    d = sources.delete(sources.c.distribution == distro_id)
    query_db(d)
    transaction.commit()

    # create new data
    pkgs = []
    pkgs_b = {}
    now = datetime.now()

    def insert_pkg_list(pkg_list, state, timestamp):
        # Add new data
        for pkg in same:
            p = {
                'name': pkg['Package'],
                'version': pkg['Version'],
                'suite': suite,
                'architecture': pkg['Architecture'],
                'distribution': distro_id
            }
            pkgs.append(p)
            data = {
                'status': pkg['status'],
                'build_date': timestamp,
                'build_duration': 2342,
            }
            pkgs_b[(pkg['package'], pkg['version'])] = data

    insert_pkg_list(same, "reproducible", now)
    insert_pkg_list(alone_a, "FTBFS on B", now)
    insert_pkg_list(alone_b, "FTBFS on A", now)
    insert_pkg_list(differ, "unreproducible", now)

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
            distributions.c.name == 'openwrt',
            sources.c.suite == bindparam('suite'),
            sources.c.architecture == bindparam('arch')
        )
    )
    cur_pkgs = query_db(cur_pkgs.params({'suite': 'factory', 'arch': 'x86_64'}))

    builds = []
    for pkg in cur_pkgs:
        # (id, name, version, suite, architecture)
        data = pkgs_b[(pkg[1], pkg[2])]
        p = {
            'package_id': pkg[0],
            'version': pkg[2],
            'status': pkg['status'],
            'build_date': data['build_date'],
            'build_duration': data['build_duration'],
            'job': 'external',
        }
        builds.append(p)
    if builds:
        transaction = conn_db.begin()
        conn_db.execute(results.insert(), builds)
    transaction.commit()

def example():
    import io

    package_list = io.StringIO(download_manifest)
    packages = parse_packages(package_list)

    for pkg in packages:
        print(pkg['Filename'])

def main():
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument('packagea', nargs=1, type=argparse.FileType('r'),
                        help='The first package list')
    parser.add_argument('packageb', nargs=1, type=argparse.FileType('r'),
                        help='The second package list')
    args = parser.parse_args()

    result = show_list_difference(args.packagea[0], args.packageb[0])
    insert_into_db(result)

if __name__ == "__main__":
    main()
