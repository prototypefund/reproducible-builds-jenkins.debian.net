#!/bin/bash
# vim: set noexpandtab:

# Copyright © 2012-2017 Holger Levsen <holger@layer-acht.org>
#           ©      2013 Antonio Terceiro <terceiro@debian.org>
#           ©      2014 Joachim Breitner <nomeata@debian.org>
#           © 2015-2018 MAttia Rizzolo <mattia@debian.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# bootstraps a new chroot for schroot, and then moves it into the right location

# $1 = schroot name
# $2 = base distro/suite
# $3 $4 ... = extra packages to install

if [ $# -lt 2 ]; then
	echo "usage: $0 TARGET SUITE [backports] [reproducible] [ARG1 ARG2 ...]"
	exit 1
fi

# initialize vars
declare -a EXTRA_SOURCES
for i in $(seq 0 7) ; do
	EXTRA_SOURCES[$i]=""
done
CONTRIB=""

if [ "$1" = "torbrowser-launcher" ] ; then
	CONTRIB="contrib"
	shift
fi

if [ "$1" = "backports" ] ; then
	EXTRA_SOURCES[2]="deb $MIRROR ${SUITE}-backports main $CONTRIB"
	EXTRA_SOURCES[3]="deb-src $MIRROR ${SUITE}-backports main $CONTRIB"
	shift
fi

if [ "$1" = "reproducible" ] ; then
	EXTRA_SOURCES[4]="deb http://reproducible.alioth.debian.org/debian/ ./"
	EXTRA_SOURCES[5]="deb-src http://reproducible.alioth.debian.org/debian/ ./"
	REPRODUCIBLE=true
	shift
fi


TARGET="$1"
shift
SUITE="$1"
shift

TMPLOG=$(mktemp --tmpdir=$TMPDIR schroot-create-XXXXXXXX)

if [ "$SUITE" = "experimental" ] ; then
	# experimental cannot be bootstrapped
	SUITE=sid
	EXTRA_SOURCES[0]="deb $MIRROR experimental main $CONTRIB"
	EXTRA_SOURCES[1]="deb-src $MIRROR experimental main $CONTRIB"
elif [ "$SUITE" != "unstable" ] && [ "$SUITE" != "sid" ] ; then
	EXTRA_SOURCES[6]="deb http://security.debian.org $SUITE/updates main $CONTRIB"
	EXTRA_SOURCES[7]="deb-src http://security.debian.org $SUITE/updates main $CONTRIB"
fi

export SCHROOT_TARGET=$(mktemp -d -p $SCHROOT_BASE/ schroot-install-$TARGET-XXXX)
if [ -z "$SCHROOT_TARGET" ]; then
	echo "Could not create a directory to create the chroot in, aborting."
	exit 1
fi
sudo chmod +x $SCHROOT_TARGET	# workaround #844220 / #872812

#
# create script to add key for reproducible repo
# and configuring APT to ignore Release file expiration (since the host may
# have the date set far in the future)
#
reproducible_setup() {
	cat > $1 <<- EOF
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
apt-key list
echo
echo "Configuring APT to ignore the Release file expiration"
echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/398future
echo "Configuring APT to not download package descriptions"
echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/10no-package-descriptions
echo
EOF
}

robust_chroot_apt() {
	set +e
	sudo chroot $SCHROOT_TARGET apt-get $@ | tee $TMPLOG
	local RESULT=$(egrep 'Failed to fetch.*(Unable to connect to|Connection failed|Size mismatch|Cannot initiate the connection to|Bad Gateway|Service Unavailable)' $TMPLOG || true)
	set -e
	if [ ! -z "$RESULT" ] ; then
		echo "$(date -u) - 'apt-get $@' failed, sleeping 5min before retrying..."
		sleep 5m
		sudo chroot $SCHROOT_TARGET apt-get $@ || ( echo "$(date -u ) - 2nd 'apt-get $@' failed, giving up..." ; exit 1 )
	fi
	rm -f $TMPLOG
}

bootstrap() {
	mkdir -p "$SCHROOT_TARGET/etc/dpkg/dpkg.cfg.d"
	echo force-unsafe-io > "$SCHROOT_TARGET/etc/dpkg/dpkg.cfg.d/02dpkg-unsafe-io"

	echo "Bootstraping $SUITE into $SCHROOT_TARGET now."
	set +e
	sudo debootstrap $SUITE $SCHROOT_TARGET $MIRROR | tee $TMPLOG
	local RESULT=$(egrep "E: (Couldn't download packages|Invalid Release signature)" $TMPLOG || true)
	set -e
	if [ ! -z "$RESULT" ] ; then
		echo "$(date -u) - initial debootstrap failed, sleeping 5min before retrying..."
		sudo rm -rf --one-file-system $SCHROOT_TARGET
		sleep 5m
		sudo debootstrap $SUITE $SCHROOT_TARGET $MIRROR || ( echo "$(date -u ) - 2nd debootstrap failed, giving up..." ; exit 1 )
	fi
	rm -f $TMPLOG

	echo -e '#!/bin/sh\nexit 101'              | sudo tee   $SCHROOT_TARGET/usr/sbin/policy-rc.d >/dev/null
	sudo chmod +x $SCHROOT_TARGET/usr/sbin/policy-rc.d
	if [ ! -z "$http_proxy" ] ; then
		echo "Acquire::http::Proxy \"$http_proxy\";" | sudo tee    $SCHROOT_TARGET/etc/apt/apt.conf.d/80proxy >/dev/null
	fi

	# configure the APT sources
	sudo tee "$SCHROOT_TARGET/etc/apt/sources.list" > /dev/null <<-__END__
	# generated by $BUILD_URL
	deb $MIRROR $SUITE main $CONTRIB
	deb-src $MIRROR $SUITE main $CONTRIB
	__END__
	for i in $(seq 0 7) ; do
		[ -z "${EXTRA_SOURCES[$i]}" ] || echo "${EXTRA_SOURCES[$i]}"                     | sudo tee -a $SCHROOT_TARGET/etc/apt/sources.list >/dev/null
	done

	if $REPRODUCIBLE ; then
		TMPFILE=$(mktemp -u)
		reproducible_setup $SCHROOT_TARGET/$TMPFILE
		sudo chroot $SCHROOT_TARGET bash $TMPFILE
		rm $SCHROOT_TARGET/$TMPFILE
	fi


	robust_chroot_apt update
	if [ -n "$1" ] ; then
		for d in proc ; do
			sudo mount --bind /$d $SCHROOT_TARGET/$d
		done
		set -x
		robust_chroot_apt update
		# first, (if), install diffoscope with all recommends...
		if [ "$1" = "diffoscope" ] ; then
			# we could also use $SCRIPT_HEADER (set in bin/common-functions.sh) in our generated scripts
			# instead of using the next line, maybe we should…
			echo 'debconf debconf/frontend select noninteractive' | sudo chroot $SCHROOT_TARGET debconf-set-selections
			robust_chroot_apt install -y --install-recommends diffoscope
		fi
		robust_chroot_apt install -y --no-install-recommends sudo
		robust_chroot_apt install -y --no-install-recommends $@
		# try to use diffoscope from experimental if available
		if ([ "$SUITE" != "unstable" ] && [ "$SUITE" != "experimental" ]) && [ "$1" = "diffoscope" ] ; then
			# always try to use diffoscope from unstable on stretch/buster
			echo "deb $MIRROR unstable main"        | sudo tee -a $SCHROOT_TARGET/etc/apt/sources.list > /dev/null
			robust_chroot_apt update
			# install diffoscope from unstable without re-adding all recommends...
			sudo chroot $SCHROOT_TARGET apt-get install -y -t unstable --no-install-recommends diffoscope || echo "Warning: diffoscope from unstable is uninstallable at the moment."
		fi
		if [ "$SUITE" != "experimental" ] && [ "$1" = "diffoscope" ] ; then
			echo "deb $MIRROR experimental main"        | sudo tee -a $SCHROOT_TARGET/etc/apt/sources.list > /dev/null
			robust_chroot_apt update
			# install diffoscope from experimental without re-adding all recommends...
			sudo chroot $SCHROOT_TARGET apt-get install -y -t experimental --no-install-recommends diffoscope || echo "Warning: diffoscope from experimental is uninstallable at the moment."
		fi
		if ! $DEBUG ; then set +x ; fi
		if [ "$1" = "diffoscope" ] ; then
			echo
			sudo chroot $SCHROOT_TARGET dpkg -l diffoscope
			echo
		fi
		# umount in reverse order than how they were mounted earlier
		for d in proc ; do
			sudo umount -l $SCHROOT_TARGET/$d
		done
		# configure sudo inside just like outside
		echo "jenkins    ALL=NOPASSWD: ALL" | sudo tee -a $SCHROOT_TARGET/etc/sudoers.d/jenkins >/dev/null
		sudo chroot $SCHROOT_TARGET chown root.root /etc/sudoers.d/jenkins
		sudo chroot $SCHROOT_TARGET chmod 700 /etc/sudoers.d/jenkins
	fi
}

cleanup() {
	cd
	if [ -d "$SCHROOT_TARGET" ]; then
		sudo rm -rf --one-file-system "$SCHROOT_TARGET" || ( echo "Warning: $SCHROOT_TARGET could not be fully removed during cleanup." ; ls "$SCHROOT_TARGET" -la )
	fi
	rm -f "$TMPLOG"
}
trap cleanup INT TERM EXIT
bootstrap $@

trap - INT TERM EXIT

# pivot the new schroot in place
cd "$SCHROOT_TARGET"
rand="$RANDOM"
echo "$(date -u) - tarballing the chroot…"
sudo tar -c --exclude ./sys/* --exclude ./proc/* -f "$SCHROOT_BASE/$TARGET-$rand.tar" ./*
echo "$(date -u) - moving the chroot in place…"
sudo mv "$SCHROOT_BASE/$TARGET-$rand.tar" "$SCHROOT_BASE/$TARGET.tar"


# write the schroot config
echo "$(date -u) - writing schroot configuration"
sudo tee /etc/schroot/chroot.d/jenkins-"$TARGET" <<-__END__
	[jenkins-$TARGET]
	description=Jenkins schroot $TARGET
	file=$SCHROOT_BASE/$TARGET.tar
	type=file
	root-users=jenkins
	source-root-users=jenkins
	__END__

echo "schroot $TARGET set up successfully in $SCHROOT_BASE/$TARGET.tar - exiting now."
