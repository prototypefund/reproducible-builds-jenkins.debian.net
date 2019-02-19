#!/bin/sh

# as posted by Vagrant on https://lists.reproducible-builds.org/pipermail/rb-general/2018-October/001239.html

packages="$@"
bdn_url="https://buildinfo.debian.net/api/v1/buildinfos/checksums/sha1"
log=${0}.log

reproducible_packages=
unreproducible_packages=
for package in $packages ; do
	apt-get download ${package}/sid
	sha1sum ${package}_*.deb | while read checksum package_file ; do
		if [ ! -e ${package_file}.json ]; then
			wget --quiet -O ${package_file}.json ${bdn_url}/${checksum}
		fi
		count=$(fmt ${package_file}.json | grep '\.buildinfo' | wc -l)
		if [ "${count}" -ge 2 ]; then
			echo "REPRODUCIBLE: $package_file $count"
		else
			echo "UNREPRODUCIBLE: $package_file $count"
		fi
		echo
	done
done > $log

reproducible_packages=$(awk '/^REPRODUCIBLE:/{print $2}' $log)
reproducible_count=$(echo $reproducible_packages | wc -w)
unreproducible_packages=$(awk '/^UNREPRODUCIBLE:/{print $2}' $log)
unreproducible_count=$(echo $unreproducible_packages | wc -w)

echo reproducible packages: $reproducible_count: $reproducible_packages
echo
echo unreproducible packages: $unreproducible_count: $unreproducible_packages
