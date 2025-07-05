#!/bin/bash

# arch-secure-install.sh
#
# This script automates the installation of Arch Linux with:
# - LUKS full disk encryption
# - Btrfs filesystem with subvolumes (@, @home, @snapshots, @var_log, @tmp, @swap)
# - Snapper for Btrfs snapshots
# - systemd-boot as the bootloader
# - Secure Boot enabled with sbctl, including automatic kernel signing via a pacman hook.
#
# WARNING: This script is highly destructive and will erase all data on the target disk.
#          Use with extreme caution and ensure you have backed up any important data.
#
# Usage: Run from the Arch Linux live environment as root:
#        curl -L your_github_repo_url/arch-secure-install.sh | bash
#        (Or download and run locally: bash arch-secure-install.sh)

# --- Script setup ---
# Exit on any error, treat unset variables as an error, and prevent errors in a pipeline from being masked.
set -euo pipefail

# --- Logging Setup ---
# All output will be logged to /tmp/arch_install.log
LOG_FILE="/tmp/arch_install.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

# --- Cleanup on Exit ---
cleanup() {
    echo "Cleaning up..."
    umount -R /mnt &>/dev/null || true
    cryptsetup close cryptroot &>/dev/null || true
}
trap cleanup EXIT


# --- Configuration Variables ---
# Recommended sizes. Adjust as needed.
ESP_SIZE="512M" # EFI System Partition size
BOOT_SIZE="1G"  # Boot partition size (for kernel/initramfs outside LUKS)
SWAPFILE_SIZE="4G" # Swap file size within Btrfs (adjust based on RAM)

# Btrfs mount options (adjust as per your SSD/HDD and compression preference)
# 'ssd' for SSDs, 'noatime' for performance, 'compress=zstd' for good compression
BTRFS_MOUNT_OPTS="defaults,noatime,compress=zstd:3"
BTRFS_SWAP_OPTS="defaults,noatime" # Swap subvolume should not be compressed

# --- Global Variables for User Input ---
KERNEL_PACKAGE="" # This will be set by the select_kernel function
KERNEL_NAME=""    # e.g., 'linux', 'linux-lts', 'linux-zen'
HOSTNAME=""       # Will be set by get_user_details
USERNAME=""       # Will be set by get_user_details
SUDO_ACCESS=""    # Will be set by get_user_details (yes/no)
KEYMAP=""         # Will be set by select_keyboard_layout
LOCALE=""         # Will be set by select_locale_options
TIMEZONE=""       # Will be set by select_locale_options
LUKS_UUID=""      # Will be set during LUKS setup

# --- Functions ---

print_header() {
    echo -e "\n================================================================="
    echo -e "  Arch Linux Secure Installation Script"
    echo -e "=================================================================\n"
}

confirm_action() {
    local prompt_message="$1"
    read -p "$prompt_message (y/N): " response
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
    if [[ "$response" != "y" ]]; then
        echo "Action aborted. Exiting script."
        exit 1
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root."
        exit 1
    fi
}

check_uefi() {
    if [ ! -d /sys/firmware/efi/efivars ]; then
        echo "This system is not booted in UEFI mode. Secure Boot requires UEFI."
        echo "Please boot the Arch Linux ISO in UEFI mode."
        exit 1
    fi
    echo "UEFI mode detected."
}

set_up_internet() {
    echo "Setting up internet connection..."
    # Check for internet connectivity
    ping -c 1 archlinux.org &>/dev/null
    if [ $? -ne 0 ]; then
        echo "No internet connection detected. Please ensure you are connected."
        echo "For Wi-Fi, use 'iwctl' or 'wifi-menu'. For wired, 'dhcpcd' might be needed."
        read -p "Press Enter to continue after establishing connection, or Ctrl+C to exit."
        ping -c 1 archlinux.org &>/dev/null
        if [ $? -ne 0 ]; then
            echo "Internet still not available. Exiting."
            exit 1
        fi
    fi
    timedatectl set-ntp true
    echo "Internet connection and NTP sync verified."
}

