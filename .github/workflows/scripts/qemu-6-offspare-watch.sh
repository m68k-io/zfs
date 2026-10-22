#!/usr/bin/env bash
# DEBUG: while zpool_offline_spare loops, save the resilver_txg reset
# counters and "DEBUG reset" dbgmsg lines every minute, and on a ZFS
# assertion save dmesg and the debug log and stop test-runner: the
# panicking thread never returns, so every later pass would only hang.
# At $DEBUG_DEADLINE stop test-runner too.
save() {
  for f in /sys/module/zfs/parameters/zfs_vdev_debug_*; do
    echo "$(basename $f) $(cat $f)"
  done > /var/tmp/debug-counters.txt 2>&1
  { cat /var/tmp/debug-reset.txt 2>/dev/null
    sudo grep 'DEBUG reset' /proc/spl/kstat/zfs/dbgmsg 2>/dev/null
  } | sort -u > /var/tmp/debug-reset.new
  mv /var/tmp/debug-reset.new /var/tmp/debug-reset.txt
}
while sleep 20; do
  save
  if sudo dmesg | grep -qE 'PANIC at|VERIFY'; then
    { date -u; sudo dmesg | tail -200
      echo "=== dbgmsg"; sudo tail -2000 /proc/spl/kstat/zfs/dbgmsg
    } > /var/tmp/watchdog-panic.txt 2>&1
    sudo pkill -f '/test-runne[r]\.py' || true
    save
    exit 0
  fi
  if [ "$(date +%s)" -ge "$DEBUG_DEADLINE" ]; then
    date -u > /var/tmp/deadline-reached.txt
    sudo pkill -f '/test-runne[r]\.py' || true
    save
    exit 0
  fi
done
