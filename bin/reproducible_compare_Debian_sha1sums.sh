#!/bin/bash

# as posted by Vagrant on https://lists.reproducible-builds.org/pipermail/rb-general/2018-October/001239.html

# Copyright 2019 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2+

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set -e

# TODOs:
# - ${package_file}.sha1output includes ${package_file} in the file name and contents
# - run on osuoslXXX ? harder with using db..
# - GRAPH
# - save results in db
# - loop through all packages known in db
# - show results in 'normal pages' 
# - store date when a package was last reproduced... (and constantly do that...)
# - throw away results (if none has been|which have not) signed with a tests.r-b.o key
# - json files from buildinfo.d.n are never re-downloaded

echo
echo
echo 'this is an early prototype...'
echo
echo

bdn_url="https://buildinfo.debian.net/api/v1/buildinfos/checksums/sha1"
log=$(mktemp --tmpdir=$TMPDIR sha1-comp-XXXXXXX)

SHA1DIR=/srv/reproducible-results/debian-sha1
mkdir -p $SHA1DIR
cd $SHA1DIR

# downloading (and keeping) all the packages is also too much, but let's prototype this... (and improve later)
PACKAGES=$(mktemp --tmpdir=$TMPDIR sha1-comp-XXXXXXX)
schroot --directory  $SHA1DIR -c chroot:jenkins-reproducible-unstable-diffoscope cat /var/lib/apt/lists/cdn-fastly.deb.debian.org_debian_dists_unstable_main_binary-amd64_Packages > $PACKAGES
packages="$(grep ^Package: $PACKAGES| awk '{print $2}' | sort | xargs echo)"
# workaround, to more quickly cleanup the wrongly populated pool structure
# (so that we sooner can drop the workaround from the previous commit)
packages="baloo-kf5 base-files base-passwd bash bowtie2-examples bsdmainutils bsdutils check check-mk-livestatus chromium-driver cl-diagnostic-msgs cl-qmynd comparepdf coreutils courier-ldap cpio cron crrcsim-doc cupp3 cups-common curseofwar cvsdelta dash debconf debconf-i18n debian-archive-keyring debianutils dict-freedict-ita-jpn dict-freedict-kur-tur diffutils dmidecode dmsetup dpkg drascula-german drmips dssi-utils e2fsprogs education-desktop-gnome elpa-elfeed-web fai-nfsroot fdisk findutils firefox-esr-l10n-hi-in firefox-l10n-lv flycheck-doc fonts-tlwg-loma-otf freemedforms-common-resources fusionforge-plugin-scmdarcs fw4spl g++-8-riscv64-linux-gnu galois gcc-7-plugin-dev-i686-linux-gnu gcc-8-base gcc-multilib-mips64-linux-gnuabi64 gcr gdbm-l10n gdc-8-sh4-linux-gnu gdc-multilib-powerpc-linux-gnu gdigi geany-plugin-codenav geeqie-common gem-plugin-dc1394 gifti-bin gir1.2-gegl-0.4 git-dpm gkrellm-leds gnokii-smsd-mysql gnome-doc-utils gnome-session-canberra gnu-smalltalk-common gnu-smalltalk-el gobjc++-8-mipsisa32r6el-linux-gnu go-exploitdb golang-github-azure-azure-storage-blob-go-dev golang-github-docker-docker-dev golang-github-howeyc-gopass-dev golang-github-jroimartin-gocui-dev golang-github-minio-minio-go-dev golang-github-spf13-viper-dev golang-github-svent-go-nbreader-dev gpgv grep gstreamer1.0-plugins-ugly-doc guncat gzip hardinfo hgview hostname hpsockd httpry-tools hunspell-fr-modern hunspell-se hyphy-common ifupdown init init-system-helpers iproute2 iptables iputils-ping isc-dhcp-client isc-dhcp-common janus-tools java2html jigdo-file jstest-gtk juce-modules-source kbruch kdeedu-kvtml-data kdiamond kig kmod kwin-decoration-oxygen leds-alix-source lemonldap-ng-fastcgi-server less lfc lib32lsan0-amd64-cross libacl1 libafflib0v5 libalsa-ocaml-dev libanalitza8 libapache2-mod-auth-radius libapparmor1 libapp-control-perl libapt-inst2.0 libapt-pkg5.0 libargon2-1 libattr1 libaudit1 libaudit-common libbarclay-java libbcpkix-java libbitstream-dev libblkid1 libboost-container1.67.0 libboost-coroutine1.62.0 libboost-signals1.67.0 libboost-stacktrace1.67-dev libbsd0 libbuild-helper-maven-plugin-java libbz2-1.0 libc6 libc6-mips64-mipsn32-cross libcap2 libcap2-bin libcap-ng0 libc-bin libcgi-application-server-perl libchemistry-openbabel-perl libchi-driver-redis-perl libclass-autoloadcan-perl libclass-errorhandler-perl libclass-loader-dev libcom-err2 libconfig-model-openssh-perl libcryptsetup12 libdatrie-dev libdb5.3 libdebconfclient0 libdebconf-kde1 libdevmapper1.02.1 libdisorder-dev libdist-zilla-plugin-makemaker-fallback-perl libdist-zilla-plugin-test-eol-perl libdns-export1104 libelf1 libeliom-ocaml-dev libestr0 libeval-context-perl libext2fs2 libfastjson4 libfdisk1 libffi6 libfile-modified-perl libfile-touch-perl libflexdock-java libfm-gtk-dbg libgcc1 libgcc-7-dev-alpha-cross libgcrypt20 libgdk3.0-cil libghc-ansi-wl-pprint-doc libghc-binary-tagged-prof libghc-bmp-dev libghc-cabal-helper-prof libghc-chart-cairo-dev libghc-connection-prof libghc-crypto-doc libghc-data-default-instances-base-doc libghc-dbus-doc libghc-enummapset-th-prof libghc-fast-logger-prof libghc-fgl-arbitrary-doc libghc-hmatrix-gsl-dev libghc-hstringtemplate-dev libghc-network-conduit-tls-doc libghc-operational-dev libghc-simple-sendfile-doc libghc-src-exts-simple-doc libghc-websockets-doc libglom-1.30-0 libgmp10 libgnat-8-mips-cross libgnuradio-atsc3.7.13 libgnustep-dl2-dev libgnutls30 libgoffice-0.10-10-common libgpg-error0 libhash-moreutils-perl libhdhomerun-dev libhmat-oss1-dbg libhogweed4 libidn11 libidn2-0 libimglib2-java-doc libimporter-perl libio-socket-timeout-perl libip4tc0 libip6tc0 libipaddr-ocaml libiptc0 libisc-export1100 libjava-xmlbuilder-java libjs-leaflet libjson-c3 libjs-three libkf5activities5 libkf5akonadisearch-dev libkf5dbusaddons-data libkf5ldap-doc libkf5parts-plugins libkf5textwidgets5 libkf5widgetsaddons-data libkmod2 liblapack3 libliquid-dev liblocale-gettext-perl liblog-agent-perl liblognorm5 liblz4-1 liblzma5 libmail-checkuser-perl libmaven-shared-jar-java libmaven-shared-jar-java-doc libmnl0 libmoosex-yaml-perl libmount1 libmousex-nativetraits-perl libncurses6 libncursesw6 libnetfilter-conntrack3 libnet-ldap-server-test-perl libnettle6 libnewt0.52 libnfnetlink0 libnftnl11 libnginx-mod-http-upstream-fair libobjc-7-dev libocrad-dev libopenni2-dev libopenrawgnome-dev liborbit2-dev libp11-kit0 libpam0g libpam-modules libpam-modules-bin libpam-runtime libparse-fixedlength-perl libparse-win32registry-perl libparsington-java-doc libpcl-tracking1.9 libpcre3 libpmi0-dev libpopt0 libpostscriptbarcode libprocps7 libqgis-customwidgets libquota-perl libqwt-dev libreoffice-help-hu libreoffice-l10n-el librime-data-luna-pinyin librngom-java libroar-plugins-universal librosbag3d librust-packed-simd+coresimd-dev librust-rustc-demangle-dev librust-thread-id-dev librust-url+heapsize-dev libsdl2-net-dev libseccomp2 libselinux1 libsemanage1 libsemanage-common libsepol1 libshout-ocaml libslang2 libsmartcols1 libsmraw-utils libspatialaudio0 libss2 libssl1.1 libstdc++6 libsystemd0 libtasn1-6 libtemplate-plugin-javascript-perl libterralib3 libtest2-suite-perl libtest-www-mechanize-catalyst-perl libtext-charwidth-perl libtext-iconv-perl libtext-wrapi18n-perl libtifiles2-10 libtinfo6 libtrilinos-pliris-dev libtrilinos-trilinoscouplings12 libudev1 libunicode-collate-perl libunistring2 liburi-perl libuuid1 libvibe-utils0 libvtk6-java libvtk7-java libweb-simple-perl libwhy3-ocaml-dev libwwwbrowser-perl libwww-form-urlencoded-xs-perl libxapian-java-doc libxml-libxml-simple-perl libxtables12 libzstd1 lighttpd-doc loadmeter login logrotate lsb-base lua-http lxsession-default-apps mawk mdk4 metview-data mgp mialmpick mimetex molds mount mp3report mpdas muroar-bin myspell-he nano nasm nautilus ncoils ncurses-base ncurses-bin netbase networkd-dispatcher node-async-each node-cli-truncate node-core-js node-glob node-graphlibrary node-restore-cursor node-webpack-sources nordugrid-arc-misc-utils ntrack-module-rtnetlink-0 octave-doc openbsc-dev openvpn-systemd-resolved passwd pdal pd-bassemu perl-base phpab php-file-iterator php-horde-queue php-mdb2-driver-pgsql piuparts piuparts-common piuparts-master piuparts-slave plink pm-utils printer-driver-cjet procps pulseaudio-equalizer puppet-module-designate puredata python3-azure-devtools python3-brlapi python3-curtsies python3-descartes python3-django-gravatar2 python3-doc python3-easywebdav python3-genpy python3-magnum-ui python3-notmuch python3-omemo-backend-signal python3-oslo.serialization python3-pbr python3-pyiosxr python3-pystache python3-scrypt python3-sigmavirus24-urltemplate python3-tables python3-tackerclient python3-zaqar python3-zfec python-bitstruct python-can-doc python-djangorestframework-generators python-feedparser python-flask-principal python-fs-plugin-webdav python-gccjit python-keystoneauth1-doc python-linaro-image-tools python-link-grammar python-mia python-optcomplete python-paypal python-pylxd python-seamicroclient python-test-server python-tuskarclient-doc python-webassets-doc python-wsgicors python-zconfig qml-module-qtaudioengine qt5-style-kvantum-l10n r-bioc-hilbertvis readline-common ros-topic-tools-srvs rsyslog rtl-sdr ruby-actionpack-page-caching ruby-case-transform ruby-enum ruby-ldap ruby-recaptcha sass-spec-data sbox-dtc science-psychophysics sed sensible-utils sharness signon-plugin-password simstring-bin snort-rules-default sofa-apps spamoracle ssldump stoken storymaps subcommander-doc swisswatch systemd systemd-sysv sysvinit-utils tar tasksel tasksel-data tcl-snack tcputils testdisk-dbg texlive-science the-doc thunderbird-l10n-all tinyca tinyhoneypot trac-odtexport triplea tryton-modules-product-measurements tzdata uc-echo udev ukui-settings-daemon upx-ucl utalk util-linux vim-common vim-editorconfig vim-fugitive vim-tiny vino visual-regexp webdis wesnoth-1.14-dw whiptail wordpress-civicrm wrapperfactory.app xfce4-verve-plugin xflr5-doc xshogi xstarfish xwpe xxd zinnia-utils zlib1g $packages"

