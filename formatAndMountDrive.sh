#!/bin/bash -x
#mounts, partitions AND FORMATS a drive that is provided as the first argument
#adds a line to the fstab if the second argument is 1
#Assumes that there is NO FILE SYSTEM on the drive
#Adds an entry to the fstab if the second argument is true (1)

# This script does not do much error checking. Make sure before you execute it that drives are empty




#add UUID (first argument) to specific mountpoint (second argument) in fstab if there is not an existing entry for UUID
add_to_fstab() {
    UUID=${1}
    MOUNTPOINT=${2}
    grep "${UUID}" /etc/fstab >/dev/null 2>&1
    if [ ${?} -eq 0 ];
    then
        echo "Not adding ${UUID} to fstab again (it's already there!)"
    else
        LINE="UUID=\"${UUID}\"\t${MOUNTPOINT}\text4\trw,noatime,nodiratime,nodev,ex
ec,nosuid,nofail,auto\t1 2"
        sudo /bin/bash -c "echo -e \"${LINE}\" >> /etc/fstab"
    fi
}

#take an nvme drive name or partition name such  as /dev/nvme3n1 or /dev/nvme3n1p1 and return the sd mapping
#nvme must be installed prior to calling
mapnvmetosd() {
    sd=`sudo nvme id-ctrl -v $1 |grep '^0000'|grep -o 'sd.'`
    echo $sd
}


do_partition() {
# takes as a single argument a disk device (e.g. /dev/nvme1n1)
# This function creates one (1) primary partition on the
# disk, using all available space
    echo "Partitioning ${DISK}"
    DISK=${1}
    sudo parted ${DISK} --script -- mklabel gpt
    sudo parted -a opt ${DISK} mkpart primary ext4 0% 100% > /dev/null 2>&1
    echo "done with new partition"
}


if [ "$#" -ne 2 ];
then
    echo "Usage: formatAndMountDrive.sh /dev/nvmexxx  [0|1]"
    echo "where 0/1 indicates whether to add to fstab (1) or not (0)"
    exit 1
fi

device=$1
addtofstab=$2



echo "Formatting and mounting ${device}"
sd=`mapnvmetosd ${device}`
mountpoint=/mnt/${sd}


do_partition ${device}
PARTITION=$(sudo fdisk -l ${device}|grep -A 1 Device|tail -n 1|awk '{print $1}')
echo "Creating filesystem on ${PARTITION}."
sudo mkfs -j -t ext4 ${PARTITION}

# we are mounting drives here on the /mnt/sdx directories so we have unique names for them
read UUID FS_TYPE < <(blkid -u filesystem ${device}|awk -F "[= ]" '{print $3" "$5}'|tr -d "\"")
grep ${UUID} /etc/fstab  > /dev/null 2>&1
if [ ${?} -eq 1 ];
then
    [ -d "${mountpoint}" ] || sudo mkdir "${mountpoint}"
    echo "mounting ${PARTITION} on ${mountpoint}"
    sudo mount ${PARTITION} ${mountpoint}
    if [ $addtofstab -eq 1 ]
    then
	add_to_fstab ${UUID} ${mountpoint}
    fi
    
fi



