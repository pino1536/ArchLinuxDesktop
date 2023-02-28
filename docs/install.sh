#!/usr/bin/env bash
# 1.9 Partition the disks
disks=()
partitions=()
for i in $(lsblk /dev/hd* /dev/sd* /dev/nvme* --nodeps --scsi --noheadings --output NAME,SIZE);
do
    disks+=(${i})
done
disk=$(whiptail --title "Select Disk" --menu "Select disk device:" 25 50 11 "${disks[@]}" 3>&1 1>&2 2>&3)
fdisk --wipe-partitions always /dev/${disk}

if (whiptail --title "Disk Partition" --yesno "Wipe Disk?" 25 50)
then
    (
    echo g
    echo w
    ) | fdisk --wipe always --wipe-partitions always /dev/${disk}
fi

if (whiptail --title "Disk Partition" --yesno "Create EFI Boot Partition?" 25 50)
then
    (
    echo n
    echo  
    echo  
    echo +512M
    echo t
    echo  
    echo 1
    echo w
    ) | fdisk --wipe always --wipe-partitions always /dev/${disk}
    partitionefi=($(fdisk /dev/${disk} --list -p Device,Type | grep "EFI System"))
    read -p "${partitionefi[1]}"
    mkfs.fat -F 32 ${partitionefi[1]}
fi
read -p "debug"
(
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
) | fdisk --wipe-partitions always /dev/${disk}

partitionefi=($(fdisk /dev/${disk} --list -p Device,Type | grep "EFI System"))
partitionswap=($(fdisk /dev/${disk} --list -p Device,Type | grep "Linux swap"))
partitionroot=($(fdisk /dev/${disk} --list -p Device,Type | grep "Linux root"))
read -p "${partitionefi[1]}"
read -p "${partitionswap[1]}"
read -p "${partitionroot[1]}"

# 1.10 Format the partitions
mkswap ${partitionswap[1]}
mkfs.ext4 ${partitionroot[1]}

# 1.11 Mount the file systems
mount ${partitionroot[1]} /mnt
mount --mkdir ${partitionefi[1]} /mnt/boot
swapon ${partitionswap[1]}

# 2.1 Select the mirrors
reflector --latest 20 --protocol https --save /etc/pacman.d/mirrorlist

# 2.2 Install essential packages
cpu=$(whiptail --title "GPU" --menu "Select CPU:" 25 50 11 "AMD" "" "Intel" "" 3>&1 1>&2 2>&3)
local microcode=""
case ${cpu} in
    "AMD") microcode="amd-ucode" ;;
    "Intel") microcode="intel-ucode" ;;
esac

pacstrap -K /mnt base linux linux-firmware grub efibootmgr networkmanager ${microcode}

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
ln -sf /mnt/usr/share/zoneinfo/${zone}/${subzone} /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc

# 3.4 Localization
echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
keymap=$(whiptail --title "Choose Your Keyboard" --menu "Set the Keyboard Layout:" 25 50 11 "de" "German" "fr" "France" "ru" "Russia" "uk" "Unitet Kindom" "us" "USA" 3>&1 1>&2 2>&3)
echo "KEYMAP=${keymap}" > /mnt/etc/vconsole.conf

# 3.5 Network configuration
hostname=$(whiptail --title "Hostname" --inputbox "What is your new hostname?" 25 50 3>&1 1>&2 2>&3)
echo ${hostname} > /mnt/etc/hostname
echo -ne "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t${hostname}.localdomain ${hostname}" > /mnt/etc/hosts
arch-chroot /mnt systemctl enable NetworkManager.service

# 3.6 Initramfs

# 3.7 Root password
rootpw=$(whiptail --title "Set new root password" --passwordbox "Please set your new root password..." 25 50 3>&1 1>&2 2>&3)
echo -e "${rootpw}\n${rootpw}" | arch-chroot /mnt passwd
user=$(whiptail --title "Please provide sudo username" --inputbox "Please provide a sudo username: " 25 50 3>&1 1>&2 2>&3)
arch-chroot /mnt useradd -m -G wheel ${user}
userpw=$(whiptail --title "Getting user password" --passwordbox "Please enter your new user's password: " 25 50 3>&1 1>&2 2>&3)
echo -e "${userpw}\n${userpw}" | arch-chroot /mnt passwd ${user}

# 3.8 Boot loader
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=boot --bootloader-id=GRUB
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg