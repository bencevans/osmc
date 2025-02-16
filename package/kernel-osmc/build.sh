# (c) 2014-2015 Sam Nazarko
# email@samnazarko.co.uk

#!/bin/bash

. ../common.sh
test $1 == rbp1 && VERSION="4.2.1" && REV="1"
test $1 == rbp2 && VERSION="4.2.1" && REV="1"
test $1 == vero && VERSION="4.1.7" && REV="4"
test $1 == atv && VERSION="4.2.3" && REV="2"
test $1 == pc && VERSION="4.2.3" && REV="1"
if [ $1 == "rbp1" ] || [ $1 == "rbp2" ] || [ $1 == "atv" ] || [ $1 == "pc" ]
then
	if [ -z $VERSION ]; then echo "Don't have a defined kernel version for this target!" && exit 1; fi
	MAJOR=$(echo ${VERSION:0:1})
	SOURCE_LINUX="https://www.kernel.org/pub/linux/kernel/v${MAJOR}.x/linux-${VERSION}.tar.xz"
fi
if [ $1 == "vero" ]; then SOURCE_LINUX="https://github.com/osmc/vero-linux/archive/master.tar.gz"; fi
pull_source "${SOURCE_LINUX}" "$(pwd)/src"
if [ $? != 0 ]; then echo -e "Error downloading" && exit 1; fi
# Build in native environment
BUILD_OPTS=get_build_option_defaults
BUILD_OPTS=(($BUILD_OPTS - $BUILD_OPTION_USE_NOFP))
build_in_env "${1}" $(pwd) "kernel-osmc" "$BUILD_OPTS"
build_return=$?
if [ $build_return == 99 ]
then
	echo -e "Building Linux kernel"
	make clean
	sed '/Package/d' -i files/DEBIAN/control
	sed '/Depends/d' -i files/DEBIAN/control
	update_sources
	handle_dep "kernel-package"
	handle_dep "liblz4-tool"
	handle_dep "cpio"
	handle_dep "bison"
	handle_dep "flex"
	echo "maintainer := Sam G Nazarko
	email := email@samnazarko.co.uk
	priority := High" >/etc/kernel-pkg.conf
	JOBS=$(if [ ! -f /proc/cpuinfo ]; then mount -t proc proc /proc; fi; cat /proc/cpuinfo | grep processor | wc -l && umount /proc/ >/dev/null 2>&1)
	pushd src/*linux*
	if [ "$1" == "rbp1" ] || [ "$1" == "rbp2" ]
	then
		install_patch "../../patches" "rbp"
		rm -rf drivers/net/wireless/rtl8192cu
		# have to do this after, because upstream brings its own rtl8192cu in! Other kernels use rtlwifi by default. Have to do earlier here or Kconfig won't find it!
		mv drivers/net/wireless/rtl8192cu-new drivers/net/wireless/rtl8192cu
	fi
	install_patch "../../patches" "${1}"
	# Set up DTC
	if [ "$1" == "rbp1" ] || [ "$1" == "rbp2" ]
	then
		pushd dtc-overlays
		$BUILD
		popd
		DTC=$(pwd)"/dtc-overlays/dtc"
	else
		$BUILD scripts
		DTC=$(pwd)"/scripts/dtc/dtc"
	fi
	make-kpkg --stem $1 kernel_image --append-to-version -${REV}-osmc --jobs $JOBS --revision $REV
	if [ $? != 0 ]; then echo "Building kernel image package failed" && exit 1; fi
	make-kpkg --stem $1 kernel_headers --append-to-version -${REV}-osmc --jobs $JOBS --revision $REV
	if [ $? != 0 ]; then echo "Building kernel headers package failed" && exit 1; fi
	make-kpkg --stem $1 kernel_source --append-to-version -${REV}-osmc --jobs $JOBS --revision $REV
	if [ $? != 0 ]; then echo "Building kernel source package failed" && exit 1; fi
	# Make modules directory
	mkdir -p ../../files-image/lib/modules/${VERSION}-${REV}-osmc/kernel/drivers
	if [ "$1" == "rbp1" ] || [ "$1" == "rbp2" ]; then mkdir -p ../../files-image/boot/dtb-${VERSION}-${REV}-osmc/overlays; fi
	if [ "$1" == "vero" ]; then mkdir -p ../../files-image/boot/dtb-${VERSION}-${REV}-osmc; fi
	if [ "$1" == "atv" ]; then mkdir -p ../../files-image/boot; fi
	if [ "$1" == "rbp1" ]
	then
		make bcm2708-rpi-b.dtb
		make bcm2708-rpi-b-plus.dtb
	fi
	if [ "$1" == "rbp2" ]; then make bcm2709-rpi-2-b.dtb; fi
	if [ "$1" == "rbp1" ] || [ "$1" == "rbp2" ]
	then
		mv arch/arm/boot/dts/*.dtb ../../files-image/boot/dtb-${VERSION}-${REV}-osmc/
		overlays=( "hifiberry-dac-overlay" "hifiberry-dacplus-overlay" "hifiberry-digi-overlay" "hifiberry-amp-overlay" "iqaudio-dac-overlay" "iqaudio-dacplus-overlay" "rpi-dac-overlay" "lirc-rpi-overlay" "w1-gpio-overlay" "w1-gpio-pullup-overlay" "hy28a-overlay" "hy28b-overlay" "piscreen-overlay" "rpi-display-overlay" "spi-bcm2835-overlay" "sdhost-overlay" "rpi-proto-overlay" "i2c-rtc-overlay" "i2s-mmap-overlay" "pps-gpio-overlay" "uart1-overlay" "rpi-ft5406-overlay" "rpi-sense-overlay")
		pushd arch/arm/boot/dts/overlays
		for dtb in ${overlays[@]}
		do
			echo Building DT overlay $dtb
			$DTC -@ -I dts -O dtb -o $dtb.dtb $dtb.dts
		done
		popd
		mv arch/arm/boot/dts/overlays/*-overlay.dtb ../../files-image/boot/dtb-${VERSION}-${REV}-osmc/overlays
	fi
	if [ "$1" == "vero" ]
	then
		make imx6dl-vero.dtb
		mv arch/arm/boot/dts/*.dtb ../../files-image/boot/dtb-${VERSION}-${REV}-osmc/
	fi
	# Add out of tree modules that lack a proper Kconfig and Makefile
	# Fix CPU architecture
	ARCH=$(arch)
    echo $ARCH | grep -q arm
    if [ $? == 0 ]
	then
	    ARCH=$(echo $ARCH | tr -d v7l | tr -d v6)
	fi
	if [ $ARCH == "i686" ]; then ARCH="i386"; fi
	export ARCH
		if [ "$1" == "rbp1" ] || [ "$1" == "rbp2" ] || [ "$1" == "atv" ] || [ "$1" == "vero" ]
		then
		# Build RTL8812AU module
		pushd drivers/net/wireless/rtl8812au
		$BUILD
		if [ $? != 0 ]; then echo "Building kernel module failed" && exit 1; fi
		popd
		mkdir -p ../../files-image/lib/modules/${VERSION}-${REV}-osmc/kernel/drivers/net/wireless/
		cp drivers/net/wireless/rtl8812au/8812au.ko ../../files-image/lib/modules/${VERSION}-${REV}-osmc/kernel/drivers/net/wireless/
		fi
		if [ "$1" == "rbp1" ] || [ "$1" == "rbp2" ] || [ "$1" == "atv" ] || [ "$1" == "vero" ]
		then
		# Build RTL8192CU module
		if [ "$1" == "atv" ] || [ "$1" == "vero" ]; then mv drivers/net/wireless/rtl8192cu-new drivers/net/wireless/rtl8192cu; fi
		pushd drivers/net/wireless/rtl8192cu
		$BUILD
		if [ $? != 0 ]; then echo "Building kernel module failed" && exit 1; fi
		popd
		mkdir -p ../../files-image/lib/modules/${VERSION}-${REV}-osmc/kernel/drivers/net/wireless/
		cp drivers/net/wireless/rtl8192cu/8192cu.ko ../../files-image/lib/modules/${VERSION}-${REV}-osmc/kernel/drivers/net/wireless/
		fi
		if [ "$1" == "rbp1" ] || [ "$1" == "rbp2" ] || [ "$1" == "atv" ] || [ "$1" == "vero" ]
		then
		# Build RTL8192DU model
		pushd drivers/net/wireless/rtl8192du
		$BUILD
		if [ $? != 0 ]; then echo -e "Building kernel module failed" && exit 1; fi
		popd
		mkdir -p ../../files-image/lib/modules/${VERSION}-${REV}-osmc/kernel/drivers/net/wireless/
		cp drivers/net/wireless/rtl8192du/8192du.ko ../../files-image/lib/modules/${VERSION}-${REV}-osmc/kernel/drivers/net/wireless/
		fi
		if [ "$1" == "rbp1" ] || [ "$1" == "rbp2" ] || [ "$1" == "atv" ] || [ "$1" == "vero" ]
		then
		# Build RTL8192EU model
		pushd drivers/net/wireless/rtl8192eu
		$BUILD
		if [ $? != 0 ]; then echo -e "Building kernel module failed" && exit 1; fi
		popd
		mkdir -p ../../files-image/lib/modules/${VERSION}-${REV}-osmc/kernel/drivers/net/wireless/
		cp drivers/net/wireless/rtl8192eu/8192eu.ko ../../files-image/lib/modules/${VERSION}-${REV}-osmc/kernel/drivers/net/wireless/
		fi
		if [ "$1" == "atv" ]
		then
		# Build CrystalHD
		pushd drivers/staging/chd
		$BUILD
		if [ $? != 0 ]; then echo -e "Building kernel module failed" && exit 1; fi
		popd
		mkdir -p ../../files-image/lib/modules/${VERSION}-${REV}-osmc/kernel/drivers/staging/chd/
		cp drivers/staging/chd/crystalhd.ko ../../files-image/lib/modules/${VERSION}-${REV}-osmc/kernel/drivers/staging
		fi
		if [ "$1" == "atv" ]
		then
		pushd drivers/staging/nv-osmc
		$BUILD SYSSRC=$(pwd)/../../../
		if [ $? != 0 ]; then echo -e "Building kernel module failed" && exit 1; fi
		popd
		mkdir -p ../../files-image/lib/modules/${VERSION}-${REV}-osmc/kernel/drivers/staging/nv-osmc
		cp drivers/staging/nv-osmc/nvidia.ko ../../files-image/lib/modules/${VERSION}-${REV}-osmc/kernel/drivers/staging
		fi
	# Unset architecture
	ARCH=$(arch)
	export ARCH
	popd
	# Disassemble kernel image package to add device tree overlays, additional out of tree modules etc
	mv src/${1}-image*.deb .
	dpkg -x ${1}-image*.deb files-image/
	dpkg-deb -e ${1}-image*.deb files-image/DEBIAN
	rm ${1}-image*.deb
	dpkg_build files-image ${1}-image-${VERSION}-${REV}-osmc.deb
	# Disassemble kernel headers package to include full headers (upstream Debian bug...)
	if [ "$ARCH" == "armv7l" ]
	then
		mv src/${1}-headers*.deb .
		mkdir -p files-headers/
		dpkg -x ${1}-headers*.deb files-headers/
		dpkg-deb -e ${1}-headers*.deb files-headers/DEBIAN
		rm ${1}-headers*.deb
		cp -ar src/*linux*/arch/arm/include/ files-headers/usr/src/*-headers-${VERSION}-${REV}-osmc/include
		dpkg_build files-headers ${1}-headers-${VERSION}-${REV}-osmc.deb
	fi
	echo "Package: ${1}-kernel-osmc" >> files/DEBIAN/control
	echo "Depends: ${1}-image-${VERSION}-${REV}-osmc" >> files/DEBIAN/control
	fix_arch_ctl "files/DEBIAN/control"
	dpkg_build files/ ${1}-kernel-${VERSION}-${REV}-osmc.deb
	build_return=$?
fi
teardown_env "${1}"
exit $build_return
