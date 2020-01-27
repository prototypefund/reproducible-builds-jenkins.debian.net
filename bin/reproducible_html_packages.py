#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015-2018 Mattia Rizzolo <mattia@mapreri.org>
# Copyright © 2016-2017 Valerie R Young <spectranaut@riseup.net>
# Based on reproducible_html_packages.sh © 2014 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2
#
# Depends: python3
#
# Build rb-pkg pages (the pages that describe the package status)

import os
import errno
import urllib
import pystache
import apt_pkg
import sqlalchemy
apt_pkg.init_system()

from rblib import query_db
from rblib.confparse import log, args
from rblib.models import Package, Status
from rblib.utils import strip_epoch, convert_into_hms_string
from rblib.html import gen_status_link_icon, write_html_page
from rblib.const import (
    DISTRO,
    TEMPLATE_PATH,
    REPRODUCIBLE_URL,
    DISTRO_URL,
    SUITES, ARCHS,
    RB_PKG_PATH, RB_PKG_URI,
    HISTORY_PATH, HISTORY_URI,
    NOTES_PATH, NOTES_URI,
    DBDTXT_PATH, DBDTXT_URI,
    DBDJSON_PATH, DBDJSON_URI,
    DBD_PATH, DBD_URI,
#    DIFFS_PATH, DIFFS_URI,
#    LOGS_PATH, LOGS_URI,
)


# Templates used for creating package pages
renderer = pystache.Renderer();
package_page_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'package_page'))
package_navigation_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'package_navigation'))
suitearch_section_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'package_suitearch_section'))
suitearch_details_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'package_suitearch_details'))
project_links_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'project_links'))
package_history_template = renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'package_history'))


def sizeof_fmt(num):
    for unit in ['B','KB','MB','GB']:
        if abs(num) < 1024.0:
            if unit == 'GB':
                log.error('The size of this file is bigger than 1 GB!')
                log.error('Please check')
            return str(int(round(float("%3f" % num), 0))) + "%s" % (unit)
        num /= 1024.0
    return str(int(round(float("%f" % num), 0))) + "%s" % ('Yi')


def get_dbd_links(package, eversion, suite, arch):
    """Returns dictionary of links to diffoscope pages.

    dictionary keys:
    dbd_uri -- included only if file for formatted diffoscope results exists
    dbdtxt_uri -- included only if file for unformatted diffoscope results
                  exists
    dbdjson_uri -- included only if file for JSON-formatted diffoscope results
                  exists
    dbd_page_uri -- included only if file for formatted diffoscope results
                    (dbd_uri) exists. This uri is a package page with diffoscope
                    results in main iframe by default.
    dbd_page_file -- always returned, check existence of dbd_uri to know whether
                     it this file is valid
    """
    dbd_file = os.path.join(DBD_PATH, suite, arch, package + '_' + eversion
                       + '.diffoscope.html')
    dbdtxt_file = os.path.join(DBDTXT_PATH, suite, arch, package + '_' + eversion
                          + '.diffoscope.txt.gz')
    dbdjson_file = os.path.join(DBDJSON_PATH, suite, arch, package + '_' + eversion
                          + '.diffoscope.json.gz')
    dbd_page_file = os.path.join(RB_PKG_PATH, suite, arch, 'diffoscope-results',
                                 package + '.html')
    dbd_uri = DBD_URI + '/' + suite + '/' + arch + '/' +  package + '_' + \
              eversion + '.diffoscope.html'
    dbdtxt_uri = DBDTXT_URI + '/' + suite + '/' + arch + '/' +  package + '_' + \
                eversion + '.diffoscope.txt.gz'
    dbdjson_uri = DBDJSON_URI + '/' + suite + '/' + arch + '/' +  package + '_' + \
                eversion + '.diffoscope.json.gz'
    dbd_page_uri = RB_PKG_URI + '/' + suite + '/' + arch + \
                   '/diffoscope-results/' + package + '.html'
    links = {}
    # only return dbd_uri and dbdtext_uri if they exist
    if os.access(dbd_file, os.R_OK):
        links['dbd_uri'] = dbd_uri
        links['dbd_page_uri'] = dbd_page_uri
        if os.access(dbdtxt_file, os.R_OK):
            links['dbdtxt_uri'] = dbdtxt_uri
        if os.access(dbdjson_file, os.R_OK):
            links['dbdjson_uri'] = dbdjson_uri

    # always return dbd_page_file, because we might need to delete it
    links['dbd_page_file'] = dbd_page_file
    return links


