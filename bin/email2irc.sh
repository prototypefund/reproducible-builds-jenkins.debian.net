#!/bin/bash

# Copyright 2012-2017 Holger Levsen <holger@layer-acht.org>
#           ©    2018 Mattia Rizzolo <mattia@debian.org>
# released under the GPLv=2

# called by ~jenkins/.procmailrc
# to turn jenkins email notifications into irc announcements with kgb
# see https://salsa.debian.org/kgb-team/kgb/wikis/home
#
LOGFILE=/var/log/jenkins/email.log

rmtmp() {
    rm -f "$TMPFILE"
}
TMPFILE=$(mktemp email2irc-XXXXXXX)
trap rmtmp INT TERM EXIT
cat > "$TMPFILE"

# try to run the new script to see how it goes
/srv/jenkins/bin/email2irc.py "$TMPFILE" 2>&1 >> "$LOGFILE"

if [ $? -ne 0 ]; then
    # email2irc failed to parse the file, mail it for further investigation
    echo "@@@@ email2irc failed" >> $LOGFILE
fi
