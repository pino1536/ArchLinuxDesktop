#!/usr/bin/env bash

# efi_boot_mode(){( $(ls /sys/firmware/efi/efivars &>/dev/null) && return 0 ) || return 1}

kde_desktop=( plasma plasma-wayland-session kde-applications plasma-workspace-wallpapers )
devel_stuff=( git nodejs npm npm-check-updates ruby )
printing_stuff=( system-config-printer foomatic-db foomatic-db-engine gutenprint cups cups-pdf cups-filters cups-pk-helper ghostscript gsfonts )
multimedia_stuff=( brasero sox eog shotwell imagemagick sox cmus mpg123 alsa-utils cheese )
all_extras=( "${kde_desktop[@]}" "${devel_stuff[@]}" "${printing_stuff[@]}" "${multimedia_stuff[@]}" )
all_pkgs=()

# Can't show checkmarks very easily...  This array will help show the user which tasks are completed or not
completed_tasks=( "X" )

keymap="-"
zone="-"
subzone="-"
hostname="-"
rootpw="-"
rootset="-"
user="-"
userpw="-"
cpu="-"
gpu="-"
disk="-"

prepare(){
    if $(ping -c 3 archlinux.org &>/dev/null); then
        networkconnection="Online"
    else
        networkconnection="Offline"
    fi
}

set_keymap(){
    keymap=$(whiptail --title "Choose Your Keyboard" --menu "Set the Keyboard Layout:" 25 50 20 "de" "German" "fr" "France" "ru" "Russia" "uk" "Unitet Kindom" "us" "USA" 3>&1 1>&2 2>&3)
    loadkeys $keymap
}

set_timezone(){
    local getsubzones=()
    local subzones=()
    zone=$(whiptail --title "Time Zone" --menu "Select continent:" 25 50 20 "Africa" "" "America" "" "Antarctica" "" "Asia" "" "Australia" "" "Europe" "" 3>&1 1>&2 2>&3)
    getsubzones=($(ls /usr/share/zoneinfo/$zone))
    for i in ${getsubzones[@]}; do
        subzones+=($i "")
    done
    subzone=$(whiptail --title "Time Zone" --menu "Select city:" 25 50 20 "${subzones[@]}" 3>&1 1>&2 2>&3)
}

set_hostname(){
    hostname=$(whiptail --title "Hostname" --inputbox "What is your new hostname?" 20 40 3>&1 1>&2 2>&3)
}

set_root(){
    rootpw=$(whiptail --title "Set new root password" --passwordbox "Please set your new root password..." 8 48 3>&1 1>&2 2>&3)
    rootset="Set"
}

set_user(){
    user=$(whiptail --title "Please provide sudo username" --inputbox "Please provide a sudo username: " 8 40 3>&1 1>&2 2>&3)
    userpw=$(whiptail --title "Getting user password" --passwordbox "Please enter your new user's password: " 8 78 3>&1 1>&2 2>&3)
}

set_cpu(){
    cpu=$(whiptail --title "GPU" --menu "Select CPU:" 25 50 20 "AMD" "" "Intel" "" 3>&1 1>&2 2>&3)
}

set_gpu(){
    gpu=$(whiptail --title "GPU" --menu "Select GPU:" 25 50 20 "AMD" "" "Nvidia" "" "Intel" "" 3>&1 1>&2 2>&3)
    # card=$(lspci | grep VGA | sed 's/^.*: //g')
}

