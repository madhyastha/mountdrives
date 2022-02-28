#!/bin/bash -x
#mounts a drive OR a partition that is provided as the first argument
#adds a line to the fstab if the second argument is 1 (and if the entry for the UUID doesn't already exist in fstab)
#assumes there is a file system on the drive/partition
#Reasons you might not want to add a line to an fstab - if this is an ephemeral drive 

# This script does not do much error checking. Make sure before you execute it that there is file system data
# where you expect it to be


#add UUID (first argument) to specific mountpoint (second argument) in fstab
add_to_fstab() {
    UUID=${1}
    MOUNTPOINT=${2}
    LINE="UUID=\"${UUID}\"\t${MOUNTPOINT}\text4\trw,noatime,nodiratime,nodev,exec,nosuid,nofail,auto\t1 2"
    sudo /bin/bash -c "echo -e \"${LINE}\" >> /etc/fstab"

}

#take an nvme drive name or partition name such  as /dev/nvme3n1 or /dev/nvme3n1p1 and return the sd mapping
#the nvme command must be installed prior to calling
mapnvmetosd() {
    sd=`sudo nvme id-ctrl -v $1 |grep '^0000'|grep -o 'sd.'`
    echo $sd
}

checkForSuccess() {
    # takes mountpoint and disk/partition (/dev/nvmexxxx) as argument and checks to make sure disk is mounted
    mountpoint=$1
    DISK=$2
    mounted=$(df ${mountpoint}|grep ${DISK}|awk '{print $1}')
    if [ "X${mounted}" = "X${DISK}" ]
    then
	echo "RONIN LINK SUCCESS| Disk successfully mounted"
    else
	echo "RONIN LINK ERROR| Something went wrong..."
    fi
}


if [ "$#" -ne 2 ];
then
    echo "Usage: mountDrive.sh /dev/nvmexxx  [0|1]"
    echo "where 0/1 indicates whether to add to fstab (1) or not (0)"
    exit 1
fi

device=$1
addtofstab=$2


echo "Mounting ${device}"
sd=`mapnvmetosd ${device}`
mountpoint=/dev/${sd}

# we are mounting drives here on the /mnt/sdx directories so we have unique names for them
read UUID FS_TYPE < <(blkid -u filesystem ${device}|awk -F "[= ]" '{print $3" "$5}'|tr -d "\"")
grep ${UUID} /etc/fstab  > /dev/null 2>&1
if [ ${?} -eq 1 ]; # entry is not in fstab, create entry if needed
then
    if [ -d "${mountpoint}" ]
    then
	echo "RONIN LINK ERROR| Mount point already exists"
    else
	sudo mkdir "${mountpoint}"
    fi
    
    if [ $addtofstab -eq 1 ]
    then
	add_to_fstab ${UUID} ${mountpoint}
    fi
fi
# Do the mount
echo "mounting ${device} on ${mountpoint}"
sudo mount ${device} ${mountpoint}

    





