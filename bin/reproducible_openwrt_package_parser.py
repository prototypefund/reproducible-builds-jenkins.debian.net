#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright Alexander Couzens <lynxis@fe80.eu> 2018, 2019
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
        if line == '\n' or line == '':
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
    results_tbl = db_table('results')
    sources_tbl = db_table('sources')

    distro_id = query_db(
        select([distributions.c.id]).where(distributions.c.name == 'openwrt')
        )[0][0]

    src_pkgs = []
    build_pkgs = {}
    now = datetime.now()

    # query for a source package with name, version
    query_src_pkg = select(
        [sources_tbl.c.id, sources_tbl.c.name, sources_tbl.c.version,
         sources_tbl.c.suite, sources_tbl.c.architecture]
    ).select_from(
        sources_tbl.join(distributions)
    ).where(
        and_(
            distributions.c.name == 'openwrt',
            sources_tbl.c.name == bindparam('name'),
            sources_tbl.c.version == bindparam('version')
        )
    )

    query_results_pkg = select(
        [results_tbl.c.id]
    ).where(results_tbl.c.package_id == bindparam('package_id'))

    def insert_pkg_list(pkg_list, state, timestamp):
        # Add new data
        for pkg in pkg_list:
            entry = pkg_list[pkg][0]
            package = {
                'name': pkg,
                'version': entry['Version'],
                'suite': suite,
                'architecture': entry['Architecture'],
                'distribution': distro_id
            }
            src_pkgs.append(package)
            data = {
                'status': state,
                'build_date': timestamp,
                'build_duration': 2342,
            }
            build_pkgs[(entry['package'], entry['version'])] = data

    # parse the pkg lists into our structure
    insert_pkg_list(same, "reproducible", now)
    insert_pkg_list(alone_a, "FTBFS on B", now)
    insert_pkg_list(alone_b, "FTBFS on A", now)
    insert_pkg_list(differ, "unreproducible", now)

    # import new source packages if they are not yet present
    new_src_pkgs = []
    for pkg in src_pkgs:
        db_pkg = query_db(query_src_pkg.params({'name': pkg['name'], 'version': pkg['version']}))
        if db_pkg:
            continue
        new_src_pkgs.append(pkg)

    if new_src_pkgs:
        log.info('Found new source packages. Adding to the database')
        transaction = conn_db.begin()
        conn_db.execute(sources_tbl.insert(), new_src_pkgs)
        transaction.commit()

    log.info('Injecting build results…')
    results = []
    for pkg in build_pkgs:
        # pkg = ("<package_name>", "<package_version>"
        data = build_pkgs[pkg]

        # search for the source package
        db_pkg = query_db(query_src_pkg.params({'name': pkg[0], 'version': pkg[1]}))
        if not db_pkg:
            log.warning("Could not find the source package for %s version %s", pkg[0], pkg[1])
            continue
        db_pkg = db_pkg[0]

        # search results and remove it
        result_pkg = query_db(query_results_pkg.params({'package_id': db_pkg[0]}))
        if result_pkg:
            transaction = conn_db.begin()
            query_db(results_tbl.delete(results_tbl.c.package_id == db_pkg[0]))
            transaction.commit()

        bin_pkg = {
            'package_id': db_pkg[0],
            'version': pkg[1],
            'status': data['status'],
            'build_date': data['build_date'],
            'build_duration': data['build_duration'],
            'job': 'external',
        }
        results.append(bin_pkg)

    # add new results
    if results:
        transaction = conn_db.begin()
        conn_db.execute(results_tbl.insert(), results)
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