def get_and_clean_dbd_links(package, eversion, suite, arch, status):
    links = get_dbd_links(package, eversion, suite, arch)

    dbd_links = {}
    if 'dbd_uri' in links:
        dbd_links = {
            'dbd_page_file': links['dbd_page_file'],
            'dbd_page_uri': links['dbd_page_uri'],
            'dbd_uri': links['dbd_uri'],
        }
    else:
        if status == 'FTBR' and not args.ignore_missing_files:
            log.critical(DISTRO_URL + '/' + suite + '/' + arch + '/' + package +
                         ' is unreproducible, but without diffoscope output.')
        # if there are no diffoscope results, we want to remove the old package
        # page used to display diffoscope results
        if os.access(links['dbd_page_file'], os.R_OK):
            os.remove(links['dbd_page_file'])

    return dbd_links


def gen_suitearch_details(package, version, suite, arch, status, spokenstatus,
                          build_date):
    eversion = strip_epoch(version) # epoch_free_version is too long
    pkg = Package(package)
    build = pkg.builds[suite][arch]

    context = {}
    default_view = ''

    # Make notes the default default view
    notes_file = NOTES_PATH + '/' + package + '_note.html'
    notes_uri = NOTES_URI + '/' + package + '_note.html'
    if os.access(notes_file, os.R_OK):
        default_view = notes_uri

    # Get summary context
    context['status_html'] = gen_status_link_icon(status, spokenstatus, None,
                                                  suite, arch)
    context['build_date'] =  build_date

    # Get diffoscope differences context
    dbd_links = get_dbd_links(package, eversion, suite, arch)
    dbd_uri = dbd_links.get('dbd_uri', '')
    if dbd_uri:
        context['dbd'] = {
            'dbd_page_uri': dbd_links['dbd_page_uri'],
            'dbdtxt_uri': dbd_links.get('dbdtxt_uri', ''),
            'dbdjson_uri': dbd_links.get('dbdjson_uri', ''),
        }
        default_view = default_view if default_view else dbd_uri

    # Get buildinfo context
    if build.buildinfo:
        context['buildinfo_uri'] = build.buildinfo.url
        default_view = default_view if default_view else build.buildinfo.url
    elif not args.ignore_missing_files and status not in \
        ('untested', 'blacklisted', 'FTBFS', 'NFU', 'depwait', '404'):
            log.critical('buildinfo not detected at ' + build.buildinfo.path)

    # Get rbuild, build2 and build diffs context
    if build.rbuild:
        context['rbuild_uri'] = build.rbuild.url
        context['rbuild_size'] = sizeof_fmt(build.rbuild.size)
        default_view = default_view if default_view else build.rbuild.url
        context['buildlogs'] = {}
        if build.build2 and build.logdiff:
            context['buildlogs']['build2_uri'] = build.build2.url
            context['buildlogs']['build2_size'] = sizeof_fmt(build.build2.size)
            context['buildlogs']['diff_uri'] = build.logdiff.url
        else:
            log.error('Either {} or {} is missing'.format(
                build.build2.path, build.logdiff.path))
    elif status not in ('untested', 'blacklisted') and \
         not args.ignore_missing_files:
        log.critical(DISTRO_URL  + '/' + suite + '/' + arch + '/' + package +
                     ' didn\'t produce a buildlog, even though it has been built.')

    context['has_buildloginfo'] = 'buildinfo_uri' in context or \
                                  'buildlogs' in context or \
                                  'rbuild_uri' in context

    default_view = '/untested.html' if not default_view else default_view
    suitearch_details_html = renderer.render(suitearch_details_template, context)
    return (suitearch_details_html, default_view)


