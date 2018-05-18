#!/bin/bash
# vim: set noexpandtab:

# Copyright 2014-2017 Holger Levsen <holger@layer-acht.org>
#           ©    2018 Mattia Rizzolo <mattia@debian.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

# support different suites
if [ -z "$1" ] ; then
	SUITE="unstable"
else
	SUITE="$1"
fi

#
# create script to configure a pbuilder chroot
#
create_customized_tmpfile() {
	TMPFILE=$1
	shift
	cat >> $TMPFILE <<- EOF
#
# this script is run within the pbuilder environment to further customize initially
#
echo
echo "Preseeding man-db/auto-update to false"
echo "man-db man-db/auto-update boolean false" | debconf-set-selections
echo
echo "Configuring dpkg to not fsync()"
echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/02speedup
echo
EOF
	. /srv/jenkins/bin/jenkins_node_definitions.sh
	get_node_ssh_port "$HOSTNAME"
	if "$NODE_RUN_IN_THE_FUTURE" ; then
		cat >> $TMPFILE <<- EOF
			echo "Configuring APT to ignore the Release file expiration"
			echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/398future
			echo
		EOF
	fi

}

create_setup_our_repo_tmpfile() {
	TMPFILE=$1
	shift
	cat >> $TMPFILE <<- EOF
#
# this script is run within the pbuilder environment to further customize once more
#
echo "Configure the chroot to use the reproducible team experimental archive..."
echo "-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.12 (GNU/Linux)

mQINBFQsy/gBEADKGF55qQpXxpTn7E0Vvqho82/HFB/yT9N2wD8TkrejhJ1I6hfJ
zFXD9fSi8WnNpLc6IjcaepuvvO4cpIQ8620lIuONQZU84sof8nAO0LDoMp/QdN3j
VViXRXQtoUmTAzlOBNpyb8UctAoSzPVgO3jU1Ngr1LWi36hQPvQWSYPNmbsDkGVE
unB0p8DCN88Yq4z2lDdlHgFIy0IDNixuRp/vBouuvKnpe9zyOkijV83Een0XSUsZ
jmoksFzLzjChlS5fAL3FjtLO5XJGng46dibySWwYx2ragsrNUUSkqTTmU7bOVu9a
zlnQNGR09kJRM77UoET5iSXXroK7xQ26UJkhorW2lXE5nQ97QqX7igWp2u0G74RB
e6y3JqH9W8nV+BHuaCVmW0/j+V/l7T3XGAcbjZw1A4w5kj8YGzv3BpztXxqyHQsy
piewXLTBn8dvgDqd1DLXI5gGxC3KGGZbC7v0rQlu2N6OWg2QRbcVKqlE5HeZxmGV
vwGQs/vcChc3BuxJegw/bnP+y0Ys5tsVLw+kkxM5wbpqhWw+hgOlGHKpJLNpmBxn
T+o84iUWTzpvHgHiw6ShJK50AxSbNzDWdbo7p6e0EPHG4Gj41bwO4zVzmQrFz//D
txVBvoATTZYMLF5owdCO+rO6s/xuC3s04pk7GpmDmi/G51oiz7hIhxJyhQARAQAB
tC5EZWJpYW4gUmVwcm9kdWNpYmxlIEJ1aWxkcyBBcmNoaXZlIFNpZ25pbmcgS2V5
iQI9BBMBCAAnAhsDBQsJCAcDBRUKCQgLBRYDAgEAAh4BAheABQJakW5lBQkKJwlk
AAoJEF23ymfqWaMfAh0P/RJqbeTtlWYXKWIWU9y+DtJYKLECGhUxRymeIE4NQvkD
ffHgGKc6CiN7s3gVnWb/hJE9U7UjpQ0E2ufpneGT1JNNK2yCGWsC1ArFRD2ZCdKF
xDzY9zkh6I9t87Qznb1zfbEkbru89Z+V0Pg6ROMHqQR2fX+FwivblsevGJ27AtZ1
+hv1CzKdGooDSMJlhYxwR8I0jjoaVV8SI7Kbz+73vvXfrQGHu4gVR1Qlby+pD9NS
NydzmWdgWxBrSQdWg/K+U3AmLWnLTDcqa54G5S8jyyxMYLRWzVrkz3/CkH3E4qru
44sVit8GppLUiESR2O7gqDeVnALYNN0m0fiy3vige4AXl/T4R8GFoueCFu7aHN3V
kNjg2uIXUisyi123r5sb8AtsWYSYO9tocMDIzUxM2lyJAIhJNg+XJifGKxq3LSms
N13hh6PJsBYJN5H8ykYyHlteIKoYGkSPM8qxqm5nLc3skAuZsQloZhnDHSZmPAZO
zaIcpUkirRMKTCN4S9CBT6q1dHZwANgx9sn2Z7bWs6F5D//54BmYoHdVCWtptwUg
0hI7x8jS5PsAI5qQtdA48SBmknDuuLizD6HkJ3XX6PLQ/naaMCpillm0uTEUc0Rw
3t6mjgG4PvM7bVUNXK3mIjgY/IU5z/tDemzZywiI5sigUz0aBkKI4C4ugoWQdC4c
=LHVA
-----END PGP PUBLIC KEY BLOCK-----" > /etc/apt/trusted.gpg.d/reproducible.asc
# Let's Encrypt intermediary certificate, as found at
# https://letsencrypt.org/certs/letsencryptauthorityx3.pem.txt
# See also https://letsencrypt.org/certificates/
# This makes possible to use our repository with https without first installing
# the ca-certificates package.
echo "-----BEGIN CERTIFICATE-----
MIIFjTCCA3WgAwIBAgIRANOxciY0IzLc9AUoUSrsnGowDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTYxMDA2MTU0MzU1
WhcNMjExMDA2MTU0MzU1WjBKMQswCQYDVQQGEwJVUzEWMBQGA1UEChMNTGV0J3Mg
RW5jcnlwdDEjMCEGA1UEAxMaTGV0J3MgRW5jcnlwdCBBdXRob3JpdHkgWDMwggEi
MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCc0wzwWuUuR7dyXTeDs2hjMOrX
NSYZJeG9vjXxcJIvt7hLQQWrqZ41CFjssSrEaIcLo+N15Obzp2JxunmBYB/XkZqf
89B4Z3HIaQ6Vkc/+5pnpYDxIzH7KTXcSJJ1HG1rrueweNwAcnKx7pwXqzkrrvUHl
Npi5y/1tPJZo3yMqQpAMhnRnyH+lmrhSYRQTP2XpgofL2/oOVvaGifOFP5eGr7Dc
Gu9rDZUWfcQroGWymQQ2dYBrrErzG5BJeC+ilk8qICUpBMZ0wNAxzY8xOJUWuqgz
uEPxsR/DMH+ieTETPS02+OP88jNquTkxxa/EjQ0dZBYzqvqEKbbUC8DYfcOTAgMB
AAGjggFnMIIBYzAOBgNVHQ8BAf8EBAMCAYYwEgYDVR0TAQH/BAgwBgEB/wIBADBU
BgNVHSAETTBLMAgGBmeBDAECATA/BgsrBgEEAYLfEwEBATAwMC4GCCsGAQUFBwIB
FiJodHRwOi8vY3BzLnJvb3QteDEubGV0c2VuY3J5cHQub3JnMB0GA1UdDgQWBBSo
SmpjBH3duubRObemRWXv86jsoTAzBgNVHR8ELDAqMCigJqAkhiJodHRwOi8vY3Js
LnJvb3QteDEubGV0c2VuY3J5cHQub3JnMHIGCCsGAQUFBwEBBGYwZDAwBggrBgEF
BQcwAYYkaHR0cDovL29jc3Aucm9vdC14MS5sZXRzZW5jcnlwdC5vcmcvMDAGCCsG
AQUFBzAChiRodHRwOi8vY2VydC5yb290LXgxLmxldHNlbmNyeXB0Lm9yZy8wHwYD
VR0jBBgwFoAUebRZ5nu25eQBc4AIiMgaWPbpm24wDQYJKoZIhvcNAQELBQADggIB
ABnPdSA0LTqmRf/Q1eaM2jLonG4bQdEnqOJQ8nCqxOeTRrToEKtwT++36gTSlBGx
A/5dut82jJQ2jxN8RI8L9QFXrWi4xXnA2EqA10yjHiR6H9cj6MFiOnb5In1eWsRM
UM2v3e9tNsCAgBukPHAg1lQh07rvFKm/Bz9BCjaxorALINUfZ9DD64j2igLIxle2
DPxW8dI/F2loHMjXZjqG8RkqZUdoxtID5+90FgsGIfkMpqgRS05f4zPbCEHqCXl1
eO5HyELTgcVlLXXQDgAWnRzut1hFJeczY1tjQQno6f6s+nMydLN26WuU4s3UYvOu
OsUxRlJu7TSRHqDC3lSE5XggVkzdaPkuKGQbGpny+01/47hfXXNB7HntWNZ6N2Vw
p7G6OfY+YQrZwIaQmhrIqJZuigsrbe3W+gdn5ykE9+Ky0VgVUsfxo52mwFYs1JKY
2PGDuWx8M6DlS6qQkvHaRUo0FMd8TsSlbF0/v965qGFKhSDeQoMpYnwcmQilRh/0
ayLThlHLN81gSkJjVrPI0Y8xCVPB4twb1PFUd2fPM3sA1tJ83sZ5v8vgFv2yofKR
PB0t6JzUA81mSqM3kxl5e+IZwhYAyO0OTg3/fs8HqGTNKd9BqoUwSRBzp06JMg5b
rUCGwbCUDI0mxadJ3Bz4WxR6fyNpBK2yAinWEsikxqEt
-----END CERTIFICATE-----" > /etc/apt/letsencryptauthorityx3.pem
echo 'Acquire::https::CAInfo "/etc/apt/letsencryptauthorityx3.pem";' > /etc/apt/apt.conf.d/reproducible-ca
echo 'deb https://tests.reproducible-builds.org/debian/repository/debian/ ./' > /etc/apt/sources.list.d/reproducible.list
echo "Package: *
Pin: release o=reproducible
Pin-Priority: 1001" > /etc/apt/preferences.d/reproducible
echo
apt-get update
apt-get -y upgrade
apt-get install -y $@
echo
apt-cache policy
echo
dpkg -l
echo
for i in \$(dpkg -l |grep ^ii |awk -F' ' '{print \$2}'); do   apt-cache madison "\$i" | head -1 | grep reproducible.alioth.debian.org || true  ; done
echo
EOF
}


