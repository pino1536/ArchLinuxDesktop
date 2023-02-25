#!/usr/bin/env bash

kde_desktop=( plasma plasma-wayland-session kde-applications plasma-workspace-wallpapers )
devel_stuff=( git nodejs npm npm-check-updates ruby )
printing_stuff=( system-config-printer foomatic-db foomatic-db-engine gutenprint cups cups-pdf cups-filters cups-pk-helper ghostscript gsfonts )
multimedia_stuff=( brasero sox eog shotwell imagemagick sox cmus mpg123 alsa-utils cheese )
all_extras=( "${kde_desktop[@]}" "${devel_stuff[@]}" "${printing_stuff[@]}" "${multimedia_stuff[@]}" )

network="-"
set_network(){
    if $(ping -c 1 archlinux.org &>/dev/null); then
        network="Online"
    else
        network="Offline"
    fi
}

disk="-"
set_disk(){
    local disks=()
    for i in $(lsblk /dev/hd* /dev/sd* /dev/nvme* --nodeps --scsi --noheadings --output NAME,SIZE); do
        disks+=(${i})
    done
    disk=$(whiptail --title "Select Disk" --menu "Select disk device:" 25 50 11 "${disks[@]}" 3>&1 1>&2 2>&3)
}

partitiontype="-"
set_partitiontype(){
    partitiontype=$(whiptail --title "Disk Partition and Formating" --menu "Default Partition Layout:\nEFI (500mb), Swap (4gb), Root (?)" 25 50 11 \
        "FullWipe" "Wipe Disk, default Partitions" \
        "DualBoot" "Use the existing Boot Partition" \
        "Custom" "The Command Line way." 3>&1 1>&2 2>&3
    )
}

cpu="-"
set_cpu(){
    cpu=$(whiptail --title "GPU" --menu "Select CPU:" 25 50 11 "AMD" "" "Intel" "" 3>&1 1>&2 2>&3)
}

zone="-"
subzone="-"
set_timezone(){
    local getsubzones=()
    local subzones=()
    zone=$(whiptail --title "Time Zone" --menu "Select continent:" 25 50 11 "Africa" "" "America" "" "Antarctica" "" "Asia" "" "Australia" "" "Europe" "" 3>&1 1>&2 2>&3)
    getsubzones=($(ls /usr/share/zoneinfo/$zone))
    for i in ${getsubzones[@]}; do
        subzones+=($i "")
    done
    subzone=$(whiptail --title "Time Zone" --menu "Select city:" 25 50 11 "${subzones[@]}" 3>&1 1>&2 2>&3)
}

keymap="-"
set_keymap(){
    keymap=$(whiptail --title "Choose Your Keyboard" --menu "Set the Keyboard Layout:" 25 50 11 "de" "German" "fr" "France" "ru" "Russia" "uk" "Unitet Kindom" "us" "USA" 3>&1 1>&2 2>&3)
}

hostname="-"
set_hostname(){
    hostname=$(whiptail --title "Hostname" --inputbox "What is your new hostname?" 25 50 3>&1 1>&2 2>&3)
}

rootpw="-"
set_root(){
    rootpw=$(whiptail --title "Set new root password" --passwordbox "Please set your new root password..." 25 50 3>&1 1>&2 2>&3)
}

user="-"
userpw="-"
set_user(){
    user=$(whiptail --title "Please provide sudo username" --inputbox "Please provide a sudo username: " 25 50 3>&1 1>&2 2>&3)
    userpw=$(whiptail --title "Getting user password" --passwordbox "Please enter your new user's password: " 25 50 3>&1 1>&2 2>&3)
}

gpu="-"
set_gpu(){
    gpu=$(whiptail --title "GPU" --menu "Select GPU:" 25 50 11 "AMD" "" "Nvidia" "" "Intel" "" 3>&1 1>&2 2>&3)
    # card=$(lspci | grep VGA | sed 's/^.*: //g')
}

ald_preinstall(){
    # 1.9 Partition the disks
    set_disk
    set_partitiontype
    case ${partitiontype} in
        "FullWipe")
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
                echo  
                echo t
                echo 3
                echo 23
                echo w
            ) | fdisk --wipe-partitions always /dev/${disk}
            # 1.10 Format the partitions
            mkfs.fat -F 32 "/dev/${disk}1"
            mkswap "/dev/${disk}2"
            mkfs.ext4 "/dev/${disk}3"

            # 1.11 Mount the file systems
            mount --mkdir /dev/${disk}1 /mnt/boot
            swapon /dev/${disk}2
            mount /dev/${disk}3 /mnt
        ;;
        "DualBoot")
            # later
        ;;
        "Custom")
            fdisk --wipe-partitions always /dev/${disk}
        ;;
    esac
}

ald_install(){
    # 2.1 Select the mirrors
    reflector

    # 2.2 Install essential packages
    set_cpu
    local microcode=""
    case ${cpu} in
        "AMD") microcode="amd-ucode" ;;
        "Intel") microcode="intel-ucode" ;;
    esac
    pacstrap -K /mnt base linux linux-firmware grub efibootmgr networkmanager $microcode
}

ald_config(){
    # 3.1 Fstab
    genfstab -U /mnt >> /mnt/etc/fstab

    # 3.2 Chroot
    arch-chroot /mnt

    # 3.3 Time zone
    set_timezone
    ln -sf /usr/share/zoneinfo/${zone}/${subzone} /etc/localtime
    hwclock --systohc

    # 3.4 Localization
    set_keymap
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "KEYMAP=${keymap}" > /etc/vconsole.conf

    # 3.5 Network configuration
    set_hostname
    echo ${hostname} > /mnt/etc/hostname
    echo -ne "127.0.0.1\tlocalhost\n::1\tlocalhost\n127.0.1.1\t${hostname}.localdomain\t${hostname}" > /mnt/etc/hosts
    systemctl enable NetworkManager

    # 3.6 Initramfs
    # not needed

    # 3.7 Root password
    set_root
    echo -e "${rootpw}\n${rootpw}" | passwd
    set_user
    useradd -m -G wheel "${user}"
    echo -e "${userpw}\n${userpw}" | passwd "${user}"

    # 3.8 Boot loader
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
}
ald_desktop(){
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

ald_preinstall
ald_install
ald_config
# ald_desktop