def determine_reproducibility(status1, version1, status2, version2):
    versionscompared = apt_pkg.version_compare(version1, version2);

    # if version1 > version2,
    # ignore the older package (version2)
    if (versionscompared > 0):
        return status1, version1

    # if version1 < version2,
    # ignore the older package (version1)
    elif (versionscompared < 0):
        return status2, version2

    # if version1 == version 2,
    # we are comparing status for the same (most recent) version
    else:
        if status1 == 'reproducible' and status2 == 'reproducible':
            return 'reproducible', version1
        else:
            return 'not_reproducible', version1


def gen_suitearch_section(package, current_suite, current_arch):
    # keep track of whether the package is entirely reproducible
    final_version = ''
    final_status = ''

    default_view = ''
    context = {}
    context['architectures'] = []
    for a in ARCHS:

        suites = []
        for s in reversed(SUITES):

            status = package.builds[s][a].status
            if not status:  # The package is not available in that suite/arch
                continue
            version = package.builds[s][a].version

            if not final_version or not final_status:
                final_version = version
                final_status = status
            else:
                final_status, final_version = determine_reproducibility(
                    final_status, final_version, status, version)

            build_date = package.builds[s][a].build_date
            status = Status.get(status)

            if not (build_date and status != 'blacklisted'):
                build_date = ''

            li_classes = ['suite']
            if s == current_suite and a == current_arch:
                li_classes.append('active')
            package_uri = ('{}/{}/{}/{}.html').format(RB_PKG_URI, s, a, package.name)

            suitearch_details_html = ''
            if (s == current_suite and a == current_arch):
                suitearch_details_html, default_view = gen_suitearch_details(
                    package.name, version, s, a,
                    status.value.name, status.value.spokenstatus, build_date)

            dbd_links = get_dbd_links(package.name, strip_epoch(version), s, a)
            dbd_page_uri = dbd_links.get('dbd_page_uri', '')
            suites.append({
                'package': package.name,
                'package_quote_plus': urllib.parse.quote_plus(package.name),
                'status': status.value.name,
                'version': version,
                'build_date': build_date,
                'icon': status.value.icon,
                'spokenstatus': status.value.spokenstatus,
                'li_classes': ' '.join(li_classes),
                'arch': a,
                'suite': s,
                'untested': status == Status.UNTESTED,
                'current_suitearch': s == current_suite and a == current_arch,
                'package_uri': package_uri,
                'suitearch_details_html': suitearch_details_html,
                'dbd_page_uri': dbd_page_uri
            })

        if len(suites):
            context['architectures'].append({
                'arch': a,
                'suites': suites,
            })

    html = renderer.render(suitearch_section_template, context)
    reproducible = True if final_status == 'reproducible' else False
    return html, default_view, reproducible

def shorten_if_debiannet(hostname):
    if hostname[-11:] == '.debian.net':
        hostname = hostname[:-11]
    return hostname

