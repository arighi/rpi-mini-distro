#!/bin/sh

MAIN_DIR=$PWD

# Get the toolchain
cd $MAIN_DIR
git clone git://github.com/raspberrypi/tools.git
export PATH=$MAIN_DIR/tools/arm-bcm2708/arm-bcm2708hardfp-linux-gnueabi/bin:$PATH

# Get the kernel
cd $MAIN_DIR
git clone git://github.com/raspberrypi/linux.git
cp $MAIN_DIR/cfg/linux-config $MAIN_DIR/linux/.config
cd $MAIN_DIR/linux
make ARCH=arm CROSS_COMPILE=arm-bcm2708hardfp-linux-gnueabi- -j8
cd $MAIN_DIR/tools/mkimage
imagetool-uncompressed.py ../../linux/arch/arm/boot/zImage
cp kernel.img $MAIN_DIR

# Rootfs
cd $MAIN_DIR
cp -af rootfs-skel rootfs

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
git clone git://busybox.net/busybox.git
cp $MAIN_DIR/cfg/busybox-config $MAIN_DIR/busybox/.config
cd $MAIN_DIR/busybox
make ARCH=arm CROSS_COMPILE=arm-bcm2708hardfp-linux-gnueabi- CONFIG_PREFIX=$MAIN_DIR/rootfs install

# Build dropbear
cd $MAIN_DIR
wget https://matt.ucc.asn.au/dropbear/releases/dropbear-2013.58.tar.bz2
tar xjf dropbear-2013.58.tar.bz2
cd $MAIN_DIR/dropbear-2013.58
./configure --host=arm --disable-zlib CC=arm-bcm2708hardfp-linux-gnueabi-gcc CFLAGS=-Os
make
cp dropbear $MAIN_DIR/rootfs/usr/sbin

# Copy your ssh key to login via ssh
mkdir -p $MAIN_DIR/root/.ssh
cp ~/.ssh/id_dsa.pub $MAIN_DIR/rootfs/root/.ssh/authorized_keys
chmod 600 rootfs/root/.ssh/authorized_keys

# Copy libs
cp -af $MAIN_DIR/tools/arm-bcm2708/arm-bcm2708hardfp-linux-gnueabi/arm-bcm2708hardfp-linux-gnueabi/sysroot/lib/*.so* $MAIN_DIR/rootfs/lib

# Strip binaries
arm-bcm2708hardfp-linux-gnueabi-strip -s $MAIN_DIR/rootfs/bin/* $MAIN_DIR/rootfs/sbin/* $MAIN_DIR/rootfs/usr/bin/* $MAIN_DIR/rootfs/usr/sbin/*

# Strip libs
cd $MAIN_DIR/rootfs
mklibs -v -D -d lib2 -L lib --ldlib lib/ld-linux.so.3 --target=arm-bcm2708hardfp-linux-gnueabi bin/* sbin/* usr/sbin/* usr/bin/*
sudo rm -rf lib
sudo mv lib2 lib

# Copy over libnss and loader
cp -af $MAIN_DIR/tools/arm-bcm2708/arm-bcm2708hardfp-linux-gnueabi/arm-bcm2708hardfp-linux-gnueabi/sysroot/lib/libnss* $MAIN_DIR/rootfs
cp -af $MAIN_DIR/tools/arm-bcm2708/arm-bcm2708hardfp-linux-gnueabi/arm-bcm2708hardfp-linux-gnueabi/sysroot/lib/ld-* $MAIN_DIR/rootfs

arm-bcm2708hardfp-linux-gnueabi-strip -s $MAIN_DIR/rootfs/lib/*

# Set right ownership in rootfs
sudo chown -R root:root $MAIN_DIR/rootfs
