#!/usr/bin/env bash
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
            mount --mkdir /dev/${disk}1 /mnt/boot
            swapon /dev/${disk}2
            mount /dev/${disk}3 /mnt
        ;;
        "DualBoot")
        ;;
        "Custom")
            fdisk --wipe-partitions always /dev/${disk}
        ;;
    esac
    read -p "Debug: partition"
    reflector
    cpu=$(whiptail --title "GPU" --menu "Select CPU:" 25 50 11 "AMD" "" "Intel" "" 3>&1 1>&2 2>&3)
    local microcode=""
    case ${cpu} in
        "AMD") microcode="amd-ucode" ;;
        "Intel") microcode="intel-ucode" ;;
    esac
    pacstrap -K /mnt base linux linux-firmware grub efibootmgr networkmanager $microcode
    genfstab -U /mnt >> /mnt/etc/fstab
    nano /mnt/etc/fstab
    (
    local getsubzones=()
    local subzones=()
    zone=$(whiptail --title "Time Zone" --menu "Select continent:" 25 50 11 "Africa" "" "America" "" "Antarctica" "" "Asia" "" "Australia" "" "Europe" "" 3>&1 1>&2 2>&3)
    getsubzones=($(ls /usr/share/zoneinfo/$zone))
    for i in ${getsubzones[@]}; do
        subzones+=($i "")
    done
    subzone=$(whiptail --title "Time Zone" --menu "Select city:" 25 50 11 "${subzones[@]}" 3>&1 1>&2 2>&3)
    ln -sf /usr/share/zoneinfo/${zone}/${subzone} /etc/localtime
    hwclock --systohc
    keymap=$(whiptail --title "Choose Your Keyboard" --menu "Set the Keyboard Layout:" 25 50 11 "de" "German" "fr" "France" "ru" "Russia" "uk" "Unitet Kindom" "us" "USA" 3>&1 1>&2 2>&3)
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
    echo "KEYMAP=${keymap}" > /etc/vconsole.conf
    hostname=$(whiptail --title "Hostname" --inputbox "What is your new hostname?" 25 50 3>&1 1>&2 2>&3)
    echo ${hostname} > /mnt/etc/hostname
    echo -ne "127.0.0.1\tlocalhost\n::1\tlocalhost\n127.0.1.1\t${hostname}.localdomain\t${hostname}" > /mnt/etc/hosts
    systemctl enable NetworkManager
    rootpw=$(whiptail --title "Set new root password" --passwordbox "Please set your new root password..." 25 50 3>&1 1>&2 2>&3)
    echo -e "${rootpw}\n${rootpw}" | passwd
    user=$(whiptail --title "Please provide sudo username" --inputbox "Please provide a sudo username: " 25 50 3>&1 1>&2 2>&3)
    userpw=$(whiptail --title "Getting user password" --passwordbox "Please enter your new user's password: " 25 50 3>&1 1>&2 2>&3)
    useradd -m -G wheel "${user}"
    echo -e "${userpw}\n${userpw}" | passwd "${user}"
    read -p "Debug: GRUB"
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg
    ) | arch-chroot /mnt