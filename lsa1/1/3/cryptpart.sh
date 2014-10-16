#!/bin/bash

#
# cryptpart -- encrypt Linux drive or partition using dm-crypt with LUKS
#

#
# Requirements:
#
# * Linux with dm-crypt support (obviously)
# * GRUB installed and set up as default bootloader
# * mkinitcpio -- for creating the new initial ramdisk environment
#

#
# Why dm-crypt?
#
# Because it:
#
# * enables you to achieve full control over all aspects of partition and key
#   management
# * is de-facto standard for the Linux kernel
# * ships with the default kernel (unlike loop-AES, which requires a
#   custom-built kernel configuration)
# * is block device encryption (see below) (unlike eCryptfs and EncFs, which
#   encrypt only files in an existing filesystem)
# * is implemented in kernelspace (=> fast, unlike EncFs, which resides in
#   userspace and uses FUSE => slow)
# * supports LUKS (see below), which is used to store metadata and encryption
#   key in a consistent manner (unlike the other methods, which do not support
#   LUKS, and store them in a variety of different places)
# * supports automounting on login
# * is the most secure method:
#   - supports a wide variety of ciphers:
#     AES, Anubis, CAST5/6, Twofish, Serpent, Camellia, Blowfish, …
#     (practically every cipher the kernel Crypto API offers, unlike the other
#     methods, which only allow AES, *fish and/or Serpent)
#   - supports salting
#   - supports cascading multiple ciphers on block devices (unlike EncFS)
#   - supports key-slot diffusion
#   - protects against key-scrubbing
#   - supports multiple (independently revokable) keys for the same encrypted
#     data (unlike EncFS)
# * supports multithreading
# * supports hardware-accelerated encryption
# * supports support for (manually) resizing the encrypted block device
#   in-place (unlike TrueCrypt)
# * supports access of encrypted data from Windows
# * is used by the Debian/Ubuntu installer to encrypt the system partition
#   (where / is mounted), and by the Fedora installer
# * is still supported (unlike TrueCrypt, which isn't as of May 2014)
# * is licensed under the GPL (free as in freedom)
#
#
# Why LUKS?
#
# Because it:
# 
# * is an additional convenience layer
# * stores all of the needed setup information (cryptographic metadata and
#   wrapped encyption key) for dm-crypt on the disk itself
# * abstracts partition and key management in an attempt to improve ease of
#   use and cryptographic security
#
#
# Why block device encyption?
#
# Because it (unlike stacked filesystem encryption methods):
#
# * operates below the filesystem layer
# * makes sure that *everything* written to a certain block device (i.e. a
#   whole disk, or a partition, or a file acting as a virtual loop-back
#   device) is encrypted
# * doesn't care whether the content of the encrypted block device is a
#   filesystem, a partition table, a LVM setup, or anything else.
# * encrypts file metadata
# * allows for encryption of whole hard drives (including partition tables)
# * allows for encryption of swap space
#
# In contrast, stacked filesystem encryption methods add an additional layer
# to an existing filesystem, to automatically encrypt/decrypt files whenever
# they're written/read.
#

#
# Usage:
#
# cryptpart [ -n <device-mapper name> | -t <type> | -m <mountpoint> | -B | -C ]
#   <device>
#
# -n <device-mapper name>   - name of device to map partition/drive to
# -t <type>                 - device filesystem type
# -m <mountpoint>           - name of directory where to mount the encrypted
#                             device
# -B                        - do not configure bootloader (e.g. if not using
#                             GRUB)
# -C                        - do not configure anything (if you do not want
#                             persistence)
# -h                        - print usage information and exit
#
# <device>                  - drive or partition to encypt, e.g. /dev/sda or
#                             /dev/sdb1
#

# prints usage info
function help {
	echo 'Usage:

cryptpart [ -n <device-mapper name> | -t <type> | -m <mountpoint> | -B | -C ]
  <device>

-n <device-mapper name>   - name of device to map partition/drive to
-t <type>                 - device filesystem type
-m <mountpoint>           - name of directory where to mount the encrypted
                            device
-B                        - do not configure bootloader (e.g. if not using
                            GRUB)
-C                        - do not configure anything (if you do not want
                            persistence)
-h                        - print usage information and exit

<device>                  - drive or partition to encypt, e.g. /dev/sda or
                            /dev/sdb1
						 
'
}

# if no arguments were passed, print usage info and exit
if [ "$#" -eq 0 ]; then
	help
	exit 0
fi

# reset getopts
OPTIND=1

