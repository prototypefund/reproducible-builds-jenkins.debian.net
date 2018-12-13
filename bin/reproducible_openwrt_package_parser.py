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

def insert_into_db(result):
    from pprint import pprint
    same, alone_a, alone_b, differ = result

    for pkg in same:
        pprint(pkg)

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
