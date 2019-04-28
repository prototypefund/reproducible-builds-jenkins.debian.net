#!/bin/bash
# vim: set noexpandtab:
# Copyright 2012-2019 Holger Levsen <holger@layer-acht.org>
#         ©      2018 Mattia Rizzolo <mattia@debian.org>
# released under the GPLv=2

# puppet / salt / ansible / fai / chef / deployme.app - disclaimer
# (IOW: this script has been grown in almost 500 commits and it shows…)
#
# yes, we know… and: "it" should probably still be done.
#
# It just unclear, how/what, and what we have actually mostly works.
#
# Switching to jenkins.debian.org is probably an opportunity
# to write (refactor this into) *yet another deployment script*
# (interacting with the DSA machine setup which is in puppet…),
# thus obsoleting this script gradually, though this is used on
# 47 hosts currently (of which quite some were initially installed
# manually…)
#
# so, yes, patches welcome. saying this is crap alone is not helpful,
# nor is just suggesting some new or old technology. patches most welcome!
#
# that said, there's a new one: init_node ;)

set -e

BASEDIR="$(dirname "$(readlink -e $0)")"
STAMP=/var/log/jenkins/update-jenkins.stamp
# The $@ below means that command line args get passed on to j-j-b
# which allows one to specify --flush-cache or --ignore-cache
JJB="jenkins-jobs $@"
DPKG_ARCH="$(dpkg --print-architecture)"

# so we can later run some commands only if $0 has been updated…
if [ -f $STAMP ] && [ $STAMP -nt $BASEDIR/$0 ] ; then
	UP2DATE=true
	echo $HOSTNAME is up2date.
else
	UP2DATE=false
	echo $HOSTNAME needs to be updated.
fi


explain() {
	echo "$HOSTNAME: $1"
}

set_correct_date() {
		# set correct date
		sudo service ntp stop || true
		sudo ntpdate -b $1
}

disable_dsa_check_packages() {
	# disable check for outdated packages as someday in the future
	# packages from security.d.o will appear outdated always…
	echo -e "#!/bin/sh\n# disabled dsa-check by update_jdn.sh\nexit 0" | sudo tee /usr/local/bin/dsa-check-packages
	sudo chmod a+rx /usr/local/bin/dsa-check-packages
}

echo "--------------------------------------------"
explain "$(date) - begin deployment update."

#
# temporarily test to check which hosts don't use systemd
#
if [ -z "$(dpkg -l|grep systemd-sysv||true)" ] ; then 
	echo "no systemd-sysv installed on $(hostname), please enter to continue…"
	read
fi

# some nodes need special treatment…
case $HOSTNAME in
	profitbricks-build5-amd64|profitbricks-build6-i386|profitbricks-build15-amd64|profitbricks-build16-i386)
		# set correct date
		set_correct_date de.pool.ntp.org
		;;
	codethink-sled9*|codethink-sled11*|codethink-sled13*|codethink-sled15*)
		# set correct date
		set_correct_date de.pool.ntp.org
		;;
	osuosl-build170-amd64|osuosl-build172-amd64)
		# set correct date
		set_correct_date time.osuosl.org
		;;
	*)	;;
esac

# ubuntu decided to change kernel perms in the middle of LTS…
case $HOSTNAME in
	codethink-sled*)
		# fixup perms
		sudo chmod +r /boot/vmlinuz-*
		;;
	*)	;;
esac



#
# set up users and groups
#
declare -A user_host_groups u_shell
sudo_groups='jenkins,jenkins-adm,sudo,adm'

# if there's a need for host groups, a case statement on $HOSTNAME here that sets $GROUPNAME, say, should do the trick
# then you can define user_host_groups['phil','lvm_group']=... below
# and add checks for the GROUP version where ever the HOSTNAME is checked in the following code

user_host_groups['helmut','*']="$sudo_groups"
user_host_groups['holger','*']="$sudo_groups"
user_host_groups['holger','jenkins']="reproducible,${user_host_groups['holger','*']}"
user_host_groups['mattia','*']="$sudo_groups"
user_host_groups['mattia','jenkins']="reproducible,${user_host_groups['mattia','*']}"
user_host_groups['phil','jenkins-test-vm']="$sudo_groups,libvirt,libvirt-qemu"
user_host_groups['phil','jenkins']="$sudo_groups"
user_host_groups['lunar','jenkins']='reproducible'
user_host_groups['lynxis','osuosl-build171-amd64']="$sudo_groups"
user_host_groups['lynxis','osuosl-build172-amd64']="$sudo_groups"
user_host_groups['lynxis','jenkins']="jenkins"
user_host_groups['hans','osuosl-build168-amd64']="$sudo_groups"
user_host_groups['vagrant','*']="$sudo_groups"


u_shell['mattia']='/bin/zsh'
u_shell['lynxis']='/bin/fish'
u_shell['jenkins-adm']='/bin/bash'

# get the users out of the user_host_groups array's index
users=$(for i in ${!user_host_groups[@]}; do echo ${i%,*} ; done | sort -u)

( $UP2DATE && [ -z "$(find authorized_keys -newer $0)" ] ) || for user in ${users}; do
	# -v is a bashism to check for set variables, used here to see if this user is active on this host
	if [ ! -v user_host_groups["$user","$HOSTNAME"] ] && [ ! -v user_host_groups["$user",'*'] ] && [ ! -v user_host_groups["$user","$DPKG_ARCH"] ] ; then
		continue
	fi

	# create the user
	if ! getent passwd $user > /dev/null ; then
		# adduser, defaulting to /bin/bash as shell
		sudo adduser --gecos "" --shell "${u_shell[$user]:-/bin/bash}" --disabled-password $user
	fi
	# add groups: first try the specific host, or if unset fall-back to default '*' setting
	for h in "$HOSTNAME" "$DPKG_ARCH" '*' ; do
		if [ -v user_host_groups["$user","$h"] ] ; then
			sudo usermod -G "${user_host_groups["$user","$h"]}" $user
			break
		fi
	done
	# add the user's keys (if any)
	if ls authorized_keys/${user}@*.pub >/dev/null 2>&1 ; then
		[ -d /var/lib/misc/userkeys ] || sudo mkdir -p /var/lib/misc/userkeys
		cat authorized_keys/${user}@*.pub | sudo tee /var/lib/misc/userkeys/${user} > /dev/null
	fi
done

sudo mkdir -p /srv/workspace
[ -d /srv/schroots ] || sudo mkdir -p /srv/schroots
[ -h /chroots ] || sudo ln -s /srv/workspace/chroots /chroots
[ -h /schroots ] || sudo ln -s /srv/schroots /schroots

# prepare tmpfs on some hosts
case $HOSTNAME in
	jenkins)
		TMPFSSIZE=100
		TMPSIZE=15
		;;
	profitbricks-build9-amd64)
		TMPFSSIZE=40
		TMPSIZE=8
		;;
	profitbricks-build*)
		TMPFSSIZE=200
		TMPSIZE=15
		;;
	codethink*)
		TMPFSSIZE=100
		TMPSIZE=15
		;;
	osuosl*)
		TMPFSSIZE=400
		TMPSIZE=50
		;;
	*) ;;
esac
case $HOSTNAME in
	profitbricks-build*i386)
		if ! grep -q '/srv/workspace' /etc/fstab; then
			echo "Warning: you need to manually create a /srv/workspace partition on i386 nodes, exiting."
			exit 1
		fi
		;;
	jenkins|profitbricks-build*amd64|codethink*|osuosl*)
		if ! grep -q '^tmpfs\s\+/srv/workspace\s' /etc/fstab; then
			echo "tmpfs		/srv/workspace	tmpfs	defaults,size=${TMPFSSIZE}g	0	0" | sudo tee -a /etc/fstab >/dev/null  
		fi
		if ! grep -q '^tmpfs\s\+/tmp\s' /etc/fstab; then
			echo "tmpfs		/tmp	tmpfs	defaults,size=${TMPSIZE}g	0	0" | sudo tee -a /etc/fstab >/dev/null
		fi
		if ! mountpoint -q /srv/workspace; then
			if test -z "$(ls -A /srv/workspace)"; then
				sudo mount /srv/workspace
			else
				explain "WARNING: mountpoint /srv/workspace is non-empty."
			fi
		fi
		;;
	*) ;;
esac

# make sure needed directories exists - some directories will not be needed on all hosts...
for directory in /schroots /srv/reproducible-results /srv/d-i /srv/udebs /var/log/jenkins/ /srv/jenkins /srv/jenkins/pseudo-hosts /srv/workspace/chroots ; do
	if [ ! -d $directory ] ; then
		sudo mkdir $directory
	fi
	sudo chown jenkins.jenkins $directory
