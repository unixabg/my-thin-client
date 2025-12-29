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

mtc_setup_logging() {
  [[ "${MTC_LOGGING_SETUP:-0}" -eq 1 ]] && return 0
  : "${MTC_WORK_DIR:?MTC_WORK_DIR not set}"
  mkdir -p "$MTC_WORK_DIR"
  local log_file="${MTC_WORK_DIR}/build.log"
  export MTC_LOGGING_SETUP=1
  exec > >(tee -a "$log_file") 2>&1
}

mtc_mountpoint() { mountpoint -q "$1"; }

# Safe unmount: works even if not mounted.
mtc_umount() {
  local p="$1"
  if mtc_mountpoint "$p"; then
    umount -lf "$p" || true
  fi
}
