#!/bin/bash
## kola:
##   # additionalDisks is only supported on qemu.
##   platforms: qemu
##   # Root reprovisioning requires at least 4GiB of memory.
##   minMemory: 4096
##   # Linear RAID is setup on these disks.
##   additionalDisks: ["5G", "5G"]
##   # This test includes a lot of disk I/O and needs a higher
##   # timeout value than the default.
##   timeoutMin: 15
##   # This test reprovisions the rootfs.
##   tags: reprovision
##   description: Verify the root reprovision with RAID 1 works.

set -xeuo pipefail

# shellcheck disable=SC1091
. "$KOLA_EXT_DATA/commonlib.sh"

srcdev=$(findmnt -nvr /sysroot -o SOURCE)
[[ ${srcdev} == $(realpath /dev/md/foobar) ]]

blktype=$(lsblk -o TYPE "${srcdev}" --noheadings)
[[ ${blktype} == raid1 ]]

fstype=$(findmnt -nvr /sysroot -o FSTYPE)
[[ ${fstype} == xfs ]]
ok "source is XFS on RAID1 device"

rootflags=$(findmnt /sysroot -no OPTIONS)
if ! grep prjquota <<< "${rootflags}"; then
    fatal "missing prjquota in root mount flags: ${rootflags}"
fi
ok "root mounted with prjquota"

case "${AUTOPKGTEST_REBOOT_MARK:-}" in
  "")
      # check that ignition-ostree-growfs didn't run
      if [ -e /run/ignition-ostree-growfs.stamp ]; then
          fatal "ignition-ostree-growfs ran"
      fi

      # check that autosave-xfs didn't run
      if [ -e /run/ignition-ostree-autosaved-xfs.stamp ]; then
          fatal "unexpected autosaved XFS"
      fi

      # reboot once to sanity-check we can find root on second boot
      /tmp/autopkgtest-reboot rebooted
      ;;

  rebooted)
      grep root=UUID= /proc/cmdline
      grep rd.md.uuid= /proc/cmdline
      ok "found root kargs"

      # Test bare soft-reboot on RAID1. This validates that
      # DefaultDependencies=no on var.mount and the sysroot.mount drop-in
      # work correctly when the root filesystem is on an mdraid device.
      # See https://github.com/ostreedev/ostree/pull/3571
      echo "Testing bare soft-reboot on RAID1 root..."
      /tmp/autopkgtest-soft-reboot-prepare "soft-rebooted"
      systemctl soft-reboot
      ;;

  soft-rebooted)
      # After soft-reboot on RAID1, verify critical mounts survived
      echo "Verifying post-soft-reboot state on RAID1..."

      # /var must be mounted and writable
      mountpoint /var
      touch /var/tmp/soft-reboot-raid-test && rm /var/tmp/soft-reboot-raid-test
      ok "/var mounted and writable after soft-reboot"

      # /sysroot must still be mounted
      mountpoint /sysroot
      ok "/sysroot mounted after soft-reboot"

      # /boot must still be mounted
      mountpoint /boot
      ok "/boot mounted after soft-reboot"

      # Root should still be on RAID1
      srcdev=$(findmnt -nvr /sysroot -o SOURCE)
      [[ ${srcdev} == $(realpath /dev/md/foobar) ]]
      ok "root still on RAID1 after soft-reboot"

      # ostree commands should work
      ostree admin status
      ok "ostree admin status works after soft-reboot"
      ;;
  *) fatal "unexpected mark: ${AUTOPKGTEST_REBOOT_MARK}";;
esac
