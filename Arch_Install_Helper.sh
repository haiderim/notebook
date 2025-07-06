#!/bin/bash

# Arch Linux Auto-Installation Script for ThinkPad X280
# Features: LUKS encryption, Btrfs with Snapper, Secure Boot with systemd-boot
# Author: Auto-generated installation script
# Warning: This script will wipe the target disk completely!

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[INPUT]${NC} $1"
}

confirm_action() {
    local action="$1"
    echo -e "${YELLOW}[CONFIRM]${NC} $action"
    read -p "Continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        error "Operation cancelled by user"
    fi
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
fi

# Check if UEFI mode
if [[ ! -d /sys/firmware/efi ]]; then
    error "This script requires UEFI mode"
fi

# Check if secure boot is available (EFI variables access)
if [[ ! -d /sys/firmware/efi/efivars ]]; then
    error "EFI variables not accessible. Secure Boot setup may fail."
fi

clear
echo -e "${RED}=== ARCH LINUX AUTO-INSTALLATION SCRIPT ===${NC}"
echo -e "${RED}WARNING: This script will COMPLETELY WIPE the selected disk!${NC}"
echo -e "${RED}Make sure you have backed up all important data!${NC}"
echo ""
confirm_action "Starting Arch Linux installation process"

# --- AGGRESSIVE INITIAL CLEANUP ---
# This section ensures the system is clean from previous failed runs or existing mounts
# before any disk selection or partitioning.
log "Performing initial aggressive cleanup of any existing mounts and LUKS mappings..."

# Attempt to unmount /mnt and its subdirectories
if mountpoint -q /mnt; then
    warn "Unmounting /mnt and its subdirectories..."
    umount -R /mnt 2>/dev/null || true
fi

# Attempt to close any cryptroot LUKS mapping
if cryptsetup status cryptroot &>/dev/null; then
    warn "Closing existing 'cryptroot' LUKS mapping..."
    cryptsetup close cryptroot 2>/dev/null || true
fi

# Attempt to remove all device mapper devices (includes any lingering LUKS mappings)
warn "Removing any lingering device mapper devices..."
dmsetup remove_all 2>/dev/null || true

log "Initial aggressive cleanup complete."
# --- END AGGRESSIVE INITIAL CLEANUP ---


# Interactive configuration
info "Select installation disk:"
lsblk -d -o NAME,SIZE,MODEL
echo ""
read -p "Enter disk (e.g., nvme0n1, sda): " DISK_NAME
DISK="/dev/$DISK_NAME"

# Determine partition suffix based on disk type (e.g., sda1 vs nvme0n1p1)
if [[ "$DISK_NAME" == nvme* ]]; then
    PART_SUFFIX="p"
else
    PART_SUFFIX="" # For sda, sdb, etc.
fi

ESP_PART="${DISK}${PART_SUFFIX}1"
BOOT_PART="${DISK}${PART_SUFFIX}2"
LUKS_PART="${DISK}${PART_SUFFIX}3"

# Global variable for LUKS UUID, to be set after LUKS setup
LUKS_UUID=""

if [[ ! -b $DISK ]]; then
    error "Disk $DISK does not exist"
fi

confirm_action "This will WIPE ALL DATA on $DISK"

info "Select kernel variant:"
echo "1) linux (default)"
echo "2) linux-lts"
echo "3) linux-zen"
read -p "Choice [1-3]: " KERNEL_CHOICE

case $KERNEL_CHOICE in
    2) KERNEL="linux-lts" ;;
    3) KERNEL="linux-zen" ;;
    *) KERNEL="linux" ;;
esac

info "Select timezone:"
echo "Examples: UTC, America/New_York, Europe/London, Asia/Tokyo"
read -p "Timezone [UTC]: " TIMEZONE
TIMEZONE=${TIMEZONE:-UTC}

info "Select locale:"
read -p "Locale [en_US.UTF-8]: " LOCALE
LOCALE=${LOCALE:-en_US.UTF-8}

info "Select keymap:"
read -p "Keymap [us]: " KEYMAP
KEYMAP=${KEYMAP:-us}

info "Set hostname:"
read -p "Hostname [x280-arch]: " HOSTNAME
HOSTNAME=${HOSTNAME:-x280-arch}

info "Set username:"
read -p "Username [user]: " USERNAME
USERNAME=${USERNAME:-user}

# Update system clock
log "Updating system clock..."
timedatectl set-ntp true

