\
#!/usr/bin/env bash
set -euo pipefail

mtc_ts() { date '+%F %T'; }
mtc_log() { printf '[%s] %s\n' "$(mtc_ts)" "$*"; }
mtc_die() { mtc_log "ERROR: $*"; exit 1; }

mtc_require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    mtc_die "Run as root (or with sudo)."
  fi
}

mtc_mountpoint() { mountpoint -q "$1"; }

# Safe unmount: works even if not mounted.
mtc_umount() {
  local p="$1"
  if mtc_mountpoint "$p"; then
    umount -lf "$p" || true
  fi
}