#
# setup pbuilder for reproducible builds
#
setup_pbuilder() {
	SUITE=$1
	shift
	NAME=$1
	shift
	PACKAGES="$@"						# from our repo
	EXTRA_PACKAGES="locales-all fakeroot disorderfs"	# from sid
	echo "$(date -u) - creating /var/cache/pbuilder/${NAME}.tgz now..."
	TMPFILE=$(mktemp --tmpdir=$TEMPDIR pbuilder-XXXXXXXXX)
	LOG=$(mktemp --tmpdir=$TEMPDIR pbuilder-XXXXXXXX)
	if [ "$SUITE" = "experimental" ] ; then
		SUITE=unstable
		echo "echo 'deb $MIRROR experimental main' > /etc/apt/sources.list.d/experimental.list" > ${TMPFILE}
		echo "echo 'deb-src $MIRROR experimental main' >> /etc/apt/sources.list.d/experimental.list" >> ${TMPFILE}
	fi
	# use host apt proxy configuration for pbuilder too
	if [ ! -z "$http_proxy" ] ; then
		echo "echo '$(cat /etc/apt/apt.conf.d/80proxy)' > /etc/apt/apt.conf.d/80proxy" >> ${TMPFILE}
		pbuilder_http_proxy="--http-proxy $http_proxy"
	fi
	# setup base.tgz
	sudo pbuilder --create $pbuilder_http_proxy --basetgz /var/cache/pbuilder/${NAME}-new.tgz --distribution $SUITE --extrapackages "$EXTRA_PACKAGES"

	# customize pbuilder
	create_customized_tmpfile ${TMPFILE}
	if [ "$DEBUG" = "true" ] ; then
		cat "$TMPFILE"
	fi
	sudo pbuilder --execute $pbuilder_http_proxy --save-after-exec --basetgz /var/cache/pbuilder/${NAME}-new.tgz -- ${TMPFILE} | tee ${LOG}
	rm ${TMPFILE}

	# add repo only for experimental and unstable - keep stretch/buster "real" (and sid progressive!)
	if [ "$SUITE" = "unstable" ] || [ "$SUITE" = "experimental" ]; then
		# apply further customisations, eg. install $PACKAGES from our repo
		create_setup_our_repo_tmpfile ${TMPFILE} "${PACKAGES}"
		if [ "$DEBUG" = "true" ] ; then
			cat "$TMPFILE"
		fi
		sudo pbuilder --execute $pbuilder_http_proxy --save-after-exec --basetgz /var/cache/pbuilder/${NAME}-new.tgz -- ${TMPFILE} | tee ${LOG}
		rm ${TMPFILE}
		if [ ! -z "$PACKAGES" ] ; then
			# finally, confirm things are as they should be
			echo
			echo "Now let's see whether the correct packages where installed..."
			for PKG in ${PACKAGES} ; do
				egrep "http://reproducible.alioth.debian.org/debian(/|) ./ Packages" ${LOG} \
					| grep -v grep | grep "${PKG} " \
					|| ( echo ; echo "Package ${PKG} is not installed at all or probably rather not in our version, so removing the chroot and exiting now." ; sudo rm -v /var/cache/pbuilder/${NAME}-new.tgz ; rm $LOG ; exit 1 )
			done
		fi
	fi

	sudo mv /var/cache/pbuilder/${NAME}-new.tgz /var/cache/pbuilder/${NAME}.tgz
	# create stamp file to record initial creation date minus some hours so the file will be older than 24h when checked in <24h...
	touch -d "$(date -u -d '6 hours ago' '+%Y-%m-%d %H:%M')" /var/log/jenkins/${NAME}.tgz.stamp
	rm ${LOG}
}