# Function to clean up disk before partitioning
pre_partition_cleanup() {
    log "Performing pre-partitioning cleanup on $DISK..."
    # Unmount all partitions on the target disk (e.g., /dev/sda1, /dev/sda2)
    # This specifically targets partitions on the chosen disk.
    for part_name in $(lsblk -no NAME "$DISK" | tail -n +2); do # Get partition names, skip disk itself
        local part_path="/dev/$part_name"
        if mountpoint -q "$part_path"; then # Check if it's a mountpoint
            warn "Unmounting partition $part_path..."
            umount "$part_path" || true
        fi
    done

    # Deactivate any swap areas on the target disk
    if swapon --show | grep -q "$DISK"; then
        warn "Deactivating swap areas on $DISK..."
        swapoff -a
    fi

    # Close any LUKS containers associated with the target disk's partitions
    for dev in $(ls /dev/mapper/ | grep -E "^crypt"); do
        if cryptsetup status "$dev" &>/dev/null; then
            LUKS_UNDERLYING_DEV=$(cryptsetup status "$dev" | grep "device:" | awk '{print $2}')
            # Check if the underlying device of the LUKS mapping is a partition of our target DISK
            if [[ "$LUKS_UNDERLYING_DEV" == "${DISK}${PART_SUFFIX}"* || "$LUKS_UNDERLYING_DEV" == "$DISK" ]]; then
                warn "Closing LUKS container /dev/mapper/$dev on $LUKS_UNDERLYING_DEV..."
                cryptsetup close "$dev" || true
            fi
        fi
    done

    # Remove any device mapper entries for partitions on the disk
    # This is often needed after closing LUKS containers
    if command -v kpartx &>/dev/null; then
        log "Removing kpartx device mapper entries for $DISK..."
        kpartx -d "$DISK" || true
    fi

    # Aggressively clear filesystem and partition table signatures
    # This is crucial for parted to work on a "clean" disk
    log "Clearing old filesystem and partition table signatures with wipefs..."
    wipefs -af "$DISK" || true # Use || true to prevent script from exiting if wipefs fails (e.g., no signatures)
    blockdev --flushbufs "$DISK" || true # Flush disk buffers
    sync # Flush filesystem caches
    sleep 1 # Give kernel a moment to process

    # Tell the kernel to re-read the partition table (should be empty now)
    log "Telling kernel to re-read partition table..."
    partprobe -s "$DISK" || true # Use || true as it might fail if disk is truly blank
    udevadm settle # Wait for udev events to complete
    sleep 1 # Give kernel a moment to process

    # Remove all device mapper devices (including any lingering LUKS mappings)
    log "Removing any lingering device mapper devices (final attempt)..."
    dmsetup remove_all || true # Use || true as it might fail if no devices exist

    log "Pre-partitioning cleanup complete."
}

# Partition the disk
confirm_action "Partitioning disk $DISK"
pre_partition_cleanup # Call cleanup function before partitioning
log "Creating GPT partition table..."
# Use a subshell to capture parted's output to check for persistent errors
if ! parted -s "$DISK" mklabel gpt 2>&1 | tee /dev/stderr | grep -q "Partition(s) on .* are being used"; then
    log "GPT partition table created."
else
    error "Failed to create GPT partition table. This often means the kernel is still holding references to the disk. Please reboot the Arch Linux ISO and try again."
fi


log "Creating EFI System Partition (1GB)..."
parted -s "$DISK" mkpart primary fat32 1MiB 1GiB
parted -s "$DISK" set 1 esp on

log "Creating Boot partition (1GB)..."
parted -s "$DISK" mkpart primary ext4 1GiB 2GiB

log "Creating LUKS partition (remaining space)..."
parted -s "$DISK" mkpart primary 2GiB 100%

# Format partitions
confirm_action "Formatting partitions"
log "Formatting EFI partition ($ESP_PART)..."
mkfs.fat -F32 "$ESP_PART"

log "Formatting boot partition ($BOOT_PART)..."
mkfs.ext4 "$BOOT_PART"

# Setup LUKS encryption
log "Setting up LUKS encryption..."
while true; do
    echo -n "Enter LUKS passphrase: "
    read -s LUKS_PASS
    echo
    echo -n "Confirm LUKS passphrase: "
    read -s LUKS_PASS_CONFIRM
    echo
    
    if [[ "$LUKS_PASS" == "$LUKS_PASS_CONFIRM" ]]; then
        break
    else
        error "Passphrases do not match. Please try again."
    fi
done

confirm_action "Creating LUKS container on $LUKS_PART (this may take a while)"
cryptsetup luksFormat "$LUKS_PART" <<< "$LUKS_PASS"
cryptsetup open "$LUKS_PART" cryptroot <<< "$LUKS_PASS"
LUKS_UUID=$(blkid -s UUID -o value "$LUKS_PART") # Capture LUKS UUID here

# Create Btrfs filesystem
confirm_action "Creating Btrfs filesystem on /dev/mapper/cryptroot"
mkfs.btrfs -L arch /dev/mapper/cryptroot

