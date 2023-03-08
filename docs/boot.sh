# 3.8 Boot loader
partitionroot=($(fdisk --list -o Device,Type /dev/${disk} | grep "Linux root"))
read -p "test"
arch-chroot /mnt bootctl install
read -p "test"
echo -ne "title\tArch Linux\nlinux\t/vmlinuz-linux\ninitrd\t/${microcode}.img\ninitrd\t/initramfs-linux.img\noptions\troot=${partitionroot[0]} rw" > /mnt/boot/loader/entries/arch.conf
read -p "test"