def gen_history_page(package, arch=None):
    keys = ['build date', 'version', 'suite', 'architecture', 'result',
        'build duration', 'node1', 'node2', 'job']

    context = {}
    try:
        package.history[0]  # we don't care about the actual value, it jst need to exist
    except IndexError:
        context['arch'] = arch
    else:
        context['keys'] = [{'key': key} for key in keys]
        rows = []
        for r in package.history:
            # make a copy, since we modify in place
            record = dict(r)
            # skip records for suites that are unknown to us (i.e. other distro)
            if record['suite'] not in SUITES:
                continue
            # skip records for other archs if we care about arch
            if arch and record['architecture'] != arch:
                continue
            # remove trailing .debian.net from hostnames
            record['node1'] = shorten_if_debiannet(record['node1'])
            record['node2'] = shorten_if_debiannet(record['node2'])
            # add icon to result
            status = Status.get(record['result'])
            result_html = '{spokenstatus}<img src="/static/{icon}" alt="{spokenstatus}" title="{spokenstatus}"/>'
            record['result'] = result_html.format(
                icon=status.value.icon, spokenstatus=status.value.spokenstatus)
            # human formatting of build duration
            record['build duration'] = convert_into_hms_string(
                int(record['build duration']))
            row_items = [{'item': record[key]} for key in keys]
            rows.append({'row_items': row_items})
        context['rows'] = rows

    html = renderer.render(package_history_template, context)
    if arch:
        destfile = os.path.join(HISTORY_PATH, arch, package.name+'.html')
    else:
        destfile = os.path.join(HISTORY_PATH, package.name+'.html')
    title = 'build history of {}'.format(package.name)
    if arch:
        title += ' on {}'.format(arch)
    write_html_page(title=title, body=html, destfile=destfile,
                    noendpage=True)

def gen_packages_html(packages, no_clean=False):
    """
    generate the /rb-pkg/package.HTML pages.
    packages should be a list of Package objects.
    """
    total = len(packages)
    log.info('Generating the pages of ' + str(total) + ' package(s)')
    for package in sorted(packages, key=lambda x: x.name):
        assert isinstance(package, Package)
        gen_history_page(package)
        for arch in ARCHS:
            gen_history_page(package, arch)

        pkg = package.name

        notes_uri = ''
        notes_file = NOTES_PATH + '/' + pkg + '_note.html'
        if os.access(notes_file, os.R_OK):
            notes_uri = NOTES_URI + '/' + pkg + '_note.html'

        for suite in SUITES:
            for arch in ARCHS:

                status = package.builds[suite][arch].status
                version = package.builds[suite][arch].version
                build_date = package.builds[suite][arch].build_date
                if status is None:  # the package is not in the checked suite
                    continue
                log.debug('Generating the page of %s/%s/%s @ %s built at %s',
                          pkg, suite, arch, version, build_date)

                suitearch_section_html, default_view, reproducible = \
                    gen_suitearch_section(package, suite, arch)

                history_uri = '{}/{}.html'.format(HISTORY_URI, pkg)
                history_archs = []
                for a in ARCHS:
                    history_archs.append({
                        'history_arch': a,
                        'history_arch_uri': '{}/{}/{}.html'.format(HISTORY_URI, a, pkg)
                    })
                project_links = renderer.render(project_links_template)
                desturl = '{}{}/{}/{}/{}.html'.format(
                    REPRODUCIBLE_URL,
                    RB_PKG_URI,
                    suite,
                    arch,
                    pkg,
                )

                navigation_html = renderer.render(package_navigation_template, {
                    'package': pkg,
                    'suite': suite,
                    'arch': arch,
                    'version': version,
                    'history_uri': history_uri,
                    'history_archs': history_archs,
                    'notes_uri': notes_uri,
                    'notify_maintainer': package.notify_maint,
                    'suitearch_section_html': suitearch_section_html,
                    'project_links_html': project_links,
                    'reproducible': reproducible,
                    'dashboard_url': DISTRO_URL,
                    'desturl': desturl,
                })

                body_html = renderer.render(package_page_template, {
                    'default_view': default_view,
                })

                destfile = os.path.join(RB_PKG_PATH, suite, arch, pkg + '.html')
                title = pkg + ' - reproducible builds result'
                write_html_page(title=title, body=body_html, destfile=destfile,
                                no_header=True, noendpage=True,
                                left_nav_html=navigation_html)
                log.debug("Package page generated at " + desturl)

                # Optionally generate a page in which the main iframe shows the
                # diffoscope results by default. Needed for navigation between
                # diffoscope pages for different suites/archs
                eversion = strip_epoch(version)
                dbd_links = get_and_clean_dbd_links(pkg, eversion, suite, arch,
                                                    status)
                # only generate the diffoscope page if diffoscope results exist
                if 'dbd_uri' in dbd_links:
                    body_html = renderer.render(package_page_template, {
                        'default_view': dbd_links['dbd_uri'],
                    })
                    destfile = dbd_links['dbd_page_file']
                    desturl = REPRODUCIBLE_URL + "/" + dbd_links['dbd_page_uri']
                    title = "{} ({}) diffoscope results in {}/{}".format(
                        pkg, version, suite, arch)
                    write_html_page(title=title, body=body_html, destfile=destfile,
                                    no_header=True, noendpage=True,
                                    left_nav_html=navigation_html)
                    log.debug("Package diffoscope page generated at " + desturl)

    if not no_clean:
        purge_old_pages()  # housekeep is always good