# Mount and create subvolumes
log "Creating Btrfs subvolumes..."
mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@swap # For swapfile
umount /mnt

# Mount subvolumes with proper options (corrected order for boot/efi)
log "Mounting Btrfs subvolumes..."
mount -o compress=zstd,noatime,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,var,tmp,.snapshots,swap} # Create these directories first
mount -o compress=zstd,noatime,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o compress=zstd,noatime,subvol=@var /dev/mapper/cryptroot /mnt/var
mount -o compress=zstd,noatime,subvol=@tmp /dev/mapper/cryptroot /mnt/tmp
mount -o compress=zstd,noatime,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
mount -o noatime,subvol=@swap /dev/mapper/cryptroot /mnt/swap # Mount the @swap subvolume for swapfile creation later

# Mount boot partitions (Crucial: mount /mnt/boot BEFORE creating /mnt/boot/efi)
mkdir -p /mnt/boot # Ensure /mnt/boot exists
mount "$BOOT_PART" /mnt/boot
mkdir -p /mnt/boot/efi # Create /mnt/boot/efi AFTER /mnt/boot is mounted
mount "$ESP_PART" /mnt/boot/efi
chmod 0700 /mnt/boot/efi # Set strict permissions on ESP

# Install base system
confirm_action "Installing base system packages"
log "Installing base system and essential packages..."
# Use printf to send multiple '1' inputs for interactive prompts from pacstrap
printf "1\n1\n" | pacstrap /mnt base base-devel "$KERNEL" linux-firmware intel-ucode btrfs-progs snapper \
    vim nano sudo cryptsetup sbctl efibootmgr networkmanager

# Generate fstab
log "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Add Btrfs mount options to fstab and LUKS timeout
log "Adding Btrfs mount options and LUKS timeout to fstab..."
sed -i '/btrfs/ s/relatime/noatime,compress=zstd/' /mnt/etc/fstab
# Add x-systemd.device-timeout=0 for LUKS device
sed -i "/\/dev\/mapper\/cryptroot/s/defaults/defaults,x-systemd.device-timeout=0/" /mnt/etc/fstab

# Configure system in chroot
confirm_action "Configuring system in chroot"
log "Configuring system in chroot..."
arch-chroot /mnt /bin/bash <<EOF
set -e

# Set timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Set locale
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Set keymap
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOL
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOL

# Configure mkinitcpio for LUKS and Btrfs
# Ensure encrypt and btrfs hooks are present, without hardcoding the entire line
if ! grep -q "HOOKS=.*encrypt" /etc/mkinitcpio.conf; then
    sed -i '/^HOOKS=/ s/\(filesystems\)/\1 encrypt/' /etc/mkinitcpio.conf
fi
if ! grep -q "HOOKS=.*btrfs" /etc/mkinitcpio.conf; then
    sed -i '/^HOOKS=/ s/\(filesystems\)/\1 btrfs/' /etc/mkinitcpio.conf
fi
# Ensure kms is removed if present and not explicitly desired for minimal setup
sed -i 's/\<kms\>//g' /etc/mkinitcpio.conf # Remove kms hook if present
mkinitcpio -P
# IMPORTANT: The sbctl mkinitcpio hook will warn "Secureboot key directory doesn't exist, not signing!"
# during pacstrap's post-transaction phase because keys are created later in this chroot block.
# This is expected and harmless for the initial install. The kernel and bootloader will be
# manually signed below after key creation.

# Install and configure systemd-boot
# The D-Bus error from bootctl install is common in chroot environments as D-Bus might not be fully active.
# It's usually benign if the bootloader files are created successfully.
bootctl --path=/boot/efi install

# Set strict permissions on the random-seed file created by bootctl
chmod 0600 /boot/efi/loader/random-seed

# Use the LUKS_UUID passed from the outer script
# This is more reliable than re-deriving it inside chroot
LUKS_UUID_CHROOT="$LUKS_UUID"


# Create systemd-boot entry
mkdir -p /boot/efi/loader/entries
cat > /boot/efi/loader/loader.conf <<EOL
default arch.conf
timeout 3
console-mode keep
editor no
EOL

# Determine ucode image based on installed package
UCODE_IMG=""
if pacman -Qq intel-ucode &>/dev/null; then
    UCODE_IMG="initrd /intel-ucode.img"
elif pacman -Qq amd-ucode &>/dev/null; then
    UCODE_IMG="initrd /amd-ucode.img"
fi


cat > /boot/efi/loader/entries/arch.conf <<EOL
title Arch Linux
linux /vmlinuz-$KERNEL
$UCODE_IMG
initrd /initramfs-$KERNEL.img
options cryptdevice=UUID=\$LUKS_UUID_CHROOT:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw
EOL