select_disk() {
    lsblk -f
    echo -e "\n"
    read -p "Enter the target disk (e.g., /dev/sda, /dev/nvme0n1): " TARGET_DISK
    if [[ ! -b "$TARGET_DISK" ]]; then
        echo "Invalid disk: $TARGET_DISK. Exiting."
        exit 1
    fi
    echo "Selected disk: $TARGET_DISK"
    read -p "WARNING: All data on $TARGET_DISK will be erased. Type 'YES' to confirm: " CONFIRM_ERASE
    if [[ "$CONFIRM_ERASE" != "YES" ]]; then
        echo "Aborting installation."
        exit 1
    fi
}

select_kernel() {
    while true; do
        echo -e "\nSelect the kernel package to install:"
        echo "1) linux (mainline kernel)"
        echo "2) linux-lts (Long Term Support kernel)"
        echo "3) linux-zen (Zen kernel)"
        read -p "Enter your choice (1, 2, or 3): " KERNEL_CHOICE

        case "$KERNEL_CHOICE" in
            1)
                KERNEL_PACKAGE="linux"
                KERNEL_NAME="linux"
                break
                ;;
            2)
                KERNEL_PACKAGE="linux-lts"
                KERNEL_NAME="linux-lts"
                break
                ;;
            3)
                KERNEL_PACKAGE="linux-zen"
                KERNEL_NAME="linux-zen"
                break
                ;;
            *)
                echo "Invalid choice. Please select 1, 2, or 3."
                ;;
        esac
    done
    echo "Selected kernel: $KERNEL_PACKAGE"
}

select_keyboard_layout() {
    while true; do
        echo -e "
--- Keyboard Layout Selection ---"
        echo "Common layouts: us, de, fr, gb, es, it, jp, ru"
        echo "You can list all available keymaps with 'localectl list-keymaps'."
        read -p "Enter your desired keyboard layout (e.g., us): " KEYMAP
        if [[ -n "$KEYMAP" ]]; then
            loadkeys "$KEYMAP" # Apply keymap for the live environment
            echo "Selected keyboard layout: $KEYMAP"
            break
        else
            echo "Keyboard layout cannot be empty. Please try again."
        fi
    done
}

