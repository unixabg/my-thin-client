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

```bash
sudo ./bin/mtc debian

## Install (UEFI)

⚠️ This will erase the target disk.

```bash
sudo bash bin/mtc_installer \
  --target /dev/mmcblk0 \
  --build ./output \
  --yes

