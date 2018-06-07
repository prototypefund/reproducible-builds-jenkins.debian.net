#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015-2018 Mattia Rizzolo <mattia@debian.org>
# Copyright © 2015-2017 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2

import os
import re
import subprocess
from tempfile import NamedTemporaryFile

from rblib.consts import log, TEMP_PATH, JOB_NAME

url2html = re.compile(r'((mailto\:|((ht|f)tps?)\://|file\:///){1}\S+)')


def print_critical_message(msg):
    print('\n\n\n')
    try:
        for line in msg.splitlines():
            log.critical(line)
    except AttributeError:
        log.critical(msg)
    print('\n\n\n')


def create_temp_file(mode='w+b'):
    os.makedirs(TEMP_PATH, exist_ok=True)
    return NamedTemporaryFile(suffix=JOB_NAME, dir=TEMP_PATH, mode=mode)


def convert_into_hms_string(duration):
    if not duration:
        duration = ''
    else:
        duration = int(duration)
        hours = int(duration/3600)
        minutes = int((duration-(hours*3600))/60)
        seconds = int(duration-(hours*3600)-(minutes*60))
        duration = ''
        if hours > 0:
            duration = str(hours)+'h ' + str(minutes)+'m ' + str(seconds) + 's'
        elif minutes > 0:
            duration = str(minutes)+'m ' + str(seconds) + 's'
        else:
            duration = str(seconds)+'s'
    return duration


def strip_epoch(version):
    """
    Stip the epoch out of the version string. Some file (e.g. buildlogs, debs)
    do not have epoch in their filenames.
    """
    try:
        return version.split(':', 1)[1]
    except IndexError:
        return version


def irc_msg(msg, channel='debian-reproducible'):
    kgb = ['kgb-client', '--conf', '/srv/jenkins/kgb/%s.conf' % channel,
           '--relay-msg']
    kgb.extend(str(msg).strip().split())
    subprocess.run(kgb)