select_locale_options() {
    while true; do
        echo -e "
--- Locale and Timezone Configuration ---"
        echo "Common locales: en_US.UTF-8, de_DE.UTF-8, fr_FR.UTF-8, es_ES.UTF-8"
        echo "You can list all available locales with 'locale -a'."
        read -p "Enter your desired locale (e.g., en_US.UTF-8): " LOCALE
        if [[ -n "$LOCALE" ]]; then
            break
        else
            echo "Locale cannot be empty. Please try again."
        fi
    done

    while true; do
        echo -e "
Common timezones: Asia/Kolkata, Europe/Berlin, America/New_York"
        echo "You can list all available timezones with 'timedatectl list-timezones'."
        read -p "Enter your desired timezone (e.g., Asia/Kolkata): " TIMEZONE
        if [[ -n "$TIMEZONE" && -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
            echo "Selected locale: $LOCALE"
            echo "Selected timezone: $TIMEZONE"
            break
        else
            echo "Invalid or empty timezone. Please enter a valid timezone."
        fi
    done
}

get_user_details() {
    echo -e "
--- User and Hostname Configuration ---"
    while true; do
        read -p "Enter desired hostname for the system: " HOSTNAME
        if [[ -n "$HOSTNAME" ]]; then
            break
        else
            echo "Hostname cannot be empty. Please try again."
        fi
    done

    while true; do
        read -p "Enter desired username for the new user: " USERNAME
        if [[ -n "$USERNAME" ]]; then
            break
        else
            echo "Username cannot be empty. Please try again."
        fi
    done

    while true; do
        read -p "Should '$USERNAME' be added to the sudoers group? (yes/no): " SUDO_ACCESS
        SUDO_ACCESS=$(echo "$SUDO_ACCESS" | tr '[:upper:]' '[:lower:]') # Convert to lowercase
        if [[ "$SUDO_ACCESS" == "yes" || "$SUDO_ACCESS" == "no" ]]; then
            echo "User details collected."
            break
        else
            echo "Invalid input. Please answer 'yes' or 'no'."
        fi
    done
}

partition_disk() {
    echo "Partitioning disk: $TARGET_DISK..."
    confirm_action "Proceed with partitioning $TARGET_DISK? This will erase all data."
    # Clear existing partitions
    sgdisk --zap-all "$TARGET_DISK"

    # Create partitions: ESP, Boot, LUKS Container
    sgdisk -n 1:0:+"$ESP_SIZE" -t 1:ef00 -c 1:"EFI System Partition" "$TARGET_DISK"
    sgdisk -n 2:0:+"$BOOT_SIZE" -t 2:8300 -c 2:"Linux Boot Partition" "$TARGET_DISK"
    sgdisk -n 3:0:0 -t 3:8300 -c 3:"Linux LUKS Container" "$TARGET_DISK"

    # Get partition names reliably
    ESP_PART=$(lsblk -o NAME,PARTLABEL | grep "EFI System Partition" | awk '{print "/dev/"$1}')
    BOOT_PART=$(lsblk -o NAME,PARTLABEL | grep "Linux Boot Partition" | awk '{print "/dev/"$1}')
    LUKS_PART=$(lsblk -o NAME,PARTLABEL | grep "Linux LUKS Container" | awk '{print "/dev/"$1}')

    # Format partitions
    mkfs.fat -F 32 "$ESP_PART"
    mkfs.ext4 -F "$BOOT_PART"

    echo "Disk partitioning complete."
    echo "ESP: $ESP_PART"
    echo "Boot: $BOOT_PART"
    echo "LUKS: $LUKS_PART"
}

setup_luks() {
    echo "Setting up LUKS encryption on $LUKS_PART..."
    read -s -p "Enter LUKS passphrase: " LUKS_PASSPHRASE
    echo
    read -s -p "Confirm LUKS passphrase: " LUKS_PASSPHRASE_CONFIRM
    echo

    if [[ "$LUKS_PASSPHRASE" != "$LUKS_PASSPHRASE_CONFIRM" ]]; then
        echo "Passphrases do not match. Exiting."
        exit 1
    fi
    confirm_action "Proceed with LUKS encryption on $LUKS_PART? This is irreversible."

    echo "$LUKS_PASSPHRASE" | cryptsetup -q luksFormat "$LUKS_PART" -
    echo "$LUKS_PASSPHRASE" | cryptsetup -q open "$LUKS_PART" cryptroot -

    unset LUKS_PASSPHRASE
    unset LUKS_PASSPHRASE_CONFIRM

    LUKS_UUID=$(blkid -s UUID -o value "$LUKS_PART")
    echo "LUKS setup complete. Decrypted device: /dev/mapper/cryptroot"
    echo "LUKS UUID: $LUKS_UUID"
}

setup_btrfs() {
    echo "Setting up Btrfs filesystem and subvolumes..."
    confirm_action "Proceed with creating Btrfs filesystem and subvolumes on /dev/mapper/cryptroot?"
    mkfs.btrfs -f /dev/mapper/cryptroot

    mount /dev/mapper/cryptroot /mnt

    # Create Btrfs subvolumes
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@snapshots
    btrfs subvolume create /mnt/@var_log
    btrfs subvolume create /mnt/@tmp
    btrfs subvolume create /mnt/@swap # For swapfile

    umount /mnt

    # Mount subvolumes
    mount -o "$BTRFS_MOUNT_OPTS",subvol=@ /dev/mapper/cryptroot /mnt
    mkdir -p /mnt/{home,.snapshots,var/log,tmp,boot,boot/efi,swap}
    mount -o "$BTRFS_MOUNT_OPTS",subvol=@home /dev/mapper/cryptroot /mnt/home
    mount -o "$BTRFS_MOUNT_OPTS",subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
    mount -o "$BTRFS_MOUNT_OPTS",subvol=@var_log /dev/mapper/cryptroot /mnt/var/log
    mount -o "$BTRFS_MOUNT_OPTS",subvol=@tmp /dev/mapper/cryptroot /mnt/tmp
    mount -o "$BTRFS_SWAP_OPTS",subvol=@swap /dev/mapper/cryptroot /mnt/swap # Mount swap subvolume

    # Mount boot and ESP
    mount "$BOOT_PART" /mnt/boot
    mount "$ESP_PART" /mnt/boot/efi

    echo "Btrfs subvolumes mounted."
}

install_base_system() {
    echo "Installing base system and essential packages..."
    confirm_action "Proceed with installing Arch Linux base system and selected kernel ($KERNEL_PACKAGE)?"
    # Use the selected KERNEL_PACKAGE
    pacstrap /mnt base "$KERNEL_PACKAGE" linux-firmware btrfs-progs snapper systemd-boot efibootmgr sbctl mkinitcpio cryptsetup dosfstools e2fsprogs # refind-efi is a dependency of sbctl-mkinitcpio-hook, often pulled.
    echo "Base system installed."
}

generate_fstab() {
    echo "Generating fstab..."
    confirm_action "Proceed with generating and modifying /etc/fstab?"
    genfstab -U /mnt >> /mnt/etc/fstab

    # Add Btrfs subvolume options and LUKS timeout
    sed -i "s|/dev/mapper/cryptroot / btrfs defaults|/dev/mapper/cryptroot / btrfs ${BTRFS_MOUNT_OPTS},subvol=@,x-systemd.device-timeout=0|g" /mnt/etc/fstab
    sed -i "s|/dev/mapper/cryptroot /home btrfs defaults|/dev/mapper/cryptroot /home btrfs ${BTRFS_MOUNT_OPTS},subvol=@home|g" /mnt/etc/fstab
    sed -i "s|/dev/mapper/cryptroot /.snapshots btrfs defaults|/dev/mapper/cryptroot /.snapshots btrfs ${BTRFS_MOUNT_OPTS},subvol=@snapshots|g" /mnt/etc/fstab
    sed -i "s|/dev/mapper/cryptroot /var/log btrfs defaults|/dev/mapper/cryptroot /var/log btrfs ${BTRFS_MOUNT_OPTS},subvol=@var_log|g" /mnt/etc/fstab
    sed -i "s|/dev/mapper/cryptroot /tmp btrfs defaults|/dev/mapper/cryptroot /tmp btrfs ${BTRFS_MOUNT_OPTS},subvol=@tmp|g" /mnt/etc/fstab
    sed -i "s|/dev/mapper/cryptroot /swap btrfs defaults|/dev/mapper/cryptroot /swap btrfs ${BTRFS_SWAP_OPTS},subvol=@swap|g" /mnt/etc/fstab

    echo "fstab generated and modified."
}

create_chroot_script() {
    echo "Creating chroot configuration script..."
    cat <<EOF > /mnt/chroot_script.sh
#!/bin/bash
set -euo pipefail

# --- Variables passed from main script ---
LOCALE="$LOCALE"
KEYMAP="$KEYMAP"
TIMEZONE="$TIMEZONE"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
SUDO_ACCESS="$SUDO_ACCESS"
KERNEL_NAME="$KERNEL_NAME"
KERNEL_PACKAGE="$KERNEL_PACKAGE"
LUKS_UUID="$LUKS_UUID"
BTRFS_MOUNT_OPTS="$BTRFS_MOUNT_OPTS"
SWAPFILE_SIZE="$SWAPFILE_SIZE"

# --- Chroot Configuration ---

# Locale
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Keyboard layout
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat <<EOT >> /etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
EOT

# Network Configuration
systemctl enable systemd-networkd
systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# User and Passwords
echo "Set the root password:"
passwd
echo "Creating user $USERNAME..."
useradd -m -g users -s /bin/bash "$USERNAME"
echo "Set the password for $USERNAME:"
passwd "$USERNAME"

# Sudo access
if [[ "$SUDO_ACCESS" == "yes" ]]; then
    usermod -aG wheel "$USERNAME"
    echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
    echo "User '$USERNAME' added to wheel group for sudo access."
fi

# mkinitcpio
sed -i 's/^HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block sd-encrypt btrfs filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Swapfile
btrfs filesystem mkswapfile --size "$SWAPFILE_SIZE" /swap/swapfile
echo "/swap/swapfile none swap defaults 0 0" >> /etc/fstab
swapon /swap/swapfile

# Bootloader and Secure Boot
bootctl install

echo "default arch.conf" > /boot/loader/loader.conf
echo "timeout 3" >> /boot/loader/loader.conf
echo "editor no" >> /boot/loader/loader.conf

# Correct kernel parameter for sd-encrypt is luks.name
cat <<EOT > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-$KERNEL_NAME
initrd  /initramfs-$KERNEL_NAME.img
options luks.name=$LUKS_UUID=cryptroot root=/dev/mapper/cryptroot rw $BTRFS_MOUNT_OPTS rd.luks.options=discard
EOT

cat <<EOT > /boot/loader/entries/arch-fallback.conf
title   Arch Linux (fallback)
linux   /vmlinuz-$KERNEL_NAME
initrd  /initramfs-$KERNEL_NAME-fallback.img
options luks.name=$LUKS_UUID=cryptroot root=/dev/mapper/cryptroot rw $BTRFS_MOUNT_OPTS rd.luks.options=discard
EOT

sbctl create-keys
sbctl enroll-keys -m
sbctl sign -s /boot/efi/EFI/systemd/systemd-bootx64.efi
sbctl sign -s /boot/vmlinuz-$KERNEL_NAME
sbctl sign -s /boot/initramfs-$KERNEL_NAME.img
sbctl sign -s /boot/initramfs-$KERNEL_NAME-fallback.img

# Pacman hook for sbctl
cat <<EOF_HOOK > /etc/pacman.d/hooks/90-sbctl-sign.hook
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = $KERNEL_PACKAGE

[Action]
Description = Signing kernel and initramfs with sbctl...
When = PostTransaction
Exec = /usr/bin/sbctl sign -s /boot/vmlinuz-$KERNEL_NAME -s /boot/initramfs-$KERNEL_NAME.img -s /boot/initramfs-$KERNEL_NAME-fallback.img
EOF_HOOK

echo "Chroot configuration complete."

EOF

    chmod +x /mnt/chroot_script.sh
    echo "Chroot script created."
}

run_chroot_script() {
    echo "Running chroot configuration script..."
    arch-chroot /mnt /chroot_script.sh
    echo "Chroot script execution finished."
}

final_cleanup() {
    echo "Performing final cleanup and unmounting..."
    confirm_action "Proceed with unmounting file systems and closing LUKS container? System will be ready for reboot."
    umount -R /mnt
    cryptsetup close cryptroot
    echo "Cleanup complete. You can now reboot."
}

# --- Main Script Execution ---
print_header
confirm_action "This script will automate Arch Linux installation. It is highly destructive. Do you wish to proceed?"
check_root
check_uefi
set_up_internet
select_disk
select_kernel
select_keyboard_layout
select_locale_options
get_user_details
partition_disk
setup_luks
setup_btrfs
install_base_system
generate_fstab
create_chroot_script
run_chroot_script
final_cleanup

echo -e "\n================================================================="
echo -e "  Arch Linux Installation Complete!"
echo -e "  Please reboot your system now: reboot"
echo -e "=================================================================\n"