set_disk(){
    local disks=()
    for i in $(lsblk /dev/hd* /dev/sd* /dev/nvme* --nodeps --scsi --noheadings --output NAME,SIZE); do
        disks+=(${i})
    done
    disk=$(whiptail --title "Select Disk" --menu "Select disk device:" 25 50 20 "${disks[@]}" 3>&1 1>&2 2>&3)
}
install_disk(){
    while true ; do
        menupick=$(whiptail --title "Disk Partition and Formating" --menu "Default Partition Layout: EFI (500mb), Swap (4gb), Root (?)" 25 50 10 \
            "Wipe All" "Wipe Disk and create default Partitions" \
            "Dualboot" "Use the existing Boot Partition" \
            "Manual" "The Command Line way." \
            "Cancel" "" 3>&1 1>&2 2>&3
        )
        case $menupick in
            "Wipe All") install_disk_wipe ;;
            "Dualboot") install_disk_dualboot ;;
            "Manual") install_disk_manual ;;
            "Cancel") menu ;;
        esac
    done
}
install_disk_wipe(){
    local rootsize=3
    (
        echo g
        echo n
        echo 1
        echo  
        echo +512M
        echo t
        echo 1
        echo n
        echo 2
        echo  
        echo +4048M
        echo t
        echo 2
        echo 19
        echo n
        echo 3
        echo  
        echo +${rootsize}G
        echo t
        echo 3
        echo 23
        echo w
    ) | fdisk /dev/$disk
    mkfs.fat -F 32 "/dev/${disk}1"
    mkswap "/dev/${disk}2"
    mkfs.ext4 "/dev/${disk}3"
    mount --mkdir /dev/${disk}1 /mnt/boot
    mount /dev/${disk}3 /mnt
    swapon /dev/${disk}2
    menu
}
install_base(){
    local microcode=""
    case $cpu in
        "AMD") microcode="amd-ucode" ;;
        "Intel") microcode="intel-ucode" ;;
    esac
    pacstrap -K /mnt base linux linux-firmware grub efibootmgr networkmanager $microcode
}
install_settings(){
    # 3.1 Fstab
    genfstab -U /mnt >> /mnt/etc/fstab

    # 3.2 Chroot
    arch-chroot /mnt

    # 3.3 Time zone
    ln -sf /usr/share/zoneinfo/$zone/$subzone /etc/localtime
    hwclock --systohc

    # 3.4 Localization
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "KEYMAP=$keymap" > /etc/vconsole.conf

    # 3.5 Network configuration
    echo "$hostname" > /mnt/etc/hostname
    echo -ne "127.0.0.1\tlocalhost\n::1\tlocalhost\n127.0.1.1\t$hostname.localdomain\t$hostname" > /mnt/etc/hosts
    systemctl enable NetworkManager

    # 3.7 Root password
    echo -e "$rootpw\n$rootpw" | passwd
    useradd -m -G wheel "$user"
    echo -e "$userpw\n$userpw" | passwd "$user"

    # 3.8 Boot loader
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
}
install_desktop(){
    # EXTRA PACKAGES, FONTS, THEMES, CURSORS
    arch-chroot /mnt pacman -S "${basic_x[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt pacman -S "${extra_x1[@]}" --noconfirm    &>>$LOGFILE
    arch-chroot /mnt pacman -S "${extra_x2[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt pacman -S "${extra_x3[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt pacman -S "${extra_x4[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt pacman -S "${devel_stuff[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt pacman -S "${printing_stuff[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt pacman -S "${multimedia_stuff[@]}" --noconfirm   &>>$LOGFILE

    # DRIVER FOR GRAPHICS CARD, DESKTOP, DISPLAY MGR
    arch-chroot /mnt pacman -S "${display_mgr[@]}" --noconfirm  &>>$LOGFILE 
    arch-chroot /mnt pacman -S "xf86-video-vmware" --noconfirm    &>>$LOGFILE 
    arch-chroot /mnt pacman -S "${kde_desktop[@]}" --noconfirm   &>>$LOGFILE
    arch-chroot /mnt systemctl enable "${display_mgr[@]}" &>>$LOGFILE 2>&1
    arch-chroot /mnt pacman -S "${all_extras[@]}" --noconfirm
}
menu(){
    local c="Keyboard Layout"
    while true ; do
        menupick=$(whiptail --title "Arch Linux Desktop Installer" --default-item "${c}" --menu "Install Settings:" 25 50 10 \
            "Keyboard Layout" "${keymap}" \
            "Time Zone" "${subzone}" \
            "Hostname" "${hostname}" \
            "Root Password" "${rootset}" \
            "User Account" "${user}" \
            "Network" "${networkconnection}" \
            "CPU" "${cpu}" \
            "GPU" "${gpu}" \
            "Disk" "${disk}" \
            "Next" "" \
            "Cancel                 " "" 3>&1 1>&2 2>&3
        )
        case $menupick in
            "Keyboard Layout") set_keymap; c="Keyboard Layout" ;;
            "Time Zone") set_timezone; c="Time Zone" ;;
            "Hostname") set_hostname; c="Hostname" ;;
            "Root Password") set_root; c="Root Password" ;;
            "User Account") set_user; c="User Account" ;;
            "Network") mc="Network" ;;
            "CPU") set_cpu; c="CPU" ;;
            "GPU") set_gpu; c="GPU" ;;
            "Disk") set_disk; c="Disk" ;;
            "Next") install_disk ;;
            "Cancel                 ") exit 0 ;;
        esac
    done
}