def gen_all_rb_pkg_pages(no_clean=False):
    query = (
        'SELECT DISTINCT s.name '
        'FROM sources s JOIN distributions d ON d.id=s.distribution '
        'WHERE d.name=:d AND s.suite = ANY(:s)'
    )
    rows = query_db(sqlalchemy.text(query), d=DISTRO, s=SUITES)
    pkgs = [Package(str(i[0]), no_notes=True) for i in rows]
    log.info('Processing all %s package from all suites/architectures',
             len(pkgs))
    gen_packages_html(pkgs, no_clean=True)  # we clean at the end
    purge_old_pages()


def purge_old_pages():
    for suite in SUITES:
        for arch in ARCHS:
            log.info('Removing old pages from ' + suite + '/' + arch + '.')
            try:
                presents = sorted(os.listdir(RB_PKG_PATH + '/' + suite + '/' +
                                  arch))
            except OSError as e:
                if e.errno != errno.ENOENT:  # that's 'No such file or
                    raise                    # directory' error (errno 17)
                presents = []
            log.debug('page presents: ' + str(presents))

            # get the existing packages
            query = (
                "SELECT s.name, s.suite, s.architecture "
                "FROM sources s JOIN distributions d on d.id=s.distribution "
                "WHERE s.suite=:suite AND s.architecture=:arch "
                "AND d.name=:dist"
            )
            cur_pkgs = set([
                (p.name, p.suite, p.architecture) for p in query_db(
                    sqlalchemy.text(query), suite=suite, arch=arch, dist=DISTRO)
            ])

            for page in presents:
                # When diffoscope results exist for a package, we create a page
                # that displays the diffoscope results by default in the main iframe
                # in this subdirectory. Ignore this directory.
                if page == 'diffoscope-results':
                    continue
                pkg = page.rsplit('.', 1)[0]

                if (pkg, suite, arch) not in cur_pkgs:
                    log.info('There is no package named ' + pkg + ' from ' +
                             suite + '/' + arch + ' in the database. ' +
                             'Removing old page.')
                    os.remove(RB_PKG_PATH + '/' + suite + '/' + arch + '/' +
                              page)

            # Additionally clean up the diffoscope results default pages
            log.info('Removing old pages from ' + suite + '/' + arch +
                     '/diffoscope-results/.')
            try:
                presents = sorted(os.listdir(RB_PKG_PATH + '/' + suite + '/' +
                                             arch + '/diffoscope-results'))
            except OSError as e:
                if e.errno != errno.ENOENT:  # that's 'No such file or
                    raise                    # directory' error (errno 17)
                presents = []
            log.debug('diffoscope page presents: ' + str(presents))
            for page in presents:
                pkg = page.rsplit('.', 1)[0]
                if (pkg, suite, arch) not in cur_pkgs:
                    log.info('There is no package named ' + pkg + ' from ' +
                             suite + '/' + arch + '/diffoscope-results in ' +
                             'the database. Removing old page.')
                    os.remove(RB_PKG_PATH + '/' + suite + '/' + arch + '/' +
                              'diffoscope-results/' + page)
