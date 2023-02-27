#!/usr/bin/env bash
    # 1.9 Partition the disks
    local disks=()
    for i in $(lsblk /dev/hd* /dev/sd* /dev/nvme* --nodeps --scsi --noheadings --output NAME,SIZE); do
        disks+=(${i})
    done
    disk=$(whiptail --title "Select Disk" --menu "Select disk device:" 25 50 11 "${disks[@]}" 3>&1 1>&2 2>&3)
    read -p "${disk}"
    partitiontype=$(whiptail --title "Disk Partition and Formating" --menu "Default Partition Layout:\nEFI (500mb), Swap (4gb), Root (?)" 25 50 11 "FullWipe" "Wipe Disk, default Partitions" "DualBoot" "Use the existing Boot Partition" "Custom" "The Command Line way." 3>&1 1>&2 2>&3)
    read -p "${partitiontype}"
    case ${partitiontype} in
        "FullWipe")
            (
                echo g
                echo n
                echo  
                echo  
                echo +512M
                echo t
                echo  
                echo 1
                echo n
                echo  
                echo  
                echo +4048M
                echo t
                echo  
                echo 19
                echo n
                echo  
                echo  
                echo  
                echo t
                echo  
                echo 23
                echo w
            ) | fdisk -w always -W always /dev/${disk}
            read -p "debug"
            # 1.10 Format the partitions
            mkfs.fat -F 32 /dev/${disk}1
            mkswap /dev/${disk}2
            mkfs.ext4 /dev/${disk}3
            read -p "debug"
            # 1.11 Mount the file systems
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
    read -p "debug"
    # 2.1 Select the mirrors
    reflector --latest 20 --protocol https --save /etc/pacman.d/mirrorlist
    read -p "debug"
    # 2.2 Install essential packages
    cpu=$(whiptail --title "GPU" --menu "Select CPU:" 25 50 11 "AMD" "" "Intel" "" 3>&1 1>&2 2>&3)
    local microcode=""
    case ${cpu} in
        "AMD") microcode="amd-ucode" ;;
        "Intel") microcode="intel-ucode" ;;
    esac
    read -p "${microcode}"
    pacstrap -K /mnt base linux linux-firmware grub efibootmgr networkmanager ${microcode}
    read -p "debug"
    # 3.1 Configure the system
    genfstab -U /mnt >> /mnt/etc/fstab
    read -p "debug"
    # 3.3 Time zone
    local getsubzones=()
    local subzones=()
    zone=$(whiptail --title "Time Zone" --menu "Select continent:" 25 50 11 "Africa" "" "America" "" "Antarctica" "" "Asia" "" "Australia" "" "Europe" "" 3>&1 1>&2 2>&3)
    getsubzones=($(ls /mnt/usr/share/zoneinfo/${zone}))
    for i in ${getsubzones[@]}; do
        subzones+=($i "")
    done
    subzone=$(whiptail --title "Time Zone" --menu "Select city:" 25 50 11 "${subzones[@]}" 3>&1 1>&2 2>&3)
    ln -sf /mnt/usr/share/zoneinfo/${zone}/${subzone} /mnt/etc/localtime
    arch-chroot /mnt hwclock --systohc
    read -p "debug"
    # 3.4 Localization
    echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
    keymap=$(whiptail --title "Choose Your Keyboard" --menu "Set the Keyboard Layout:" 25 50 11 "de" "German" "fr" "France" "ru" "Russia" "uk" "Unitet Kindom" "us" "USA" 3>&1 1>&2 2>&3)
    echo "KEYMAP=${keymap}" > /mnt/etc/vconsole.conf
    read -p "debug"
    # 3.5 Network configuration
    hostname=$(whiptail --title "Hostname" --inputbox "What is your new hostname?" 25 50 3>&1 1>&2 2>&3)
    echo ${hostname} > /mnt/etc/hostname
    echo -ne "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t${hostname}.localdomain ${hostname}" > /mnt/etc/hosts
    arch-chroot /mnt systemctl enable NetworkManager.service
    read -p "press Enter"
    # 3.6 Initramfs
    read -p "debug"
    # 3.7 Root password
    rootpw=$(whiptail --title "Set new root password" --passwordbox "Please set your new root password..." 25 50 3>&1 1>&2 2>&3)
    echo -e "${rootpw}\n${rootpw}" | arch-chroot /mnt passwd
    user=$(whiptail --title "Please provide sudo username" --inputbox "Please provide a sudo username: " 25 50 3>&1 1>&2 2>&3)
    arch-chroot /mnt useradd -m -G wheel ${user}
    userpw=$(whiptail --title "Getting user password" --passwordbox "Please enter your new user's password: " 25 50 3>&1 1>&2 2>&3)
    echo -e "${userpw}\n${userpw}" | arch-chroot /mnt passwd ${user}
    read -p "debug"
    # 3.8 Boot loader
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=boot --bootloader-id=GRUB
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    read -p "debug"