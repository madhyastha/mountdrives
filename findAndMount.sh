#!/bin/bash -x

# install the nvme tools
#sudo apt-get update >& /dev/null
#sudo apt install nvme-cli -y >& /dev/null

# Get any unmounted and unpartitioned ephemeral drives. We assume these would
# have been ignored upon launch - so we can offer to partition them, put file systems
getUnmountedEphemeralDrives() {
    DISKS=""
    # Looks for unpartitioned NVME disks that are Ephemeral volumes
    ALLDISKS=$(lsblk --noheadings --raw -o NAME,TYPE|grep nvme|awk '$2=="disk" {print $1}')
    for disk in $ALLDISKS
    do
	sudo nvme id-ctrl -v /dev/${disk}|grep '^mn '| grep "Instance">&/dev/null
            if [ $? -eq 0 ]; 
	    then
		DISKS="$DISKS ${disk}"
	    fi
	done
		   
    # Find unmounted disks that don't have partitions
    PARTS=$(lsblk --noheadings --raw -o NAME,TYPE|grep nvme|awk '$2=="part" {print $1}')

    RAW=""
    for i in $DISKS
    do
	found=`grep "$i" <<< ${PARTS}`
	if [ -z $found ]
	then
	    RAW="$RAW /dev/$i"
	fi
    done
    
    echo "unmounted ephemeral drives:" $RAW
    
    for i in $RAW
    do
        ID=$(sudo nvme id-ctrl -v $i | grep "0000:" | awk '{print $NF}' | sed 's/\.//g' | sed 's/^"//' | sed 's/"$//' | sed 's/:.*//' | sed 's/\/dev\///')
	STRIP=$(echo $i | awk -F '/' '{print $3}')
	SIZE=$(lsblk | grep $STRIP | awk 'NR==1{print $4}')
	MOUNTPOINT="/mnt/$ID" 
	echo "RONINLINK | EPHEMERAL | $ID | $SIZE | BLANK | $MOUNTPOINT"
    done
    
 }


