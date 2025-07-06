#!/bin/bash

# Arch Linux Auto-Installation Script
# Features: LUKS encryption, Btrfs with Snapper, Secure Boot with systemd-boot
# Version: 5.6 (Final Hardened)
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

clear
echo -e "${RED}=== ARCH LINUX AUTO-INSTALLATION SCRIPT (HARDENED) ===${NC}"
echo -e "${RED}WARNING: This script will COMPLETELY WIPE the selected disk!${NC}"
echo ""
confirm_action "Starting Arch Linux installation process"

# --- AGGRESSIVE INITIAL CLEANUP ---
log "Performing initial aggressive cleanup..."
if mountpoint -q /mnt; then umount -R /mnt 2>/dev/null || true; fi
if cryptsetup status cryptroot &>/dev/null; then cryptsetup close cryptroot 2>/dev/null || true; fi
dmsetup remove_all 2>/dev/null || true
log "Initial cleanup complete."
# --- END AGGRESSIVE INITIAL CLEANUP ---

# --- USER CONFIGURATION ---
info "Select installation disk:"
lsblk -d -o NAME,SIZE,MODEL
echo ""
read -p "Enter disk (e.g., nvme0n1, sda): " DISK_NAME
DISK="/dev/$DISK_NAME"

if [[ "$DISK_NAME" == nvme* ]]; then PART_SUFFIX="p"; else PART_SUFFIX=""; fi
ESP_PART="${DISK}${PART_SUFFIX}1"
BOOT_PART="${DISK}${PART_SUFFIX}2"
LUKS_PART="${DISK}${PART_SUFFIX}3"

if [[ ! -b $DISK ]]; then error "Disk $DISK does not exist"; fi

confirm_action "This will WIPE ALL DATA on $DISK"

info "Select kernel variant: [1] linux (default), [2] linux-lts, [3] linux-zen"
read -p "Choice [1-3]: " KERNEL_CHOICE
case $KERNEL_CHOICE in 2) KERNEL="linux-lts";; 3) KERNEL="linux-zen";; *) KERNEL="linux";; esac

read -p "Timezone [UTC]: " TIMEZONE; TIMEZONE=${TIMEZONE:-UTC}
read -p "Locale [en_US.UTF-8]: " LOCALE; LOCALE=${LOCALE:-en_US.UTF-8}
read -p "Keymap [us]: " KEYMAP; KEYMAP=${KEYMAP:-us}
read -p "Hostname [think-arch]: " HOSTNAME; HOSTNAME=${HOSTNAME:-think-arch}
read -p "Username [user]: " USERNAME; USERNAME=${USERNAME:-user}

# --- PRE-INSTALLATION ---
log "Updating system clock..."
timedatectl set-ntp true

pre_partition_cleanup() {
    log "Wiping all signatures and partition tables from $DISK..."
    swapoff -a 2>/dev/null || true
    wipefs -af "$DISK" || true
    sgdisk --zap-all "$DISK" || true
    sync
    partprobe -s "$DISK" || true
    udevadm settle
    sleep 2
}

# --- DISK PARTITIONING & FORMATTING ---
confirm_action "Partitioning disk $DISK"
pre_partition_cleanup

log "Creating partitions..."
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI System Partition" "$DISK"
sgdisk -n 2:0:+1G -t 2:8300 -c 2:"Boot Partition" "$DISK"
sgdisk -n 3:0:0   -t 3:8300 -c 3:"LUKS Root" "$DISK"

log "Formatting partitions..."
mkfs.fat -F32 "$ESP_PART"
mkfs.ext4 -F "$BOOT_PART"

# --- LUKS ENCRYPTION SETUP ---
log "Setting up LUKS encryption..."
while true; do
    read -s -p "Enter LUKS passphrase: " LUKS_PASS; echo
    read -s -p "Confirm LUKS passphrase: " LUKS_PASS_CONFIRM; echo
    if [[ "$LUKS_PASS" == "$LUKS_PASS_CONFIRM" ]]; then break; else echo "Passphrases do not match. Please try again."; fi
done

log "Creating LUKS container on $LUKS_PART..."
cryptsetup --verbose luksFormat "$LUKS_PART" <<< "$LUKS_PASS"

if ! cryptsetup isLuks "$LUKS_PART"; then
    error "Failed to create LUKS container"
fi

log "Opening LUKS container..."
cryptsetup open "$LUKS_PART" cryptroot <<< "$LUKS_PASS"
if ! cryptsetup status cryptroot &>/dev/null; then error "Failed to open LUKS container."; fi

