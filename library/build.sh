\
#!/usr/bin/env bash
set -euo pipefail

# Expects:
#   CFG_DIR, CFG_NAME
#   MTC_ARCH, MTC_SUITE, MTC_MIRROR, MTC_BUILDS_DIR, MTC_SQUASHFS_COMP, MTC_RAMDISK_SIZE
#   PACKAGES (bash array)
#   CHROOT_SHELL (0/1)

mtc_host_arch() {
  # normalize uname -m to debian arch-ish values
  local u
  u="$(uname -m)"
  case "$u" in
    x86_64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    armv7l|armv7*) echo armhf ;;
    i386|i686) echo i386 ;;
    *) echo "$u" ;;
  esac
}

mtc_prepare_dirs() {
  mkdir -p "${MTC_WORK_DIR}/output" "${MTC_WORK_DIR}/squashfs"
}

mtc_maybe_mount_tmpfs() {
  if [[ -n "${MTC_RAMDISK_SIZE:-}" ]]; then
    mtc_log "Mounting tmpfs (${MTC_RAMDISK_SIZE}) at ${MTC_WORK_DIR}/squashfs"
    mount -t tmpfs -o "size=${MTC_RAMDISK_SIZE}" tmpfs "${MTC_WORK_DIR}/squashfs"
  fi
}

mtc_write_sources_list() {
  # Debian-style defaults; flavors can override by providing their own /etc/apt/sources.list in chroot overlay.
  local root="${MTC_WORK_DIR}/squashfs"
  if [[ -f "${root}/etc/apt/sources.list" ]]; then
    mtc_log "sources.list already provided by overlay; leaving as-is."
    return 0
  fi
  mkdir -p "${root}/etc/apt"
  cat > "${root}/etc/apt/sources.list" <<EOF
deb ${MTC_MIRROR} ${MTC_SUITE} main contrib non-free non-free-firmware
deb ${MTC_MIRROR} ${MTC_SUITE}-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${MTC_SUITE}-security main contrib non-free non-free-firmware
EOF
}

mtc_debootstrap() {
  local root="${MTC_WORK_DIR}/squashfs"
  local host_arch
  host_arch="$(mtc_host_arch)"

  mtc_log "Running debootstrap: suite=${MTC_SUITE} arch=${MTC_ARCH} mirror=${MTC_MIRROR}"
  if [[ "${MTC_ARCH}" == "${host_arch}" ]]; then
    debootstrap --arch="${MTC_ARCH}" "${MTC_SUITE}" "${root}" "${MTC_MIRROR}"
  else
    # foreign bootstrap
    debootstrap --arch="${MTC_ARCH}" --foreign "${MTC_SUITE}" "${root}" "${MTC_MIRROR}"
    # copy qemu for second stage
    if command -v qemu-"${MTC_ARCH}"-static >/dev/null 2>&1; then
      cp "$(command -v qemu-"${MTC_ARCH}"-static)" "${root}/usr/bin/" || true
    elif command -v qemu-aarch64-static >/dev/null 2>&1 && [[ "${MTC_ARCH}" == "arm64" ]]; then
      cp "$(command -v qemu-aarch64-static)" "${root}/usr/bin/" || true
    else
      mtc_die "Foreign arch bootstrap requires qemu-user-static for ${MTC_ARCH}."
    fi
    mtc_chroot_mounts
    chroot "${root}" /debootstrap/debootstrap --second-stage
    mtc_chroot_umounts
  fi
}

mtc_rsync_chroot_overlay() {
  local src="${CFG_DIR}/chroot"
  local dst="${MTC_WORK_DIR}/squashfs"
  if [[ -d "${src}" ]]; then
    mtc_log "Applying chroot overlay: ${src} -> ${dst}"
    rsync -a "${src}/" "${dst}/"
  fi
}

mtc_rsync_output_overlay() {
  local src="${CFG_DIR}/output"
  local dst="${MTC_WORK_DIR}/output"
  if [[ -d "${src}" ]]; then
    mtc_log "Applying output overlay: ${src} -> ${dst}"
    rsync -a "${src}/" "${dst}/"
  fi
}

mtc_chroot_mounts() {
  local root="${MTC_WORK_DIR}/squashfs"
  mkdir -p "${root}/proc" "${root}/sys" "${root}/dev"
  mtc_mountpoint "${root}/proc" || mount -t proc proc "${root}/proc"
  mtc_mountpoint "${root}/sys"  || mount --bind /sys "${root}/sys"
  mtc_mountpoint "${root}/dev"  || mount --bind /dev "${root}/dev"
}

mtc_chroot_umounts() {
  local root="${MTC_WORK_DIR}/squashfs"
  mtc_umount "${root}/dev"
  mtc_umount "${root}/sys"
  mtc_umount "${root}/proc"
}

mtc_drop_to_chroot_shell_if_enabled() {
  [[ "${CHROOT_SHELL:-0}" -eq 1 ]] || return 0
  local root="${MTC_WORK_DIR}/squashfs"
  mtc_log "Dropping into chroot shell. Exit to resume build."
  mtc_chroot_mounts
  if [[ -x "${root}/bin/bash" ]]; then
    chroot "${root}" /bin/bash -l
  else
    chroot "${root}" /bin/sh -l
  fi
  mtc_log "Chroot shell exited; resuming."
  mtc_chroot_umounts
}

