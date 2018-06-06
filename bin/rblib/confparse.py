#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2015-2018 Mattia Rizzolo <mattia@debian.org>
# Copyright © 2015-2017 Holger Levsen <holger@layer-acht.org>
# Licensed under GPL-2


import os
import sys
import atexit
import logging
import argparse
import configparser
from datetime import datetime

DEBUG = False
QUIET = False

__location__ = os.path.realpath(
    os.path.join(os.getcwd(), os.path.dirname(__file__), '..'))

CONFIG = os.path.join(__location__, 'reproducible.ini')

# command line option parsing
parser = argparse.ArgumentParser()
group = parser.add_mutually_exclusive_group()
parser.add_argument('--distro', help='name of the distribution to work on',
                    default='debian', nargs='?')
group.add_argument("-d", "--debug", action="store_true")
group.add_argument("-q", "--quiet", action="store_true")
parser.add_argument("--skip-database-connection", action="store_true",
                    help="skip connecting to database")
parser.add_argument("--ignore-missing-files", action="store_true",
                    help="useful for local testing, where you don't have all "
                    "the build logs, etc..")
args, unknown_args = parser.parse_known_args()
DISTRO = args.distro
log_level = logging.INFO
if args.debug or DEBUG:
    DEBUG = True
    log_level = logging.DEBUG
if args.quiet or QUIET:
    log_level = logging.ERROR
log = logging.getLogger(__name__)
log.setLevel(log_level)
sh = logging.StreamHandler()
sh.setFormatter(logging.Formatter(
    '[%(asctime)s] %(levelname)s: %(message)s', datefmt='%Y-%m-%d %H:%M:%S'))
log.addHandler(sh)

started_at = datetime.now()
log.info('Starting at %s', started_at)


# load configuration
config = configparser.ConfigParser()
config.read(CONFIG)
try:
    conf_distro = config[DISTRO]
except KeyError:
    log.critical('Distribution %s is not known.', DISTRO)
    sys.exit(1)


@atexit.register
def print_time():
    log.info('Finished at %s, took: %s', datetime.now(),
             datetime.now()-started_at)
