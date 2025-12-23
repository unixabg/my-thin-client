\
#!/usr/bin/env bash
set -euo pipefail

# Uses: MTC_WORK_DIR

mtc_teardown_mounts() {
  local root="${MTC_WORK_DIR}/squashfs"
  # order matters: deepest first
  mtc_umount "${root}/proc"
  mtc_umount "${root}/sys"
  mtc_umount "${root}/dev"
  mtc_umount "${MTC_WORK_DIR}/squashfs"  # tmpfs, if used
}

mtc_cleanup_workdir() {
  mtc_teardown_mounts || true
  if [[ -n "${MTC_WORK_DIR:-}" && "${MTC_WORK_DIR}" != "/" && -d "${MTC_WORK_DIR}" ]]; then
    rm -rf "${MTC_WORK_DIR}"
  fi
}