#
# main
#
BASETGZ=/var/cache/pbuilder/$SUITE-reproducible-base.tgz
STAMP=/var/log/jenkins/$SUITE-reproducible-base.tgz.stamp

if [ -f "$STAMP" ] ; then
	if [ -f "$STAMP" -a $(stat -c %Y "$STAMP") -gt $(date +%s) ]; then
		if [ $(stat -c %Y "$STAMP") -gt $(date +%s -d "+ 6 months") ]; then
			echo "Warning: stamp file is too far in the future, assuming something is wrong and deleting it"
			rm -v "$STAMP"
		else
			echo "stamp file has a timestamp from the future."
			exit 1
		fi
	fi
fi

OLDSTAMP=$(find $STAMP -mtime +1 -exec ls -lad {} \; || echo "nostamp")
if [ -n "$OLDSTAMP" ] || [ ! -f $BASETGZ ] || [ ! -f $STAMP ] ; then
	if [ ! -f $BASETGZ ] ; then
		echo "No $BASETGZ exists, creating a new one..."
	else
		echo "$BASETGZ outdated, creating a new one..."
	fi
	setup_pbuilder $SUITE $SUITE-reproducible-base # list packages which must be installed from our repo here
else
	echo "$BASETGZ not old enough, doing nothing..."
fi
echo