reproducible_packages=
unreproducible_packages=

cleanup_all() {
	reproducible_packages=$(awk '/ REPRODUCIBLE: /{print $2}' $log)
	reproducible_count=$(echo $reproducible_packages | wc -w)
	unreproducible_packages=$(awk '/ UNREPRODUCIBLE: /{print $2}' $log)
	unreproducible_count=$(echo $unreproducible_packages | wc -w)

	percent_repro=$(echo "scale=4 ; $reproducible_count / ($reproducible_count+$unreproducible_count) * 100" | bc)
	percent_unrepro=$(echo "scale=4 ; $unreproducible_count / ($reproducible_count+$unreproducible_count) * 100" | bc)

	echo "-------------------------------------------------------------"
	echo "reproducible packages: $reproducible_count: $reproducible_packages"
	echo
	echo "unreproducible packages: $unreproducible_count: $unreproducible_packages"
	echo
	echo "reproducible packages: $reproducible_count: ($percent_repro%)"
	echo
	echo "unreproducible packages: $unreproducible_count: ($percent_unrepro%)"
	echo
	echo
	echo "$(du -sch $SHA1DIR)"
	echo
	rm $log $PACKAGES
}

trap cleanup_all INT TERM EXIT

for package in $packages ; do
	cd $SHA1DIR
	echo
	echo "$(date -u) - checking whether we have seen the .deb for $package before"
	version=$(grep-dctrl -X -P ${package} -s version -n $PACKAGES)
	arch=$(grep-dctrl -X -P ${package} -s Architecture -n $PACKAGES)
	package_file="${package}_$(echo $version | sed 's#:#%3a#')_${arch}.deb"
	pool_dir="$(dirname $(grep-dctrl -X -P ${package} -s Filename -n $PACKAGES))"
	mkdir -p $pool_dir
	# temp code, only needed to cleanup pool... (from wrong layout before)
	if [ -e ${package_file}.sha1output ] || [ -e ${package_file}.json ] ; then
		mv ${package_file}.sha1output $pool_dir || true
		mv ${package_file}.json $pool_dir || true
	fi
	# end temp code
	cd $pool_dir
	if [ ! -e ${package_file}.sha1output ] ; then
		echo -n "$(date -u) - preparing to download $filename"
		( schroot --directory  $SHA1DIR/$pool_dir -c chroot:jenkins-reproducible-unstable-diffoscope apt-get download ${package} 2>&1 |xargs echo ) || continue
		echo "$(date -u) - calculating sha1sum"
		SHA1SUM_PKG="$(sha1sum ${package_file} | tee ${package_file}.sha1output | awk '{print $1}' )"
		rm ${package_file}
	else
		echo "$(date -u) - ${package_file} is known, gathering sha1sum"
		SHA1SUM_PKG="$(cat ${package_file}.sha1output | awk '{print $1}' )"
	fi
	if [ ! -e ${package_file}.json ]; then
		echo "$(date -u) - downloading .json from buildinfo.debian.net"
		wget --quiet -O ${package_file}.json ${bdn_url}/${SHA1SUM_PKG} || echo "WARNING: failed to download ${bdn_url}/${SHA1SUM_PKG}"
	else
		echo "$(date -u) - reusing local copy of .json from buildinfo.debian.net"
	fi
	echo "$(date -u) - generating result"
	count=$(fmt ${package_file}.json | grep -c '\.buildinfo' || true)
	if [ "${count}" -ge 2 ]; then
		echo "$(date -u) - REPRODUCIBLE: $package_file: $SHA1SUM_PKG - reproduced $count times."
	else
		echo "$(date -u) - UNREPRODUCIBLE: $package_file: $SHA1SUM_PKG on ftp.debian.org, but nowhere else."
	fi
done | tee $log

cleanup_all
trap - INT TERM EXIT