done
for directory in /srv/jenkins ; do
	if [ ! -d $directory ] ; then
		sudo mkdir $directory
		sudo chown jenkins-adm.jenkins-adm $directory
	fi
done

if ! test -h /chroots; then
	sudo rmdir /chroots || sudo rm -f /chroots # do not recurse
	if test -e /chroots; then
		explain "/chroots could not be cleared."
	else
		sudo ln -s /srv/workspace/chroots /chroots
	fi
fi

# only on Debian systems
if [ -f /etc/debian_version ] ; then
	#
	# install packages we need
	#
	if [ $BASEDIR/$0 -nt $STAMP ] || [ ! -f $STAMP ] ; then
		DEBS=" 
			bash-completion 
			bc
			bsd-mailx
			curl
			debian-archive-keyring
			debootstrap/stretch-backports
			cdebootstrap-
			devscripts
			eatmydata
			etckeeper
			figlet
			git
			gnupg
			haveged
			htop
			less
			locales-all
			lsof
			molly-guard
			moreutils
			munin-node/stretch-backports
			munin-plugins-core/stretch-backports
			munin-plugins-extra/stretch-backports
			needrestart
			netcat-traditional
			ntp
			ntpdate
			pbuilder/stretch-backports
			pigz 
			postfix
			procmail
			psmisc
			python3-psycopg2 
			python3-yaml
			schroot 
			screen
			slay
			stunnel
			subversion 
			subversion-tools 
			systemd-sysv
			sudo 
			unzip 
			vim 
			zsh
			"
		# needed for rebuilding Debian (using .buildinfo files)
		case $HOSTNAME in
			osuosl-build173-amd64) DEBS="$DEBS libdpkg-perl libwww-mechanize-perl sbuild" ;;
			*) ;;
		esac
		# install squid / apache2 on a few nodes only
		case $HOSTNAME in
			profitbricks-build1-a*|profitbricks-build10*|codethink-sled16*|osuosl-build167*) DEBS="$DEBS
				squid" ;;
			profitbricks-build7-a*) DEBS="$DEBS
				apache2" ;;
			*) ;;
		esac
		# notifications are only done from a view nodes
		case $HOSTNAME in
			jenkins|jenkins-test-vm|profitbricks-build*) DEBS="$DEBS
				kgb-client
				python3-yaml" ;;
			*) ;;
		esac
		# install debootstrap from stretch-backports on ubuntu nodes as since 20180927 debootstrap 1.0.78+nmu1ubuntu1.6 cannot install sid anymore
		case $HOSTNAME in
			codethink*) DEBS="$DEBS
				debootstrap/stretch-backports" ;;
			*) 	;;
		esac
		# needed to run the 2nd reproducible builds nodes in the future...
		case $HOSTNAME in
			profitbricks-build5-amd64|profitbricks-build6-i386|profitbricks-build15-amd64|profitbricks-build16-i386) DEBS="$DEBS ntpdate" ;;
			codethink-sled9*|codethink-sled11*|codethink-sled13*|codethink-sled15*) DEBS="$DEBS ntpdate" ;;
			osuosl-build170-amd64|osuosl-build172-amd64) DEBS="$DEBS ntpdate" ;;
			*) ;;
		esac
		# needed to run coreboot/openwrt/netbsd/fedora jobs
		case $HOSTNAME in
		osuosl-build171-amd64|osuosl-build172-amd64) DEBS="$DEBS
				bison
				ca-certificates
				cmake
				diffutils
				findutils
				fish
				flex
				g++
				gawk
				gcc
				grep
				iasl
				libc6-dev
				libncurses5-dev
				libssl-dev
				locales-all
				kgb-client
				m4
				make
				python3-clint
				python3-git
				python3-pystache
				python3-requests
				python3-yaml
				subversion
				tree
				unzip
				util-linux
				zlib1g-dev"
			;;
			*) ;;
		esac
		# needed to run fdroid jobs
		case $HOSTNAME in
			osuosl-build168-amd64) DEBS="$DEBS
				androguard/stretch-backports
				android-sdk
				bzr
				git-svn
				fdroidserver/stretch-backports
				linux-headers-amd64
				mercurial
				python3-asn1crypto/stretch-backports
				python3-babel
				python3-mwclient/stretch-backports
				python3-setuptools
				subversion
				vagrant/stretch-backports
				virtualbox/stretch-backports"
			;;
			*) ;;
		esac
		if [ "$HOSTNAME" = "jenkins-test-vm" ] ; then
			# for phil only
			DEBS="$DEBS postfix-pcre"
			# only needed on the main node
		elif [ "$HOSTNAME" = "jenkins" ] ; then
			DEBS="$DEBS ffmpeg libav-tools python3-popcon dose-extra"
		fi
		# mock is needed to build fedora
		if [ "$HOSTNAME" = "osuosl-build171-amd64" ] || [ "$HOSTNAME" = "osuosl-build172-amd64" ] || [ "$HOSTNAME" = "jenkins" ] ; then
			DEBS="$DEBS mock"
		fi
		# only on main node
		if [ "$HOSTNAME" = "jenkins" ] || [ "$HOSTNAME" = "jenkins-test-vm" ] ; then
			MASTERDEBS=" 
				apache2 
				apt-file 
				apt-listchanges 
				asciidoc
				binfmt-support 
				bison
				botch
				build-essential 
				cmake 
				cron-apt 
				csvtool 
				dnsmasq-base 
				dstat 
				figlet 
				flex
				gawk 
				ghc
				git-lfs
				git-notifier 
				gocr 
				graphviz 
				iasl 
				imagemagick 
				ip2host
				jekyll
				jenkins-job-builder/stretch-backports
				kgb-client
				libcap2-bin 
				libfile-touch-perl 
				libguestfs-tools 
				libjson-rpc-perl 
				libsoap-lite-perl 
				libxslt1-dev 
				moreutils 
				mr 
				mtr-tiny 
				munin/stretch-backports
				ntp 
				obfs4proxy
				openbios-ppc 
				openbios-sparc 
				openjdk-8-jre 
				pandoc
				postgresql
				postgresql-autodoc
				postgresql-client 
				poxml 
				procmail 
				python3-debian 
				python3-pystache
				python3-requests
				python3-rpy2 
				python3-sqlalchemy
				python3-xdg
				python3-yaml
				python-arpy 
				python-hachoir-metadata 
				python-imaging 
				python-lzma 
				python-pip 
				python-setuptools 
				python-twisted 
				python-yaml 
				qemu 
				qemu-kvm 
				qemu-system-x86 
				qemu-user-static 
				radvd 
				ruby-rspec
				rustc
				seabios 
				shorewall 
				shorewall6 
				sqlite3 
				syslinux
				systemd/stretch-backports
				thin-provisioning-tools
				tor
				vncsnapshot 
				vnstat
				whohas
				x11-apps 
				xtightvncviewer
				xvfb
				xvkbd
				zutils"
		else
			MASTERDEBS=""
		fi
		$UP2DATE || sudo apt-get update
		$UP2DATE || sudo apt-get install $DEBS $MASTERDEBS
		# for varying kernels:
		# - we use bpo kernels on pb-build5+15 (and the default amd64 kernel on pb-build6+16-i386)
		# - we also use the bpo kernel on osuosl-build172 (but not osuosl-build171)
		# - this is done as a seperate step as bpo kernels are frequently uninstallable when upgraded on bpo
		if [ "$HOSTNAME" = "profitbricks-build5-amd64" ] || [ "$HOSTNAME" = "profitbricks-build15-amd64" ] \
			|| [ "$HOSTNAME" = "osuosl-build172-amd64" ] ; then
			sudo apt install linux-image-amd64/stretch-backports || true # backport kernels are frequently uninstallable...
		elif [ "$HOSTNAME" = "profitbricks-build6-i386" ] || [ "$HOSTNAME" = "profitbricks-build16-i386" ] \
			|| [ "$HOSTNAME" = "profitbricks-build2-i386" ] || [ "$HOSTNAME" = "profitbricks-build12-i386" ] ; then
			# we dont vary the kernel on i386 atm, see #875990 + #876035
			sudo apt install linux-image-amd64:amd64
		elif [ "$HOSTNAME" = "osuosl-build169-amd64" ] || [ "$HOSTNAME" = "osuosl-build170-amd64" ] ; then
			# Arch Linux builds latest stuff which sometimes (eg, currentlt Qt) needs newer kernel to build...
			sudo apt install linux-image-amd64/stretch-backports || true # backport kernels are frequently uninstallable...
		fi
		# don't (re-)install pbuilder if it's on hold
		if [ "$(dpkg-query -W -f='${db:Status-Abbrev}\n' pbuilder)" != "hi " ] ; then
			$UP2DATE || sudo apt-get install pbuilder
		fi
		# remove unattended-upgrades if it's installed
		if [ "$(dpkg-query -W -f='${db:Status-Abbrev}\n' unattended-upgrades 2>/dev/null || true)" = "ii "  ] ; then
			 sudo apt-get -y purge unattended-upgrades
		fi
		sudo apt-get clean
		explain "packages installed."
	else
		explain "no new packages to be installed."
	fi