LUKS_UUID=$(blkid -s UUID -o value "$LUKS_PART")
if [ -z "$LUKS_UUID" ]; then error "Failed to retrieve LUKS partition UUID."; fi

# --- BTRFS & MOUNTING ---
log "Creating Btrfs filesystem and subvolumes..."
mkfs.btrfs -L arch /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt
# We create @, @home, etc., but NOT @snapshots. Snapper will create its own
# nested .snapshots directory inside the @ subvolume when we run create-config.
for vol in @ @home @var @tmp @swap; do btrfs subvolume create "/mnt/$vol"; done
umount /mnt

log "Mounting filesystems..."
BTRFS_OPTS="compress=zstd,noatime"
mount -o "$BTRFS_OPTS,subvol=@" /dev/mapper/cryptroot /mnt
# Create mount points for subvolumes, but handle /boot separately
mkdir -p /mnt/{home,var,tmp,swap}
mount -o "$BTRFS_OPTS,subvol=@home" /dev/mapper/cryptroot /mnt/home
mount -o "$BTRFS_OPTS,subvol=@var" /dev/mapper/cryptroot /mnt/var
mount -o "$BTRFS_OPTS,subvol=@tmp" /dev/mapper/cryptroot /mnt/tmp
mount -o "subvol=@swap" /dev/mapper/cryptroot /mnt/swap

# Correctly mount boot and EFI partitions
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot
mkdir -p /mnt/boot/efi
mount "$ESP_PART" /mnt/boot/efi
chmod 0755 /mnt/boot/efi

# --- BASE SYSTEM INSTALLATION ---
confirm_action "Installing base system and essential packages"
# Add essential networking and utility packages
pacstrap /mnt base base-devel "$KERNEL" linux-firmware intel-ucode amd-ucode btrfs-progs snapper \
    sudo cryptsetup sbctl efibootmgr networkmanager nano iproute2 inetutils dhcpcd wget

# --- FSTAB & CHROOT PREPARATION ---
log "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
sed -i "/swap/d" /mnt/etc/fstab

echo "$LUKS_UUID" > /mnt/tmp/luks_uuid_value

# --- SYSTEM CONFIGURATION (IN CHROOT) ---
confirm_action "Configuring system in chroot"
arch-chroot /mnt /bin/bash <<EOF
set -e # Exit on error within chroot

# --- Basic System Setup ---
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOL
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOL

# --- Initramfs Configuration ---
echo "[CHROOT] Configuring initramfs..."
sed -i -E "s/^MODULES=\(.*\)/MODULES=(btrfs)/" /etc/mkinitcpio.conf
sed -i -E "s/^HOOKS=\(.*\)/HOOKS=(base udev autodetect modconf keyboard keymap consolefont block encrypt filesystems fsck)/" /etc/mkinitcpio.conf

if ! mkinitcpio -P; then
    echo -e "\033[0;31m[ERROR]\033[0m Failed to generate initramfs images."
    exit 1
fi
echo "[CHROOT] Initramfs generated successfully."

# --- Bootloader Setup ---
echo "[CHROOT] Installing and configuring systemd-boot..."
if ! bootctl --path=/boot/efi install; then
    echo -e "\033[0;31m[ERROR]\033[0m Failed to install systemd-boot."
    exit 1
fi

cat > /boot/efi/loader/loader.conf <<EOL
default arch.conf
timeout 5
console-mode keep
editor no
EOL

