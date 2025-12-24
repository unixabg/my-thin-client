\
#!/usr/bin/env bash
# Flavor: debian
# This file is sourced by bin/mkSquashfs.
# Put only settings + package lists here (no commands).

MTC_ARCH="amd64"
MTC_SUITE="trixie"
MTC_MIRROR="http://deb.debian.org/debian"
MTC_BUILDS_DIR="/mnt/data/temp/mtc-builds"
MTC_SQUASHFS_COMP="lz4"
MTC_RAMDISK_SIZE=""   # e.g. "6G" to build rootfs on tmpfs

# Set to 1 to drop into an interactive chroot shell and PAUSE the build until you exit.
CHROOT_SHELL=0

# Packages installed inside the chroot (after apt-get update).
PACKAGES=(
  ca-certificates
  curl
  vim-tiny
  linux-image-amd64
  initramfs-tools
  sudo
  openssl
  live-boot
  initramfs-tools
  squashfs-tools
  cryptsetup
  cryptsetup-initramfs
  busybox
  console-setup

  # Display manager (lightweight)
  xserver-xorg
  lightdm
  lightdm-gtk-greeter

  # XFCE desktop (core + goodies)
  xfce4
  xfce4-goodies
  chromium

  # Terminal + file manager helpers
  xfce4-terminal
  thunar-archive-plugin
  thunar-media-tags-plugin

  # Audio
  pipewire
  pipewire-audio
  wireplumber
  pavucontrol

  # Networking
  network-manager
  network-manager-gnome

  # Wi-Fi support
  firmware-linux
  firmware-linux-nonfree
  firmware-iwlwifi
  firmware-realtek
  firmware-atheros
  firmware-brcm80211
  iw
  wireless-tools
  wpasupplicant
  dbus

  # Utilities
  gvfs
  gvfs-backends
  udisks2
  polkitd
  pkexec

  # Fonts
  fonts-dejavu
  fonts-liberation
)

# --- Accounts -------------------------------------------------

# Root password (leave empty to keep root locked)
ROOT_PASSWORD="rootpass"

# Create an MTC user
MTC_USER="mtc"
MTC_PASSWORD="mtcpass"
MTC_UID=""          # optional (empty = auto)
MTC_SHELL="/bin/bash"
MTC_GROUPS="sudo"   # comma-separated, e.g. "sudo,adm"

# Whether to allow passwordless sudo (0 or 1)
MTC_SUDO_NOPASSWD=0