fi

#
# deploy package configuration in /etc and /usr
#
cd $BASEDIR
for h in common common-amd64 common-i386 common-arm64 common-armhf "$HOSTNAME" ; do
	# $HOSTNAME has precedence over common-$DPKG_ARCH over common
	case $h in
		common-amd64) [ $DPKG_ARCH = "amd64" ] || continue ;;
		common-i386)  [ $DPKG_ARCH = "i386" ] || continue ;;
		common-arm64) [ $DPKG_ARCH = "arm64" ] || continue ;;
		common-armhf) [ $DPKG_ARCH = "armhf" ] || continue ;;
		*) ;;
	esac
	if [ -d "hosts/$h/etc/sudoers.d/" ]; then
		for f in "hosts/$h/etc/sudoers.d/"* ; do
			/usr/sbin/visudo -c -f "$f" > /dev/null
		done
	fi
	for d in etc usr ; do
		if [ -d "hosts/$h/$d" ]; then
			sudo cp --preserve=mode,timestamps -r "hosts/$h/$d/"* "/$d"
		fi
	done
done
# we ship one or two service files…
sudo systemctl daemon-reload &

#
# more configuration than a simple cp can do
#
sudo chown root.root /etc/sudoers.d/jenkins ; sudo chmod 700 /etc/sudoers.d/jenkins
sudo chown root.root /etc/sudoers.d/jenkins-adm ; sudo chmod 700 /etc/sudoers.d/jenkins-adm
[ -f /etc/mailname ] || ( echo $HOSTNAME.debian.net | sudo tee /etc/mailname )

