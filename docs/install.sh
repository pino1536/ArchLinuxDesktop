#!/usr/bin/env bash
    whiptail --backtitle "Dave's ARCH Installer (DARCHI)" --title "Welcome to DARCHI!" --msgbox "This Installer will lead you through the default command line installation to install Arch Linux with KDE Plasma." 15 80
    
    # 1.9 Partition the disks
    # 1.10 Format the partitions
    # 1.11 Mount the file systems
    local disks=()
    for i in $(lsblk /dev/hd* /dev/sd* /dev/nvme* --nodeps --scsi --noheadings --output NAME,SIZE); do
        disks+=(${i})
    done
    disk=$(whiptail --title "Select Disk" --menu "Select disk device:" 25 50 11 "${disks[@]}" 3>&1 1>&2 2>&3)
    partitiontype=$(whiptail --title "Disk Partition and Formating" --menu "Default Partition Layout:\nEFI (500mb), Swap (4gb), Root (?)" 25 50 11 "FullWipe" "Wipe Disk, default Partitions" "DualBoot" "Use the existing Boot Partition" "Custom" "The Command Line way." 3>&1 1>&2 2>&3)
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
            ) | fdisk -w always -W always /dev/${disk}
            mkfs.fat -F 32 "/dev/${disk}1"
            mkswap "/dev/${disk}2"
            mkfs.ext4 "/dev/${disk}3"
            mount /dev/${disk}3 /mnt
            mount --mkdir /dev/${disk}1 /mnt/boot
            swapon /dev/${disk}2
        ;;
        "DualBoot")
        ;;
        "Custom")
            fdisk --wipe-partitions always /dev/${disk}
        ;;
    esac

    # 2.1 Select the mirrors
    reflector

    # 2.2 Install essential packages
    cpu=$(whiptail --title "GPU" --menu "Select CPU:" 25 50 11 "AMD" "" "Intel" "" 3>&1 1>&2 2>&3)
    local microcode=""
    case ${cpu} in
        "AMD") microcode="amd-ucode" ;;
        "Intel") microcode="intel-ucode" ;;
    esac
    pacstrap -K /mnt base linux linux-firmware grub efibootmgr networkmanager $microcode
    
    # 3.1 Configure the system
    genfstab -U /mnt >> /mnt/etc/fstab

    # 3.3 Time zone
    local getsubzones=()
    local subzones=()
    zone=$(whiptail --title "Time Zone" --menu "Select continent:" 25 50 11 "Africa" "" "America" "" "Antarctica" "" "Asia" "" "Australia" "" "Europe" "" 3>&1 1>&2 2>&3)
    getsubzones=($(ls /mnt/usr/share/zoneinfo/${zone}))
    for i in ${getsubzones[@]}; do
        subzones+=($i "")
    done
    subzone=$(whiptail --title "Time Zone" --menu "Select city:" 25 50 11 "${subzones[@]}" 3>&1 1>&2 2>&3)
    ln -sf mnt/usr/share/zoneinfo/${zone}/${subzone} mnt/etc/localtime
    arch-chroot /mnt hwclock --systohc

    # 3.4 Localization
    keymap=$(whiptail --title "Choose Your Keyboard" --menu "Set the Keyboard Layout:" 25 50 11 "de" "German" "fr" "France" "ru" "Russia" "uk" "Unitet Kindom" "us" "USA" 3>&1 1>&2 2>&3)
    echo "en_US.UTF-8 UTF-8" > mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
    echo "KEYMAP=${keymap}" > /mnt/etc/vconsole.conf

    # 3.5 Network configuration
    hostname=$(whiptail --title "Hostname" --inputbox "What is your new hostname?" 25 50 3>&1 1>&2 2>&3)
    echo ${hostname} > /mnt/etc/hostname
    echo -ne "127.0.0.1\tlocalhost\n::1\tlocalhost\n127.0.1.1\t${hostname}.localdomain\t${hostname}" > /mnt/etc/hosts
    arch-chroot /mnt systemctl enable NetworkManager

    # 3.6 Initramfs

    # 3.7 Root password
    rootpw=$(whiptail --title "Set new root password" --passwordbox "Please set your new root password..." 25 50 3>&1 1>&2 2>&3)
    arch-chroot /mnt "echo -e "${rootpw}\n${rootpw}" | passwd"
    user=$(whiptail --title "Please provide sudo username" --inputbox "Please provide a sudo username: " 25 50 3>&1 1>&2 2>&3)
    userpw=$(whiptail --title "Getting user password" --passwordbox "Please enter your new user's password: " 25 50 3>&1 1>&2 2>&3)
    arch-chroot /mnt useradd -m -G wheel ${user}
    arch-chroot /mnt "echo -e "${userpw}\n${userpw}" | passwd ${user}"

    # 3.8 Boot loader
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg