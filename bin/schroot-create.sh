#!/bin/bash
# vim: set noexpandtab:

# Copyright © 2012-2020 Holger Levsen <holger@layer-acht.org>
#           ©      2013 Antonio Terceiro <terceiro@debian.org>
#           ©      2014 Joachim Breitner <nomeata@debian.org>
#           © 2015-2018 Mattia Rizzolo <mattia@debian.org>
# released under the GPLv2

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

if [ "$1" = "backports" ] ; then
	EXTRA_SOURCES[2]="deb $MIRROR ${SUITE}-backports main"
	EXTRA_SOURCES[3]="deb-src $MIRROR ${SUITE}-backports main"
	shift
fi

REPRODUCIBLE=false
if [ "$1" = "reproducible" ] ; then
	REPRODUCIBLE=true
	shift
fi


TARGET="$1"
shift
SUITE="$1"
shift

SCHROOT_TARGET=$(mktemp -d -p $SCHROOT_BASE/ schroot-install-$TARGET-XXXX)
if [ -z "$SCHROOT_TARGET" ]; then
	echo "Could not create a directory to create the chroot in, aborting."
	exit 1
fi
TMPLOG=$(mktemp --tmpdir=$TMPDIR schroot-create-XXXXXXXX)
cleanup() {
	cd
	if [ -d "$SCHROOT_TARGET" ]; then
		local i
		for i in $(findmnt -l -c | awk '{print $1}' | grep "^$SCHROOT_TARGET"); do
			sudo umount "$i"
		done
		sudo rm -rf --one-file-system "$SCHROOT_TARGET" || ( echo "Warning: $SCHROOT_TARGET could not be fully removed during cleanup." ; ls "$SCHROOT_TARGET" -la )
	fi
	rm -f "$TMPLOG"
}
trap cleanup INT TERM EXIT

sudo chmod +x $SCHROOT_TARGET	# workaround #844220 / #872812

if [ "$SUITE" = "experimental" ] ; then
	# experimental cannot be bootstrapped
	SUITE=sid
	EXTRA_SOURCES[0]="deb $MIRROR experimental main"
	EXTRA_SOURCES[1]="deb-src $MIRROR experimental main"
elif [ "$SUITE" != "unstable" ] && [ "$SUITE" != "sid" ] ; then
	if [ "$SUITE" = "stretch" ] || [ "$SUITE" = "buster" ] ; then
		EXTRA_SOURCES[6]="deb http://security.debian.org $SUITE/updates main"
		EXTRA_SOURCES[7]="deb-src http://security.debian.org $SUITE/updates main"
	else
		EXTRA_SOURCES[6]="deb http://security.debian.org ${SUITE}-security main"
		EXTRA_SOURCES[7]="deb-src http://security.debian.org ${SUITE}-security main"
	fi
fi


robust_chroot_apt() {
	sudo chroot $SCHROOT_TARGET apt-get $@ | tee $TMPLOG
	local rt="${PIPESTATUS[0]}"
	local RESULT=$(egrep 'Failed to fetch.*(Unable to connect to|Connection failed|Size mismatch|Cannot initiate the connection to|Bad Gateway|Service Unavailable)' $TMPLOG || true)
	if [ ! -z "$RESULT" ] || [ "$rt" -ne 0 ] ; then
		echo "$(date -u) - 'apt-get $@' failed, sleeping 5min before retrying..."
		sleep 5m
		sudo chroot $SCHROOT_TARGET apt-get $@ || ( echo "$(date -u ) - 2nd 'apt-get $@' failed, giving up..." ; exit 1 )
	fi
	rm -f $TMPLOG
}

