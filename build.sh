#!/bin/sh

if [ $# -lt 1 ]; then
	echo usage: $0 IPADDR
	exit 1
fi

IPADDR=$1
MAIN_DIR=$PWD

# Get the toolchain
cd $MAIN_DIR
if [ ! -d tools ]; then
	git clone git://github.com/raspberrypi/tools.git
fi
export PATH=$MAIN_DIR/tools/arm-bcm2708/arm-bcm2708hardfp-linux-gnueabi/bin:$PATH

# Get the firmware (optional)
if [ ! -d firmware ]; then
	git clone git://github.com/raspberrypi/firmware.git
fi

# Get the kernel
cd $MAIN_DIR
if [ ! -d linux ]; then
	git clone git://github.com/raspberrypi/linux.git
fi
cp -af $MAIN_DIR/cfg/linux-config $MAIN_DIR/linux/.config
cd $MAIN_DIR/linux
git checkout rpi-3.9.y
if [ ! -e $MAIN_DIR/linux/.patched ]; then
	git apply $MAIN_DIR/patches/linux.patch
	touch $MAIN_DIR/linux/.patched
fi
make ARCH=arm CROSS_COMPILE=arm-bcm2708hardfp-linux-gnueabi- -j8
cd $MAIN_DIR/tools/mkimage
./imagetool-uncompressed.py ../../linux/arch/arm/boot/zImage
cp -af kernel.img $MAIN_DIR

# Rootfs
cd $MAIN_DIR
sudo rm -rf $MAIN_DIR/rootfs $MAIN_DIR/rootfs.img
cp -af rootfs-skel rootfs

# Set the right IP address
sed -i "s/IP=.*/IP=$IPADDR/" $MAIN_DIR/rootfs/etc/init.d/rcS

# Initialize main dirs
for d in bin sbin dev home lib proc sys usr/bin usr/sbin var/log; do
	mkdir -p $MAIN_DIR/rootfs/$d
done

# Initialize /dev
cd $MAIN_DIR/rootfs/dev
cat << EOF | sudo sh
mknod tty1 c 4 1
mknod tty2 c 4 2
mknod tty3 c 4 3
mknod tty4 c 4 4
mknod tty5 c 4 5
mknod tty6 c 4 6
mknod console c 5 1
mknod null c 1 3
mknod zero c 1 5
EOF

# Build busybox
cd $MAIN_DIR
if [ ! -d busybox ]; then
	git clone git://busybox.net/busybox.git
fi
cp -af $MAIN_DIR/cfg/busybox-config $MAIN_DIR/busybox/.config
cd $MAIN_DIR/busybox
make ARCH=arm CROSS_COMPILE=arm-bcm2708hardfp-linux-gnueabi- CONFIG_PREFIX=$MAIN_DIR/rootfs install

# Build dropbear
cd $MAIN_DIR
if [ ! -e dropbear-2013.58.tar.bz2 ]; then
	wget https://matt.ucc.asn.au/dropbear/releases/dropbear-2013.58.tar.bz2
fi
if [ ! -d $MAIN_DIR/dropbear-2013.58 ]; then
	tar xjf dropbear-2013.58.tar.bz2
fi
cd $MAIN_DIR/dropbear-2013.58
./configure --host=arm --disable-zlib CC=arm-bcm2708hardfp-linux-gnueabi-gcc CFLAGS=-Os
make
cp -af dropbear $MAIN_DIR/rootfs/usr/sbin

# Copy your ssh key to login via ssh
mkdir -p $MAIN_DIR/rootfs/root/.ssh
cp -af ~/.ssh/id_dsa.pub $MAIN_DIR/rootfs/root/.ssh/authorized_keys
sudo chmod 700 $MAIN_DIR/rootfs/root -R
sudo chmod 600 $MAIN_DIR/rootfs/root/.ssh/authorized_keys

# Copy libs
cp -af $MAIN_DIR/tools/arm-bcm2708/arm-bcm2708hardfp-linux-gnueabi/arm-bcm2708hardfp-linux-gnueabi/sysroot/lib/*.so* $MAIN_DIR/rootfs/lib

# Strip binaries
arm-bcm2708hardfp-linux-gnueabi-strip -s $MAIN_DIR/rootfs/bin/* $MAIN_DIR/rootfs/sbin/* $MAIN_DIR/rootfs/usr/bin/* $MAIN_DIR/rootfs/usr/sbin/*

# Strip libs
cd $MAIN_DIR/rootfs
mkdir -p $MAIN_DIR/rootfs/lib2
mklibs -v -D -d lib2 -L lib --ldlib lib/ld-linux.so.3 --target=arm-bcm2708hardfp-linux-gnueabi bin/* sbin/* usr/sbin/* usr/bin/*
sudo rm -rf lib
sudo mv lib2 lib

# Copy over libnss and loader
cp -af $MAIN_DIR/tools/arm-bcm2708/arm-bcm2708hardfp-linux-gnueabi/arm-bcm2708hardfp-linux-gnueabi/sysroot/lib/libnss* $MAIN_DIR/rootfs/lib
cp -af $MAIN_DIR/tools/arm-bcm2708/arm-bcm2708hardfp-linux-gnueabi/arm-bcm2708hardfp-linux-gnueabi/sysroot/lib/ld-* $MAIN_DIR/rootfs/lib

arm-bcm2708hardfp-linux-gnueabi-strip -s $MAIN_DIR/rootfs/lib/*

# Set right ownership in rootfs
sudo chown -R root:root $MAIN_DIR/rootfs

# Create a squashfs image
sudo mksquashfs $MAIN_DIR/rootfs $MAIN_DIR/rootfs.img -noappend -comp lzo
