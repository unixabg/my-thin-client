# my-thin-client

A minimal, reproducible Linux thin-client image builder and installer.

This project builds a Debian-based immutable (SquashFS) system with optional
persistence and optional LUKS encryption, designed for UEFI systems and
headless / remote deployments.

---

## Features

- Debian-based root filesystem (debootstrap)
- SquashFS immutable root
- Optional persistence overlay
- Optional LUKS encryption for persistence
- UEFI boot (x86_64)
- Deterministic rebuilds
- Simple disk installer
- Optional SSH remote unlock in initramfs (dropbear)

---

## Repository layout

```
bin/        entrypoints (mtc, mtc_installer)
library/    shared build logic
config/     flavor definitions
```

Each flavor lives in:

```
config/<flavor>/
  ├── config.sh
  ├── chroot/   (rsynced into rootfs before provisioning)
  └── output/   (rsynced into output after squashfs is built)
```

---

## Building images (`bin/mtc`)

### Basic build

```bash
sudo ./bin/mtc debian
```

This produces artifacts under the build output directory:

```
filesystem.squashfs
vmlinuz
initrd
```

Build logs are written to:

```
${MTC_WORK_DIR}/build.log
```

---

## Build stages

The build is split into two stages, controlled from
`config/<flavor>/config.sh`.

### Stage variables

```bash
MTC_BUILD_CHROOT=1
MTC_BUILD_OUTPUT=1
```

### Common workflows

```bash
# full rebuild
MTC_BUILD_CHROOT=1
MTC_BUILD_OUTPUT=1

# reuse existing chroot, rebuild squashfs + output only
MTC_BUILD_CHROOT=0
MTC_BUILD_OUTPUT=1

# rebuild chroot only
MTC_BUILD_CHROOT=1
MTC_BUILD_OUTPUT=0
```

---

## Remote unlock (dropbear-initramfs)

The initrd can optionally include dropbear so you can SSH in during early boot
and unlock an encrypted persistence volume remotely.

This is intended for **persistence + LUKS** installs.

### 1) Generate an SSH key for remote unlock

Generate a dedicated keypair:

```bash
ssh-keygen -t ed25519 -f ./mtc-remote-unlock-key -C "mtc remote unlock"
```

Files created:

- `mtc-remote-unlock-key`     (private key)
- `mtc-remote-unlock-key.pub` (public key)

The `.pub` file is a valid `authorized_keys` entry.

---

### 2) Enable remote unlock in the flavor config

Edit `config/<flavor>/config.sh`:

```bash
MTC_REMOTE_UNLOCK=1
MTC_DROPBEAR_PORT=2222
MTC_AUTHORIZED_KEYS_FILE="./mtc-remote-unlock-key.pub"
```

Notes:

- Dropbear host keys are regenerated on every build
- Build fails if `MTC_REMOTE_UNLOCK=1` and the key file is missing

---

### 3) Build the image

```bash
sudo ./bin/mtc debian
```

---

## Installer (`bin/mtc_installer`)

The installer writes the built artifacts to a target disk using GPT + UEFI.

⚠️ WARNING: The target disk will be erased.

### Basic usage

```bash
sudo bash bin/mtc_installer \
  --mode persistence \
  --target /dev/mmcblk0 \
  --build ./output \
  --persistence-luks \
  --yes
```

### Installer modes

- `stateless`   – immutable root, no persistence
- `persistence` – immutable root with writable overlay
- `mutable`     – traditional writable root filesystem

### Persistence + LUKS

When `--persistence-luks` is used:
- The persistence partition is encrypted with LUKS
- live-boot handles unlock during initramfs
- `/etc/crypttab` is intentionally not used

---

## Remote unlock at boot

When booting a persistence + LUKS install with remote unlock enabled:

### 1) SSH into initramfs

```bash
ssh -i ./mtc-remote-unlock-key -p 2222 root@IP
```

### 2) Provide the passphrase

```sh
# send passphrase (no trailing newline)
echo -n "YOUR_LUKS_PASSPHRASE" > /lib/cryptsetup/passfifo
```

Boot will continue automatically.

⚠️ Limitation:
- Remote unlock is effectively **single-attempt**
- If the passphrase is wrong, retry happens on the physical console (tty0)
- Reboot is required to retry remotely

---

## Summary

- `bin/mtc` builds images
- `bin/mtc_installer` installs them to disk
- Persistence + LUKS is handled by live-boot
- Remote unlock works via SSH + `/lib/cryptsetup/passfifo`
- `/etc/crypttab` is not used in live installs
