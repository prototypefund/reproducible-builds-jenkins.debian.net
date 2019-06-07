#!/bin/bash
# vim: set noexpandtab:

# Copyright 2014-2019 Holger Levsen <holger@layer-acht.org>
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
	get_node_information "$HOSTNAME"
	if "$NODE_RUN_IN_THE_FUTURE" ; then
		cat >> $TMPFILE <<- EOF
			echo "Configuring APT to ignore the Release file expiration"
			sed -i 's,^deb ,deb [check-valid-until=no] ,g' /etc/apt/sources.list
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
iQJUBBMBCAA+AhsDBQsJCAcDBRUKCQgLBRYDAgEAAh4BAheAFiEESbZXRzbQtjfM
NwHqXbfKZ+pZox8FAlxG+gsFCQ29yJMACgkQXbfKZ+pZox/oKhAArNl6txTTDzjh
9DG5qywijR4ydUOuoLZBsvoiltzaTXZVlRdHm3JDU2gpQcZfgWzsGBiN9f1/a9uJ
teg93n5BlcBa+FEazcdWd9fssOkkphOMpv15y92G3nqfuhHnK/vhI5tP4lC4bGBi
MCoCLWULD86rPNYZxdr4KuY6RpvbrM7kj4PDaHwWH9EGvfBdqvrbjfG7e4KULl1D
SfeCxXV5bIVKxlyL8dLwKoyHe9Mp+jXGG3ZdyISprGPTIvSrpHzWIKuToJc4gYdJ
FHG9jRsJ+tBO5qW8GQ5NsthJJJ3YH3RQwGLLDdV065/DhHTzMvE5KgSkn2eN36Zl
gCLuT/qlpUkxmoBcqph9jLm/f1Mu9uo9psM/+n+aRscGRoRxtfcEpn+jXgumQ39a
S3EbiwsTVFqWr1FaCJBkT6biTgHH3oUj+Q9aq7ymZAWOvZ3WeAjRbfkYq9TjgNx9
LLAt784kuLfFlUv2/jE+pIXrCXp7RfWHq+UbIMLAtHXP8je4G8Sl8m0jmfaYmXL+
4fCGLQn6VMu/h4iQo0Kr1XpLWcvE3s6fK2GVKm8awbJhtn+xH3BIS4M9TmVz0934
PmJ9QvvxltW0X/5bhEJaaQRN2HuoiC1hItak9E8GfUIuDng24KGl9mgsgU4thO1F
TqlQavDrP+hwePoKd4P3Wvj50NVjQL4=
=1Wlp
-----END PGP PUBLIC KEY BLOCK-----" > /etc/apt/trusted.gpg.d/reproducible.asc
echo 'deb http://tests.reproducible-builds.org/debian/repository/debian/ ./' > /etc/apt/sources.list.d/reproducible.list
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
for i in \$(dpkg -l |grep ^ii |awk -F' ' '{print \$2}'); do   apt-cache madison "\$i" | head -1 | grep reproducible-builds.org || true  ; done
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
	sudo pbuilder --create $pbuilder_http_proxy --basetgz /var/cache/pbuilder/${NAME}-new.tgz --distribution $SUITE --debootstrapopts --no-merged-usr --extrapackages "$EXTRA_PACKAGES" --loglevel D

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
				egrep "http://tests.reproducible-builds.org/debian/repository/debian(/|) ./ Packages" ${LOG} \
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