bootstrap() {
	echo "Bootstraping $SUITE into $SCHROOT_TARGET now."

	# this sets $NODE_RUN_IN_THE_FUTURE appropriatly
	. /srv/jenkins/bin/jenkins_node_definitions.sh
	get_node_information "$HOSTNAME"

	# choosing bootstrapping method
	local DEBOOTSTRAP=()
	if command -v mmdebstrap >/dev/null ; then
		# not available on Ubuntu 16.04 LTS
		DEBOOTSTRAP+=(mmdebstrap)
		if "$NODE_RUN_IN_THE_FUTURE" ; then
			# configure apt to ignore expired release files
			echo "This node is reported to run in the future, configuring APT to ignore the Release file expiration..."
			DEBOOTSTRAP+=(--aptopt='Acquire::Check-Valid-Until "false"')
		fi
	else
		DEBOOTSTRAP+=(debootstrap)
		# configure dpkg to be faster (mmdebstrap expects an empty directory and is fast by design)
		mkdir -p "$SCHROOT_TARGET/etc/dpkg/dpkg.cfg.d"
		echo force-unsafe-io > "$SCHROOT_TARGET/etc/dpkg/dpkg.cfg.d/02dpkg-unsafe-io"
		if "$NODE_RUN_IN_THE_FUTURE" ; then
			# configure apt to ignore expired release files
			echo "This node is reported to run in the future, configuring APT to ignore the Release file expiration..."
			mkdir -p "$SCHROOT_TARGET/etc/apt/apt.conf.d/"
			echo 'Acquire::Check-Valid-Until "false";' | sudo tee -a "$SCHROOT_TARGET"/etc/apt/apt.conf.d/398future >/dev/null
		fi

	fi
	set -x
	sudo -- "${DEBOOTSTRAP[@]}" "$SUITE" "$SCHROOT_TARGET" "$MIRROR" | tee "$TMPLOG"
	local rt="${PIPESTATUS[0]}"
	if ! "$DEBUG" ; then set +x ; fi
	local RESULT=$(egrep "E: (Couldn't download packages|Invalid Release signature)" $TMPLOG || true)
	if [ ! -z "$RESULT" ] || [ "$rt" -ne 0 ]; then
		echo "$(date -u) - initial bootstrap failed, sleeping 5min before retrying..."
		sudo rm -rf --one-file-system $SCHROOT_TARGET
		sleep 5m
		sudo -- "${DEBOOTSTRAP[@]}" "$SUITE" "$SCHROOT_TARGET" "$MIRROR" || ( echo "$(date -u ) - 2nd bootstrap failed, giving up..." ; exit 1 )
	fi
	rm -f $TMPLOG

	# configure policy-rc.d to not start services
	echo -e '#!/bin/sh\nexit 101' | sudo tee $SCHROOT_TARGET/usr/sbin/policy-rc.d >/dev/null
	sudo chmod +x $SCHROOT_TARGET/usr/sbin/policy-rc.d
	# configure proxy
	if [ ! -z "$http_proxy" ] ; then
		echo "Acquire::http::Proxy \"$http_proxy\";" | sudo tee $SCHROOT_TARGET/etc/apt/apt.conf.d/80proxy >/dev/null
	fi
	# configure dpkg to be faster
	echo force-unsafe-io | sudo tee "$SCHROOT_TARGET/etc/dpkg/dpkg.cfg.d/02dpkg-unsafe-io"

	# configure the APT sources
	sudo tee "$SCHROOT_TARGET/etc/apt/sources.list" > /dev/null <<-__END__
	# generated by $BUILD_URL
	deb $MIRROR $SUITE main
	deb-src $MIRROR $SUITE main
	__END__
	for i in $(seq 0 7) ; do
		[ -z "${EXTRA_SOURCES[$i]}" ] || echo "${EXTRA_SOURCES[$i]}" | sudo tee -a $SCHROOT_TARGET/etc/apt/sources.list >/dev/null
	done

	# Misc configuration for a building-aimed chroot
	sudo tee "$SCHROOT_TARGET/etc/apt/apt.conf.d/15jenkins" > /dev/null <<-__END__
	APT::Install-Recommends "false";
	APT::AutoRemove::SuggestsImportant false;
	APT::AutoRemove::RecommendsImportant false;
	# don't download package descriptions
	Acquire::Languages none;
	__END__

	sudo tee -a "$SCHROOT_TARGET/var/cache/debconf/config.dat" > /dev/null <<-__END__
	Name: man-db/auto-update
	Template: man-db/auto-update
	Value: false
	Owners: man-db
	__END__

	robust_chroot_apt update
	if [ -n "$1" ] ; then
		sudo mount --bind /proc $SCHROOT_TARGET/proc
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
			echo "deb $MIRROR unstable main" | sudo tee -a $SCHROOT_TARGET/etc/apt/sources.list > /dev/null
			robust_chroot_apt update
			# install diffoscope from unstable without re-adding all recommends...
			sudo chroot $SCHROOT_TARGET apt-get install -y -t unstable --no-install-recommends diffoscope || echo "Warning: diffoscope from unstable is uninstallable at the moment."
		fi
		if [ "$SUITE" != "experimental" ] && [ "$1" = "diffoscope" ] ; then
			echo "deb $MIRROR experimental main" | sudo tee -a $SCHROOT_TARGET/etc/apt/sources.list > /dev/null
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
		sudo umount -l $SCHROOT_TARGET/proc
		# configure sudo inside just like outside
		echo "jenkins    ALL=NOPASSWD: ALL" | sudo tee -a $SCHROOT_TARGET/etc/sudoers.d/jenkins >/dev/null
		sudo chroot $SCHROOT_TARGET chown root.root /etc/sudoers.d/jenkins
		sudo chroot $SCHROOT_TARGET chmod 700 /etc/sudoers.d/jenkins
	fi
}

bootstrap $@

# pivot the new schroot in place
rand="$(date -u +%Y%m%d)-$RANDOM"
if $REPRODUCIBLE ; then
	# for diffoscope we really need a directory schroot, as otherwise we end up
	# with too many unpacked chroots
	# Let's just keep changing the trailing number and trust the maintenance job
	# to clean up old chroots.
	echo "$(date -u) This chroot will be placed in $SCHROOT_BASE/$TARGET-$rand"
	sudo mv "$SCHROOT_TARGET" "$SCHROOT_BASE/$TARGET-$rand"
else
	cd "$SCHROOT_TARGET"
	echo "$(date -u) - tarballing the chroot…"
	sudo tar -c --exclude ./sys/* --exclude ./proc/* -f "$SCHROOT_BASE/$TARGET-$rand.tar" ./*
	echo "$(date -u) - moving the chroot in place…"
	sudo mv "$SCHROOT_BASE/$TARGET-$rand.tar" "$SCHROOT_BASE/$TARGET.tar"
fi


# write the schroot config
echo "$(date -u) - writing schroot configuration"
sudo tee /etc/schroot/chroot.d/jenkins-"$TARGET" <<-__END__
	[jenkins-$TARGET]
	description=Jenkins schroot $TARGET
	root-users=jenkins
	source-root-users=jenkins
__END__
if $REPRODUCIBLE ; then
	sudo tee -a /etc/schroot/chroot.d/jenkins-"$TARGET" <<-__END__
		directory=$SCHROOT_BASE/$TARGET-$rand
		type=directory
		union-type=overlay
	__END__
else
	sudo tee -a /etc/schroot/chroot.d/jenkins-"$TARGET" <<-__END__
		file=$SCHROOT_BASE/$TARGET.tar
		type=file
	__END__
fi

echo "schroot $TARGET set up successfully - cleaning up and exiting now."