# Configure snapper
snapper -c root create-config /
chmod 750 /.snapshots

# Configure snapper settings
cat > /etc/snapper/configs/root <<EOL
SUBVOLUME="/"
FSTYPE="btrfs"
QGROUP=""
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
ALLOW_USERS=""
ALLOW_GROUPS=""
SYNC_ACL="no"
BACKGROUND_COMPARISON="yes"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="50"
NUMBER_LIMIT_IMPORTANT="10"
TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="10"
TIMELINE_LIMIT_DAILY="10"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="10"
TIMELINE_LIMIT_YEARLY="10"
EOL

# Enable services
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable NetworkManager # Enable NetworkManager
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

# Create user
useradd -m -G wheel -s /bin/bash "$USERNAME" # Use quotes for variable

# Set user password
echo "Set password for user '$USERNAME':"
while true; do
    passwd "$USERNAME" && break # Use quotes for variable
    echo "Password setting failed. Please try again."
done

# Configure sudo
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel # Set correct permissions for sudoers file

# Set root password
echo "Set password for root user:"
while true; do
    passwd root && break
    echo "Password setting failed. Please try again."
done

# Setup secure boot
echo "Setting up secure boot..."
sbctl create-keys
sbctl enroll-keys -m

# Sign kernel and bootloader
sbctl sign -s /boot/efi/EFI/systemd/systemd-bootx64.efi
sbctl sign -s /boot/efi/EFI/BOOT/BOOTX64.EFI
sbctl sign -s /boot/vmlinuz-$KERNEL
sbctl sign -s /boot/initramfs-$KERNEL.img
sbctl sign -s /boot/initramfs-$KERNEL-fallback.img # Sign fallback initramfs

# Create pacman hook for automatic signing
mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/999-sign_kernel_for_secureboot.hook <<EOL
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = linux-lts
Target = linux-zen

[Action]
Description = Signing kernel with Machine Owner Key for Secure Boot
When = PostTransaction
Exec = /usr/bin/sbctl sign -s /boot/vmlinuz-%PKGBASE% -s /boot/initramfs-%PKGBASE%.img -s /boot/initramfs-%PKGBASE%-fallback.img
Depends = sbctl
EOL
# Ensure the hook is executable (though pacman hooks don't strictly need it, good practice)
chmod +x /etc/pacman.d/hooks/999-sign_kernel_for_secureboot.hook


# Create systemd-boot update hook
cat > /etc/pacman.d/hooks/100-systemd-boot.hook <<EOL
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Gracefully upgrading systemd-boot...
When = PostTransaction
Exec = /usr/bin/systemctl restart systemd-boot-update.service
EOL

echo "Secure boot setup complete"
echo "Signed files:"
sbctl list-files

EOF

# Create post-install script
cat > /mnt/home/$USERNAME/post-install.sh <<'EOF'
#!/bin/bash

# Post-installation script for additional configuration

log() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

log "Running post-installation configuration..."

# Create initial snapshot
sudo snapper -c root create --description "Initial snapshot after installation"

log "Post-installation configuration complete!"
log "System is ready for use with secure boot enabled."
log "Available snapshots:"
sudo snapper -c root list

log "Network configuration needed:"
log "If you rely on Wi-Fi or more complex network setups, consider running:"
log "sudo systemctl enable --now NetworkManager"
log "sudo systemctl disable --now systemd-networkd systemd-resolved"
log "Then reboot."
log "For wired connections, you might need to create configuration files in /etc/systemd/network/"
log "Example: /etc/systemd/network/20-wired.network"
EOF

chmod +x /mnt/home/$USERNAME/post-install.sh

# Unmount filesystems
log "Unmounting filesystems..."
confirm_action "Unmounting filesystems and closing LUKS container. System will be ready for reboot."
umount -R /mnt
cryptsetup close cryptroot

log "Installation complete!"
log "System is configured with:"
log "- LUKS encryption on ${LUKS_PART}"
log "- Separate boot partition on ${BOOT_PART}"
log "- Btrfs with compression and subvolumes"
log "- Snapper for snapshots"
log "- Systemd-boot with secure boot support"
log "- Automatic kernel signing for secure boot"
log "- $KERNEL kernel"
log ""
log "After reboot:"
log "1. Boot into the new system"
log "2. Configure network (NetworkManager is installed, but you may need to enable/disable systemd-networkd)"
log "3. Run the post-install script in your home directory: /home/$USERNAME/post-install.sh"
log "4. Verify secure boot status with: bootctl status"
log "5. Check signed files with: sudo sbctl list-files"
log ""
warn "Make sure to backup your LUKS passphrase!"
warn "The system will automatically sign kernels on updates."

echo "Press Enter to reboot..."
read
reboot