getUnmountedEmptyEBSDrives() {
    DISKS=""
    # Looks for unpartitioned NVME disks that are EBS volumes
    ALLDISKS=$(lsblk --noheadings --raw -o NAME,TYPE|awk '$2=="disk" {print $1}
')
    for disk in $ALLDISKS
    do
	sudo nvme id-ctrl -v /dev/${disk}|grep '^mn '| grep "Amazon Elastic Block Store">&/dev/null
            if [ $? -eq 0 ]; 
	    then
		DISKS="$DISKS ${disk}"
	    fi
	done
		   
    # Find unmounted disks that don't have partitions
    PARTS=$(lsblk --noheadings --raw -o NAME,TYPE|awk '$2=="part" {print $1}')


    NOPART=""
    for i in $DISKS
    do
	found=`grep "$i" <<< ${PARTS}`
	if [ -z $found ]
	then
	    NOPART="$NOPART /dev/$i"
	fi
    done

    #Now check to see if any of these have file systems
    RAW=""
    for i in $NOPART
    do
	has_filesystem ${i}
	if [ ${?} -ne 0 ]; # no file system
	then
	    RAW="$RAW ${i}"
	fi
    done
    echo "unmounted RAW EBS drives:" $RAW
    
    for i in $RAW
    do
        ID=$(sudo nvme id-ctrl -v $i | grep "0000:" | awk '{print $NF}' | sed 's/\.//g' | sed 's/^"//' | sed 's/"$//' | sed 's/:.*//' | sed 's/\/dev\///')
	STRIP=$(echo $i | awk -F '/' '{print $3}')
	SIZE=$(lsblk | grep $STRIP | awk 'NR==1{print $4}')
	MOUNTPOINT="/mnt/$ID" # Need to figure out a way to keep mount point bound to a drive ID so it doesn't get messed up - this might be better than using "volume1" etc?
	echo "RONINLINK | EBS | /dev/$ID | $SIZE | BLANK | $MOUNTPOINT"
    done
    
}


getUnmountedEBSDrivesAndPartitionsWithData() {
    DISKS=""
    # Looks for any unmounted EBS volumes with data on them
    UNMOUNTEDDISKS=$(lsblk --noheadings --raw -o NAME,TYPE,MOUNTPOINT|grep nvme|awk '{if($2=="disk" && $3=="") print $1}')
    # limit to EBS only
    for disk in $UNMOUNTEDDISKS
    do
	sudo nvme id-ctrl -v /dev/${disk}|grep '^mn '| grep "Amazon Elastic Block Store">&/dev/null
            if [ $? -eq 0 ]; 
	    then
		DISKS="$DISKS ${disk}"
	    fi
	done
		   
    # Find unmounted disks that don't have mounted partitions
    MOUNTEDPARTS=$(lsblk --noheadings --raw -o NAME,TYPE,MOUNTPOINT|awk '{if($2=="part" && $3!="") print $1}')


    NOPART=""
    for i in $DISKS
    do
	found=`grep "$i" <<< ${MOUNTEDPARTS}`
	if [ -z $found ]
	then
	    NOPART="$NOPART $i"
	fi
    done

    
    # Now for each drive without a mounted partition,
    # see if it has an unmounted partition. Grab the partition rather than the drive, because
    # that is then what we will need to deal with
    UNMOUNTEDPARTS=$(lsblk --noheadings --raw -o NAME,TYPE,MOUNTPOINT|awk '{if ($2=="part" && $3=="") print $1}')
    HASPART=""
    DRIVES=""
    for i in $NOPART
    do
	found=`grep "$i" <<< ${UNMOUNTEDPARTS}`
	if [ -z $found ]
	then
	    DRIVES="${DRIVES} $i"
	else
	    HASPART="${HASPART} /dev/$i"
	fi
    done
    
    # For each drive with an unmounted partition, check to see if the partition is the full size of the drive
    FULLPART=""
    RESIZED=""
    for i in $HASPART
    do
        STRIP=$(echo $i | awk -F '/' '{print $3}')
	DISKSIZE=$(lsblk | grep $STRIP | grep "disk" | awk '{print $4}')
	PARTITIONSIZE=$(lsblk | grep $STRIP | grep -v "disk" | awk 'NR==1{print $4}')
	if [[ $DISKSIZE == $PARTITIONSIZE ]]
	then
	    FULLPART="${FULLPART} $i"
	else
	    RESIZED="${RESIZED} $i"
	fi
    done

    # Finally, check the drives to see if they have
    # file data on them

    DRIVESWITHDATA=""
    for d in ${DRIVES}
    do
	has_filesystem /dev/${d}
	if [ ${?} -eq 0 ]; # has a file system
	then
	    DRIVESWITHDATA="$DRIVESWITHDATA /dev/${d}"
	fi
    done
	     
    # Everything here is unmounted 
    # But should have file system data.
    echo unmounted drives that have data: ${DRIVESWITHDATA}
    echo unmounted drives with partitions that probably have data: ${HASPART}
    echo unmounted drives with partitions that are the full size of the drive: ${FULLPART}
    echo unmounted drives that have been resized and require a filesystem extension: ${RESIZED}
    
    for i in $FULLPART
    do
        ID=$(sudo nvme id-ctrl -v $i | grep "0000:" | awk '{print $NF}' | sed 's/\.//g' | sed 's/^"//' | sed 's/"$//' | sed 's/:.*//' | sed 's/\/dev\///')
	STRIP=$(echo $i | awk -F '/' '{print $3}')
	SIZE=$(lsblk | grep $STRIP | awk 'NR==1{print $4}')
	MOUNTPOINT="/mnt/$ID" # Need to figure out a way to keep mount point bound to a drive ID so it doesn't get messed up - this might be better than using "volume1" etc?
	echo "RONINLINK | EBS | /dev/$ID | $SIZE | DATA | $MOUNTPOINT"
    done
    
    for i in $RESIZED
    do
        ID=$(sudo nvme id-ctrl -v $i | grep "0000:" | awk '{print $NF}' | sed 's/\.//g' | sed 's/^"//' | sed 's/"$//' | sed 's/:.*//' | sed 's/\/dev\///')
	STRIP=$(echo $i | awk -F '/' '{print $3}')
	SIZE=$(lsblk | grep $STRIP | awk 'NR==1{print $4}')
	MOUNTPOINT="/mnt/$ID" # Need to figure out a way to keep mount point bound to a drive ID so it doesn't get messed up - this might be better than using "volume1" etc?
	echo "RONINLINK | RESZIED | /dev/$ID | $SIZE | DATA | $MOUNTPOINT"
    done
    
}

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
        echo -e "${LINE}" >> /etc/fstab
    fi
}

is_partitioned() {
# Checks if there is a valid partition table on the
# specified disk
    OUTPUT=$(sfdisk -l ${1} | grep '^Device'| awk '{print $1}')
    if [ -z "${OUTPUT}" ]
    then
	return 1 # not partitioned
    else
	return 0 # partitioned
    fi
     
}