# "Install") specialprogressgauge install_general "Installing Xorg and Desktop Resources..." "INSTALLING XORG" ;;
####################################

find_card(){
    

    whiptail --title "Your Video Card" --msgbox \
       "You're using a $card  Write this down and hit OK to continue." 8 65 3>&1 1>&2 2>&3
}
showprogress(){
    start=$1; end=$2; shortest=$3; longest=$4

    for n in $(seq $start $end); do
        echo $n
        pause=$(shuf -i ${shortest:=1}-${longest:=3} -n 1)  # random wait between 1 and 3 seconds
        sleep $pause
    done
}
specialprogressgauge(){
    process_to_measure=$1   # This is the function we're going to measure progress for
    message=$2              # Message on Whiptail progress window
    backmessage=$3          # Message on Background Window
    eval $process_to_measure &      # Start the process in the background
    thepid=$!               # Immediately capture the PID for this process
    echo "=== Watching PID $thepid for progress ===" &>>$LOGFILE
    num=10                  # Shortest progress bar could be 10 sec to 30 sec
    while true; do
        showprogress 1 $num 1 3 
        sleep 2             # Max of 47 sec before we check for completion
        while $(ps aux | grep -v 'grep' | grep "$thepid" &>/dev/null); do
            if [[ $num -gt 97 ]] ; then num=$(( num-1 )); fi
            showprogress $num $((num+1)) 
            num=$(( num+1 ))
        done
        showprogress 99 100 3 3  # If we have completion, we add 6 sec. Max of 53 sec.
        echo "=== No longer watching PID: $thepid ===" &>>$LOGFILE
        break
    done  | whiptail --backtitle "$backmessage" --title "Progress Gauge" --gauge "$message" 9 70 0
}
check_tasks(){
    completed_tasks[$1]="X"
}
lvm_hooks(){
    sed -i 's/^HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)$/HOOKS=(base udev autodetect modconf block lvm2 filesystems keyboard fsck)/g' /mnt/etc/mkinitcpio.conf
    arch-chroot /mnt mkinitcpio -P 
}
encrypt_lvm_hooks(){
    sed -i 's/^HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)$/HOOKS=(base udev autodetect modconf block encrypt lvm2 filesystems keyboard fsck)/g' /mnt/etc/mkinitcpio.conf
    arch-chroot /mnt mkinitcpio -P 
}
lv_create(){
    # FOR LOGICAL VOLUME PARTITIONS
    # Choose your installation device
    disk=$(choose_disk)
    IN_DEVICE=/dev/"$disk"
    choices=()

    # Set up the partition choices for the install disk
    if [[ $disk =~ 'nvme' ]]; then
        choices+=( "${disk}p1" "${disk}p2" "${disk}p3" "${disk}p4" )
    else
        choices+=( "${disk}1" "${disk}2" "${disk}3" "${disk}4" )
    fi

    # Choose a partition for the root device
    root_dev=$(whiptail --title "Get Physical Volume Device" --radiolist \
    "What partition for your Physical Volume Group?  (sda2, nvme0n1p2, sdb2, etc)" 20 50 4 \
    "${choices[0]}" "" OFF \
    "${choices[1]}" "" ON \
    "${choices[2]}" "" OFF \
    "${choices[3]}" "" OFF 3>&1 1>&2 2>&3) 
    ROOT_DEVICE=/dev/"$root_dev"

    # get root partition or volume
    rootsize=$(whiptail --title "Get Size of Root Partition or Volume" --radiolist \
        "What size for your root partition? (15G, 50G, 100G, etc)" 20 50 4 \
        "15G" "" ON \
        "50G" "" OFF \
        "75G" "" OFF \
        "100G" "" OFF 3>&1 1>&2 2>&3)
    ROOT_SIZE="$rootsize"

    # get size of swap partition or volume
    swapsize=$(whiptail --title "Get Size of Swap Partition or Volume" --radiolist \
        "What size for your swap partition? (4G, 8G, 16G, etc)" 20 50 5 \
    "4G" "" ON \
    "8G" "" OFF \
    "16G" "" OFF \
    "32G" "" OFF \
    "64G" "" OFF 3>&1 1>&2 2>&3) 
    SWAP_SIZE="$swapsize"

    # Get EFI or BOOT partition?
    if $(efi_boot_mode); then

        efi_dev=$(whiptail --title "Get EFI Device" --radiolist \
            "What partition for your EFI Device?  (sda1 nvme0n1p1, sdb1, etc)" 20 50 4 \
            "${choices[0]}" "" ON \
            "${choices[1]}" "" OFF \
            "${choices[2]}" "" OFF \
            "${choices[3]}" "" OFF  3>&1 1>&2 2>&3) 

        # show an infobox while we wait for partitions
        TERM=ansi whiptail --backtitle "CREATING PARTITIONS" --title "Creating Your Partitions" --infobox "Please wait a moment while we create your partitions..." 8 40

        EFI_DEVICE=/dev/"$efi_dev"
        EFI_SIZE=512M   # This is a duplicate line

        # Create the physical partitions
        sgdisk -Z "$IN_DEVICE"                                    &>> $LOGFILE
        sgdisk -n 1::+"$EFI_SIZE" -t 1:ef00 -c 1:EFI "$IN_DEVICE" &>> $LOGFILE
        sgdisk -n 2 -t 2:8e00 -c 2:VOLGROUP "$IN_DEVICE"          &>> $LOGFILE

    else
        # get boot partition (we're using MBR with LVM here)
        boot_dev=$(whiptail --title "Get Boot Device" --radiolist \
            "What partition for your Boot Device? (sda1 nvme0n1p1, sdb1, etc)" 20 50 4 \
            "${choices[0]}" "" ON \
            "${choices[0]}" "" OFF \
            "${choices[0]}" "" OFF \
            "${choices[0]}" "" OFF  3>&1 1>&2 2>&3) 

        # show an infobox while we wait for partitions
        TERM=ansi whiptail --backtitle "CREATING PARTITIONS" --title "Creating Your Partitions" --infobox "Please wait a moment while we create your partitions..." 8 40

        BOOT_DEVICE=/dev/"$boot_dev"
        BOOT_SIZE=512M

        # The HERE document requires zero indentation:
        echo -ne "$BOOT_DEVICE : start= 2048, size=+$BOOT_SIZE, type=83, bootable\n$ROOT_DEVICE : type=83" > /tmp/sfdisk.cmd

        # Using sfdisk because we're talking MBR disktable now...
        sfdisk /dev/sda < /tmp/sfdisk.cmd   &>> $LOGFILE

        # format the boot partition
        format_disk "$BOOT_DEVICE" boot
    fi

    # run cryptsetup on root device  # uncomment this later
    [[ "$USE_CRYPT" == 'TRUE' ]] && crypt_setup "$ROOT_DEVICE"

    # run cryptsetup on root device  # uncomment this later
    if [[ "$USE_CRYPT" == 'TRUE' ]] ; then
        pvcreate /dev/mapper/"$CRYPT_PART"                 &>> $LOGFILE
    else
        # create the physical volumes
        pvcreate "$ROOT_DEVICE"                &>> $LOGFILE
    fi


    # Setup LV's one way for encryption, another way without
    # Note:  Haven't removed old comments because I'm still not sure new way will
    # work.  Keep both methods around until I verify them
    if [[ "$USE_CRYPT" == 'TRUE' ]] ; then
        # create vg on encrypted partition
        vgcreate "$VOL_GROUP" "$CRYPT_PART"   &>> $LOGFILE

        # You can extend with 'vgextend' to other devices too

        # create the volumes with specific size
        lvcreate -L "$ROOT_SIZE" "$CRYPT_PART" -n "$LV_ROOT"   &>> $LOGFILE
        #lvcreate -L "$ROOT_SIZE" "$VOL_GROUP" -n "$LV_ROOT"   &>> $LOGFILE
        lvcreate -L "$SWAP_SIZE" "$CRYPT_PART" -n "$LV_SWAP"   &>> $LOGFILE
        #lvcreate -L "$SWAP_SIZE" "$VOL_GROUP" -n "$LV_SWAP"   &>> $LOGFILE
        lvcreate -l 100%FREE  "$CRYPT_PART" -n "$LV_HOME"      &>> $LOGFILE
        #lvcreate -l 100%FREE  "$VOL_GROUP" -n "$LV_HOME"      &>> $LOGFILE
        
        # Format SWAP 
        format_disk /dev/"$CRYPT_PART"/"$LV_SWAP" swap
        # insert the vol group kernel module
        modprobe dm_mod                                       &>> $LOGFILE
        
        # activate the vol group
        vgchange -ay                                          &>> $LOGFILE

        ## format the volumes
        format_disk /dev/"$CRYPT_PART"/"$LV_ROOT"  root
        ## Format the EFI partition:  have to do this AFTER the 
        ## root partition or else it won't get mounted properly
        if $( efi_boot_mode ) ; then
            format_disk "$EFI_DEVICE" efi
        else
            format_disk "$BOOT_DEVICE" boot
        fi
            #[[ ! $(efi_boot_mode ) ]] && format_disk "$BOOT_DEVICE" boot 
            #[[ $(efi_boot_mode ) ]] && format_disk "$EFI_DEVICE" efi 
        format_disk /dev/"$CRYPT_PART"/"$LV_HOME"  home
    else
        # create the volume group
        vgcreate "$VOL_GROUP" "$ROOT_DEVICE"   &>> $LOGFILE
        # You can extend with 'vgextend' to other devices too

        # create the volumes with specific size
        lvcreate -L "$ROOT_SIZE" "$VOL_GROUP" -n "$LV_ROOT"   &>> $LOGFILE
        lvcreate -L "$SWAP_SIZE" "$VOL_GROUP" -n "$LV_SWAP"   &>> $LOGFILE
        lvcreate -l 100%FREE  "$VOL_GROUP" -n "$LV_HOME"      &>> $LOGFILE
        
        # Format SWAP 
        format_disk "/dev/$VOL_GROUP/$LV_SWAP" swap
    
        # insert the vol group kernel module
        modprobe dm_mod                                       &>> $LOGFILE
        
        # activate the vol group
        vgchange -ay                                          &>> $LOGFILE

        ## format the volumes
        format_disk "/dev/$VOL_GROUP/$LV_ROOT"  root
        ## Format the EFI partition:  have to do this AFTER the 
        ## root partition or else it won't get mounted properly
        if $( efi_boot_mode ); then
            format_disk "$EFI_DEVICE" efi
        else
            format_disk "$BOOT_DEVICE" boot
            #[[ ! $(efi_boot_mode ) ]] && format_disk "$BOOT_DEVICE" boot 
            #[[ $(efi_boot_mode ) ]] && format_disk "$EFI_DEVICE" efi 
        fi
        format_disk "/dev/$VOL_GROUP/$LV_HOME"  home
    fi
    
    # examine our work here
    lsblk > /tmp/filesystems_created
    whiptail --title "LV's Created and Mounted" --backtitle "Filesystem Created" \
        --textbox /tmp/filesystems_created 30 70
    sleep 4
    Menu
}
mount_part(){
    # Mount the device ($1) and the mount point ($2)
    # 2nd parameter is mount point
    device=$1; mt_pt=$2

    # both efi and non-efi systems need /mnt/boot
    [[ ! -d /mnt/boot ]] && mkdir /mnt/boot &>> $LOGFILE

    # only efi systems need /mnt/boot/efi
    $(efi_boot_mode) && ! [ -d /mnt/boot/efi ] && mkdir /mnt/boot/efi &>> $LOGFILE

    # if mt_pt doesn't exist, create it if possible
    [[ ! -d "$mt_pt" ]] && mkdir "$mt_pt"   &>>$LOGFILE
    
    # Do the deed (Mount it!)  Don't forget the logfile
    mount "$device" "$mt_pt" 2>&1  &>>$LOGFILE

    # Check if we've succeeded or not
    if [[ "$?" -eq 0 ]]; then
        echo "====== $device mounted successfully on $mt_pt ======" &>>$LOGFILE
    else

        TERM=ansi whiptail --title "Mount NOT successful" \
            --msgbox "$device failed mounting on $mt_pt" 8 65
        echo "!!!### ===== $device failed mounting on $mt_pt ===== ###!!!"
    fi
    return 0
}

