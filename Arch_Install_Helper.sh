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

    # Get partition names
    ESP_PART="${TARGET_DISK}p1"
    BOOT_PART="${TARGET_DISK}p2"
    LUKS_PART="${TARGET_DISK}p3"

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

    # Add a tmpfs mount for /tmp to reduce wear on SSDs
    echo "tmpfs /tmp tmpfs noatime,mode=1777 0 0" >> /mnt/etc/fstab

    echo "fstab generated and modified."
}

chroot_and_configure_system() {
    echo "Chrooting into the new system for configuration..."
    confirm_action "Proceed with chrooting and configuring the new system (locale, timezone, hostname, users, passwords, mkinitcpio, swapfile)?"
    arch-chroot /mnt /bin/bash <<EOF
    # Locale
    echo "$LOCALE UTF-8" >> /etc/locale.gen
    locale-gen
    echo "LANG=$LOCALE" > /etc/locale.conf

    # Keyboard layout
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

    # Timezone
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc

    # Hostname (using user input)
    echo "$HOSTNAME" > /etc/hostname
    echo "127.0.0.1 localhost" >> /etc/hosts
    echo "::1       localhost" >> /etc/hosts
    echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

    # Network Configuration (systemd-networkd)
    echo "[Match]" > /etc/systemd/network/20-wired.network
    echo "Name=en*" >> /etc/systemd/network/20-wired.network
    echo "[Network]" >> /etc/systemd/network/20-wired.network
    echo "DHCP=yes" >> /etc/systemd/network/20-wired.network
    systemctl enable systemd-networkd
    systemctl enable systemd-resolved
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

    # Root password (explicit prompt)
    echo "Please set the password for the root user:"
    passwd

    # Create user account (using user input)
    useradd -m -g users -s /bin/bash "$USERNAME"
    echo "Please set the password for user '$USERNAME':"
    passwd "$USERNAME"

    # Configure sudo for wheel group if requested
    if [[ "$SUDO_ACCESS" == "yes" ]]; then
        usermod -aG wheel "$USERNAME"
        echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
        echo "User '$USERNAME' added to wheel group and sudoers."
    else
        echo "User '$USERNAME' NOT added to wheel group."
    fi

    # mkinitcpio configuration
    # The KERNEL_NAME variable is passed from the outer script
    # Ensure the correct initramfs name is used based on the selected kernel
    sed -i 's/^HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block sd-encrypt btrfs filesystems fsck)/' /etc/mkinitcpio.conf
    mkinitcpio -P

    # Create swapfile on @swap subvolume
    btrfs filesystem mkswapfile --size "$SWAPFILE_SIZE" /swap/swapfile
    echo "/swap/swapfile none swap defaults 0 0" >> /etc/fstab
    swapon /swap/swapfile

    # Enable Display Manager if a DE was selected
    if [[ -n "$DM_SERVICE" ]]; then
        systemctl enable "$DM_SERVICE"
        echo "Enabled display manager: $DM_SERVICE"
    fi

    echo "System configuration complete in chroot."
EOF
}

setup_bootloader_and_secureboot() {
    echo "Setting up systemd-boot and Secure Boot..."
    confirm_action "Proceed with installing systemd-boot, configuring boot entries, and setting up Secure Boot with sbctl?"

    arch-chroot /mnt /bin/bash <<EOF
    # Install systemd-boot
    bootctl install

    # Configure systemd-boot entries
    echo "default arch.conf" > /boot/loader/loader.conf
    echo "timeout 3" >> /boot/loader/loader.conf
    echo "editor no" >> /boot/loader/loader.conf

    # Create arch.conf entry using KERNEL_NAME
    echo "title   Arch Linux" > /boot/loader/entries/arch.conf
    echo "linux   /vmlinuz-$KERNEL_NAME" >> /boot/loader/entries/arch.conf
    echo "initrd  /initramfs-$KERNEL_NAME.img" >> /boot/loader/entries/arch.conf
    echo "options rd.luks.name=$LUKS_UUID=cryptroot root=/dev/mapper/cryptroot rw $BTRFS_MOUNT_OPTS rd.luks.options=discard" >> /boot/loader/entries/arch.conf

    # Optional: Create arch-fallback.conf entry using KERNEL_NAME
    echo "title   Arch Linux (fallback)" > /boot/loader/entries/arch-fallback.conf
    echo "linux   /vmlinuz-$KERNEL_NAME" >> /boot/loader/entries/arch-fallback.conf
    echo "initrd  /initramfs-$KERNEL_NAME-fallback.img" >> /boot/loader/entries/arch-fallback.img
    echo "options rd.luks.name=$LUKS_UUID=cryptroot root=/dev/mapper/cryptroot rw $BTRFS_MOUNT_OPTS rd.luks.options=discard" >> /boot/loader/entries/arch-fallback.conf

    # Secure Boot Setup with sbctl
    echo "Creating Secure Boot keys and enrolling them..."
    sbctl create-keys
    sbctl enroll-keys -m

    # Sign bootloader and initial kernel/initramfs using KERNEL_NAME
    sbctl sign -s /boot/efi/EFI/systemd/systemd-bootx64.efi
    sbctl sign -s /boot/vmlinuz-$KERNEL_NAME
    sbctl sign -s /boot/initramfs-$KERNEL_NAME.img
    sbctl sign -s /boot/initramfs-$KERNEL_NAME-fallback.img

    # Automate kernel signing with a pacman hook
    mkdir -p /etc/pacman.d/hooks/
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
    echo "Pacman hook for auto-signing kernels created."

    echo "Bootloader and Secure Boot setup complete."
EOF
}

setup_snapper() {
    echo "Setting up Snapper for Btrfs snapshots..."
    confirm_action "Proceed with setting up Snapper configurations and enabling its services?"
    arch-chroot /mnt /bin/bash <<EOF
    # Create Snapper configuration for root
    snapper -c root create-config /

    # Adjust Snapper configuration (optional, example values)
    # sed -i 's/TIMELINE_LIMIT_HOURLY="10"/TIMELINE_LIMIT_HOURLY="5"/' /etc/snapper/configs/root
    # sed -i 's/TIMELINE_LIMIT_DAILY="10"/TIMELINE_LIMIT_DAILY="7"/' /etc/snapper/configs/root

    # Enable Snapper services
    systemctl enable snapper-timeline.timer
    systemctl enable snapper-cleanup.timer

    # Create Snapper configuration for home (optional)
    snapper -c home create-config /home

    echo "Snapper setup complete."
EOF
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
chroot_and_configure_system
setup_bootloader_and_secureboot
setup_snapper
final_cleanup

echo -e "\n================================================================="
echo -e "  Arch Linux Installation Complete!"
echo -e "  Please reboot your system now: reboot"
echo -e "=================================================================\n"
