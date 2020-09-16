# Get the live installation image  on a flash drive

# Plug flash drive into computer

# May need to disable "secure boot" in boot menu
# May need to install image as "dd" instead of "iso"
# (I needed to do that on my 3rd generation Lenovo X1 Carbon)

# Once it boots up, a couple things to note
# Press ALT + Right-Arrow to open another ttyl session
# Login with username: root; password: <blank>

# Use iwd to connect to wifi. The following command opens
# the interactive prompt.
> iwctl

# Type "help" into the prompt for help on the commands.
# For me, I did something like this
> device list
wlan0 # This is my wifi card I guess

> station wlan0 scan # Find available networks
> station wlan0 show # Display those networks
> station wlan0 connect "Sandy Llama"
> ****** # Prompted for password

# Should now be connected to the internet, and
# it should have that network saved to automatically
# connect in the future. Verify internet connection.
> ping 8.8.8.8
> ping archlinux.org

# If you want, you can now open another ttyl session
# and view the installation guide (or any other website)
> lynx google.com

# No need to adjust keyboard layout

# Verify that we are in the UEFI boot mode by checking
# if the efivars directory exists
> ls /sys/firmware/efi/efivars

# If it doesn't exist, reboot and look around in the boot
# menu for something that would indicate booting in
# UEFI mode. Keep trying until that efivars file exists

# Now comes the fun part of partitioning. We need a few
# special partitions, but a lot of this is up to you and
# your personal preference. I'll just describe what I did.

# End result:
> lsblk
 NAME               MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINT
sda                  8:0    0 238.5G  0 disk  
├─sda1               8:1    0   512M  0 part  /boot/efi
├─sda2               8:2    0   256M  0 part  /boot
└─sda3               8:3    0 237.7G  0 part  
  └─main-encrypted 254:0    0 237.7G  0 crypt 
    ├─arch-swap    254:1    0   512M  0 lvm   [SWAP]
    ├─arch-root    254:2    0    64G  0 lvm   /
    └─arch-home    254:3    0 173.2G  0 lvm   /home 

> gdisk /dev/sda
# This was created with gdisk. Use the help menu of gdisk
# to inform your decisions. Basically you just want to make
# your first partition your EFI partition (using the special
# EFI hex code EF00), then make one boot partition (hex code
# 8300) and one main partition for all the rest of your system.
# I chose to encrypt that main partition and split it into
# logical volumes.

# Use the following commands to create boot and efi filesystems
mkfs.vfat -F32 /dev/sda1 # efi must be FAT32
mkfs.ext4 /dev/sda2 # ext2 or btrfs could also work for boot

# Encrypt the main system partition
cryptsetup -c aes-xts-plain64 -h sha512 -s 512 luksFormat /dev/sda3

# Open the main system partition (now encrypted). Feel free to
# name it anything you want to.
cryptsetup luksOpen /dev/sda3 main-encrypted

# Create the logical volume (LVM) partitions
pvcreate /dev/mapper/main-encrypted
vgcreate arch /dev/mapper/main-encrypted # I made the vg name "arch"
lvcreate -L +512M arch -n swap # idk I guess I'll have swap
lvcreate -L +64G arch -n root # big ol root
lvcreate -L +100%FREE arch -n home # whatever is left for home

# Make swap actually swap
mkswap /dev/mapper/arch-swap

# Make root and home filesystems
mkfs.ext4 /dev/mapper/arch-root
mkfs.ext /dev/mapper/arch-home

# Mount the new system! If you come back in with the installation
# image later THESE ARE THE STEPS you'll need to repeat to get
# back into the machine's filesystem. (Obvs. exclude the mkdirs)

mount /dev/mapper/arch-root /mnt
swapon /dev/mapper/arch-swap

mkdir /mnt/boot
mount /dev/sda2 /mnt/boot

mkdir /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi

mkdir /mnt/home
mount /dev/sda3 /mnt/home

# You may want to edit the mirrorlist to get better package
# download speeds. Just put some physically close mirrors near
# the top.
vim /etc/pacman.d/mirrorlist

# Install the arch system to the mounted machine with packstrap
pacstrap /mnt base base-devel grub efibootmgr dialog iwd lvm2 linux linux-headers vim zsh linux-firmware

# Not sure if dhcpcd is also necessary -- theoretically iwd has it's own?

# Create the fstab
genfstab -U /mnt >> /mnt/etc/fstab # -U pulls in UUIDs for mounted filesystem
cat /mnt/etc/fstab # Check this over and modify if necessary (?)

# Enter the new system
arch-chroot /mnt /bin/bash

# Set system clock
ln -s /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc --utc

# Wifi is required following reboot (yes please)
systemctl enable iwd

# Give yourself a classy hostname
echo TheBestHostName > /etc/hostname

# Set locale.
# For English users like myself, do the following:
en_US.UTF-8 UTF-8 # **uncomment this line in /etc/locale.gen**
LANG=en_US.UTF-8 # **should be the only line in /etc/locale.conf**

# Generate the locale
locale-gen

# Set the root password. Do not forget this.
passwd

# Create a user and assign them to the wheel group because you can
# pretty easily give them root access.
useradd -m -G wheel -s /bin/bash TheBestUserName

passwd TheBestUserName

# Since we encrypted the hard drive we need the right hooks
# in mkinitcpio.
vim /etc/mkinitcpio.conf

# Make this the HOOKS statement. 'resume' is used when you have swap.
HOOKS=(base udev autodetect modconf block keymap encrypt lvm2 resume filesystems keyboard fsck)

# Generate the initrd image
mkinitcpio -p linux

# Install and configure Grub-EFI
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ArchLinux

# Edit /etc/default/grub so it has this statement (or something like it)
# If no swap, just leave out the remove statement.
GRUB_CMDLINE_LINUX="cryptdevice=/dev/sda3:main-encrypted resume=/dev/mapper/arch-swap"

# Generate final grub configuration
grub-mkconfig -o /boot/grub/grub.cfg

# Exit your machine's arch system (back out to installation image)
exit

# Unmount all partitions
umount -R /mnt
swapoff -a

# Reboot and pray
reboot

# -------------------------------------------------
# Nice you made it
# Now you can work on making all the things work
# -------------------------------------------------

# --------------------------------
# Audio
# --------------------------------

# I had trouble getting audio to work, and it ended up being something
# along the lines of the default card or device (or both) was wrong.
# Maybe it was defaulting to sending audio out through hdmi?

# Anways, I just had to make sure that the default card was the PCH
# View all playback hardware devices:
aplay -l

# in ~/.asoundrc
defaults.pcm.card 1
defaults.clt.card 1

# Set volume and stuff with alsamixer
alsamixer

# --------------------------------
# Internet
# --------------------------------

# Not sure why but I felt a bit like a purist or something so I didn't
# want a network manager but instead felt like iwd (which we used
# on the installation image) should be good enough for me. So. I tried
# to use that. Took a bit of configuration though.

# Seems like all that was necessary was making sure that the name resolution
# service had all the right Domain Name Services (DNS). For me,
# I just had to make sure that it included 1.1.1.1 (see etc/resolv.conf*)
1.1.1.1