crypt_setup(){
    # Takes a disk partition as an argument
    # Give msg to user about purpose of encrypted physical volume
    message="You are about to encrypt a physical volume.  Your data will be stored in an encrypted state when powered off.  Your files will only be protected while the system is powered off.  This could be very useful if your laptop gets stolen, for example. Hit OK to continue."

    back_message="ENCRYPTING PARTITION WITH LUKS"
    title_message="Encrypting Paritition"

    whiptail --backtitle "$back_message" --title "$title_message" --msgbox "$message" 15 80

    #read -p "Encrypting a disk partition. Please enter a memorable passphrase: " -s passphrase
    passphrase=$( whiptail --backtitle "$back_message" --title "$title_message" --passwordbox \
        "Please enter a memorable passphrase: " 12 80 3>&1 1>&2 2>&3 )

    echo "$passphrase" > /tmp/passphrase

    #echo -n "$passphrase" | cryptsetup -q luksFormat $1 -   2>&1 &>>$LOGFILE
    cryptsetup -y -v luksFormat $1 --key-file /tmp/passphrase   2>&1 &>>$LOGFILE
    #echo -n "$passphrase" | cryptsetup -q luksFormat --hash=sha512 --key-size=512 --cipher=aes-xts-plain64 --verify-passphrase $1 -  2>&1 &>>$LOGFILE

    cryptsetup luksOpen  $1 $CRYPT_PART   2>&1 &>>$LOGFILE      

    cryptsetup -v status $CRYPT_PART    2>&1 &>>$LOGFILE

    term=ANSI whiptail --backtitle "$back_message" --title "$title_message" --infobox "Wiping every byte of device with zeroes, could take a while..." 24 80

    ## Shouldn't be using mapper at this point!!!
    dd if=/dev/zero of=/dev/mapper/"$CRYPT_PART" bs=1M    2>&1  &>>$LOGFILE
    cryptsetup luksClose "$CRYPT_PART"                    2>&1  &>>$LOGFILE
    
    term=ANSI whiptail --backtitle "$back_message" --title "$title_message" --infobox "Filling header of device with random data..." 24 80
    dd if=/dev/urandom of="$1" bs=512 count=20480     2>&1  &>>$LOGFILE
}

menu

