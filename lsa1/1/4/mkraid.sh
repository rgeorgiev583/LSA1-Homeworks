#!/bin/bash

# mkraid -- setups RAID

#
# Dependencies:
#  - mdadm
#

#
# TODO:  Major corrections (accepting arguments, all-in-one: remake into
# script)
#

# create RAID0 array consisting of four SATA drives 
mdadm --create --verbose /dev/md0 --level=mirror --raid-devices=4 /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sdd1

# add drive to RAID array as hot spare
mdadm /dev/md0 --add /dev/sdaX

# create RAID10 array consisting of four SATA drives 
mdadm --create --verbose /dev/md0 --level=raid01 --raid-devices=4 /dev/sda1 /dev/sdb1 /dev/sdc1 /dev/sdd1

# stop a device in a running RAID array and prepare it for replacement
mdadm /dev/md0 --fail /dev/sdaX

# create RAID6 array consisting of ten SATA drives
mdadm --create --verbose /dev/md0 --level=6 --raid-devices=10 /dev/sda1
/dev/sdb1 /dev/sdc1 /dev/sdd1 /dev/sde1 /dev/sdf1 /dev/sdg1 /dev/sdh1 /dev/sdi1
/dev/sdj1 --spare-devices=1 /dev/sdk1

# create RAID6 array consisting of five SATA drives
mdadm --create --verbose /dev/md0 --level=6 --raid-devices=5 /dev/sda1
/dev/sdb1 /dev/sdc1 /dev/sdd1 /dev/sde1 --spare-devices=1 /dev/sdf1

# save RAID configuration so that it could be reused after reboot
mdadm --detail --scan >> /etc/mdadm/mdadm.conf