LUKS_UUID_FROM_FILE=\$(cat /tmp/luks_uuid_value)
rm /tmp/luks_uuid_value
if [ -z "\$LUKS_UUID_FROM_FILE" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m LUKS UUID could not be read inside chroot."
    exit 1
fi

UCODE_IMG=""
if grep -q "GenuineIntel" /proc/cpuinfo; then
    UCODE_IMG="initrd /intel-ucode.img"
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    UCODE_IMG="initrd /amd-ucode.img"
else
    UCODE_IMG="" # Explicitly set to empty if no known CPU
fi

cat > /boot/efi/loader/entries/arch.conf <<EOL
title Arch Linux
linux /vmlinuz-$KERNEL
\$UCODE_IMG
initrd /initramfs-$KERNEL.img
options cryptdevice=UUID=\$LUKS_UUID_FROM_FILE:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw
EOL

cat > /boot/efi/loader/entries/arch-fallback.conf <<EOL
title Arch Linux (Fallback)
linux /vmlinuz-$KERNEL
\$UCODE_IMG
initrd /initramfs-$KERNEL-fallback.img
options cryptdevice=UUID=\$LUKS_UUID_FROM_FILE:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw
EOL

if [[ ! -f "/boot/efi/loader/entries/arch.conf" ]]; then
    echo -e "\033[0;31m[ERROR]\033[0m Failed to create bootloader entry file."
    exit 1
fi
echo "[CHROOT] Bootloader entries created successfully."

# --- User and Password Setup ---
echo "[CHROOT] Creating user and setting passwords..."
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "Set password for user '$USERNAME':"; while ! passwd "$USERNAME"; do echo "Try again."; done
echo "Set password for root user:"; while ! passwd root; do echo "Try again."; done
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

# --- Swapfile Configuration ---
echo "[CHROOT] Configuring swapfile..."
truncate -s 0 /swap/swapfile
chattr +C /swap/swapfile
btrfs property set /swap/swapfile compression none
fallocate -l 4G /swap/swapfile
chmod 0600 /swap/swapfile
mkswap /swap/swapfile

# Verify swapfile creation before adding to fstab
if blkid -p /swap/swapfile | grep -q 'TYPE="swap"'; then
    echo "/swap/swapfile none swap defaults 0 0" >> /etc/fstab
    echo "[CHROOT] Swapfile configured and added to fstab."
else
    echo -e "\033[1;33m[WARN]\033[0m Swapfile creation failed. Continuing without swap."
fi

# --- Snapper and Services ---
echo "[CHROOT] Configuring Snapper and enabling services..."
# Configure snapper first, then enable its services
snapper -c root create-config /
chmod 750 /.snapshots
systemctl enable NetworkManager
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

# --- Secure Boot Setup ---
echo "[CHROOT] Setting up Secure Boot..."
if sbctl create-keys; then
    echo "[CHROOT] Secure Boot keys created. Enrolling and signing..."
    sbctl enroll-keys -m --microsoft

    echo "[CHROOT] Signing all boot files..."
    sbctl sign -s /boot/efi/EFI/systemd/systemd-bootx64.efi
    sbctl sign -s /boot/efi/EFI/BOOT/BOOTX64.EFI
    /usr/bin/find /boot -maxdepth 1 -name 'vmlinuz-*' -exec /usr/bin/sbctl sign -s {} \;
    /usr/bin/find /boot -maxdepth 1 -name 'initramfs-*.img' -exec /usr/bin/sbctl sign -s {} \;

    mkdir -p /etc/pacman.d/hooks
    cat > /etc/pacman.d/hooks/999-secureboot.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = linux-lts
Target = linux-zen

[Action]
Description = Signing kernel and initramfs for Secure Boot
When = PostTransaction
Exec = /bin/bash -c "/usr/bin/find /boot -maxdepth 1 -name 'vmlinuz-*' -exec /usr/bin/sbctl sign -s {} \; && /usr/bin/find /boot -maxdepth 1 -name 'initramfs-*.img' -exec /usr/bin/sbctl sign -s {} \;"
Depends = sbctl
HOOK

    echo "[CHROOT] Secure boot setup complete."
    sbctl list-files
else
    echo -e "\033[1;33m[WARN]\033[0m Failed to create Secure Boot keys. Continuing without Secure Boot."
fi

# --- Post-Install Verification Script ---
cat > "/home/$USERNAME/post-install-check.sh" <<'VERIFY'
#!/bin/bash
echo "--- Post-Installation Verification ---"
echo ""
echo "1. Checking Network Connectivity..."
if ping -c 1 archlinux.org &>/dev/null; then
    echo "  [OK] Network is up."
else
    echo "  [FAIL] Network is down. Check 'ip a' and 'systemctl status NetworkManager'."
fi
echo ""
echo "2. Checking Snapper Status..."
if sudo snapper list-configs | grep -q "root"; then
    echo "  [OK] Snapper config 'root' exists."
    sudo snapper -c root list
else
    echo "  [FAIL] Snapper config not found."
fi
echo ""
echo "3. Checking Secure Boot Status..."
if bootctl status | grep -q "Secure Boot: enabled"; then
    echo "  [OK] Secure Boot is enabled."
    sudo sbctl status
else
    echo "  [WARN] Secure Boot is disabled or status could not be determined."
fi
echo ""
echo "--- Verification Complete ---"
VERIFY
chmod +x "/home/$USERNAME/post-install-check.sh"

EOF

# --- FINALIZATION ---
log "Unmounting filesystems..."
umount -R /mnt
cryptsetup close cryptroot

log "Installation complete!"
log "System is configured with LUKS, Btrfs, Snapper, and Secure Boot."
log "After reboot, log in as '$USERNAME' and run './post-install-check.sh' to verify the setup."
warn "Make sure to backup your LUKS passphrase!"

echo "Press Enter to reboot..."
read
reboot
