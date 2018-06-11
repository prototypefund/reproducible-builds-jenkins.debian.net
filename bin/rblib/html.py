# -*- coding: utf-8 -*-
#
# Copyright © 2015-2018 Mattia Rizzolo <mattia@debian.org>
# Copyright © 2015-2017 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2

import os
import errno
import hashlib
import pystache
from datetime import datetime

from .confparse import log, conf_distro
from .const import (
    defaultsuite, defaultarch,
    SUITES, ARCHS,
    DISTRO_DASHBOARD_URI,
    JENKINS_URL, JOB_URL, JOB_NAME,
    TEMPLATE_PATH, REPRODUCIBLE_STYLES,
)


tab = '  '

# take a SHA1 of the css page for style version
_hasher = hashlib.sha1()
with open(REPRODUCIBLE_STYLES, 'rb') as f:
        _hasher.update(f.read())
REPRODUCIBLE_STYLE_SHA1 = _hasher.hexdigest()

# Templates used for creating package pages
_renderer = pystache.Renderer()
status_icon_link_template = _renderer.load_template(
    TEMPLATE_PATH + '/status_icon_link')
default_page_footer_template = _renderer.load_template(
    TEMPLATE_PATH + '/default_page_footer')
pkg_legend_template = _renderer.load_template(
    TEMPLATE_PATH + '/pkg_symbol_legend')
project_links_template = _renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'project_links'))
main_navigation_template = _renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'main_navigation'))
basic_page_template = _renderer.load_template(
    os.path.join(TEMPLATE_PATH, 'basic_page'))


def _create_default_page_footer(date):
    return _renderer.render(default_page_footer_template, {
            'date': date,
            'job_url': JOB_URL,
            'job_name': JOB_NAME,
            'jenkins_url': JENKINS_URL,
        })


def _gen_suite_arch_nav_context(suite, arch, suite_arch_nav_template=None,
                                ignore_experimental=False, no_suite=None,
                                no_arch=None):
    # if a template is not passed in to navigate between suite and archs the
    # current page, we use the "default" suite/arch summary view.
    default_nav_template = \
            '/{{distro}}/{{suite}}/index_suite_{{arch}}_stats.html'
    if not suite_arch_nav_template:
        suite_arch_nav_template = default_nav_template

    suite_list = []
    if not no_suite:
        for s in SUITES:
            include_suite = True
            if s == 'experimental' and ignore_experimental:
                include_suite = False
            suite_list.append({
                's': s,
                'class': 'current' if s == suite else '',
                'uri': _renderer.render(suite_arch_nav_template,
                                       {'distro': conf_distro['distro_root'],
                                        'suite': s, 'arch': arch})
                if include_suite else '',
            })

    arch_list = []
    if not no_arch:
        for a in ARCHS:
            arch_list.append({
                'a': a,
                'class': 'current' if a == arch else '',
                'uri': _renderer.render(suite_arch_nav_template,
                                       {'distro': conf_distro['distro_root'],
                                        'suite': suite, 'arch': a}),
            })
    return (suite_list, arch_list)


# See bash equivelent: reproducible_common.sh's "write_page_header()"
def create_main_navigation(suite=defaultsuite, arch=defaultarch,
                           displayed_page=None, suite_arch_nav_template=None,
                           ignore_experimental=False, no_suite=None,
                           no_arch=None):
    suite_list, arch_list = _gen_suite_arch_nav_context(suite, arch,
            suite_arch_nav_template, ignore_experimental, no_suite, no_arch)
    context = {
        'suite': suite,
        'arch': arch,
        'project_links_html': _renderer.render(project_links_template),
        'suite_nav': {
            'suite_list': suite_list
        } if len(suite_list) else '',
        'arch_nav': {
            'arch_list': arch_list
        } if len(arch_list) else '',
        'debian_uri': DISTRO_DASHBOARD_URI,
        'cross_suite_arch_nav': True if suite_arch_nav_template else False,
    }
    if suite != 'experimental':
        # there are not package sets in experimental
        context['include_pkgset_link'] = True
    # the "display_page" argument controls which of the main page navigation
    # items will be highlighted.
    if displayed_page:
        context[displayed_page] = True
    return _renderer.render(main_navigation_template, context)


def write_html_page(title, body, destfile, no_header=False, style_note=False,
                    noendpage=False, refresh_every=None, displayed_page=None,
                    left_nav_html=None):
    meta_refresh_html = '<meta http-equiv="refresh" content="%d"></meta>' % \
        refresh_every if refresh_every is not None else ''
    if style_note:
        body += _renderer.render(pkg_legend_template, {})
    if not noendpage:
        now = datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')
        body += _create_default_page_footer(now)
    context = {
        'page_title': title,
        'meta_refresh_html': meta_refresh_html,
        'navigation_html': left_nav_html,
        'main_header': title if not no_header else "",
        'main_html': body,
        'style_dot_css_sha1sum': REPRODUCIBLE_STYLE_SHA1,
    }
    html = _renderer.render(basic_page_template, context)

    try:
        os.makedirs(destfile.rsplit('/', 1)[0], exist_ok=True)
    except OSError as e:
        if e.errno != errno.EEXIST:  # that's 'File exists' error (errno 17)
            raise
    log.debug("Writing " + destfile)
    with open(destfile, 'w', encoding='UTF-8') as fd:
        fd.write(html)


def gen_status_link_icon(status, spokenstatus, icon, suite, arch):
    """
    Returns the html for "<icon> <spokenstatus>" with both icon and status
    linked to the appropriate index page for the status, arch and suite.

    If icon is set to None, the icon will be ommited.
    If spokenstatus is set to None, the spokenstatus link be ommited.
    """
    context = {
        'status': status,
        'spokenstatus': spokenstatus,
        'icon': icon,
        'suite': suite,
        'arch': arch,
        'untested': True if status == 'untested' else False,
    }
    return _renderer.render(status_icon_link_template, context)