mtc_chroot_provision() {
  local root="${MTC_WORK_DIR}/squashfs"
  mtc_log "Provisioning inside chroot (apt-get update/install)"
  mtc_chroot_mounts

  # noninteractive defaults
  chroot "${root}" /usr/bin/env bash -lc 'export DEBIAN_FRONTEND=noninteractive; true'

  # apt-get update
  chroot "${root}" /usr/bin/env bash -lc 'export DEBIAN_FRONTEND=noninteractive; apt-get update'

  if declare -p PACKAGES >/dev/null 2>&1; then
    # write packages into file to avoid quoting issues
    local pkgfile="${root}/tmp/mtc.packages"
    mkdir -p "${root}/tmp"
    : > "${pkgfile}"
    for p in "${PACKAGES[@]}"; do
      [[ -n "${p}" ]] && printf '%s\n' "${p}" >> "${pkgfile}"
    done
    chroot "${root}" /usr/bin/env bash -lc 'export DEBIAN_FRONTEND=noninteractive; mapfile -t pkgs < /tmp/mtc.packages; if (( ${#pkgs[@]} )); then apt-get install -y --no-install-recommends "${pkgs[@]}"; fi'
    rm -f "${pkgfile}"
  fi

  # Ensure initrd includes newly-installed hooks (live-boot, cryptsetup-initramfs, etc.)
  mtc_log "Regenerating initramfs inside chroot"
  chroot "${root}" /usr/bin/env bash -lc 'update-initramfs -u'

  # optional user-provided setup script inside rootfs overlay
  if [[ -x "${root}/tmp/mtc/setup.sh" ]]; then
    mtc_log "Running /tmp/mtc/setup.sh inside chroot"
    chroot "${root}" /usr/bin/env bash -lc 'export DEBIAN_FRONTEND=noninteractive; /tmp/mtc/setup.sh'
  fi

  # cleanup apt caches
  chroot "${root}" /usr/bin/env bash -lc 'apt-get clean; rm -rf /var/lib/apt/lists/* || true'

  mtc_chroot_umounts
}

mtc_configure_accounts() {
  local root="$MTC_WORK_DIR/squashfs"

  mtc_log "Configuring accounts (root + ${MTC_USER:-})"

  # Ensure tools exist (openssl provides sha-512 hashing)
  chroot "$root" apt-get install -y sudo openssl >/dev/null

  # Set root password if provided
  if [[ -n "${ROOT_PASSWORD:-}" ]]; then
    chroot "$root" usermod \
      --password "$(chroot "$root" openssl passwd -6 "$ROOT_PASSWORD")" \
      root
  fi

  # Create/update mtc user if configured
  if [[ -n "${MTC_USER:-}" ]]; then
    if ! chroot "$root" id "$MTC_USER" >/dev/null 2>&1; then
      chroot "$root" useradd -m -s /bin/bash "$MTC_USER"
    fi

    if [[ -n "${MTC_PASSWORD:-}" ]]; then
      chroot "$root" usermod \
        --password "$(chroot "$root" openssl passwd -6 "$MTC_PASSWORD")" \
        "$MTC_USER"
    fi

    if [[ -n "${MTC_GROUPS:-}" ]]; then
      chroot "$root" usermod -aG "$MTC_GROUPS" "$MTC_USER"
    fi

    if [[ "${MTC_SUDO_NOPASSWD:-0}" -eq 1 ]]; then
      cat > "$root/etc/sudoers.d/90-mtc" <<EOF
$MTC_USER ALL=(ALL) NOPASSWD:ALL
EOF
      chmod 0440 "$root/etc/sudoers.d/90-mtc"
    fi
  fi
}

mtc_extract_boot_artifacts() {
  local root="${MTC_WORK_DIR}/squashfs"
  local out="${MTC_WORK_DIR}/output"
  local k i

  k="$(ls -1 "${root}"/boot/vmlinuz-* 2>/dev/null | head -n1 || true)"
  [[ -z "${k}" && -e "${root}/vmlinuz" ]] && k="${root}/vmlinuz"
  if [[ -n "${k}" ]]; then
    cp -f "${k}" "${out}/vmlinuz"
  else
    mtc_log "No kernel found to extract (install linux-image-* if you need vmlinuz)."
  fi

  i="$(ls -1 "${root}"/boot/initrd.img-* 2>/dev/null | head -n1 || true)"
  [[ -z "${i}" && -e "${root}/initrd.img" ]] && i="${root}/initrd.img"
  if [[ -n "${i}" ]]; then
    cp -f "${i}" "${out}/initrd"
  else
    mtc_log "No initrd found to extract."
  fi
}

mtc_squashfs_cleanup_rootfs() {
  local root="${MTC_WORK_DIR}/squashfs"
  rm -rf "${root}/tmp/"* "${root}/var/log/"* "${root}/var/cache/apt/"* "${root}/usr/share/doc/"* 2>/dev/null || true
}

mtc_make_squashfs() {
  local root="${MTC_WORK_DIR}/squashfs"
  local out="${MTC_WORK_DIR}/output/filesystem.squashfs"
  mtc_log "Building SquashFS: ${out} (comp=${MTC_SQUASHFS_COMP})"
  mksquashfs "${root}" "${out}" -noappend -comp "${MTC_SQUASHFS_COMP}"
}

mtc_build_all() {
  mtc_prepare_dirs
  mtc_maybe_mount_tmpfs
  mtc_debootstrap
  mtc_write_sources_list
  mtc_rsync_chroot_overlay
  mtc_drop_to_chroot_shell_if_enabled
  mtc_chroot_provision
  mtc_configure_accounts
  mtc_extract_boot_artifacts
  mtc_squashfs_cleanup_rootfs
  mtc_make_squashfs
  mtc_rsync_output_overlay
  chmod -R a+rX "${MTC_WORK_DIR}/output" || true
  mtc_log "Artifacts in: ${MTC_WORK_DIR}/output"
}
