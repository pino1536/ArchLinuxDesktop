#!/usr/bin/env bash
# 1.9 Partition the disks
for i in $(lsblk --nodeps --noheadings --include 8,259 --output NAME,SIZE);
do
    disks+=(${i})
done
disk=$(whiptail --title "Select Disk" --menu "Select disk device:" 25 50 11 "${disks[@]}" 3>&1 1>&2 2>&3)
read -p "test"
if (whiptail --title "Disk Partition" --yesno "Wipe Disk and default Partitions?" 25 50)
then
    (
    echo g
    echo n
    echo  
    echo  
    echo +512M
    echo t
    echo  
    echo 1
    echo w
    ) | fdisk --noauto-pt --wipe always --wipe-partitions always /dev/${disk}
    partitionefi=($(fdisk --list -o Device,Type /dev/${disk} | grep "EFI System"))
    mkfs.fat -F 32 ${partitionefi[0]}
fi
read -p "test"
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
read -p "test"
clear
fdisk --list /dev/${disk}
echo  
echo "Please enter the EFI Partition:"
read -p "/dev/" partitionefi
partitionswap=($(fdisk --list -o Device,Type /dev/${disk} | grep "Linux swap"))
partitionroot=($(fdisk --list -o Device,Type /dev/${disk} | grep "Linux root"))
read -p "test"
# 1.10 Format the partitions
mkswap ${partitionswap[0]}
mkfs.ext4 ${partitionroot[0]}
read -p "test"
# 1.11 Mount the file systems
mount ${partitionroot[0]} /mnt
mount --mkdir /dev/${partitionefi} /mnt/boot
swapon ${partitionswap[0]}
read -p "test"
# 2.1 Select the mirrors

# 2.2 Install essential packages
cpu=$(whiptail --title "GPU" --menu "Select CPU:" 25 50 11 "AMD" "" "Intel" "" 3>&1 1>&2 2>&3)
local microcode=""
case ${cpu} in
    "AMD") microcode="amd-ucode" ;;
    "Intel") microcode="intel-ucode" ;;
esac
pacstrap -K /mnt base linux linux-firmware networkmanager ${microcode}
read -p "test"
# 3.1 Configure the system
genfstab -U /mnt >> /mnt/etc/fstab
read -p "test"
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
read -p "test"
# 3.4 Localization
echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
keymap=$(whiptail --title "Choose Your Keyboard" --menu "Set the Keyboard Layout:" 25 50 11 "de" "German" "fr" "France" "ru" "Russia" "uk" "Unitet Kindom" "us" "USA" 3>&1 1>&2 2>&3)
echo "KEYMAP=${keymap}" > /mnt/etc/vconsole.conf
read -p "test"
# 3.5 Network configuration
echo linux > /mnt/etc/hostname
echo -ne "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\tlinux.localdomain linux" > /mnt/etc/hosts
arch-chroot /mnt systemctl enable NetworkManager.service
read -p "test"
# 3.6 Initramfs
read -p "test"
# 3.7 Root password
rootpw=$(whiptail --title "Set new root password" --passwordbox "Please set your new root password..." 25 50 3>&1 1>&2 2>&3)
echo -e "${rootpw}\n${rootpw}" | arch-chroot /mnt passwd
user=$(whiptail --title "Please provide sudo username" --inputbox "Please provide a sudo username: " 25 50 3>&1 1>&2 2>&3)
arch-chroot /mnt useradd -m -G wheel ${user}
userpw=$(whiptail --title "Getting user password" --passwordbox "Please enter your new user's password: " 25 50 3>&1 1>&2 2>&3)
echo -e "${userpw}\n${userpw}" | arch-chroot /mnt passwd ${user}
read -p "test"