if [ "$HOSTNAME" = "jenkins" ] || [ "$HOSTNAME" = "profitbricks-build7-amd64" ] ; then
	if ! $UP2DATE || [ $BASEDIR/hosts/$HOSTNAME/etc/apache2 -nt $STAMP ]  ; then
		if [ ! -e /etc/apache2/mods-enabled/proxy.load ] ; then
			sudo a2enmod proxy
			sudo a2enmod proxy_http
			sudo a2enmod rewrite
			sudo a2enmod ssl
			sudo a2enmod headers
			sudo a2enmod macro
			sudo a2enmod filter
		fi
		if [ "$HOSTNAME" = "jenkins" ] ; then
			sudo a2ensite -q jenkins.debian.net
			sudo chown jenkins-adm.jenkins-adm /etc/apache2/sites-enabled/jenkins.debian.net.conf
			sudo a2enconf -q munin
		else # "$HOSTNAME" = "profitbricks-build7-amd64"
			sudo a2ensite -q buildinfos.debian.net
			sudo chown jenkins-adm.jenkins-adm /etc/apache2/sites-enabled/buildinfos.debian.net.conf
		fi
		# for reproducible.d.n url rewriting:
		[ -L /var/www/userContent ] || sudo ln -sf /var/lib/jenkins/userContent /var/www/userContent
		sudo service apache2 reload
	fi
fi

if ! $UP2DATE || [ $BASEDIR/hosts/$HOSTNAME/etc/munin -nt $STAMP ] ; then
	cd /etc/munin/plugins
	sudo rm -f postfix_* open_inodes interrupts irqstats threads proc_pri vmstat if_err_* exim_* netstat fw_forwarded_local fw_packets forks open_files users nfs* iostat_ios ntp* df_abs 2>/dev/null
	case $HOSTNAME in
			profitbricks-build1-a*|profitbricks-build10*|codethink-sled16*|osuosl-build167*) [ -L /etc/munin/plugins/squid_cache ] || for i in squid_cache squid_objectsize squid_requests squid_traffic ; do sudo ln -s /usr/share/munin/plugins/$i $i ; done ;;
			*)	;;
	esac
	case $HOSTNAME in
			jenkins) [ -L /etc/munin/plugins/postfix_mailstats ] || for i in postfix_mailstats postfix_mailvolume postfix_mailqueue ; do sudo ln -s /usr/share/munin/plugins/$i $i ; done ;;
			*)	;;
	esac
	if [ "$HOSTNAME" != "jenkins" ] && [ -L /etc/munin/plugins/iostat ] ; then
		sudo rm /etc/munin/plugins/iostat
	fi
	if ( [ "$HOSTNAME" = "jenkins" ] || [ "$HOSTNAME" = "profitbricks-build7-amd64" ] ) && [ ! -L /etc/munin/plugins/apache_accesses ] ; then
		for i in apache_accesses apache_volume ; do sudo ln -s /usr/share/munin/plugins/$i $i ; done
		sudo ln -s /usr/share/munin/plugins/loggrep jenkins_oom
	fi
	# this is a hack to work around (rare) problems with restarting munin-node...
	sudo service munin-node restart || sudo service munin-node restart || sudo service munin-node restart
fi

# add some users to groups after packages have been installed
if ! $UP2DATE ; then
	case $HOSTNAME in
		osuosl-build173-amd64)		sudo adduser jenkins sbuild ;;
		*) 				;;
	esac
fi
# finally
explain "packages configured."

#
# install the heart of jenkins.debian.net
#
cd $BASEDIR
[ -d /srv/jenkins/features ] && sudo rm -rf /srv/jenkins/features
# check for bash syntax *before* actually deploying anything
shopt -s nullglob
for f in bin/*.sh bin/**/*.sh ; do bash -n "$f" ; done
shopt -u nullglob
for dir in bin logparse mustache-templates ; do
	sudo mkdir -p /srv/jenkins/$dir
	sudo rsync -rpt --delete $dir/ /srv/jenkins/$dir/
	sudo chown -R jenkins-adm.jenkins-adm /srv/jenkins/$dir
done
HOST_JOBS="hosts/$HOSTNAME/job-cfg"
if [ -e "$HOST_JOBS" ] ; then
	sudo -u jenkins-adm rsync -rpt --copy-links --delete "$HOST_JOBS/" /srv/jenkins/job-cfg/
else
	# tidying up ... assuming that we don't want clutter on peripheral servers
	[ -d /srv/jenkins/job-cfg ] && sudo rm -rf /srv/jenkins/job-cfg
fi


sudo mkdir -p -m 700 /var/lib/jenkins/.ssh
sudo chown jenkins.jenkins /var/lib/jenkins/.ssh
if [ "$HOSTNAME" = "jenkins" ] ; then
	sudo -u jenkins install -m 600 jenkins-home/authorized_keys /var/lib/jenkins/.ssh/authorized_keys
	sudo -u jenkins cp jenkins-home/procmailrc /var/lib/jenkins/.procmailrc
	sudo -u jenkins cp jenkins-home/offline_nodes /var/lib/jenkins/offline_nodes
else
	sudo cp jenkins-nodes-home/authorized_keys /var/lib/jenkins/.ssh/authorized_keys
fi
if [ -f jenkins-nodes-home/authorized_keys.$HOSTNAME ] ; then
	cat jenkins-nodes-home/authorized_keys.$HOSTNAME | sudo tee -a /var/lib/jenkins/.ssh/authorized_keys
fi
sudo -u jenkins cp jenkins-home/ssh_config.in /var/lib/jenkins/.ssh/config
nodes/gen_ssh_config | sudo -u jenkins tee -a /var/lib/jenkins/.ssh/config > /dev/null
nodes/gen_known_host_file | sudo tee /etc/ssh/ssh_known_hosts > /dev/null
explain "scripts and configurations for jenkins updated."