# retrieve command-line arguments one by one
while getopts ":n:" opt; do
	case "$opt" in
		# device mapper name
		n)
			DEVMAPPER_NAME="$OPTARG"
			;;
		# filesystem type
		t)
			TYPE="$OPTARG"
			;;
		# mountpoint
		m)
			MOUNTPOINT="$OPTARG"
			;;
		# disable bootloader configuration
		B)
			NO_CONFIG_BOOTLDR='1'
			;;
		# disable any configuration
		C)
			NO_CONFIG='1'
			;;
		# help
		h)
			# print usage info and exit
			help
			exit 0
			;;
	esac
done

# trim non-positional arguments in order to read the positional ones
shift "$(($OPTIND - 1))"

# if device is NOT specified as argument, print error message and exit with
#   error code
if [ -z "$1" ]; then
	echo "error: no drive or partition specified" > /dev/stderr
	exit 1;
fi

# if device is NOT a storage drive or partition (i.e. is NOT a valid one),
#   print error message and exit with error code
if [[ ! "$1" =~ \/dev\/sd ]]; then
	echo "error: invalid drive or partition specified" > /dev/stderr
	exit 2;
fi

# the device specified is a valid one, so continue
DEVICE="$1"

# if device mapper name is NOT specified as argument,
#   assign default value: get short device name from full device pathname
#   and use it as device mapper name
#
if [ -z "$DEVMAPPER_NAME" ]; then
	DEVMAPPER_NAME="${DEVICE##*/}"
fi

if [ -z "$TYPE" ]; then
	TYPE="ext4"
fi

if [ -z "$MOUNTPOINT" ]; then
	MOUNTPOINT="/mnt"
fi

# -- Part 1. Drive preparation --

# create a temporary encrypted container
cryptsetup open --type plain $DEVICE container

# check for existence
if ! fdisk -l; then
	echo "error: could not create encrypted container" > /dev/stderr
	return 3;
fi

# wipe with pseudorandom (encrypted data)
dd if=/dev/zero of=/dev/mapper/container

# -- Part 2. Device encryption --

# encrypt partition
cryptsetup -s 512 -h sha512 -y luksFormat $DEVICE

# DEBUG: check if encryption was successful
#cryptsetup luksDump $DEVICE

# unlock encrypted device
cryptsetup open --type luks $DEVICE $DEVMAPPER_NAME

# create filesystem for encrypted device
mkfs -t $TYPE $DEVMAPPER_NAME

# mount said filesystem
mount -t $TYPE $DEVMAPPER_NAME $MOUNTPOINT

#
# You can use the device now. To close it (unmount and lock it again), please
#   execute the following commands:
#
#umount $MOUNTPOINT
#cryptsetup close $DEVMAPPER_NAME

#
# -- Part 3. System configuration --
#
# WARNING: The following code will only work with GRUB-based systems.  If you
#   use another bootloader, you have to do the following part yourself
#   (and you will also have to run this script with the `-b' parameter
#   enabled.)
# WARNING #2: This script also assumes that you have a separate /boot
#   partition mounted where GRUB is located.
# WARNING #3: The following WON'T work with GRUB legacy.  Please update your
#   system instead. :-)
#

# skip the following steps if `-C' flag is raised
if [ -n "$NO_CONFIG" ]; then
	return 0	
fi

#
# a) configure mkinitcpio:
#

# append hooks to mkinitcpio config file
sed 's/^\(HOOKS=".+\)"$/\1 encrypt keyboard"' -i /etc/mkinitcpio.conf
mkinitcpio -p linux

#
# b) configure bootloader:
#

# a kernel parameter which instructs the kernel that $DEVICE is encrypted
#   and is mapped to $DEVMAPPER_NAME has to be passed at boot time
# so therefore append said kernel parameter to the GRUB_CMDLINE_LINUX_DEFAULT
#   line in /etc/default/grub to make it run persistently at every boot
#

# skip bootloader configuration part if `-B' flag is raised
if [ -z "$NO_CONFIG_BOOTLDR" ]; then
	# append kernel parameter to config file
	sed 's/^\(GRUB_CMDLINE_LINUX_DEFAULT=".+\)"$/\1 cryptdevice=$DEVICE:$DEVMAPPER_NAME"/' -i /etc/default/grub

	# generate grub config file with new kernel parameter 
	grub-mkconfig -o /boot/grub/grub.cfg
fi

#
# c) configure crypttab:
#

#
# get device UUID (this is a VERY UGLY hack but I couldn't find an another way
# out)
#
DEVICE_UUID=$(blkid | grep $DEVICE | sed 's/.*UUID="\([0-9a-f-]\+\)".*/\1/')

# add encrypted device to /etc/crypttab
echo -e "$DEVICE_NAME\tUUID=$DEVICE_UUID\tnone\tluks,timeout=180" >> /etc/crypttab

# add encrypted device to /etc/fstab
echo -e "$DEVMAPPER_NAME\t$MOUNTPOINT\text4\tdefaults,errors=remount-ro\t0\t2" >> /etc/fstab
