#!/bin/bash

#
# mkramdisk -- create ramdisk
#

#
# Usage:
#
# mkramdisk [ -n <index> | -t <type> | -l <size> | -h ] [ <name> ]
#
# -n <index>  - index of ram device, default: 0
# -t <type>   - filesystem type, default: ext2
# -l <size>   - filesystem size, default: 8192
# -h          - print usage information and exit
#
# <name>      - ramdisk mount name
#

# reset getopts
OPTIND=1

# retrieve command-line arguments one by one
while getopts ":n:t:l:" opt; do
	case "$opt" in
		# ram device index
		n)
			NUMBER="$OPTARG"
			;;
		# filesystem type
		t)
			TYPE="$OPTARG"
			;;
		# filesystem size
		l)
			SIZE="$OPTARG"
			;;
		# help
		h)
			# print usage info and exit
			echo 'Usage:

mkramdisk [ -n <index> | -t <type> | -l <size> | -h ] [ <name> ]

-n <index>  - index of ram device, default: 0
-t <type>   - filesystem type, default: ext2
-l <size>   - filesystem size, default: 8192
-h          - print usage information and exit

<name>      - ramdisk mount name

'
			exit 0
			;;
	esac
done

#
# if ram device index is NOT specified as argument or the value specified is
#   NOT valid (i.e. NOT a number), assign default value
#
if [ -z "$NUMBER" -o "$NUMBER" -ne "$NUMBER" ] > /dev/null; then
	NUMBER=0
fi

# if filesystem type is NOT specified as argument, assign default value
if [ -z "$TYPE" ]; then
	TYPE="ext2"
fi

# if filesystem size is NOT specified as argument, assign default value
if [ -z "$SIZE" -o "$SIZE" -ne "$SIZE" ]; then
	SIZE=8192
fi

# trim non-positional arguments in order to read the positional ones
shift "$(($OPTIND - 1))"

#
# for security reasons make sure ramdisk name does NOT contain any `/'s
#   and if it does, revert to default value
#
if [[ ! "$1" =~ / ]]; then
	NAME="$1"
else
	NAME=ramcache
fi

# create filesystem for ramdisk
mkfs -t $TYPE -q /dev/ram$NUMBER $SIZE 

# and mount said filesystem (if it is not already mounted, of course)
if [ -d /mnt/$NAME ]; then
	echo "error: /mnt/$NAME already exists" > /dev/stderr
	exit 1
fi
mkdir -p /mnt/$NAME
mount /dev/ram$NUMBER /mnt/$NAME

# print mountpoint
echo "/mnt/$NAME"

# at this point user may check if the new filesystem is up and running by
#   executing these commands
#df -H | grep $NAME

# Okay, you are done! Now you may copy things to the ramdisk, e.g.:
#cp ~/foo/bar /mnt/$NAME
# Be aware that you may have to run these commands with root permissions.

