# (c) 2014-2015 Sam Nazarko
# email@samnazarko.co.uk

#!/bin/bash

. ../common.sh

pull_source "https://sites.google.com/site/libnfstarballs/li/libnfs-1.9.8.tar.gz" "$(pwd)/src"
if [ $? != 0 ]; then echo -e "Error downloading" && exit 1; fi
# Build in native environment
build_in_env "${1}" $(pwd) "libnfs-osmc"
build_return=$?
if [ $build_return == 99 ]
then
	echo -e "Building libnfs"
	out=$(pwd)/files
	if [ -d files/usr ]; then rm -rf files/usr; fi
	if [ -d files-dev/usr ]; then rm -rf files-dev/usr; fi
	sed '/Package/d' -i files/DEBIAN/control
	sed '/Package/d' -i files-dev/DEBIAN/control
	sed '/Depends/d' -i files-dev/DEBIAN/control
	update_sources
	handle_dep "autoconf"
	handle_dep "libtool"
	echo "Package: ${1}-libnfs-osmc" >> files/DEBIAN/control && echo "Package: ${1}-libnfs-dev-osmc" >> files-dev/DEBIAN/control && echo "Depends: ${1}-libnfs-osmc" >> files-dev/DEBIAN/control
	pushd src/libnfs-*
	./bootstrap
	./configure --prefix=/usr
	$BUILD
	make install DESTDIR=${out}
	if [ $? != 0 ]; then echo "Error occured during build" && exit 1; fi
	strip_files "${out}"
	popd
	mkdir -p files-dev/usr
	mv files/usr/include  files-dev/usr/
	fix_arch_ctl "files/DEBIAN/control"
	fix_arch_ctl "files-dev/DEBIAN/control"
	dpkg_build files ${1}-libnfs-osmc.deb
	dpkg_build files-dev ${1}-libnfs-dev-osmc.deb
	build_return=$?
fi
teardown_env "${1}"
exit $build_return