if [ "$HOSTNAME" = "jenkins" ] ; then
	sudo cp -pr README INSTALL TODO CONTRIBUTING d-i-preseed-cfgs /var/lib/jenkins/userContent/
	TMPFILE=$(mktemp)
	git log | grep ^Author| cut -d " " -f2-|sort -u -f > $TMPFILE
	echo "----" >> $TMPFILE
	sudo tee /var/lib/jenkins/userContent/THANKS > /dev/null < THANKS.head
	# samuel, lunar, jelle, josch and phil committed with several committers, only display one
	grep -v -e "samuel.thibault@ens-lyon.org" -e Lunar -e "j.schauer@email.de" -e "mattia@mapreri.org" -e "phil@jenkins-test-vm" -e "jelle@vdwaa.nl" $TMPFILE | sudo tee -a /var/lib/jenkins/userContent/THANKS > /dev/null
	rm $TMPFILE
	TMPDIR=$(mktemp -d -t update-jdn-XXXXXXXX)
	sudo cp -pr userContent $TMPDIR/
	sudo chown -R jenkins.jenkins $TMPDIR
	sudo cp -pr $TMPDIR/userContent  /var/lib/jenkins/
	sudo rm -r $TMPDIR > /dev/null
	cd /var/lib/jenkins/userContent/
	ASCIIDOC_PARAMS="-a numbered -a data-uri -a iconsdir=/etc/asciidoc/images/icons -a scriptsdir=/etc/asciidoc/javascripts -b html5 -a toc -a toclevels=4 -a icons -a stylesheet=$(pwd)/theme/debian-asciidoc.css"
	[ about.html -nt README ] || asciidoc $ASCIIDOC_PARAMS -o about.html README
	[ todo.html -nt TODO ] || asciidoc $ASCIIDOC_PARAMS -o todo.html TODO
	[ setup.html -nt INSTALL ] || asciidoc $ASCIIDOC_PARAMS -o setup.html INSTALL
	[ contributing.html -nt CONTRIBUTING ] || asciidoc $ASCIIDOC_PARAMS -o contributing.html CONTRIBUTING
	diff THANKS .THANKS >/dev/null || asciidoc $ASCIIDOC_PARAMS -o thanks.html THANKS
	mv THANKS .THANKS
	rm TODO README INSTALL CONTRIBUTING
	sudo chown jenkins.jenkins /var/lib/jenkins/userContent/*html
	explain "user content for jenkins updated."
fi

if [ "$HOSTNAME" = "jenkins" ] || [ "$HOSTNAME" = "jenkins-test-vm" ] ; then
	#
	# run jenkins-job-builder to update jobs if needed
	#     (using sudo because /etc/jenkins_jobs is root:root 700)
	#
	cd /srv/jenkins/job-cfg
	for metaconfig in *.yaml.py ; do
		if [ -f $metaconfig ] ; then
			TMPFILE=$(sudo -u jenkins-adm mktemp)
			./$metaconfig | sudo -u jenkins-adm tee "$TMPFILE" >/dev/null
			if ! sudo -u jenkins-adm cmp -s ${metaconfig%.py} "$TMPFILE" ; then
				sudo -u jenkins-adm mv "$TMPFILE" "${metaconfig%.py}"
			fi
		fi
	done
	for config in *.yaml ; do
		# do update, if
		# no stamp file exist or
		# no .py file exists and config is newer than stamp or
		# a .py file exists and .py file is newer than stamp
		if [ ! -f $STAMP ] || \
		 ( [ ! -f $config.py ] && [ $config -nt $STAMP ] ) || \
		 ( [ -f $config.py ] && [ $config.py -nt $STAMP ] ) ; then
			echo "$config has changed, executing updates."
			$JJB update $config
		fi
	done
	explain "jenkins jobs updated."
fi

#
# configure git for jenkins
#
if [ "$(sudo su - jenkins -c 'git config --get user.email')" != "jenkins@jenkins.debian.net" ] ; then
	sudo su - jenkins -c "git config --global user.email jenkins@jenkins.debian.net"
	sudo su - jenkins -c "git config --global user.name Jenkins"
fi

#
# generate the kgb-client configurations
#
if [ "$HOSTNAME" = "jenkins" ] || [ "$HOSTNAME" = "osuosl-build168-amd64" ] || [ "$HOSTNAME" = "osuosl-build171-amd64" ] || [ "$HOSTNAME" = "osuosl-build172-amd64" ] || [ "$HOSTNAME" = "profitbricks-build2-i386" ] || [ "$HOSTNAME" = "profitbricks-build12-i386" ] ; then
	cd $BASEDIR
	KGB_SECRETS="/srv/jenkins/kgb/secrets.yml"
	if [ -f "$KGB_SECRETS" ] && [ $(stat -c "%a:%U:%G" "$KGB_SECRETS") = "640:jenkins-adm:jenkins-adm" ] ; then
		# the last condition is to assure the files are owned by the right user/team
		if [ "$KGB_SECRETS" -nt $STAMP ] || [ "deploy_kgb.py" -nt "$STAMP" ] || [ ! -f $STAMP ] ; then
			sudo -u jenkins-adm "./deploy_kgb.py"
		else
			explain "kgb-client configuration unchanged, nothing to do."
		fi
	else
		figlet -f banner Warning
		echo "Warning: $KGB_SECRETS either does not exist or has bad permissions. Please fix. KGB configs not generated"
		echo "We expect the secrets file to be mode 640 and owned by jenkins-adm:jenkins-adm."
		echo "/srv/jenkins/kgb should be mode 755 and owned by jenkins-adm:root."
		echo "/srv/jenkins/kgb/client-status should be mode 755 and owned by jenkins:jenkins."
	fi
	KGB_STATUS="/srv/jenkins/kgb/client-status"
	sudo mkdir -p $KGB_STATUS
	sudo chown jenkins:jenkins $KGB_STATUS
fi

#
# Create GPG key for jenkins user if they do not already exist (eg. to sign .buildinfo files)
#
if sudo -H -u jenkins gpg --with-colons --fixed-list-mode --list-secret-keys | cut -d: -f1 | grep -qsFx 'sec' >/dev/null 2>&1 ; then
	: # not generating GPG key as one already exists for jenkins user
else
	explain "$(date) - Generating GPG key for jenkins user."

	sudo -H -u jenkins gpg --no-tty --batch --gen-key <<EOF
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Name-Real: $HOSTNAME
Name-Comment: Automatically generated key for signing .buildinfo files
Expire-Date: 0
%no-ask-passphrase
%no-protection
%commit
EOF

	GPG_KEY_ID="$(sudo -H -u jenkins gpg --with-colons --fixed-list-mode --list-secret-keys | grep '^sec' | cut -d: -f5 | tail -n1)"

	if [ "$GPG_KEY_ID" = "" ]
	then
		explain "$(date) - Generated GPG key but could not parse key ID"
	else
		explain "$(date) - Generated GPG key $GPG_KEY_ID - submitting to keyserver"
		sudo -H -u jenkins gpg --send-keys $GPG_KEY_ID
	fi
fi

#
# There's always some work left...
#	echo FIXME is ignored so check-jobs scripts can output templates requiring manual work
#
if [ "$HOSTNAME" = "jenkins" ] || [ "$HOSTNAME" = "jenkins-test-vm" ] ; then
	TMPFILE=$(mktemp)
	rgrep FI[X]ME $BASEDIR/* | grep -v $BASEDIR/TODO | grep -v echo > $TMPFILE || true
	if [ -s $TMPFILE ] ; then
		echo
		cat $TMPFILE
		echo
	fi
	rm -f $TMPFILE
fi

#
# almost finally…
#
sudo touch $STAMP	# so on the next run, only configs newer than this file will be updated
explain "$(date) - finished deployment."

# finally!
case $HOSTNAME in
	# set time back to the future
	profitbricks-build5-amd64|profitbricks-build6-i386|profitbricks-build15-amd64|profitbricks-build16-i386)
		disable_dsa_check_packages
		sudo date --set="+398 days +6 hours + 23 minutes"
		;;
	codethink-sled9*|codethink-sled11*|codethink-sled13*|codethink-sled15*)
		disable_dsa_check_packages
		sudo date --set="+398 days +6 hours + 23 minutes"
		;;
	osuosl-build170-amd64|osuosl-build172-amd64)
		disable_dsa_check_packages
		sudo date --set="+398 days +6 hours + 23 minutes"
		;;
	jenkins)
		# notify irc on updates of jenkins.d.n
		MESSAGE="jenkins.d.n updated to $(cd $BASEDIR ; git describe --always)."
		kgb-client --conf /srv/jenkins/kgb/debian-qa.conf --relay-msg "$MESSAGE"
		;;
	*)	;;
esac

echo
figlet ok
echo
echo "__$HOSTNAME=ok__"