has_filesystem() {
    DEVICE=${1}
    OUTPUT=$(file -s ${DEVICE})
    #Check for boot volume just in case root drive is passed here
    egrep "filesystem|boot" <<< "${OUTPUT}" > /dev/null 2>&1
    return ${?} # 0 if filesystem, 1 if not
}

do_partition() {
# This function creates one (1) primary partition on the
# disk, using all available space
    echo "Partitioning ${DISK}"
    DISK=${1}
    parted ${DISK} --script -- mklabel gpt
    parted -a opt ${DISK} mkpart primary ext4 0% 100% > /dev/null 2>&1
    echo "done with new partition"
}

get_next_mountpoint() {
    type=$1
    if [ $type = "ephemeral" ]
    then
	DATA_BASE="/ephemeral"
    else
	DATA_BASE="/mnt"
    fi
    
    DIRS=($(ls -1d ${DATA_BASE}/volume* 2>&1| sort --version-sort))
    if [ -z "${DIRS[0]}" ];
    then
        echo "${DATA_BASE}/volume1"
        return
    else
        IDX=$(echo "${DIRS[${#DIRS[@]}-1]}"|tr -d "[a-zA-Z/]" )
        IDX=$(( ${IDX} + 1 ))
        echo "${DATA_BASE}/volume${IDX}"
    fi
}



partitionAndMountDrive() {
# takes two arguments - the disk and then the type
   DISK=$1
   type=$2

   echo "Working on ${DISK}"
   if [ ${type} = "ephermeral" ]
   then
       echo "Drive ${DISK} is ephemeral. This means that if you use this drive your data will go away when you stop your instance. Do you want to use this drive? (y/n)"
       read response
       if [ $response != "y" ]
       then
	   return
       fi
       echo "ok, you asked for it"
   fi
   
   is_partitioned ${DISK}
   if [ ${?} -ne 0 ]; # not partitioned
   then
	# It is quite possible to have a disk be attached after creation
	# that does not have a partition but has a file system. Just to be
	# cautious, do not partition anything that has a file system.
        has_filesystem ${DISK}
        if [ ${?} -ne 0 ]; # no file system
        then
            echo "${DISK} is not partitioned and has no file system. Do you want to partition and create a file system? (y/n)"
	    read response
	    if [ $response != "y" ]
	    then
		return
	    fi
	    echo "ok, formatarama"
	    
            do_partition ${DISK}
            PARTITION=$(fdisk -l ${DISK}|grep -A 1 Device|tail -n 1|awk '{print $1}')
            echo "Creating filesystem on ${PARTITION}."
            mkfs -j -t ext4 ${PARTITION}
        
            MOUNTPOINT=$(get_next_mountpoint $type)
            echo "Next mount point appears to be ${MOUNTPOINT}"
            [ -d "${MOUNTPOINT}" ] || mkdir "${MOUNTPOINT}"
            read UUID FS_TYPE < <(blkid -u filesystem ${PARTITION}|awk -F "[= ]" '{print $3" "$5}'|tr -d "\"")
	    if [ $type != "ephemeral" ]
	       then
		   add_to_fstab "${UUID}" "${MOUNTPOINT}"
		   echo "Mounting disk ${PARTITION} on ${MOUNTPOINT}"
		   mount "${MOUNTPOINT}"
	    else
		echo "Remember that this drive is ephemeral. Everything you write to it will go away when you stop the machine. So this mount will go away when you do this again."
		mount ${PARTITION} "${MOUNTPOINT}"
	    fi

        else # disk is not partitioned but has a file system
            # partitioning it should not cause loss of data but let's not
            # instead check to see if it is in the fstab and if not, mount it
            echo ${DISK} is not partitioned but has a file system 
            read UUID FS_TYPE < <(blkid -u filesystem ${PARTITION}|awk -F "[= ]" '{print $3" "$5}'|tr -d "\"")
            grep ${UUID} /etc/fstab  > /dev/null 2>&1
            if [ ${?} -ne 0 ];
            then
                MOUNTPOINT=$(get_next_mountpoint $type)
                echo "Next mount point appears to be ${MOUNTPOINT}"
                [ -d "${MOUNTPOINT}" ] || mkdir "${MOUNTPOINT}"		
                echo "mounting ${DISK} on ${MOUNTPOINT}"
                mount ${DISK} ${MOUNTPOINT}
            fi
        fi
    fi
}




getUnmountedEmptyEBSDrives
getUnmountedEphemeralDrives
getUnmountedEBSDrivesAndPartitionsWithData


#for d in $drives
#do
#    partitionAndMountDrive $d ebs
#done
