#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2018 Mattia Rizzolo <mattia@mapreri.org>
# Based on the email2irc.sh by © 2012-2017 Holger Levsen <holger@layer-acht.org>
#
# Released under the GPLv2

import re
import sys
import argparse
import email
import email.parser
import email.policy
from subprocess import run, CalledProcessError
from email.utils import getaddresses, parseaddr

parser = argparse.ArgumentParser()
parser.add_argument('-n', '--dry-run', action='store_true')
parser.add_argument('origin_file', metavar='email',
        help='file containing the email to be relayed to IRC')
args = parser.parse_args()


def error(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)
    sys.exit(1)


try:
    with open(args.origin_file, 'rb') as f:
        ep = email.parser.BytesParser(policy=email.policy.compat32)
        message = ep.parse(f)
except FileNotFoundError:
    error('E: file [{}] not found'.format(args.origin_file))

# From
origin = parseaddr(message.get('From'))[1]
if origin is None:
    error('This email does not contain a "From" header')
if origin != 'jenkins@jenkins.debian.net':
    error('E: This email is not from jenkins: {}'.format(message['From']))

# Subject
subject = message.get('Subject')
if subject is None:
    error('E: This email does not contain a "Subject" header')
subject = subject.replace('\n', ' ')

# X-Jenkins-Job
jenkins_job = message.get('X-Jenkins-Job')
if jenkins_job is None:
    error('E: This email does not originate from a jenkins job')

# Date
date = message.get('Date')
if date is None:
    error('E: This email does not have a "Date" field')

# To
recipients = [a[1] for a in getaddresses(message.get_all('To', []))]
if not recipients:
    error('E: This email does not contain any address in the "To" header')
channels = []
for dest in recipients:
    # look for an address like jenkins+debian-boot@jenkins.debian.net
    regex = re.compile(r'^jenkins\+(.+)@jenkins\.debian\.net$')
    m = regex.search(dest)
    if m:
        channels.append(m.group(1))
if not channels:
    error('E: This email does not contain any IRC channel in its recipients')

# Body
for part in message.walk():
    if part.get_content_type() == 'text/plain':
        # Get only the first line
        fline = part.get_payload(decode=True).splitlines()[0]
        fline = fline.decode('utf-8', errors='replace')
        fline = ' '.join(fline.split()[:2])
        break
else:
    error('E: This email does not contain any text/plain part')


# If we got this far, the message is good to go and we got everything we
# needed.

ircmsg = '{} {}'.format(subject.split(':', 1)[0], fline)
ircmsg = re.sub(r'[<>]', r'', ircmsg)
ircmsg = re.sub(r'^Failure', r'Failed ', ircmsg)
ircmsg = re.sub(r'^Build failed in Jenkins', r'Failed ', ircmsg)
ircmsg = re.sub(r'^Jenkins build is back to (normal|stable)', r'Fixed ', ircmsg)
ircmsg = re.sub(r'^Jenkins build became', r'Became', ircmsg)
ircmsg = re.sub(r'^Jenkins build is unstable', r'Unstable', ircmsg)
ircmsg = re.sub(r'^Jenkins build is still unstable', r'Still unstable', ircmsg)
ircmsg = re.sub(r'^Still Failing', r'Still failing', ircmsg)
ircmsg = re.sub(r' See ', r' ', ircmsg)
ircmsg = re.sub(r'Changes:', r'', ircmsg)
ircmsg = re.sub(r'\?page=changes$', r'', ircmsg)
ircmsg = re.sub(r'/(console|changes)$', r'', ircmsg)
ircmsg = re.sub(r'display/redirec.*\>$', r'', ircmsg)
ircmsg = re.sub(r'/$', r'', ircmsg)

print('''
-----------
valid email
-----------
Date:       {date}
Job:        {jenkins_job}
Channels:   {channels}
Subject:    {subject}
First line: {fline}
IRC msg:    {ircmsg}
'''.format(date=date, jenkins_job=jenkins_job, channels=channels,
    subject=subject, fline=fline, ircmsg=ircmsg)
)

if args.dry_run:
    print('Running in dry-run mode, not actually notifying kgb')
    sys.exit()

fail = 0
for ch in channels:
    print('Noifying kgb for {}...'.format(ch))
    try:
        p = run(['kgb-client', '--conf', '/srv/jenkins/kgb/{}.conf'.format(ch),
            '--relay-msg', ircmsg], check=True)
    except CalledProcessError as p:
        print('E: kgb-client returned an error (code {})'.format(p.returncode),
                file=sys.stderr)
    else:
        print('kgb informed successfully')
    finally:
        if p.stderr:
            print('stderr: [{}]'.format(p.stderr))
        if p.stdout:
            print('stdout: [{}]'.format(p.stdout))
    fail = fail | p.returncode

sys.exit(fail)
