# my-thin-client

A minimal, reproducible Linux thin-client image builder and installer.

## Features

- Debian-based rootfs built via debootstrap
- SquashFS-based immutable filesystem
- UEFI-only boot (x86_64)
- Deterministic rebuilds
- Interactive chroot breakpoint (optional)
- Simple disk installer (`mtc_installer`)

## Layout

- `bin/` – entrypoints
- `library/` – shell logic
- `config/<flavor>/` – declarative build configuration

## Build

Builds are driven by a flavor config:

- `config/<flavor>/config.sh`
- `config/<flavor>/chroot/`   (rsync into rootfs BEFORE chroot runs)
- `config/<flavor>/output/`   (rsync into output AFTER filesystem.squashfs is built)

```bash
sudo ./bin/mtc debian
```

## Install (UEFI)

⚠️ This will erase the target disk.

```bash
sudo bash bin/mtc_installer \
  --target /dev/mmcblk0 \
  --build ./output \
  --yes
```

## Config Variables

The build is split into two stages (controlled by variables in config/<flavor>/config.sh):

### Full build

MTC_BUILD_CHROOT=1
MTC_BUILD_OUTPUT=1

### Only rebuild output artifacts from an existing chroot
MTC_BUILD_CHROOT=0
MTC_BUILD_OUTPUT=1

#### Only (re)build the chroot (no squashfs/output)
MTC_BUILD_CHROOT=1
MTC_BUILD_OUTPUT=0

### Remote unlock
```bash
# generate a key
ssh-keygen -t ed25519 -f ./mtc-remote-unlock-key -C "mtc remote unlock"

# variables in confid/<flavor>/config.sh
# Set to 1 to enable dropbear remote unlock
MTC_REMOTE_UNLOCK=0
MTC_DROPBEAR_PORT=2222
MTC_AUTHORIZED_KEYS_FILE="${HOME}/mtc-remote-unlock-key.pub"
